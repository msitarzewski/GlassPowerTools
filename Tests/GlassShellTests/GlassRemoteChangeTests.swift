import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// A backend that records what it was asked to do. The real one needs CloudKit, an account and a
/// network; none of that is available to a unit test, which is why the backend is a protocol.
private final class RecordingBackend: GlassCatalogSyncBackend, @unchecked Sendable {
    var fetchCount = 0
    var subscribed = false
    var saved: [HostProfile] = []
    var subscribeError: (any Error)?

    func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?) {
        fetchCount += 1
        return ([], token)
    }
    func save(_ profiles: [HostProfile]) async throws { saved.append(contentsOf: profiles) }
    func subscribeToChanges() async throws {
        if let subscribeError { throw subscribeError }
        subscribed = true
    }
}

private struct Boom: Error {}

@Suite("Live catalog updates", .serialized)
@MainActor
struct GlassRemoteChangeTests {
    private func makeModel() throws -> (GlassShellModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassRemoteChangeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                    layers: GlassLayerStore())
        return (model, root)
    }

    /// The defect this pins: a subscription can be registered and nothing listen for it, which is
    /// indistinguishable from working until two real devices are in front of you.
    @Test("Enabling sync registers for change notifications")
    func enablingSyncSubscribes() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = RecordingBackend()
        model.enableCatalogSync(backend)
        try await Task.sleep(for: .milliseconds(150))
        #expect(backend.subscribed, "a backend that is never asked to subscribe will never push")
    }

    @Test("A remote change notification reconciles the library")
    func remoteChangeTriggersASync() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = RecordingBackend()
        model.enableCatalogSync(backend)
        try await Task.sleep(for: .milliseconds(150))
        let before = backend.fetchCount

        NotificationCenter.default.post(name: GlassShellModel.remoteChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(300))

        #expect(backend.fetchCount > before, "the push is only useful if something syncs on it")
    }

    /// Push is best-effort on every Apple platform. A device that cannot register must still be a
    /// working device — it simply reconciles at foreground instead.
    @Test("Failing to subscribe does not stop the library from syncing")
    func subscriptionFailureIsNotFatal() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = RecordingBackend()
        backend.subscribeError = Boom()
        model.enableCatalogSync(backend)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!backend.subscribed)

        await model.synchronizeCatalog()
        #expect(backend.fetchCount >= 1, "sync is independent of whether push was available")
        #expect(model.catalogSyncStatusDescription.isEmpty == false)
    }
}
