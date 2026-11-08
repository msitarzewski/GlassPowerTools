//
//  TerminalShellKind.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06): the shells whose history the app reads and whose prompts its shell
//  integration marks. `tasks/2026-11/2026-11-06_type-ahead.md`.
//

import Foundation

/// A shell the app knows: where it keeps its history, how its prompt is marked.
nonisolated enum TerminalShellKind: String, Sendable, CaseIterable, Codable {
    case zsh, bash, fish

    /// The shell a login shell's path names, by its last component (`/bin/zsh`, `/usr/local/bin/fish`, `-bash`).
    init?(path: String) {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        self.init(rawValue: name.hasPrefix("-") ? String(name.dropFirst()) : name)
    }
}
