#if os(macOS)

import Testing
import Foundation
@testable import GlassEditorUI
@testable import GlassEditorCore

/// M-6 (pen-sec): `wordPrefix` must be bounded, not quadratic in the length of a
/// giant single line. These tests assert correctness on ordinary input and that
/// a caret at the end of a huge single-line document returns promptly with a
/// bounded prefix rather than materialising the whole line.
@MainActor
@Suite("wordPrefix is correct and bounded (M-6)")
struct WordPrefixTests {

    private func model(_ content: String) -> GlassEditorModel {
        GlassEditorModel(
            snapshot: DocumentLoader.make(content: content, origin: .ephemeral(id: UUID())),
            language: .sql
        )
    }

    @Test("returns the word immediately before the caret")
    func ordinaryPrefix() {
        let m = model("SELECT count")
        #expect(m.wordPrefix(before: m.utf16Length) == "count")
        #expect(m.wordPrefix(before: 6) == "SELECT")
    }

    @Test("stops at a non-word boundary")
    func stopsAtBoundary() {
        let m = model("a.bcd")
        #expect(m.wordPrefix(before: m.utf16Length) == "bcd")
    }

    @Test("empty at the document start and after a boundary")
    func emptyCases() {
        let m = model("x = ")
        #expect(m.wordPrefix(before: 0) == "")
        #expect(m.wordPrefix(before: m.utf16Length) == "")
    }

    @Test("a huge single-line document returns a bounded prefix promptly")
    func boundedOnHugeLine() {
        // One 2 MB line of word characters. The old implementation materialised
        // the whole line and front-inserted per char — quadratic. The bounded
        // window must return quickly with a capped prefix.
        let huge = String(repeating: "a", count: 2_000_000)
        let m = model(huge)
        let clock = ContinuousClock()
        let start = clock.now
        let prefix = m.wordPrefix(before: m.utf16Length)
        let elapsed = start.duration(to: clock.now)
        #expect(prefix.count <= 256, "prefix was not bounded: \(prefix.count) chars")
        #expect(prefix.allSatisfy { $0 == "a" })
        #expect(elapsed < .seconds(1), "wordPrefix took \(elapsed) on a huge line — likely still quadratic")
    }
}

#endif
