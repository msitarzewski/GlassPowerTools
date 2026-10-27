import Foundation
import Testing
import GlassLayers
@testable import GlassTerminal

/// A terminal window's own name (the owner, 2026-10-25, on the headset: "need a way to name windows
/// (They all say 'Terminal on [his Mac]'). Also moving a tab … only shows maximized windows (or it
/// grouped them since they all have the same name)").
@MainActor
@Suite("A terminal window's name")
struct TerminalWindowNameTests {
    private func server(_ name: String) -> ServerConfiguration {
        ServerConfiguration(name: name, host: "\(name).example.com", username: "ann")
    }

    private func withManager(_ servers: [ServerConfiguration], _ body: (SessionManager) throws -> Void) throws {
        let suite = "TerminalWindowName.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let serverManager = ServerManager(loadImmediately: false, defaults: defaults,
                                          passwordStore: ServerPasswordStore(retrieve: { _ in "unused" },
                                                                             save: { _, _ in }, delete: { _ in }))
        serverManager.servers = servers
        let manager = SessionManager(serverManager: serverManager, loadImmediately: false)
        defer { manager.closeAllSessions() }
        try body(manager)
    }

    /// A window on `server` with one terminal in it, never connected.
    private func window(on server: ServerConfiguration, in manager: SessionManager) -> UUID {
        let id = manager.createWorkgroup(name: server.name, colorTag: .blue)
        let session = TerminalSession(server: server)
        manager.registerSession(session)
        manager.appendSession(session, toWorkgroup: id)
        return id
    }

    private func title(_ id: UUID, _ manager: SessionManager) throws -> String {
        GlassTerminalCapability.title(of: try #require(manager.workgroup(for: id)), live: manager.sessions(inWorkgroup: id))
    }

    @Test("a name given titles the window, trimmed; a blank one gives it back its own")
    func naming() throws {
        let alpha = server("alpha")
        try withManager([alpha]) { manager in
            let id = window(on: alpha, in: manager)
            let own = try title(id, manager)
            manager.renameWorkgroup(id, to: "  Builds ")
            #expect(try title(id, manager) == "Builds")
            #expect(manager.workgroup(for: id)?.displayName == "Builds")
            manager.renameWorkgroup(id, to: "   ")
            #expect(manager.workgroup(for: id)?.givenName == nil)
            #expect(try title(id, manager) == own)
            #expect(manager.workgroup(for: id)?.name == "alpha", "what it was opened as is untouched")
        }
    }

    @Test("Move Tab To tells two windows on one machine apart by the names given them")
    func moveTabTo() throws {
        let alpha = server("alpha")
        try withManager([alpha]) { manager in
            let from = window(on: alpha, in: manager)
            let builds = window(on: alpha, in: manager)
            let logs = window(on: alpha, in: manager)
            manager.renameWorkgroup(builds, to: "Builds")
            manager.renameWorkgroup(logs, to: "Logs")
            let destinations = TerminalTabMoves.destinations(from: from, among: nil, in: manager)
            #expect(destinations.map(\.id) == [builds, logs])
            #expect(destinations.map(\.title) == ["Builds", "Logs"])
        }
    }

    @Test("the reopen list keeps the name given; a list written before it reads none")
    func reopened() throws {
        let record = TerminalWorkgroupReopenRecord(
            id: UUID(), name: "alpha", colorTag: .blue,
            terminals: [.init(serverID: UUID(), tmuxSession: "glass-1", label: nil, name: nil)],
            selectedIndex: 0, isShown: false, givenName: "Builds")
        let back = try JSONDecoder().decode(TerminalWorkgroupReopenRecord.self, from: JSONEncoder().encode(record))
        #expect(back.givenName == "Builds")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "givenName")
        let earlier = try JSONDecoder().decode(TerminalWorkgroupReopenRecord.self,
                                               from: JSONSerialization.data(withJSONObject: object))
        #expect(earlier.givenName == nil && earlier.terminals == record.terminals)
    }
}
