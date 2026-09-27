//
//  MySQLAdapter.swift
//  GlassDBKit
//
//  mysql-nio wrapper implementing DatabaseProtocol
//

import Foundation
import MySQLNIO
import NIOCore
import NIOPosix
import NIOSSL
import Logging

public final class MySQLEngine: DatabaseEngine, @unchecked Sendable {
    private let eventLoopGroup: any EventLoopGroup

    public init() {
        // The process-wide singleton: never shut down, so releasing an engine cannot block a
        // thread. A per-engine group had to be torn down in `deinit`, synchronously.
        self.eventLoopGroup = MultiThreadedEventLoopGroup.singleton
    }

    public var engineName: String { "MySQL" }
    public var capabilities: Set<DatabaseCapability> {
        [
            .transactions, .parameterBinding, .transportTLS, .metadata,
            .indexes, .foreignKeys, .tableStatistics, .aggregateTableStatistics,
            .createTableDefinition, .explain, .serverVersion, .queryTimeout,
            .cancellation, .truncateTable,
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
        let (tlsConfiguration, serverHostname) = try Self.makeTLSConfiguration(
            policy: tlsPolicy,
            connectionHost: host
        )
        if tlsPolicy.isRequired {
            guard try await serverAdvertisesTLS(host: host, port: port) else {
                throw DatabaseError.tlsRequiredButUnavailable(host: host, port: port)
            }
        }
        let connection = try await MySQLConnection.connect(
            to: .makeAddressResolvingHost(host, port: port),
            username: username,
            database: database ?? "",
            password: password,
            tlsConfiguration: tlsConfiguration,
            serverHostname: serverHostname,
            on: eventLoopGroup.next()
        ).get()

        if tlsPolicy.isRequired {
            let tlsActive = try await connection.channel.eventLoop.submit {
                (try? connection.channel.pipeline.syncOperations.context(
                    handlerType: NIOSSLClientHandler.self
                )) != nil
            }.get()
            guard tlsActive else {
                try? await connection.close().get()
                throw DatabaseError.tlsRequiredButUnavailable(host: host, port: port)
            }
        }

        return MySQLDatabaseConnection(connection: connection)
    }

    /// Reads only the unauthenticated MySQL greeting. This prevents mysql-nio's
    /// opportunistic TLS behavior from ever sending an authentication response
    /// when a required-TLS server does not advertise CLIENT_SSL.
    private func serverAdvertisesTLS(host: String, port: Int) async throws -> Bool {
        let eventLoop = eventLoopGroup.next()
        let probe = MySQLTLSCapabilityProbe(eventLoop: eventLoop)
        let channel = try await ClientBootstrap(group: eventLoop)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHandler(probe)
            }
            .connect(host: host, port: port)
            .get()
        let timeout = eventLoop.scheduleTask(in: .seconds(10)) {
            probe.fail(DatabaseError.unexpectedResult("Timed out waiting for the MySQL server greeting."))
        }
        defer {
            timeout.cancel()
            if channel.isActive { channel.close(promise: nil) }
        }
        return try await probe.result.get()
    }

    /// Delegates to the one policy-to-NIOSSL mapping in `DatabaseTLSConfiguration.swift`, shared
    /// with the PostgreSQL adapter so the two engines cannot drift on what a policy verifies.
    private static func makeTLSConfiguration(
        policy: DatabaseTLSPolicy,
        connectionHost: String
    ) throws -> (TLSConfiguration?, String?) {
        try policy.makeTLSConfiguration(connectionHost: connectionHost)
    }

}

