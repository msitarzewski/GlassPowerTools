import Testing
import Foundation
@testable import GlassEditorUI
import GlassEditorCore

/// A clock the test moves by hand, so undo coalescing is asserted rather than
/// timed. `UndoCoordinator` reads no ambient clock, which is what makes this
/// possible (`UndoCoordinator.swift:5–13`).
final class ManualUndoClock: UndoClock, @unchecked Sendable {
    private var current = ContinuousClock.now

    func now() -> ContinuousClock.Instant { current }

    func advance(by duration: Duration) {
        current = current.advanced(by: duration)
    }
}

@MainActor
private func makeModel(
    _ content: String,
    clock: any UndoClock = ContinuousUndoClock(),
    configuration: GlassEditorConfiguration = GlassEditorConfiguration()
) -> GlassEditorModel {
    GlassEditorModel(
        snapshot: DocumentLoader.make(content: content, origin: .ephemeral(id: UUID())),
        configuration: configuration,
        undoClock: clock
    )
}

@Suite("GlassEditorModel")
@MainActor
struct ModelTests {

    // MARK: - Round trips

    @Test("edit → undo → redo round-trips the text exactly")
    func editUndoRedoRoundTrip() throws {
        let model = makeModel("SELECT * FROM users")
        let original = model.text

        try model.apply(TextEdit.insert(" WHERE id = 1", at: 19), intent: .typing)
        #expect(model.text == "SELECT * FROM users WHERE id = 1")

        #expect(model.undo())
        #expect(model.text == original)

        #expect(model.redo())
        #expect(model.text == "SELECT * FROM users WHERE id = 1")

        #expect(model.undo())
        #expect(model.text == original)
        #expect(model.canUndo == false)
    }

    @Test("a typing run coalesces into one undo unit through the model")
    func typingRunCoalesces() throws {
        let clock = ManualUndoClock()
        let model = makeModel("", clock: clock)

        for (index, character) in "SELECT".enumerated() {
            try model.apply(TextEdit.insert(String(character), at: index), intent: .typing)
            clock.advance(by: .milliseconds(40))
        }
        #expect(model.text == "SELECT")

        // Six keystrokes inside the run gap are one unit.
        #expect(model.undo())
        #expect(model.text == "")
        #expect(model.canUndo == false)
    }

    @Test("a pause longer than the run gap splits the undo unit")
    func typingRunSplitsAtPause() throws {
        let clock = ManualUndoClock()
        let model = makeModel("", clock: clock)

        try model.apply(TextEdit.insert("abc", at: 0), intent: .typing)
        clock.advance(by: CoalescingPolicy.maximumRunGap + .milliseconds(1))
        try model.apply(TextEdit.insert("def", at: 3), intent: .typing)

        #expect(model.text == "abcdef")
        #expect(model.undo())
        #expect(model.text == "abc")
        #expect(model.undo())
        #expect(model.text == "")
    }

    @Test("a batch is applied and undone as one unit, in the order the buffer applied it")
    func batchIsOneUndoUnit() throws {
        let model = makeModel("aaa bbb ccc")
        // Pre-batch ranges, deliberately listed front-to-back — the buffer
        // applies them back-to-front and reports them in that order, which is
        // what the undo coordinator must receive.
        let batch = TextEditBatch(edits: [
            TextEdit(replacementRange: 0..<3, text: "XXX"),
            TextEdit(replacementRange: 8..<11, text: "ZZZ"),
        ])
        let applied = try model.apply(batch, intent: .replaceAll)

        #expect(model.text == "XXX bbb ZZZ")
        // Application order is highest-offset-first.
        #expect(applied.map(\.edit.replacementRange.lowerBound) == [8, 0])

        #expect(model.undo())
        #expect(model.text == "aaa bbb ccc")
        #expect(model.canUndo == false)
    }

    // MARK: - Dirty tracking

    @Test("isDirty tracks the buffer against the last clean content")
    func dirtyTransitions() throws {
        let model = makeModel("hello")
        #expect(model.isDirty == false)

        try model.apply(TextEdit.insert("!", at: 5), intent: .typing)
        #expect(model.isDirty == true)

        // Undoing back to the opened content is clean again — the flag is exact,
        // not sticky.
        #expect(model.undo())
        #expect(model.isDirty == false)

        try model.apply(TextEdit.insert("?", at: 5), intent: .typing)
        #expect(model.isDirty == true)
        model.markClean()
        #expect(model.isDirty == false)
        #expect(model.snapshot.content == "hello?")
    }

    @Test("a same-length edit is still detected as dirty")
    func dirtyDetectsEqualLengthChange() throws {
        let model = makeModel("abc")
        try model.apply(TextEdit(replacementRange: 0..<3, text: "xyz"), intent: .typing)
        #expect(model.utf16Length == 3)
        #expect(model.isDirty == true)
    }

    // MARK: - Highlights and surface

