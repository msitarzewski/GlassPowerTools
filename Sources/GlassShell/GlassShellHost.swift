import Foundation
import GlassConnectionKit

/// One machine as the library shows it: every catalog record that describes the same host,
/// consolidated for presentation. The shared catalog was written by three separate apps, each of
/// which created its own `HostProfile` per endpoint (`HostCatalogStore.applyPublication` keys new
/// records by the endpoint's id and matches only by endpoint id), so "juliet" from glas.sh and
/// "juliet" from glassDT are two records. Until Stage 6 those apps still read the file by their
/// own ids, so the records are grouped here and never merged on disk.
public struct GlassShellHost: Identifiable, Hashable, Sendable {
    /// The canonical member's id: the oldest record, ties broken by id. Favorites, last-used and
    /// selection key on it.
    public let id: HostID
    public let displayName: String
    /// The machine's address as the library shows it: the canonical member's, else the first
    /// member that has one. Services inherit it; the host editor is where it is typed.
    public let address: String?
    /// Every distinct address across the members. More than one means the records disagree; the
    /// detail surfaces that rather than hiding it.
    public let addresses: [String]
    public let aliases: [String]
    public let tags: [String]
    /// Union of every member's services, canonical member first, deduplicated by endpoint.
    public let services: [HostServiceLink]
    public let createdAt: Date
    /// Canonical first.
    public let members: [HostProfile]

    public var canonical: HostProfile { members[0] }
    public var isConsolidated: Bool { members.count > 1 }

    public func member(owning endpointID: EndpointID) -> HostProfile? {
        members.first { $0.services.contains { $0.endpointID == endpointID } }
    }

    public func contains(_ hostID: HostID) -> Bool { members.contains { $0.id == hostID } }

    init(members: [HostProfile]) {
        precondition(!members.isEmpty)
        let ordered = members.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
        let canonical = ordered[0]
        var seen = Set<EndpointID>()
        var services: [HostServiceLink] = []
        for member in ordered {
            for link in member.services where seen.insert(link.endpointID).inserted { services.append(link) }
        }
        id = canonical.id
        displayName = canonical.displayName
        let addresses = Self.union(ordered.compactMap(\.address).map { [$0] })
        self.addresses = addresses
        address = addresses.first
        aliases = Self.union(ordered.map(\.aliases))
        tags = Self.union(ordered.map(\.tags))
        self.services = services
        createdAt = canonical.createdAt
        self.members = ordered
    }

    private static func union(_ lists: [[String]]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for value in lists.joined() where seen.insert(value.lowercased()).inserted { out.append(value) }
        return out
    }
}

/// The grouping rule. Two records are the same machine when their normalised display names are
/// equal, when they share an alias (the source apps published the address as the alias), or when
/// they carry the same address. Loopback addresses never group: many distinct local services
/// legitimately carry them.
public enum GlassShellHostGrouping {
    public static func normalizedName(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
        if value.hasSuffix(".local") { value.removeLast(".local".count) }
        return value
    }

    /// `nil` for values that must not link records: empty, or loopback.
    public static func normalizedAlias(_ alias: String) -> String? {
        let value = normalizedName(alias)
        guard !value.isEmpty, !Self.loopback.contains(value) else { return nil }
        return value
    }

    private static let loopback: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]

    /// Groups live records into hosts; deleted records are ignored by the caller (the catalog
    /// snapshot already excludes them). Output is sorted like the catalog: by name, then id.
    public static func group(_ records: [HostProfile]) -> [GlassShellHost] {
        guard !records.isEmpty else { return [] }
        var parent = Array(records.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        func join(_ a: Int, _ b: Int) { let ra = find(a), rb = find(b); if ra != rb { parent[max(ra, rb)] = min(ra, rb) } }

        var byName: [String: Int] = [:]
        var byAlias: [String: Int] = [:]
        for (index, record) in records.enumerated() {
            let name = normalizedName(record.displayName)
            if !name.isEmpty {
                if let first = byName[name] { join(first, index) } else { byName[name] = index }
            }
            for alias in (record.aliases + [record.address].compactMap { $0 }).compactMap(normalizedAlias) {
                if let first = byAlias[alias] { join(first, index) } else { byAlias[alias] = index }
            }
        }
        var groups: [Int: [HostProfile]] = [:]
        for (index, record) in records.enumerated() { groups[find(index), default: []].append(record) }
        return groups.values.map(GlassShellHost.init(members:)).sorted {
            if $0.displayName != $1.displayName { return $0.displayName < $1.displayName }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }
}
