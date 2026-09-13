//
//  Models.swift
//  glassdb
//
//  Core data models for database connections, sessions, and configuration
//

import Foundation
import SwiftUI
import GlassDBKit

// MARK: - TLS verification

/// How a service checks the certificate the server presents, once `useTLS` is on.
///
/// Three named modes, all chosen by the user. The app never moves between them on its own and
/// never retries a rejected connection with a weaker one: a failed handshake stays a failure
/// (D13). The weakest of the three still authenticates the certificate chain — none of them is
/// "encrypt and trust anything".
enum DatabaseTLSVerification: String, Codable, CaseIterable, Hashable, Sendable {
    /// Verified against the system's trust roots and against this machine's name.
    case systemTrust
    /// Verified against a certificate the user supplied, and against this machine's name.
    case pinnedCertificate
    /// Verified against a certificate the user supplied. **The name is not checked.**
    case pinnedCertificateAuthorityOnly

    var displayName: String {
        switch self {
        case .systemTrust: "Verify with the system's certificate authorities"
        case .pinnedCertificate: "Verify with a certificate I supply"
        case .pinnedCertificateAuthorityOnly: "Verify with a certificate I supply, without checking the server's name"
        }
    }

    /// Said plainly, and said in the sheet, because this is where a user decides how much of the
    /// connection is actually authenticated. Each says what it checks *and* what it does not.
    var explanation: String {
        switch self {
        case .systemTrust:
            "The certificate must be issued by an authority this device already trusts and must name this machine. A server that presents anything else is refused."
        case .pinnedCertificate:
            "The certificate must be issued by the authority in the file you choose and must name this machine. Nothing else is accepted, including certificates this device would otherwise trust."
        case .pinnedCertificateAuthorityOnly:
            "The certificate must be issued by the authority in the file you choose. Its name is not checked, so another machine holding a certificate from the same authority could take this connection unnoticed. Use this only when the server's certificate does not carry a usable name — a default MySQL or PostgreSQL install is exactly that case."
        }
    }

    /// A short form for a row that has no room for the explanation.
    var shortDescription: String {
        switch self {
        case .systemTrust: "System authorities, server name checked"
        case .pinnedCertificate: "Supplied certificate, server name checked"
        case .pinnedCertificateAuthorityOnly: "Supplied certificate, server name not checked"
        }
    }

    var requiresCertificate: Bool {
        switch self {
        case .systemTrust: false
        case .pinnedCertificate, .pinnedCertificateAuthorityOnly: true
        }
    }

