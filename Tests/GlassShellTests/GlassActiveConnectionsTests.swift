import SwiftUI
import GlassLayers
import Foundation
import Testing
import GlassConnectionKit
import GlassHostCatalog
import GlassConnectionUI
@testable import GlassShell

/// Active: the live sessions, grouped by the machine each one is on.
@Suite("Active groups live sessions by machine")
@MainActor
struct GlassActiveConnectionsTests {
    private final class StubCapability: GlassCapability {
        let kind: HostServiceKind
        let displayName: String
        let symbolName = "circle"
        var sessions: [GlassOpenSession] = []
        var running: [GlassRunningSession] = []
        private(set) var asked = 0
        init(kind: HostServiceKind, displayName: String) { self.kind = kind; self.displayName = displayName }
        func open(service: HostServiceLink, host: HostProfile,
                  report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.dismissed) }
        func openSessions() -> [GlassOpenSession] { sessions }
        func runningSessions() async -> [GlassRunningSession] { asked += 1; return running }
    }

    private func running(_ id: String, on endpoint: EndpointID) -> GlassRunningSession {
        GlassRunningSession(id: id, title: id, symbolName: "terminal", endpointID: endpoint,
                            isAttachedElsewhere: false, open: {}, takeOver: {}, end: {})
    }

    @Test("The green dot: services with a connected session, not ones still connecting or failed")
    func connectedEndpoints() async throws {
        let (model, root, _) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let live = EndpointID(), connecting = EndpointID(), workgroupLive = EndpointID(), workgroupDown = EndpointID()
        let database = StubCapability(kind: .database, displayName: "Database")
        database.sessions = [
            GlassOpenSession(id: "database:1", title: "a", symbolName: "circle", endpointIDs: [live], activate: {}, close: {}),
            GlassOpenSession(id: "database:2", title: "b", symbolName: "circle", endpointIDs: [connecting],
                             activate: {}, close: {}, isConnected: false),
        ]
        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.sessions = [GlassOpenSession(id: "terminal:1", title: "w", symbolName: "circle",
                                              endpointIDs: [workgroupLive, workgroupDown], activate: {}, close: {},
                                              connectedEndpointIDs: [workgroupLive])]
        model.registry.register(database); model.registry.register(terminal)
        await model.load()
        #expect(model.connectedEndpoints() == [live, workgroupLive])
    }

    @Test("D44: sessions running on a machine join its group, and a machine with nothing open here still appears")
    func runningSessionsJoinTheirMachine() async throws {
        let (model, root, store) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let alphaTerminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on alpha")
        let bravoTerminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on bravo")
        try await store.upsert(try HostProfile(displayName: "alpha", address: "10.0.0.1", services: [alphaTerminal]))
        try await store.upsert(try HostProfile(displayName: "bravo", address: "10.0.0.2", services: [bravoTerminal]))
        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.sessions = [session("terminal:1", title: "alpha", endpoints: [alphaTerminal.endpointID])]
        terminal.running = [running("tmux:glass-2", on: alphaTerminal.endpointID),
                            running("tmux:glass-1", on: bravoTerminal.endpointID),
                            running("tmux:nowhere", on: EndpointID())]
        model.registry.register(terminal)
        await model.load()

        #expect(model.activeMachines().flatMap(\.running).isEmpty, "nothing until Active asks")
        await model.refreshRunningSessions()
        let machines = model.activeMachines()
        #expect(machines.map(\.name) == ["alpha", "bravo"])
        #expect(machines[0].sessions.map(\.id) == ["terminal:1"] && machines[0].running.map(\.id) == ["tmux:glass-2"])
        #expect(machines[1].sessions.isEmpty && machines[1].running.map(\.id) == ["tmux:glass-1"])
        #expect(model.activeSessionCount() == 3,
                "W6: the sidebar counts what Active lists — open here, and running on a machine in the library")

        // Opening one takes it off the list at once: it is about to be open here instead.
        let chosen = try #require(model.runningSessions.first { $0.id == "tmux:glass-1" })
        model.open(chosen)
        #expect(!model.runningSessions.contains { $0.id == "tmux:glass-1" })
        #expect(model.activeMachines().flatMap(\.running).map(\.id) == ["tmux:glass-2"])
    }

    /// A capability that reports machines it could not ask, as the terminal does (W6).
    private final class ReportingCapability: GlassCapability {
        let kind: HostServiceKind = .ssh
        let displayName = "Terminal"
        let symbolName = "circle"
        var report = GlassRunningReport()
        func open(service: HostServiceLink, host: HostProfile,
                  report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.dismissed) }
        func runningReport() async -> GlassRunningReport { report }
    }

    @Test("W6: the badge counts running sessions as well as open ones, from the last listing alone")
    func badgeCountsRunningSessions() async throws {
        let (model, root, store) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let terminalOnAlpha = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on alpha")
        try await store.upsert(try HostProfile(displayName: "alpha", address: "192.0.2.1", services: [terminalOnAlpha]))
        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.running = (1...14).map { running("tmux:glass-\($0)", on: terminalOnAlpha.endpointID) }
        model.registry.register(terminal)
        await model.load()

        #expect(model.activeSessionCount() == 0, "nothing is asked to count: none listed yet")
        await model.refreshRunningSessions()
        #expect(model.activeSessionCount() == 14, "fourteen sessions running: the badge says so")
        #expect(model.activeConnectionsPanel().count == 14, "and the sidebar row carries it")
    }

    @Test("The library asks as it appears, so the count is right before Active is opened, and not again for a while")
    func libraryAsksWhenDue() async throws {
        let (model, root, store) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let terminalOnAlpha = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on alpha")
        try await store.upsert(try HostProfile(displayName: "alpha", address: "192.0.2.1", services: [terminalOnAlpha]))
        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.running = (1...15).map { running("tmux:glass-\($0)", on: terminalOnAlpha.endpointID) }
        model.registry.register(terminal)
        await model.load()

        // The owner, 2026-10-09: "the active count is always 0 to start. once you go in it updates to 15".
        await model.refreshRunningSessionsIfDue()
        #expect(terminal.asked == 1)
        #expect(model.activeConnectionsPanel().count == 15, "counted at launch, without opening Active")

        // Back to the front a minute later: the answer stands. Each ask may open SSH connections.
        await model.refreshRunningSessionsIfDue(now: .now + .seconds(60))
        #expect(terminal.asked == 1)
        // After five minutes the library asks again.
        terminal.running.removeLast()
        await model.refreshRunningSessionsIfDue(now: .now + GlassShellModel.runningSessionsMaxAge + .seconds(1))
        #expect(terminal.asked == 2)
        #expect(model.activeConnectionsPanel().count == 14)
    }

    @Test("W6: a session open here comes forward when chosen and stays listed; a skipped machine says why")
    func openHereAndUnchecked() async throws {
        let (model, root, store) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let alphaTerminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on alpha")
        let bravoTerminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on bravo")
        try await store.upsert(try HostProfile(displayName: "alpha", address: "192.0.2.1", services: [alphaTerminal]))
        try await store.upsert(try HostProfile(displayName: "bravo", address: "192.0.2.2", services: [bravoTerminal]))
        final class Opened { var names: [String] = [] }
        let opened = Opened()
        let capability = ReportingCapability()
        capability.report = GlassRunningReport(
            sessions: [GlassRunningSession(id: "tmux:glass-3", title: "shop", symbolName: "terminal",
                                           endpointID: alphaTerminal.endpointID, isAttachedElsewhere: false, isOpenHere: true,
                                           open: { opened.names.append("glass-3") }, takeOver: {}, end: {})],
            unchecked: [GlassUncheckedMachine(endpointID: bravoTerminal.endpointID,
                                              reason: "Not checked: signing in would need your password.")])
        model.registry.register(capability)
        await model.load()
        await model.refreshRunningSessions()

        let machines = model.activeMachines()
        #expect(machines.map(\.name) == ["alpha", "bravo"])
        #expect(machines[1].running.isEmpty && machines[1].notChecked == "Not checked: signing in would need your password.")
        #expect(machines[0].notChecked == nil)
        #expect(model.activeSessionCount() == 1, "a note is not a session")

        let chosen = try #require(model.runningSessions.first)
        model.open(chosen)
        #expect(opened.names == ["glass-3"], "it goes to the window showing it")
        #expect(model.runningSessions.map(\.id) == ["tmux:glass-3"], "and stays listed, open here")
    }

    private func makeModel() throws -> (GlassShellModel, URL, HostCatalogStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassActive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false, layers: GlassLayerStore())
        let store = HostCatalogStore(fileURL: root.appendingPathComponent("group/GlassHostCatalog/hosts.json"))
        return (model, root, store)
    }

    private func session(_ id: String, title: String, endpoints: [EndpointID] = [], host: HostID? = nil) -> GlassOpenSession {
        GlassOpenSession(id: id, title: title, symbolName: "circle", endpointIDs: endpoints, hostID: host,
                         activate: {}, close: {})
    }

    @Test("Sessions land under the machine that owns their service; an editor lands under its project's machine")
    func groupsByMachine() async throws {
        let (model, root, store) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let alphaTerminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on alpha")
        let alphaDatabase = HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "MySQL on alpha")
        let foxtrotTerminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on bravo")
        let alpha = try HostProfile(displayName: "alpha", address: "10.0.0.1", services: [alphaTerminal, alphaDatabase])
        let foxtrot = try HostProfile(displayName: "bravo", address: "10.0.0.2", services: [foxtrotTerminal])
        try await store.upsert(alpha); try await store.upsert(foxtrot)

        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.sessions = [session("terminal:1", title: "alpha", endpoints: [alphaTerminal.endpointID]),
                             session("terminal:2", title: "bravo", endpoints: [foxtrotTerminal.endpointID])]
        let database = StubCapability(kind: .database, displayName: "Database")
        database.sessions = [session("database:1", title: "MySQL on alpha", endpoints: [alphaDatabase.endpointID])]
        model.registry.register(terminal); model.registry.register(database)
        model.registry.registerSessionProvider(id: "editor") { [self] in
            [session("editor:1", title: "notes", host: alpha.id)]
        }
        await model.load()

        let machines = model.activeMachines()
        #expect(machines.map(\.name) == ["alpha", "bravo"], "machines in the order sessions were listed")
        #expect(machines.first?.sessions.map(\.id) == ["terminal:1", "database:1", "editor:1"],
                "the terminal, the database and the editor on alpha are one group")
        #expect(machines.last?.sessions.map(\.id) == ["terminal:2"])
        #expect(model.activeSessionCount() == 4)
    }

    @Test("A session no machine owns is still listed, under Elsewhere, rather than dropped")
    func orphansAreNotHidden() async throws {
        let (model, root, _) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.sessions = [session("terminal:9", title: "a quick connect", endpoints: [EndpointID()])]
        model.registry.register(terminal)
        await model.load()

        let machines = model.activeMachines()
        #expect(machines.map(\.name) == ["Elsewhere"])
        #expect(machines.first?.sessions.map(\.id) == ["terminal:9"])
    }

    @Test("Nothing open is 0 for the sidebar, like every other row")
    func emptyCountIsZero() async throws {
        let (model, root, _) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        #expect(model.activeSessionCount() == 0)
        #expect(model.activeConnectionsPanel().count == 0, "and the panel row carries the 0")
        #expect(model.activeMachines().isEmpty)
    }

    @Test("The bolt asks for the Active panel, and the panel sits in the Library section")
    func boltAndPanel() async throws {
        let (model, root, _) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.panelToShow == nil)
        model.showActiveConnections()
        #expect(model.panelToShow == GlassShellModel.activePanelID)
        let panel = model.activeConnectionsPanel()
        #expect(panel.id == GlassShellModel.activePanelID)
        #expect(panel.sectionTitle == GlassLibraryPanel.librarySectionTitle)
        #expect(panel.title == "Active")
    }
}
