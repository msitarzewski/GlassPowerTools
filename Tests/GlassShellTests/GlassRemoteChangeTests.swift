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
    /// Asked to subscribe, whether or not it could.
    var subscribeAttempts = 0

    func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?) {
        fetchCount += 1
        return ([], token)
    }
    func save(_ profiles: [HostProfile]) async throws { saved.append(contentsOf: profiles) }
    func subscribeToChanges() async throws {
        subscribeAttempts += 1
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
                                    layers: GlassLayerStore.forTest())
        return (model, root)
    }

    /// Until `condition` holds, for up to 30 s. These waited a fixed 150 ms, and a run whose other
    /// tests held the main actor longer than that failed them (2026-10-24).
    private func until(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return condition()
    }

    /// The defect this pins: a subscription can be registered and nothing listen for it, which is
    /// indistinguishable from working until two real devices are in front of you.
    @Test("Enabling sync registers for change notifications")
    func enablingSyncSubscribes() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = RecordingBackend()
        model.enableCatalogSync(backend)
        #expect(await until { backend.subscribed }, "a backend that is never asked to subscribe will never push")
    }

    @Test("A remote change notification reconciles the library")
    func remoteChangeTriggersASync() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = RecordingBackend()
        model.enableCatalogSync(backend)
        #expect(await until { backend.subscribed })
        let before = backend.fetchCount

        // Posted until a sync follows: the model starts listening a moment after it subscribes, and
        // a notification before that is not heard — as a push at launch isn't, before the library
        // reconciles on coming to the front.
        // Addressed to this model: the tests run side by side, and other tests' models listen too.
        #expect(await until {
            NotificationCenter.default.post(name: GlassShellModel.remoteChangeNotification, object: model)
            return backend.fetchCount > before
        }, "the push is only useful if something syncs on it")
    }

    @Test("A change notice addressed to another library doesn't sync this one; one for every library does")
    func remoteChangeForAnotherModel() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let (other, otherRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let backend = RecordingBackend()
        model.enableCatalogSync(backend)
        #expect(await until { backend.subscribed })
        // Heard at all: the listener starts a moment after it subscribes.
        #expect(await until {
            NotificationCenter.default.post(name: GlassShellModel.remoteChangeNotification, object: nil)
            return backend.fetchCount > 0
        })
        // Taken in order, each of this library's notices syncs it and each of another's is passed over. The
        // waits above can leave notices of their own queued, which sync after: one did after a bare 100 ms
        // under load (2026-11-02) and read as another library's notice syncing. So nothing here counts on
        // time: once the five are taken, the notices taken outnumber the syncs by them (and by any other
        // test's notice for its own library, taken here too). Each synced, they never would.
        for _ in 0..<5 {
            NotificationCenter.default.post(name: GlassShellModel.remoteChangeNotification, object: other)
        }
        #expect(await until { model.remoteChangesTaken - backend.fetchCount >= 5 },
                "another library's notice synced this one: \(model.remoteChangesTaken) taken, \(backend.fetchCount) syncs")
        withExtendedLifetime(other) {}
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
        #expect(await until { backend.subscribeAttempts > 0 }, "asked, and refused")
        #expect(!backend.subscribed)

        await model.synchronizeCatalog()
        #expect(backend.fetchCount >= 1, "sync is independent of whether push was available")
        #expect(model.catalogSyncStatusDescription.isEmpty == false)
    }
}
