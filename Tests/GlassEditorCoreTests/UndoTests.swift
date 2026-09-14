import Foundation
import Testing
@testable import GlassEditorCore

// MARK: - Headless harness
//
// These tests deliberately do not touch `TextStorageBuffer`. Undo's contract is
// expressed entirely in `TextEdit` / `AppliedEdit` geometry, so the buffer here
// is a plain `String` that produces `AppliedEdit`s the same way real storage
// must. If these pass and the real buffer disagrees, the buffer is wrong.

/// A minimal document model: a `String` addressed in UTF-16 offsets, exactly as
/// `TextEdit.replacementRange` is defined.
private struct TextModel {
    private(set) var text: String

    init(_ text: String) {
        self.text = text
    }

    var utf16Length: Int { text.utf16.count }

    /// Applies one edit and reports what it replaced — the same `AppliedEdit`
    /// the real buffer owes the coordinator.
    @discardableResult
    mutating func apply(_ edit: TextEdit) -> AppliedEdit {
        let lower = String.Index(utf16Offset: edit.replacementRange.lowerBound, in: text)
        let upper = String.Index(utf16Offset: edit.replacementRange.upperBound, in: text)
        let replaced = String(text[lower..<upper])
        text.replaceSubrange(lower..<upper, with: edit.text)
        return AppliedEdit(edit: edit, replacedText: replaced)
    }

    /// Applies an undo step the way the engine must: one edit at a time, in
    /// order, each range resolved against the state the previous one produced.
    mutating func applyStep(_ step: UndoStep) {
        for edit in step.edits {
            _ = apply(edit)
        }
    }
}

/// A clock the tests advance by hand. Coalescing is time-dependent, and a
/// time-dependent rule tested against a real clock is a flake generator.
private final class ManualClock: UndoClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now

    func now() -> ContinuousClock.Instant {
        lock.withLock { instant }
    }

    func advance(by duration: Duration) {
        lock.withLock { instant = instant.advanced(by: duration) }
    }
}

/// Model plus coordinator, kept in lockstep. Every mutation goes through the
/// model *and* gets recorded, so `text` is always the truth the engine would
/// show and every assertion below is an exact-text assertion.
private final class Harness {
    let clock = ManualClock()
    let coordinator: UndoCoordinator
    private var model: TextModel

    init(_ initial: String = "", maximumUnitCount: Int = 1000) {
        model = TextModel(initial)
        coordinator = UndoCoordinator(clock: clock, maximumUnitCount: maximumUnitCount)
    }

    var text: String { model.text }
    var length: Int { model.utf16Length }

    func advance(_ duration: Duration) {
        clock.advance(by: duration)
    }

    func apply(_ edit: TextEdit, intent: EditIntent) {
        coordinator.record(model.apply(edit), intent: intent)
    }

    /// Records a group as one unit. Edits must arrive in application order —
    /// for a replace-all that means highest offset first, matching a buffer that
    /// applies a `TextEditBatch` back-to-front.
    func applyGroup(_ edits: [TextEdit], intent: EditIntent) {
        coordinator.record(edits.map { model.apply($0) }, intent: intent)
    }

    /// Types character by character, advancing the clock between keystrokes.
    func type(_ string: String, at offset: Int, tick: Duration = .milliseconds(50)) {
        var cursor = offset
        for character in string {
            let piece = String(character)
            apply(.insert(piece, at: cursor), intent: .typing)
            cursor += piece.utf16.count
            advance(tick)
        }
    }

    func typeAtEnd(_ string: String, tick: Duration = .milliseconds(50)) {
        type(string, at: length, tick: tick)
    }

    /// Backspaces `count` times from the end of the document.
    func deleteBackwardFromEnd(count: Int, tick: Duration = .milliseconds(50)) {
        for _ in 0..<count {
            let end = length
            apply(.delete((end - 1)..<end), intent: .deleteBackward)
            advance(tick)
        }
    }

