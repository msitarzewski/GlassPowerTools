//
//  ConnectionManager.swift
//  glassdb
//
//  CRUD for saved database connections with persistence
//  Pattern adapted from glas.sh ServerManager
//

import SwiftUI
import Foundation
import GlassConnectionKit
import Observation
import os

enum ConnectionPersistenceError: LocalizedError {
    case readbackMismatch
    case rollbackFailed
    case credentialRollbackFailed

    var errorDescription: String? {
        switch self {
        case .readbackMismatch:
            return "The saved connection list could not be verified. No connection or managed database changes were committed."
        case .rollbackFailed:
            return "The connection list could not be saved and its previous persisted state could not be restored. Reopen the app and verify the saved connections before continuing."
        case .credentialRollbackFailed:
            return "The connection list could not be saved and its credentials could not be fully restored. Re-enter the credentials before connecting again."
        }
    }
}

struct ConnectionPersistenceStore: @unchecked Sendable {
    let load: () -> Data?
    let save: (Data) throws -> Void
    let restore: (Data?) throws -> Void

    static let live = ConnectionPersistenceStore(
        load: { UserDefaults.standard.data(forKey: UserDefaultsKeys.connections) },
        save: { data in
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.connections)
            guard UserDefaults.standard.data(forKey: UserDefaultsKeys.connections) == data else {
                throw ConnectionPersistenceError.readbackMismatch
            }
        },
        restore: { data in
            if let data {
                UserDefaults.standard.set(data, forKey: UserDefaultsKeys.connections)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.connections)
            }
            guard UserDefaults.standard.data(forKey: UserDefaultsKeys.connections) == data else {
                throw ConnectionPersistenceError.rollbackFailed
            }
        }
    )
}

enum DatabaseConnectionLibraryMode: String, CaseIterable, Identifiable, Hashable {
    case all
    case favorites
    case recent
    case collections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .collections: return "Collections"
        }
    }
}

enum DatabaseConnectionLibraryScope: Hashable, Identifiable {
    case allConnections
    case favorites
    case recent
    case collection(String)

    var id: String {
        switch self {
        case .allConnections: return "all-connections"
        case .favorites: return "favorites"
        case .recent: return "recent"
        case .collection(let id): return "collection-\(id)"
        }
    }
}

struct DatabaseConnectionLibraryCollection: Identifiable, Hashable {
    let id: String
    let name: String
    let connectionIDs: [UUID]

    var count: Int { connectionIDs.count }
}

/// A transient, read-only library view over ConnectionManager's persisted
/// records. Scopes never become a second connection catalog.
struct DatabaseConnectionLibraryProjection {
    let connections: [DatabaseConnectionConfig]
    let favoriteConnectionIDs: [UUID]
    let recentConnectionIDs: [UUID]
    let collections: [DatabaseConnectionLibraryCollection]
    var sharedProjection: GlassLibraryProjection<UUID> { shared }
    private let shared: GlassLibraryProjection<UUID>
    private let records: [UUID: DatabaseConnectionConfig]

