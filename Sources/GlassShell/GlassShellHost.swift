import Foundation
import GlassConnectionKit

/// One machine as the library shows it: every catalog record that describes the same host,
/// consolidated for presentation. The shared catalog was written by three separate apps, each of
/// which created its own `HostProfile` per endpoint (`HostCatalogStore.applyPublication` keys new
/// records by the endpoint's id and matches only by endpoint id), so "bravo" from glas.sh and
/// "bravo" from glassDT are two records. Until Stage 6 those apps still read the file by their
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
    /// On the local host the capabilities' built-in services come first, then the saved ones.
    public let services: [HostServiceLink]
    public let createdAt: Date
    /// Canonical first.
    public let members: [HostProfile]
    /// This is the device itself (D8), not a machine to reach. See `GlassLocalHost`.
    public let isLocal: Bool
    /// Services a capability provides on this device without setup, so nothing is stored for
    /// them: they cannot be edited or removed, and the capability that minted the endpoint id
    /// recognises it in `open`. Always empty off the local host.
    public let builtInEndpointIDs: Set<EndpointID>

    public var canonical: HostProfile { members[0] }
    public var isConsolidated: Bool { members.count > 1 }

    public func isBuiltIn(_ endpointID: EndpointID) -> Bool { builtInEndpointIDs.contains(endpointID) }

    /// Whether "connect the machine" means anything here. False on the device itself: see
    /// `GlassShellModel.connectAll(hostID:)` for the reasoning.
    public var allowsConnectAll: Bool { !isLocal }

    public func member(owning endpointID: EndpointID) -> HostProfile? {
        members.first { $0.services.contains { $0.endpointID == endpointID } }
    }

    /// The record a service belongs to. A built-in local service has no stored link, so it is
    /// answered by the local record itself: it is that device's service, just not a saved one.
    public func record(owning endpointID: EndpointID) -> HostProfile? {
        member(owning: endpointID) ?? (isBuiltIn(endpointID) ? canonical : nil)
    }

    public func contains(_ hostID: HostID) -> Bool { members.contains { $0.id == hostID } }

    /// The device's own host: one record, never grouped with anything, plus whatever the
    /// registered capabilities provide on it without setup.
    init(local record: HostProfile, builtInServices: [HostServiceLink]) {
        id = record.id
        displayName = record.displayName
        // The host has no address; its services are given `GlassLocalHost.address` at commit time.
        address = nil
        addresses = []
        aliases = record.aliases
        tags = record.tags
        var seen = Set<EndpointID>()
        services = (builtInServices + record.services).filter { seen.insert($0.endpointID).inserted }
        createdAt = record.createdAt
        members = [record]
        isLocal = true
        builtInEndpointIDs = Set(builtInServices.map(\.endpointID))
    }

    init(members: [HostProfile]) {
        isLocal = false
        builtInEndpointIDs = []
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
            // As Finder sorts: "bravo" before "Zulu", "web2" before "web10".
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }
}

extension GlassShellHost {
    /// What deleting a host does, for its confirmation: the services' settings and saved passwords
    /// go with it, on every device the library reaches. SSH keys are the library's and stay.
    static func deletionConsequence(_ host: GlassShellHost) -> String {
        guard !host.services.isEmpty else {
            return "This removes \(host.displayName) from your library on every device."
        }
        let services = host.services.count == 1 ? "its service" : "its \(host.services.count) services"
        return "This removes \(host.displayName) and \(services) from your library on every device, with each service's settings and saved password. Your SSH keys stay in SSH Keys."
    }
}
