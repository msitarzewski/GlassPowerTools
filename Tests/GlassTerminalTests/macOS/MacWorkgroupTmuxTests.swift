#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import GlassTerminal

/// W4b (2026-10-08): on the Mac, a workgroup's panes open on their saved tmux sessions — local
/// ones on this Mac's server, SSH ones on their hosts — a pane without one writes back the one it
/// is given, saving a window captures what runs now, and SSH panes reattach after a relaunch.
///
/// Nothing here starts tmux or connects: local names come from `MacLocalTmuxTests.FakeServer`,
/// hosts answer from memory. Tests that swap `MacLocalTmux.server` never suspend while it is in
/// place, so no other test runs against the fake.
@MainActor
@Suite("Mac workgroups keep their tmux sessions", .serialized)
struct MacWorkgroupTmuxTests {
    @MainActor final class Writes {
        var lines: [String] = []
        func receive(_ data: Data) { lines.append(String(decoding: data, as: UTF8.self)) }
    }

    /// A host's tmux from memory, as `WorkgroupTmuxSessionsTests` has it.
    @MainActor final class Host {
        var running: Set<String> = []
        private(set) var claims: [[String]] = []
        func answer(_ command: String) -> String {
            guard let offered = TerminalTmuxTests.offered(in: command) else {
                return running.sorted().map { "\($0)\t0\t1\t0" }.joined(separator: "\n")
            }
            claims.append(offered)
            for name in offered {
                if !running.contains(name) {
                    running.insert(name)
                    return "created \(name)\n"
                }
                if offered.count == 1 { return "exists \(name)\n" }
            }
            return "__glass_tmux_failed__\n"
        }
    }

    /// Opens SSH panes on `host` without a network: the terminal is configured as the real
    /// manager would, then reported connected, which types its attach line.
    final class HostManager: SessionManager {
        let host = Host()
        let writes = Writes()
        var server: ServerConfiguration?

        override func createAuthorizedSessionByServerID(
            _ serverID: UUID,
            settingsManager: SettingsManager,
            startupCommand: String? = nil,
            tmux: TerminalTmuxAttachment? = nil,
            configure: (@MainActor (TerminalSession) -> Void)? = nil,
            initialTerminalPresentation: TerminalSession.InitialTerminalPresentationRequest? = nil
        ) async throws -> AuthorizedSessionLaunch {
            var server = ServerConfiguration(id: serverID, name: "alpha", host: "192.0.2.10", username: "ann")
            server.tmux = true
            self.server = server
            let session = TerminalSession(server: server, terminalWriteSink: { [writes] in writes.receive($0) })
            session.tmuxCommandRunner = { [host] in host.answer($0) }
            _ = session.installStartupCommand(startupCommand)
            configure?(session)
            initialTerminalPresentation?(session)
            session.state = .connected
            return AuthorizedSessionLaunch(session: session)
        }
    }