    init(connections: [DatabaseConnectionConfig], recentLimit: Int = 10) {
        let shared = GlassLibraryProjection(items: connections.map(Self.item), order: .alphabetical, recentLimit: recentLimit)
        var records: [UUID: DatabaseConnectionConfig] = [:]
        for connection in connections where records[connection.id] == nil { records[connection.id] = connection }
        self.shared = shared
        self.records = records
        self.connections = shared.items.compactMap { records[$0.id] }
        favoriteConnectionIDs = shared.favoriteIDs
        recentConnectionIDs = shared.recentIDs
        collections = shared.collections.map { DatabaseConnectionLibraryCollection(id: $0.id, name: $0.name, connectionIDs: $0.itemIDs) }
    }
    func connections(in scope: DatabaseConnectionLibraryScope, searchQuery: String = "") -> [DatabaseConnectionConfig] {
        shared.items(in: Self.sharedScope(scope), searchQuery: searchQuery).compactMap { records[$0.id] }
    }
    func resolvedSelection(preferredConnectionID: UUID?, in scope: DatabaseConnectionLibraryScope, searchQuery: String = "") -> UUID? {
        shared.resolvedSelection(preferredConnectionID, in: Self.sharedScope(scope), searchQuery: searchQuery)
    }
    func itemCount(in scope: DatabaseConnectionLibraryScope) -> Int { shared.itemCount(in: Self.sharedScope(scope)) }
    func collection(named name: String) -> DatabaseConnectionLibraryCollection? {
        guard let id = Self.collectionID(for: name) else { return nil }
        return collections.first { $0.id == id }
    }
    static func normalizedTags(_ rawTags: [String]) -> [String] {
        // Each input is a distinct source record so all spelling variants take
        // part in the existing deterministic representative-name selection.
        GlassLibraryProjection(items: rawTags.enumerated().map {
            GlassLibraryItem(id: $0.offset, name: "", tags: [$0.element])
        }).collections.map(\.name)
    }
    static func collectionID(for name: String) -> String? { GlassLibraryProjection<UUID>.collectionID(for: name) }
    private static func item(_ connection: DatabaseConnectionConfig) -> GlassLibraryItem<UUID> {
        .init(id: connection.id, name: connection.name,
              searchTerms: [connection.engine.displayName, connection.host, connection.username, connection.defaultDatabase ?? ""],
              tags: connection.tags, isFavorite: connection.isFavorite, lastConnected: connection.lastConnected,
              dateAdded: connection.dateAdded, sortKeys: [connection.host, connection.username])
    }
    private static func sharedScope(_ scope: DatabaseConnectionLibraryScope) -> GlassLibraryScope {
        switch scope {
        case .allConnections: .allConnections
        case .favorites: .favorites
        case .recent: .recent
        case .collection(let id): .collection(id)
        }
    }
}

@MainActor
@Observable
class ConnectionManager {
    var externalConnectionRequest: UUID?
    var connections: [DatabaseConnectionConfig] = []
    var credentialError: String?

    private(set) var familyCatalogLoaded = false
    private var hasLoaded = false
    private let persistenceStore: ConnectionPersistenceStore

    init(
        loadImmediately: Bool = true,
        persistenceStore: ConnectionPersistenceStore = .live
    ) {
        self.persistenceStore = persistenceStore
        if loadImmediately {
            loadIfNeeded()
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        load()
        do {
            _ = try KeychainManager.runMigrationsIfNeeded(connections: connections)
        } catch {
            credentialError = error.localizedDescription
            Logger.keychain.error("Credential migration failed without exposing credential material: \(error.localizedDescription)")
        }
    }

    func load() {
        familyCatalogLoaded = false
        guard let data = persistenceStore.load() else {
            connections = []
            familyCatalogLoaded = true
            return
        }

        do {
            connections = try JSONDecoder().decode([DatabaseConnectionConfig].self, from: data)
            familyCatalogLoaded = true
        } catch {
            Logger.connections.error("Failed to load connections: \(error)")
            connections = []
        }
    }

    func save() throws {
        try persist(connections)
    }

    func add(_ connection: DatabaseConnectionConfig) throws {
        var candidate = connections
        candidate.append(connection)
        try persist(candidate)
        connections = candidate
    }

    func update(_ connection: DatabaseConnectionConfig) throws {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            let previous = connections[index]
            var candidate = connections
            candidate[index] = connection
            try persist(candidate)
            connections = candidate
            removeUnreferencedSQLiteFile(from: previous, replacingWith: connection)
        }
    }

    func connection(for id: UUID) -> DatabaseConnectionConfig? {
        connections.first { $0.id == id }
    }

