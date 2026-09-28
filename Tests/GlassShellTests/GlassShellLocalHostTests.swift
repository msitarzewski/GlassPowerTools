import Foundation
import SwiftUI
import Testing
import GlassConnectionKit
import GlassHostCatalog
import GlassLayers
@testable import GlassShell

/// The device's own host (D8): always in the library, never in the shared catalog, never asked
/// for an address, never a tunnel, and the first host in the product to carry several services
/// of one kind.

@MainActor private func makeModel(registry: GlassCapabilityRegistry = GlassCapabilityRegistry())
throws -> (GlassShellModel, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassShellLocalHost-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                sharedContainerURL: root.appendingPathComponent("group"),
                                resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                layers: GlassLayerStore(), registry: registry)
    return (model, root)
}

/// A capability with a built-in local service, standing in for the terminal's Local Shell.
@MainActor
private final class LocalShellCapability: GlassCapability {
    static let endpointID = EndpointID(rawValue: UUID(uuidString: "4c4f4341-4c00-0000-0000-5348454c4c00")!)
    let kind: HostServiceKind = .ssh
    var displayName: String { "Terminal" }
    var symbolName: String { "terminal" }
    var opened: [(HostServiceLink, HostProfile)] = []
    var forwards = 0

    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
        opened.append((service, host))
        report(.connected)
    }
    func builtInLocalServices() -> [HostServiceLink] {
        [HostServiceLink(endpointID: Self.endpointID, kind: .ssh, displayName: "Local Shell")]
    }
    var supportsLocalSetup: Bool { false }
    func openPortForward(host: HostProfile, toHost remoteHost: String,
                         port: Int) async throws -> any GlassHostPortForward {
        forwards += 1
        throw GlassPortForwardError.unavailable
    }
    func resolveHostTrust(host: HostProfile) async -> GlassHostTrustOutcome { .trusted }
}

/// A capability that can be set up locally, standing in for the database.
@MainActor
private final class LocalSetupCapability: GlassCapability {
    let kind: HostServiceKind
    var displayName: String { kind.rawValue }
    var symbolName: String { "circle" }
    var opened: [(HostServiceLink, HostProfile)] = []
    /// Addresses the shell committed drafts with.
    var committedAddresses: [String] = []
    init(kind: HostServiceKind) { self.kind = kind }
    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
        opened.append((service, host))
    }
    func makeSetupDraft() -> any GlassServiceDraft { RecordingDraft(kind: kind, capability: self) }
}

@MainActor
private final class RecordingDraft: GlassServiceDraft {
    let kind: HostServiceKind
    private unowned let capability: LocalSetupCapability
    init(kind: HostServiceKind, capability: LocalSetupCapability) {
        self.kind = kind
        self.capability = capability
    }
    func serviceDisplayName(hostName: String) -> String { "\(kind.rawValue) on \(hostName)" }
    func requiredFields() -> AnyView { AnyView(EmptyView()) }
    func advancedFields() -> AnyView { AnyView(EmptyView()) }
    func validate(address: String) -> [GlassSetupIssue] { [] }
    func focusFirstIssue(_ issues: [GlassSetupIssue]) {}
    func commit(endpointID: EndpointID, host: HostProfile, address: String) async throws {
        capability.committedAddresses.append(address)
    }
    func rollback(endpointID: EndpointID) async {}
}

