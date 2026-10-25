//
//  D19SyncPublishTests.swift
//  Glass Power Tools — GlassShellTests
//
//  One deleted machine must not stop the library from ever publishing again.
//
//  Reported 2026-09-16: a database service added on the Mac never reached the phone, while the
//  machine itself and its other two services were already there. The sync's own log, once it had
//  one, said it in a line:
//
//      Sync: 18 local, 17 incoming, 7 to apply, 1 to publish
//      Sync failed: hostDeleted(HostID(EF002C19-…))
//
//  There *was* a record to publish. It never got there. Applying the incoming records used
//  `HostCatalogStore.upsert`, which is the **local-edit** path: it refuses a tombstone by design,
//  because editing a deleted machine is a mistake — and it restamps `updatedAt` and `lastWriterID`
//  as though this device had authored the incoming record. Wrong on both counts for a remote
//  record, and the throw happened before the publish, so a single tombstone anywhere in the account
//  silently froze every future publish from that device.
//
//  `merge(_:)` is the API for incoming records and always was: deletion precedence, revision time,
//  writer id, already tested in the catalog's own suite.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// Hands back whatever the account is said to hold, and records what was published.
private final class ScriptedBackend: GlassCatalogSyncBackend, @unchecked Sendable {
    var remote: [HostProfile] = []
    var saved: [HostProfile] = []
    func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?) {
        (remote, Data("token".utf8))
    }
    func save(_ profiles: [HostProfile]) async throws { saved.append(contentsOf: profiles) }
}

@MainActor
@Suite("Publishing survives a deleted machine (D19)")
struct D19SyncPublishTests {

    private func makeShell() throws -> (GlassShellModel, ScriptedBackend, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D19Publish-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore.forTest())
        let backend = ScriptedBackend()
        model.enableCatalogSync(backend)
        return (model, backend, root)
    }

    /// The reported failure, reduced: one machine deleted here and still present in the account,
    /// and a second machine this device has that the account has never seen.
    @Test func aTombstonedMachineDoesNotBlockPublishingEverythingElse() async throws {
        let (model, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        // A machine that exists on both sides, then is deleted here.
        _ = try await model.adoptService(kind: .ssh, hostName: "retired",
                                         address: "retired.example", serviceName: "Terminal")
        let retired = try #require(model.catalogHosts.first { $0.displayName == "retired" })
        // Captured before the delete: `records` holds only what is still alive.
        var accountCopy = try #require(model.records.first { $0.id == retired.id })
        try await model.deleteHost(retired.id)
        // The account's copy is *also* a tombstone, stamped at a different moment — which is what
        // two devices deleting the same machine produces, and the case that actually threw. A
        // remote tombstone with its own timestamp makes the merge's winner differ from the local
        // record, so the record goes to the apply loop — and the apply loop refuses to touch a
        // machine this device has already deleted.
        accountCopy.deletedAt = Date().addingTimeInterval(60)
        accountCopy.updatedAt = Date().addingTimeInterval(60)

        // A second machine the account has never heard of — the one that has to travel.
        _ = try await model.adoptService(kind: .database, hostName: "alpha",
                                         address: "192.0.2.10", serviceName: "MySQL on alpha")

        // The account still holds the machine this device deleted, exactly as CloudKit would
        // return it until the tombstone reaches it.
        backend.saved.removeAll()
        backend.remote = [accountCopy]

        await model.synchronizeCatalog()

        let publishedNames = Set(backend.saved.map(\.displayName))
        #expect(publishedNames.contains("alpha"),
                "nothing was published: applying the incoming record for a deleted machine stopped the sync")
        if case .failed(let reason) = model.catalogSyncStatus {
            Issue.record("the sync reported a failure: \(reason)")
        }
    }

    /// The tombstone still wins. Fixing the publish must not resurrect a machine the user deleted
    /// — the rule the catalog's own merge already enforces, and the reason this is `merge` rather
    /// than a relaxed `upsert`.
    @Test func anIncomingRecordDoesNotResurrectAMachineDeletedHere() async throws {
        let (model, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        _ = try await model.adoptService(kind: .ssh, hostName: "retired",
                                         address: "retired.example", serviceName: "Terminal")
        let retired = try #require(model.catalogHosts.first { $0.displayName == "retired" })
        var accountCopy = try #require(model.records.first { $0.id == retired.id })
        accountCopy.displayName = "retired, renamed elsewhere"
        try await model.deleteHost(retired.id)

        backend.remote = [accountCopy]
        await model.synchronizeCatalog()

        #expect(!model.hosts.contains { $0.displayName.hasPrefix("retired") },
                "a machine deleted here came back from the account")
    }

    /// The same with the service set up, as every real machine's is (2026-10-17). The merge's
    /// second pass revived any set-up service no live record held: it adopted the account's older
    /// copy instead of sending the deletion, so the machine stayed on every other device (this
    /// device's store refused the older copy). The test above passed only because its service had
    /// no setup.
    @Test func aSetUpMachineDeletedHereStaysDeletedAndTheDeletionIsSent() async throws {
        let (model, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let endpoint = try await model.adoptService(kind: .ssh, hostName: "retired",
                                                    address: "retired.example", serviceName: "Terminal")
        let retired = try #require(model.catalogHosts.first { $0.displayName == "retired" })
        var accountCopy = try #require(model.records.first { $0.id == retired.id })
        let index = try #require(accountCopy.services.firstIndex { $0.endpointID == endpoint })
        accountCopy.services[index].configuration = Data(#"{"port":22}"#.utf8)
        // The account holds the machine, set up, when it is deleted here; deleting syncs.
        backend.remote = [accountCopy]
        backend.saved.removeAll()
        try await model.deleteHost(retired.id)
        await model.synchronizeCatalog()

        #expect(!model.hosts.contains { $0.displayName == "retired" }, "a set-up machine deleted here came back")
        #expect(backend.saved.contains { $0.id == retired.id && $0.deletedAt != nil }, "the deletion was never sent")
    }

    /// Remove Service, the same way: the account's older copy still holds the service.
    @Test func aServiceRemovedHereStaysRemoved() async throws {
        let (model, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let terminal = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                    address: "192.0.2.10", serviceName: "Terminal")
        let database = try await model.adoptService(kind: .database, hostName: "alpha",
                                                    address: "192.0.2.10", serviceName: "MySQL on alpha")
        let alpha = try #require(model.catalogHosts.first { $0.displayName == "alpha" })
        var accountCopy = try #require(model.records.first { record in
            record.services.contains { $0.endpointID == database }
        })
        for index in accountCopy.services.indices {
            accountCopy.services[index].configuration = Data(#"{"port":3306}"#.utf8)
        }
        backend.remote = [accountCopy]
        backend.saved.removeAll()
        try await model.removeService(database, from: alpha.id)
        await model.synchronizeCatalog()

        let services = model.records.flatMap(\.services).map(\.endpointID)
        #expect(services.contains(terminal))
        #expect(!services.contains(database), "a service removed here came back")
        let sent = backend.saved.filter { $0.id == accountCopy.id }
        #expect(!sent.isEmpty && sent.allSatisfy { !$0.services.contains { $0.endpointID == database } },
                "the removal was never sent: \(sent.map { $0.services.map(\.displayName) })")
    }
}
