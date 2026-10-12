#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// Plain terminals on the Mac (the owner, 2026-10-12: "What if I just want a quick naked local
/// terminal?" and "allow remote sessions without tmux too even if it's been selected as
/// default"): a pane started without tmux has no session, claims none, types no attach line, and is
/// plain again after a relaunch or from a workgroup. Its tmux is a stand-in (rule 63).
extension LocalTmuxServerSuites {
@MainActor
@Suite("Plain terminals on the Mac", .serialized)
struct MacPlainTerminalTests {
    private func withFake(_ body: (MacLocalTmuxTests.FakeServer, UserDefaults) async throws -> Void) async throws {
        let suite = "MacPlainTerminalTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        let fake = MacLocalTmuxTests.FakeServer()
        let previous = MacLocalTmux.server
        MacLocalTmux.server = fake.server
        defer {
            MacLocalTmux.server = previous
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(true, forKey: UserDefaultsKeys.localTmux)
        try await body(fake, defaults)
    }

    @Test("a plain pane keeps no tmux session, now or after a relaunch; a pane saved before reads as it was")
    func intentCoding() throws {
        var local = MacWorkspacePaneIntent.local
        local.localTmuxSession = "glass-1"
        let plain = local.startingWithoutTmux()
        #expect(plain.withoutTmux && plain.localTmuxSession == nil)
        #expect(try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: JSONEncoder().encode(plain)) == plain)

        var ssh = MacWorkspacePaneIntent.ssh(serverID: UUID())
        ssh.sshTmuxSession = "work"
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(ssh)) as? [String: Any])
        object["withoutTmux"] = true
        let marked = try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(marked.withoutTmux && marked.sshTmuxSession == nil, "a plain pane has no session to go back to")
        object.removeValue(forKey: "withoutTmux")
        let saved = try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!saved.withoutTmux && saved.sshTmuxSession == "work", "saved before: as it was")
    }

    @Test("with tmux on, a plain pane is given no session and nothing is claimed for it; an ordinary pane beside it is")
    func plainLocalPane() async throws {
        try await withFake { fake, defaults in
            let id = UUID()
            let tab = MacWorkspaceController(
                request: MacWorkspaceTabRequest(workspaceID: id, startsEmpty: false,
                                                initialPaneIntent: MacWorkspacePaneIntent.local.startingWithoutTmux()),
                defaults: defaults)
            tab.saveIfUnsaved()
            #expect(tab.focusedPane?.intent.localTmuxSession == nil && tab.focusedPane?.intent.withoutTmux == true)
            #expect(fake.claims.isEmpty)
            tab.addPane(intent: .local, axis: .horizontal)
            let names = tab.state.root?.panes.map(\.intent.localTmuxSession) ?? []
            #expect(names.count == 2 && names[0] == nil && names[1] != nil)
            #expect(fake.claims.count == 1, "only the ordinary pane's")
            let relaunched = MacWorkspaceController(workspaceID: id, defaults: defaults)
            #expect(relaunched.state.root?.panes.map(\.intent.withoutTmux) == [true, false])
            #expect(relaunched.state.root?.panes.first?.intent.localTmuxSession == nil, "still plain")
        }
    }

    @Test("⌃⌘T's tab: a plain shell, in the folder of the terminal in front")
    func plainTabFollowsFolder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plain-tab-\(UUID())").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try await withFake { fake, defaults in
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(tabs: [MacWorkspaceTabRequest(initialPaneIntent: .local)]), defaults: defaults)
            defer { window.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
            let lookups = MacLocalShellFolder.Lookups(tmuxDirectory: { _ in folder }, isFolder: MacLocalShellFolder.Lookups.folderExists)
            let claimed = fake.claims.count
            let tab = try #require(await window.addTabStartingWhereFocusedIs(
                repeating: MacLocalTerminalStart.intent(in: nil).startingWithoutTmux(), lookups: lookups))
            let pane = try #require(tab.focusedPane)
            #expect(pane.intent.withoutTmux && pane.intent.localTmuxSession == nil)
            #expect(pane.intent.localDirectory == folder)
            #expect(fake.claims.count == claimed, "no session made for it")
        }
    }

    @Test("an SSH pane opened without tmux on a host that keeps them in it: nothing claimed, no attach line, plain after a relaunch")
    func plainSSHPane() async throws {
        try await withFake { _, defaults in
            let manager = MacWorkgroupTmuxTests.HostManager(loadImmediately: false)
            let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
            let serverID = UUID()
            let tab = MacWorkspaceController(
                request: MacWorkspaceTabRequest(workspaceID: UUID(), startsEmpty: false, initialPaneIntent: .local),
                defaults: defaults)
            tab.saveIfUnsaved()
            defer { tab.closeAllSessions(sessionManager: manager) }
            tab.requestSSHPane(axis: .horizontal)
            tab.addSSHPane(serverID: serverID, withoutTmux: true)
            let pane = try #require(tab.state.root?.panes.first { $0.intent.kind == .ssh })
            #expect(pane.intent.withoutTmux)

            await tab.prepareSSHPaneIfNeeded(pane, sessionManager: manager, settingsManager: settings)
            let session = try #require(tab.session(for: pane.id))
            await session.waitUntilTerminalWritesComplete()
            #expect(session.withoutTmux && !session.usesTmux, "the host keeps terminals in tmux; this one is plain")
            #expect(manager.host.claims.isEmpty && manager.writes.lines.isEmpty, "no session claimed, nothing typed")

            let relaunched = MacWorkspaceController(workspaceID: tab.workspaceID, defaults: defaults)
            #expect(relaunched.state.root?.panes.first { $0.intent.kind == .ssh }?.intent.withoutTmux == true)
        }
    }

    @Test("Connect without tmux opens a window whose pane is plain, so it is plain after a relaunch")
    func connectWithoutTmuxWindow() {
        var server = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")
        server.tmux = true
        let session = TerminalSession(server: server)
        session.withoutTmux = true
        let broker = MacLiveSessionBroker()
        let request = MacLiveSessionWorkspaceRouter.launchRequest(for: session, sessionManager: SessionManager(loadImmediately: false),
                                                                  broker: broker)
        #expect(request.initialPaneIntent?.withoutTmux == true)
        let ordinary = MacLiveSessionWorkspaceRouter.launchRequest(for: TerminalSession(server: server),
                                                                   sessionManager: SessionManager(loadImmediately: false), broker: broker)
        #expect(ordinary.initialPaneIntent?.withoutTmux == false)
    }

    @Test("a workgroup keeps a plain terminal plain: opened from it, and saved into it again")
    func workgroups() async throws {
        try await withFake { fake, defaults in
            var server = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")
            server.tmux = true
            let preset = LayoutPreset(name: "Desk", sessionIntents: [
                .init(kind: .local, withoutTmux: true),
                .init(serverID: server.id, withoutTmux: true),
                .init(serverID: server.id),
            ])
            let broker = MacStartupCommandBroker()
            let request = try MacWorkgroupLauncher.launch(preset: preset, broker: broker, openWindow: { _ in })[0]
            let panes = request.tabs.flatMap { $0.initialState?.root?.panes ?? [] }
            #expect(panes.map(\.intent.withoutTmux) == [true, true, false])

            let window = MacWorkspaceWindowController(request: request, startupCommandBroker: broker, defaults: defaults)
            defer { window.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
            #expect(fake.claims.isEmpty, "the plain local terminal makes no session")
            let saved = try window.capturePreset(name: "Desk", servers: [server])
            #expect(saved.sessionIntents.map(\.withoutTmux) == [true, true, false])
        }
    }
}
}
#endif