@Suite("The device's own host", .serialized)
@MainActor
struct GlassShellLocalHostTests {
    @Test("It is in the library from the first launch, first, with no address and no catalog record")
    func alwaysPresent() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let local = try #require(model.localHost)
        #expect(model.hosts.first?.id == GlassLocalHost.id, "the machine you are holding comes first")
        #expect(local.isLocal && local.displayName == GlassLocalHost.displayName)
        #expect(local.address == nil && local.addresses.isEmpty, "it has no address and never asks for one")
        #expect(model.catalogHosts.isEmpty, "it is not one of the shared catalog's hosts")
        #expect(model.records.isEmpty, "and it is not one of its records")
        #expect(model.localHostProblem == nil)
    }

    @Test("Its record is written to this app's own file, never to the shared catalog the family reads")
    func neverPublished() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        _ = try await model.addService(kind: .database, displayName: "notes.sqlite", to: GlassLocalHost.id)

        let shared = try await model.catalog.snapshot()
        #expect(shared.isEmpty, "nothing the three source apps read has changed")
        #expect(model.localCatalogFileURL != model.catalogFileURL)
        #expect(!model.localCatalogFileURL.path.contains("group"), "its file is in this app's storage")
        let localRecords = try await model.localCatalog.snapshot()
        #expect(localRecords.map(\.id) == [GlassLocalHost.id])
        #expect(localRecords[0].services.map(\.displayName) == ["notes.sqlite"])
        #expect(localRecords[0].address == nil)
    }

    @Test("Its services and name survive a relaunch")
    func persists() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        _ = try await model.addService(kind: .database, displayName: "golf.sqlite", to: GlassLocalHost.id)
        try await model.updateHost(GlassLocalHost.id, displayName: "My Mac", aliases: [], tags: ["Work"])

        let relaunched = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                         sharedContainerURL: root.appendingPathComponent("group"),
                                         resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                         layers: GlassLayerStore())
        await relaunched.load()
        let local = try #require(relaunched.localHost)
        #expect(local.displayName == "My Mac")
        #expect(local.tags == ["Work"])
        #expect(local.services.map(\.displayName) == ["golf.sqlite"])
    }

    @Test("It never merges with a catalog machine that shares its name")
    func neverGroups() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        // A discovered machine named exactly like the device's host: grouping is by normalised
        // name, so this is the case that would silently swallow the local host if it went
        // through `GlassShellHostGrouping` like everything else.
        _ = try await model.addHost(displayName: GlassLocalHost.displayName, address: "10.0.0.9")
        await model.load()

        #expect(model.hosts.count == 2)
        #expect(model.hosts.filter(\.isLocal).count == 1)
        let discovered = try #require(model.catalogHosts.first)
        #expect(discovered.id != GlassLocalHost.id && discovered.address == "10.0.0.9")
        #expect(model.localHost?.services.isEmpty == true, "the discovered machine's services stayed on it")
    }

    @Test("An address cannot be set on it, and no address is adopted onto it from a service")
    func noAddress() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        await #expect(throws: GlassShellError.localHostHasNoAddress) {
            try await model.setHostAddress("10.0.0.4", for: GlassLocalHost.id)
        }
        #expect(model.localHost?.address == nil)
    }

    @Test("It cannot be deleted; its services are removed one at a time instead")
    func notRemovable() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let link = try await model.addService(kind: .database, displayName: "notes.sqlite", to: GlassLocalHost.id)

        await #expect(throws: GlassShellError.localHostNotRemovable) {
            try await model.deleteHost(GlassLocalHost.id)
        }
        #expect(model.localHost != nil)

        try await model.removeService(link.endpointID, from: GlassLocalHost.id)
        #expect(model.localHost?.services.isEmpty == true)
        #expect(model.localHost != nil, "removing its last service does not remove the host")
    }

    // MARK: Built-in services

    @Test("A capability's built-in local service appears on it, opens, and cannot be edited or removed")
    func builtInService() async throws {
        let registry = GlassCapabilityRegistry()
        let terminal = LocalShellCapability()
        registry.register(terminal)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let local = try #require(model.localHost)
        #expect(local.services.map(\.displayName) == ["Local Shell"])
        #expect(local.isBuiltIn(LocalShellCapability.endpointID))

        model.connect(hostID: GlassLocalHost.id, endpointID: LocalShellCapability.endpointID)
        #expect(terminal.opened.count == 1)
        #expect(terminal.opened.first?.1.id == GlassLocalHost.id, "the local record is handed over, not nothing")

        // Nothing is stored for a built-in, so there is nothing to remove — and it says so
        // rather than reporting the service as missing, which would be a different bug.
        await #expect(throws: GlassShellError.builtInServiceNotEditable("Local Shell")) {
            try await model.removeService(LocalShellCapability.endpointID, from: GlassLocalHost.id)
        }
        #expect(model.localHost?.services.count == 1)
    }

    @Test("A built-in local service is not written to the record, so it never accumulates or duplicates")
    func builtInIsNotStored() async throws {
        let registry = GlassCapabilityRegistry()
        registry.register(LocalShellCapability())
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        await model.load()
        await model.load()

        let stored = try await model.localCatalog.snapshot()
        #expect(stored[0].services.isEmpty, "three loads wrote no links")
        #expect(model.localHost?.services.count == 1, "and the library still shows exactly one")
    }

    // MARK: Setup

    @Test("Setup on it collects no address, commits against loopback, and offers only the kinds that make sense here")
    func setupSkipsTheAddressGate() async throws {
        let registry = GlassCapabilityRegistry()
        let terminal = LocalShellCapability()
        let database = LocalSetupCapability(kind: .database)
        registry.register(terminal)
        registry.register(database)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let local = try #require(model.localHost)

        // Terminal opts out (its local service is the built-in shell); Desktop has no capability
        // in this build, so it stays a disabled tab here as it is everywhere else.
        #expect(GlassShellSetupModel.setupKinds(for: local, registry: registry) == [.database, .rdp])
        #expect(GlassShellSetupModel.setupKinds(for: nil, registry: registry) == [.ssh, .database, .rdp])

        let setup = GlassShellSetupModel(model: model, mode: .addService(local, .database))
        #expect(setup.isLocalHost)
        #expect(!setup.addressEditable, "there is no address field to fill in")
        #expect(setup.validateForSave().host.isEmpty, "and no address gate to fail")

        let id = try #require(await setup.save())
        #expect(id == GlassLocalHost.id)
        #expect(database.committedAddresses == [GlassLocalHost.address],
                "a service here is committed against loopback, not against a blank address")
        #expect(model.localHost?.services.map(\.kind) == [.ssh, .database],
                "built-in first, then the saved one")
    }

    @Test("The sheet never offers to delete it")
    func setupOffersNoDelete() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let local = try #require(model.localHost)
        let setup = GlassShellSetupModel(model: model, mode: .editHost(local))
        #expect(setup.editedHost == nil, "the delete section is what editedHost drives")

        let remote = try await model.addHost(displayName: "Box", address: "10.0.0.9")
        await model.load()
        let remoteHost = try #require(model.host(remote.id))
        #expect(GlassShellSetupModel(model: model, mode: .editHost(remoteHost)).editedHost != nil)
    }

    // MARK: Connecting

    @Test("Connect-the-machine is refused on it; connecting one named service is not")
    func connectAllIsRefused() async throws {
        let registry = GlassCapabilityRegistry()
        let terminal = LocalShellCapability()
        let database = LocalSetupCapability(kind: .database)
        registry.register(terminal)
        registry.register(database)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let db = try await model.addService(kind: .database, displayName: "gpt_test", to: GlassLocalHost.id)

        #expect(model.localHost?.allowsConnectAll == false)
        model.connectAll(hostID: GlassLocalHost.id)
        #expect(terminal.opened.isEmpty && database.opened.isEmpty,
                "a stray connectAll on this device opens nothing at all")
        #expect(model.errorMessage == nil, "and it is not an error the user has to dismiss either")

        model.connect(hostID: GlassLocalHost.id, endpointID: db.endpointID)
        #expect(database.opened.count == 1)
    }

    @Test("A machine you reach still connects all of its services")
    func connectAllStillWorksElsewhere() async throws {
        let registry = GlassCapabilityRegistry()
        let terminal = LocalShellCapability()
        registry.register(terminal)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Box", address: "10.0.0.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)

        model.connectAll(hostID: host.id)
        #expect(terminal.opened.count == 1)
    }

    // MARK: Several services of one kind

    @Test("Three terminals and two databases on one host: icons dedupe, the subtitle counts, and every row is distinguishable")
    func severalServicesOfOneKind() async throws {
        let registry = GlassCapabilityRegistry()
        let terminal = LocalShellCapability()
        let database = LocalSetupCapability(kind: .database)
        registry.register(terminal)
        registry.register(database)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        let created = try await model.addHost(displayName: "Box", address: "10.0.0.9")
        for name in ["Terminal", "Terminal 2", "Terminal 3"] {
            _ = try await model.addService(kind: .ssh, displayName: name, to: created.id)
        }
        for name in ["gpt_test", "gpt_scratch"] {
            _ = try await model.addService(kind: .database, displayName: name, to: created.id)
        }
        let host = try #require(model.host(created.id))

        #expect(host.services.count == 5, "the catalog takes several services of one kind")
        #expect(model.serviceKinds(for: host.id) == [.ssh, .database],
                "the row's icons are one per kind, not one per service")
        #expect(GlassShellModel.subtitle(for: model.serviceKinds(for: host.id)) == "Terminal · Database")

        // Identifiers have to stay unique or UI automation matches an arbitrary row.
        let suffixes = host.services.map { GlassShellLibraryView.identifierSuffix(for: $0, in: host) }
        #expect(suffixes == ["", "-2", "-3", "", "-2"], "the first of a kind keeps the bare identifier")
        let identifiers = zip(host.services, suffixes).map { "host-service-connect-\($0.kind.rawValue)\($1)" }
        #expect(Set(identifiers).count == identifiers.count)

        // connectAll opens every one of them, in the host's own order, and each capability is
        // handed its own service — not the first of its kind five times.
        model.connectAll(hostID: host.id)
        #expect(terminal.opened.map(\.0.displayName) == ["Terminal", "Terminal 2", "Terminal 3"])
        #expect(database.opened.map(\.0.displayName) == ["gpt_test", "gpt_scratch"])
    }

    @Test("Several databases on the device itself are separate services with separate endpoints")
    func severalLocalDatabases() async throws {
        let registry = GlassCapabilityRegistry()
        registry.register(LocalSetupCapability(kind: .database))
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        for name in ["notes.sqlite", "Local MySQL", "Local PostgreSQL"] {
            _ = try await model.addService(kind: .database, displayName: name, to: GlassLocalHost.id)
        }
        let local = try #require(model.localHost)
        #expect(local.services.map(\.displayName) == ["notes.sqlite", "Local MySQL", "Local PostgreSQL"])
        #expect(Set(local.services.map(\.endpointID)).count == 3)
        #expect(local.services.allSatisfy { local.record(owning: $0.endpointID)?.id == GlassLocalHost.id })
    }
}
