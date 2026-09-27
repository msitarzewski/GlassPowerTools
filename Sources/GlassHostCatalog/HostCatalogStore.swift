import Foundation
import GlassConnectionKit
import Darwin

public struct HostPublication: Hashable, Sendable {
    public let service: HostServiceLink
    public let hostName: String
    public let aliases: [String]
    public init(service: HostServiceLink, hostName: String, aliases: [String] = []) {
        self.service = service
        self.hostName = hostName
        self.aliases = aliases
    }
}

public enum HostCatalogError: Error, Equatable, Sendable {
    case unsupportedVersion(UInt16)
    case tooLarge
    case duplicateHost(HostID)
    case endpointAlreadyPaired(EndpointID)
    case endpointNotFound(EndpointID)
    case hostNotFound(HostID)
    case hostDeleted(HostID)
    case fileLockFailed(Int32)
}

/// File-backed family metadata. The caller supplies an App Group or private URL.
/// Each operation locks, reloads and atomically replaces the file, so independent
/// app processes do not overwrite each other's changes. No secrets are stored.
public actor HostCatalogStore {
    public let fileURL: URL
    public let writerID: WriterID
    private static let maximumBytes = 8 * 1024 * 1024
    private static let maximumHosts = 10_000

    public init(fileURL: URL, writerID: WriterID = WriterID()) {
        self.fileURL = fileURL
        self.writerID = writerID
    }

    public func snapshot(includeDeleted: Bool = false) throws -> [HostProfile] {
        try transaction(write: false) { hosts in
            hosts.filter { includeDeleted || $0.deletedAt == nil }.sorted {
                if $0.displayName != $1.displayName { return $0.displayName < $1.displayName }
                return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
            }
        }
    }

    public func upsert(_ profile: HostProfile) throws {
        try profile.validate()
        try transaction { hosts in
            var candidate = profile
            if let index = hosts.firstIndex(where: { $0.id == candidate.id }) {
                guard hosts[index].deletedAt == nil else { throw HostCatalogError.hostDeleted(candidate.id) }
                candidate.updatedAt = Self.revision(Date(), after: hosts[index].updatedAt)
                candidate.lastWriterID = writerID
                hosts[index] = candidate
            } else {
                candidate.lastWriterID = writerID
                hosts.append(candidate)
            }
        }
    }

    /// Publish app-owned endpoint metadata without undoing a user's host pairing.
    /// Repeated publication follows the current endpoint membership. Existing host
    /// labels/tags remain user-owned; publishers may update their service label and
    /// add aliases. A missing credential reference cannot erase an existing one.
    @discardableResult
    public func publish(service: HostServiceLink, hostName: String, aliases: [String] = [],
                        at date: Date = Date()) throws -> HostProfile {
        try transaction { hosts in
            try applyPublication(service: service, hostName: hostName, aliases: aliases, at: date, hosts: &hosts)
        }
    }

    /// Publish a whole app-owned metadata snapshot under one transaction. A bad
    /// record aborts the batch; no prior publication or pairing is discarded.
    @discardableResult
    public func publish(_ records: [HostPublication], at date: Date = Date()) throws -> [HostProfile] {
        guard records.count <= Self.maximumHosts else { throw HostCatalogError.tooLarge }
        return try transaction { hosts in
            try records.map { record in
                try applyPublication(service: record.service, hostName: record.hostName,
                                     aliases: record.aliases, at: date, hosts: &hosts)
            }
        }
    }

    private func applyPublication(service: HostServiceLink, hostName: String, aliases: [String],
                                  at date: Date, hosts: inout [HostProfile]) throws -> HostProfile {
        if let hostIndex = hosts.firstIndex(where: {
            $0.deletedAt == nil && $0.services.contains { $0.endpointID == service.endpointID }
        }), let linkIndex = hosts[hostIndex].services.firstIndex(where: { $0.endpointID == service.endpointID }) {
            let old = hosts[hostIndex]
            guard old.services[linkIndex].kind == service.kind else {
                throw HostCatalogError.endpointAlreadyPaired(service.endpointID)
            }
            var link = service
            if link.credentialID == nil { link.credentialID = old.services[linkIndex].credentialID }
            var links = old.services
            links[linkIndex] = link
            let normalizedAliases = Array(Set((old.aliases + aliases).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            }.filter { !$0.isEmpty })).sorted()
            if links == old.services && normalizedAliases == old.aliases { return old }
            let updated = try HostProfile(id: old.id, displayName: old.displayName, address: old.address,
                aliases: old.aliases + aliases, services: links, tags: old.tags,
                createdAt: old.createdAt, updatedAt: Self.revision(date, after: old.updatedAt),
                lastWriterID: writerID)
            hosts[hostIndex] = updated
            return updated
        }
        let id = HostID(rawValue: service.endpointID.rawValue)
        // Do not resurrect a user-deleted grouping during an app's next launch.
        if let existing = hosts.first(where: { $0.id == id }) {
            if existing.deletedAt != nil { throw HostCatalogError.hostDeleted(id) }
            throw HostCatalogError.duplicateHost(id)
        }
        let created = try HostProfile(id: id, displayName: hostName, aliases: aliases,
            services: [service], createdAt: date, updatedAt: date, lastWriterID: writerID)
        hosts.append(created)
        return created
    }

    /// Move an existing link atomically. Credentials and protocol identity remain
    /// unchanged. Only an emptied source grouping becomes a tombstone.
    public func move(endpointID: EndpointID, to hostID: HostID, at date: Date = Date()) throws {
        try transaction { hosts in
            guard let targetIndex = hosts.firstIndex(where: { $0.id == hostID }) else {
                throw HostCatalogError.hostNotFound(hostID)
            }
            guard hosts[targetIndex].deletedAt == nil else { throw HostCatalogError.hostDeleted(hostID) }
            guard let sourceIndex = hosts.firstIndex(where: {
                $0.deletedAt == nil && $0.services.contains { $0.endpointID == endpointID }
            }), let linkIndex = hosts[sourceIndex].services.firstIndex(where: { $0.endpointID == endpointID }) else {
                throw HostCatalogError.endpointNotFound(endpointID)
            }
            guard sourceIndex != targetIndex else { return }
            let link = hosts[sourceIndex].services.remove(at: linkIndex)
            hosts[sourceIndex].updatedAt = Self.revision(date, after: hosts[sourceIndex].updatedAt)
            hosts[sourceIndex].lastWriterID = writerID
            if hosts[sourceIndex].services.isEmpty { hosts[sourceIndex].deletedAt = hosts[sourceIndex].updatedAt }
            hosts[targetIndex].services.append(link)
            hosts[targetIndex].updatedAt = Self.revision(date, after: hosts[targetIndex].updatedAt)
            hosts[targetIndex].lastWriterID = writerID
        }
    }

    /// Remove a service from a grouping without deleting its discoverable entry.
    /// A new metadata-only host owns the unchanged endpoint/credential reference;
    /// subsequent publication follows that membership instead of restoring the pair.
    @discardableResult
    public func detach(endpointID: EndpointID, at date: Date = Date()) throws -> HostProfile {
        try transaction { hosts in
            guard let sourceIndex = hosts.firstIndex(where: {
                $0.deletedAt == nil && $0.services.contains { $0.endpointID == endpointID }
            }), let linkIndex = hosts[sourceIndex].services.firstIndex(where: { $0.endpointID == endpointID }) else {
                throw HostCatalogError.endpointNotFound(endpointID)
            }
            let source = hosts[sourceIndex]
            // Already standalone is an idempotent success, without a new revision.
            guard source.services.count > 1 else { return source }
            let link = hosts[sourceIndex].services.remove(at: linkIndex)
            let revision = Self.revision(date, after: source.updatedAt)
            hosts[sourceIndex].updatedAt = revision
            hosts[sourceIndex].lastWriterID = writerID
            let detached = try HostProfile(displayName: link.displayName,
                aliases: source.aliases, services: [link], createdAt: revision,
                updatedAt: revision, lastWriterID: writerID)
            hosts.append(detached)
            return detached
        }
    }

    /// A publisher calls this only after its endpoint deletion commits. Missing
    /// endpoints are an idempotent success, allowing durable deletion retries.
    /// Removing the last reference tombstones the grouping; secrets are untouched.
    public func remove(endpointID: EndpointID, at date: Date = Date()) throws {
        try transaction { hosts in
            guard let index = hosts.firstIndex(where: {
                $0.deletedAt == nil && $0.services.contains { $0.endpointID == endpointID }
            }) else { return }
            hosts[index].services.removeAll { $0.endpointID == endpointID }
            hosts[index].updatedAt = Self.revision(date, after: hosts[index].updatedAt)
            hosts[index].lastWriterID = writerID
            if hosts[index].services.isEmpty { hosts[index].deletedAt = hosts[index].updatedAt }
        }
    }

    public func pair(_ service: HostServiceLink, with hostID: HostID, at date: Date = Date()) throws {
        try mutate(hostID: hostID, at: date) { host in
            if let index = host.services.firstIndex(where: { $0.endpointID == service.endpointID }) {
                // Replacing a display label must not silently switch protocol identity.
                guard host.services[index].kind == service.kind else {
                    throw HostCatalogError.endpointAlreadyPaired(service.endpointID)
                }
                host.services[index] = service
            } else { host.services.append(service) }
        }
    }

    public func unpair(endpointID: EndpointID, from hostID: HostID, at date: Date = Date()) throws {
        try mutate(hostID: hostID, at: date) { host in
            host.services.removeAll { $0.endpointID == endpointID }
        }
    }

    /// A tombstone removes the grouping only; endpoint/credential stores are untouched.
    public func delete(hostID: HostID, at date: Date = Date()) throws {
        try mutate(hostID: hostID, at: date) { host in host.deletedAt = host.updatedAt }
    }

    /// Merge a non-secret snapshot using deletion precedence, revision time and
    /// writer ID. Tombstones cannot be resurrected by an offline writer; creating
    /// a new grouping requires a new HostID. Equal-revision payloads have a canonical final tie-break.
    /// Invalid or multiply-paired input fails atomically, preserving the file.
    public func merge(_ incoming: [HostProfile]) throws {
        try Self.validate(incoming)
        try transaction { hosts in
            var byID = Dictionary(uniqueKeysWithValues: hosts.map { ($0.id, $0) })
            for candidate in incoming {
                if let current = byID[candidate.id] {
                    if try Self.precedes(current, candidate) { byID[candidate.id] = candidate }
                } else { byID[candidate.id] = candidate }
            }
            hosts = Array(byID.values)
        }
    }

    private func mutate(hostID: HostID, at date: Date,
                        _ body: (inout HostProfile) throws -> Void) throws {
        try transaction { hosts in
            guard let index = hosts.firstIndex(where: { $0.id == hostID }) else {
                throw HostCatalogError.hostNotFound(hostID)
            }
            guard hosts[index].deletedAt == nil else { throw HostCatalogError.hostDeleted(hostID) }
            hosts[index].updatedAt = Self.revision(date, after: hosts[index].updatedAt)
            hosts[index].lastWriterID = writerID
            try body(&hosts[index])
        }
    }

    private struct Envelope: Codable {
        let schemaVersion: UInt16
        let hosts: [HostProfile]
    }

    private func transaction<T>(write: Bool = true,
                                _ body: (inout [HostProfile]) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let descriptor = open(fileURL.appendingPathExtension("lock").path,
                              O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw HostCatalogError.fileLockFailed(errno) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw HostCatalogError.fileLockFailed(errno) }
        }
        defer { flock(descriptor, LOCK_UN) }
        var hosts = try load()
        let previous = hosts
        let result = try body(&hosts)
        if write && hosts != previous {
            try Self.validate(hosts)
            let data = try Self.encoder().encode(Envelope(schemaVersion: 1, hosts: hosts.sorted {
                $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
            }))
            guard data.count <= Self.maximumBytes else { throw HostCatalogError.tooLarge }
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        }
        return result
    }

    private func load() throws -> [HostProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= Self.maximumBytes else {
            throw HostCatalogError.tooLarge
        }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= Self.maximumBytes else { throw HostCatalogError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw HostCatalogError.unsupportedVersion(envelope.schemaVersion) }
        try Self.validate(envelope.hosts)
        return envelope.hosts
    }

    private static func validate(_ hosts: [HostProfile]) throws {
        guard hosts.count <= maximumHosts else { throw HostCatalogError.tooLarge }
        var ids = Set<HostID>()
        var endpoints = Set<EndpointID>()
        for host in hosts {
            try host.validate()
            guard ids.insert(host.id).inserted else { throw HostCatalogError.duplicateHost(host.id) }
            if host.deletedAt == nil {
                for service in host.services {
                    guard endpoints.insert(service.endpointID).inserted else {
                        throw HostCatalogError.endpointAlreadyPaired(service.endpointID)
                    }
                }
            }
        }
    }

    private static func revision(_ date: Date, after previous: Date) -> Date {
        let value = max(date, previous.addingTimeInterval(0.001))
        return Date(timeIntervalSince1970: (value.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Whether `rhs` should replace `lhs` in a merge: the later statement about the record wins,
    /// **a deletion included** — a tombstone is dated, and it beats a live record only when it is
    /// the more recent of the two. Equal dates keep the tombstone, so a stale echo of an edit
    /// cannot undo a delete made at the same instant.
    ///
    /// It used to make a tombstone immortal — beat the live record whatever the dates — which is
    /// the rule `GlassCatalogMerge.winner` never had. On 2026-09-21 the two disagreed and the
    /// store's rule ate a server's record on the Mac: the phone folded its records into one, the merged
    /// record arrived live and newer, and the Mac's five-day-old tombstone for that record id
    /// refused it — silently, because the reconcile had already decided the live record won.
    private static func precedes(_ lhs: HostProfile, _ rhs: HostProfile) throws -> Bool {
        if (lhs.deletedAt != nil) != (rhs.deletedAt != nil) {
            let live = lhs.deletedAt == nil ? lhs : rhs
            let dead = lhs.deletedAt == nil ? rhs : lhs
            let deathBeatsLife = dead.deletedAt! >= live.updatedAt
            // `rhs` replaces `lhs` when it is the winner.
            return (rhs.deletedAt != nil) == deathBeatsLife
        }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        if lhs.lastWriterID != rhs.lastWriterID {
            return lhs.lastWriterID.rawValue.uuidString < rhs.lastWriterID.rawValue.uuidString
        }
        return try encoder().encode(lhs).lexicographicallyPrecedes(encoder().encode(rhs))
    }
}
