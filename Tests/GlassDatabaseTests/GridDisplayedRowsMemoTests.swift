import Foundation
import Testing
@testable import GlassDatabase

/// The grid keeps its displayed rows between body evaluations; a stale answer would show the
/// wrong rows after a filter, sort or new page, so every part of the key must invalidate it.
@Suite("Grid displayed rows memo")
@MainActor
struct GridDisplayedRowsMemoTests {
    private func key(result: UUID = Self.result, rowCount: Int = 10,
                     filters: [GridColumnFilter] = [], sorts: [GridSortDescriptor] = [],
                     isTable: Bool = true) -> GridDisplayedRowsMemo.Key {
        .init(result: result, rowCount: rowCount, filters: filters, sorts: sorts,
              dialect: .mysql, isAnalysis: false, isTable: isTable)
    }
    private static let result = UUID()

    @Test func sameKeyIsComputedOnce() {
        let memo = GridDisplayedRowsMemo()
        #expect(memo.rows(for: key()) { [3, 1, 2] } == [3, 1, 2])
        #expect(memo.rows(for: key()) { Issue.record("recomputed"); return [] } == [3, 1, 2])
        #expect(memo.computations == 1)
    }

    @Test func everyPartOfTheKeyInvalidates() {
        let memo = GridDisplayedRowsMemo()
        let changed: [GridDisplayedRowsMemo.Key] = [
            key(result: UUID()),
            key(rowCount: 11),
            key(sorts: [GridSortDescriptor(columnName: "name", direction: .descending)]),
            key(isTable: false),
        ]
        _ = memo.rows(for: key()) { [0] }
        for (offset, next) in changed.enumerated() {
            #expect(memo.rows(for: next) { [offset + 1] } == [offset + 1])
        }
        #expect(memo.computations == changed.count + 1)
    }
}
