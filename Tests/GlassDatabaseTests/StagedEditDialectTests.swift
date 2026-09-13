//
//  StagedEditDialectTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  `StagedEdit` carries the engine, so the record editor's size rules can tell MySQL's 64 KiB
//  `text` from PostgreSQL's gigabyte one. Six of the eight `TEXT`/`BLOB` names exist only in
//  MySQL and need no dialect; bare `text` and bare `blob` are shared, and borrowing MySQL's limit
//  for them would refuse values that store perfectly well.
//
//  These assert the wiring — that the dialect actually reaches `ColumnTypeConstraint` through a
//  `StagedEdit` — rather than re-testing the constraint table itself.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

private func edit(_ type: String, dialect: DatabaseDialect?, text: String) -> StagedEdit {
    StagedEdit(columnIndex: 0, columnName: "body", columnType: type, dialect: dialect,
               isPrimaryKey: false, isNullable: true, isUnsigned: false, isGenerated: false,
               defaultValue: nil, originalValue: .null, editText: text,
               isNull: false, useDefault: false)
}

@Suite("Staged edit dialect")
struct StagedEditDialectTests {

    private var tooBigForMySQL: String { String(repeating: "a", count: 65_536) }

    @Test("A MySQL `text` is bounded at 65,535 bytes through the staged edit")
    func mysqlTextIsBounded() {
        let staged = edit("text", dialect: .mysql, text: tooBigForMySQL)
        let message = try! #require(staged.validationError)
        #expect(message.contains("65535"))
    }

    @Test("The same value in a PostgreSQL `text` is not refused")
    func postgresTextIsNotBounded() {
        #expect(edit("text", dialect: .postgresql, text: tooBigForMySQL).validationError == nil)
        #expect(edit("text", dialect: .sqlite, text: tooBigForMySQL).validationError == nil)
    }

    @Test("With no dialect the shared names stay unconstrained — a missing limit, never a borrowed one")
    func unknownDialectLeavesSharedNamesAlone() {
        // The safe direction, and the reason `dialect` is optional rather than defaulted to MySQL:
        // failing to warn costs a server-side error the user can read; a false limit silently
        // refuses data that would have stored.
        #expect(edit("text", dialect: nil, text: tooBigForMySQL).validationError == nil)
        #expect(edit("blob", dialect: nil, text: "not base64 but size is what is under test")
                    .constraint == nil)
    }

    @Test("The six MySQL-only names need no dialect at all")
    func mysqlOnlyNamesNeedNoDialect() {
        // `tinytext` and friends exist nowhere else, so they are safe to bound without knowing
        // the engine — which is why six of the eight worked before this field existed.
        let staged = edit("tinytext", dialect: nil, text: String(repeating: "a", count: 256))
        #expect(staged.validationError?.contains("255") == true)
    }

    @Test("`initialValue(for:columnIndex:dialect:)` carries the dialect onto the new row's edits")
    func initialValueCarriesTheDialect() {
        let column = ColumnInfo(name: "body", type: "text")
        #expect(StagedEdit.initialValue(for: column, columnIndex: 0, dialect: .mysql).dialect == .mysql)
        #expect(StagedEdit.initialValue(for: column, columnIndex: 0).dialect == nil)
    }
}
