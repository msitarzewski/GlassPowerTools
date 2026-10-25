import Foundation
import SwiftUI
import Testing
import GlassConnectionKit
import GlassHostCatalog
import GlassLayers
@testable import GlassShell

/// D86: This Mac and the library machine that is the same Mac, one on this device. The machine's row
/// stands for This Mac, its Terminal opens a shell here, and nothing about it is synced.
@MainActor
@Suite("This Mac's own machine")
struct GlassThisMacLinkTests {
    /// The terminal's built-in Local Shell, and what it was asked to open.
    @MainActor final class Shell: GlassCapability {
        static let endpointID = EndpointID(rawValue: UUID(uuidString: "4c4f4341-4c00-0000-0000-5348454c4c00")!)
        let kind: HostServiceKind = .ssh
        var displayName: String { "Terminal" }
        var symbolName: String { "terminal" }
        var opened: [(service: HostServiceLink, host: HostProfile)] = []
        func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
            opened.append((service, host))
            report(.connected)
        }
        func builtInLocalServices() -> [HostServiceLink] {
            [HostServiceLink(endpointID: Self.endpointID, kind: .ssh, displayName: "Local Shell")]
        }
        var supportsLocalSetup: Bool { false }
    }

    @MainActor final class Database: GlassCapability {
        let kind: HostServiceKind = .database
        var displayName: String { "Database" }
        var symbolName: String { "cylinder" }
        var opened: [(service: HostServiceLink, host: HostProfile)] = []
        func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
            opened.append((service, host))
        }
    }

    private struct Fixture {
        let model: GlassShellModel
        let root: URL
        let shell: Shell
        let database: Database
        let machine: HostID
        let terminal: HostServiceLink
    }

    private func makeModel(root: URL, shell: Shell, database: Database) -> GlassShellModel {
        let registry = GlassCapabilityRegistry()
        registry.register(shell)
        registry.register(database)
        return GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                               sharedContainerURL: root.appendingPathComponent("group"),
                               resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                               layers: GlassLayerStore.forTest(), registry: registry)
    }

    /// This Mac, and alpha: a machine with a Terminal and a database.
    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThisMacLink-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let shell = Shell(), database = Database()
        let model = makeModel(root: root, shell: shell, database: database)
        await model.load()
        let machine = try await model.addHost(displayName: "alpha", address: "192.0.2.10")
        let terminal = try await model.addService(kind: .ssh, displayName: "Terminal on alpha", to: machine.id)
        _ = try await model.addService(kind: .database, displayName: "MySQL on alpha", to: machine.id)
        return Fixture(model: model, root: root, shell: shell, database: database, machine: machine.id, terminal: terminal)
    }

    @Test("linked, the machine's row is This Mac's: one row, first, saying so; This Mac's ids find it")
    func folds() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(f.model.hosts.contains { $0.id == GlassLocalHost.id }, "two rows before")

        f.model.setThisMac(f.machine)
        let first = try #require(f.model.hosts.first)
        #expect(first.id == f.machine && first.isThisMac && !first.isLocal)
        #expect(!f.model.hosts.contains { $0.id == GlassLocalHost.id }, "This Mac's row folded in")
        #expect(f.model.hosts.filter { $0.id == f.machine }.count == 1)
        #expect(first.services.filter { $0.kind == .ssh }.count == 1, "one Terminal: the machine's")
        #expect(f.model.host(GlassLocalHost.id)?.id == f.machine, "what was This Mac's is the machine's")
        #expect(f.model.host(owningEndpoint: Shell.endpointID)?.id == f.machine, "a local terminal's machine")
        #expect(f.model.items.first?.subtitle.hasPrefix(GlassLocalHost.displayName) == true)
    }

    @Test("its Terminal opens a shell here, as This Mac; its database opens as itself")
    func connects() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.model.setThisMac(f.machine)
        f.model.connect(hostID: f.machine, endpointID: f.terminal.endpointID)
        let opened = try #require(f.shell.opened.last)
        #expect(opened.service.endpointID == Shell.endpointID, "the local shell, not SSH to itself")
        #expect(opened.host.id == GlassLocalHost.id)

        let database = try #require(f.model.host(f.machine)?.services.first { $0.kind == .database })
        f.model.connect(hostID: f.machine, endpointID: database.endpointID)
        #expect(f.database.opened.last?.host.id == f.machine)
    }

    @Test("kept on this device across launches; unlinking brings This Mac's row back")
    func persists() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.model.setThisMac(f.machine)
        let again = makeModel(root: f.root, shell: Shell(), database: Database())
        await again.load()
        #expect(again.thisMacHostID == f.machine)
        #expect(again.hosts.first?.isThisMac == true)
        again.setThisMac(nil)
        #expect(again.hosts.contains { $0.id == GlassLocalHost.id })
        #expect(!again.hosts.contains { $0.isThisMac })
    }

    @Test("a pinned host key links by itself; an address is offered once, and Not Now is remembered")
    func recognises() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.model.thisMacEvidence = { $0.id == f.machine ? .address("192.0.2.10") : nil }
        f.model.recognizeThisMac()
        #expect(f.model.thisMacHostID == nil, "an address only offers")
        #expect(f.model.thisMacSuggestion?.id == f.machine)
        f.model.declineThisMacSuggestion()
        f.model.recognizeThisMac()
        #expect(f.model.thisMacSuggestion == nil, "not offered again")

        f.model.thisMacEvidence = { $0.id == f.machine ? .hostKey : nil }
        f.model.recognizeThisMac()
        #expect(f.model.thisMacHostID == f.machine, "a host key is proof")
    }

    @Test("its remote desktop isn't offered here, where it would show the screen it's on; it stays the machine's")
    func noScreenSharingToItself() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        _ = try await f.model.addService(kind: .rdp, displayName: "alpha", to: f.machine)
        #expect(f.model.host(f.machine)?.services.contains { $0.kind == .rdp } == true, "before")
        f.model.setThisMac(f.machine)
        #expect(f.model.host(f.machine)?.services.contains { $0.kind == .rdp } == false)
        #expect(f.model.record(f.machine)?.services.contains { $0.kind == .rdp } == true, "still in the library")
    }

    @Test("This Mac with services of its own keeps its row; the machine still opens its Terminal here")
    func localWithServices() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        _ = try await f.model.addService(kind: .database, displayName: "SQLite on This Mac", to: GlassLocalHost.id)
        f.model.setThisMac(f.machine)
        #expect(f.model.hosts.contains { $0.id == GlassLocalHost.id })
        #expect(f.model.host(f.machine)?.isThisMac == true)
        f.model.connect(hostID: f.machine, endpointID: f.terminal.endpointID)
        #expect(f.shell.opened.last?.service.endpointID == Shell.endpointID)
    }
}
