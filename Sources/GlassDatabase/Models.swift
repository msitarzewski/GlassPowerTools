//
//  Models.swift
//  glassdb
//
//  Core data models for database connections, sessions, and configuration
//

import Foundation
import SwiftUI

// MARK: - Database Connection Configuration

/// One saved database service. Moved from `../glassdb/glassdb/Models.swift:13-140` with its
/// six SSH fields removed: under D7 the host owns the machine's address and its Terminal
/// service owns the tunnel, so a database service carries no SSH configuration of its own.
struct DatabaseConnectionConfig: Identifiable, Codable, Hashable {
    /// The persisted shape of this record. glassdb's format carried no version at all, so a
    /// record without one is version 1 — the pre-merge shape, with its own SSH fields.
    /// Version 2 is this one: no SSH fields, `usesHostTunnel` in their place.
    static let currentSchemaVersion = 2

    let id: UUID
    var name: String
    var engine: DatabaseEngineType
    /// The machine's address, or the managed file path for SQLite. Written from the host's
    /// address at commit and kept in step by `hostAddressDidChange`, exactly as the terminal
    /// keeps `ServerConfiguration.host` (`GlassTerminalHostAddressSync`).
    var host: String
    var port: Int
    var username: String
    var defaultDatabase: String?
    /// Reach the database through the host's own Terminal service instead of connecting to
    /// `host:port` directly — the D7 replacement for glassdb's `useSSHTunnel` plus its five
    /// SSH fields. The forward is brokered by the shell; this module never opens one itself.
    var usesHostTunnel: Bool
    /// Refuse every statement that is not a read on this service. Enforced on the connection
    /// itself (`ReadOnlyDatabaseConnection`), not by hiding buttons, because five of the app's
    /// write paths call the driver directly rather than going through `executeQuery`.
    var isReadOnly: Bool
    /// How many rows a page of this service's data holds, overriding the global setting.
    /// Nil means follow the global one. Clamped to 1...10,000 like the grid's own control.
    var rowPageSize: Int?
    var databaseCredentialPolicy: CredentialStoragePolicy
    var useTLS: Bool
    var isFavorite: Bool
    var colorTag: ConnectionColorTag
    let dateAdded: Date
    var lastConnected: Date?
    var tags: [String]
    /// The version this record was decoded from, carried so a later migration can tell a
    /// record it has already rewritten from one it has not.
    private(set) var schemaVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        engine: DatabaseEngineType = .mysql,
        host: String = "127.0.0.1",
        port: Int = 3306,
        username: String = "root",
        defaultDatabase: String? = nil,
        usesHostTunnel: Bool = false,
        isReadOnly: Bool = false,
        rowPageSize: Int? = nil,
        databaseCredentialPolicy: CredentialStoragePolicy = .appOnly,
        useTLS: Bool = false,
        isFavorite: Bool = false,
        colorTag: ConnectionColorTag = .none,
        dateAdded: Date = Date(),
        lastConnected: Date? = nil,
        tags: [String] = [],
        schemaVersion: Int = DatabaseConnectionConfig.currentSchemaVersion
    ) {
        self.id = id
        self.name = name
        self.engine = engine
        self.host = host
        self.port = port
        self.username = username
        self.defaultDatabase = defaultDatabase
        self.usesHostTunnel = usesHostTunnel
        self.isReadOnly = isReadOnly
        self.rowPageSize = rowPageSize.map { Self.clampedRowPageSize($0) }
        self.databaseCredentialPolicy = databaseCredentialPolicy
        self.useTLS = useTLS
        self.isFavorite = isFavorite
        self.colorTag = colorTag
        self.dateAdded = dateAdded
        self.lastConnected = lastConnected
        self.tags = tags
        self.schemaVersion = schemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id, name, engine, host, port, username, defaultDatabase
        case usesHostTunnel, isReadOnly, rowPageSize
        case databaseCredentialPolicy
        case useTLS, isFavorite, colorTag, dateAdded, lastConnected, tags
        /// Version 1 only. Read to migrate, never written.
        case useSSHTunnel
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        engine = try values.decodeIfPresent(DatabaseEngineType.self, forKey: .engine) ?? .mysql
        host = try values.decode(String.self, forKey: .host)
        port = try values.decode(Int.self, forKey: .port)
        username = try values.decode(String.self, forKey: .username)
        defaultDatabase = try values.decodeIfPresent(String.self, forKey: .defaultDatabase)
        // A version-1 record that tunnelled carried its own SSH host, port, user, auth method
        // and key id. None of them survive: the host's Terminal service supplies all five. The
        // intent — "this database is not reachable directly" — is what carries forward.
        usesHostTunnel = try values.decodeIfPresent(Bool.self, forKey: .usesHostTunnel)
            ?? values.decodeIfPresent(Bool.self, forKey: .useSSHTunnel)
            ?? false
        isReadOnly = try values.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
        // Re-clamped on read, not only in the UI: a hand-edited or corrupt value must not
        // become a page size the grid cannot render.
        rowPageSize = try values.decodeIfPresent(Int.self, forKey: .rowPageSize).map(Self.clampedRowPageSize)
        // Database passwords are never shared across the Glass family — no other capability has
        // a use for them. A shared (or legacy-defaulted) policy normalizes to app-only on read.
        let decodedDatabasePolicy = try values.decodeIfPresent(
            CredentialStoragePolicy.self,
            forKey: .databaseCredentialPolicy
        ) ?? .sharedWithGlas
        databaseCredentialPolicy = decodedDatabasePolicy == .sharedWithGlas
            ? .appOnly
            : decodedDatabasePolicy
        useTLS = try values.decodeIfPresent(Bool.self, forKey: .useTLS) ?? false
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        colorTag = try values.decodeIfPresent(ConnectionColorTag.self, forKey: .colorTag) ?? .none
        dateAdded = try values.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        lastConnected = try values.decodeIfPresent(Date.self, forKey: .lastConnected)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        // Always written at the current version: encoding is the rewrite.
        try values.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(engine, forKey: .engine)
        try values.encode(host, forKey: .host)
        try values.encode(port, forKey: .port)
        try values.encode(username, forKey: .username)
        try values.encodeIfPresent(defaultDatabase, forKey: .defaultDatabase)
        try values.encode(usesHostTunnel, forKey: .usesHostTunnel)
        try values.encode(isReadOnly, forKey: .isReadOnly)
        try values.encodeIfPresent(rowPageSize, forKey: .rowPageSize)
        try values.encode(databaseCredentialPolicy, forKey: .databaseCredentialPolicy)
        try values.encode(useTLS, forKey: .useTLS)
        try values.encode(isFavorite, forKey: .isFavorite)
        try values.encode(colorTag, forKey: .colorTag)
        try values.encode(dateAdded, forKey: .dateAdded)
        try values.encodeIfPresent(lastConnected, forKey: .lastConnected)
        try values.encode(tags, forKey: .tags)
    }

    /// The grid's own page-size control accepts 1 through 10,000; a per-service override
    /// obeys the same bounds.
    static func clampedRowPageSize(_ value: Int) -> Int { min(max(value, 1), 10_000) }

    var displaySubtitle: String {
        if engine == .sqlite {
            let filename = URL(fileURLWithPath: host).lastPathComponent
            return filename.isEmpty ? "Local SQLite database" : filename
        }
        var parts = ["\(username)@\(host):\(port)"]
        if let db = defaultDatabase, !db.isEmpty {
            parts.append(db)
        }
        return parts.joined(separator: " / ")
    }
}