    /// Removes the record, its credentials and any managed SQLite working copy.
    ///
    /// glassdb staged a `HostCatalogDeletionOutbox` intent here first
    /// (`../glassdb/glassdb/ConnectionManager.swift:237-241`), because it published its own
    /// connections into the shared catalog and had to record a removal that survived a crash.
    /// **That is gone, and not merely as redundant.** The outbox was namespaced
    /// `app.glassdb`, and this app is not sandboxed on macOS, so keeping it would have written
    /// into `~/Library/Application Support/app.glassdb/` — the still-shipping glassdb's own
    /// directory, which has to keep working until parity. The shell owns catalog deletion now.
    func delete(_ connection: DatabaseConnectionConfig) throws {
        let credentialReceipt = try KeychainManager.deleteCredentials(for: connection)
        let candidate = connections.filter { $0.id != connection.id }
        do {
            try persist(candidate)
        } catch {
            do {
                try KeychainManager.restoreCredentials(credentialReceipt)
            } catch {
                throw ConnectionPersistenceError.credentialRollbackFailed
            }
            throw error
        }
        connections = candidate
        removeUnreferencedSQLiteFile(from: connection, replacingWith: nil)
        // Unsaved SQL written against this connection goes with it, rather than ageing out of the
        // draft store over ninety days. Drafts are the user's own text and can hold anything the
        // schema does; deleting the connection is the clearest statement that they are finished
        // with it. Placed here rather than in the capability because every deletion path — the
        // shell's `removeService` included — converges on this method.
        SQLDraftStore.shared.removeAll(connectionID: connection.id)
    }

    private func removeUnreferencedSQLiteFile(
        from previous: DatabaseConnectionConfig,
        replacingWith replacement: DatabaseConnectionConfig?
    ) {
        guard previous.engine == .sqlite,
              replacement?.engine != .sqlite || replacement?.host != previous.host,
              !connections.contains(where: { $0.engine == .sqlite && $0.host == previous.host }) else {
            return
        }
        do {
            let managedURL = try SQLiteFileImporter.validatedURL(forPath: previous.host)
            try FileManager.default.removeItem(at: managedURL)
        } catch SQLiteFileImporter.ImportError.managedCopyMissing {
            return
        } catch {
            Logger.connections.error(
                "Failed to remove unreferenced SQLite database: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func updateLastConnected(_ connectionID: UUID) {
        if let index = connections.firstIndex(where: { $0.id == connectionID }) {
            var candidate = connections
            candidate[index].lastConnected = Date()
            do {
                try persist(candidate)
                connections = candidate
            } catch {
                credentialError = "The connection succeeded, but its recent-connection timestamp could not be saved. \(error.localizedDescription)"
            }
        }
    }

    func toggleFavorite(_ connection: DatabaseConnectionConfig) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            var candidate = connections
            candidate[index].isFavorite.toggle()
            do {
                try persist(candidate)
                connections = candidate
            } catch {
                credentialError = "The favorite change could not be saved, so it was not applied. \(error.localizedDescription)"
            }
        }
    }

    private func persist(_ candidate: [DatabaseConnectionConfig]) throws {
        let data = try JSONEncoder().encode(candidate)
        let previousData = persistenceStore.load()
        do {
            try persistenceStore.save(data)
        } catch {
            do {
                try persistenceStore.restore(previousData)
                guard persistenceStore.load() == previousData else {
                    throw ConnectionPersistenceError.rollbackFailed
                }
            } catch {
                throw ConnectionPersistenceError.rollbackFailed
            }
            throw error
        }
    }

    var favoriteConnections: [DatabaseConnectionConfig] {
        connections.filter { $0.isFavorite }
            .sorted { ($0.lastConnected ?? $0.dateAdded) > ($1.lastConnected ?? $1.dateAdded) }
    }

    var recentConnections: [DatabaseConnectionConfig] {
        connections
            .filter { $0.lastConnected != nil }
            .sorted { $0.lastConnected! > $1.lastConnected! }
            .prefix(10)
            .map { $0 }
    }

    var allTags: [String] {
        Array(Set(connections.flatMap { $0.tags })).sorted()
    }
}
