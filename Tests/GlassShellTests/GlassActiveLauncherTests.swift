import Foundation
import Testing
import GlassConnectionKit
import GlassHostCatalog
import GlassLayers
@testable import GlassShell

/// Active, when nothing is open: the library's machines under the service they have.
@Suite("Active offers the machines to connect to while nothing is open")
@MainActor
struct GlassActiveLauncherTests {
    private final class StubCapability: GlassCapability {
        let kind: HostServiceKind
        let displayName: String
        let symbolName = "circle"
        var builtIn: [HostServiceLink] = []
        init(kind: HostServiceKind, displayName: String) { self.kind = kind; self.displayName = displayName }
        func open(service: HostServiceLink, host: HostProfile,
                  report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.dismissed) }
        func builtInLocalServices() -> [HostServiceLink] { builtIn }
    }

    private func makeModel() throws -> (GlassShellModel, URL, HostCatalogStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassActiveLauncher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false, layers: GlassLayerStore.forTest())
        let store = HostCatalogStore(fileURL: root.appendingPathComponent("group/GlassHostCatalog/hosts.json"))
        return (model, root, store)
    }

    @Test("Terminal, Database, Desktop in turn, each machine in the library's order")
    func machinesBySection() async throws {
        let (model, root, store) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let bravoTerminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on bravo")
        let bravoDesktop = HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "Desktop on bravo")
        let alphaDatabase = HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "MySQL on alpha")
        let alphaTerminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on alpha")
        let alphaOps = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Ops shell")
        let charlieDatabase = HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "charlie")
        try await store.upsert(try HostProfile(displayName: "bravo", address: "192.0.2.2", services: [bravoTerminal, bravoDesktop]))
        try await store.upsert(try HostProfile(displayName: "alpha", address: "192.0.2.1",
                                               services: [alphaDatabase, alphaTerminal, alphaOps]))
        try await store.upsert(try HostProfile(displayName: "charlie", address: "192.0.2.3", services: [charlieDatabase]))
        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.builtIn = [HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Local Shell")]
        // Desktop and database registered first: the order offered is the setup's tabs, not
        // registration's, nor the kinds' own (Desktop, Terminal, Database).
        model.registry.register(StubCapability(kind: .rdp, displayName: "Desktop"))
        model.registry.register(StubCapability(kind: .database, displayName: "Database"))
        model.registry.register(terminal)
        await model.load()

        let launcher = model.activeLauncher()
        #expect(launcher.sections.map(\.kind) == [.ssh, .database, .rdp])
        let terminals = launcher.sections[0].entries
        #expect(terminals.map(\.endpointID) == [terminal.builtIn[0].endpointID, alphaTerminal.endpointID,
                                                alphaOps.endpointID, bravoTerminal.endpointID],
                "this device first, then the library's order, each machine's terminals in its own order")
        #expect(terminals.map(\.detail) == ["Local Shell", nil, "Ops shell", nil],
                "a service's name is shown only where it says more than its heading and machine")
        #expect(terminals.dropFirst().map(\.machine) == ["alpha", "alpha", "bravo"])
        let databases = launcher.sections[1].entries
        #expect(databases.map(\.machine) == ["alpha", "charlie"])
        #expect(databases.map(\.detail) == ["MySQL on alpha", nil])
        #expect(launcher.sections[2].entries.map(\.endpointID) == [bravoDesktop.endpointID])
    }

    @Test("A kind this build has no capability for is not offered: choosing it would only say so")
    func unopenableKindsAreLeftOut() async throws {
        let (model, root, store) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let terminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on alpha")
        let desktop = HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "Desktop on alpha")
        try await store.upsert(try HostProfile(displayName: "alpha", address: "192.0.2.1", services: [terminal, desktop]))
        model.registry.register(StubCapability(kind: .ssh, displayName: "Terminal"))
        await model.load()
        #expect(model.activeLauncher().sections.map(\.kind) == [.ssh])
    }

    @Test("Nothing to offer when no machine has a service")
    func emptyLibrary() async throws {
        let (model, root, _) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        model.registry.register(StubCapability(kind: .ssh, displayName: "Terminal"))
        await model.load()
        #expect(model.activeLauncher().isEmpty)
    }
}