// MARK: - Enums

enum DatabaseEngineType: String, Codable, CaseIterable, Identifiable {
    case mysql
    case postgresql
    case sqlite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mysql: return "MySQL"
        case .postgresql: return "PostgreSQL"
        case .sqlite: return "SQLite"
        }
    }

    var defaultPort: Int {
        switch self {
        case .mysql: return 3306
        case .postgresql: return 5432
        case .sqlite: return 0
        }
    }

    var iconName: String {
        switch self {
        case .mysql: return "cylinder"
        case .postgresql: return "cylinder.split.1x2"
        case .sqlite: return "externaldrive"
        }
    }

    var defaultHost: String {
        switch self {
        case .mysql, .postgresql: "127.0.0.1"
        case .sqlite: ""
        }
    }

    var defaultUsername: String {
        switch self {
        case .mysql: "root"
        case .postgresql: "postgres"
        case .sqlite: ""
        }
    }

    var supportsNetworkTransport: Bool { self != .sqlite }
    var supportsCredentials: Bool { self != .sqlite }
    var supportsTLS: Bool { self != .sqlite }
    var supportsSSHTunnel: Bool { self != .sqlite }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self).lowercased()
        switch value {
        case "mysql", "mariadb": self = .mysql
        case "postgres", "postgresql", "postgres-nio": self = .postgresql
        case "sqlite", "sqlite3": self = .sqlite
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported database engine ‘\(value)’"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum AuthenticationMethod: String, Codable, CaseIterable {
    case password
    case sshKey

    var displayName: String {
        switch self {
        case .password: return "Password"
        case .sshKey: return "SSH Key"
        }
    }
}

