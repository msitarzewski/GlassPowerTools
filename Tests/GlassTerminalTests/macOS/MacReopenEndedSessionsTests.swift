#if os(macOS)
import Foundation
import GlassTerminalEmulator
import Testing
@testable import GlassTerminal

/// A relaunch never brings back a tab whose tmux session has ended (2026-11-19). The owner's Mac restarted with 29 tabs
/// open, every one in tmux: each came back an empty shell in his home folder under its old session name, and closing
/// their windows left that many empty sessions running, so he typed `exit` in each. Asked, he chose "I'd rather close
/// it, or rather not reopen it, if it was a tmux session."
///
/// Records only: saved windows and tabs written to a test's own defaults, and the Mac's sessions as the test says they
/// are. Nothing here starts tmux or a shell, or asks the owner's server.
@MainActor
struct MacReopenEndedSessionsTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "MacReopenEndedSessionsTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func local(_ session: String?, created: Int? = nil) -> MacWorkspacePaneIntent {
        var intent = MacWorkspacePaneIntent.local(shell: nil, directory: "/Users/ann/src")
        intent.localTmuxSession = session
        intent.localTmuxSessionCreated = session == nil ? nil : created
        return intent
    }

    private func ssh(_ session: String) -> MacWorkspacePaneIntent {
        var intent = MacWorkspacePaneIntent.ssh(serverID: UUID())
        intent.sshTmuxSession = session
        intent.sshTmuxSessionCreated = 1_790_000_000
        return intent
    }

    private func tabKey(_ id: UUID) -> String {
        "\(UserDefaultsKeys.macWorkspaceRestoration).\(id.uuidString.lowercased())"
    }

    /// A window as the last run saved it: one tab per intent, each tab's record beside it.
    private func savedWindow(_ intents: [MacWorkspacePaneIntent], _ defaults: UserDefaults) throws -> (window: UUID, tabs: [UUID]) {
        let window = UUID()
        let tabs = intents.map { _ in UUID() }
        for (tab, intent) in zip(tabs, intents) {
            defaults.set(try JSONEncoder().encode(MacWorkspaceRestorationState(id: tab, initialIntent: intent)), forKey: tabKey(tab))
        }
        let state = MacWorkspaceWindowRestorationState(
            tabs: tabs.map { MacWorkspaceTabDescriptor(MacWorkspaceTabRequest(workspaceID: $0)) }, selectedTabID: tabs[0])
        defaults.set(try JSONEncoder().encode(state),
                     forKey: "\(UserDefaultsKeys.macWorkspaceRestoration).window.\(window.uuidString.lowercased())")
        try #require(MacWorkspaceWindowController.hasSavedState(windowID: window, defaults: defaults))
        return (window, tabs)
    }

    private func savedTabs(_ window: UUID, _ defaults: UserDefaults) -> [UUID]? {
        guard case .restored(let saved) = MacWorkspaceWindowController.load(windowID: window, defaults: defaults) else { return nil }
        return saved.tabs.map(\.id)
    }

    @Test("a local pane comes back only while its own session runs; an SSH pane, a plain shell and an unknown answer always do")
    func whichPanesComeBack() {
        let running = [TerminalTmux.Session(name: "glass-1", attachedClients: 0, windows: 1, created: 1_790_000_000),
                       TerminalTmux.Session(name: "glass-2", attachedClients: 0, windows: 1, created: 1_795_105_500)]
        #expect(MacLocalTmux.reopens(local("glass-1", created: 1_790_000_000), local: running))
        #expect(!MacLocalTmux.reopens(local("glass-2", created: 1_790_000_100), local: running),
                "a later session took its name: not its own")
        #expect(!MacLocalTmux.reopens(local("glass-3", created: 1_790_000_200), local: running), "its session has ended")
        #expect(!MacLocalTmux.reopens(local("glass-3"), local: running), "never learnt when: the name alone, and that's gone")
        #expect(MacLocalTmux.reopens(local("glass-2"), local: running), "never learnt when: the name alone, and that runs")
        #expect(!MacLocalTmux.reopens(local("glass-1", created: 1_790_000_000), local: []), "after a restart, nothing runs")
        #expect(MacLocalTmux.reopens(local("glass-3", created: 1), local: nil), "not known what runs: it comes back")
        #expect(MacLocalTmux.reopens(local(nil), local: []), "a plain shell: nothing to have ended")
        #expect(MacLocalTmux.reopens(ssh("glass-9"), local: []), "an SSH pane joins as it connects, and goes then if it can't")
    }

    @Test("after a restart, a window of ended local sessions stays closed and its records go; a window keeps the tabs that come back")
    func endedTabsStayClosed() throws {
        try withDefaults { defaults in
            let allEnded = try savedWindow([local("glass-1", created: 1_790_000_000), local("glass-2", created: 1_790_000_100)],
                                           defaults)
            let mixed = try savedWindow([local("glass-3", created: 1_790_000_200), ssh("work"), local("glass-4", created: 7)],
                                        defaults)
            let running = [TerminalTmux.Session(name: "glass-4", attachedClients: 0, windows: 1, created: 7)]

            let (reopening, ended) = MacLocalTmux.withoutEndedSessions([allEnded.window, mixed.window], local: running,
                                                                       defaults: defaults)
            #expect(reopening == [mixed.window])
            #expect(ended == MacLocalTmux.EndedTabs(tabs: 3, windows: 1, workgroups: [], newestCreated: 1_790_000_200))
            #expect(!MacWorkspaceWindowController.hasSavedState(windowID: allEnded.window, defaults: defaults),
                    "its record went, so nothing comes back to it later")
            #expect(allEnded.tabs.allSatisfy { defaults.object(forKey: tabKey($0)) == nil })
            #expect(savedTabs(mixed.window, defaults) == Array(mixed.tabs.dropFirst()), "the SSH tab and the running one")
            #expect(defaults.object(forKey: tabKey(mixed.tabs[0])) == nil)
            #expect(defaults.object(forKey: tabKey(mixed.tabs[2])) != nil)

            // Not known what runs here: every window comes back as saved, and a pane whose session is gone closes
            // once tmux says so.
            let unknown = try savedWindow([local("glass-5", created: 9)], defaults)
            #expect(MacLocalTmux.withoutEndedSessions([unknown.window], local: nil, defaults: defaults).reopening == [unknown.window])
            #expect(savedTabs(unknown.window, defaults) == unknown.tabs)
        }
    }

    @Test("the last run's list is taken without the windows whose sessions ended")
    func takenWithoutEnded() throws {
        try withDefaults { defaults in
            let ended = try savedWindow([local("glass-1", created: 1_790_000_000)], defaults)
            let alive = try savedWindow([local("glass-2", created: 1_790_000_100)], defaults)
            defaults.set([ended.window, alive.window].map(\.uuidString), forKey: MacLocalTmux.reopenKey)
            let reopen = MacWindowsToReopen(defaults: defaults, registry: MacWorkspacePreviewRegistry(), localSessions: {
                [TerminalTmux.Session(name: "glass-2", attachedClients: 0, windows: 1, created: 1_790_000_100)]
            })
            #expect(reopen.takeOnce(askedBy: "a terminal window") == [alive.window])
        }
    }

    /// The owner, 2026-11-19: "We should let the user know that we lost the tmux session … right now I'd be wondering why
    /// my sessions didn't restore. Maybe check uptime, or check how long the tmux daemon has been running?"
    @Test("the launch says how many tabs it left closed, why — the Mac restarted, tmux did, or neither — and which Workgroups start them")
    func saysWhy() throws {
        let made = 1_790_000_000
        let ended = MacLocalTmux.EndedTabs(tabs: 29, windows: 4, workgroups: ["Backend", "Docs"], newestCreated: made)
        let now = Date(timeIntervalSince1970: TimeInterval(made + 7_200))
        let boot = Date(timeIntervalSince1970: TimeInterval(made + 3_600))
        let restartedTmux = TerminalTmux.Session(name: "glass-9", attachedClients: 0, windows: 1,
                                                 server: TerminalTmux.Server(pid: 1, startTime: made + 600, socketPath: "/tmp/s"))
        let sameTmux = TerminalTmux.Session(name: "glass-9", attachedClients: 0, windows: 1,
                                            server: TerminalTmux.Server(pid: 1, startTime: made - 600, socketPath: "/tmp/s"))

        #expect(MacLocalTmux.whyEnded(ended, local: [], bootTime: boot) == .machineRestarted(at: boot), "booted after they were made")
        #expect(MacLocalTmux.whyEnded(ended, local: [restartedTmux], bootTime: Date(timeIntervalSince1970: 1))
                == .tmuxRestarted(at: Date(timeIntervalSince1970: TimeInterval(made + 600))), "tmux started after them")
        #expect(MacLocalTmux.whyEnded(ended, local: [], bootTime: Date(timeIntervalSince1970: 1)) == .tmuxNotRunning)
        #expect(MacLocalTmux.whyEnded(ended, local: [sameTmux], bootTime: Date(timeIntervalSince1970: 1)) == .ended)

        let notice = try #require(MacLocalTmux.endedNotice(ended, reason: .machineRestarted(at: boot), now: now))
        #expect(notice.title == "29 tabs in 4 windows weren't reopened")
        #expect(notice.message.hasPrefix("Your Mac restarted at \(boot.formatted(date: .omitted, time: .shortened)), which ended their tmux sessions"))
        #expect(notice.message.hasSuffix("To start their terminals again, open “Backend” and “Docs” from Workgroups."))
        let one = MacLocalTmux.EndedTabs(tabs: 1, windows: 0, workgroups: [], newestCreated: nil)
        #expect(MacLocalTmux.endedNotice(one, reason: .tmuxNotRunning, now: now)?.title == "A tab wasn't reopened")
        #expect(MacLocalTmux.endedNotice(MacLocalTmux.EndedTabs(), reason: .ended) == nil, "nothing left closed: nothing said")
    }

    @Test("a relaunch after a restart has its notice, once")
    func noticeTakenOnce() throws {
        try withDefaults { defaults in
            let ended = try savedWindow([local("glass-1", created: 1_790_000_000)], defaults)
            defaults.set([ended.window.uuidString], forKey: MacLocalTmux.reopenKey)
            let boot = Date(timeIntervalSince1970: 1_795_105_378)
            let reopen = MacWindowsToReopen(defaults: defaults, registry: MacWorkspacePreviewRegistry(),
                                            localSessions: { [] }, bootTime: { boot })
            #expect(reopen.takeOnce(askedBy: "a terminal window") == [])
            let notice = try #require(reopen.takeEndedNotice())
            #expect(notice.title == "A tab wasn't reopened" && notice.message.hasPrefix("Your Mac restarted at"))
            #expect(reopen.takeEndedNotice() == nil, "said once")
        }
    }

    @Test("a pane's session and when tmux made it are kept with the tab, read back, and dropped with a plain shell")
    func createdIsSaved() throws {
        var intent = local("glass-1", created: 1_790_000_000)
        let decoded = try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: JSONEncoder().encode(intent))
        #expect(decoded.localTmuxSessionCreated == 1_790_000_000 && decoded.tmuxSessionCreated == 1_790_000_000)
        #expect(intent.startingWithoutTmux().localTmuxSessionCreated == nil)
        // A date without the session it dates is not read.
        intent.localTmuxSession = nil
        let undated = try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: JSONEncoder().encode(intent))
        #expect(undated.localTmuxSessionCreated == nil)
        // The same pane to start, whenever its session was made.
        #expect(local("glass-1", created: 1).startsSamePane(as: local("glass-1", created: 2)))
    }

    @Test("a pane that has been in its session only joins it again: attach-session, never new-session")
    func joinsOnly() {
        #expect(MacLocalTmux.joinArguments(session: "glass-1") == ["-u", "-T", "sync,RGB", "attach-session", "-t", "=glass-1"])
        #expect(MacLocalTmux.joinArguments(session: "glass-1", control: true) == ["-u", "-C", "attach-session", "-t", "=glass-1"])
        #expect(!MacLocalTmux.joinArguments(session: "glass-1").contains("new-session"))
        // As a pane starts: no shell given to make it with, no folder. A tmux that isn't there is named, so nothing runs.
        let joining = MacLocalTerminalConfiguration.resolve(shell: "/bin/zsh", directory: "/tmp", tmuxSession: "glass-1",
                                                            tmux: "/nonexistent/tmux", joining: true)
        #expect(joining.arguments == ["-u", "-T", "sync,RGB", "attach-session", "-t", "=glass-1"])
        let making = MacLocalTerminalConfiguration.resolve(shell: "/bin/zsh", directory: "/tmp", tmuxSession: "glass-1",
                                                           tmux: "/nonexistent/tmux")
        #expect(making.arguments.contains("new-session") && making.arguments.contains("/bin/zsh"), "a new pane still makes its own")
    }
}
#endif