    /// False for exactly one mode, and the UI has to be able to say so without re-deriving it.
    var verifiesServerIdentity: Bool {
        switch self {
        case .systemTrust, .pinnedCertificate: true
        case .pinnedCertificateAuthorityOnly: false
        }
    }
}

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
    /// How the server's certificate is checked when `useTLS` is on. Meaningless when it is off,
    /// and deliberately left at whatever the user last chose rather than reset, so turning TLS
    /// back on restores the mode they picked instead of quietly reverting to another one.
    var tlsVerification: DatabaseTLSVerification
    /// The trust root the two pinned modes verify against: the bytes of the certificate file the
    /// user imported, PEM or DER, carried in the record rather than in GlasSecretStore.
    ///
    /// A CA certificate is public trust metadata, not a secret — it is what the server hands to
    /// every client that connects — and the project rule is to keep metadata out of the secret
    /// store. Inline also means there is no managed file beside the record to lose, to validate
    /// for escape, or to leave behind on delete, which the SQLite import has to do.
    var tlsCertificate: Data?
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
        tlsVerification: DatabaseTLSVerification = .systemTrust,
        tlsCertificate: Data? = nil,
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
        self.tlsVerification = tlsVerification
        self.tlsCertificate = tlsCertificate
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
        case useTLS, tlsVerification, tlsCertificate
        case isFavorite, colorTag, dateAdded, lastConnected, tags
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
        // Absent on every record written before D13 was closed, and system trust is what those
        // records meant. A record whose mode needs a certificate and has none is **not** quietly
        // moved to another mode here: `DatabaseSessionManager.transportPlan` refuses it by name,
        // because silently choosing a different way to verify a server is the thing this whole
        // decision exists to prevent.
        tlsVerification = try values.decodeIfPresent(DatabaseTLSVerification.self, forKey: .tlsVerification) ?? .systemTrust
        tlsCertificate = try values.decodeIfPresent(Data.self, forKey: .tlsCertificate)
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
        try values.encode(tlsVerification, forKey: .tlsVerification)
        try values.encodeIfPresent(tlsCertificate, forKey: .tlsCertificate)
        try values.encode(isFavorite, forKey: .isFavorite)
        try values.encode(colorTag, forKey: .colorTag)
        try values.encode(dateAdded, forKey: .dateAdded)
        try values.encodeIfPresent(lastConnected, forKey: .lastConnected)
        try values.encode(tags, forKey: .tags)
    }

    /// The grid's own page-size control accepts 1 through 10,000; a per-service override
    /// obeys the same bounds.
    static func clampedRowPageSize(_ value: Int) -> Int { min(max(value, 1), 10_000) }

    /// A certificate file is a few hundred bytes to a few kilobytes; a chain of them is still
    /// well inside this. Enforced at import and again here, because the record can also arrive
    /// from a hand-edited defaults plist.
    static let maximumTLSCertificateBytes = 64 * 1024

    /// The trust root as the engine takes it, or nil when this service has none.
    ///
    /// PEM and DER are told apart by content, not by the file's extension: a `.crt` may hold
    /// either, and guessing from the name would hand DER bytes to the PEM parser.
    var tlsCertificateMaterial: DatabaseTLSCertificate? {
        guard let tlsCertificate, !tlsCertificate.isEmpty,
              tlsCertificate.count <= Self.maximumTLSCertificateBytes else { return nil }
        return DatabaseTLSCertificate(bytes: tlsCertificate, format: Self.certificateFormat(of: tlsCertificate))
    }

    static func certificateFormat(of bytes: Data) -> DatabaseTLSCertificate.Format {
        // PEM is ASCII armour; anything that does not carry the armour header is treated as DER
        // and will be rejected by the parser if it is neither.
        let prefix = bytes.prefix(1024)
        return prefix.range(of: Data("-----BEGIN".utf8)) != nil ? .pem : .der
    }

    /// What this service actually verifies, in one line, for any surface that reports the
    /// transport. Never says "encrypted" without saying what is checked.
    var transportVerificationSummary: String {
        guard engine.supportsTLS else { return "Not encrypted in transit" }
        guard useTLS else { return "Not encrypted" }
        return tlsVerification.shortDescription
    }

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
    /// The predicate's **shape only** — the SQL with its bound placeholders left in, never the
    /// parameters. The optimistic predicate these paths build is the primary key plus every
    /// original column value of the row, so the parameters are a verbatim copy of the user's
    /// record; writing them here would put complete rows into `UserDefaults` in plaintext, in a
    /// store whose whole purpose is to be read back and displayed. The shape still answers which
    /// columns identified the row, whether NULLs took part, and how wide the conflict check was.
    /// It deliberately cannot answer *which* row: a primary key is routinely identifying in
    /// itself, so there is no subset of the parameters that is safely "just the key".
    ///
    /// Optional, so records already written under `glassdb.mutationAudit.v1` still decode.
    let predicate: String?

    init(
        id: UUID = UUID(),
        connectionID: UUID,
        database: String?,
        object: String?,
        normalizedOperation: String,
        source: String,
        timestamp: Date = Date(),
        outcome: MutationOutcome,
        affectedRows: UInt64?,
        predicate: String? = nil
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
        self.predicate = predicate
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