final class MySQLTLSCapabilityProbe: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    let result: EventLoopFuture<Bool>
    private let promise: EventLoopPromise<Bool>
    private var buffer = ByteBufferAllocator().buffer(capacity: 256)
    private var isComplete = false

    init(eventLoop: EventLoop) {
        let promise = eventLoop.makePromise(of: Bool.self)
        self.promise = promise
        self.result = promise.futureResult
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        buffer.writeBuffer(&incoming)
        guard buffer.readableBytes >= 4,
              let length0 = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self),
              let length1 = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self),
              let length2 = buffer.getInteger(at: buffer.readerIndex + 2, as: UInt8.self) else {
            return
        }
        let payloadLength = Int(length0) | (Int(length1) << 8) | (Int(length2) << 16)
        guard buffer.readableBytes >= payloadLength + 4,
              let payload = buffer.getBytes(at: buffer.readerIndex + 4, length: payloadLength) else {
            return
        }
        complete(Self.serverSupportsTLS(in: payload))
        context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !isComplete {
            fail(DatabaseError.unexpectedResult("The MySQL server closed before sending its greeting."))
        }
    }

    func fail(_ error: Error) {
        guard !isComplete else { return }
        isComplete = true
        promise.fail(error)
    }

    private func complete(_ supportsTLS: Bool) {
        guard !isComplete else { return }
        isComplete = true
        promise.succeed(supportsTLS)
    }

    static func serverSupportsTLS(in greeting: [UInt8]) -> Bool {
        guard greeting.first == 10 else { return false }
        var index = 1
        guard let terminator = greeting[index...].firstIndex(of: 0) else { return false }
        index = terminator + 1
        // connection id (4), auth-plugin-data-part-1 (8), filler (1), lower capabilities (2)
        index += 4 + 8 + 1
        guard greeting.count >= index + 2 else { return false }
        let lowerCapabilities = UInt16(greeting[index]) | (UInt16(greeting[index + 1]) << 8)
        let clientSSL: UInt16 = 0x0800
        return lowerCapabilities & clientSSL != 0
    }
}

final class MySQLDatabaseConnection: DatabaseConnection, @unchecked Sendable {
    private let connection: MySQLConnection

    init(connection: MySQLConnection) {
        self.connection = connection
    }

    var engineName: String { "MySQL" }
    var capabilities: Set<DatabaseCapability> {
        [
            .transactions, .parameterBinding, .transportTLS, .metadata,
            .indexes, .foreignKeys, .tableStatistics, .aggregateTableStatistics,
            .createTableDefinition, .explain, .serverVersion, .queryTimeout,
            .cancellation, .truncateTable,
        ]
    }

    var isConnected: Bool {
        get async {
            connection.channel.isActive
        }
    }

    func serverVersion() async throws -> String {
        let result = try await execute("SELECT VERSION()", parameters: [])
        guard let version = result.rows.first?.first?.displayString else {
            throw DatabaseError.unexpectedResult("MySQL did not return a server version.")
        }
        return version
    }

    func explain(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        try await execute("EXPLAIN FORMAT=JSON \(query)", parameters: parameters)
    }

    func execute(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        let start = ContinuousClock.now

        // MySQL rejects utility commands (USE, SET, SHOW, DESCRIBE, etc.)
        // in the prepared statement protocol. Route them through simpleQuery.
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows: [MySQLRow]
        var metadata: MySQLQueryMetadata?
        if Self.shouldUseTextProtocol(trimmed, parameters: parameters) {
            rows = try await connection.simpleQuery(trimmed).get()
        } else {
            let binds = try parameters.map(Self.mysqlData(for:))
            rows = try await connection.query(trimmed, binds) { queryMetadata in
                metadata = queryMetadata
            }.get()
        }

        let elapsed = ContinuousClock.now - start
        let components = elapsed.components
        let executionTime = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000.0
        // mysql-nio does not expose warning metadata for COM_QUERY. Read the
        // per-session diagnostics immediately, before any other user statement.
        let executionStatus = try? await currentExecutionStatus()

        var columns: [ColumnInfo] = []
        var resultRows: [[DatabaseValue]] = []

        if let firstRow = rows.first {
            columns = firstRow.columnDefinitions.enumerated().map { index, col in
                ColumnInfo(
                    name: col.name,
                    type: mysqlTypeName(col.columnType),
                    isNullable: !col.flags.contains(.COLUMN_NOT_NULL),
                    isPrimaryKey: col.flags.contains(.PRIMARY_KEY),
                    ordinalPosition: index,
                    isUnsigned: col.flags.contains(.COLUMN_UNSIGNED),
                    characterSetID: col.characterSet.rawValue,
                    sourceSchema: col.schema.isEmpty ? nil : col.schema,
                    sourceTable: col.orgTable.isEmpty ? nil : col.orgTable,
                    sourceColumn: col.orgName.isEmpty ? nil : col.orgName,
                    length: col.columnLength,
                    decimals: col.decimals
                )
            }
        }

        for row in rows {
            let values = zip(row.columnDefinitions, row.values).map { column, buffer in
                Self.decodeValue(
                    MySQLData(
                        type: column.columnType,
                        format: row.format,
                        buffer: buffer,
                        isUnsigned: column.flags.contains(.COLUMN_UNSIGNED)
                    ),
                    column: column
                )
            }
            resultRows.append(values)
        }

        return QueryResult(
            query: query,
            columns: columns,
            rows: resultRows,
            affectedRows: metadata?.affectedRows
                ?? (Self.reportsAffectedRows(trimmed) ? executionStatus?.affectedRows : nil),
            lastInsertID: metadata?.lastInsertID,
            warningCount: executionStatus?.warningCount,
            executionTime: executionTime
        )
    }

