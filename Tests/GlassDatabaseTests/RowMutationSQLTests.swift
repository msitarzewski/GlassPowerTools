//
//  RowMutationSQLTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  The row-identity predicate and the DELETE built on it.
//
//  These assert the *shape of the SQL*, which is all a unit test can reach: whether a server
//  actually reports one affected row is proven in `LiveDatabaseIntegrationTests` against a real
//  table in `gpt_scratch`. Rule 22 — a green test is not a green feature — so the two halves are
//  written and read together.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

private func column(_ name: String, _ type: String = "int", primaryKey: Bool = false) -> ColumnInfo {
    ColumnInfo(name: name, type: type, isPrimaryKey: primaryKey)
}

private let keyedColumns = [
    column("id", primaryKey: true),
    column("name", "varchar(40)"),
    column("score")
]

@Suite("Row identity predicate")
struct RowIdentityPredicateTests {

    // MARK: The predicate the update paths have always built

    @Test("Every column of the row is constrained, not only the primary key")
    func bindsTheWholeRow() throws {
        let predicate = try RowMutationSQL.identityPredicate(
            columns: keyedColumns,
            row: [.int(7), .string("Ada"), .int(91)],
            identifierQuote: "`",
            dialect: .mysql
        )
        #expect(predicate.sql == "`id` = ? AND `name` = ? AND `score` = ?")
        #expect(predicate.parameters == [.int(7), .string("Ada"), .int(91)])
        #expect(predicate.columnNames == ["id", "name", "score"])
    }

    @Test("A NULL becomes IS NULL and binds nothing — `= NULL` would match no row at all")
    func nullsAreCompared() throws {
        let predicate = try RowMutationSQL.identityPredicate(
            columns: keyedColumns,
            row: [.int(7), .null, .int(91)],
            identifierQuote: "`",
            dialect: .mysql
        )
        #expect(predicate.sql == "`id` = ? AND `name` IS NULL AND `score` = ?")
        #expect(predicate.parameters == [.int(7), .int(91)])
    }

    @Test("PostgreSQL numbers its placeholders, and the offset is where the caller left off")
    func postgresPlaceholdersContinueFromTheCaller() throws {
        // The single-row update binds its SET values first, so the predicate cannot start at $1.
        // Getting this wrong would bind the wrong values to the wrong columns without any error.
        let predicate = try RowMutationSQL.identityPredicate(
            columns: keyedColumns,
            row: [.int(7), .string("Ada"), .null],
            identifierQuote: "\"",
            dialect: .postgresql,
            parameterOffset: 2
        )
        #expect(predicate.sql == "\"id\" = $3 AND \"name\" = $4 AND \"score\" IS NULL")
        #expect(predicate.parameters == [.int(7), .string("Ada")])
    }

