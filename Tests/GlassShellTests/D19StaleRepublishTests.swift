//
//  D19StaleRepublishTests.swift
//  Glass Power Tools — GlassShellTests
//
//  A device must never publish a copy the account did not ask for.
//
//  Reported 2026-09-27: collections made on the Mac never reached the phone, which said "Synced".
//  Every sync after a device's first asked the account only for what had changed, and the merge
//  then read "not among the changes" as "the account has never seen this" and published every
//  other record the device held — over whatever the account had, newer or not. A phone holding
//  copies from before the collections existed overwrote the Mac's on every foreground, then read
//  its own old copies back.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// An account that answers a token with only what changed after it, the way CloudKit does.
private final class DeltaBackend: GlassCatalogSyncBackend, @unchecked Sendable {
    private var stored: [HostID: (profile: HostProfile, revision: Int)] = [:]
    private var revision = 0
    var published: [HostProfile] = []

    func seed(_ profile: HostProfile) {
        revision += 1
        stored[profile.id] = (profile, revision)
    }

    func current(_ id: HostID) -> HostProfile? { stored[id]?.profile }

    func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?) {
        let after = token.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        let changed = stored.values.filter { $0.revision > after }.map(\.profile)
        return (changed, Data(String(revision).utf8))
    }

    func save(_ profiles: [HostProfile]) async throws {
        published.append(contentsOf: profiles)
        for profile in profiles { seed(profile) }
    }
}

@MainActor
@Suite("A sync publishes only what the account lacks (D19)")
struct D19StaleRepublishTests {

    private func makeShell() throws -> (GlassShellModel, DeltaBackend, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D19Stale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        let backend = DeltaBackend()
        model.enableCatalogSync(backend)
        return (model, backend, root)
    }

    /// Nothing changed anywhere between two syncs, so the second has nothing to send.
    @Test func aSecondSyncWithNoChangesPublishesNothing() async throws {
        let (model, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        _ = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                         address: "alpha.example", serviceName: "Terminal")
        await model.synchronizeCatalog()
        backend.published.removeAll()

        await model.synchronizeCatalog()

        #expect(backend.published.isEmpty)
    }

    /// The reported case: another device edits a record after this one last synced, while this one
    /// still holds the old copy. The newer copy must survive in the account and arrive here.
    @Test func aStaleCopyDoesNotOverwriteANewerOneFromAnotherDevice() async throws {
        let (model, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        _ = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                         address: "alpha.example", serviceName: "Terminal")
        await model.synchronizeCatalog()
        let host = try #require(model.catalogHosts.first { $0.displayName == "alpha" })

        // Another device adds the machine to a collection. Its write reaches the account; this
        // device has not synced since.
        var elsewhere = try #require(backend.current(host.id))
        elsewhere.tags = ["Home"]
        elsewhere.updatedAt = Date().addingTimeInterval(120)
        backend.seed(elsewhere)

        await model.synchronizeCatalog()
        await model.synchronizeCatalog()

        #expect(backend.current(host.id)?.tags == ["Home"])
        #expect(model.catalogHosts.first { $0.id == host.id }?.tags == ["Home"])
    }
}
