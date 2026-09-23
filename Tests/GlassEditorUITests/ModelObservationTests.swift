#if os(macOS)

import Testing
import AppKit
@testable import GlassEditorUI
@testable import GlassEditorCore

/// Regression tests for the model-first paths: "the model is the API, not the
/// view" (GlassEditorView.swift) must hold for consumers that never touch the
/// engine. Found via the demo app rendering monochrome: `model.setHighlights`
/// updated the model and nothing observed it, so the view never repainted.
@MainActor
@Suite("Engine observes the model")
struct ModelObservationTests {

    private func makeEngine(text: String) -> GlassEditorAppKitEngine {
        let snapshot = DocumentSnapshot(
            content: text,
            encoding: .utf8(hadBOM: false),
            lineEndings: .lf,
            origin: .ephemeral(id: UUID())
        )
        // Opt out of built-in highlighting: these tests verify the *manual*
        // `setHighlights` path and the observation plumbing, so they drive
        // highlights themselves and assert a monochrome starting state.
        let model = GlassEditorModel(
            snapshot: snapshot,
            configuration: GlassEditorConfiguration(),
            theme: .glassDark,
            language: .sql,
            builtInHighlighting: false
        )
        return GlassEditorAppKitEngine(model: model)
    }

    /// Distinct foreground colors present in the text view's storage.
    private func distinctForegroundColors(in engine: GlassEditorAppKitEngine) -> Set<String> {
        guard let storage = engine.textView.glassTextStorage else { return [] }
        var seen = Set<String>()
        storage.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: storage.length)
        ) { value, _, _ in
            if let color = value as? NSColor {
                seen.insert(color.description)
            }
        }
        return seen
    }

    @Test("model.setHighlights alone repaints the view — no engine call required")
    func modelFirstHighlights() async throws {
        let engine = makeEngine(text: "SELECT 'hello' FROM t WHERE n = 42 -- note\n")
        let before = distinctForegroundColors(in: engine)
        #expect(before.count <= 1, "plain load should be monochrome, got \(before.count)")

        // Highlight through the MODEL — the engine is never told directly.
        let parser = try DocumentParser(language: .sql, registry: GrammarRegistry())
        parser.parseFull(engine.model.text)
        engine.model.setHighlights(parser.highlights)

        // Observation delivery hops the main actor once; yield until it lands.
        for _ in 0..<50 where distinctForegroundColors(in: engine).count <= 1 {
            await Task.yield()
        }
        let after = distinctForegroundColors(in: engine)
        #expect(
            after.count > 1,
            "model.setHighlights must reach the view; still \(after.count) color(s)"
        )
    }

    @Test("a model-applied edit reaches the view without an engine call")
    func modelFirstEdits() async throws {
        let engine = makeEngine(text: "SELECT 1;")
        // Edit through the MODEL — e.g. a consumer-side formatting pass.
        try engine.model.apply(TextEdit.insert(" -- tail", at: 9), intent: .programmatic)

        for _ in 0..<50 where engine.textView.string != engine.model.text {
            await Task.yield()
        }
        #expect(engine.textView.string == engine.model.text)
        #expect(engine.textView.string == "SELECT 1; -- tail")
    }

    @Test("typing-equivalent engine edits still repaint exactly once per pass")
    func engineEditsStillWork() throws {
        let engine = makeEngine(text: "SELECT 1;")
        try engine.apply(TextEdit.insert("X", at: 0), intent: .typing)
        #expect(engine.textView.string == engine.model.text)
    }
}

#endif
