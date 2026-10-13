//
//  PostgreSQLAdapter.swift
//  GlassDBKit
//
//  postgres-nio wrapper implementing the shared database contracts.
//

import Foundation
import Logging
import NIOCore
import NIOPosix
import NIOSSL
import PostgresNIO

public final class PostgreSQLEngine: DatabaseEngine, @unchecked Sendable {
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let logger = Logger(label: "app.glassdb.postgresql")

    public init() {
        // See MySQLEngine: the singleton group needs no shutdown, so there is no blocking deinit.
        self.eventLoopGroup = MultiThreadedEventLoopGroup.singleton
    }

    public var engineName: String { "PostgreSQL" }
    public var dialect: DatabaseDialect { .postgresql }
    public var capabilities: Set<DatabaseCapability> {
        [
            .transactions, .parameterBinding, .transportTLS, .queryTimeout,
            .metadata, .schemas, .indexes, .foreignKeys, .explain,
            .serverVersion, .cancellation, .tableStatistics,
            .aggregateTableStatistics, .truncateTable,
        ]
    }

    public func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String?,
        tlsPolicy: DatabaseTLSPolicy
    ) async throws -> any DatabaseConnection {
        let (tls, serverName) = try Self.makeTLS(policy: tlsPolicy, connectionHost: host)
        var configuration = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: tls
        )
        configuration.options.tlsServerName = serverName
        let connection: PostgresConnection
        do {
            connection = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: configuration,
                id: 1,
                logger: logger
            )
        } catch let error as PSQLError {
            throw Self.connectFailure(error, host: host, port: port)
        }
        return PostgreSQLDatabaseConnection(connection: connection, logger: logger)
    }

    /// What `connect` throws, in a form the app can word. PostgresNIO keeps a `PSQLError`'s
    /// details out of its description on purpose, so every failure to connect reached the user as
    /// "The operation couldn't be completed. (PostgresNIO.PSQLError error 1.)" — a wrong password
    /// included (measured 2026-10-13 against the test VM; queries go through the older API, whose
    /// `PostgresError` reads well). The server's refusal becomes its own words. A failure to reach
    /// it becomes the error underneath, unwrapped from NIO's connection error to the one MySQLNIO
    /// throws for the same failure (an `IOError`, or the unknown host), so both engines are worded
    /// alike.
    static func connectFailure(_ error: PSQLError, host: String, port: Int) -> any Error {
        switch error.code {
        case .server:
            if let message = error.serverInfo?[.message] { return DatabaseError.server(message) }
        case .connectionError:
            guard let underlying = error.underlying else { break }
            guard let connection = underlying as? NIOConnectionError else { return underlying }
            if let lookup = connection.dnsAError ?? connection.dnsAAAAError { return lookup }
            return connection.connectionErrors.first?.error ?? connection
        case .sslUnsupported:
            return DatabaseError.tlsRequiredButUnavailable(host: host, port: port)
        default:
            break
        }
        return error
    }

    /// Delegates to the one policy-to-NIOSSL mapping in `DatabaseTLSConfiguration.swift`, shared
    /// with the MySQL adapter so the two engines cannot drift on what a policy verifies. The only
    /// PostgreSQL-specific part is the wrapping: `.disable` versus `.require(NIOSSLContext)`.
    private static func makeTLS(
        policy: DatabaseTLSPolicy,
        connectionHost: String
    ) throws -> (PostgresConnection.Configuration.TLS, String?) {
        let (configuration, serverName) = try policy.makeTLSConfiguration(connectionHost: connectionHost)
        guard let configuration else { return (.disable, nil) }
        return (.require(try NIOSSLContext(configuration: configuration)), serverName)
    }

}