enum CredentialStoragePolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case sharedWithGlas
    /// Raw value preserved so version-1 records still decode.
    case appOnly = "glassdbOnly"
    case requireAuthentication

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sharedWithGlas: return "Shared with glas.sh"
        case .appOnly: return "This app only"
        case .requireAuthentication: return "Require authentication"
        }
    }

    var policyDescription: String {
        switch self {
        case .sharedWithGlas:
            return "Available to every Glass app on this device while it is unlocked."
        case .appOnly:
            return "Stored in this app's private, device-only Keychain namespace."
        case .requireAuthentication:
            return "Private to this app and requires device-owner authentication before every use."
        }
    }

    /// Database passwords are never shared across the Glass family; sharing is an
    /// SSH-credential concept, and no other capability has a use for database secrets.
    static var databasePolicies: [CredentialStoragePolicy] {
        [.appOnly, .requireAuthentication]
    }
}

enum ConnectionColorTag: String, Codable, CaseIterable {
    case none
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink

    var color: Color {
        switch self {
        case .none: return .secondary
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Session State

enum SessionState: Equatable {
    case disconnected
    case connecting(stage: ConnectionStage)
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
}

enum ConnectionStage: String, Equatable {
    case resolvingHost = "Resolving host..."
    case openingHostTunnel = "Opening tunnel through the host..."
    case authenticating = "Authenticating..."
    case selectingDatabase = "Selecting database..."
    case ready = "Connected"
}

// MARK: - Saved Query

struct SavedQuery: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var sql: String
    var connectionID: UUID?
    var lastUsed: Date?
    var useCount: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sql: String,
        connectionID: UUID? = nil,
        lastUsed: Date? = nil,
        useCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sql = sql
        self.connectionID = connectionID
        self.lastUsed = lastUsed
        self.useCount = useCount
        self.createdAt = createdAt
    }
}

// MARK: - Mutation Audit

enum MutationOutcome: String, Codable, Sendable {
    case committed
    case rolledBack
    case serverStateUnknown
    case notStarted
}

struct MutationAuditRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let connectionID: UUID
    let database: String?
    let object: String?
    let normalizedOperation: String
    let source: String
    let timestamp: Date
    let outcome: MutationOutcome
    let affectedRows: UInt64?

    init(
        id: UUID = UUID(),
        connectionID: UUID,
        database: String?,
        object: String?,
        normalizedOperation: String,
        source: String,
        timestamp: Date = Date(),
        outcome: MutationOutcome,
        affectedRows: UInt64?
    ) {
        self.id = id
        self.connectionID = connectionID
        self.database = database
        self.object = object
        self.normalizedOperation = normalizedOperation
        self.source = source
        self.timestamp = timestamp
        self.outcome = outcome
        self.affectedRows = affectedRows
    }
}

@MainActor
enum MutationAuditStore {
    private static let storageKey = UserDefaultsKeys.mutationAudit
    private static let maximumRecords = 1_000

    static func append(_ record: MutationAuditRecord, defaults: UserDefaults = .standard) {
        var records: [MutationAuditRecord] = []
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MutationAuditRecord].self, from: data) {
            records = decoded
        }
        records.append(record)
        if records.count > maximumRecords {
            records.removeFirst(records.count - maximumRecords)
        }
        if let encoded = try? JSONEncoder().encode(records) {
            defaults.set(encoded, forKey: storageKey)
        }
    }
}
