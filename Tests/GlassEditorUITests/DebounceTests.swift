import Testing
import Foundation
@testable import GlassEditorUI
import GlassEditorCore

#if canImport(AppKit) && os(macOS)
import AppKit
#endif

@Suite("Highlight debounce")
@MainActor
struct DebounceTests {

    // MARK: - The box itself

    @Test("a burst of schedules collapses into one run")
    func burstCollapsesToOneRun() {
        let box = DebounceBox(milliseconds: 75)
        var runs = 0
        for _ in 0..<10 {
            box.schedule { runs += 1 }
        }
        #expect(runs == 0)
        #expect(box.hasPendingWork)

        box.flush()
        #expect(runs == 1)
        #expect(box.hasPendingWork == false)
    }

    @Test("flushing with nothing pending is a no-op")
    func flushWithoutWork() {
        let box = DebounceBox(milliseconds: 75)
        box.flush()
        #expect(box.hasPendingWork == false)
    }

    @Test("cancel discards pending work rather than running it")
    func cancelDiscards() {
        let box = DebounceBox(milliseconds: 75)
        var runs = 0
        box.schedule { runs += 1 }
        box.cancel()
        box.flush()
        #expect(runs == 0)
    }

    @Test("the interval comes from the configuration, not a literal")
    func intervalFromConfiguration() {
        var configuration = GlassEditorConfiguration()
        #expect(configuration.highlightDebounceMilliseconds == 75)
        #expect(DebounceBox(configuration: configuration).delay == .milliseconds(75))

        configuration.highlightDebounceMilliseconds = 200
        #expect(DebounceBox(configuration: configuration).delay == .milliseconds(200))
    }

    @Test("it does actually fire on its own after the interval")
    func firesAfterTheInterval() async {
        let box = DebounceBox(milliseconds: 5)
        var runs = 0
        box.schedule { runs += 1 }

        // Poll rather than wait a fixed budget. Every other test in this target
        // is `@MainActor` too, so under parallel execution the main actor can be
        // busy for far longer than the debounce interval — a single fixed sleep
        // measures scheduler contention, not the box. The claim under test is
        // "it fires without anyone calling flush", and polling asserts exactly
        // that while staying fast when the actor is free.
        for _ in 0..<200 {
            if runs > 0 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(runs == 1)
        #expect(box.hasPendingWork == false)
    }

    // MARK: - Through the AppKit coordinator

    #if canImport(AppKit) && os(macOS)

    private func makeEngine(_ content: String) -> GlassEditorAppKitEngine {
        GlassEditorAppKitEngine(
            model: GlassEditorModel(
                snapshot: DocumentLoader.make(content: content, origin: .ephemeral(id: UUID()))
            )
        )
    }

    private func notifyTextDidChange(_ engine: GlassEditorAppKitEngine) {
        engine.coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: engine.textView)
        )
    }

    @Test("two rapid edits produce one highlight pass after a flush")
    func twoEditsOnePass() {
        let engine = makeEngine("SELECT")
        let coordinator = engine.coordinator
        let before = coordinator.highlightPassCount

        // Two keystrokes in quick succession. `insertText` is the real AppKit
        // entry point: it consults the delegate's `shouldChangeTextIn` and then
        // posts `textDidChange`, so driving it exercises the whole chain rather
        // than a hand-assembled imitation of it.
        engine.textView.insertText(" ", replacementRange: NSRange(location: 6, length: 0))
        engine.textView.insertText("1", replacementRange: NSRange(location: 7, length: 0))

        #expect(engine.model.text == "SELECT 1")
        #expect(engine.textView.string == "SELECT 1")
        #expect(coordinator.forwardedEditCount == 2)

        // Nothing has been repainted yet — that is the debounce.
        #expect(coordinator.highlightPassCount == before)
        #expect(coordinator.highlightDebounce.hasPendingWork)

        coordinator.flushPendingHighlight()
        #expect(coordinator.highlightPassCount == before + 1)
    }

    @Test("an edit during marked text defers the pass instead of rewriting attributes")
    func markedTextDefersThePass() {
        let engine = makeEngine("SELECT")
        let coordinator = engine.coordinator
        let textView = engine.textView

        // Start a composition. `setMarkedText` is the real IME entry point, so
        // `hasMarkedText()` is true for the same reason it would be on device.
        textView.setMarkedText(
            "か",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 6, length: 0)
        )
        #expect(textView.hasMarkedText())

        let before = coordinator.highlightPassCount
        notifyTextDidChange(engine)

        // No pass was even scheduled: rewriting attributes now would replace the
        // marked-text attributes the input method is relying on
        // (INTEGRATION.md A3 — "correctness, not perf").
        #expect(coordinator.highlightDebounce.hasPendingWork == false)
        coordinator.flushPendingHighlight()
        #expect(coordinator.highlightPassCount == before)

        // Committing the composition lets highlighting resume.
        textView.unmarkText()
        #expect(textView.hasMarkedText() == false)
        notifyTextDidChange(engine)
        #expect(coordinator.highlightDebounce.hasPendingWork)
        coordinator.flushPendingHighlight()
        #expect(coordinator.highlightPassCount == before + 1)
    }

    @Test("a pass scheduled before composition began does not land during it")
    func inFlightPassIsCancelledByComposition() {
        let engine = makeEngine("SELECT")
        let coordinator = engine.coordinator
        let textView = engine.textView

        notifyTextDidChange(engine)
        #expect(coordinator.highlightDebounce.hasPendingWork)

        textView.setMarkedText(
            "か",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 6, length: 0)
        )
        notifyTextDidChange(engine)

        // The cancel is unconditional and happens before the marked-text guard,
        // so the earlier scheduled pass is gone rather than merely delayed.
        #expect(coordinator.highlightDebounce.hasPendingWork == false)
    }

    @Test("a pass computed for text that has since changed is dropped")
    func stalePassIsDropped() throws {
        let engine = makeEngine("SELECT")
        let coordinator = engine.coordinator
        let before = coordinator.highlightPassCount

        coordinator.scheduleHighlight(for: engine.textView)
        // The document moves on before the timer lands.
        try engine.apply(TextEdit.insert(" 1", at: 6), intent: .typing)
        let afterSync = coordinator.highlightPassCount

        coordinator.flushPendingHighlight()
        // The stale closure ran and declined to do anything; only the sync's own
        // pass counted.
        #expect(coordinator.highlightPassCount == afterSync)
        #expect(afterSync > before)
    }

    @Test("setHighlightRuns during composition is deferred, not applied")
    func setHighlightRunsDefersUnderMarkedText() {
        let engine = makeEngine("SELECT")
        let coordinator = engine.coordinator

        engine.textView.setMarkedText(
            "か",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 6, length: 0)
        )
        let before = coordinator.highlightPassCount
        engine.setHighlightRuns([HighlightRun(range: 0..<6, role: .keyword)])

        #expect(coordinator.highlightPassCount == before)
        #expect(engine.model.highlightRuns.count == 1)
    }

    #endif
}
