//
//  TerminalSessionNaming.swift
//  Glass Power Tools — GlassTerminal
//
//  One rule names a terminal wherever it is listed: a Mac's tab, and Active on every device
//  (W6, 2026-10-08). The owner saw tabs named by their programs' titles and their projects'
//  folders listed in Active as "Terminal 1"…"Terminal 14": Active knew only the session's name,
//  and the tabs asked tmux what the session shows. Now Active asks the same, and both name it by
//  this rule.
//
//  In order: a name someone gave it, the title its program set, a folder other than home, and
//  last the session's own name ("Terminal N" for Glass's `glass-N`). The Mac's tabs put a few of
//  their own between these — a workgroup's name, the shell — but never reorder them.
//

import Foundation

enum TerminalSessionNaming {
    /// The longest name a tab or a session carries, as `MacWorkspaceTabRequest.maximumDisplayTextLength`.
    nonisolated static let maximumLength = 80

    /// What a tmux session is called in Active: as a tab showing it would be.
    nonisolated static func name(given: String?, title: String?, directory: String?, home: String?, session: String) -> String {
        given.flatMap { displayText($0) }
            ?? automaticName(title: title, directory: directory, home: home)
            ?? tmuxDisplayName(session)
    }

    /// The name a terminal gives itself, or nil when it has said nothing that names it: the title
    /// its program set, else the folder it is in. The home folder and `/` do not: a tab called "~"
    /// read as a tab with no name (2026-10-08), so the caller goes on to its next choice.
    nonisolated static func automaticName(title: String?, directory: String?, home: String?) -> String? {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        guard let directory, directory.hasPrefix("/"), directory != "/", directory != home else { return nil }
        return (directory as NSString).lastPathComponent
    }

    /// The title a program set, or nil: tmux titles a pane with the host name until a program
    /// sets one, and that is not a title.
    nonisolated static func programTitle(_ title: String?, hostNames: [String]) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty,
              !hostNames.contains(title) else { return nil }
        return title
    }

    /// A tmux session by its own name: Glass's `glass-N` is "Terminal N", any other its own name.
    nonisolated static func tmuxDisplayName(_ session: String) -> String {
        TerminalTmux.glassNumber(session).map { "Terminal \($0)" } ?? session
    }

    /// A directory as a person writes it: `~/src/app` under the home directory.
    nonisolated static func abbreviated(_ directory: String, home: String?) -> String {
        guard let home, !home.isEmpty, home != "/" else { return directory }
        if directory == home { return "~" }
        if directory.hasPrefix(home + "/") { return "~" + directory.dropFirst(home.count) }
        return directory
    }

    /// Text from elsewhere as a tab can show it: one line, no control or direction-changing
    /// characters, at most `maximumLength` characters; nil when nothing is left. A session's name
    /// can be set by anyone with tmux, so what Active reads is held to what a tab accepts.
    nonisolated static func displayText(_ value: String, maximumLength: Int = maximumLength) -> String? {
        let visible = String(String.UnicodeScalarView(value.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) || isDirectionControl(scalar) ? " " : scalar
        }))
        let line = visible.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.isEmpty ? nil : String(line.prefix(maximumLength))
    }

    private nonisolated static func isDirectionControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: true
        default: false
        }
    }
}
