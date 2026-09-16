//
//  D26DeviceBoundSyncTests.swift
//  Glass Power Tools — GlassShellTests
//
//  D26 stage 3: a service whose credential cannot leave this device does not appear on any other.
//  A Secure Enclave key is the only one today — hardware material cannot be copied, so a terminal
//  that authenticates with one cannot work anywhere else, and showing it there would be a row that
//  does nothing and has to be explained.
//
//  **The reason `syncingTwiceKeepsIt` exists is the whole suite.** The rule has two halves — redact
//  on publish, re-attach on apply — and the first half alone passes every single-sync test while
//  destroying data on the second: this device publishes the host without its hardware-key service,
//  pulls its own record back as the merge winner, and deletes its own local service. Nothing
//  throws. The configuration is simply gone.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// An account that keeps whatever it was last given, as CloudKit would.
private final class EchoingBackend: GlassCatalogSyncBackend, @unchecked Sendable {
    var remote: [HostProfile] = []
    private(set) var saveCount = 0
    func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?) {
        (remote, Data("token".utf8))
    }
    func save(_ profiles: [HostProfile]) async throws {
        saveCount += 1
        for profile in profiles {
            if let index = remote.firstIndex(where: { $0.id == profile.id }) { remote[index] = profile }
            else { remote.append(profile) }
        }
    }
}

/// Reports whichever endpoints the test declares device-bound, and records removals.
@MainActor
private final class BindingCapability: GlassCapability {
    let kind: HostServiceKind = .ssh
    let displayName = "Binder"
    let symbolName = "lock"
    var deviceBound: Set<EndpointID> = []
    private(set) var removed: [EndpointID] = []

    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.failed("not used")) }
    func credential(for service: HostServiceLink, host: HostProfile) -> GlassServiceCredential {
        // A key id per endpoint so "device-bound" and "shared" are the same answer here as in the
        // app: binding is a property of the credential, not of the service.
        guard deviceBound.contains(service.endpointID) else { return .ownedByService }
        return .sharedKey(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, deviceBound: true)
    }
    func removeService(_ service: HostServiceLink, host: HostProfile) async throws {
        removed.append(service.endpointID)
    }
}

@MainActor
@Suite("A device-bound service stays on its device (D26 stage 3)")
struct D26DeviceBoundSyncTests {

    private func makeShell() throws -> (GlassShellModel, BindingCapability, EchoingBackend, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D26Bound-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        let capability = BindingCapability()
        model.registry.register(capability)
        return (model, capability, EchoingBackend(), root)
    }

    @Test func aDeviceBoundServiceIsNeverPublished() async throws {
        let (model, capability, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let bound = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                 address: "oscar.example", serviceName: "Hardware key")
        let portable = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                    address: "oscar.example", serviceName: "Password")
        capability.deviceBound = [bound]

        model.enableCatalogSync(backend)
        await model.synchronizeCatalog()

        let published = try #require(backend.remote.first)
        #expect(published.services.map(\.endpointID) == [portable],
                "a service that cannot leave this device was published to the account")
        // And it is still here, where it works.
        #expect(Set(model.services(for: published.id).map(\.endpointID)) == [bound, portable])
    }

    /// The one that catches the dangerous bug. One sync proves nothing.
    @Test func syncingTwiceKeepsTheDeviceBoundService() async throws {
        let (model, capability, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let bound = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                 address: "oscar.example", serviceName: "Hardware key")
        capability.deviceBound = [bound]
        let hostID = try #require(model.records.first).id

        model.enableCatalogSync(backend)
        await model.synchronizeCatalog()

        // **This is the line that makes the test bite, and it was missing at first.** Simply
        // syncing twice proves nothing: the account echoes back the redacted record with the *same*
        // `updatedAt`, so the merge keeps the local copy and applies nothing at all — the test
        // passed with the re-attach deleted. The record has to come back *newer*, which is what
        // happens the moment any other device touches the host, or this one edits it again.
        var touchedElsewhere = try #require(backend.remote.first)
        touchedElsewhere.updatedAt = Date(timeIntervalSinceNow: 60)
        backend.remote = [touchedElsewhere]

        await model.synchronizeCatalog()

        #expect(model.services(for: hostID).map(\.endpointID) == [bound],
                "the second sync pulled back this device's own redacted record and deleted the service")
        #expect(capability.removed.isEmpty,
                "the credential was deleted for a service that only ever existed here")
    }

    /// Stage 2 must not read "absent because redacted" as "deleted on another device".
    @Test func aRedactedServiceIsNotMistakenForOneDeletedElsewhere() async throws {
        let (model, capability, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let bound = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                 address: "oscar.example", serviceName: "Hardware key")
        capability.deviceBound = [bound]
        let mine = try #require(model.records.first)

        // Another device edits the host. Its copy has never contained the bound service.
        var elsewhere = mine
        elsewhere.services = []
        elsewhere.displayName = "oscar renamed elsewhere"
        elsewhere.updatedAt = Date(timeIntervalSinceNow: 60)
        backend.remote = [elsewhere]

        model.enableCatalogSync(backend)
        await model.synchronizeCatalog()

        #expect(capability.removed.isEmpty, "stage 2 deleted the credential of a redacted service")
        #expect(model.services(for: mine.id).map(\.endpointID) == [bound])
    }

    /// Binding is derived, so unbinding a service makes it start travelling with no flag to clear.
    @Test func aServiceThatStopsBeingDeviceBoundStartsPublishing() async throws {
        let (model, capability, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let endpoint = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                    address: "oscar.example", serviceName: "Terminal")
        capability.deviceBound = [endpoint]
        model.enableCatalogSync(backend)
        await model.synchronizeCatalog()
        #expect(backend.remote.first?.services.isEmpty == true)

        // The user switches it from a hardware key to a password.
        capability.deviceBound = []
        try await model.updateHost(try #require(model.records.first).id, displayName: "oscar",
                                   address: "oscar.example", aliases: [], tags: [])
        await model.synchronizeCatalog()

        #expect(backend.remote.first?.services.map(\.endpointID) == [endpoint])
    }
}
