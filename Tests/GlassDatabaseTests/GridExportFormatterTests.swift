//
//  GridExportFormatterTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  `GridExportFormatter` (`DataExporter.swift:66`) is what leaves the app: the CSV/JSON/SQL export
//  document and the TSV the grid puts on the pasteboard for a copied selection. It came from
//  glassdb verbatim with no tests.
//
//  This is fidelity rather than security — nobody is attacked by a bad export — but the failure is
//  silent, which is why it is worth pinning. An export is written once, read somewhere else, and
//  the reader has nothing to compare it against.
//
//  **The TSV null encoding is the part that collapses.** It carries three distinct states:
//
//  | value                       | encoding |
//  |-----------------------------|----------|
//  | SQL `NULL`                  | `\N`     |
//  | empty string                | (empty)  |
//  | the two characters `\` `N`  | `\\N`    |
//
//  The third exists only because `escapeTSV` doubles backslashes, and it is the one an edit
//  removes without noticing: drop it and a row containing the literal text `\N` comes back from
//  the paste as NULL. `nullEmptyAndLiteralBackslashNAreThreeStates` asserts all three together and
//  asserts that they differ, rather than three separate expectations that could each be satisfied
//  by the same collapsed encoding.
//
//  Note the asymmetry with CSV, pinned below in `csvCannotDistinguishNullFromTheWordNULL`: CSV has
//  no null encoding at all and writes `NULL` for both. That is a real limitation of the format and
//  is recorded here so the difference reads as deliberate rather than as a bug in one of them.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

@Suite("Grid export formatting")
struct GridExportFormatterTests {
    private func result(
        columns: [String],
        rows: [[DatabaseValue]],
        types: [String]? = nil
    ) -> QueryResult {
        QueryResult(
            query: "SELECT *",
            columns: columns.enumerated().map { index, name in
                ColumnInfo(name: name, type: types?[index] ?? "varchar(255)")
            },
            rows: rows,
            executionTime: 0
        )
    }

    private func tsv(_ rows: [[DatabaseValue]], columns: [String] = ["a"]) -> String {
        let subject = result(columns: columns, rows: rows)
        return GridExportFormatter.tsv(
            result: subject,
            rowRange: 0...(max(rows.count, 1) - 1),
            columnRange: 0...(columns.count - 1)
        )
    }

    // MARK: - TSV: the three states

    /// The whole point of the TSV encoding, asserted as one test because the property is that the
    /// three are *distinct*, not that each has some particular spelling.
    @Test("NULL, the empty string and a literal backslash-N are three different encodings")
    func nullEmptyAndLiteralBackslashNAreThreeStates() {
        let lines = tsv([[.null], [.string("")], [.string(#"\N"#)]]).split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.count == 3)
        #expect(lines[0] == #"\N"#, "SQL NULL")
        #expect(lines[1] == "", "an empty string is empty, not null")
        #expect(lines[2] == #"\\N"#, "the escaped form of the two characters \\ and N")
        #expect(Set(lines).count == 3, "a reader must be able to tell the three apart")
    }

    /// `NULL` spelled as text is a fourth thing again, and unlike CSV, TSV keeps it separate.
    @Test("The string NULL survives as text, distinct from SQL NULL")
    func theWordNULLIsNotNull() {
        let lines = tsv([[.null], [.string("NULL")]]).split(separator: "\n")

        #expect(lines[0] == #"\N"#)
        #expect(lines[1] == "NULL")
    }

    @Test("Tabs, newlines and carriage returns are escaped so a value stays one cell")
    func tsvEscapesStructuralCharacters() {
        #expect(tsv([[.string("a\tb")]]) == #"a\tb"#)
        #expect(tsv([[.string("a\nb")]]) == #"a\nb"#)
        #expect(tsv([[.string("a\r\nb")]]) == #"a\r\nb"#)
        #expect(tsv([[.string(#"a\tb"#)]]) == #"a\\tb"#,
                "a literal backslash-t must not become a tab when read back")
    }

    @Test("TSV separates cells with tabs and rows with newlines")
    func tsvLayout() {
        let text = tsv([[.string("a"), .int(1)], [.string("b"), .int(2)]], columns: ["x", "y"])

        #expect(text == "a\t1\nb\t2", "no header row: this is a copied selection, not a file")
    }

    /// The pasteboard copies whatever rectangle is selected, and the selection is clamped to the
    /// result rather than trusted.
    @Test("Row and column ranges are clamped to the result")
    func tsvRangesAreClamped() {
        let subject = result(
            columns: ["x", "y", "z"],
            rows: [
                [.string("a1"), .string("b1"), .string("c1")],
                [.string("a2"), .string("b2"), .string("c2")]
            ]
        )

        #expect(GridExportFormatter.tsv(result: subject, rowRange: 1...1, columnRange: 1...2)
                == "b2\tc2")
        #expect(GridExportFormatter.tsv(result: subject, rowRange: 0...99, columnRange: 0...99)
                == "a1\tb1\tc1\na2\tb2\tc2",
                "an over-wide selection is clamped, not an index crash")
        #expect(GridExportFormatter.tsv(result: subject, rowRange: 5...9, columnRange: 0...0) == "",
                "a selection entirely past the end copies nothing")
    }

