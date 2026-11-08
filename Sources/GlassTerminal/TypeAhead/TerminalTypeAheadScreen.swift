//
//  TerminalTypeAheadScreen.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead's screen source (D102, 2026-11-06): words already printed above the prompt — a container ID from
//  `docker ps`, a hash from `git log`, a path, a host — offered for the word being typed once two characters of it
//  are, as iTerm2's ⌘; offers them. Nearer the prompt counts for more. `tasks/2026-11/2026-11-06_type-ahead.md`.
//

import Foundation

nonisolated enum TerminalTypeAheadScreen {
    /// Characters that end a word on screen besides blanks.
    private static let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()[]{}<>\"'`,;|=\u{0}"))
    /// Trailing punctuation that isn't part of the word (`main.` at a sentence's end, `src:` in a listing).
    private static let trailing = CharacterSet(charactersIn: ".:,!?")

    /// Words for the word being typed on `line`, from `screen`'s lines, top first.
    static func words(line: String, screen: [String]) -> [(word: String, score: Double)] {
        let word = TerminalTypeAheadEngine.currentWord(of: line).word
        guard word.count >= 2, !word.hasPrefix("-") else { return [] }
        var best: [String: Double] = [:]
        let count = max(1, screen.count)
        for (index, text) in screen.enumerated() {
            let score = 0.5 + 0.3 * Double(index + 1) / Double(count)
            for token in text.components(separatedBy: separators) {
                let token = trimmed(token)
                guard token.count >= 4, token.count <= 200, token != word, token.hasPrefix(word),
                      token.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
                best[token] = max(best[token] ?? 0, score)
            }
        }
        return best.map { ($0.key, $0.value) }.sorted { $0.score > $1.score }
    }

    private static func trimmed(_ token: String) -> String {
        var token = Substring(token)
        while let last = token.unicodeScalars.last, trailing.contains(last) { token = token.dropLast() }
        return String(token)
    }
}