    func execute(
        _ query: String,
        parameters: [DatabaseValue],
        timeout: Duration?
    ) async throws -> QueryResult {
        guard let timeout else {
            return try await execute(query, parameters: parameters)
        }
        let components = timeout.components
        let fractionalNanoseconds = Int64(components.attoseconds / 1_000_000_000)
        guard components.seconds > 0
                || (components.seconds == 0 && fractionalNanoseconds > 0) else {
            throw DatabaseError.queryTimedOut
        }
        let nanoseconds: Int64
        if components.seconds > (Int64.max - max(0, fractionalNanoseconds)) / 1_000_000_000 {
            nanoseconds = Int64.max
        } else {
            nanoseconds = components.seconds * 1_000_000_000 + fractionalNanoseconds
        }

        let timeoutState = MySQLQueryTimeoutState()
        let timeoutTask = connection.channel.eventLoop.scheduleTask(
            in: .nanoseconds(nanoseconds)
        ) { [connection] in
            guard timeoutState.fire() else { return }
            connection.channel.close(promise: nil)
        }
        do {
            let result = try await execute(query, parameters: parameters)
            let didTimeOut = timeoutState.complete()
            timeoutTask.cancel()
            if didTimeOut { throw DatabaseError.queryTimedOut }
            return result
        } catch {
            let didTimeOut = timeoutState.complete()
            timeoutTask.cancel()
            if didTimeOut { throw DatabaseError.queryTimedOut }
            throw error
        }
    }

    func cancelCurrentQuery() async throws {
        // mysql-nio does not expose COM_PROCESS_KILL for a live query. Closing
        // the channel is the only cancellation that guarantees the query stops
        // without requiring a second privileged server connection.
        try await connection.close().get()
    }

    private func currentExecutionStatus() async throws -> (affectedRows: UInt64?, warningCount: UInt16?) {
        let rows = try await connection.simpleQuery(
            "SELECT ROW_COUNT() AS glassdb_affected_rows, @@warning_count AS glassdb_warning_count"
        ).get()
        guard let row = rows.first else { return (nil, nil) }
        let affectedSigned = row.column("glassdb_affected_rows")?.int64
        let affected = affectedSigned.flatMap { $0 >= 0 ? UInt64($0) : nil }
        let warnings = row.column("glassdb_warning_count")?.uint64
            .map { UInt16(clamping: $0) }
        return (affected, warnings)
    }

    /// COM_QUERY preserves exact textual temporal/decimal values. Prepared
    /// statements remain mandatory whenever parameters or mutation metadata are needed.
    private static func shouldUseTextProtocol(_ sql: String, parameters: [DatabaseValue]) -> Bool {
        guard parameters.isEmpty else { return false }
        let upper = sql.uppercased()
        return upper.hasPrefix("SELECT ") || upper == "SELECT" || isUtilityCommand(sql)
    }

    private static func reportsAffectedRows(_ sql: String) -> Bool {
        let upper = sql.uppercased()
        let prefixes = [
            "INSERT ", "UPDATE ", "DELETE ", "REPLACE ",
            "CREATE ", "DROP ", "ALTER ", "TRUNCATE ",
            "GRANT ", "REVOKE ", "ANALYZE ", "OPTIMIZE ", "REPAIR ",
        ]
        return prefixes.contains { upper.hasPrefix($0) }
    }

