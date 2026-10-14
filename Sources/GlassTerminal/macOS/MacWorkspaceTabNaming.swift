//
//  MacWorkspaceTabNaming.swift
//  Glass Power Tools — GlassTerminal
//
//  What a terminal tab is called when nobody has named it (2026-10-07). Two local tabs both read
//  "Local / user@localhost"; the owner: "we should be able to do better by default than the
//  location of terminal". Terminal.app's answer, in its order: the title the shell or program set,
//  else where the shell is standing. A name someone gave the tab wins over both.
//
//  The rule itself is `TerminalSessionNaming`'s, which Active uses on every device (W6), so a
//  session is called the same in Active as in the tab that shows it.
//

import Foundation

/// What a pane's terminal says about itself: the title its shell or program set (OSC 0/2) and the
/// directory it is in — read from the local shell's process, reported by a remote one (OSC 7). In
/// tmux, what tmux says the session's active pane shows, on this Mac or on a host (W19).
nonisolated struct MacWorkspacePaneContext: Equatable, Sendable {
    var title: String?
    var directory: String?
    /// The name a tab on any device gave the pane's tmux session (`@glass-name`, W6). The tab
    /// follows it (W19). Only tmux answers this; nil everywhere else.
    var givenName: String? = nil
    /// The home folder of the account the pane's tmux session runs as, when a host said it (W19):
    /// a remote folder is then named as Active names it, and home names nothing.
    var home: String? = nil
    /// The foreground program, as tmux names it, and its program and script (`TerminalAgent`,
    /// 2026-10-14). Only tmux answers the first; nil everywhere else.
    var program: String? = nil
    var programArguments: String? = nil
}

enum MacWorkspaceTabNaming {
    /// The automatic name, or nil when the terminal has said nothing that names it. The caller
    /// goes on to the workgroup, the tmux session or the shell. The repository the pane's folder
    /// is in stands in for the folder (W11).
    static func automaticTitle(_ context: MacWorkspacePaneContext?, repository: TerminalRepository? = nil,
                               home: String?) -> String? {
        guard context != nil || repository != nil else { return nil }
        return TerminalSessionNaming.automaticName(title: context?.title, directory: context?.directory, home: home,
                                                   repository: repository)
    }

    /// A tmux session as Active names it when nothing else does: `glass-N` is "Terminal N".
    static func tmuxDisplayName(_ session: String) -> String {
        TerminalSessionNaming.tmuxDisplayName(session)
    }

    /// A directory as a person writes it: `~/src/app` under the home directory.
    static func abbreviated(_ directory: String, home: String?) -> String {
        TerminalSessionNaming.abbreviated(directory, home: home)
    }
}