    @discardableResult
    func undo() -> Bool {
        guard let step = coordinator.undoUnit() else { return false }
        model.applyStep(step)
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let step = coordinator.redoUnit() else { return false }
        model.applyStep(step)
        return true
    }

    func undoAll() {
        while undo() {}
    }

    func redoAll() {
        while redo() {}
    }
}

// MARK: - Tests

@Suite("Undo coalescing")
struct UndoTests {

    @Test("A typing run within the gap limit is one undo unit")
    func typingRunCoalesces() {
        let h = Harness()
        h.typeAtEnd("hello")

        #expect(h.text == "hello")
        #expect(h.coordinator.undoDepth == 1)
        #expect(h.coordinator.canUndo)
        #expect(!h.coordinator.canRedo)

        #expect(h.undo())
        #expect(h.text == "")
        #expect(!h.coordinator.canUndo)
        #expect(h.coordinator.canRedo)
    }

    @Test("A pause longer than the gap limit splits the run")
    func typingPauseSplitsRun() {
        let h = Harness()
        h.typeAtEnd("abc")
        h.advance(.seconds(2))
        h.typeAtEnd("def")

        #expect(h.text == "abcdef")
        #expect(h.coordinator.undoDepth == 2)

        #expect(h.undo())
        #expect(h.text == "abc")
        #expect(h.undo())
        #expect(h.text == "")
        #expect(!h.coordinator.canUndo)
    }

    @Test("A typed newline ends the run on both sides")
    func newlineBreaksRun() {
        let h = Harness()
        h.typeAtEnd("ab")
        h.typeAtEnd("\n")
        h.typeAtEnd("cd")

        #expect(h.text == "ab\ncd")
        // "ab" | "\n" | "cd" — the newline neither joins the run before it nor
        // lets the run after it join back.
        #expect(h.coordinator.undoDepth == 3)

        #expect(h.undo())
        #expect(h.text == "ab\n")
        #expect(h.undo())
        #expect(h.text == "ab")
        #expect(h.undo())
        #expect(h.text == "")
    }

    @Test("Typing that is not contiguous with the previous keystroke starts a unit")
    func nonContiguousTypingSplitsRun() {
        let h = Harness("hello world")
        h.type("X", at: 11)
        // Caret jumped back to the start of the line — same intent, same instant,
        // but not where the last insertion ended.
        h.type("Y", at: 0)

        #expect(h.text == "Yhello worldX")
        #expect(h.coordinator.undoDepth == 2)

        h.undoAll()
        #expect(h.text == "hello world")
    }

    @Test("A paste is atomic and never merges with surrounding typing")
    func pasteIsAtomic() {
        let h = Harness()
        h.typeAtEnd("ab")
        h.apply(.insert("XYZ", at: h.length), intent: .paste)
        h.advance(.milliseconds(50))
        h.typeAtEnd("cd")

        #expect(h.text == "abXYZcd")
        #expect(h.coordinator.undoDepth == 3)

        #expect(h.undo())
        #expect(h.text == "abXYZ")
        #expect(h.undo())
        #expect(h.text == "ab")
        #expect(h.undo())
        #expect(h.text == "")
    }

    @Test("Back-to-back pastes stay separate units")
    func consecutivePastesDoNotCoalesce() {
        let h = Harness()
        h.apply(.insert("one", at: 0), intent: .paste)
        h.advance(.milliseconds(10))
        h.apply(.insert("two", at: 3), intent: .paste)

        #expect(h.text == "onetwo")
        #expect(h.coordinator.undoDepth == 2)

        #expect(h.undo())
        #expect(h.text == "one")
        #expect(h.undo())
        #expect(h.text == "")
    }