    static func mysqlData(for value: DatabaseValue) throws -> MySQLData {
        switch value {
        case .string(let string):
            return MySQLData(string: string)
        case .int(let integer):
            var buffer = ByteBufferAllocator().buffer(capacity: MemoryLayout<Int64>.size)
            buffer.writeInteger(integer, endianness: .little)
            return MySQLData(type: .longlong, buffer: buffer)
        case .uint(let integer):
            var buffer = ByteBufferAllocator().buffer(capacity: MemoryLayout<UInt64>.size)
            buffer.writeInteger(integer, endianness: .little)
            return MySQLData(type: .longlong, buffer: buffer, isUnsigned: true)
        case .decimal(let decimal):
            guard Decimal(string: decimal, locale: Locale(identifier: "en_US_POSIX")) != nil else {
                throw DatabaseError.unsupportedParameter("\"\(decimal)\" is not a base-10 decimal.")
            }
            var buffer = ByteBufferAllocator().buffer(capacity: decimal.utf8.count)
            buffer.writeString(decimal)
            return MySQLData(type: .newdecimal, buffer: buffer)
        case .double(let double):
            return MySQLData(double: double)
        case .data(let data):
            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
            buffer.writeBytes(data)
            return MySQLData(type: .blob, buffer: buffer)
        case .json(let json):
            guard (try? JSONSerialization.jsonObject(with: Data(json.utf8))) != nil else {
                throw DatabaseError.unsupportedParameter("The JSON value is not valid JSON text.")
            }
            var buffer = ByteBufferAllocator().buffer(capacity: json.utf8.count)
            buffer.writeString(json)
            return MySQLData(type: .json, buffer: buffer)
        case .temporal(let temporal):
            return MySQLData(string: temporal.rawValue)
        case .bit(let bytes):
            var buffer = ByteBufferAllocator().buffer(capacity: bytes.count)
            buffer.writeBytes(bytes)
            return MySQLData(type: .bit, buffer: buffer, isUnsigned: true)
        case .null:
            return .null
        case .date(let date):
            return MySQLData(date: date)
        case .bool(let bool):
            return MySQLData(bool: bool)
        }
    }

    static func decodeValue(
        _ value: MySQLData,
        column: MySQLProtocol.ColumnDefinition41
    ) -> DatabaseValue {
        decodeValue(
            value,
            columnLength: column.columnLength,
            isBinaryCharacterSet: column.characterSet == .binary
        )
    }

    static func decodeValue(
        _ value: MySQLData,
        columnLength: UInt32,
        isBinaryCharacterSet: Bool
    ) -> DatabaseValue {
        guard value.buffer != nil else { return .null }

        switch value.type {
        case .tiny:
            if columnLength == 1, let bool = value.bool { return .bool(bool) }
            return decodeInteger(value)
        case .short, .long, .longlong, .int24:
            return decodeInteger(value)
        case .year:
            let raw: String
            if let string = value.string {
                raw = string
            } else if var buffer = value.buffer,
                      let year = buffer.readInteger(endianness: .little, as: UInt16.self) {
                raw = String(year)
            } else {
                raw = dataValue(value).base64EncodedString()
            }
            return .temporal(.init(rawValue: raw, kind: .year))
        case .float, .double:
            if let double = value.double { return .double(double) }
            return dataValue(value).isEmpty ? .null : .data(dataValue(value))
        case .decimal, .newdecimal:
            if let string = value.string ?? utf8Value(value) { return .decimal(string) }
            return .data(dataValue(value))
        case .bit:
            return .bit(dataValue(value))
        case .json:
            if let string = value.string ?? utf8Value(value) { return .json(string) }
            return .data(dataValue(value))
        case .date, .newdate:
            return decodeTemporal(value, kind: .date)
        case .time, .time2:
            return decodeTemporal(value, kind: .time)
        case .datetime, .datetime2:
            return decodeTemporal(value, kind: .dateTime)
        case .timestamp, .timestamp2:
            return decodeTemporal(value, kind: .timestamp)
        case .blob, .tinyBlob, .mediumBlob, .longBlob:
            if isBinaryCharacterSet { return .data(dataValue(value)) }
            if let string = value.string { return .string(string) }
            return .data(dataValue(value))
        case .geometry:
            return .data(dataValue(value))
        case .varchar, .varString, .string, .enum, .set:
            if let string = value.string ?? utf8Value(value) { return .string(string) }
            return .data(dataValue(value))
        case .null:
            return .null
        default:
            if let string = value.string { return .string(string) }
            return .data(dataValue(value))
        }
    }

    private static func decodeInteger(_ value: MySQLData) -> DatabaseValue {
        if value.isUnsigned, let integer = value.uint64 { return .uint(integer) }
        if let integer = value.int64 { return .int(integer) }
        return .data(dataValue(value))
    }