    @Test("An empty result copies nothing")
    func tsvOfEmptyResult() {
        let empty = QueryResult(query: "SELECT *", executionTime: 0)

        #expect(GridExportFormatter.tsv(result: empty, rowRange: 0...0, columnRange: 0...0) == "")
    }

    /// Binary is Base64 in a TSV cell, but a bit field is its binary digits — `.bit` is the one
    /// type the TSV path deliberately takes from `displayString` instead of `exportString`,
    /// because `b'1010'` means the digits, not four bytes.
    @Test("Binary is Base64 and a bit field is its digits")
    func tsvBinaryAndBits() {
        #expect(tsv([[.data(Data([0xDE, 0xAD]))]]) == Data([0xDE, 0xAD]).base64EncodedString())
        #expect(tsv([[.bit(Data([0b0000_1010]))]]) == "00001010")
    }

    @Test("A row shorter than the selection contributes an empty cell, not a shifted one")
    func tsvShortRow() {
        let subject = result(
            columns: ["x", "y"],
            rows: [[.string("only")]]
        )

        #expect(GridExportFormatter.tsv(result: subject, rowRange: 0...0, columnRange: 0...1)
                == "only\t")
    }

    // MARK: - CSV

    @Test("CSV writes a header row and quotes only what needs quoting")
    func csvShape() {
        let text = GridExportFormatter.csv(result: result(
            columns: ["id", "note"],
            rows: [
                [.int(1), .string("plain")],
                [.int(2), .string("has,comma")],
                [.int(3), .string("has\"quote")],
                [.int(4), .string("has\nnewline")]
            ]
        ))

        #expect(text == """
            id,note
            1,plain
            2,"has,comma"
            3,"has""quote"
            4,"has
            newline"
            """)
    }

    /// Recorded, not endorsed. CSV has no null sentinel, so both of these become the four
    /// characters `NULL`. The TSV path exists partly because of this.
    @Test("CSV cannot distinguish NULL from the word NULL")
    func csvCannotDistinguishNullFromTheWordNULL() {
        let text = GridExportFormatter.csv(result: result(
            columns: ["a"],
            rows: [[.null], [.string("NULL")], [.string("")]]
        ))

        #expect(text == "a\nNULL\nNULL\n")
    }

    @Test("A row shorter than the column list is padded with empty cells")
    func csvShortRow() {
        let text = GridExportFormatter.csv(result: result(
            columns: ["a", "b", "c"],
            rows: [[.string("x")]]
        ))

        #expect(text == "a,b,c\nx,,")
    }

    @Test("A result with no rows exports its header alone")
    func csvHeaderOnly() {
        #expect(GridExportFormatter.csv(result: result(columns: ["a", "b"], rows: [])) == "a,b")
    }

    // MARK: - SQL

    @Test("SQL exports one INSERT per row with quoted identifiers")
    func sqlShape() {
        let text = GridExportFormatter.sql(
            result: result(
                columns: ["id", "note"],
                rows: [[.int(1), .string("hi")], [.int(2), .null]]
            ),
            database: "shop",
            table: "orders"
        )

        #expect(text == """
            INSERT INTO `shop`.`orders` (`id`, `note`) VALUES (1, 'hi');
            INSERT INTO `shop`.`orders` (`id`, `note`) VALUES (2, NULL);
            """)
    }

    @Test("A single quote in a value is doubled, and so is a quote in an identifier")
    func sqlQuoting() {
        let text = GridExportFormatter.sql(
            result: result(columns: ["no`te"], rows: [[.string("it's")]]),
            database: "sh`op",
            table: "orders"
        )

        #expect(text == "INSERT INTO `sh``op`.`orders` (`no``te`) VALUES ('it''s');")
    }

    @Test("PostgreSQL identifiers use the quote the caller passes")
    func sqlHonoursTheIdentifierQuote() {
        let text = GridExportFormatter.sql(
            result: result(columns: ["id"], rows: [[.int(1)]]),
            database: "shop",
            table: "orders",
            identifierQuote: "\""
        )

        #expect(text == #"INSERT INTO "shop"."orders" ("id") VALUES (1);"#)
    }

    @Test("Binary and bit values use SQL's own literal syntaxes")
    func sqlBinaryLiterals() {
        let text = GridExportFormatter.sql(
            result: result(columns: ["b", "f"], rows: [[.data(Data([0xDE, 0xAD])), .bit(Data([0b0000_1010]))]]),
            database: "d",
            table: "t"
        )

        #expect(text.contains("X'DEAD'"))
        #expect(text.contains("B'00001010'"))
    }

    /// A non-finite double has no SQL literal, so it becomes NULL rather than the text `inf`,
    /// which would fail to parse on replay.
    @Test("A non-finite double exports as NULL")
    func sqlNonFiniteDouble() {
        let text = GridExportFormatter.sql(
            result: result(columns: ["d"], rows: [[.double(.infinity)], [.double(.nan)]]),
            database: "d",
            table: "t"
        )

        #expect(text == """
            INSERT INTO `d`.`t` (`d`) VALUES (NULL);
            INSERT INTO `d`.`t` (`d`) VALUES (NULL);
            """)
    }

    @Test("An empty result produces no INSERT statements")
    func sqlEmptyResult() {
        #expect(GridExportFormatter.sql(
            result: result(columns: ["a"], rows: []),
            database: "d",
            table: "t"
        ) == "")
        #expect(GridExportFormatter.sql(
            result: QueryResult(query: "", executionTime: 0),
            database: "d",
            table: "t"
        ) == "")
    }

    // MARK: - JSON

    @Test("JSON keeps types rather than stringifying everything")
    func jsonTypes() throws {
        let text = GridExportFormatter.json(result: result(
            columns: ["i", "s", "n", "b", "d"],
            rows: [[.int(-5), .string("x"), .null, .bool(true), .double(1.5)]]
        ))
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let row = try #require((object["rows"] as? [[Any]])?.first)

        #expect(row[0] as? Int == -5)
        #expect(row[1] as? String == "x")
        #expect(row[2] is NSNull, "a JSON null, not the string NULL")
        #expect(row[3] as? Bool == true)
        #expect(row[4] as? Double == 1.5)
    }

    /// A `UInt64` past 2^53 cannot round-trip through a JSON number, so it is written as a string
    /// instead of being quietly rounded.
    @Test("An unsigned integer beyond exact double range becomes a string")
    func jsonLargeUnsigned() throws {
        let text = GridExportFormatter.json(result: result(
            columns: ["u"],
            rows: [[.uint(9_007_199_254_740_991)], [.uint(9_007_199_254_740_992)]]
        ))
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let rows = try #require(object["rows"] as? [[Any]])

        #expect(rows[0][0] as? UInt64 == 9_007_199_254_740_991)
        #expect(rows[1][0] as? String == "9007199254740992")
    }

    @Test("Binary and bit values are tagged objects so they are not mistaken for text")
    func jsonBinaryIsTagged() throws {
        let text = GridExportFormatter.json(result: result(
            columns: ["b", "f"],
            rows: [[.data(Data([0xDE, 0xAD])), .bit(Data([0b0000_1010]))]]
        ))
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let row = try #require((object["rows"] as? [[Any]])?.first)

        #expect((row[0] as? [String: Any])?["$binary"] as? String == "3q0=")
        #expect((row[1] as? [String: Any])?["$bit"] as? String == "00001010")
    }

    /// A JSON column holds JSON, so it is embedded rather than escaped into a string.
    @Test("A JSON column is embedded as structure, and invalid JSON falls back to text")
    func jsonColumnIsEmbedded() throws {
        let text = GridExportFormatter.json(result: result(
            columns: ["j", "k"],
            rows: [[.json(#"{"a":1}"#), .json("not json")]]
        ))
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let row = try #require((object["rows"] as? [[Any]])?.first)

        #expect((row[0] as? [String: Any])?["a"] as? Int == 1)
        #expect(row[1] as? String == "not json")
    }

    @Test("JSON carries the column names and types")
    func jsonColumns() throws {
        let text = GridExportFormatter.json(result: result(
            columns: ["id"],
            rows: [],
            types: ["int"]
        ))
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let columns = try #require(object["columns"] as? [[String: String]])

        #expect(columns == [["name": "id", "type": "int"]])
        #expect((object["rows"] as? [Any])?.isEmpty == true)
    }

    // MARK: - The document that ships them

    /// `GridExportDocument` is the production entry point; it must route each format to the
    /// formatter this file tests rather than to a second implementation.
    @Test("The export document routes each format to the formatter")
    func documentRoutesEachFormat() {
        let subject = result(columns: ["id"], rows: [[.int(1)]])

        for format in GridExportFormat.allCases {
            let document = GridExportDocument(
                result: subject,
                format: format,
                database: "shop",
                table: "orders"
            )
            let expected = switch format {
            case .csv: GridExportFormatter.csv(result: subject)
            case .json: GridExportFormatter.json(result: subject)
            case .sql: GridExportFormatter.sql(result: subject, database: "shop", table: "orders")
            }
            #expect(document.text == expected, "\(format) is not the formatter's output")
        }
    }
}
