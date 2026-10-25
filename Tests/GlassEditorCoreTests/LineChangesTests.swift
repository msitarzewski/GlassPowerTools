import Testing
@testable import GlassEditorCore

/// The marks beside changed lines (2026-10-23): which lines differ from the last commit.
@Suite("Line changes against the last commit")
struct LineChangesTests {

    @Test func theSameTextHasNoMarks() {
        #expect(LineChanges.between(base: "a\nb\n", current: "a\nb\n").isEmpty)
        #expect(LineChanges.between(base: "", current: "").isEmpty)
    }

    @Test func linesAddedChangedAndRemovedAreToldApart() {
        let base = "one\ntwo\nthree\nfour\nfive\n"
        let current = "one\nTWO\nthree\nnew\nfour\n"
        #expect(LineChanges.between(base: base, current: current) == [
            LineChange(kind: .modified, lines: 1..<2, baseLines: 1..<2),
            LineChange(kind: .added, lines: 3..<4, baseLines: 3..<3),
            LineChange(kind: .deleted, lines: 5..<5, baseLines: 4..<5),
        ])
    }

    @Test func aChangeThatAddsLinesIsOneChangeCoveringThemAll() {
        // Two lines where one was: changed, all of it, as VS Code marks it.
        #expect(LineChanges.between(base: "a\nb\nc\n", current: "a\nB1\nB2\nc\n") == [
            LineChange(kind: .modified, lines: 1..<3, baseLines: 1..<2),
        ])
    }

    @Test func aNewFileIsAddedThroughout() {
        #expect(LineChanges.between(base: "", current: "x\ny\n") == [
            LineChange(kind: .added, lines: 0..<2, baseLines: 0..<0),
        ])
    }

    @Test func linesRemovedFromTheEndAreMarkedAfterTheLastLine() {
        // No newline at the end: the removal is below the last line there is.
        #expect(LineChanges.between(base: "a\nb\nc", current: "a\nb") == [
            LineChange(kind: .deleted, lines: 2..<2, baseLines: 2..<3),
        ])
        #expect(LineChanges.between(base: "a\nb\nc\n", current: "a\nb\n") == [
            LineChange(kind: .deleted, lines: 2..<2, baseLines: 2..<3),
        ])
    }

    @Test func windowsLineEndingsCompareAsTheyAre() {
        #expect(LineChanges.between(base: "a\r\nb\r\nc\r\n", current: "a\r\nB\r\nc\r\n") == [
            LineChange(kind: .modified, lines: 1..<2, baseLines: 1..<2),
        ])
    }

    @Test func editsFarApartInALongFileAreEachFound() {
        let base = (0..<50_000).map { "line \($0)" }
        var current = base
        current[10] = "changed"
        current.insert("inserted", at: 40_000)
        let changes = LineChanges.between(base: base.joined(separator: "\n"), current: current.joined(separator: "\n"))
        #expect(changes == [
            LineChange(kind: .modified, lines: 10..<11, baseLines: 10..<11),
            LineChange(kind: .added, lines: 40_000..<40_001, baseLines: 40_000..<40_000),
        ])
    }

    @Test func repeatedLinesStillLineUp() {
        // Blank lines and braces repeat everywhere in code; the difference must not drift.
        let base = "{\n}\n\n{\n}\n"
        let current = "{\n}\n\n{\nx\n}\n"
        #expect(LineChanges.between(base: base, current: current) == [
            LineChange(kind: .added, lines: 4..<5, baseLines: 4..<4),
        ])
    }

    @Test func aRewritePastTheLimitIsOneChange() {
        let base = (0..<3_000).map { "old \($0)" }.joined(separator: "\n") + "\n"
        let current = (0..<3_000).map { "new \($0)" }.joined(separator: "\n") + "\n"
        #expect(LineChanges.between(base: base, current: current) == [
            LineChange(kind: .modified, lines: 0..<3_000, baseLines: 0..<3_000),
        ])
    }

    @Test func theDifferenceIsMinimal() throws {
        let old: [Int32] = [1, 2, 3, 4, 5, 6, 7]
        let new: [Int32] = [2, 9, 3, 4, 7, 8]
        let result = try #require(LineChanges.difference(old, new, limit: 100))
        // The longest common subsequence is 2 3 4 7, so three lines go and two come: five edits.
        #expect(result.removed == [true, false, false, false, true, true, false])
        #expect(result.inserted == [false, true, false, false, false, true])
        #expect(LineChanges.difference(old, new, limit: 4) == nil, "five edits are past a limit of four")
    }
}