    private static func decodeTemporal(
        _ value: MySQLData,
        kind: DatabaseTemporalValue.Kind
    ) -> DatabaseValue {
        if let raw = value.string {
            return .temporal(.init(rawValue: raw, kind: kind))
        }
        let time = value.time ?? normalizedTemporalData(value).time
        guard let time else { return .data(dataValue(value)) }
        let date = [time.year.map { String(format: "%04d", $0) },
                    time.month.map { String(format: "%02d", $0) },
                    time.day.map { String(format: "%02d", $0) }]
            .compactMap { $0 }
            .joined(separator: "-")
        let clock = [time.hour.map { String(format: "%02d", $0) },
                     time.minute.map { String(format: "%02d", $0) },
                     time.second.map { String(format: "%02d", $0) }]
            .compactMap { $0 }
            .joined(separator: ":")
        var raw = [date, clock].filter { !$0.isEmpty }.joined(separator: " ")
        if let microsecond = time.microsecond, microsecond > 0 {
            raw += String(format: ".%06d", microsecond)
        }
        return .temporal(.init(rawValue: raw, kind: kind))
    }

    private static func dataValue(_ value: MySQLData) -> Data {
        value.buffer.map { Data($0.readableBytesView) } ?? Data()
    }

    private static func utf8Value(_ value: MySQLData) -> String? {
        String(data: dataValue(value), encoding: .utf8)
    }

    private static func normalizedTemporalData(_ value: MySQLData) -> MySQLData {
        let type: MySQLProtocol.DataType
        switch value.type {
        case .newdate: type = .date
        case .time2: type = .time
        case .datetime2: type = .datetime
        case .timestamp2: type = .timestamp
        default: type = value.type
        }
        return MySQLData(
            type: type,
            format: value.format,
            buffer: value.buffer,
            isUnsigned: value.isUnsigned
        )
    }

    /// Commands that MySQL does not support in the prepared statement protocol.
    /// These must be sent via COM_QUERY (simpleQuery) instead of COM_STMT_PREPARE.
    private static func isUtilityCommand(_ sql: String) -> Bool {
        let upper = sql.uppercased()
        let prefixes = [
            "USE ", "SET ", "SHOW ", "DESCRIBE ", "DESC ",
            "EXPLAIN ", "FLUSH ", "KILL ", "RESET ", "TRUNCATE ",
            "CREATE ", "DROP ", "ALTER ", "GRANT ", "REVOKE ",
            "LOCK ", "UNLOCK ", "BEGIN", "START ", "COMMIT", "ROLLBACK",
            "SAVEPOINT ", "RELEASE ",
        ]
        return prefixes.contains { upper.hasPrefix($0) || upper == $0.trimmingCharacters(in: .whitespaces) }
    }

    func close() async throws {
        try await connection.close().get()
    }

    func databases() async throws -> [String] {
        let result = try await execute("SHOW DATABASES")
        return result.rows.compactMap { row in
            if case .string(let name) = row.first {
                return name
            }
            return nil
        }
    }

    func tables(in database: String) async throws -> [String] {
        let result = try await execute("SHOW TABLES FROM `\(Self.escapeIdentifier(database))`")
        return result.rows.compactMap { row in
            if case .string(let name) = row.first {
                return name
            }
            return nil
        }
    }

    func columns(in table: String, database: String) async throws -> [ColumnInfo] {
        // Bound, not spliced: hand-escaped literals break under NO_BACKSLASH_ESCAPES.
        let result = try await execute(
            "SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY, ORDINAL_POSITION, COLUMN_DEFAULT, EXTRA " +
            "FROM INFORMATION_SCHEMA.COLUMNS " +
            "WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? " +
            "ORDER BY ORDINAL_POSITION",
            parameters: [.string(database), .string(table)]
        )
        return result.rows.enumerated().compactMap { index, row in
            guard row.count >= 8,
                  case .string(let name) = row[0],
                  case .string(let type) = row[1] else {
                return nil
            }
            let columnType = row[2].isNull ? type : row[2].displayString
            let lowercaseColumnType = columnType.lowercased()
            let editableType: String
            if lowercaseColumnType.hasSuffix(" unsigned zerofill") {
                editableType = String(columnType.dropLast(" unsigned zerofill".count)) + " ZEROFILL"
            } else if lowercaseColumnType.hasSuffix(" unsigned") {
                editableType = String(columnType.dropLast(" unsigned".count))
            } else {
                editableType = columnType
            }
            let nullable: Bool
            if case .string(let n) = row[3] {
                nullable = n == "YES"
            } else {
                nullable = true
            }
            let isPK: Bool
            if case .string(let k) = row[4] {
                isPK = k == "PRI"
            } else {
                isPK = false
            }
            let ordinalPosition: Int
            switch row[5] {
            case .int(let value): ordinalPosition = (Int(exactly: value) ?? 1) - 1
            case .uint(let value): ordinalPosition = (Int(exactly: value) ?? 1) - 1
            case .string(let value): ordinalPosition = (Int(value) ?? 1) - 1
            default: ordinalPosition = index
            }
            let defaultValue = row[6].isNull ? nil : row[6].displayString
            let extra = row[7].isNull ? "" : row[7].displayString.uppercased()
            return ColumnInfo(
                name: name,
                type: editableType,
                isNullable: nullable,
                isPrimaryKey: isPK,
                ordinalPosition: max(ordinalPosition, 0),
                isUnsigned: columnType.localizedCaseInsensitiveContains("unsigned"),
                defaultValue: defaultValue,
                isGenerated: extra.contains("GENERATED")
            )
        }
    }

