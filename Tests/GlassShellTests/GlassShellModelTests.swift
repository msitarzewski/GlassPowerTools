import GlassLayers
import Foundation
import Testing
import GlassConnectionKit
import GlassConnectionUI
import GlassHostCatalog
@testable import GlassShell

@MainActor
private func makeModel(shared: Bool = true) throws -> (GlassShellModel, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassShellTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                sharedContainerURL: shared ? root.appendingPathComponent("group") : nil,
                                resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                layers: GlassLayerStore.forTest())
    return (model, root)
}

@MainActor
private final class RecordingCapability: GlassCapability {
    let kind: HostServiceKind
    var displayName: String { "Recorder" }
    var symbolName: String { "circle" }
    var opened: [(HostServiceLink, HostProfile)] = []
    /// The shell's outcome callback for the latest `open`; tests deliver it explicitly.
    var pendingReport: ((GlassCapabilityOutcome) -> Void)?
    init(kind: HostServiceKind) { self.kind = kind }
    func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
        opened.append((service, host))
        pendingReport = report
    }
}

@Suite("GlassShellModel", .serialized)
@MainActor
struct GlassShellModelTests {
    @Test("Catalog lives at the App Group path and existing hosts appear without migration")
    func readsExistingCatalog() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        // Another app wrote the file first, as glas.sh/glassdb/glassDT do today.
        let sibling = HostCatalogStore(fileURL: root.appendingPathComponent("group/GlassHostCatalog/hosts.json"))
        let link = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "shell")
        try await sibling.upsert(try HostProfile(displayName: "Alpha", services: [link]))
        await model.load()
        #expect(model.hasSharedContainer)
        #expect(model.catalogHosts.map(\.displayName) == ["Alpha"])
        #expect(model.serviceKinds(for: model.catalogHosts[0].id) == [.ssh])
        #expect(model.catalogFileURL.path.hasSuffix("group/GlassHostCatalog/hosts.json"))
    }

    @Test("Projection is deterministic and sorted by the catalog order")
    func projectionDeterminism() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await model.addHost(displayName: "Zed", tags: ["Prod"])
        _ = try await model.addHost(displayName: "Alpha", tags: ["prod", "Lab"])
        let first = model.catalogItems, second = model.catalogItems
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.sortKeys) == second.map(\.sortKeys))
        #expect(first.map(\.name) == ["Alpha", "Zed"])
        #expect(first[0].subtitle == "No services yet")
        let projection = GlassLibraryProjection(items: first)
        #expect(projection.collections.map(\.name) == ["Lab", "Prod"])
        #expect(projection.collections.first { $0.name == "Prod" }?.count == 2)
    }

    @Test("Add a service creates the link in hosts.json and it survives reload")
    func addServicePersists() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Box")
        let link = try await model.addService(kind: .database, displayName: "Postgres", to: host.id)
        #expect(model.services(for: host.id) == [link])
        let (reloaded, _) = try (GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                                 sharedContainerURL: root.appendingPathComponent("group"),
                                                 resolveSharedContainer: false, layers: GlassLayerStore.forTest()), root)
        await reloaded.load()
        #expect(reloaded.services(for: host.id).map(\.displayName) == ["Postgres"])
        #expect(reloaded.catalogItems.first?.subtitle == "Database")
        try await reloaded.removeService(link.endpointID, from: host.id)
        #expect(reloaded.services(for: host.id).isEmpty)
    }

    @Test("Connect picks the sole service, then last-used, then first")
    func connectSelection() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Multi")
        #expect(model.connect(hostID: host.id) == nil)
        let ssh = try await model.addService(kind: .ssh, displayName: "ssh", to: host.id)
        #expect(model.connect(hostID: host.id)?.endpointID == ssh.endpointID)
        #expect(model.errorMessage == GlassShellModel.unavailableMessage(for: .ssh), "no capability → says so, connects nothing")
        let db = try await model.addService(kind: .database, displayName: "db", to: host.id)
        #expect(model.connect(hostID: host.id)?.endpointID == ssh.endpointID, "last-used wins over first")
        model.connect(hostID: host.id, endpointID: db.endpointID)
        #expect(model.lastUsedService(for: host.id)?.endpointID == db.endpointID)
        #expect(model.connect(hostID: host.id)?.endpointID == db.endpointID)
        try await model.removeService(db.endpointID, from: host.id)
        #expect(model.lastUsedService(for: host.id) == nil)
        #expect(model.connect(hostID: host.id)?.endpointID == ssh.endpointID, "falls back to first")
        #expect(model.lastConnected(host.id) == nil, "F3: an unavailable kind connects nothing, so no connection time")
    }

    @Test("A registered capability receives the open call")
    func capabilityRouting() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = RecordingCapability(kind: .rdp)
        model.registry.register(recorder)
        let host = try await model.addHost(displayName: "Win")
        let rdp = try await model.addService(kind: .rdp, displayName: "desktop", to: host.id)
        model.errorMessage = nil
        model.connect(hostID: host.id)
        #expect(recorder.opened.count == 1)
        #expect(recorder.opened.first?.0.endpointID == rdp.endpointID)
        #expect(model.errorMessage == nil)
        #expect(model.registry.registeredKinds == [.rdp])
    }

    @Test("Preferences round-trip: favorites, last-used and writer identity survive relaunch")
    func preferencesRoundTrip() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Fav")
        _ = try await model.addService(kind: .ssh, displayName: "s", to: host.id)
        model.toggleFavorite(host.id)
        model.connect(hostID: host.id)
        let writer = model.writerID
        let again = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false, layers: GlassLayerStore.forTest())
        await again.load()
        #expect(again.isFavorite(host.id))
        #expect(again.catalogItems.first?.isFavorite == true)
        #expect(again.lastUsedService(for: host.id) != nil)
        #expect(again.writerID == writer)
        #expect(again.preferencesProblem == nil)
        again.toggleFavorite(host.id)
        #expect(!again.isFavorite(host.id))
    }

    @Test("Corrupt preferences are reported, not swallowed")
    func corruptPreferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: app.appendingPathComponent("shell-preferences.json"))
        defer { try? FileManager.default.removeItem(at: root) }
        let model = GlassShellModel(storageDirectory: app, sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false, layers: GlassLayerStore.forTest())
        #expect(model.preferencesProblem?.contains("could not be read") == true)
    }

    @Test("Unavailable shared container gives an honest status and a local catalog")
    func unavailableContainer() async throws {
        let (model, root) = try makeModel(shared: false)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!model.hasSharedContainer)
        #expect(model.hostLibraryStatus.contains("group.sh.glas.shared"))
        #expect(model.catalogFileURL.path.hasPrefix(root.appendingPathComponent("app").path))
        _ = try await model.addHost(displayName: "Local")
        #expect(model.catalogHosts.count == 1)
    }

    @Test("Deleting a host tombstones it and clears its preferences")
    func deleteHost() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Gone")
        model.toggleFavorite(host.id)
        try await model.deleteHost(host.id)
        #expect(model.catalogHosts.isEmpty)
        #expect(!model.isFavorite(host.id))
        let all = try await model.catalog.snapshot(includeDeleted: true)
        #expect(all.first?.deletedAt != nil)
    }

    @Test("Names are validated")
    func nameValidation() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: GlassShellError.invalidName) { _ = try await model.addHost(displayName: "   ") }
        let host = try await model.addHost(displayName: "Ok")
        await #expect(throws: GlassShellError.invalidName) { _ = try await model.addService(kind: .ssh, displayName: " ", to: host.id) }
    }
}
