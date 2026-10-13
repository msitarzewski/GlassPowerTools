import Testing
import Foundation
import SwiftTreeSitter
@testable import GlassEditorCore

/// Tier 3 (2026-10-12): tree-sitter 0.25 numbers the capture lists of matches in progress in
/// 16 bits, and nothing bounded how many there could be. See `HighlightExtractor.matchLimit`.
@MainActor
@Suite("Highlighting bounds the matches in progress")
struct QueryMatchLimitTests {
    /// A pattern that waits for a later sibling keeps one match in progress per earlier candidate.
    /// Over a long enough array that passes 65,535 — the overflow — and long before that, the
    /// time grows faster than the array: 2,000 numbers took 32 s in a debug build without a
    /// limit, 1.4 s with it. The bound here is generous; without the limit it is far exceeded.
    @Test("A pattern waiting on a later sibling over a long array finishes, and finds nothing")
    func longArrayWithAPendingPattern() throws {
        let language = try #require(try GrammarRegistry().grammar(for: .json).treeSitterLanguage)
        let query = try Query(language: language, data: Data("(array (number) @n (string))".utf8))
        let parser = Parser()
        try parser.setLanguage(language)
        let text = "[" + Array(repeating: "1", count: 2_000).joined(separator: ",") + "]"
        let tree = try #require(parser.parse(text))

        let clock = ContinuousClock()
        var runs: [HighlightRun] = []
        let elapsed = clock.measure {
            runs = HighlightExtractor.runs(in: tree, query: query, language: .json, utf16: Array(text.utf16))
        }
        #expect(elapsed < .seconds(10), "took \(elapsed)")
        #expect(runs == [HighlightRun(range: 0..<text.utf16.count, role: .plain)], "the pattern never completes")
    }
}