actor PostgreSQLDatabaseConnection: DatabaseConnection {
    nonisolated let engineName = "PostgreSQL"
    nonisolated let dialect: DatabaseDialect = .postgresql
    nonisolated let capabilities: Set<DatabaseCapability> = [
        .transactions, .parameterBinding, .transportTLS, .queryTimeout,
        .metadata, .schemas, .indexes, .foreignKeys, .explain,
        .serverVersion, .cancellation, .tableStatistics,
        .aggregateTableStatistics, .truncateTable,
    ]
    nonisolated let identifierQuoteCharacter: Character = "\""

    private let connection: PostgresConnection
    private let logger: Logger

    init(connection: PostgresConnection, logger: Logger) {
        self.connection = connection
        self.logger = logger
    }

    var isConnected: Bool { !connection.isClosed }

    func execute(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        try await performQuery(query, parameters: parameters)
    }

    func execute(
        _ query: String,
        parameters: [DatabaseValue],
        timeout: Duration?
    ) async throws -> QueryResult {
        guard let timeout else {
            return try await performQuery(query, parameters: parameters)
        }
        let milliseconds = Self.timeoutMilliseconds(timeout)
        guard milliseconds > 0 else { throw DatabaseError.queryTimedOut }

        _ = try await performQuery(
            "SELECT set_config('statement_timeout', $1, false)",
            parameters: [.string("\(milliseconds)ms")]
        )
        do {
            let result = try await performQuery(query, parameters: parameters)
            _ = try? await performQuery(
                "SELECT set_config('statement_timeout', '0', false)",
                parameters: []
            )
            return result
        } catch let error as PSQLError {
            _ = try? await performQuery(
                "SELECT set_config('statement_timeout', '0', false)",
                parameters: []
            )
            if error.serverInfo?[.sqlState] == "57014" {
                throw DatabaseError.queryTimedOut
            }
            throw error
        } catch let error as PostgresError {
            _ = try? await performQuery(
                "SELECT set_config('statement_timeout', '0', false)",
                parameters: []
            )
            if case .server(let serverError) = error,
               serverError.fields[.sqlState] == "57014" {
                throw DatabaseError.queryTimedOut
            }
            throw error
        } catch {
            _ = try? await performQuery(
                "SELECT set_config('statement_timeout', '0', false)",
                parameters: []
            )
            throw error
        }
    }

    func cancelCurrentQuery() async throws {
        // postgres-nio 1.33 does not expose PostgreSQL's cancel-request packet
        // for a live query on a direct connection. Closing the transport is an
        // abortive cancellation and intentionally disconnects this session.
        try await connection.close()
    }

    func beginTransaction() async throws {
        _ = try await performQuery("BEGIN", parameters: [])
    }

    func commitTransaction() async throws {
        _ = try await performQuery("COMMIT", parameters: [])
    }

    func rollbackTransaction() async throws {
        _ = try await performQuery("ROLLBACK", parameters: [])
    }

    func close() async throws {
        try await connection.close()
    }

    /// PostgreSQL schemas are returned here because the existing browser contract
    /// models the namespace containing tables. PostgreSQL databases require a new
    /// connection and cannot be switched in-session.
    func databases() async throws -> [String] {
        try await stringColumn(
            """
            SELECT schema_name
            FROM information_schema.schemata
            WHERE schema_name <> 'information_schema'
              AND schema_name NOT LIKE 'pg_%'
            ORDER BY schema_name
            """
        )
    }

    func tables(in database: String) async throws -> [String] {
        try await stringColumn(
            """
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = $1
              AND table_type IN ('BASE TABLE', 'VIEW', 'FOREIGN')
            ORDER BY table_name
            """,
            parameters: [.string(database)]
        )
    }

    func columns(in table: String, database: String) async throws -> [ColumnInfo] {
        let result = try await performQuery(
            """
            SELECT c.column_name, c.data_type, c.is_nullable, c.ordinal_position,
                   c.column_default, c.is_generated,
                   EXISTS (
                       SELECT 1
                       FROM information_schema.table_constraints tc
                       JOIN information_schema.key_column_usage kcu
                         ON tc.constraint_name = kcu.constraint_name
                        AND tc.constraint_schema = kcu.constraint_schema
                       WHERE tc.constraint_type = 'PRIMARY KEY'
                         AND tc.table_schema = c.table_schema
                         AND tc.table_name = c.table_name
                         AND kcu.column_name = c.column_name
                   ) AS is_primary_key
            FROM information_schema.columns c
            WHERE c.table_schema = $1 AND c.table_name = $2
            ORDER BY c.ordinal_position
            """,
            parameters: [.string(database), .string(table)]
        )
        return result.rows.map { row in
            ColumnInfo(
                name: row[safe: 0]?.displayString ?? "",
                type: row[safe: 1]?.displayString ?? "unknown",
                isNullable: row[safe: 2]?.displayString == "YES",
                isPrimaryKey: row[safe: 6] == .bool(true),
                ordinalPosition: Int(row[safe: 3]?.displayString ?? "0") ?? 0,
                sourceSchema: database,
                sourceTable: table,
                defaultValue: row[safe: 4].flatMap { $0.isNull ? nil : $0.displayString },
                isGenerated: row[safe: 5]?.displayString != "NEVER"
            )
        }
    }

    func showCreateTable(_ table: String, database: String) async throws -> String {
        throw DatabaseError.unsupportedCapability(.createTableDefinition, engine: engineName)
    }

    func indexes(in table: String, database: String) async throws -> [IndexInfo] {
        let result = try await performQuery(
            """
            SELECT index_class.relname, attribute.attname, index.indisunique,
                   access_method.amname, ordinality.ordinality, index.indisprimary
            FROM pg_catalog.pg_class table_class
            JOIN pg_catalog.pg_namespace namespace
              ON namespace.oid = table_class.relnamespace
            JOIN pg_catalog.pg_index index ON index.indrelid = table_class.oid
            JOIN pg_catalog.pg_class index_class ON index_class.oid = index.indexrelid
            JOIN pg_catalog.pg_am access_method ON access_method.oid = index_class.relam
            JOIN LATERAL unnest(index.indkey) WITH ORDINALITY AS ordinality(attnum, ordinality)
              ON true
            LEFT JOIN pg_catalog.pg_attribute attribute
              ON attribute.attrelid = table_class.oid
             AND attribute.attnum = ordinality.attnum
            WHERE namespace.nspname = $1 AND table_class.relname = $2
            ORDER BY index_class.relname, ordinality.ordinality
            """,
            parameters: [.string(database), .string(table)]
        )
        return result.rows.map { row in
            IndexInfo(
                name: row[safe: 0]?.displayString ?? "",
                columnName: row[safe: 1]?.displayString ?? "<expression>",
                isUnique: row[safe: 2] == .bool(true),
                isPrimary: row[safe: 5] == .bool(true),
                type: row[safe: 3]?.displayString ?? "",
                sequenceInIndex: Int(row[safe: 4]?.displayString ?? "0") ?? 0
            )
        }
    }

    /// Reads `pg_catalog` rather than `information_schema`. The previous query was wrong in **two
    /// independent ways**, and anyone "simplifying" this back to `information_schema` reintroduces
    /// both. Keep the positional join.
    ///
    /// 1. **Privileges.** PostgreSQL restricts `information_schema.constraint_column_usage` to the
    ///    table's owner — its definition is `WHERE pg_has_role(tblowner, 'USAGE')`, with no
    ///    privilege branch, so granting SELECT is not enough. The inner join therefore returned
    ///    nothing for any non-owning account and the Foreign Keys tab rendered empty,
    ///    indistinguishable from a table with no keys, for exactly the least-privilege accounts a
    ///    careful user connects with. (By contrast `information_schema.schemata`, `tables` and
    ///    `columns` are fine here: they carry `has_*_privilege` branches. Verified against a live
    ///    server as a non-owning account, not assumed.)
    /// 2. **Composite keys were a cross product.** The referenced columns were joined with no
    ///    ordinal correlation, so a two-column key `(x, y) → (a, b)` yielded four rows —
    ///    `x→a, x→b, y→a, y→b` — asserting relationships that do not exist. This one is worse than
    ///    the first: empty is unhelpful, but confidently wrong sends foreign-key navigation to the
    ///    wrong column. Reproduced on a table the account **owned**, so privileges were not the
    ///    cause. `conkey` and `confkey` are positionally paired arrays; unnesting one
    ///    `WITH ORDINALITY` and indexing the other by that ordinal is what actually pairs them.
    ///
    /// Both found by the live integration run, not by reading. `tableStatus` below already reads
    /// `pg_catalog`, so this is house-consistent rather than novel.
    func foreignKeys(in table: String, database: String) async throws -> [ForeignKeyInfo] {
        let result = try await performQuery(
            """
            SELECT con.conname, att.attname, ref_class.relname, ref_att.attname, ord.n
            FROM pg_catalog.pg_constraint con
            JOIN pg_catalog.pg_class rel ON rel.oid = con.conrelid
            JOIN pg_catalog.pg_namespace ns ON ns.oid = rel.relnamespace
            JOIN LATERAL unnest(con.conkey) WITH ORDINALITY AS ord(attnum, n) ON true
            JOIN pg_catalog.pg_attribute att
              ON att.attrelid = con.conrelid AND att.attnum = ord.attnum
            JOIN pg_catalog.pg_class ref_class ON ref_class.oid = con.confrelid
            JOIN pg_catalog.pg_attribute ref_att
              ON ref_att.attrelid = con.confrelid AND ref_att.attnum = con.confkey[ord.n]
            WHERE con.contype = 'f' AND ns.nspname = $1 AND rel.relname = $2
            ORDER BY con.conname, ord.n
            """,
            parameters: [.string(database), .string(table)]
        )
        return result.rows.map { row in
            ForeignKeyInfo(
                constraintName: row[safe: 0]?.displayString ?? "",
                columnName: row[safe: 1]?.displayString ?? "",
                referencedTable: row[safe: 2]?.displayString ?? "",
                referencedColumn: row[safe: 3]?.displayString ?? "",
                ordinalPosition: Int(row[safe: 4]?.displayString ?? "0") ?? 0
            )
        }
    }

    func tableStatus(in database: String) async throws -> [TableStatus] {
        let result = try await performQuery(
            """
            SELECT table_class.relname,
                   GREATEST(COALESCE(stats.n_live_tup, table_class.reltuples), 0)::bigint,
                   pg_total_relation_size(table_class.oid),
                   GREATEST(stats.last_analyze, stats.last_autoanalyze),
                   stats.n_mod_since_analyze
            FROM pg_catalog.pg_class table_class
            JOIN pg_catalog.pg_namespace namespace
              ON namespace.oid = table_class.relnamespace
            LEFT JOIN pg_catalog.pg_stat_user_tables stats
              ON stats.relid = table_class.oid
            WHERE namespace.nspname = $1
              AND table_class.relkind IN ('r', 'p')
            ORDER BY table_class.relname
            """,
            parameters: [.string(database)]
        )
        return result.rows.map { Self.tableStatus(from: $0, startingAt: 0) }
    }

    /// One pass over every user schema in the current database, mirroring the
    /// per-schema query above and the schema filter used by databases().
    static let aggregateTableStatusQuery = """
        SELECT namespace.nspname,
               table_class.relname,
               GREATEST(COALESCE(stats.n_live_tup, table_class.reltuples), 0)::bigint,
               pg_total_relation_size(table_class.oid),
               GREATEST(stats.last_analyze, stats.last_autoanalyze),
               stats.n_mod_since_analyze
        FROM pg_catalog.pg_class table_class
        JOIN pg_catalog.pg_namespace namespace
          ON namespace.oid = table_class.relnamespace
        LEFT JOIN pg_catalog.pg_stat_user_tables stats
          ON stats.relid = table_class.oid
        WHERE namespace.nspname <> 'information_schema'
          AND namespace.nspname NOT LIKE 'pg_%'
          AND table_class.relkind IN ('r', 'p')
        ORDER BY namespace.nspname, table_class.relname
        """

    func tableStatusByNamespace() async throws -> [String: [TableStatus]] {
        let result = try await performQuery(Self.aggregateTableStatusQuery, parameters: [])
        var grouped: [String: [TableStatus]] = [:]
        for row in result.rows {
            guard let schema = row[safe: 0]?.displayString, !schema.isEmpty else { continue }
            grouped[schema, default: []].append(Self.tableStatus(from: row, startingAt: 1))
        }
        return grouped
    }

    /// Shared mapping for the per-schema and aggregate statistics queries. The
    /// aggregate query prepends the schema name, so its rows map from offset 1.
    /// Internal (not private) so tests can pin the offset-based contract.
    static func tableStatus(from row: [DatabaseValue], startingAt offset: Int) -> TableStatus {
        let statisticsUpdatedAt: Date? = if case .date(let value)? = row[safe: offset + 3] {
            value
        } else {
            nil
        }
        return TableStatus(
            name: row[safe: offset]?.displayString ?? "",
            engine: "PostgreSQL",
            rowCount: Int(row[safe: offset + 1]?.displayString ?? "0") ?? 0,
            dataLength: Int(row[safe: offset + 2]?.displayString ?? "0") ?? 0,
            collation: nil,
            rowCountAccuracy: .estimated,
            statisticsUpdatedAt: statisticsUpdatedAt,
            modifiedRowsSinceAnalysis: Int(row[safe: offset + 4]?.displayString ?? "")
        )
    }

    func rowCount(table: String, database: String) async throws -> Int {
        try await rowCount(table: table, database: database, timeout: nil)
    }

    func rowCount(table: String, database: String, timeout: Duration?) async throws -> Int {
        let result = try await execute(
            "SELECT COUNT(*) FROM \(quotedIdentifier(database)).\(quotedIdentifier(table))",
            parameters: [],
            timeout: timeout
        )
        guard let value = result.rows.first?.first,
              let count = Int(value.displayString) else {
            throw DatabaseError.unexpectedResult("PostgreSQL did not return a row count.")
        }
        return count
    }

    func serverVersion() async throws -> String {
        let result = try await performQuery("SHOW server_version", parameters: [])
        guard let version = result.rows.first?.first?.displayString else {
            throw DatabaseError.unexpectedResult("PostgreSQL did not return a server version.")
        }
        return version
    }

    func explain(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        try await performQuery("EXPLAIN (FORMAT JSON) \(query)", parameters: parameters)
    }

    private func stringColumn(
        _ query: String,
        parameters: [DatabaseValue] = []
    ) async throws -> [String] {
        try await performQuery(query, parameters: parameters).rows.compactMap {
            $0.first?.displayString
        }
    }

    private func performQuery(
        _ query: String,
        parameters: [DatabaseValue]
    ) async throws -> QueryResult {
        let start = ContinuousClock.now
        let binds = try parameters.map(Self.postgresData(for:))
        let future: EventLoopFuture<PostgresQueryResult> = connection.query(query, binds)
        let postgresResult = try await future.get()
        let elapsed = ContinuousClock.now - start

        let columns: [ColumnInfo]
        if let first = postgresResult.rows.first {
            columns = first.enumerated().map { index, cell in
                ColumnInfo(
                    name: cell.columnName,
                    type: cell.dataType.description,
                    ordinalPosition: index,
                    length: nil
                )
            }
        } else {
            columns = []
        }
        let rows = postgresResult.rows.map { row in
            row.map(Self.databaseValue(for:))
        }
        return QueryResult(
            query: query,
            columns: columns,
            rows: rows,
            affectedRows: postgresResult.metadata.rows.flatMap { $0 >= 0 ? UInt64($0) : nil },
            executionTime: Self.seconds(elapsed)
        )
    }

    static func postgresData(for value: DatabaseValue) throws -> PostgresData {
        switch value {
        case .string(let value):
            return PostgresData(string: value)
        case .int(let value):
            return PostgresData(int64: value)
        case .uint(let value):
            guard value <= UInt64(Int64.max) else {
                throw DatabaseError.unsupportedParameter(
                    "PostgreSQL has no unsigned 64-bit integer type; \(value) exceeds INT8."
                )
            }
            return PostgresData(int64: Int64(value))
        case .decimal(let value):
            guard let numeric = PostgresNumeric(string: value) else {
                throw DatabaseError.unsupportedParameter("\"\(value)\" is not a base-10 decimal.")
            }
            return PostgresData(numeric: numeric)
        case .double(let value):
            return PostgresData(double: value)
        case .data(let value), .bit(let value):
            var buffer = ByteBufferAllocator().buffer(capacity: value.count)
            buffer.writeBytes(value)
            return PostgresData(type: .bytea, value: buffer)
        case .json(let value):
            guard (try? JSONSerialization.jsonObject(with: Data(value.utf8))) != nil else {
                throw DatabaseError.unsupportedParameter("The JSON value is not valid JSON text.")
            }
            return PostgresData(jsonb: Data(value.utf8))
        case .temporal(let value):
            return PostgresData(string: value.rawValue)
        case .null:
            return .null
        case .date(let value):
            return PostgresData(date: value)
        case .bool(let value):
            return PostgresData(bool: value)
        }
    }

    static func databaseValue(for cell: PostgresCell) -> DatabaseValue {
        let data = PostgresData(
            type: cell.dataType,
            formatCode: cell.format,
            value: cell.bytes
        )
        guard data.value != nil else { return .null }
        switch cell.dataType {
        case .bool:
            return data.bool.map(DatabaseValue.bool) ?? rawValue(data)
        case .int2, .int4, .int8:
            return data.int64.map(DatabaseValue.int) ?? rawValue(data)
        case .oid:
            return data.int64.flatMap { $0 >= 0 ? DatabaseValue.uint(UInt64($0)) : nil }
                ?? rawValue(data)
        case .numeric:
            return data.numeric.map { .decimal($0.string) } ?? rawValue(data)
        case .float4, .float8:
            return data.double.map(DatabaseValue.double) ?? rawValue(data)
        case .bytea:
            return data.value.map { .data(Data($0.readableBytesView)) } ?? .null
        case .json:
            return data.json.map { .json(String(decoding: $0, as: UTF8.self)) } ?? rawValue(data)
        case .jsonb:
            return data.jsonb.map { .json(String(decoding: $0, as: UTF8.self)) } ?? rawValue(data)
        case .date:
            return data.string.map {
                .temporal(.init(rawValue: $0, kind: .date))
            } ?? rawValue(data)
        case .timestamp, .timestamptz:
            return data.date.map(DatabaseValue.date) ?? rawValue(data)
        default:
            return data.string.map(DatabaseValue.string) ?? rawValue(data)
        }
    }

    private static func rawValue(_ data: PostgresData) -> DatabaseValue {
        guard let buffer = data.value else { return .null }
        if data.formatCode == .text {
            return .string(String(decoding: buffer.readableBytesView, as: UTF8.self))
        }
        return .data(Data(buffer.readableBytesView))
    }

    private static func timeoutMilliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        let seconds = components.seconds.multipliedReportingOverflow(by: 1_000)
        guard !seconds.overflow else { return Int64.max }
        let subsecond = components.attoseconds / 1_000_000_000_000_000
        return max(0, seconds.partialValue + subsecond)
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