    func showCreateTable(_ table: String, database: String) async throws -> String {
        let safeDB = Self.escapeIdentifier(database)
        let safeTable = Self.escapeIdentifier(table)
        let rows = try await connection.simpleQuery("SHOW CREATE TABLE `\(safeDB)`.`\(safeTable)`").get()
        guard let row = rows.first,
              let createSQL = row.column("Create Table")?.string else {
            throw DatabaseError.unexpectedResult("SHOW CREATE TABLE returned no result")
        }
        return createSQL
    }

    func indexes(in table: String, database: String) async throws -> [IndexInfo] {
        let safeTable = Self.escapeIdentifier(table)
        let safeDB = Self.escapeIdentifier(database)
        let rows = try await connection.simpleQuery("SHOW INDEX FROM `\(safeTable)` FROM `\(safeDB)`").get()
        return rows.compactMap { row in
            guard let keyName = row.column("Key_name")?.string,
                  let columnName = row.column("Column_name")?.string,
                  let indexType = row.column("Index_type")?.string else {
                return nil
            }
            let nonUnique = row.column("Non_unique")?.string ?? "1"
            let seqInIndex = Int(row.column("Seq_in_index")?.string ?? "1") ?? 1
            return IndexInfo(
                name: keyName,
                columnName: columnName,
                isUnique: nonUnique == "0",
                isPrimary: keyName.uppercased() == "PRIMARY",
                type: indexType,
                sequenceInIndex: seqInIndex
            )
        }
    }

    func foreignKeys(in table: String, database: String) async throws -> [ForeignKeyInfo] {
        let result = try await execute(
            "SELECT CONSTRAINT_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME, ORDINAL_POSITION " +
            "FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE " +
            "WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND REFERENCED_TABLE_NAME IS NOT NULL " +
            "ORDER BY CONSTRAINT_NAME, ORDINAL_POSITION",
            parameters: [.string(database), .string(table)]
        )
        return result.rows.compactMap { row in
            guard row.count >= 5,
                  case .string(let constraintName) = row[0],
                  case .string(let columnName) = row[1],
                  case .string(let refTable) = row[2],
                  case .string(let refColumn) = row[3] else {
                return nil
            }
            let ordinal: Int
            switch row[4] {
            case .string(let pos): ordinal = Int(pos) ?? 0
            case .int(let pos): ordinal = Int(exactly: pos) ?? 0
            case .uint(let pos): ordinal = Int(exactly: pos) ?? 0
            default: ordinal = 0
            }
            return ForeignKeyInfo(
                constraintName: constraintName,
                columnName: columnName,
                referencedTable: refTable,
                referencedColumn: refColumn,
                ordinalPosition: ordinal
            )
        }
    }

    func tableStatus(in database: String) async throws -> [TableStatus] {
        let safeDB = Self.escapeIdentifier(database)
        let rows = try await connection.simpleQuery("SHOW TABLE STATUS FROM `\(safeDB)`").get()
        return rows.compactMap(Self.tableStatus(from:))
    }

