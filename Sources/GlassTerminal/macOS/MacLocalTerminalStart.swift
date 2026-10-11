//
//  MacLocalTerminalStart.swift
//  Glass Power Tools — GlassTerminal
//
//  Where a new local terminal starts (W37). The owner, 2026-10-11: "we need to make new local
//  terminals pwd to the pwd in use in the current terminal." Opened from a local terminal — ⌘T
//  or "+", ⇧⌘T, ⌘N or New Terminal Window, a split — a new local terminal starts in the folder
//  that terminal is in now, as Terminal.app's "Same Working Directory" does. Opened from anywhere
//  else (Connections, the Dock, an SSH tab, the windows a relaunch reopens) it starts where it
//  always has: the Settings folder, else Home.
//
//  The folder is asked exactly as Open Folder Here asks (`MacLocalShellFolder`): tmux's
//  `pane_current_path` for a pane kept in tmux, whose own reports stop at tmux; the shell
//  process's folder otherwise. Only a folder that exists now is used. Anything else — tmux not
//  answering, a shell that has exited, a folder deleted since the shell went there — starts the
//  new terminal where it would have started anyway, and says so in the log.
//
//  The folder travels as the new pane's `localDirectory`, and from there as an argument, never
//  through a shell: tmux's `-c` (`MacLocalTmux.claim`, `MacLocalTmux.arguments`) or the PTY's
//  working directory (`SwiftTermLocalProcessConfiguration.currentDirectory`).
//

#if os(macOS)
import Foundation
import GlassTerminalEmulator
import os

enum MacLocalTerminalStart {
    /// How a new local terminal is being opened.
    nonisolated enum Opening: Sendable, CaseIterable {
        /// ⌘T, "+", and ⇧⌘T on a local tab.
        case tab
        /// ⌘N and File ▸ New Terminal Window in a terminal window, and a local pane's New Local
        /// Terminal Window.
        case window
        /// Split Right, Split Down and New Local Pane.
        case split
    }

    /// **The one place that says which openings follow the terminal in front.** The owner was
    /// told that new tabs and new windows both follow it (2026-10-11), and may yet ask for new
    /// windows to start at Home, as Terminal.app's defaults have them: that is `.window` here.
    nonisolated static func followsTerminalInFront(_ opening: Opening) -> Bool {
        switch opening {
        case .tab, .window, .split: true
        }
    }

    /// The local terminal a new one is opened from, as `MacLocalShellFolder` asks where it is.
    struct Source {
        /// The tmux session it runs in, or nil for a plain shell.
        var tmuxSession: String?
        /// Whether its own process is running.
        var shellIsRunning: Bool
        /// The shell process's folder, else what it reported (OSC 7). Read only for a plain shell.
        var processDirectory: () -> String?
    }

    /// The folder a new local terminal opened from `source` starts in, or nil for the folder it
    /// would start in anyway. Nil `source`: no local terminal in front.
    @MainActor
    static func folder(for opening: Opening, from source: Source?,
                       lookups: MacLocalShellFolder.Lookups = .live) async -> String? {
        guard let source, followsTerminalInFront(opening) else { return nil }
        let found = await MacLocalShellFolder.resolve(
            tmuxSession: source.tmuxSession,
            shellIsRunning: source.shellIsRunning,
            processDirectory: source.processDirectory,
            lookups: lookups
        )
        switch found {
        case .folder(let path):
            return path
        case .missing(let path):
            logger.notice("A new local terminal starts in the default folder: the terminal it was opened from is in a folder that is gone, \(path, privacy: .private)")
            return nil
        case .unknown:
            logger.notice("A new local terminal starts in the default folder: where the terminal it was opened from is could not be found")
            return nil
        }
    }

    /// A new local pane, in `folder` when there is one.
    static func intent(in folder: String?) -> MacWorkspacePaneIntent {
        .local(shell: nil, directory: folder)
    }

    /// A new terminal window's request: one local tab, in `folder` when there is one. With none,
    /// exactly the request New Terminal Window always made.
    static func windowRequest(in folder: String?) -> MacWorkspaceLaunchRequest {
        guard let folder else { return MacWorkspaceLaunchRequest() }
        return MacWorkspaceLaunchRequest(initialPaneIntent: intent(in: folder))
    }

    private nonisolated static let logger = Logger(subsystem: "sh.glas", category: "terminal")
}

// MARK: The terminal in front

extension MacWorkspaceController {
    /// The focused pane, when it is a local terminal, as a new local terminal asks where it is
    /// (W37). Nil for an SSH pane and for an empty tab: those open new terminals at the default.
    var focusedLocalTerminal: MacLocalTerminalStart.Source? {
        guard let pane = focusedPane, pane.intent.kind == .local else { return nil }
        let runtime = localRuntimesByPaneID[pane.id]
        return MacLocalTerminalStart.Source(
            tmuxSession: localTmuxSession(for: pane.id),
            shellIsRunning: runtime?.processState.isRunning ?? false,
            processDirectory: { runtime?.currentWorkingDirectory }
        )
    }

    /// Split Right, Split Down and New Local Pane (W37): a local pane beside the focused one, in
    /// the folder the focused local terminal is in.
    func addLocalPane(axis: MacWorkspaceSplitAxis, lookups: MacLocalShellFolder.Lookups = .live) async {
        let folder = await MacLocalTerminalStart.folder(for: .split, from: focusedLocalTerminal, lookups: lookups)
        // Closed while tmux was asked: nothing to split.
        guard !isClosed else { return }
        addPane(intent: MacLocalTerminalStart.intent(in: folder), axis: axis)
    }
}

extension MacWorkspaceWindowController {
    /// ⌘T and "+" (W37): a tab with a shell on this Mac, in the folder of the local terminal in
    /// front. With `repeating`, ⇧⌘T's tab: that pane's intent, in that folder when it is a local
    /// one. The caller starts its panes (`startLocalPanes`).
    @discardableResult
    func addTabStartingWhereFocusedIs(repeating repeated: MacWorkspacePaneIntent? = nil,
                                      lookups: MacLocalShellFolder.Lookups = .live) async -> MacWorkspaceController? {
        var intent = repeated ?? MacLocalTerminalStart.intent(in: nil)
        if intent.kind == .local,
           let folder = await MacLocalTerminalStart.folder(for: .tab, from: selectedTab.focusedLocalTerminal, lookups: lookups) {
            intent.localDirectory = folder
        }
        // Closed, or emptied by a drag, while tmux was asked: a tab added now would make a tmux
        // session, or start a shell, that no window shows.
        guard isOpen else { return nil }
        return addTab(MacWorkspaceTabRequest(startsEmpty: false, initialPaneIntent: intent))
    }

    /// ⌘N and New Terminal Window from this window (W37): one local tab, in the folder of the
    /// local terminal in front.
    func newWindowRequest(lookups: MacLocalShellFolder.Lookups = .live) async -> MacWorkspaceLaunchRequest {
        MacLocalTerminalStart.windowRequest(
            in: await MacLocalTerminalStart.folder(for: .window, from: selectedTab.focusedLocalTerminal, lookups: lookups)
        )
    }

    /// The window is still showing tabs: not closed, and not emptied by a drag into another.
    private var isOpen: Bool {
        !closesAfterLastTabLeft && tabs.contains { !$0.isClosed }
    }
}
#endif
