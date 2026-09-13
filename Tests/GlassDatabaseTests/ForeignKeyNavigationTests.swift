//
//  ForeignKeyNavigationTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  Following a foreign key. The composite case is the point: `foreignKeys(in:database:)` returned
//  a cross product with no ordinal correlation until 2026-09-12, and navigation built on that
//  would have opened the referenced table filtered by the wrong column — wrong, and confident.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

private func key(_ constraint: String, _ column: String, _ table: String,
                 _ referenced: String, _ ordinal: Int) -> ForeignKeyInfo {
    ForeignKeyInfo(constraintName: constraint, columnName: column, referencedTable: table,
                   referencedColumn: referenced, ordinalPosition: ordinal)
}

private func column(_ name: String, _ type: String = "int", unsigned: Bool = false) -> ColumnInfo {
    ColumnInfo(name: name, type: type, isUnsigned: unsigned)
}

@Suite("Foreign-key relationships")
struct ForeignKeyRelationshipTests {

    @Test("A single-column key becomes one relationship")
    func singleColumnKey() {
        let relationships = ForeignKeyNavigation.relationships(
            from: [key("members_team_fk", "team_id", "teams", "id", 1)])
        #expect(relationships.count == 1)
        #expect(relationships[0].pairs == [.init(column: "team_id", referencedColumn: "id")])
        #expect(!relationships[0].isComposite)
        #expect(relationships[0].summary == "team_id → teams.id")
    }

    @Test("A composite key pairs by ordinal, in ordinal order, however the rows arrive")
    func compositeKeyPairsByOrdinal() {
        // Deliberately out of order: the adapter guarantees the ordinals, not the row order.
        let relationships = ForeignKeyNavigation.relationships(from: [
            key("gpt_fk_two", "y", "gpt_fk_parent", "b", 2),
            key("gpt_fk_two", "x", "gpt_fk_parent", "a", 1)
        ])
        let relationship = try! #require(relationships.first)
        #expect(relationship.isComposite)
        #expect(relationship.pairs == [.init(column: "x", referencedColumn: "a"),
                                       .init(column: "y", referencedColumn: "b")])
        #expect(relationship.summary == "(x, y) → gpt_fk_parent (a, b)")
    }

    @Test("A cross product is refused rather than followed")
    func crossProductIsRefused() {
        // What the PostgreSQL adapter used to return for `(x, y) → (a, b)`: four rows, every
        // ordinal duplicated. Half of these pairings are wrong and nothing in the data says which,
        // so the key is dropped instead of guessed at.
        let relationships = ForeignKeyNavigation.relationships(from: [
            key("gpt_fk_two", "x", "gpt_fk_parent", "a", 1),
            key("gpt_fk_two", "x", "gpt_fk_parent", "b", 1),
            key("gpt_fk_two", "y", "gpt_fk_parent", "a", 2),
            key("gpt_fk_two", "y", "gpt_fk_parent", "b", 2)
        ])
        #expect(relationships.isEmpty)
    }

    @Test("A key whose members disagree about the referenced table is refused")
    func inconsistentTargetIsRefused() {
        let relationships = ForeignKeyNavigation.relationships(from: [
            key("k", "x", "one", "a", 1),
            key("k", "y", "two", "b", 2)
        ])
        #expect(relationships.isEmpty)
    }

    @Test("Several keys on one table are listed, sorted by constraint name")
    func multipleKeysAreSorted() {
        let relationships = ForeignKeyNavigation.relationships(from: [
            key("zeta_fk", "b_id", "bees", "id", 1),
            key("alpha_fk", "a_id", "ays", "id", 1)
        ])
        #expect(relationships.map(\.constraintName) == ["alpha_fk", "zeta_fk"])
    }
}

@Suite("Following a foreign key")
struct ForeignKeyFollowTests {

    private let localColumns = [column("id"), column("team_id"), column("name", "varchar(40)")]
    private let teamColumns = [column("id"), column("name", "varchar(40)")]

    @Test("A single-column follow filters the referenced table on the referenced column")
    func singleColumnFollow() throws {
        let relationship = ForeignKeyNavigation.relationships(
            from: [key("members_team_fk", "team_id", "teams", "id", 1)])[0]
        let filters = try ForeignKeyNavigation.filters(
            following: relationship,
            row: [.int(1), .int(42), .string("Ada")],
            columns: localColumns,
            referencedColumns: teamColumns
        )
        #expect(filters.count == 1)
        #expect(filters[0].columnName == "id", "the referenced column, not the referencing one")
        #expect(filters[0].operation == .equals)
        #expect(filters[0].value == "42")
        // Parenthesised deliberately: `validationError` takes a dialect now, and an unparenthesised
        // reference compiles as a *function value*, which `== nil` then promotes and answers false
        // for — a comparison that can never hold and never warns. Ask it for a verdict, not a
        // reference to the function that produces one.
        #expect(filters[0].validationError(dialect: .mysql) == nil)
    }

    @Test("A composite follow carries every column pair, so it lands on one row")
    func compositeFollowCarriesEveryPair() throws {
        // The defect this exists for: with only the leading pair the target opens at the first
        // row sharing `a`, which is a different row whenever the key is composite for a reason.
        let relationship = ForeignKeyNavigation.relationships(from: [
            key("gpt_fk_two", "x", "gpt_fk_parent", "a", 1),
            key("gpt_fk_two", "y", "gpt_fk_parent", "b", 2)
        ])[0]
        let filters = try ForeignKeyNavigation.filters(
            following: relationship,
            row: [.int(5), .int(7)],
            columns: [column("x"), column("y")],
            referencedColumns: [column("a"), column("b")]
        )
        #expect(filters.map(\.columnName) == ["a", "b"])
        #expect(filters.map(\.value) == ["5", "7"])
    }

