//
//  TerminalTypeAheadEngine.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06): which command to offer for the line being typed. Every source gives whole
//  commands that start with what's typed; this scores them, keeps the best for the grey text and the next few for
//  the chips. `tasks/2026-11/2026-11-06_type-ahead.md`, "Sources".
//

import Foundation

nonisolated enum TerminalTypeAheadSource: String, Sendable, Codable, CaseIterable {
    /// Commands run on this machine, seen by the app.
    case history
    /// Read from the machine's own history file.
    case imported
    case snippet
    /// Machines and databases in the library.
    case library
    /// Branches, files, package scripts and make targets in the folder.
    case folder
    /// Common tools' subcommands and options.
    case tool
    /// The programs in the machine's PATH folders and the shell's own commands, for a command's first word.
    case commands
    /// Words shown on screen.
    case screen
    /// The on-device model's guess.
    case assistant
}

nonisolated struct TerminalTypeAheadCandidate: Equatable, Sendable {
    let command: String
    let score: Double
    let source: TerminalTypeAheadSource
}

/// What the ranking knows besides the line: where, after what, when.
nonisolated struct TerminalTypeAheadContext: Equatable, Sendable {
    var folder: String?
    var previousCommand: String?
    var now: Date = Date()
}

nonisolated enum TerminalTypeAheadEngine {
    // MARK: - Candidates

    /// Commands run here that start with `typed`, scored by how often and how lately, higher when they ran in this
    /// folder or after the command just run, lower when they last failed. Those only read from the machine's own
    /// history count for less than those seen run.
    static func historyCandidates(typed: String, records: [TerminalCommandRecord],
                                  context: TerminalTypeAheadContext) -> [TerminalTypeAheadCandidate] {
        records.compactMap { record in
            guard record.command.hasPrefix(typed), record.command != typed else { return nil }
            return TerminalTypeAheadCandidate(command: record.command, score: score(record, context: context),
                                              source: record.imported ? .imported : .history)
        }
    }

    static func score(_ record: TerminalCommandRecord, context: TerminalTypeAheadContext) -> Double {
        let days = max(0, context.now.timeIntervalSince(record.lastUsed)) / 86_400
        var score = log2(1 + Double(record.count)) + 2 / (1 + days)
        if let folder = context.folder, record.folders[folder] != nil { score += 1.5 }
        if let previous = context.previousCommand, record.after[previous] != nil { score += 1 }
        if let status = record.lastStatus, status != 0 { score -= 0.75 }
        return record.imported ? score * 0.6 : score
    }

    /// Snippets whose command starts with `typed`, by how often and how lately they were used.
    static func snippetCandidates(typed: String, snippets: [(command: String, useCount: Int, lastUsed: Date?)],
                                  context: TerminalTypeAheadContext) -> [TerminalTypeAheadCandidate] {
        snippets.compactMap { snippet in
            guard snippet.command.hasPrefix(typed), snippet.command != typed,
                  !snippet.command.contains("\n") else { return nil }
            var score = 1 + log2(1 + Double(snippet.useCount)) * 0.5
            if let used = snippet.lastUsed {
                score += 1 / (1 + max(0, context.now.timeIntervalSince(used)) / 86_400)
            }
            return TerminalTypeAheadCandidate(command: snippet.command, score: score, source: .snippet)
        }
    }

    /// The line with its last word completed by each of `words` that starts with it: what word-by-word sources
    /// (branches, files, hosts, a tool's options) offer.
    static func wordCandidates(typed: String, words: [(word: String, score: Double)],
                               source: TerminalTypeAheadSource) -> [TerminalTypeAheadCandidate] {
        let (base, word) = currentWord(of: typed)
        return words.compactMap { candidate in
            guard candidate.word.hasPrefix(word), candidate.word != word else { return nil }
            return TerminalTypeAheadCandidate(command: base + candidate.word, score: candidate.score, source: source)
        }
    }

    /// The line up to the word being typed, and that word (empty right after a space). A space inside quotes or
    /// after a backslash is part of the word.
    static func currentWord(of typed: String) -> (base: String, word: String) {
        var quote: Character?
        var escaped = false
        var wordStart = typed.startIndex
        var index = typed.startIndex
        while index < typed.endIndex {
            let character = typed[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == " " || character == "\t" {
                wordStart = typed.index(after: index)
            }
            index = typed.index(after: index)
        }
        return (String(typed[..<wordStart]), String(typed[wordStart...]))
    }

    // MARK: - Choosing

    /// The best candidate, for the grey text (only once something is typed), and the best `choices` distinct
    /// commands, for the chips (also for an empty line: what usually comes next).
    static func choose(typed: String, candidates: [TerminalTypeAheadCandidate],
                       choices: Int = 3) -> (best: TerminalTypeAheadCandidate?, choices: [TerminalTypeAheadCandidate]) {
        var seen: Set<String> = []
        var ranked: [TerminalTypeAheadCandidate] = []
        for candidate in candidates.sorted(by: { $0.score != $1.score ? $0.score > $1.score : $0.command < $1.command })
        where candidate.command.hasPrefix(typed) && candidate.command != typed && !seen.contains(candidate.command) {
            seen.insert(candidate.command)
            ranked.append(candidate)
        }
        return (typed.isEmpty ? nil : ranked.first, Array(ranked.prefix(choices)))
    }
}
