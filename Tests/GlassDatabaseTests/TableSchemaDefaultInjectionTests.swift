//
//  TableSchemaDefaultInjectionTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  `ALTER TABLE … SET DEFAULT <expr>` is **one statement**, which is why neither protocol-level
//  protection helps here: mysql-nio omits `CLIENT_MULTI_STATEMENTS` and PostgresNIO's extended
//  protocol refuses multi-statement strings. A **comma** needs neither — `0, DROP COLUMN secret`
//  stays a single `ALTER TABLE` with a second clause bolted on.
//
//  Two ways in, found by the 2026-09-13 security review:
//
//  1. **The operator's literal.** `literalExpression` guarded a numeric default with
//     `Decimal(string:) != nil` and then emitted the ORIGINAL string. `Decimal(string:)` parses a
//     *prefix*: it answers `0` for `"0, DROP COLUMN secret"`, `1` for `"1; DROP TABLE t --"` and
//     `0` for `"0 OR 1=1"` and `"0x41"` — all measured, not assumed.
//  2. **The server's own metadata**, which is the more serious of the two because the attacker is
//     not the operator. `existingDefaultExpression` returned three shapes verbatim, and the value
//     is `INFORMATION_SCHEMA.COLUMNS.COLUMN_DEFAULT` copied straight from the server
//     (`MySQLAdapter.swift:624`). Anyone with DDL rights on a table the operator later opens picks
//     that string. The route is ordinary: `beginEditing` sets the default behaviour to **Keep
//     Current**, so it is reached by opening the column editor and applying any change at all.
//
//  `validatedType` has refused a top-level comma in column *types* since it was written. Default
//  expressions were simply never given the same rule. These tests pin that they now are.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

@Suite("Column defaults cannot escape their clause")
struct TableSchemaDefaultInjectionTests {
    private func column(_ name: String = "c", type: String = "int",
                        default defaultValue: String? = nil) -> ColumnInfo {
        ColumnInfo(name: name, type: type, isNullable: false, isPrimaryKey: false,
                   defaultValue: defaultValue)
    }

    /// `original` is built non-nullable and the alter asks for nullable, so there is always a real
    /// change to emit — otherwise the builder refuses with "Change at least one column setting"
    /// and a test could pass without ever reaching the default expression at all.
    private func alter(_ dialect: DatabaseDialect, mode: TableColumnDefaultMode,
                       literal: String = "", original: ColumnInfo, type: String = "int") throws -> [String] {
        try TableSchemaSQL.alterColumn(
            database: "d", table: "t", original: original, name: original.name, type: type,
            nullable: true, unsigned: false, defaultMode: mode, defaultLiteral: literal,
            dialect: dialect, quoteCharacter: dialect == .mysql ? "`" : "\"")
    }

    // MARK: - The operator's literal