    @Test("The filter is typed by the referenced column, not the referencing one")
    func filterTakesTheTargetType() throws {
        let relationship = ForeignKeyNavigation.relationships(
            from: [key("fk", "team_id", "teams", "id", 1)])[0]
        let filters = try ForeignKeyNavigation.filters(
            following: relationship,
            row: [.int(1), .uint(42), .string("Ada")],
            columns: localColumns,
            referencedColumns: [column("id", "bigint", unsigned: true)]
        )
        #expect(filters[0].columnType == "bigint")
        #expect(filters[0].isUnsigned)
        #expect(try filters[0].boundValue() == .uint(42), "an unsigned target binds unsigned")
    }

    @Test("A NULL foreign key references nothing and is refused")
    func nullReferenceIsRefused() {
        let relationship = ForeignKeyNavigation.relationships(
            from: [key("fk", "team_id", "teams", "id", 1)])[0]
        #expect(throws: ForeignKeyNavigationError.nullReference(column: "team_id")) {
            try ForeignKeyNavigation.filters(
                following: relationship,
                row: [.int(1), .null, .string("Ada")],
                columns: localColumns,
                referencedColumns: teamColumns)
        }
    }

    @Test("A value whose display form is a placeholder is refused, not filtered on")
    func binaryValueIsRefused() {
        // `DatabaseValue.data` displays as `<3 bytes>`. Filtering on that string would find
        // nothing and look like an empty referenced table.
        let relationship = ForeignKeyNavigation.relationships(
            from: [key("fk", "blob_id", "targets", "id", 1)])[0]
        #expect(throws: ForeignKeyNavigationError.self) {
            try ForeignKeyNavigation.filters(
                following: relationship,
                row: [.data(Data([1, 2, 3]))],
                columns: [column("blob_id", "blob")],
                referencedColumns: [column("id", "blob")])
        }
    }

    @Test("A column missing from the loaded result is refused rather than skipped")
    func missingColumnIsRefused() {
        let relationship = ForeignKeyNavigation.relationships(
            from: [key("fk", "absent", "teams", "id", 1)])[0]
        #expect(throws: ForeignKeyNavigationError.missingColumn("absent")) {
            try ForeignKeyNavigation.filters(
                following: relationship,
                row: [.int(1)],
                columns: [column("id")],
                referencedColumns: teamColumns)
        }
    }
}

@MainActor
@Suite("Foreign-key filter handoff")
struct ForeignKeyFilterHandoffTests {

    @Test("Staged filters are claimed once and never twice")
    func claimIsDestructive() {
        ForeignKeyFilterHandoff.reset()
        let session = UUID()
        let target = ForeignKeyFilterHandoff.Key(sessionID: session, database: "d", table: "teams")
        let filter = GridColumnFilter(columnName: "id", columnType: "int",
                                      operation: .equals, value: "42")
        ForeignKeyFilterHandoff.stage([filter], for: target)

        #expect(ForeignKeyFilterHandoff.claim(target)?.map(\.value) == ["42"])
        #expect(ForeignKeyFilterHandoff.claim(target) == nil,
                "a stale handoff must not be applied to a later, unrelated visit")
    }

    @Test("A handoff that nothing ever claimed goes stale rather than ambushing a later visit")
    func staleHandoffIsDiscarded() {
        // The failure this bounds is silent: an entry left behind because nothing opened the table
        // would filter the user's next ordinary visit to it and look exactly like the app working.
        // The real claim happens on the next run loop, so the window is never tight in practice.
        ForeignKeyFilterHandoff.reset()
        let target = ForeignKeyFilterHandoff.Key(sessionID: UUID(), database: "d", table: "teams")
        let staged = Date(timeIntervalSince1970: 1_000_000)
        let filter = GridColumnFilter(columnName: "id", columnType: "int",
                                      operation: .equals, value: "42")

        ForeignKeyFilterHandoff.stage([filter], for: target, at: staged)
        #expect(ForeignKeyFilterHandoff.claim(target, at: staged + 1) != nil, "the ordinary case")

        ForeignKeyFilterHandoff.stage([filter], for: target, at: staged)
        #expect(ForeignKeyFilterHandoff.claim(
            target, at: staged + ForeignKeyFilterHandoff.staleAfter + 1) == nil)
        #expect(ForeignKeyFilterHandoff.claim(target, at: staged) == nil,
                "and a discarded entry is gone, not merely refused once")
    }

    @Test("A handoff belongs to one session, database and table")
    func keysDoNotBleed() {
        ForeignKeyFilterHandoff.reset()
        let session = UUID()
        let target = ForeignKeyFilterHandoff.Key(sessionID: session, database: "d", table: "teams")
        ForeignKeyFilterHandoff.stage(
            [GridColumnFilter(columnName: "id", columnType: "int", operation: .equals, value: "1")],
            for: target)

        #expect(ForeignKeyFilterHandoff.claim(.init(sessionID: UUID(), database: "d", table: "teams")) == nil)
        #expect(ForeignKeyFilterHandoff.claim(.init(sessionID: session, database: "other", table: "teams")) == nil)
        #expect(ForeignKeyFilterHandoff.claim(.init(sessionID: session, database: "d", table: "members")) == nil)
        #expect(ForeignKeyFilterHandoff.claim(target) != nil, "and the right key still finds it")
    }
}
