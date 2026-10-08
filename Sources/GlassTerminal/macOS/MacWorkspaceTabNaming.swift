//
//  MacWorkspaceTabNaming.swift
//  Glass Power Tools — GlassTerminal
//
//  What a terminal tab is called when nobody has named it (2026-10-07). Two local tabs both read
//  "Local / user@localhost"; the owner: "we should be able to do better by default than the
//  location of terminal". Terminal.app's answer, in its order: the title the shell or program set,
//  else where the shell is standing. A name someone gave the tab wins over both.
//

import Foundation

/// What a pane's terminal says about itself: the title its shell or program set (OSC 0/2) and the
/// directory it is in — read from the local shell's process, reported by a remote one (OSC 7).
struct MacWorkspacePaneContext: Equatable {
    var title: String?
    var directory: String?
}

enum MacWorkspaceTabNaming {
    /// The automatic name, or nil when the terminal has said nothing that names it. The home
    /// folder and `/` do not: a tab called "~" read as a tab with no name (2026-10-08), so the
    /// caller goes on to the workgroup, the tmux session or the shell.
    static func automaticTitle(_ context: MacWorkspacePaneContext?, home: String?) -> String? {
        guard let context else { return nil }
        if let title = context.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        guard let directory = context.directory, directory.hasPrefix("/"), directory != "/",
              directory != home else { return nil }
        return (directory as NSString).lastPathComponent
    }

    /// A tmux session as Active names it: Glass's `glass-N` is "Terminal N", any other its own name.
    static func tmuxDisplayName(_ session: String) -> String {
        TerminalTmux.glassNumber(session).map { "Terminal \($0)" } ?? session
    }

    /// A directory as a person writes it: `~/src/app` under the home directory.
    static func abbreviated(_ directory: String, home: String?) -> String {
        guard let home, !home.isEmpty, home != "/" else { return directory }
        if directory == home { return "~" }
        if directory.hasPrefix(home + "/") { return "~" + directory.dropFirst(home.count) }
        return directory
    }
}
