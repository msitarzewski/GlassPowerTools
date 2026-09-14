#if os(macOS)

import Testing
import Foundation
@testable import GlassEditorUI
@testable import GlassEditorCore

/// The batteries-included highlighting path: building a `GlassEditorModel`
/// (default `builtInHighlighting: true`) colours the document with no consumer
/// wiring — the gap that previously shipped plain-text editors.
@MainActor
@Suite("Built-in syntax highlighting")
struct BuiltInHighlightingTests {

    private func model(_ text: String, language: LanguageID, builtIn: Bool = true) -> GlassEditorModel {
        GlassEditorModel(
            snapshot: DocumentLoader.make(content: text, origin: .ephemeral(id: UUID())),
            language: language,
            builtInHighlighting: builtIn
        )
    }

    private func settle(until condition: () -> Bool, turns: Int = 80) async {
        for _ in 0..<turns {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test("a model highlights SQL by default, with no setHighlights call")
    func defaultHighlightsSQL() async {
        let m = model("SELECT id FROM users WHERE n = 42;", language: .sql)
        await settle(until: { m.highlightRuns.contains { $0.role == .keyword } })
        #expect(m.highlightRuns.contains { $0.role == .keyword }, "SELECT/FROM/WHERE should be keywords")
        #expect(m.highlightRuns.contains { $0.role == .number }, "42 should be a number")
    }

    @Test("a model highlights JSON by default — the glassdb Phase-1 case")
    func defaultHighlightsJSON() async {
        let m = model(#"{"name": "chaos", "count": 3, "ok": true}"#, language: .json)
        await settle(until: { m.highlightRuns.count > 1 })
        #expect(m.highlightRuns.contains { $0.role == .string })
        #expect(m.highlightRuns.contains { $0.role == .number })
    }

    @Test("highlighting updates after an edit")
    func updatesAfterEdit() async {
        let m = model("SELECT 1;", language: .sql)
        await settle(until: { !m.highlightRuns.isEmpty })
        // Insert another keyword; the run set should grow to cover it.
        try? m.apply(TextEdit.insert(" FROM t WHERE x = 9", at: 8), intent: .typing)
        await settle(until: { m.highlightRuns.contains { $0.role == .keyword && $0.range.lowerBound > 8 } })
        #expect(
            m.highlightRuns.contains { $0.role == .keyword && $0.range.lowerBound > 8 },
            "the inserted FROM/WHERE should have been highlighted after reparse"
        )
    }

    @Test("opting out leaves the document unhighlighted until driven manually")
    func optOutStaysPlain() async {
        let m = model("SELECT 1;", language: .sql, builtIn: false)
        // Give any stray async work a chance; there should be none.
        for _ in 0..<20 { await Task.yield() }
        #expect(m.highlightRuns.isEmpty, "opt-out must not auto-highlight")
    }

    @Test("plaintext produces a single plain cover run without error")
    func plaintextCovers() async {
        let m = model("just some text\nwith two lines", language: .plaintext)
        await settle(until: { !m.highlightRuns.isEmpty })
        #expect(m.highlightRuns.allSatisfy { $0.role == .plain })
    }
}

#endif
