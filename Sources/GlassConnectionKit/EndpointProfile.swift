import Foundation

public struct EndpointID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: UUID

    public var id: UUID { rawValue }

    public init() {
        self.init(rawValue: UUID())
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let identifier = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "EndpointID must be a UUID string."
            )
        }
        self.init(rawValue: identifier)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString.lowercased())
    }
}

public struct CredentialID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: UUID

    public var id: UUID { rawValue }

    public init() {
        self.init(rawValue: UUID())
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let identifier = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "CredentialID must be a UUID string."
            )
        }
        self.init(rawValue: identifier)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString.lowercased())
    }
}

public struct WriterID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: UUID

    public var id: UUID { rawValue }

    public init() {
        self.init(rawValue: UUID())
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let identifier = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "WriterID must be a UUID string."
            )
        }
        self.init(rawValue: identifier)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString.lowercased())
    }
}

public enum EndpointAppVisibility: String, Codable, CaseIterable, Sendable {
    case glasShOnly
    case glassdbOnly
    case glassFamily
}

public enum EndpointProfileValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(UInt16)
    case emptyField(String)
    case fieldTooLong(String, maximum: Int)
    case tooManyJumpEndpoints(maximum: Int)
    case selfReferentialJumpEndpoint
    case duplicateJumpEndpoint(EndpointID)
    case tooManyTags(maximum: Int)
    case tagTooLong(maximum: Int)
    case updatedBeforeCreation
    case deletionBeforeCreation
}

extension EndpointProfileValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported endpoint schema version: \(version)."
        case .emptyField(let field):
            "Endpoint field '\(field)' must not be empty."
        case .fieldTooLong(let field, let maximum):
            "Endpoint field '\(field)' exceeds \(maximum) characters."
        case .tooManyJumpEndpoints(let maximum):
            "An endpoint may reference at most \(maximum) jump endpoints."
        case .selfReferentialJumpEndpoint:
            "An endpoint cannot reference itself as a jump endpoint."
        case .duplicateJumpEndpoint(let identifier):
            "Jump endpoint \(identifier.rawValue.uuidString.lowercased()) is duplicated."
        case .tooManyTags(let maximum):
            "An endpoint may contain at most \(maximum) tags."
        case .tagTooLong(let maximum):
            "An endpoint tag exceeds \(maximum) characters."
        case .updatedBeforeCreation:
            "The endpoint update timestamp precedes its creation timestamp."
        case .deletionBeforeCreation:
            "The endpoint deletion timestamp precedes its creation timestamp."
        }
    }
}

public struct EndpointProfile: Codable, Hashable, Sendable {
    public static let currentSchemaVersion: UInt16 = 1
    public static let maximumDisplayNameLength = 256
    public static let maximumHostLength = 255
    public static let maximumUsernameLength = 255
    public static let maximumJumpEndpointCount = 16
    public static let maximumTagCount = 64
    public static let maximumTagLength = 64

    public let schemaVersion: UInt16
    public let id: EndpointID
    public var displayName: String
    public var host: String
    public var port: UInt16
    public var username: String
    public var credentialID: CredentialID?
    public var jumpEndpointIDs: [EndpointID]
    public var tags: [String]
    public var appVisibility: EndpointAppVisibility
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var lastWriterID: WriterID

    public init(
        schemaVersion: UInt16 = EndpointProfile.currentSchemaVersion,
        id: EndpointID = EndpointID(),
        displayName: String,
        host: String,
        port: UInt16 = 22,
        username: String,
        credentialID: CredentialID? = nil,
        jumpEndpointIDs: [EndpointID] = [],
        tags: [String] = [],
        appVisibility: EndpointAppVisibility,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        lastWriterID: WriterID
    ) throws {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = Self.normalized(displayName)
        self.host = Self.normalized(host)
        self.port = port
        self.username = Self.normalized(username)
        self.credentialID = credentialID
        self.jumpEndpointIDs = jumpEndpointIDs
        self.tags = Self.normalizedTags(tags)
        self.appVisibility = appVisibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastWriterID = lastWriterID
        try validate()
    }

