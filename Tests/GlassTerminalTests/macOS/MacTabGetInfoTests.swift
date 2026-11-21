#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// A Mac tab's Get Info and Copy tmux Session Name (the owner, 2026-11-19: "a right click > Get Info... on the tabs so
/// finding its tmux name is easier"). SSH panes not yet connected: nothing here starts tmux or a shell.
@MainActor
struct MacTabGetInfoTests {
    private let alpha = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "MacTabGetInfoTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func ssh(_ session: String?, created: Int? = nil) -> MacWorkspacePaneIntent {
        var intent = MacWorkspacePaneIntent.ssh(serverID: alpha.id)
        intent.sshTmuxSession = session
        intent.sshTmuxSessionCreated = session == nil ? nil : created
        return intent
    }

    @Test("a tab says each pane's session, machine and when the session was made; Copy gives every session's name")
    func tabInfo() throws {
        try withDefaults { defaults in
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(tabs: [MacWorkspaceTabRequest(initialPaneIntent: ssh("glass-3", created: 1_790_000_000))]),
                defaults: defaults)
            let tab = try #require(window.tabs.first)
            let info = tab.sessionInfo(servers: [alpha])
            #expect(info.count == 1)
            #expect(info.first?.tmuxSession == "glass-3" && info.first?.machine == "alpha")
            #expect(info.first?.created == Date(timeIntervalSince1970: 1_790_000_000))
            #expect(tab.tmuxSessionNames == ["glass-3"])

            tab.addPane(intent: ssh("work"), axis: .horizontal)
            #expect(tab.tmuxSessionNames == ["glass-3", "work"], "a split tab: both, for Copy tmux Session Names")
            #expect(tab.sessionInfo(servers: [alpha]).map(\.tmuxSession) == ["glass-3", "work"])

            let plain = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(tabs: [MacWorkspaceTabRequest(initialPaneIntent: ssh(nil))]), defaults: defaults)
            #expect(plain.tabs.first?.tmuxSessionNames.isEmpty == true, "nothing to copy: no Copy item")
        }
    }

    @Test("a local tab asks this Mac's tmux who else has its session open: only here, or how many other places")
    func localOpenElsewhere() async throws {
        let suite = "MacTabGetInfoTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        let fake = MacLocalTmuxTests.FakeServer()
        let previous = MacLocalTmux.server
        MacLocalTmux.server = fake.server
        defer {
            MacLocalTmux.server = previous
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(true, forKey: UserDefaultsKeys.localTmux)
        var intent = MacWorkspacePaneIntent.local(shell: nil, directory: "/tmp")
        intent.localTmuxSession = "glass-1"
        intent.localTmuxSessionCreated = 1_790_000_000
        let window = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(tabs: [MacWorkspaceTabRequest(initialPaneIntent: intent)]), defaults: defaults)
        let tab = try #require(window.tabs.first)
        func listed(_ clients: Int) -> [TerminalTmux.Session] {
            [TerminalTmux.Session(name: "glass-1", attachedClients: clients, windows: 1, created: 1_790_000_000)]
        }
        let alone = await tab.sessionInfoAskingTheMachines(servers: [], local: { listed(1) })
        #expect(alone.first?.machine == "This Mac" && alone.first?.tmuxSession == "glass-1")
        #expect(alone.first?.openElsewhere == "Only here", "\(String(describing: alone.first))")
        let shared = await tab.sessionInfoAskingTheMachines(servers: [], local: { listed(3) })
        #expect(shared.first?.openElsewhere == "Here and in 2 other places")
    }
}
#endif
