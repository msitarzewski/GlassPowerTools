//
//  GridColumnFilterDialectTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  The *joining* test for the last of the `text`/`blob` size limits.
//
//  `ColumnTypeConstraintTests` already proves the parser: MySQL's eight large-object names map to
//  their byte limits, and bare `text`/`blob` stay unconstrained without a dialect because those two
//  names mean ~1 GB on PostgreSQL and `SQLITE_MAX_LENGTH` on SQLite. That was never in doubt.
//
//  The gap turned out to be larger than the dialect. `GridColumnFilter.validationError` was a
//  second, weaker implementation that called `boundValue()` and stopped — and `boundValue()` is
//  type conversion only. So a grid filter ran **no size check at all**, on any type, on any
//  engine: `varchar(4)` accepted `"12345"` and returned an empty page with no explanation.
//  `ColumnTypeConstraint` was written to serve both the record editor and the grid; only one of
//  the two was calling it.
//
//  The first version of this file asserted only the dialect-dependent cases, and would have
//  passed for the wrong reason. Adding `varchar(4)` — which needs no dialect and should have
//  worked all along — is what exposed it. That is the standing correction from R7 arriving in a
//  new shape: an engine-level test proved the engine could do `VERIFY_CA`, not that a saved
//  record reached it. "It works" and "the parts that would make it work all exist" look identical
//  from below, and a test aimed only at the part you suspect will agree with you.
//
//  **What they still do not prove:** that the SwiftUI call sites pass a *real* dialect rather than
//  nil. `session?.connection?.dialect` is threaded at five places (`TableDetailView.swift`
//  filter validation, staged filters, display-filter evaluation, the server query builder, and
//  `ForeignKeyNavigation.filters`), and only driving the app proves those are non-nil in practice.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

@Suite("Grid filter size limits honour the dialect")
struct GridColumnFilterDialectTests {
    private func filter(type: String, value: String) -> GridColumnFilter {
        GridColumnFilter(columnName: "note", columnType: type, operation: .equals, value: value)
    }

    /// 65,536 bytes: one past MySQL's `TEXT`, comfortably inside PostgreSQL's and SQLite's.
    private var oversizeForMySQLText: String { String(repeating: "a", count: 65_536) }

    @Test("A bare `text` filter is limited on MySQL and left alone elsewhere")
    func bareTextDependsOnTheDialect() {
        let subject = filter(type: "text", value: oversizeForMySQLText)

        #expect(subject.validationError(dialect: .mysql) != nil,
                "MySQL TEXT holds 65,535 bytes; the filter value is 65,536")

        for dialect in [DatabaseDialect.postgresql, .sqlite] {
            #expect(subject.validationError(dialect: dialect) == nil,
                    "\(dialect) stores this perfectly well; refusing it would be the worse error")
        }

        #expect(subject.validationError(dialect: nil) == nil,
                "an unknown engine must not borrow MySQL's limit")
    }

    /// The six unambiguous names never needed the dialect — but they did need the filter to call
    /// the parser at all, which before this change it did not.
    @Test("MySQL-only large-object names are limited through a filter")
    func mysqlOnlyNamesAreLimitedThroughAFilter() {
        #expect(filter(type: "tinytext", value: String(repeating: "a", count: 256))
            .validationError(dialect: .mysql) != nil)
        #expect(filter(type: "tinytext", value: String(repeating: "a", count: 255))
            .validationError(dialect: .mysql) == nil)
        #expect(filter(type: "tinyblob", value: String(repeating: "a", count: 256))
            .validationError(dialect: .mysql) != nil)
    }

    /// Byte-counted, not character-counted — the distinction that matters for a utf8mb4 column.
    /// One emoji is four UTF-8 bytes, so 64 of them exceed a 255-byte `tinytext` while being
    /// only 64 characters.
    @Test("Large-object limits count bytes, not characters")
    func limitsAreCountedInBytes() {
        let emoji = String(repeating: "😀", count: 64)   // 64 characters, 256 bytes
        #expect(emoji.count == 64 && emoji.utf8.count == 256)
        #expect(filter(type: "tinytext", value: emoji).validationError(dialect: .mysql) != nil)
    }

    /// Limits that do not depend on the dialect, which filters were not checking at all before.
    @Test("Dialect-independent limits apply with no dialect")
    func dialectIndependentLimits() {
        #expect(filter(type: "varchar(4)", value: "12345").validationError() != nil)
        #expect(filter(type: "varchar(4)", value: "1234").validationError() == nil)
        #expect(filter(type: "tinyint", value: "999").validationError() != nil)
        #expect(filter(type: "tinyint", value: "127").validationError() == nil)
    }

    /// The size check is for `=` only. This is the test that stops someone "tidying" that
    /// condition away: the other three operators have legitimate out-of-range uses, and blocking
    /// them would refuse queries that are correct.
    @Test("Only equality is size-checked; ordering and inequality are left alone")
    func onlyEqualityIsSizeChecked() {
        let tooLong = "12345"   // one past varchar(4)

        var subject = filter(type: "varchar(4)", value: tooLong)
        subject.operation = .equals
        #expect(subject.validationError() != nil, "no stored row can equal this")

        subject.operation = .notEquals
        #expect(subject.validationError() == nil, "every stored row differs from it — a valid query")

        subject.operation = .greaterThan
        #expect(subject.validationError() == nil, "an out-of-range bound is how you say 'all of them'")

        subject.operation = .lessThan
        #expect(subject.validationError() == nil)
    }

    /// Operators that take no value cannot overflow, whatever the column holds.
    @Test("Valueless operators are never rejected")
    func valuelessOperatorsAreNeverRejected() {
        var subject = filter(type: "varchar(4)", value: String(repeating: "x", count: 500))
        subject.operation = .isNull
        #expect(subject.validationError() == nil)
        #expect(try! subject.boundValue() == nil)
        subject.operation = .isNotNull
        #expect(subject.validationError() == nil)
    }

    /// The dialect is a parameter, not a stored property, so a saved filter carries no engine with
    /// it. This pins that: `GridColumnFilter` round-trips through `Codable` unchanged, which is why
    /// the change needed no persistence migration.
    @Test("The dialect is not persisted with the filter")
    func dialectIsNotPartOfTheSavedFilter() throws {
        let original = filter(type: "text", value: "x")
        let decoded = try JSONDecoder().decode(
            GridColumnFilter.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)

        let encoded = String(decoding: try JSONEncoder().encode(original), as: UTF8.self)
        #expect(!encoded.contains("dialect"),
                "a saved filter outlives its session; the engine belongs to the connection")
    }
}
