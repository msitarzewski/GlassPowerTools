//
//  GlassSyncRereadTests.swift
//  Glass Power Tools — GlassShellTests
//
//  What sync brings in reaches the capabilities' own lists (2026-10-22). The terminal, the
//  database and the desktop each keep a list of what they read when the library loaded; a sync
//  while the app stayed open rebuilt the library and left those lists as they were, so Settings
//  and edit sheets showed — and saved from — copies older than the ones just received.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

private final class ScriptedBackend: GlassCatalogSyncBackend, @unchecked Sendable {
    var remote: [HostProfile] = []
    func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?) { (remote, nil) }
    func save(_ profiles: [HostProfile]) async throws {}
}

private final class CountingCapability: GlassCapability {
    let kind: HostServiceKind = .database
    let displayName = "Database"
    let symbolName = "circle"
    private(set) var reads = 0
    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.dismissed) }
    func catalogDidLoad() { reads += 1 }
}

@MainActor
@Suite("A sync that brings changes has the capabilities read again")
struct GlassSyncRereadTests {

    @Test func incomingChangesAreReadAgain() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncReread-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore.forTest())
        let capability = CountingCapability()
        model.registry.register(capability)
        let backend = ScriptedBackend()
        model.enableCatalogSync(backend)
        await model.load()
        _ = try await model.adoptService(kind: .database, hostName: "alpha", address: "192.0.2.10",
                                         serviceName: "MySQL on alpha")
        let afterLoad = capability.reads

        // Another device edits the machine; the account now holds the newer copy.
        var edited = try #require(model.records.first { $0.displayName == "alpha" })
        edited.displayName = "alpha, renamed elsewhere"
        edited.updatedAt = Date().addingTimeInterval(60)
        backend.remote = [edited]
        await model.synchronizeCatalog()

        #expect(model.hosts.contains { $0.displayName == "alpha, renamed elsewhere" }, "the sync applied it")
        #expect(capability.reads > afterLoad, "the capabilities were not told to read what arrived")

        // Nothing new: no reason to read again.
        let afterSync = capability.reads
        await model.synchronizeCatalog()
        #expect(capability.reads == afterSync)
    }
}
