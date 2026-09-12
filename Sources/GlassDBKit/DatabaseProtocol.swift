//
//  DatabaseProtocol.swift
//  GlassDBKit
//
//  Protocol abstraction for database engines (MySQL, PostgreSQL, etc.)
//

import Foundation

public enum DatabaseError: Error, LocalizedError {
    case unexpectedResult(String)
    case invalidTLSCertificate(String)
    case tlsRequiredButUnavailable(host: String, port: Int)
    case unsupportedParameter(String)
    case unsupportedCapability(DatabaseCapability, engine: String)
    case queryTimedOut

    public var errorDescription: String? {
        switch self {
        case .unexpectedResult(let message): return message
        case .invalidTLSCertificate(let message):
            return "The configured TLS certificate is invalid: \(message)"
        case .tlsRequiredButUnavailable(let host, let port):
            return "TLS is required, but \(host):\(port) did not negotiate an encrypted connection."
        case .unsupportedParameter(let message):
            return "The database parameter cannot be bound: \(message)"
        case .unsupportedCapability(let capability, let engine):
            return "\(engine) does not support the \(capability.rawValue) capability."
        case .queryTimedOut:
            return "The database query exceeded its configured timeout."
        }
    }
}

/// Features are advertised per connection so the UI can hide or explain
/// engine-specific operations instead of discovering unsupported behavior late.
public enum DatabaseCapability: String, Sendable, Hashable, CaseIterable {
    case transactions
    case parameterBinding
    case transportTLS
    case queryTimeout
    case cancellation
    case metadata
    case schemas
    case indexes
    case foreignKeys
    case tableStatistics
    case aggregateTableStatistics
    case createTableDefinition
    case explain
    case serverVersion
    case truncateTable
}

public enum DatabaseDialect: String, Sendable, Hashable {
    case mysql
    case postgresql
    case sqlite
}

/// Certificate material used as an explicit trust root for a database connection.
public struct DatabaseTLSCertificate: Sendable, Hashable {
    public enum Format: Sendable, Hashable {
        case pem
        case der
    }

    public let bytes: Data
    public let format: Format

    public init(bytes: Data, format: Format) {
        self.bytes = bytes
        self.format = format
    }
}

/// The transport policy for a database connection. Both required modes fail closed
/// when the server cannot negotiate TLS; they never fall back to plaintext.
public enum DatabaseTLSPolicy: Sendable, Hashable {
    case disabled
    case requiredSystemTrust
    /// System trust with an explicit certificate name, used when the socket is
    /// connected through a local SSH tunnel.
    case requiredSystemTrustForHost(String)
    case requiredCertificates([DatabaseTLSCertificate], serverName: String? = nil)

    public var isRequired: Bool {
        switch self {
        case .disabled: false
        case .requiredSystemTrust, .requiredSystemTrustForHost, .requiredCertificates: true
        }
    }
}

public protocol DatabaseEngine: Sendable {
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String?,
        tlsPolicy: DatabaseTLSPolicy
    ) async throws -> any DatabaseConnection

    var engineName: String { get }
    var capabilities: Set<DatabaseCapability> { get }
    var dialect: DatabaseDialect { get }
}

public protocol DatabaseConnection: Sendable {
    var isConnected: Bool { get async }
    var engineName: String { get }
    var capabilities: Set<DatabaseCapability> { get }
    var identifierQuoteCharacter: Character { get }
    var dialect: DatabaseDialect { get }

    func execute(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult
    func execute(
        _ query: String,
        parameters: [DatabaseValue],
        timeout: Duration?
    ) async throws -> QueryResult
    func cancelCurrentQuery() async throws
    func beginTransaction() async throws
    func commitTransaction() async throws
    func rollbackTransaction() async throws
    func close() async throws

    func databases() async throws -> [String]
    func tables(in database: String) async throws -> [String]
    func columns(in table: String, database: String) async throws -> [ColumnInfo]
    func showCreateTable(_ table: String, database: String) async throws -> String
    func indexes(in table: String, database: String) async throws -> [IndexInfo]
    func foreignKeys(in table: String, database: String) async throws -> [ForeignKeyInfo]
    func tableStatus(in database: String) async throws -> [TableStatus]
    func tableStatusByNamespace() async throws -> [String: [TableStatus]]
    func rowCount(table: String, database: String) async throws -> Int
    func rowCount(table: String, database: String, timeout: Duration?) async throws -> Int
    func serverVersion() async throws -> String
    func explain(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult
}

public extension DatabaseEngine {
    var capabilities: Set<DatabaseCapability> { [] }
    var dialect: DatabaseDialect { .mysql }

    /// Compatibility overload for callers that explicitly want an unencrypted connection.
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String?
    ) async throws -> any DatabaseConnection {
        try await connect(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tlsPolicy: .disabled
        )
    }
}

public extension DatabaseConnection {
    var engineName: String { "Database" }
    var capabilities: Set<DatabaseCapability> { [] }
    var identifierQuoteCharacter: Character { "`" }
    var dialect: DatabaseDialect { .mysql }

    func parameterPlaceholder(at position: Int) -> String {
        switch dialect {
        case .postgresql: "$\(position)"
        case .mysql, .sqlite: "?"
        }
    }

    func execute(_ query: String) async throws -> QueryResult {
        try await execute(query, parameters: [])
    }

    func execute(
        _ query: String,
        parameters: [DatabaseValue],
        timeout: Duration?
    ) async throws -> QueryResult {
        guard timeout == nil else {
            throw DatabaseError.unsupportedCapability(.queryTimeout, engine: engineName)
        }
        return try await execute(query, parameters: parameters)
    }

    func cancelCurrentQuery() async throws {
        throw DatabaseError.unsupportedCapability(.cancellation, engine: engineName)
    }

    func beginTransaction() async throws {
        _ = try await execute("START TRANSACTION", parameters: [])
    }

    func commitTransaction() async throws {
        _ = try await execute("COMMIT", parameters: [])
    }

    func rollbackTransaction() async throws {
        _ = try await execute("ROLLBACK", parameters: [])
    }

    func serverVersion() async throws -> String {
        throw DatabaseError.unsupportedCapability(.serverVersion, engine: engineName)
    }

    /// Per-table statistics for every namespace on the server in one round
    /// trip, keyed by database (MySQL) or schema (PostgreSQL). Namespaces with
    /// no tables yield no key; callers treat missing keys as empty. Only
    /// engines advertising `.aggregateTableStatistics` implement this.
    func tableStatusByNamespace() async throws -> [String: [TableStatus]] {
        throw DatabaseError.unsupportedCapability(.aggregateTableStatistics, engine: engineName)
    }

    func explain(_ query: String, parameters: [DatabaseValue] = []) async throws -> QueryResult {
        throw DatabaseError.unsupportedCapability(.explain, engine: engineName)
    }

    func rowCount(table: String, database: String, timeout: Duration?) async throws -> Int {
        guard timeout == nil else {
            throw DatabaseError.unsupportedCapability(.queryTimeout, engine: engineName)
        }
        return try await rowCount(table: table, database: database)
    }

    /// Quotes one logical identifier. Dotted paths must be quoted component by
    /// component so a caller cannot accidentally turn input into SQL syntax.
    func quotedIdentifier(_ identifier: String) -> String {
        let quote = String(identifierQuoteCharacter)
        return "\(quote)\(identifier.replacingOccurrences(of: quote, with: quote + quote))\(quote)"
    }
}
