//
//  MacLocalTmuxLaunchOffer.swift
//  Glass Power Tools — GlassTerminal
//
//  W7b (2026-10-08): after four crashes and an update, every terminal window came back as an
//  empty tab while all fourteen of the owner's local tmux sessions kept running, and nothing
//  said so. Once the app has opened its windows, it now offers the `glass-N` sessions no tab
//  shows, once: "14 terminal sessions are still running. Reopen them?" Reopen puts them in one
//  window, a tab each, as Active's This Mac opens one; Not Now leaves them to Active.
//

#if os(macOS)
import Foundation

@MainActor
final class MacLocalTmuxLaunchOffer {
    static let shared = MacLocalTmuxLaunchOffer()

    /// Sessions a tab here let go of in this run, by closing or quitting. Closing a tab is a
    /// choice, so its session is never offered back as one left running.
    private(set) var closedThisRun: Set<String> = []
    private var hasOffered = false

    func noteClosed(_ name: String) {
        closedThisRun.insert(name)
    }

    /// The `glass-N` sessions running on this Mac that no tab here shows or was closed on in this
    /// run, Glass's own numbers in order, as Active lists them. Empty — and nothing is run — when
    /// "Keep local terminals running with tmux" is off; empty when tmux is missing or its list
    /// can't be read, rather than a guess.
    func sessions(shown: Set<String>, defaults: UserDefaults = .standard) -> [String] {
        guard defaults.bool(forKey: UserDefaultsKeys.localTmux),
              let tmux = MacLocalTmux.server.executablePath(),
              let listing = MacLocalTmux.listing(tmux: tmux) else { return [] }
        return listing.map(\.name)
            .filter { TerminalTmux.glassNumber($0) != nil && !shown.contains($0) && !closedThisRun.contains($0) }
            .sorted { (TerminalTmux.glassNumber($0) ?? .max, $0) < (TerminalTmux.glassNumber($1) ?? .max, $1) }
    }

    /// What to offer at this launch: the sessions above, the first time it is asked and only
    /// then; nil when there are none.
    func take(shown: Set<String>, defaults: UserDefaults = .standard) -> [String]? {
        guard !hasOffered else { return nil }
        hasOffered = true
        let sessions = sessions(shown: shown, defaults: defaults)
        return sessions.isEmpty ? nil : sessions
    }

    /// The tmux sessions tabs here show or are about to: every pane of every terminal window
    /// made, on screen or still opening, and every session a pane is attached to.
    static func shownSessions(registry: MacWorkspacePreviewRegistry = .shared) -> Set<String> {
        let windows = registry.shownControllers + registry.openWindowIDs.flatMap { registry.controllers(windowID: $0) }
        let named = windows.flatMap(\.tabs).flatMap { $0.state.root?.panes ?? [] }.compactMap(\.intent.localTmuxSession)
        return Set(named).union(MacLocalTmux.shownHere.keys)
    }

    nonisolated static func message(count: Int) -> String {
        count == 1
            ? "1 terminal session is still running. Reopen it?"
            : "\(count) terminal sessions are still running. Reopen them?"
    }

    /// One window with a tab per session, in the order given: each tab the one Active's This Mac
    /// opens for a session (`.localTerminal(tmux:)`). A window holds at most 32 tabs, so more
    /// carry on in another.
    static func launchRequests(for sessions: [String]) -> [MacWorkspaceLaunchRequest] {
        let limit = MacWorkspaceWindowRestorationState.maximumTabCount
        return stride(from: 0, to: sessions.count, by: limit).map { start in
            MacWorkspaceLaunchRequest(tabs: sessions[start..<min(start + limit, sessions.count)].map { name in
                var intent = MacWorkspacePaneIntent.local
                intent.localTmuxSession = name
                return MacWorkspaceTabRequest(initialPaneIntent: intent)
            })
        }
    }
}
#endif