    @Test("Replace-all is one unit and undoes to the exact prior text")
    func replaceAllIsOneUnit() {
        let original = "foo bar foo baz foo"
        let h = Harness(original)

        // Highest offset first — the order a buffer applying a TextEditBatch
        // back-to-front actually performs them in.
        h.applyGroup(
            [
                TextEdit(replacementRange: 16..<19, text: "quux"),
                TextEdit(replacementRange: 8..<11, text: "quux"),
                TextEdit(replacementRange: 0..<3, text: "quux"),
            ],
            intent: .replaceAll
        )

        #expect(h.text == "quux bar quux baz quux")
        #expect(h.coordinator.undoDepth == 1)

        #expect(h.undo())
        #expect(h.text == original)
        #expect(!h.coordinator.canUndo)

        #expect(h.redo())
        #expect(h.text == "quux bar quux baz quux")
    }

    @Test("A backspace run coalesces; a pause splits it")
    func deleteBackwardRunCoalesces() {
        let h = Harness("hello")
        h.deleteBackwardFromEnd(count: 3)

        #expect(h.text == "he")
        #expect(h.coordinator.undoDepth == 1)

        #expect(h.undo())
        #expect(h.text == "hello")

        // Same deletions, one long pause in the middle.
        let paused = Harness("hello")
        paused.deleteBackwardFromEnd(count: 2)
        paused.advance(.seconds(3))
        paused.deleteBackwardFromEnd(count: 2)

        #expect(paused.text == "h")
        #expect(paused.coordinator.undoDepth == 2)
        #expect(paused.undo())
        #expect(paused.text == "hel")
        #expect(paused.undo())
        #expect(paused.text == "hello")
    }

    @Test("Backspace and forward delete do not merge into each other")
    func mixedDeletesDoNotCoalesce() {
        let h = Harness("abcdef")
        h.apply(.delete(2..<3), intent: .deleteForward)
        h.advance(.milliseconds(10))
        h.apply(.delete(2..<3), intent: .deleteForward)
        h.advance(.milliseconds(10))
        h.apply(.delete(1..<2), intent: .deleteBackward)

        #expect(h.text == "aef")
        // deleteForward never coalesces, and it does not absorb the backspace.
        #expect(h.coordinator.undoDepth == 3)

        h.undoAll()
        #expect(h.text == "abcdef")
    }

    @Test("A remote reload is undoable but coalesces with nothing on either side")
    func remoteReloadIsABarrier() {
        let h = Harness()
        h.typeAtEnd("local")

        // The reload swaps the whole buffer. Undoing it restores the user's
        // unsaved work — the data-safety half of the barrier rule.
        h.apply(TextEdit(replacementRange: 0..<h.length, text: "remote"), intent: .remoteReload)
        h.advance(.milliseconds(10))
        h.typeAtEnd("!")

        #expect(h.text == "remote!")
        #expect(h.coordinator.undoDepth == 3)

        #expect(h.undo())
        #expect(h.text == "remote")
        #expect(h.undo())
        #expect(h.text == "local")
        #expect(h.undo())
        #expect(h.text == "")

        // Two reloads in a row are still two units.
        let twice = Harness("a")
        twice.apply(TextEdit(replacementRange: 0..<1, text: "b"), intent: .remoteReload)
        twice.advance(.milliseconds(10))
        twice.apply(TextEdit(replacementRange: 0..<1, text: "c"), intent: .remoteReload)
        #expect(twice.coordinator.undoDepth == 2)
        #expect(twice.undo())
        #expect(twice.text == "b")
        #expect(twice.undo())
        #expect(twice.text == "a")
    }