    /// The exact strings `Decimal(string:)` accepts as a prefix. Each must now be refused outright.
    @Test("A numeric default must be the whole number, not a prefix of one")
    func numericDefaultsRejectTrailingText() {
        let poisoned = [
            "0, DROP COLUMN secret",
            "1; DROP TABLE t --",
            "0 OR 1=1",
            "0x41",
            "-- x",
            "1 UNION SELECT 1",
        ]
        for literal in poisoned {
            for dialect in [DatabaseDialect.mysql, .postgresql] {
                #expect(throws: (any Error).self,
                        "‘\(literal)’ reached \(dialect) DDL as a numeric default") {
                    try alter(dialect, mode: .literal, literal: literal, original: column())
                }
            }
        }
    }

    /// And the ordinary numbers still work, or the guard has simply broken the feature.
    @Test("Real numbers are still accepted")
    func ordinaryNumbersStillWork() throws {
        for literal in ["0", "42", "-7", "+7", "3.14", "-0.5", "1e6", "2.5E-3"] {
            let sql = try alter(.mysql, mode: .literal, literal: literal, original: column())
            #expect(sql.joined().contains(literal), "‘\(literal)’ should survive as a default")
        }
    }

    /// A non-numeric column quotes its literal, so a comma there is data and must stay allowed.
    @Test("A text default may contain a comma, because it is quoted")
    func textDefaultsMayContainCommas() throws {
        let sql = try alter(.mysql, mode: .literal, literal: "a, b",
                            original: column(type: "varchar(20)"), type: "varchar(20)")
        #expect(sql.joined().contains("'a, b'"), "quoted, so the comma is data")
    }

    /// The quote-doubling that makes the above safe.
    @Test("A quote inside a text default is doubled, not passed through")
    func textDefaultsEscapeQuotes() throws {
        let sql = try alter(.mysql, mode: .literal, literal: "O'Brien', DROP COLUMN secret --",
                            original: column(type: "varchar(40)"), type: "varchar(40)")
        let joined = sql.joined()
        #expect(joined.contains("''"), "the embedded quote is doubled")
        #expect(joined.contains(#"DEFAULT 'O''Brien'', DROP COLUMN secret --'"#), "the clause cannot be reopened: \(joined)")
    }

    /// MySQL reads a backslash in a literal as an escape (unless NO_BACKSLASH_ESCAPES, off by
    /// default): with quotes doubled alone, `x\'` ended its own literal there (2026-10-24, the test
    /// audit — this file's check above has a space that never matches, so it couldn't see it).
    @Test("A backslash in a MySQL text default is doubled, and can't end the literal; PostgreSQL's is kept")
    func textDefaultsEscapeBackslashes() throws {
        let typed = "x\\', DROP COLUMN secret #"
        let mysql = try alter(.mysql, mode: .literal, literal: typed,
                              original: column(type: "varchar(40)"), type: "varchar(40)").joined()
        #expect(mysql.contains(#"DEFAULT 'x\\'', DROP COLUMN secret #'"#), "\(mysql)")
        let postgres = try alter(.postgresql, mode: .literal, literal: typed,
                                 original: column(type: "varchar(40)"), type: "varchar(40)").joined()
        #expect(postgres.contains(#"SET DEFAULT 'x\'', DROP COLUMN secret #'"#), "a backslash is itself there: \(postgres)")
    }

    // MARK: - The server's metadata, which the operator does not choose

    /// A text default the server reports, carried by Keep Current: a backslash in it went back as an
    /// escape — `a\b` became `a`, backspace — and a hostile one ended the literal (2026-10-24).
    @Test("A server's text default with a backslash goes back as the same text")
    func serverTextDefaultsKeepTheirBackslashes() throws {
        let kept = try alter(.mysql, mode: .keep, original: column(type: "varchar(40)", default: #"a\b"#),
                             type: "varchar(40)").joined()
        #expect(kept.contains(#"DEFAULT 'a\\b'"#), "\(kept)")
        let hostile = try alter(.mysql, mode: .keep, original: column(type: "varchar(40)", default: #"x\', DROP COLUMN secret #"#),
                                type: "varchar(40)").joined()
        #expect(hostile.contains(#"DEFAULT 'x\\'', DROP COLUMN secret #'"#), "\(hostile)")
    }

    /// `Keep Current` carries the server's string into the new DDL. A hostile one must be refused.
    @Test("A hostile server default is refused when it is carried forward")
    func serverSuppliedDefaultsAreValidated() {
        let hostile = [
            // Matches the CURRENT_TIMESTAMP prefix test on a temporal column.
            ("timestamp", "CURRENT_TIMESTAMP, DROP COLUMN secret"),
            // Starts with "(" and ends with ")", so it passed as a functional default.
            ("int", "(1), DROP COLUMN secret, ADD pad int DEFAULT (1)"),
            // The numeric prefix route, arriving from the server rather than the operator.
            ("int", "0, DROP COLUMN secret"),
            // Ends its own statement.
            ("int", "0; DROP TABLE t --"),
        ]
        for (type, poisoned) in hostile {
            #expect(throws: (any Error).self,
                    "server default ‘\(poisoned)’ reached the DDL") {
                try alter(.mysql, mode: .keep,
                          original: column(type: type, default: poisoned), type: type)
            }
        }
    }

    /// Legitimate server defaults must still carry forward, or "Keep Current" is broken for
    /// every table that uses one.
    @Test("Ordinary server defaults still carry forward")
    func legitimateServerDefaultsSurvive() throws {
        #expect(throws: Never.self) {
            try alter(.mysql, mode: .keep,
                      original: column(type: "timestamp", default: "CURRENT_TIMESTAMP"),
                      type: "timestamp")
        }
        #expect(throws: Never.self) {
            try alter(.mysql, mode: .keep,
                      original: column(type: "int", default: "(1 + 2)"), type: "int")
        }
        // A functional default whose own arguments contain commas — legal, because they are
        // inside the parentheses.
        #expect(throws: Never.self) {
            try alter(.mysql, mode: .keep,
                      original: column(type: "date", default: "(DATE_ADD(CURRENT_DATE, INTERVAL 1 YEAR))"),
                      type: "date")
        }
    }

    /// The `standard_conforming_strings` divergence, which the scanner resolves in the safe
    /// direction: a backslash is NOT treated as escaping a quote, so the literal is considered to
    /// end where PostgreSQL (and MySQL under `NO_BACKSLASH_ESCAPES`) would end it — and the comma
    /// that follows is then seen at top level and refused.
    @Test("A backslash does not hide a quote, so the comma after it is still caught")
    func backslashDoesNotConcealTheClauseEscape() {
        // MySQL, not PostgreSQL: PG's `.keep` route returns "" and never carries the server's
        // default forward, so it has nothing to validate. The scanner is only reached on MySQL.
        #expect(throws: (any Error).self) {
            try alter(.mysql, mode: .keep,
                      original: column(type: "text", default: "('\\'), DROP COLUMN secret --')"),
                      type: "text")
        }
    }
}
