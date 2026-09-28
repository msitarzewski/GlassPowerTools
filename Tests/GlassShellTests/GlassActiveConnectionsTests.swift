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
        init(kind: HostServiceKind, displayName: String) { self.kind = kind; self.displayName = displayName }
        func open(service: HostServiceLink, host: HostProfile,
                  report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.dismissed) }
        func openSessions() -> [GlassOpenSession] { sessions }
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
        let beastTerminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on bravo")
        let alpha = try HostProfile(displayName: "alpha", address: "10.0.0.1", services: [alphaTerminal, alphaDatabase])
        let foxtrot = try HostProfile(displayName: "bravo", address: "10.0.0.2", services: [beastTerminal])
        try await store.upsert(alpha); try await store.upsert(foxtrot)

        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.sessions = [session("terminal:1", title: "alpha", endpoints: [alphaTerminal.endpointID]),
                             session("terminal:2", title: "bravo", endpoints: [beastTerminal.endpointID])]
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
