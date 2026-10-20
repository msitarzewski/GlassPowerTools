import CloudKit
import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// A sync that fails says why in words a person can act on (2026-10-20): the first release, run on
/// a Mac with no Apple Account, said "iCloud sync failed" and CloudKit's "This request requires an
/// authenticated account".
@Suite("The library's sync, said plainly")
@MainActor
struct GlassCatalogSyncWordingTests {
    private final class Refusing: GlassCatalogSyncBackend, @unchecked Sendable {
        let error: any Error
        init(_ error: any Error) { self.error = error }
        func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?) { throw error }
        func save(_ profiles: [HostProfile]) async throws {}
    }

    private struct Elsewhere: LocalizedError { var errorDescription: String? { "The disk is full" } }

    private func status(after error: any Error) async throws -> (GlassCatalogSyncStatus, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyncWording-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        await model.load()
        model.enableCatalogSync(Refusing(error))
        await model.synchronizeCatalog()
        return (model.catalogSyncStatus, model.catalogSyncStatusDescription)
    }

    @Test("signed out of iCloud is iCloud unavailable, with what to do, not CloudKit's words")
    func signedOut() async throws {
        let (status, words) = try await status(after: CKError(.notAuthenticated))
        guard case .unavailable = status else { Issue.record("\(status)"); return }
        #expect(words.hasPrefix("Not signed in to iCloud. Sign in with your Apple Account in System Settings"))
        #expect(!words.contains("authenticated account"))
    }

    @Test("a restricted account is unavailable too")
    func restricted() async throws {
        let (status, _) = try await status(after: CKError(.managedAccountRestricted))
        guard case .unavailable = status else { Issue.record("\(status)"); return }
    }

    @Test("anything else is still a failure, in the error's own words")
    func otherFailures() async throws {
        let (status, words) = try await status(after: Elsewhere())
        #expect(status == .failed("The disk is full"))
        #expect(words == "Not synced — The disk is full")
    }
}
