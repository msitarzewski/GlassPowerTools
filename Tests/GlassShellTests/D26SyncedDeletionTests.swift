//
//  D26SyncedDeletionTests.swift
//  Glass Power Tools — GlassShellTests
//
//  D26 stage 2: a machine deleted on another device has to clean up what this device's capabilities
//  stored for it, exactly as deleting it here does.
//
//  D25 fixed the local half — `deleteHost` told the capabilities. The synced half went on orphaning
//  credentials, because the merge applied a tombstone and told nobody. Both paths now run the same
//  `cascadeRemoval`, so what these tests really pin is that the sync reaches it at all.
//
//  Since stage 1 the configuration lives on the service link, so a tombstone takes it along. What
//  the cascade is still for is the **credential**, which has nobody else to remove it.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// Hands back whatever the test says the account holds, and records what was published.
private final class ScriptedBackend: GlassCatalogSyncBackend, @unchecked Sendable {
    var remote: [HostProfile] = []
    var saved: [HostProfile] = []
    func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?) {
        (remote, Data("token".utf8))
    }
    func save(_ profiles: [HostProfile]) async throws { saved.append(contentsOf: profiles) }
}

/// Records every `removeService` the shell asks for. The point of the suite.
@MainActor
private final class RecordingCapability: GlassCapability {
    let kind: HostServiceKind
    let displayName = "Recorder"
    let symbolName = "record.circle"
    private(set) var removed: [EndpointID] = []

    init(kind: HostServiceKind = .ssh) { self.kind = kind }

    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.failed("not used")) }
    func removeService(_ service: HostServiceLink, host: HostProfile) async throws {
        removed.append(service.endpointID)
    }
}

@MainActor
@Suite("A machine deleted elsewhere cleans up here (D26 stage 2)")
struct D26SyncedDeletionTests {

    private func makeShell() throws -> (GlassShellModel, RecordingCapability, ScriptedBackend, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D26Sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        let capability = RecordingCapability()
        model.registry.register(capability)
        return (model, capability, ScriptedBackend(), root)
    }

    /// A tombstone for a host this device knows: every service on it is cleaned up.
    @Test func atombstoneArrivingFromAnotherDeviceCascades() async throws {
        let (model, capability, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let endpoint = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                    address: "alpha.example", serviceName: "Terminal")
        let mine = try #require(model.records.first)

        // The same record, deleted, as the account would hand it back.
        var tombstone = mine
        tombstone.deletedAt = Date()
        tombstone.updatedAt = Date(timeIntervalSinceNow: 60)
        backend.remote = [tombstone]

        model.enableCatalogSync(backend)
        await model.synchronizeCatalog()

        #expect(capability.removed == [endpoint],
                "a host deleted on another device left this one's credential behind")
        #expect(model.catalogHosts.isEmpty)
    }

    /// The subtler half: the host survives, but one of its services was removed elsewhere.
    @Test func aServiceRemovedElsewhereCascadesWithoutTouchingTheOthers() async throws {
        let (model, capability, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let kept = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                address: "alpha.example", serviceName: "Terminal")
        let dropped = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                   address: "alpha.example", serviceName: "Second")
        let mine = try #require(model.records.first)

        var edited = mine
        edited.services = mine.services.filter { $0.endpointID != dropped }
        edited.updatedAt = Date(timeIntervalSinceNow: 60)
        backend.remote = [edited]

        model.enableCatalogSync(backend)
        await model.synchronizeCatalog()

        #expect(capability.removed == [dropped], "the wrong services were cleaned up")
        #expect(model.services(for: mine.id).map(\.endpointID) == [kept])
    }

    /// An ordinary incoming edit must not be read as a removal.
    @Test func anEditThatRemovesNothingCascadesNothing() async throws {
        let (model, capability, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        _ = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                         address: "alpha.example", serviceName: "Terminal")
        let mine = try #require(model.records.first)

        var renamed = mine
        renamed.displayName = "alpha renamed elsewhere"
        renamed.updatedAt = Date(timeIntervalSinceNow: 60)
        backend.remote = [renamed]

        model.enableCatalogSync(backend)
        await model.synchronizeCatalog()

        #expect(capability.removed.isEmpty, "a rename was treated as a deletion")
    }

    /// A host arriving for the first time has nothing local to have lost.
    @Test func aHostArrivingForTheFirstTimeCascadesNothing() async throws {
        let (model, capability, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        var incoming = try HostProfile(displayName: "bravo", address: "bravo.example")
        incoming.services = [HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal")]
        backend.remote = [incoming]

        model.enableCatalogSync(backend)
        await model.synchronizeCatalog()

        #expect(capability.removed.isEmpty)
        #expect(model.catalogHosts.count == 1)
    }
}
