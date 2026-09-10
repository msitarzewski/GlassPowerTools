//
//  ConnectionLibrary.swift
//  glas.sh
//
//  Transient projections over the existing connection and workgroup stores.
//

import Foundation
import GlassConnectionKit

enum ConnectionLibraryMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case library
    case favorites
    case recent
    case collections
    case workgroups
    case network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .collections: return "Collections"
        case .workgroups: return "Workgroups"
        case .network: return "Network"
        }
    }
}

enum ConnectionLibraryScope: Hashable, Identifiable, Sendable {
    case allConnections
    case favorites
    case recent
    case collection(String)
    case workgroups
    case network

    var id: String {
        switch self {
        case .allConnections: return "all-connections"
        case .favorites: return "favorites"
        case .recent: return "recent"
        case .collection(let id): return "collection-\(id)"
        case .workgroups: return "workgroups"
        case .network: return "network"
        }
    }
}

struct ConnectionLibraryCollection: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let serverIDs: [UUID]

    var count: Int { serverIDs.count }
}

struct ConnectionLibraryProjection {
    let servers: [ServerConfiguration]
    let favoriteServerIDs: [UUID]
    let recentServerIDs: [UUID]
    let collections: [ConnectionLibraryCollection]
    let workgroups: [LayoutPreset]
    let networkIsConfigured: Bool
    var sharedProjection: GlassLibraryProjection<UUID> { shared }
    private let shared: GlassLibraryProjection<UUID>
    private let records: [UUID: ServerConfiguration]

    init(servers: [ServerConfiguration], workgroups: [LayoutPreset], networkIsConfigured: Bool, recentLimit: Int = 10) {
        let shared = GlassLibraryProjection(items: servers.map(Self.item), order: .source, recentLimit: recentLimit)
        var records: [UUID: ServerConfiguration] = [:]
        for server in servers where records[server.id] == nil { records[server.id] = server }
        self.shared = shared
        self.records = records
        self.servers = shared.items.compactMap { records[$0.id] }
        favoriteServerIDs = shared.favoriteIDs
        recentServerIDs = shared.recentIDs
        collections = shared.collections.map { ConnectionLibraryCollection(id: $0.id, name: $0.name, serverIDs: $0.itemIDs) }
        self.workgroups = workgroups
        self.networkIsConfigured = networkIsConfigured
    }
    var availableModes: [ConnectionLibraryMode] {
        ConnectionLibraryMode.allCases.filter { $0 != .network || networkIsConfigured }
    }
    func scopes(for mode: ConnectionLibraryMode) -> [ConnectionLibraryScope] {
        switch mode {
        case .library: [.allConnections]
        case .favorites: [.favorites]
        case .recent: [.recent]
        case .collections: collections.map { .collection($0.id) }
        case .workgroups: [.workgroups]
        case .network: networkIsConfigured ? [.network] : []
        }
    }
    func collection(named name: String) -> ConnectionLibraryCollection? {
        guard let id = Self.collectionID(for: name) else { return nil }
        return collections.first { $0.id == id }
    }
    func servers(in scope: ConnectionLibraryScope, searchQuery: String = "") -> [ServerConfiguration] {
        guard let scope = Self.sharedScope(scope) else { return [] }
        return shared.items(in: scope, searchQuery: searchQuery).compactMap { records[$0.id] }
    }
    func matchingServers(from candidates: [ServerConfiguration], searchQuery: String = "") -> [ServerConfiguration] {
        let filtered = GlassLibraryProjection(items: candidates.map(Self.item)).items(in: .allConnections, searchQuery: searchQuery)
        var byID: [UUID: ServerConfiguration] = [:]
        for server in candidates where byID[server.id] == nil { byID[server.id] = server }
        return filtered.compactMap { byID[$0.id] }
    }
    func workgroups(matching searchQuery: String = "") -> [LayoutPreset] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return workgroups }
        return workgroups.filter { preset in
            preset.name.localizedCaseInsensitiveContains(query) || preset.sessionIntents.contains {
                $0.label?.localizedCaseInsensitiveContains(query) == true
            }
        }
    }
    func resolvedSelection(preferredServerID: UUID?, in scope: ConnectionLibraryScope, searchQuery: String = "") -> UUID? {
        guard let scope = Self.sharedScope(scope) else { return nil }
        return shared.resolvedSelection(preferredServerID, in: scope, searchQuery: searchQuery)
    }
    func itemCount(in scope: ConnectionLibraryScope) -> Int {
        switch scope {
        case .workgroups: workgroups.count
        case .network: networkIsConfigured ? 1 : 0
        default: servers(in: scope).count
        }
    }
    static func collectionID(for name: String) -> String? { GlassLibraryProjection<UUID>.collectionID(for: name) }
    private static func item(_ server: ServerConfiguration) -> GlassLibraryItem<UUID> {
        .init(id: server.id, name: server.name, searchTerms: [server.host, server.username], tags: server.tags,
              isFavorite: server.isFavorite, lastConnected: server.lastConnected, dateAdded: server.dateAdded,
              sortKeys: [server.host, server.username])
    }
    private static func sharedScope(_ scope: ConnectionLibraryScope) -> GlassLibraryScope? {
        switch scope {
        case .allConnections: .allConnections
        case .favorites: .favorites
        case .recent: .recent
        case .collection(let id): .collection(id)
        case .network, .workgroups: nil
        }
    }
}
