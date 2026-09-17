//
//  GlassLocalHostProjectionTests.swift
//  Glass Power Tools — GlassShellTests
//
//  "This Mac" must survive a sync.
//
//  The device's own host lives in its own store (D8) and is **inserted** into the library's
//  projection — it is not in the catalog, so `GlassShellHostGrouping.group(records)` does not know
//  about it. Any code that rebuilds `hosts` from the group alone drops it silently.
//
//  That is what happened on 2026-09-16. `synchronizeCatalog` rebuilds the projection after applying
//  incoming records, and that line had been unreachable for as long as a tombstone was throwing
//  above it. The moment the sync was fixed and started applying records again, the local host
//  disappeared from the library — a defect *created* by fixing a different one, and visible only by
//  looking at the window.
//
//  So the sync path gets its own test rather than the load path's, because the load path was never
//  broken.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

private final class ScriptedBackend: GlassCatalogSyncBackend, @unchecked Sendable {
    var remote: [HostProfile] = []
    var saved: [HostProfile] = []
    func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?) {
        (remote, Data("token".utf8))
    }
    func save(_ profiles: [HostProfile]) async throws { saved.append(contentsOf: profiles) }
}

@MainActor
@Suite("This Mac stays in the library")
struct GlassLocalHostProjectionTests {

    private func makeShell() throws -> (GlassShellModel, ScriptedBackend, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalHost-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        let backend = ScriptedBackend()
        model.enableCatalogSync(backend)
        return (model, backend, root)
    }

    @Test func theLocalHostIsInTheLibraryAfterLoading() async throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        #expect(model.hosts.contains { $0.isLocal }, "This Mac is missing after load")
        #expect(model.hosts.first?.isLocal == true, "This Mac is not at the head of the library")
    }

    /// The reported failure: a sync that actually applies something must not take the local host
    /// with it.
    @Test func theLocalHostSurvivesASyncThatAppliesIncomingRecords() async throws {
        let (model, backend, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        #expect(model.hosts.contains { $0.isLocal })

        // A machine arriving from the account — enough to make `toApplyLocally` non-empty, which is
        // the branch that rebuilds the projection.
        let incoming = try HostProfile(id: HostID(), displayName: "juliet",
                                       lastWriterID: WriterID())
        backend.remote = [incoming]
        await model.synchronizeCatalog()

        #expect(model.hosts.contains { $0.displayName == "juliet" }, "the incoming machine was not applied")
        #expect(model.hosts.contains { $0.isLocal }, "This Mac disappeared when the sync applied a record")
        #expect(model.hosts.first?.isLocal == true, "This Mac is no longer at the head")
    }

    /// And it is still there after the library reloads on activation, which is what `load()` is.
    @Test func theLocalHostSurvivesRepeatedLoads() async throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        await model.load()
        await model.load()
        #expect(model.hosts.filter { $0.isLocal }.count == 1,
                "This Mac is missing or duplicated after repeated loads")
    }
}