    /// One statement over every namespace on the server. SHOW TABLE STATUS
    /// reads from the same data dictionary as information_schema.TABLES;
    /// aliasing to the SHOW column names keeps one shared mapping and
    /// identical per-table values across both paths.
    static let aggregateTableStatusQuery =
        "SELECT TABLE_SCHEMA AS `Schema`, TABLE_NAME AS `Name`, ENGINE AS `Engine`, " +
        "TABLE_ROWS AS `Rows`, DATA_LENGTH AS `Data_length`, INDEX_LENGTH AS `Index_length`, " +
        "TABLE_COLLATION AS `Collation` " +
        "FROM INFORMATION_SCHEMA.TABLES " +
        "ORDER BY TABLE_SCHEMA, TABLE_NAME"

    func tableStatusByNamespace() async throws -> [String: [TableStatus]] {
        let rows = try await connection.simpleQuery(Self.aggregateTableStatusQuery).get()
        var grouped: [String: [TableStatus]] = [:]
        for row in rows {
            guard let schema = row.column("Schema")?.string,
                  let status = Self.tableStatus(from: row) else {
                continue
            }
            grouped[schema, default: []].append(status)
        }
        return grouped
    }

    /// Shared mapping for `SHOW TABLE STATUS` rows and the aggregate
    /// information_schema query, which aliases its columns to the SHOW names.
    private static func tableStatus(from row: MySQLRow) -> TableStatus? {
        guard let name = row.column("Name")?.string else {
            return nil
        }
        let engine = row.column("Engine")?.string
        let rowCount = Int(row.column("Rows")?.string ?? "0") ?? 0
        let tableDataLength = Int(row.column("Data_length")?.string ?? "0") ?? 0
        let indexLength = Int(row.column("Index_length")?.string ?? "0") ?? 0
        let (combinedLength, overflowed) = tableDataLength.addingReportingOverflow(indexLength)
        let dataLength = overflowed ? Int.max : combinedLength
        let collation = row.column("Collation")?.string
        return TableStatus(
            name: name,
            engine: engine,
            rowCount: rowCount,
            dataLength: dataLength,
            collation: collation,
            // MySQL documents exact SHOW TABLE STATUS counts for MyISAM;
            // other storage engines may expose optimizer estimates.
            rowCountAccuracy: engine?.localizedCaseInsensitiveCompare("MyISAM") == .orderedSame
                ? .exact
                : .estimated
        )
    }

    func rowCount(table: String, database: String) async throws -> Int {
        try await rowCount(table: table, database: database, timeout: nil)
    }

    func rowCount(table: String, database: String, timeout: Duration?) async throws -> Int {
        let safeDB = Self.escapeIdentifier(database)
        let safeTable = Self.escapeIdentifier(table)
        let result = try await execute(
            "SELECT COUNT(*) FROM `\(safeDB)`.`\(safeTable)`",
            parameters: [],
            timeout: timeout
        )
        guard let firstRow = result.rows.first,
              let firstValue = firstRow.first else {
            return 0
        }
        switch firstValue {
        case .string(let s): return Int(s) ?? 0
        case .int(let i): return Int(i)
        case .uint(let i): return Int(exactly: i) ?? Int.max
        default: return 0
        }
    }

    /// Escapes a MySQL identifier (database/table/column name) for use inside backticks.
    /// Doubles any existing backticks so `db`name` becomes `db``name`.
    private static func escapeIdentifier(_ value: String) -> String {
        value.replacingOccurrences(of: "`", with: "``")
    }

    private func mysqlTypeName(_ type: MySQLProtocol.DataType) -> String {
        switch type {
        case .varchar, .varString, .string: return "VARCHAR"
        case .long, .longlong: return "INT"
        case .tiny: return "TINYINT"
        case .short: return "SMALLINT"
        case .int24: return "MEDIUMINT"
        case .float: return "FLOAT"
        case .double: return "DOUBLE"
        case .decimal, .newdecimal: return "DECIMAL"
        case .date: return "DATE"
        case .datetime, .datetime2: return "DATETIME"
        case .timestamp, .timestamp2: return "TIMESTAMP"
        case .time, .time2: return "TIME"
        case .blob: return "BLOB"
        case .bit: return "BIT"
        case .json: return "JSON"
        case .enum: return "ENUM"
        case .set: return "SET"
        case .null: return "NULL"
        default: return "UNKNOWN"
        }
    }
}

private final class MySQLQueryTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var isComplete = false
    private var didTimeOut = false

    /// Returns whether this timeout won the race with normal completion.
    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isComplete else { return false }
        isComplete = true
        didTimeOut = true
        return true
    }

    /// Marks normal completion and returns whether the timeout won first.
    func complete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !isComplete { isComplete = true }
        return didTimeOut
    }
}