    public func validated() throws -> EndpointProfile {
        try EndpointProfile(
            schemaVersion: schemaVersion,
            id: id,
            displayName: displayName,
            host: host,
            port: port,
            username: username,
            credentialID: credentialID,
            jumpEndpointIDs: jumpEndpointIDs,
            tags: tags,
            appVisibility: appVisibility,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastWriterID: lastWriterID
        )
    }

    public mutating func normalizeAndValidate() throws {
        self = try validated()
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw EndpointProfileValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.validateRequired(
            displayName,
            field: "displayName",
            maximum: Self.maximumDisplayNameLength
        )
        try Self.validateRequired(host, field: "host", maximum: Self.maximumHostLength)
        try Self.validateRequired(
            username,
            field: "username",
            maximum: Self.maximumUsernameLength
        )
        guard jumpEndpointIDs.count <= Self.maximumJumpEndpointCount else {
            throw EndpointProfileValidationError.tooManyJumpEndpoints(
                maximum: Self.maximumJumpEndpointCount
            )
        }
        var uniqueJumpEndpoints = Set<EndpointID>()
        for jumpEndpointID in jumpEndpointIDs {
            guard jumpEndpointID != id else {
                throw EndpointProfileValidationError.selfReferentialJumpEndpoint
            }
            guard uniqueJumpEndpoints.insert(jumpEndpointID).inserted else {
                throw EndpointProfileValidationError.duplicateJumpEndpoint(jumpEndpointID)
            }
        }
        guard tags.count <= Self.maximumTagCount else {
            throw EndpointProfileValidationError.tooManyTags(maximum: Self.maximumTagCount)
        }
        guard tags.allSatisfy({ !$0.isEmpty && $0.count <= Self.maximumTagLength }) else {
            throw EndpointProfileValidationError.tagTooLong(maximum: Self.maximumTagLength)
        }
        guard updatedAt >= createdAt else {
            throw EndpointProfileValidationError.updatedBeforeCreation
        }
        if let deletedAt, deletedAt < createdAt {
            throw EndpointProfileValidationError.deletionBeforeCreation
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(UInt16.self, forKey: .schemaVersion),
            id: container.decode(EndpointID.self, forKey: .id),
            displayName: container.decode(String.self, forKey: .displayName),
            host: container.decode(String.self, forKey: .host),
            port: container.decode(UInt16.self, forKey: .port),
            username: container.decode(String.self, forKey: .username),
            credentialID: container.decodeIfPresent(CredentialID.self, forKey: .credentialID),
            jumpEndpointIDs: container.decode([EndpointID].self, forKey: .jumpEndpointIDs),
            tags: container.decode([String].self, forKey: .tags),
            appVisibility: container.decode(EndpointAppVisibility.self, forKey: .appVisibility),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt),
            deletedAt: container.decodeIfPresent(Date.self, forKey: .deletedAt),
            lastWriterID: container.decode(WriterID.self, forKey: .lastWriterID)
        )
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var uniqueTags = Set<String>()
        for tag in tags {
            let value = normalized(tag)
            if !value.isEmpty {
                uniqueTags.insert(value)
            }
        }
        return uniqueTags.sorted { left, right in
            left.utf8.lexicographicallyPrecedes(right.utf8)
        }
    }

    private static func validateRequired(
        _ value: String,
        field: String,
        maximum: Int
    ) throws {
        guard !value.isEmpty else {
            throw EndpointProfileValidationError.emptyField(field)
        }
        guard value.count <= maximum else {
            throw EndpointProfileValidationError.fieldTooLong(field, maximum: maximum)
        }
    }
}

public enum EndpointProfileCodec {
    public static func encode(_ profile: EndpointProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(profile.validated())
    }

    public static func decode(_ data: Data) throws -> EndpointProfile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(EndpointProfile.self, from: data)
    }
}
