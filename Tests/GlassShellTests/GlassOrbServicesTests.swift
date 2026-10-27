import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// A machine's services on an orb's ring (D88; the owner, 2026-10-25: "add Editor, Database, and
/// Desktop to the orb so it's more of a machine nav"): every one the machine has but the window's own
/// kind, each knowing whether it is open.
@MainActor
@Suite("An orb's machine services")
struct GlassOrbServicesTests {
    @MainActor final class Shell: GlassCapability {
        let kind: HostServiceKind = .ssh
        var displayName: String { "Terminal" }
        var symbolName: String { "terminal" }
        func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
    }

    @MainActor final class Database: GlassCapability {
        let kind: HostServiceKind = .database
        var displayName: String { "Database" }
        var symbolName: String { "cylinder" }
        func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
    }

    @MainActor final class Desktop: GlassCapability {
        let kind: HostServiceKind = .rdp
        var displayName: String { "Desktop" }
        var symbolName: String { "display" }
        func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
    }

    private struct Fixture {
        let model: GlassShellModel
        let root: URL
        let alpha: HostID
        let terminal: EndpointID
        let database: EndpointID
        let desktop: EndpointID
        let bravoTerminal: EndpointID
    }

    /// alpha with a Terminal, a database and a desktop; bravo with a Terminal only. Without
    /// `desktops`, this build has no desktop capability.
    private func fixture(desktops: Bool = true) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OrbServices-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let registry = GlassCapabilityRegistry()
        registry.register(Shell())
        registry.register(Database())
        if desktops { registry.register(Desktop()) }
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore.forTest(), registry: registry)
        await model.load()
        let alpha = try await model.addHost(displayName: "alpha", address: "192.0.2.10")
        let terminal = try await model.addService(kind: .ssh, displayName: "Terminal on alpha", to: alpha.id)
        let database = try await model.addService(kind: .database, displayName: "MySQL on alpha", to: alpha.id)
        let desktop = try await model.addService(kind: .rdp, displayName: "Desktop on alpha", to: alpha.id)
        let bravo = try await model.addHost(displayName: "bravo", address: "192.0.2.11")
        let bravoTerminal = try await model.addService(kind: .ssh, displayName: "Terminal on bravo", to: bravo.id)
        return Fixture(model: model, root: root, alpha: alpha.id, terminal: terminal.endpointID,
                       database: database.endpointID, desktop: desktop.endpointID,
                       bravoTerminal: bravoTerminal.endpointID)
    }

    private func session(_ id: String, _ endpoint: EndpointID) -> GlassOpenSession {
        GlassOpenSession(id: id, title: id, symbolName: "terminal", endpointIDs: [endpoint], activate: {}, close: {})
    }

    @Test("a terminal window's ring has its machine's open database and desktop, in the machine's order, not its terminal")
    func otherServices() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let open = [session("terminal:one", f.terminal), session("desktop:alpha", f.desktop),
                    session("database:shop", f.database)]
        let services = f.model.orbServices(for: [f.terminal], excluding: .ssh, open: open)
        #expect(services.map(\.endpointID) == [f.database, f.desktop])
        #expect(services.map(\.kind) == [.database, .rdp])
        #expect(services.map(\.openSessionID) == ["database:shop", "desktop:alpha"])
        // Named as the library names it.
        #expect(services.map(\.title) == ["MySQL on alpha", "Desktop on alpha"])
        #expect(services.allSatisfy { $0.hostID == f.alpha })
    }

    @Test("a service that isn't open is left off: no ghost services")
    func onlyOpen() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let open = [session("terminal:one", f.terminal), session("database:shop", f.database)]
        #expect(f.model.orbServices(for: [f.terminal], excluding: .ssh, open: open).map(\.endpointID) == [f.database])
        #expect(f.model.orbServices(for: [f.terminal], excluding: .ssh, open: [session("terminal:one", f.terminal)]).isEmpty)
    }

    @Test("with no kind of its own, every open service is there, its terminal included")
    func everyService() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let open = [session("terminal:one", f.terminal), session("database:shop", f.database),
                    session("desktop:alpha", f.desktop)]
        let services = f.model.orbServices(for: [f.database], excluding: nil, open: open)
        #expect(services.map(\.endpointID) == [f.terminal, f.database, f.desktop])
    }

    @Test("the machine is the window's: bravo's terminal brings none of alpha's services")
    func theWindowsMachine() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let open = [session("database:shop", f.database), session("desktop:alpha", f.desktop)]
        #expect(f.model.orbServices(for: [f.bravoTerminal], excluding: .ssh, open: open).isEmpty)
        #expect(f.model.orbServices(for: [EndpointID(rawValue: UUID())], excluding: .ssh, open: open).isEmpty,
                "a server the library doesn't know is on no machine")
    }

    @Test("a kind this build cannot open is left off the ring")
    func noCapability() async throws {
        let f = try await fixture(desktops: false)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let open = [session("database:shop", f.database), session("desktop:alpha", f.desktop)]
        #expect(f.model.orbServices(for: [f.terminal], excluding: .ssh, open: open).map(\.endpointID) == [f.database])
    }
}
