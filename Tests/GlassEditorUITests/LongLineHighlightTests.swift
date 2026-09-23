import Testing
import Foundation
@testable import GlassEditorUI
import GlassEditorCore

/// A line longer than 20,000 characters is drawn without syntax colour (2026-09-23: a one-line
/// logo SVG on oscar froze the Mac while TextKit walked its colour runs).
@Suite("Long lines are left uncoloured")
@MainActor
struct LongLineHighlightTests {
    private func run(_ lower: Int, _ upper: Int) -> HighlightRun { HighlightRun(range: lower..<upper, role: .keyword) }

    @Test("Runs touching an excluded line go; runs on other lines stay")
    func filter() {
        let runs = [run(0, 3), run(10, 20), run(25, 30), run(95, 105), run(120, 125)]
        let kept = GlassEditorModel.runs(runs, outside: [8..<100])
        #expect(kept.map(\.range) == [0..<3, 120..<125])
    }

    @Test("A document with one enormous line keeps colour on its short lines only")
    func model() throws {
        let long = "<path d=\"" + String(repeating: "L1 2 ", count: 5_000) + "\"/>"   // ~25,000 characters
        let text = "<svg>\n" + long + "\n</svg>\n"
        let snapshot = DocumentSnapshot(content: text, encoding: .utf8(hadBOM: false),
                                        lineEndings: .lf, origin: .ephemeral(id: UUID()))
        let model = GlassEditorModel(snapshot: snapshot, language: .plaintext, builtInHighlighting: false)
        let longLine = model.lineRange(ofLine: 1)
        #expect(longLine.count > GlassEditorModel.longLineHighlightLimit)
        model.setHighlights([run(0, 4), run(longLine.lowerBound + 1, longLine.lowerBound + 5), run(longLine.upperBound + 1, longLine.upperBound + 4)])
        #expect(model.highlightRuns.map(\.range) == [0..<4, (longLine.upperBound + 1)..<(longLine.upperBound + 4)])
    }

    @Test("An ordinary document keeps every run")
    func ordinary() {
        let snapshot = DocumentSnapshot(content: "let a = 1\n", encoding: .utf8(hadBOM: false),
                                        lineEndings: .lf, origin: .ephemeral(id: UUID()))
        let model = GlassEditorModel(snapshot: snapshot, language: .plaintext, builtInHighlighting: false)
        model.setHighlights([run(0, 3), run(4, 5)])
        #expect(model.highlightRuns.count == 2)
    }
}