    @Test("Undo-all then redo-all reproduces the final text exactly")
    func redoRoundTrip() {
        let h = Harness("start: ")
        h.typeAtEnd("hello")
        h.advance(.seconds(2))
        h.typeAtEnd("world")
        h.apply(.insert(" <pasted>", at: h.length), intent: .paste)
        h.advance(.milliseconds(50))
        h.deleteBackwardFromEnd(count: 3)
        h.applyGroup(
            [
                TextEdit(replacementRange: 7..<12, text: "HELLO"),
                TextEdit(replacementRange: 0..<5, text: "START"),
            ],
            intent: .replaceAll
        )

        let final = h.text
        let depth = h.coordinator.undoDepth
        #expect(depth == 5)

        h.undoAll()
        #expect(h.text == "start: ")
        #expect(!h.coordinator.canUndo)
        #expect(h.coordinator.redoDepth == depth)

        h.redoAll()
        #expect(h.text == final)
        #expect(!h.coordinator.canRedo)
        #expect(h.coordinator.undoDepth == depth)

        // And the round trip is repeatable, not a one-shot.
        h.undoAll()
        #expect(h.text == "start: ")
        h.redoAll()
        #expect(h.text == final)
    }

    @Test("Recording after an undo clears redo and starts a fresh unit")
    func newEditClearsRedo() {
        let h = Harness()
        h.typeAtEnd("abc")
        h.advance(.seconds(2))
        h.typeAtEnd("def")

        #expect(h.undo())
        #expect(h.text == "abc")
        #expect(h.coordinator.canRedo)

        // No clock advance: without the undo boundary this "x" would have
        // coalesced straight into the "abc" run.
        h.typeAtEnd("x")
        #expect(h.text == "abcx")
        #expect(!h.coordinator.canRedo)
        #expect(h.coordinator.redoUnit() == nil)
        #expect(h.coordinator.undoDepth == 2)

        #expect(h.undo())
        #expect(h.text == "abc")
        #expect(h.undo())
        #expect(h.text == "")
    }

    @Test("Typing after a redo starts a new unit rather than growing the redone one")
    func typingAfterRedoStartsFreshUnit() {
        let h = Harness()
        h.typeAtEnd("abc")
        #expect(h.undo())
        #expect(h.redo())
        #expect(h.text == "abc")

        h.typeAtEnd("d")
        #expect(h.coordinator.undoDepth == 2)
        #expect(h.undo())
        #expect(h.text == "abc")
    }

    @Test("The depth cap evicts oldest units and leaves the rest consistent")
    func depthCapEvictsOldest() {
        let h = Harness(maximumUnitCount: 3)
        for index in 0..<5 {
            h.apply(.insert("\(index)", at: h.length), intent: .programmatic)
            h.advance(.milliseconds(10))
        }

        #expect(h.text == "01234")
        #expect(h.coordinator.undoDepth == 3)

        // Only "2", "3", "4" remain undoable; "0" and "1" are permanent.
        #expect(h.undo())
        #expect(h.text == "0123")
        #expect(h.undo())
        #expect(h.text == "012")
        #expect(h.undo())
        #expect(h.text == "01")
        #expect(!h.coordinator.canUndo)
        #expect(!h.undo())
        #expect(h.text == "01")

        h.redoAll()
        #expect(h.text == "01234")
        #expect(h.coordinator.undoDepth == 3)
    }

    @Test("A coalesced run stays capped as one unit against the depth limit")
    func coalescedRunCountsAsOneUnitUnderCap() {
        let h = Harness(maximumUnitCount: 2)
        h.typeAtEnd("aaaaaaaaaa")
        #expect(h.coordinator.undoDepth == 1)
        h.advance(.seconds(2))
        h.typeAtEnd("bbbbbbbbbb")
        #expect(h.coordinator.undoDepth == 2)
        h.advance(.seconds(2))
        h.typeAtEnd("cccccccccc")
        #expect(h.coordinator.undoDepth == 2)

        h.undoAll()
        #expect(h.text == "aaaaaaaaaa")
    }
}

@Suite("Coalescing policy")
struct CoalescingPolicyTests {

    private func recorded(
        _ edit: TextEdit,
        replacing replacedText: String = "",
        intent: EditIntent
    ) -> RecordedEdit {
        RecordedEdit(applied: AppliedEdit(edit: edit, replacedText: replacedText), intent: intent)
    }

