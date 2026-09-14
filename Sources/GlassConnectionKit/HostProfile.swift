import Foundation

/// A user-confirmed grouping, never proof that endpoints share identity or trust.
public struct HostID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(UUID.self)
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString.lowercased())
    }
}

public enum HostServiceKind: String, Codable, CaseIterable, Sendable {
    case rdp, ssh, database
}

/// Metadata and a reference to a credential — never the credential itself, and pairing still
/// grants no trust.
///
/// `configuration` is D26: the capability's own record for this service, encoded by the capability
/// that owns it and opaque to everything else. The catalog is the one store for a connection, so
/// this is the record rather than a copy of one — which is what lets a host added on one device be
/// connectable from another. It carries metadata only: a password or key never enters it, because
/// secrets have their own synchronized home in the Keychain and the reference above is how they
/// are found.
public struct HostServiceLink: Codable, Hashable, Sendable, Identifiable {
    public var id: EndpointID { endpointID }
    public let endpointID: EndpointID
    public let kind: HostServiceKind
    public var displayName: String
    public var credentialID: CredentialID?
    public var configuration: Data?

    public init(endpointID: EndpointID, kind: HostServiceKind, displayName: String,
                credentialID: CredentialID? = nil, configuration: Data? = nil) {
        self.endpointID = endpointID
        self.kind = kind
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.credentialID = credentialID
        self.configuration = configuration
    }
}

public enum HostProfileError: Error, Equatable, Sendable {
    case unsupportedVersion(UInt16)
    case invalidName
    case tooManyEntries
    case invalidAlias
    case invalidTag
    case duplicateService(EndpointID)
    case invalidTimestamp
    case invalidAddress
}

public struct HostProfile: Codable, Hashable, Sendable, Identifiable {
    public static let currentSchemaVersion: UInt16 = 1
    public let schemaVersion: UInt16
    public let id: HostID
    public var displayName: String
    /// The machine's network identity — a DNS name, an IPv4 or an IPv6 literal — shared by every
    /// service on the host. Optional on the wire so records written before it existed, and by
    /// apps that do not know it, still decode (schema 1). Services derive their endpoint address
    /// from it; the shell edits it once.
    public var address: String?
    public var aliases: [String]
    public var services: [HostServiceLink]
    public var tags: [String]
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var lastWriterID: WriterID

    public init(id: HostID = HostID(), displayName: String, address: String? = nil, aliases: [String] = [],
                services: [HostServiceLink] = [], tags: [String] = [],
                createdAt: Date = Date(), updatedAt: Date = Date(),
                deletedAt: Date? = nil, lastWriterID: WriterID = WriterID()) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = try address.map(Self.normalizedAddress)
        self.aliases = Self.normalized(aliases)
        self.services = services
        self.tags = Self.normalized(tags)
        guard createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite,
              updatedAt >= createdAt,
              deletedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= createdAt && $0 <= updatedAt }) ?? true
        else { throw HostProfileError.invalidTimestamp }
        self.createdAt = Self.canonicalTimestamp(createdAt)
        self.updatedAt = Self.canonicalTimestamp(updatedAt)
        self.deletedAt = deletedAt.map(Self.canonicalTimestamp)
        self.lastWriterID = lastWriterID
        try validate()
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw HostProfileError.unsupportedVersion(schemaVersion)
        }
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              displayName.utf8.count <= 1024 else { throw HostProfileError.invalidName }
        guard aliases.count <= 64, tags.count <= 64, services.count <= 128 else {
            throw HostProfileError.tooManyEntries
        }
        if let address { guard Self.isValidAddress(address) else { throw HostProfileError.invalidAddress } }
        guard aliases.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }) else {
            throw HostProfileError.invalidAlias
        }
        guard tags.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }) else {
            throw HostProfileError.invalidTag
        }
        var endpoints = Set<EndpointID>()
        for service in services {
            guard !service.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  service.displayName.utf8.count <= 1024 else { throw HostProfileError.invalidName }
            guard endpoints.insert(service.endpointID).inserted else {
                throw HostProfileError.duplicateService(service.endpointID)
            }
        }
        guard createdAt.timeIntervalSince1970.isFinite,
              updatedAt.timeIntervalSince1970.isFinite, updatedAt >= createdAt,
              deletedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= createdAt && $0 <= updatedAt }) ?? true
        else { throw HostProfileError.invalidTimestamp }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, displayName, address, aliases, services, tags
        case createdAt, updatedAt, deletedAt, lastWriterID
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(displayName, forKey: .displayName)
        // Absent, not null, so readers that predate the field see a record they already know.
        try values.encodeIfPresent(address, forKey: .address)
        try values.encode(aliases, forKey: .aliases)
        try values.encode(services, forKey: .services)
        try values.encode(tags, forKey: .tags)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try values.encode(lastWriterID, forKey: .lastWriterID)
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(UInt16.self, forKey: .schemaVersion)
        id = try values.decode(HostID.self, forKey: .id)
        displayName = try values.decode(String.self, forKey: .displayName)
        // A malformed address written by another writer must not make the whole catalog
        // unreadable; it is dropped and the host stays usable without one.
        address = try values.decodeIfPresent(String.self, forKey: .address).flatMap { try? Self.normalizedAddress($0) }
        aliases = try values.decode([String].self, forKey: .aliases)
        services = try values.decode([HostServiceLink].self, forKey: .services)
        tags = try values.decode([String].self, forKey: .tags)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
        lastWriterID = try values.decode(WriterID.self, forKey: .lastWriterID)
        try validate()
    }

    /// Trims, strips IPv6 brackets, lowercases DNS names and IPv6 hex; an empty result is an
    /// error rather than a silent nil so a caller cannot mistake "blank" for "unset".
    public static func normalizedAddress(_ raw: String) throws -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("["), value.hasSuffix("]"), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        value = value.lowercased()
        guard isValidAddress(value) else { throw HostProfileError.invalidAddress }
        return value
    }

    /// A DNS name (letters, digits, hyphens, dots; no leading/trailing dot; labels ≤ 63),
    /// a dotted IPv4 literal, or an IPv6 literal (hex and colons, optional zone).
    public static func isValidAddress(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 253, !value.contains(where: \.isWhitespace) else { return false }
        if value.contains(":") {
            let zoneSplit = value.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
            let hex = zoneSplit[0]
            guard !hex.isEmpty, hex.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }),
                  hex.filter({ $0 == ":" }).count >= 2 else { return false }
            if zoneSplit.count == 2, zoneSplit[1].isEmpty { return false }
            return true
        }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }) else { return false }
        return true
    }

    private static func normalized(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping }.filter { !$0.isEmpty })).sorted()
    }

    /// Match the catalog's millisecond wire precision before returning new values,
    /// so a save/reload cannot introduce artificial revisions or equality changes.
    private static func canonicalTimestamp(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}
