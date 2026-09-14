import Foundation

/// Non-secret presentation values, adapted from an app's authoritative records.
/// A projection never persists records or becomes a second connection catalog.
public struct GlassLibraryItem<ID: Hashable & Sendable>: Identifiable, Sendable {
    public let id: ID
    public var name: String
    public var subtitle: String
    public var searchTerms: [String]
    public var tags: [String]
    public var isFavorite: Bool
    public var lastConnected: Date?
    public var dateAdded: Date
    /// Domain-specific tie breakers, for example host and username.
    public var sortKeys: [String]

    public init(id: ID, name: String, subtitle: String = "", searchTerms: [String] = [],
                tags: [String] = [], isFavorite: Bool = false, lastConnected: Date? = nil,
                dateAdded: Date = .distantPast, sortKeys: [String] = []) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.searchTerms = searchTerms
        self.tags = tags
        self.isFavorite = isFavorite
        self.lastConnected = lastConnected
        self.dateAdded = dateAdded
        self.sortKeys = sortKeys
    }
}

public enum GlassLibraryScope: Hashable, Sendable, Identifiable {
    case allConnections
    case favorites
    case recent
    case collection(String)

    public var id: String {
        switch self {
        case .allConnections: "all-connections"
        case .favorites: "favorites"
        case .recent: "recent"
        case .collection(let id): "collection-\(id)"
        }
    }
}

public enum GlassLibraryOrder: Sendable {
    /// Preserves glas.sh's existing All/collection order.
    case source
    /// Preserves glassdb's existing All/collection order.
    case alphabetical
}

public struct GlassLibraryCollection<ID: Hashable & Sendable>: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let itemIDs: [ID]
    public var count: Int { itemIDs.count }
}

/// Pure library behavior extracted from glas.sh ConnectionLibraryProjection and
/// glassdb DatabaseConnectionLibraryProjection. See EXTRACTION.md for provenance.
public struct GlassLibraryProjection<ID: Hashable & Sendable>: Sendable {
    public let items: [GlassLibraryItem<ID>]
    public let collections: [GlassLibraryCollection<ID>]
    public let favoriteIDs: [ID]
    public let recentIDs: [ID]
    private let index: [ID: GlassLibraryItem<ID>]

    public init(items: [GlassLibraryItem<ID>], order: GlassLibraryOrder = .source,
                recentLimit: Int = 10) {
        var seen = Set<ID>()
        let unique = items.filter { seen.insert($0.id).inserted }
        let ordered: [GlassLibraryItem<ID>]
        switch order {
        case .source: ordered = unique
        case .alphabetical: ordered = unique.sorted(by: Self.itemOrder)
        }
        self.items = ordered
        index = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        favoriteIDs = unique.filter(\.isFavorite).sorted {
            let lhs = $0.lastConnected ?? $0.dateAdded
            let rhs = $1.lastConnected ?? $1.dateAdded
            return lhs == rhs ? Self.itemOrder($0, $1) : lhs > rhs
        }.map(\.id)
        recentIDs = unique.filter { $0.lastConnected != nil }.sorted {
            let lhs = $0.lastConnected ?? .distantPast
            let rhs = $1.lastConnected ?? .distantPast
            return lhs == rhs ? Self.itemOrder($0, $1) : lhs > rhs
        }.prefix(max(0, recentLimit)).map(\.id)

        var names: [String: Set<String>] = [:]
        var members: [String: [ID]] = [:]
        for item in ordered {
            var seenTags = Set<String>()
            for raw in item.tags {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let id = Self.collectionID(for: name), seenTags.insert(id).inserted else { continue }
                names[id, default: []].insert(name)
                members[id, default: []].append(item.id)
            }
        }
        collections = names.map { id, variants in
            GlassLibraryCollection(id: id, name: variants.sorted(by: Self.displayOrder).first ?? id,
                                   itemIDs: members[id] ?? [])
        }.sorted { Self.displayOrder($0.name, $1.name) }
    }

    public func items(in scope: GlassLibraryScope, searchQuery: String = "") -> [GlassLibraryItem<ID>] {
        let candidates: [GlassLibraryItem<ID>]
        switch scope {
        case .allConnections: candidates = items
        case .favorites: candidates = favoriteIDs.compactMap { index[$0] }
        case .recent: candidates = recentIDs.compactMap { index[$0] }
        case .collection(let id):
            candidates = (collections.first { $0.id == id }?.itemIDs ?? []).compactMap { index[$0] }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter { item in
            ([item.name, item.subtitle] + item.searchTerms + item.tags)
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    public func itemCount(in scope: GlassLibraryScope) -> Int { items(in: scope).count }

    /// Never silently picks a different host after filtering/deletion.
    public func resolvedSelection(_ preferred: ID?, in scope: GlassLibraryScope,
                                  searchQuery: String = "") -> ID? {
        guard let preferred else { return nil }
        return items(in: scope, searchQuery: searchQuery).contains { $0.id == preferred } ? preferred : nil
    }

    public func title(for scope: GlassLibraryScope) -> String {
        switch scope {
        case .allConnections: "All Connections"
        case .favorites: "Favorites"
        case .recent: "Recent"
        case .collection(let id): collections.first { $0.id == id }?.name ?? "Collections"
        }
    }

    public static func collectionID(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let locale = Locale(identifier: "en_US_POSIX")
        return trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                               locale: locale).lowercased(with: locale)
    }

    private static func itemOrder(_ lhs: GlassLibraryItem<ID>, _ rhs: GlassLibraryItem<ID>) -> Bool {
        if displayOrder(lhs.name, rhs.name) { return true }
        if displayOrder(rhs.name, lhs.name) { return false }
        if lhs.sortKeys != rhs.sortKeys { return lhs.sortKeys.lexicographicallyPrecedes(rhs.sortKeys) }
        return String(describing: lhs.id) < String(describing: rhs.id)
    }

    private static func displayOrder(_ lhs: String, _ rhs: String) -> Bool {
        let order = lhs.localizedCaseInsensitiveCompare(rhs)
        return order == .orderedSame ? lhs < rhs : order == .orderedAscending
    }
}