    @Test("setHighlights and a surface change re-resolve the attributed output")
    func highlightsAndSurfaceReResolve() {
        let model = makeModel("SELECT 1")
        model.setHighlights([
            HighlightRun(range: 0..<6, role: .keyword),
            HighlightRun(range: 7..<8, role: .number),
        ])

        func render() -> NSAttributedString {
            AttributedAssembly.attributedString(
                text: model.text,
                runs: model.highlightRuns,
                theme: model.theme,
                surface: model.surfaceCondition,
                configuration: model.configuration
            )
        }

        let opaque = render()
        let keywordOpaque = opaque.attribute(
            .foregroundColor, at: 0, effectiveRange: nil
        ) as? PlatformColor
        let numberOpaque = opaque.attribute(
            .foregroundColor, at: 7, effectiveRange: nil
        ) as? PlatformColor
        #expect(keywordOpaque != nil)
        #expect(numberOpaque != nil)
        #expect(keywordOpaque != numberOpaque)

        // Same runs, thin glass: `ContrastAdapter` has to move the colors, so the
        // rendered output must differ.
        model.updateSurface(
            SurfaceCondition(windowOpacity: 0.2, backing: .material(.ultraThin), ambient: .unknown)
        )
        let translucent = render()
        let keywordTranslucent = translucent.attribute(
            .foregroundColor, at: 0, effectiveRange: nil
        ) as? PlatformColor
        #expect(keywordTranslucent != keywordOpaque)
    }

    // MARK: - Find and replace

    @Test("replace-all through the model mutates correctly and is one undo unit")
    func replaceAllIsOneUndoUnit() throws {
        let model = makeModel("cat cat cat")
        let query = FindQuery(pattern: "cat", kind: .literal, caseSensitive: true)

        let replaced = try model.replaceAll(of: query, with: "dog")
        #expect(replaced == 3)
        #expect(model.text == "dog dog dog")
        #expect(model.newestUndoIntent == .replaceAll)

        #expect(model.undo())
        #expect(model.text == "cat cat cat")
        #expect(model.canUndo == false)
    }

    @Test("replace-all with a length-changing replacement stays consistent")
    func replaceAllWithLengthChange() throws {
        let model = makeModel("a b a b a")
        let replaced = try model.replaceAll(
            of: FindQuery(pattern: "a", kind: .literal, caseSensitive: true),
            with: "LONGER"
        )
        #expect(replaced == 3)
        #expect(model.text == "LONGER b LONGER b LONGER")
        #expect(model.undo())
        #expect(model.text == "a b a b a")
    }

    @Test("find uses returned ranges, which case folding can lengthen")
    func caseInsensitiveMatchLengthCanDiffer() throws {
        // Literal case-insensitive matching applies canonical equivalence, so the
        // matched range is longer than the pattern here. Anything computing
        // `pattern.utf16.count` instead would corrupt the document.
        let model = makeModel("Grüße STRASSE")
        let matches = try model.matches(
            of: FindQuery(pattern: "strasse", kind: .literal, caseSensitive: false)
        )
        #expect(matches.count == 1)
        if let hit = matches.first {
            #expect(try model.substring(in: hit) == "STRASSE")
        }
    }

    @Test("replaceNext replaces exactly one match and reports where it landed")
    func replaceNextReplacesOne() throws {
        let model = makeModel("one two one")
        let query = FindQuery(pattern: "one", kind: .literal, caseSensitive: true)
        let landed = try model.replaceNext(of: query, with: "1", after: 0)
        #expect(model.text == "1 two one")
        #expect(landed == 0..<1)
    }

    // MARK: - Reload

    @Test("a remote reload is undoable and clears the dirty flag")
    func remoteReloadIsUndoable() throws {
        let model = makeModel("local edits")
        try model.apply(TextEdit.insert("!", at: 11), intent: .typing)
        #expect(model.isDirty == true)

        let reloaded = DocumentLoader.make(content: "remote content", origin: .ephemeral(id: UUID()))
        try model.adoptReloadedContent(reloaded)
        #expect(model.text == "remote content")
        #expect(model.isDirty == false)

        // Undoing a reload restores the pre-reload buffer — a data-safety
        // guarantee, not a convenience (`EditIntent.isBarrier`).
        #expect(model.undo())
        #expect(model.text == "local edits!")
    }

    // MARK: - Lines and providers

    @Test("line indexing follows the buffer's trailing-terminator convention")
    func lineIndexing() {
        let model = makeModel("one\ntwo\nthree\n")
        #expect(model.lineCount == 4)
        #expect(model.lineIndex(forUTF16Offset: 0) == 0)
        #expect(model.lineIndex(forUTF16Offset: 4) == 1)
        #expect(model.lineIndex(forUTF16Offset: 14) == 3)
    }

    @Test("the completion prefix uses the shared word-character rule")
    func completionPrefix() {
        let model = makeModel("SELECT * FROM user_tab")
        #expect(model.wordPrefix(before: 22) == "user_tab")
        #expect(model.wordPrefix(before: 9) == "")
    }

    @Test("providers are optional and their absence is not an error")
    func absentProvidersReturnEmpty() async throws {
        let model = makeModel("SELECT 1;")
        #expect(try await model.statementSpans().isEmpty)
        #expect(try await model.completions().isEmpty)
        #expect(try await model.diagnostics().isEmpty)
    }

    @Test("a statement provider's spans reach the model unchanged")
    func statementProviderSpansPassThrough() async throws {
        struct FixedSpans: StatementBoundaryProvider {
            func statements(in snapshot: String, language: LanguageID) async throws -> [StatementSpan] {
                [StatementSpan(id: 0, range: 0..<9)]
            }
        }
        let model = makeModel("SELECT 1;")
        model.statementBoundaryProvider = FixedSpans()
        let spans = try await model.statementSpans()
        #expect(spans == [StatementSpan(id: 0, range: 0..<9)])
    }
}