    @Test("A table with no primary key is refused rather than identified by value alone")
    func noPrimaryKeyIsRefused() {
        #expect(throws: RowIdentityError.noPrimaryKey) {
            try RowMutationSQL.identityPredicate(
                columns: [column("a"), column("b")],
                row: [.int(1), .int(2)],
                identifierQuote: "`",
                dialect: .mysql
            )
        }
    }

    @Test("A row narrower than the column metadata stops at the row, and does not index past it")
    func shortRowsAreTruncatedNotCrashed() throws {
        let predicate = try RowMutationSQL.identityPredicate(
            columns: keyedColumns,
            row: [.int(7)],
            identifierQuote: "`",
            dialect: .mysql
        )
        #expect(predicate.sql == "`id` = ?")
        #expect(predicate.columnNames == ["id"])
    }

    @Test("A row with no values at all produces no predicate instead of an unbounded statement")
    func emptyRowIsRefused() {
        #expect(throws: RowIdentityError.emptyPredicate) {
            try RowMutationSQL.identityPredicate(
                columns: keyedColumns,
                row: [],
                identifierQuote: "`",
                dialect: .mysql
            )
        }
    }

    @Test("A quote inside an identifier is doubled, not escaped away")
    func identifiersAreQuoted() throws {
        let predicate = try RowMutationSQL.identityPredicate(
            columns: [column("we`ird", primaryKey: true)],
            row: [.int(1)],
            identifierQuote: "`",
            dialect: .mysql
        )
        #expect(predicate.sql == "`we``ird` = ?")
    }

    @Test("A control character in an identifier is refused")
    func controlCharactersAreRefused() {
        #expect(throws: RowIdentityError.invalidIdentifier("bad\u{0}name")) {
            try RowMutationSQL.identityPredicate(
                columns: [column("bad\u{0}name", primaryKey: true)],
                row: [.int(1)],
                identifierQuote: "`",
                dialect: .mysql
            )
        }
    }

    // MARK: What the audit record is allowed to see

    @Test("The audit shape keeps the placeholders, so no row value can reach the audit log")
    func auditShapeCarriesNoValues() throws {
        let predicate = try RowMutationSQL.identityPredicate(
            columns: keyedColumns,
            row: [.int(7), .string("ada@example.test"), .null],
            identifierQuote: "`",
            dialect: .mysql
        )
        #expect(predicate.auditShape == "`id` = ? AND `name` = ? AND `score` IS NULL")
        #expect(!predicate.auditShape.contains("ada@example.test"))
        #expect(!predicate.auditShape.contains("7"))
    }
}

@Suite("Row deletion SQL")
struct RowDeleteSQLTests {

    @Test("DELETE carries the same optimistic identity the UPDATE path uses")
    func deleteUsesTheIdentityPredicate() throws {
        let statement = try RowMutationSQL.delete(
            database: "gpt_test",
            table: "members",
            columns: keyedColumns,
            row: [.int(7), .string("Ada"), .int(91)],
            identifierQuote: "`",
            dialect: .mysql
        )
        #expect(statement.sql == "DELETE FROM `gpt_test`.`members` WHERE `id` = ? AND `name` = ? AND `score` = ?")
        #expect(statement.predicate.parameters == [.int(7), .string("Ada"), .int(91)])
    }

    @Test("PostgreSQL deletion starts its own placeholders at $1 — nothing is bound before it")
    func postgresDelete() throws {
        let statement = try RowMutationSQL.delete(
            database: "public",
            table: "members",
            columns: keyedColumns,
            row: [.int(7), .null, .int(91)],
            identifierQuote: "\"",
            dialect: .postgresql
        )
        #expect(statement.sql == "DELETE FROM \"public\".\"members\" WHERE \"id\" = $1 AND \"name\" IS NULL AND \"score\" = $2")
        #expect(statement.predicate.parameters == [.int(7), .int(91)])
    }

    @Test("Deletion is never emitted without a WHERE clause")
    func deleteAlwaysHasAPredicate() throws {
        // The failure mode that matters: a DELETE whose predicate silently collapsed would empty
        // the table. Every refusal path must throw before any SQL exists.
        #expect(throws: RowIdentityError.emptyPredicate) {
            try RowMutationSQL.delete(database: "d", table: "t", columns: keyedColumns,
                                      row: [], identifierQuote: "`", dialect: .mysql)
        }
        #expect(throws: RowIdentityError.noPrimaryKey) {
            try RowMutationSQL.delete(database: "d", table: "t", columns: [column("a")],
                                      row: [.int(1)], identifierQuote: "`", dialect: .mysql)
        }
    }

    @Test("The database and table are quoted component by component")
    func objectNameIsQuotedPerComponent() throws {
        let statement = try RowMutationSQL.delete(
            database: "my`db",
            table: "my`table",
            columns: [column("id", primaryKey: true)],
            row: [.int(1)],
            identifierQuote: "`",
            dialect: .mysql
        )
        #expect(statement.sql.hasPrefix("DELETE FROM `my``db`.`my``table` WHERE "))
    }
}
