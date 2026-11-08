//
//  TerminalHistoryImport.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06): a machine's own shell history, read into the commands kept for it so suggestions
//  start full, when the person asks (Settings ▸ Suggestions ▸ Import). zsh's, bash's and fish's files where each
//  usually is, through the same filter as anything run here. `tasks/2026-11/2026-11-06_type-ahead.md`, source 2.
//

import Foundation

@MainActor
enum TerminalHistoryImport {
    /// The most read from one machine: its latest.
    static let limit = 3_000
    /// A history file larger than this is read no further (its end is what matters, but files that size are rare).
    static let maxBytes = 32 * 1024 * 1024

    /// Every shell's history `reader` finds under `home`, each command once at its last use, oldest first.
    static func entries(reader: any TerminalFolderReader, home: String) async -> [ShellHistoryEntry] {
        var found: [ShellHistoryEntry] = []
        for shell in TerminalShellKind.allCases {
            for relative in ShellHistoryFile.relativePaths(for: shell) {
                let path = home.hasSuffix("/") ? home + relative : home + "/" + relative
                guard let data = await reader.read(path, maxBytes: maxBytes) else { continue }
                found += ShellHistoryFile.parse(data, shell: shell)
                break
            }
        }
        // Several shells' files: those with times in time order, the rest (bash's without HISTTIMEFORMAT) before.
        let ordered = found.enumerated().sorted { lhs, rhs in
            switch (lhs.element.date, rhs.element.date) {
            case let (l?, r?): return l != r ? l < r : lhs.offset < rhs.offset
            case (nil, .some): return true
            case (.some, nil): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
        return Array(ShellHistoryFile.distinctRecent(ordered, limit: limit).reversed())
    }

    /// Reads them into `machine`'s kept commands; how many were new.
    static func importHistory(into history: TerminalCommandHistory, machine: String,
                              reader: any TerminalFolderReader, home: String) async -> Int {
        let entries = await entries(reader: reader, home: home)
        return history.importCommands(entries, machine: machine)
    }
}
