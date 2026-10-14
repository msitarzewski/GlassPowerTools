#if os(macOS)
import Foundation
import Testing
import GlassConnectionKit
import GlassHostCatalog
import GlassLayers
@testable import GlassShell

/// The Command Palette's connections come from the library (the owner, 2026-10-14: "Let's get
/// desktops into this command list"): every service of every machine, connected as Connect does.
@Suite("The Command Palette's connections", .serialized)
@MainActor
struct GlassShellPaletteConnectionsTests {
    @MainActor
    private final class Opener: GlassCapability {
        let kind: HostServiceKind
        var displayName: String { "Opener" }
        var symbolName: String { "circle" }
        var opened: [EndpointID] = []
        init(kind: HostServiceKind) { self.kind = kind }
        func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
            opened.append(service.endpointID)
        }
    }

    @Test("a desktop is listed with the terminal and the database, each as Connect opens it")
    func everyKindIsListed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassPaletteConnections-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = GlassCapabilityRegistry()
        let openers = [Opener(kind: .ssh), Opener(kind: .database), Opener(kind: .rdp)]
        openers.forEach(registry.register)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                    layers: GlassLayerStore(), registry: registry)
        let services = [
            HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on alpha"),
            HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "MySQL on alpha"),
            HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "alpha"),
        ]
        let store = HostCatalogStore(fileURL: root.appendingPathComponent("group/GlassHostCatalog/hosts.json"))
        try await store.upsert(try HostProfile(displayName: "alpha", services: services))
        await model.load()

        var opened = 0
        let entries = model.paletteConnections(openConnections: { opened += 1 })
        #expect(entries.map(\.title) == ["Connect: Terminal on alpha", "Connect: MySQL on alpha", "Connect: Desktop on alpha"])
        #expect(entries.map(\.detail) == ["Terminal · alpha", "Database · alpha", "Desktop · alpha"])
        try #require(entries.last).action()
        #expect(openers[2].opened == [services[2].endpointID], "the desktop, as the library's Connect opens it")
        #expect(opened == 1, "with no Connections window open, one is opened to carry the connection out")
    }

    @Test("a kind this build cannot open is not offered")
    func unavailableKindIsLeftOut() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassPaletteConnections-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = GlassCapabilityRegistry()
        registry.register(Opener(kind: .ssh))
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                    layers: GlassLayerStore(), registry: registry)
        let store = HostCatalogStore(fileURL: root.appendingPathComponent("group/GlassHostCatalog/hosts.json"))
        try await store.upsert(try HostProfile(displayName: "bravo", services: [
            HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on bravo"),
            HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "Desktop on bravo"),
        ]))
        await model.load()
        #expect(model.paletteConnections(openConnections: {}).map(\.title) == ["Connect: Terminal on bravo"])
    }

    @Test("a service's name carries its machine once")
    func names() throws {
        let host = GlassShellHost(members: [try HostProfile(displayName: "alpha", services: [])])
        func name(_ displayName: String, _ kind: HostServiceKind) -> String {
            GlassShellModel.paletteName(of: HostServiceLink(endpointID: EndpointID(), kind: kind, displayName: displayName), on: host)
        }
        #expect(name("", .rdp) == "Desktop on alpha")
        #expect(name("alpha", .rdp) == "Desktop on alpha")
        #expect(name("Terminal", .ssh) == "Terminal on alpha")
        #expect(name("MySQL on alpha", .database) == "MySQL on alpha")
        #expect(name("reports", .database) == "reports on alpha")
    }
}
#endif