    private static func attach(_ name: String) -> String {
        " command -v tmux >/dev/null && exec tmux -u new-session -A -s '\(name)'\n"
    }

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let suite = "MacWorkgroupTmuxTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    private func sshServer() -> ServerConfiguration {
        var server = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")
        server.tmux = true
        return server
    }

    @Test("opening a workgroup gives each pane its saved session, local and SSH, in a split as in a tab")
    func launcherCarriesNames() throws {
        let serverID = UUID()
        let preset = LayoutPreset(name: "Desk", sessionIntents: [
            .init(kind: .local, tmuxSession: "glass-4"),
            .init(serverID: serverID, tmuxSession: "work"),
            .init(serverID: serverID)
        ], workspaceLayout: .init(tabs: [
            .init(label: "Both", root: .split(axis: .vertical, fraction: 0.5, first: .session(0), second: .session(1)),
                  focusedSessionIndex: 0),
            .init(label: nil, root: .session(2), focusedSessionIndex: 2)
        ], selectedTabIndex: 0))
        let request = try MacWorkgroupLauncher.launch(preset: preset, broker: MacStartupCommandBroker(), openWindow: { _ in })[0]
        let panes = request.tabs.flatMap { $0.initialState?.root?.panes ?? [] }
        #expect(panes.map(\.intent.sourceSessionIndex) == [0, 1, 2])
        #expect(panes.map(\.intent.localTmuxSession) == ["glass-4", nil, nil])
        #expect(panes.map(\.intent.sshTmuxSession) == [nil, "work", nil])
        #expect(panes.map(\.intent.tmuxSession) == ["glass-4", "work", nil])
    }

    @Test("an SSH pane's session is kept with its tab; a name that would not do is dropped, never the tab")
    func sshPaneIntentCoding() throws {
        var intent = MacWorkspacePaneIntent.ssh(serverID: UUID())
        intent.sshTmuxSession = "glass-2"
        #expect(try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: JSONEncoder().encode(intent)) == intent)

        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        object["sshTmuxSession"] = "bad:name"
        #expect(try JSONDecoder().decode(MacWorkspacePaneIntent.self,
                                         from: JSONSerialization.data(withJSONObject: object)).sshTmuxSession == nil)
        var local = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(MacWorkspacePaneIntent.local)) as? [String: Any])
        local["sshTmuxSession"] = "glass-2"
        #expect(try JSONDecoder().decode(MacWorkspacePaneIntent.self,
                                         from: JSONSerialization.data(withJSONObject: local)).sshTmuxSession == nil)
        var moved = intent
        moved.sshTmuxSession = "glass-3"
        #expect(moved.startsSamePane(as: intent) && moved != intent, "a name written back leaves it the same pane")
    }

    @Test("an SSH pane claims a session, keeps it, writes it back to its workgroup once, and reattaches after a relaunch")
    func sshPaneReattaches() async throws {
        try await withDefaults { defaults in
            let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
            let serverID = UUID()
            settings.upsertLayoutPreset(LayoutPreset(name: "Remote", sessionIntents: [.init(serverID: serverID, startupCommand: "htop")]))
            let preset = try #require(settings.layoutPresets.first)
            let broker = MacStartupCommandBroker()
            let request = try MacWorkgroupLauncher.launch(preset: preset, broker: broker, openWindow: { _ in })[0]
            let manager = HostManager(loadImmediately: false)

            let window = MacWorkspaceWindowController(request: request, startupCommandBroker: broker, defaults: defaults)
            window.windowDidOpen()
            let tab = window.tabs[0]
            let pane = try #require(tab.focusedPane)
            await tab.prepareSSHPaneIfNeeded(pane, sessionManager: manager, settingsManager: settings)
            let session = try #require(tab.session(for: pane.id))
            await session.waitForTmuxAttach()
            await session.waitUntilTerminalWritesComplete()
            #expect(manager.writes.lines == [Self.attach("glass-1"), "htop\n"], "made for it: the command runs in it")
            #expect(tab.focusedPane?.intent.sshTmuxSession == "glass-1", "the pane keeps it")
            #expect(settings.layoutPresets.first?.sessionIntents.first?.tmuxSession == "glass-1", "and so does the workgroup")
            let written = settings.layoutPresets.first?.modifiedAt
            tab.closeAllSessions(sessionManager: manager)

            // The next launch: the window and its tab, read back from what was saved.
            manager.writes.lines = []
            let relaunched = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(windowID: request.windowID, tabs: []), defaults: defaults)
            let restoredTab = relaunched.tabs[0]
            let restored = try #require(restoredTab.focusedPane)
            #expect(restored.intent.sshTmuxSession == "glass-1")
            await restoredTab.prepareSSHPaneIfNeeded(restored, sessionManager: manager, settingsManager: settings)
            let again = try #require(restoredTab.session(for: restored.id))
            await again.waitForTmuxAttach()
            await again.waitUntilTerminalWritesComplete()
            #expect(manager.host.claims.last == ["glass-1"], "its own session, claimed")
            #expect(manager.writes.lines == [Self.attach("glass-1")], "running: attached, nothing typed into it")
            #expect(settings.layoutPresets.first?.modifiedAt == written, "written back once")
            restoredTab.closeAllSessions(sessionManager: manager)
        }
    }

    @Test("a terminal opened by Connect keeps the session it claims, so its tab reattaches after a relaunch")
    func connectedPaneKeepsItsSession() async throws {
        try await withDefaults { defaults in
            let server = sshServer()
            let session = TerminalSession(server: server)
            let liveBroker = MacLiveSessionBroker()
            let ticket = liveBroker.issue(session: session) {}
            let tab = MacWorkspaceController(
                request: MacWorkspaceTabRequest(initialPaneIntent: .ssh(serverID: server.id), liveSessionTicketID: ticket),
                liveSessionBroker: liveBroker, defaults: defaults)
            defer { tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
            tab.saveIfUnsaved()
            #expect(tab.focusedPane?.intent.sshTmuxSession == nil)
            session.tmuxSessionClaimed?("glass-9")
            #expect(tab.focusedPane?.intent.sshTmuxSession == "glass-9")
            let restored = MacWorkspaceController(workspaceID: tab.workspaceID, defaults: defaults)
            #expect(restored.focusedPane?.intent.sshTmuxSession == "glass-9", "saved with the tab")
        }
    }

    @Test("Save as Workgroup captures the session each terminal is in now, local and SSH")
    func captureCarriesLiveNames() throws {
        let suite = "MacWorkgroupTmuxTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = MacLocalTmuxTests.FakeServer()
        let previous = MacLocalTmux.server
        MacLocalTmux.server = fake.server
        defer { MacLocalTmux.server = previous }
        defaults.set(true, forKey: UserDefaultsKeys.localTmux)
        let server = sshServer()
        let session = TerminalSession(server: server)
        let liveBroker = MacLiveSessionBroker()
        let ticket = liveBroker.issue(session: session) {}
        let window = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(tabs: [
                MacWorkspaceTabRequest(initialPaneIntent: .local),
                MacWorkspaceTabRequest(initialPaneIntent: .ssh(serverID: server.id), liveSessionTicketID: ticket)
            ]),
            liveSessionBroker: liveBroker, defaults: defaults)
        defer { window.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
        let localName = try #require(window.tabs[0].focusedPane?.intent.localTmuxSession)
        // Claimed after the pane opened: the live terminal knows it before the pane does.
        session.tmuxSessionName = "glass-7"
        #expect(window.tabs[1].focusedPane?.intent.sshTmuxSession == nil)
        let preset = try window.capturePreset(name: "Desk", servers: [server])
        #expect(preset.sessionIntents.map(\.tmuxSession) == [localName, "glass-7"])
    }

    @Test("a local pane on a saved session runs its startup command only in a session made for it")
    func localStartupOnlyWhenCreated() throws {
        let suite = "MacWorkgroupTmuxTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = MacLocalTmuxTests.FakeServer()
        let previous = MacLocalTmux.server
        MacLocalTmux.server = fake.server
        defer { MacLocalTmux.server = previous }
        defaults.set(true, forKey: UserDefaultsKeys.localTmux)
        let sessionManager = SessionManager(loadImmediately: false)
        let preset = LayoutPreset(name: "Build", sessionIntents: [
            .init(kind: .local, startupCommand: "make watch", tmuxSession: "glass-44")
        ])

        for (running, command) in [(true, nil), (false, "make watch")] as [(Bool, String?)] {
            fake.running = running ? ["glass-44"] : []
            let broker = MacStartupCommandBroker()
            let request = try MacWorkgroupLauncher.launch(preset: preset, broker: broker, openWindow: { _ in })[0]
            let tab = MacWorkspaceController(request: request.tabs[0], startupCommandBroker: broker, defaults: defaults)
            let pane = try #require(tab.focusedPaneID)
            #expect(tab.localTmuxSession(for: pane) == "glass-44", "its own session, not a new one")
            #expect(fake.claims.last?.candidates == ["glass-44"], "claimed, with the pane's launch")
            #expect(tab.claimStartupCommand(for: pane)?.command == command,
                    running ? "running: nothing typed into what runs there" : "ended: made again, and the command runs in it")
            #expect(fake.running.contains("glass-44"))
            tab.closeAllSessions(sessionManager: sessionManager)
        }
    }

    @Test("a new local terminal never takes a session a saved workgroup holds on this Mac")
    func newLocalNamesSkipHeld() throws {
        let suite = "MacWorkgroupTmuxTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let held = (1...20).map { "glass-\($0)" }
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        settings.upsertLayoutPreset(LayoutPreset(name: "Many", sessionIntents: held.map { .init(kind: .local, tmuxSession: $0) }))

        let fake = MacLocalTmuxTests.FakeServer()
        let previous = MacLocalTmux.server
        MacLocalTmux.server = fake.server
        defer { MacLocalTmux.server = previous }
        defaults.set(true, forKey: UserDefaultsKeys.localTmux)
        let tab = MacWorkspaceController(request: MacWorkspaceTabRequest(initialPaneIntent: .local), defaults: defaults)
        defer { tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
        let name = try #require(tab.focusedPane?.intent.localTmuxSession)
        #expect(!held.contains(name))
        let offered = fake.claims.last?.candidates ?? []
        #expect(!offered.isEmpty && !offered.contains(where: held.contains), "never offered")
    }

    @Test("after a quit, a window of SSH terminals in tmux opens again, as one of local ones does")
    func reopenRecordIncludesSSHTabs() async throws {
        try await withDefaults { defaults in
            let server = sshServer()
            let session = TerminalSession(server: server)
            session.tmuxSessionName = "glass-2"
            let liveBroker = MacLiveSessionBroker()
            let ticket = liveBroker.issue(session: session) {}
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(initialPaneIntent: .ssh(serverID: server.id), liveSessionTicketID: ticket),
                liveSessionBroker: liveBroker, defaults: defaults)
            defer { window.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
            window.windowDidOpen()
            #expect(window.tabs[0].hasTerminalsInTmux && !window.tabs[0].hasLocalTerminalsInTmux)
            #expect(window.tabs[0].focusedPane?.intent.sshTmuxSession == "glass-2", "the tab reattaches to it")

            let registry = MacWorkspacePreviewRegistry()
            let shown = NSWindow()
            shown.isReleasedWhenClosed = false
            registry.register(window, window: shown)
            MacLocalTmux.rememberWindowsToReopen(defaults: defaults, registry: registry)
            #expect(defaults.stringArray(forKey: MacLocalTmux.reopenKey) == [window.windowID.uuidString])
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults, open: []) == [window.windowID])
        }
    }

    @Test("opening a workgroup already open brings its window forward: the one opened from it, or one showing its sessions")
    func openWorkgroupComesForward() async throws {
        try await withDefaults { defaults in
            let serverID = UUID()
            let preset = LayoutPreset(name: "Desk", sessionIntents: [.init(serverID: serverID, tmuxSession: "work")])
            let registry = MacWorkspacePreviewRegistry()
            var held: [NSWindow] = []
            @MainActor func show(_ controller: MacWorkspaceWindowController) {
                let window = NSWindow()
                window.isReleasedWhenClosed = false
                held.append(window)
                registry.register(controller, window: window)
            }
            #expect(registry.locate(workgroup: preset) == nil)

            // Tabs reopened after a quit, or a window saved as the workgroup: it shows the session.
            var pane = MacWorkspacePaneIntent.ssh(serverID: serverID)
            pane.sshTmuxSession = "work"
            let saved = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(initialPaneIntent: pane), defaults: defaults)
            show(saved)
            var elsewhere = MacWorkspacePaneIntent.ssh(serverID: UUID())
            elsewhere.sshTmuxSession = "work"
            let otherHost = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(initialPaneIntent: elsewhere), defaults: defaults)
            show(otherHost)
            #expect(registry.locate(workgroup: preset)?.controller === saved, "the same session on another host is another session")

            // The window opened from the workgroup comes first.
            let opened = MacWorkspaceWindowController(
                request: try MacWorkgroupLauncher.launch(preset: preset, broker: MacStartupCommandBroker(), openWindow: { _ in })[0],
                defaults: defaults)
            show(opened)
            #expect(registry.locate(workgroup: preset)?.controller === opened)
            withExtendedLifetime(held) {}
        }
    }
}
#endif