    @Test("Contiguity is required, not merely proximity")
    func typingContiguity() {
        let previous = recorded(.insert("a", at: 4), intent: .typing)
        let contiguous = recorded(.insert("b", at: 5), intent: .typing)
        let gapped = recorded(.insert("b", at: 6), intent: .typing)

        #expect(CoalescingPolicy.shouldCoalesce(
            previous: previous, next: contiguous, gap: .milliseconds(20)))
        #expect(!CoalescingPolicy.shouldCoalesce(
            previous: previous, next: gapped, gap: .milliseconds(20)))
    }

    @Test("The gap limit is one second, and time never runs backward")
    func gapBoundary() {
        let previous = recorded(.insert("a", at: 0), intent: .typing)
        let next = recorded(.insert("b", at: 1), intent: .typing)

        #expect(CoalescingPolicy.shouldCoalesce(
            previous: previous, next: next, gap: .milliseconds(999)))
        #expect(CoalescingPolicy.shouldCoalesce(
            previous: previous, next: next, gap: .seconds(1)))
        #expect(!CoalescingPolicy.shouldCoalesce(
            previous: previous, next: next, gap: .milliseconds(1001)))
        #expect(!CoalescingPolicy.shouldCoalesce(
            previous: previous, next: next, gap: .milliseconds(-1)))
    }

    @Test("A multi-character insertion still coalesces if it is typed text")
    func multiUnitTypingCoalesces() {
        // A composed emoji is two UTF-16 units; the next keystroke lands at +2.
        let previous = recorded(.insert("🙂", at: 0), intent: .typing)
        let next = recorded(.insert("!", at: 2), intent: .typing)
        #expect(CoalescingPolicy.shouldCoalesce(
            previous: previous, next: next, gap: .milliseconds(10)))
    }

    @Test("Intent mismatch always wins over geometry")
    func intentMismatch() {
        let previous = recorded(.insert("a", at: 0), intent: .typing)
        let next = recorded(.insert("b", at: 1), intent: .completion)
        #expect(!CoalescingPolicy.shouldCoalesce(
            previous: previous, next: next, gap: .milliseconds(1)))
    }

    @Test("Backspace coalesces leftward only")
    func deleteBackwardDirection() {
        let previous = recorded(.delete(4..<5), replacing: "o", intent: .deleteBackward)
        let leftward = recorded(.delete(3..<4), replacing: "l", intent: .deleteBackward)
        let rightward = recorded(.delete(5..<6), replacing: "!", intent: .deleteBackward)

        #expect(CoalescingPolicy.shouldCoalesce(
            previous: previous, next: leftward, gap: .milliseconds(20)))
        #expect(!CoalescingPolicy.shouldCoalesce(
            previous: previous, next: rightward, gap: .milliseconds(20)))
    }

    @Test("A deleted newline ends a backspace run")
    func deletedNewlineBreaksRun() {
        let previous = recorded(.delete(4..<5), replacing: "\n", intent: .deleteBackward)
        let next = recorded(.delete(3..<4), replacing: "o", intent: .deleteBackward)
        #expect(!CoalescingPolicy.shouldCoalesce(
            previous: previous, next: next, gap: .milliseconds(20)))
    }

    @Test("Intents that own their unit never coalesce with themselves")
    func selfContainedIntents() {
        for intent in [EditIntent.paste, .replaceAll, .completion, .drop,
                       .indentation, .programmatic, .deleteForward, .remoteReload] {
            let previous = recorded(.insert("a", at: 0), intent: intent)
            let next = recorded(.insert("b", at: 1), intent: intent)
            #expect(
                !CoalescingPolicy.shouldCoalesce(
                    previous: previous, next: next, gap: .milliseconds(1)),
                "\(intent) must always be its own unit"
            )
        }
    }
}
