import Foundation
import GlassConnectionKit

/// An app-local durable intent, staged before a saved endpoint is removed.
/// Absence alone never deletes a shared link: only an explicit pending intent
/// plus a successfully loaded local catalog permits removal. Secrets are absent.
@MainActor
public final class HostCatalogDeletionOutbox {
    private let fileURL: URL
    private struct Journal: Codable { var version = 1; var endpointIDs: [EndpointID] }

    public enum Failure: Error { case invalidJournal, journalFull }

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func applicationSupport(applicationIdentifier: String) -> HostCatalogDeletionOutbox {
        HostCatalogDeletionOutbox(fileURL: URL.applicationSupportDirectory
            .appendingPathComponent(applicationIdentifier, isDirectory: true)
            .appendingPathComponent("GlassHostCatalogPendingRemovals.json"))
    }

    public func pendingEndpointIDs() throws -> Set<EndpointID> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= 65_536 else { throw Failure.invalidJournal }
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        guard journal.version == 1, journal.endpointIDs.count <= 1_024,
              Set(journal.endpointIDs).count == journal.endpointIDs.count else { throw Failure.invalidJournal }
        return Set(journal.endpointIDs)
    }

    /// Must succeed before the app starts its existing local deletion transaction.
    public func stage(endpointID: EndpointID) throws {
        var pending = try pendingEndpointIDs()
        guard pending.insert(endpointID).inserted else { return }
        guard pending.count <= 1_024 else { throw Failure.journalFull }
        try persist(pending)
    }

    public func cancel(endpointID: EndpointID) throws {
        var pending = try pendingEndpointIDs()
        guard pending.remove(endpointID) != nil else { return }
        try persist(pending)
    }

    /// Call only after decoding the app's saved catalog successfully. Pending
    /// intents whose records still exist were aborted or rolled back. Failed
    /// shared writes remain on disk and can be retried on foreground activation.
    public func flush(to catalog: HostCatalogStore, activeEndpointIDs: Set<EndpointID>) async throws {
        for endpointID in try pendingEndpointIDs().sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            if !activeEndpointIDs.contains(endpointID) {
                try await catalog.remove(endpointID: endpointID)
            }
            try cancel(endpointID: endpointID)
        }
    }

    private func persist(_ pending: Set<EndpointID>) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journal = Journal(endpointIDs: pending.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString })
        let data = try JSONEncoder().encode(journal)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        guard try pendingEndpointIDs() == pending else { throw Failure.invalidJournal }
    }
}
