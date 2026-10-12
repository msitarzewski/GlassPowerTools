import Foundation
import Testing
import GlassLayers
@testable import GlassTerminal

/// A terminal opened without tmux on a host that keeps its terminals in it (the owner,
/// 2026-10-12: "allow remote sessions without tmux too even if it's been selected as default"):
/// a plain shell, on every device, kept plain through a workgroup and a relaunch.
@MainActor
@Suite("Terminals without tmux")
struct TerminalWithoutTmuxTests {
    private func tmuxServer() -> ServerConfiguration {
        var server = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")
        server.tmux = true
        return server
    }

    @Test("opened without tmux, a terminal is a plain shell though its host keeps terminals in tmux")
    func session() {
        let ordinary = TerminalSession(server: tmuxServer())
        #expect(ordinary.usesTmux)
        let plain = TerminalSession(server: tmuxServer())
        plain.withoutTmux = true
        #expect(!plain.usesTmux)
        plain.tmuxSessionName = "glass-1"
        #expect(!plain.usesTmux, "the choice holds over a name it was somehow given")
    }

    @Test("a workgroup's plain terminal is saved as one, read back, and written only when it is one")
    func intentCoding() throws {
        let serverID = UUID()
        let plain = LayoutPreset.SessionIntent(serverID: serverID, tmuxSession: "glass-3", withoutTmux: true)
        #expect(plain.withoutTmux && plain.tmuxSession == nil, "plain: no session to attach to")
        let local = LayoutPreset.SessionIntent(kind: .local, withoutTmux: true)
        for intent in [plain, local] {
            let decoded = try JSONDecoder().decode(LayoutPreset.SessionIntent.self, from: JSONEncoder().encode(intent))
            #expect(decoded == intent && decoded.isSupported)
        }
        let ordinary = String(decoding: try JSONEncoder().encode(LayoutPreset.SessionIntent(serverID: serverID)), as: UTF8.self)
        #expect(!ordinary.contains("withoutTmux"), "nothing new written for an ordinary terminal")
        var object = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(LayoutPreset.SessionIntent(serverID: serverID, tmuxSession: "work"))) as? [String: Any])
        object["withoutTmux"] = true
        let marked = try JSONDecoder().decode(LayoutPreset.SessionIntent.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(marked.withoutTmux && marked.tmuxSession == nil)
    }

    @Test("a menu that says \"Terminal on\" names the machine: never \"Terminal on Terminal on oscar\"")
    func machineTitles() {
        #expect(GlassTerminalRuntime.machineTitle(serverName: "Terminal on oscar", hostName: "oscar") == "oscar")
        #expect(GlassTerminalRuntime.machineTitle(serverName: "oscar", hostName: "oscar") == "oscar")
        #expect(GlassTerminalRuntime.machineTitle(serverName: "Admin shell", hostName: "oscar") == "oscar — Admin shell",
                "a terminal named something else: both, so two on one machine are told apart")
        #expect(GlassTerminalRuntime.machineTitle(serverName: "Terminal on alpha", hostName: nil) == "alpha",
                "no catalog: the default prefix a host sheet gives it comes off")
        #expect(GlassTerminalRuntime.machineTitle(serverName: "bravo", hostName: "  ") == "bravo")
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore())
        var server = ServerConfiguration(name: "Terminal on alpha", host: "alpha.example.com", username: "ann")
        runtime.hostName = { $0 == server.id ? "Alpha Lab" : nil }
        #expect(runtime.machineTitle(of: server) == "Alpha Lab",
                "a default name from before the machine was renamed: the machine's name now")
        server.name = "Admin shell"
        #expect(runtime.machineTitle(of: server) == "Alpha Lab — Admin shell")

        var root = ServerConfiguration(name: "Terminal on alpha", host: "alpha.example.com", username: "root")
        root.name = "Terminal on alpha"
        let ann = ServerConfiguration(name: "Terminal on alpha", host: "alpha.example.com", username: "ann")
        let bravo = ServerConfiguration(name: "Terminal on bravo", host: "bravo.example.com", username: "ann")
        let titles = GlassTerminalRuntime.distinguished([(root, "alpha"), (ann, "alpha"), (bravo, "bravo")]).map(\.title)
        #expect(titles == ["alpha (root)", "alpha (ann)", "bravo"], "two on one machine are told apart; one alone is not")
    }

    @Test("Connect without tmux and a plain local terminal reach the connect flow as asked")
    func requests() {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore())
        let serverID = UUID()
        runtime.requestConnect(serverID: serverID, withoutTmux: true)
        runtime.requestConnect(serverID: serverID)
        runtime.requestLocalTerminal(withoutTmux: true)
        let requests = runtime.takeRequests()
        guard requests.count == 3,
              case .connect(let first, _, _, nil, true) = requests[0],
              case .connect(_, _, _, nil, false) = requests[1],
              case .localTerminal(nil, true) = requests[2] else {
            Issue.record("unexpected requests: \(requests)")
            return
        }
        #expect(first == serverID)
    }

    @Test("reopened after a relaunch, a terminal opened without tmux is plain again; its neighbour in tmux attaches")
    func reopening() async throws {
        let suite = "TerminalWithoutTmux.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = tmuxServer()
        let serverManager = ServerManager(loadImmediately: false, defaults: defaults,
                                          passwordStore: ServerPasswordStore(retrieve: { _ in "unused" },
                                                                             save: { _, _ in }, delete: { _ in }))
        serverManager.servers = [server]
        let manager = SessionManager(serverManager: serverManager, loadImmediately: false)
        defer { manager.closeAllSessions() }
        let workgroup = manager.createWorkgroup(name: "Mixed", colorTag: .purple)
        let inTmux = TerminalSession(server: server)
        inTmux.tmuxSessionName = "glass-1"
        let plain = TerminalSession(server: server)
        plain.withoutTmux = true
        for session in [inTmux, plain] {
            manager.registerSession(session)
            manager.appendSession(session, toWorkgroup: workgroup)
        }
        let record = try #require(TerminalWorkgroupsToReopen(defaults: defaults).current(in: manager).first)
        #expect(record.terminals.map(\.withoutTmux) == [nil, true])

        // Opened again: the plain one is given no session and claims none.
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        let again = TerminalSession(server: server)
        TerminalWorkgroupOpening.prepare(again, for: LayoutRestorationTarget(
            intent: LayoutPreset.SessionIntent(serverID: server.id, withoutTmux: true), server: server, sourceIndex: 0),
            workgroupID: workgroup, settingsManager: settings)
        #expect(again.withoutTmux && !again.usesTmux && again.tmuxSessionClaimed == nil)
    }
}
