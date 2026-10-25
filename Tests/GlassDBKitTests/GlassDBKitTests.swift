//
//  GlassDBKitTests.swift
//  GlassDBKit
//

import Foundation
import MySQLNIO
import NIOSSL
import Testing
@testable import GlassDBKit

@Suite struct QueryResultTests {
    @Test func queryResultCreation() {
        let result = QueryResult(
            query: "SELECT 1",
            columns: [
                ColumnInfo(name: "1", type: "INT")
            ],
            rows: [[.int(1)]],
            affectedRows: 1,
            lastInsertID: 42,
            warningCount: 0,
            executionTime: 0.001
        )
        #expect(result.rowCount == 1)
        #expect(result.columnCount == 1)
        #expect(!result.isError)
        #expect(result.affectedRows == 1)
        #expect(result.lastInsertID == 42)
        #expect(result.warningCount == 0)
        #expect(result.appliedRowLimit == nil)
        #expect(!result.isTruncated)
    }

    @Test func queryResultTruncationMetadataIsExplicit() {
        let result = QueryResult(
            query: "SELECT * FROM events",
            rows: [[.int(1)], [.int(2)]],
            executionTime: 0.01,
            appliedRowLimit: 2,
            isTruncated: true
        )

        #expect(result.rowCount == 2)
        #expect(result.appliedRowLimit == 2)
        #expect(result.isTruncated)
    }

    @Test func databaseValueDisplay() {
        #expect(DatabaseValue.string("hello").displayString == "hello")
        #expect(DatabaseValue.int(42).displayString == "42")
        #expect(DatabaseValue.uint(UInt64.max).displayString == String(UInt64.max))
        #expect(DatabaseValue.decimal("1234567890.0000000001").displayString == "1234567890.0000000001")
        #expect(DatabaseValue.json("{\"ok\":true}").displayString == "{\"ok\":true}")
        #expect(DatabaseValue.temporal(.init(rawValue: "2026-07-17 09:30:00.123456", kind: .timestamp)).displayString == "2026-07-17 09:30:00.123456")
        #expect(DatabaseValue.bit(Data([0b1010_0101])).displayString == "10100101")
        #expect(DatabaseValue.data(Data([0, 1, 2])).exportString == "AAEC")
        #expect(DatabaseValue.null.displayString == "NULL")
        #expect(DatabaseValue.null.isNull)
        #expect(!DatabaseValue.string("test").isNull)
    }

    @Test func mysqlParameterBindingPreservesBoundaries() throws {
        let signed = try MySQLDatabaseConnection.mysqlData(for: .int(Int64.min))
        #expect(signed.int64 == Int64.min)

        let unsigned = try MySQLDatabaseConnection.mysqlData(for: .uint(UInt64.max))
        #expect(unsigned.isUnsigned)
        #expect(unsigned.uint64 == UInt64.max)

        let binary = try MySQLDatabaseConnection.mysqlData(for: .data(Data([0, 255, 127])))
        #expect(binary.buffer?.readableBytes == 3)

        let null = try MySQLDatabaseConnection.mysqlData(for: .null)
        #expect(null.buffer == nil)

        #expect(throws: DatabaseError.self) {
            try MySQLDatabaseConnection.mysqlData(for: .decimal("not-a-number"))
        }
        #expect(throws: DatabaseError.self) {
            try MySQLDatabaseConnection.mysqlData(for: .json("{invalid"))
        }
    }

    @Test func mysqlBinaryDecodingPreservesTypedText() throws {
        let exactDecimal = "12345678901234567890.000000000123456789"
        let decimalData = try MySQLDatabaseConnection.mysqlData(for: .decimal(exactDecimal))
        #expect(
            MySQLDatabaseConnection.decodeValue(
                decimalData,
                columnLength: 40,
                isBinaryCharacterSet: false
            ) == .decimal(exactDecimal)
        )

        let json = "{\"big\":18446744073709551615}"
        let jsonData = try MySQLDatabaseConnection.mysqlData(for: .json(json))
        #expect(
            MySQLDatabaseConnection.decodeValue(
                jsonData,
                columnLength: 32,
                isBinaryCharacterSet: false
            ) == .json(json)
        )

        let binaryData = try MySQLDatabaseConnection.mysqlData(for: .data(Data([0, 255])))
        #expect(
            MySQLDatabaseConnection.decodeValue(
                binaryData,
                columnLength: 2,
                isBinaryCharacterSet: true
            ) == .data(Data([0, 255]))
        )
    }

    @Test func transportPoliciesAreExplicit() {
        #expect(!DatabaseTLSPolicy.disabled.isRequired)
        #expect(DatabaseTLSPolicy.requiredSystemTrust.isRequired)
        #expect(DatabaseTLSPolicy.requiredSystemTrustForHost("db.example.com").isRequired)
        #expect(DatabaseTLSPolicy.requiredCertificates([], serverName: nil).isRequired)
        // The CA-only mode is still a required mode: it never falls back to plaintext.
        #expect(DatabaseTLSPolicy.requiredCertificatesWithoutHostnameVerification([]).isRequired)
    }

    /// The CA-only mode's whole reason to exist is that it verifies *less* than the mode beside
    /// it, so the difference has to be stated somewhere a UI can read and a reviewer can check.
    @Test func onlyTheCAOnlyModeDeclinesToVerifyServerIdentity() {
        #expect(!DatabaseTLSPolicy.disabled.verifiesServerIdentity)
        #expect(DatabaseTLSPolicy.requiredSystemTrust.verifiesServerIdentity)
        #expect(DatabaseTLSPolicy.requiredSystemTrustForHost("db.example.com").verifiesServerIdentity)
        #expect(DatabaseTLSPolicy.requiredCertificates([], serverName: nil).verifiesServerIdentity)
        #expect(!DatabaseTLSPolicy.requiredCertificatesWithoutHostnameVerification([]).verifiesServerIdentity)
    }

    /// `serverName: nil` on `.requiredCertificates` means "match the host I am connecting to" and
    /// must keep meaning that. Turning it into "match nothing" would have been the cheap way to
    /// add VERIFY_CA and would have silently downgraded every existing call site.
    @Test func nilServerNameStillMeansMatchTheConnectionHost() throws {
        let certificate = DatabaseTLSCertificate(bytes: Data(unrelatedCertificateAuthorityPEM.utf8), format: .pem)

        let (pinned, pinnedName) = try DatabaseTLSPolicy
            .requiredCertificates([certificate], serverName: nil)
            .makeTLSConfiguration(connectionHost: "db.example.com")
        #expect(pinnedName == "db.example.com")
        #expect(pinned?.certificateVerification == .fullVerification)

        let (caOnly, caOnlyName) = try DatabaseTLSPolicy
            .requiredCertificatesWithoutHostnameVerification([certificate])
            .makeTLSConfiguration(connectionHost: "db.example.com")
        // No name is matched, so no name is sent: a hostname here would set SNI while the
        // configuration claims to check no name.
        #expect(caOnlyName == nil)
        #expect(caOnly?.certificateVerification == .noHostnameVerification)
        #expect(caOnly?.minimumTLSVersion == .tlsv12)
    }

    /// Rule 18: the mode that skips the hostname check must not also skip the chain check. A
    /// policy with no usable trust root has to fail while it is still a configuration error.
    @Test func caOnlyModeRejectsMissingAndMalformedTrustRootsBeforeNetworkUse() async {
        let policies: [DatabaseTLSPolicy] = [
            .requiredCertificatesWithoutHostnameVerification([]),
            .requiredCertificatesWithoutHostnameVerification([
                .init(bytes: Data("not a certificate".utf8), format: .pem)
            ]),
            .requiredCertificatesWithoutHostnameVerification([
                .init(bytes: Data([0, 1, 2, 3]), format: .der)
            ]),
        ]
        for policy in policies {
            #expect(throws: DatabaseError.self) {
                _ = try policy.makeTLSConfiguration(connectionHost: "db.example.com")
            }
            await #expect(throws: DatabaseError.self) {
                _ = try await MySQLEngine().connect(
                    host: "127.0.0.1", port: 1, username: "user", password: "password",
                    database: nil, tlsPolicy: policy
                )
            }
            await #expect(throws: DatabaseError.self) {
                _ = try await PostgreSQLEngine().connect(
                    host: "127.0.0.1", port: 1, username: "user", password: "password",
                    database: nil, tlsPolicy: policy
                )
            }
        }
    }

    /// SQLite is a local file and has no transport to secure. The new case must be refused there
    /// like every other required policy, not silently accepted because the switch grew a case.
    @Test func sqliteRefusesTheCAOnlyModeLikeEveryOtherRequiredPolicy() async {
        await #expect(throws: DatabaseError.self) {
            _ = try await SQLiteEngine().connect(
                host: "/tmp/does-not-matter.sqlite", port: 0, username: "", password: "",
                database: nil,
                tlsPolicy: .requiredCertificatesWithoutHostnameVerification([
                    .init(bytes: Data(unrelatedCertificateAuthorityPEM.utf8), format: .pem)
                ])
            )
        }
    }

    @Test func mysqlTLSGreetingPreflightFailsClosed() {
        var greeting = [UInt8(10)] + Array("8.0.40".utf8) + [0]
        greeting += [1, 0, 0, 0]
        greeting += Array(repeating: 0, count: 8)
        greeting += [0]

        var withoutTLS = greeting
        withoutTLS += [0, 0]
        #expect(!MySQLTLSCapabilityProbe.serverSupportsTLS(in: withoutTLS))

        var withTLS = greeting
        withTLS += [0x00, 0x08]
        #expect(MySQLTLSCapabilityProbe.serverSupportsTLS(in: withTLS))
        #expect(!MySQLTLSCapabilityProbe.serverSupportsTLS(in: []))
    }

    @Test func requiredTLSRejectsMissingAndMalformedTrustRootsBeforeNetworkUse() async {
        let policies: [DatabaseTLSPolicy] = [
            .requiredCertificates([], serverName: nil),
            .requiredCertificates([
                .init(bytes: Data("not a certificate".utf8), format: .pem)
            ], serverName: "db.example.com"),
            .requiredCertificates([
                .init(bytes: Data([0, 1, 2, 3]), format: .der)
            ], serverName: "db.example.com"),
        ]

        for policy in policies {
            await #expect(throws: DatabaseError.self) {
                _ = try await MySQLEngine().connect(
                    host: "127.0.0.1",
                    port: 1,
                    username: "user",
                    password: "password",
                    database: nil,
                    tlsPolicy: policy
                )
            }
            await #expect(throws: DatabaseError.self) {
                _ = try await PostgreSQLEngine().connect(
                    host: "127.0.0.1",
                    port: 1,
                    username: "user",
                    password: "password",
                    database: nil,
                    tlsPolicy: policy
                )
            }
        }
    }

    @Test func identifiersAreQuotedAsOneComponent() {
        let connection = TestConnection()
        #expect(connection.quotedIdentifier("users") == "`users`")
        #expect(connection.quotedIdentifier("db`name") == "`db``name`")
        #expect(connection.quotedIdentifier("db.users") == "`db.users`")
    }

    @Test func engineCapabilitiesAreExplicit() async throws {
        #expect(PostgreSQLEngine().capabilities.contains(.queryTimeout))
        #expect(PostgreSQLEngine().capabilities.contains(.cancellation))
        #expect(SQLiteEngine().capabilities.contains(.cancellation))
        #expect(!SQLiteEngine().capabilities.contains(.transportTLS))
        #expect(MySQLEngine().capabilities.contains(.transportTLS))

        let sqlite = try await SQLiteEngine().connect(path: ":memory:")
        #expect(sqlite.quotedIdentifier("table\"name") == "\"table\"\"name\"")
        try await sqlite.close()
    }

    @Test func aggregateStatisticsCapabilityIsExplicitAndGatedByDefault() async throws {
        #expect(MySQLEngine().capabilities.contains(.aggregateTableStatistics))
        #expect(PostgreSQLEngine().capabilities.contains(.aggregateTableStatistics))
        #expect(!SQLiteEngine().capabilities.contains(.aggregateTableStatistics))

        // Engines that do not advertise the capability inherit a fail-closed
        // default instead of silently returning an empty aggregate.
        do {
            _ = try await TestConnection().tableStatusByNamespace()
            Issue.record("The default tableStatusByNamespace must fail closed.")
        } catch DatabaseError.unsupportedCapability(let capability, _) {
            #expect(capability == .aggregateTableStatistics)
        }
    }

    @Test func aggregateTableStatusQueriesCoverEveryNamespaceInOneStatement() {
        // MySQL aliases information_schema columns to the SHOW TABLE STATUS
        // names so both paths share one row mapping, and scans every schema
        // (no WHERE) in a single deterministic ordering.
        let mysql = MySQLDatabaseConnection.aggregateTableStatusQuery
        #expect(mysql.contains("FROM INFORMATION_SCHEMA.TABLES"))
        #expect(mysql.contains("TABLE_SCHEMA AS `Schema`"))
        #expect(mysql.contains("TABLE_NAME AS `Name`"))
        #expect(mysql.contains("ENGINE AS `Engine`"))
        #expect(mysql.contains("TABLE_ROWS AS `Rows`"))
        #expect(mysql.contains("DATA_LENGTH AS `Data_length`"))
        #expect(mysql.contains("INDEX_LENGTH AS `Index_length`"))
        #expect(mysql.contains("TABLE_COLLATION AS `Collation`"))
        #expect(mysql.contains("ORDER BY TABLE_SCHEMA, TABLE_NAME"))
        #expect(!mysql.contains("WHERE"))

        // PostgreSQL keeps the same user-schema filter as databases() and
        // takes no parameters: one unbound statement covers every schema.
        let postgres = PostgreSQLDatabaseConnection.aggregateTableStatusQuery
        #expect(postgres.contains("namespace.nspname <> 'information_schema'"))
        #expect(postgres.contains("namespace.nspname NOT LIKE 'pg_%'"))
        #expect(postgres.contains("table_class.relkind IN ('r', 'p')"))
        #expect(postgres.contains("pg_total_relation_size(table_class.oid)"))
        #expect(postgres.contains("ORDER BY namespace.nspname, table_class.relname"))
        #expect(!postgres.contains("$1"))
    }

    @Test func postgresAggregateRowsMapFromTheSchemaPrefixedOffset() {
        let analyzed = Date(timeIntervalSince1970: 1_750_000_000)
        let prefixed: [DatabaseValue] = [
            .string("analytics"),
            .string("events"),
            .int(42),
            .int(8_192),
            .date(analyzed),
            .int(7),
        ]

        let status = PostgreSQLDatabaseConnection.tableStatus(from: prefixed, startingAt: 1)
        #expect(status.name == "events")
        #expect(status.engine == "PostgreSQL")
        #expect(status.rowCount == 42)
        #expect(status.dataLength == 8_192)
        #expect(status.rowCountAccuracy == .estimated)
        #expect(status.statisticsUpdatedAt == analyzed)
        #expect(status.modifiedRowsSinceAnalysis == 7)

        // The per-schema query has no schema prefix and maps from offset 0 to
        // the same values.
        let unprefixed = PostgreSQLDatabaseConnection.tableStatus(
            from: Array(prefixed.dropFirst()),
            startingAt: 0
        )
        #expect(unprefixed.name == "events")
        #expect(unprefixed.rowCount == 42)
        #expect(unprefixed.statisticsUpdatedAt == analyzed)

        // Never-analyzed tables surface nil metadata instead of fake dates.
        let unanalyzed = PostgreSQLDatabaseConnection.tableStatus(
            from: [.string("bare"), .int(0), .int(0), .null, .null],
            startingAt: 0
        )
        #expect(unanalyzed.statisticsUpdatedAt == nil)
        #expect(unanalyzed.modifiedRowsSinceAnalysis == nil)
    }

    @Test func postgresParameterBoundariesAreExplicit() throws {
        let signed = try PostgreSQLDatabaseConnection.postgresData(for: .int(Int64.min))
        #expect(signed.int64 == Int64.min)
        let numeric = try PostgreSQLDatabaseConnection.postgresData(
            for: .decimal("12345678901234567890.000000000123456789")
        )
        #expect(numeric.numeric?.string == "12345678901234567890.000000000123456789")
        #expect(throws: DatabaseError.self) {
            try PostgreSQLDatabaseConnection.postgresData(for: .uint(UInt64.max))
        }
        #expect(throws: DatabaseError.self) {
            try PostgreSQLDatabaseConnection.postgresData(for: .json("{invalid"))
        }
    }

    @Test func errorResult() {
        let result = QueryResult(
            query: "INVALID SQL",
            executionTime: 0,
            error: "Syntax error"
        )
        #expect(result.isError)
        #expect(result.rowCount == 0)
    }
}

@Suite struct SQLiteAdapterTests {
    @Test func tableStatisticsExposeRealTablesAndExactRowCounts() async throws {
        let connection = try await SQLiteEngine().connect(path: ":memory:")
        defer { Task { try? await connection.close() } }

        _ = try await connection.execute("CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT)")
        _ = try await connection.execute("INSERT INTO projects (name) VALUES ('one'), ('two')")

        #expect(connection.capabilities.contains(.tableStatistics))
        let statuses = try await connection.tableStatus(in: "main")
        let projects = try #require(statuses.first { $0.name == "projects" })
        #expect(projects.engine == "SQLite")
        #expect(projects.rowCount == 2)
        #expect(projects.dataLength == 0)
        #expect(projects.rowCountAccuracy == .exact)
        #expect(try await connection.rowCount(
            table: "projects",
            database: "main",
            timeout: .seconds(1)
        ) == 2)
    }

    @Test func managedSnapshotCapturesCommittedWALPages() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glassdb-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("source.sqlite")
        let destinationURL = temporaryDirectory.appendingPathComponent("managed.sqlite")
        let source = try await SQLiteEngine().connect(path: sourceURL.path)
        defer { Task { try? await source.close() } }

        _ = try await source.execute("PRAGMA journal_mode = WAL")
        _ = try await source.execute("PRAGMA wal_autocheckpoint = 0")
        _ = try await source.execute("CREATE TABLE records (id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
        _ = try await source.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        _ = try await source.execute(
            "INSERT INTO records (value) VALUES (?)",
            parameters: [.string("committed in WAL")]
        )

        let walURL = URL(fileURLWithPath: sourceURL.path + "-wal")
        #expect(FileManager.default.fileExists(atPath: walURL.path))
        #expect((try walURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0)

        try SQLiteEngine.createManagedSnapshot(from: sourceURL, at: destinationURL)
        let managed = try await SQLiteEngine().connect(path: destinationURL.path, readOnly: true)
        let result = try await managed.execute("SELECT id, value FROM records ORDER BY id")
        #expect(result.rows == [[.int(1), .string("committed in WAL")]])
        try await managed.close()

        #expect(throws: DatabaseError.self) {
            try SQLiteEngine.createManagedSnapshot(from: sourceURL, at: destinationURL)
        }
        try await source.close()
    }

    @Test func bindingsPreserveNULAndRejectSmuggledOrMismatchedStatements() async throws {
        let connection = try await SQLiteEngine().connect(path: ":memory:")
        defer { Task { try? await connection.close() } }
        _ = try await connection.execute("CREATE TABLE values_table (payload TEXT)", parameters: [])

        let adversarialValue = "prefix\0'; DROP TABLE values_table; -- suffix"
        _ = try await connection.execute(
            "INSERT INTO values_table (payload) VALUES (?)",
            parameters: [.string(adversarialValue)]
        )
        let result = try await connection.execute(
            "SELECT payload FROM values_table WHERE payload = ?",
            parameters: [.string(adversarialValue)]
        )
        #expect(result.rows == [[.string(adversarialValue)]])

        await #expect(throws: DatabaseError.self) {
            _ = try await connection.execute("SELECT ?", parameters: [])
        }
        await #expect(throws: DatabaseError.self) {
            _ = try await connection.execute("SELECT 1", parameters: [.int(1)])
        }
        await #expect(throws: DatabaseError.self) {
            _ = try await connection.execute("SELECT 1; DROP TABLE values_table", parameters: [])
        }
        await #expect(throws: DatabaseError.self) {
            _ = try await connection.execute("SELECT 1\0; DROP TABLE values_table", parameters: [])
        }
        #expect(try await connection.rowCount(table: "values_table", database: "main") == 1)
        try await connection.close()
    }

    /// 2026-10-24, found by the test audit: `sqlite3_interrupt` reaches only a statement already
    /// running. A Cancel or a timeout that came while a query waited its turn behind another, or was
    /// being prepared, was lost, and the query ran to its end — here, a billion rows.
    @Test("Cancel reaches a query still waiting its turn, and a timeout one that hasn't started",
          .timeLimit(.minutes(1)))
    func cancelAndTimeoutReachAQueryNotYetRunning() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("glassdb-sqlite-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let connection = try #require(try await SQLiteEngine().connect(path: path) as? SQLiteDatabaseConnection)
        defer { Task { try? await connection.close() } }
        let billion = """
            WITH RECURSIVE counter(value) AS (
                VALUES(0) UNION ALL SELECT value + 1 FROM counter WHERE value < 1000000000
            ) SELECT sum(value) FROM counter
            """

        let running = Task { try await connection.execute(billion) }
        while connection.queriesInFlight < 1 { await Task.yield() }
        let waiting = Task { try await connection.execute(billion) }
        while connection.queriesInFlight < 2 { await Task.yield() }
        try await connection.cancelCurrentQuery()
        await #expect(throws: CancellationError.self) { try await running.value }
        await #expect(throws: CancellationError.self, "the one waiting its turn") { try await waiting.value }

        // A timeout that passes before the query has its turn.
        let holding = Task { try await connection.execute(billion) }
        while connection.queriesInFlight < 1 { await Task.yield() }
        let timed = Task { try await connection.execute(billion, parameters: [], timeout: .milliseconds(1)) }
        while connection.queriesInFlight < 2 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(20))
        holding.cancel()
        _ = try? await holding.value
        await #expect(throws: DatabaseError.self, "timed out before it ran") { try await timed.value }
    }

    @Test func realFileRoundTripMetadataTransactionsTimeoutAndCancellation() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("glassdb-sqlite-\(UUID().uuidString).sqlite")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let connection = try await SQLiteEngine().connect(path: path)
        _ = try await connection.execute(
            """
            CREATE TABLE records (
                id INTEGER PRIMARY KEY,
                payload TEXT NOT NULL,
                amount REAL,
                bytes BLOB
            )
            """
        )
        let injection = "Robert'); DROP TABLE records;--"
        let insert = try await connection.execute(
            "INSERT INTO records (payload, amount, bytes) VALUES (?, ?, ?)",
            parameters: [.string(injection), .double(3.5), .data(Data([0, 255]))]
        )
        #expect(insert.affectedRows == 1)
        #expect(insert.lastInsertID == 1)

        let selected = try await connection.execute(
            "SELECT payload, amount, bytes FROM records WHERE payload = ?",
            parameters: [.string(injection)]
        )
        #expect(selected.rows == [[.string(injection), .double(3.5), .data(Data([0, 255]))]])

        try await connection.beginTransaction()
        _ = try await connection.execute(
            "INSERT INTO records (payload) VALUES (?)",
            parameters: [.string("rolled back")]
        )
        try await connection.rollbackTransaction()
        #expect(try await connection.rowCount(table: "records", database: "main") == 1)

        #expect(try await connection.databases().contains("main"))
        #expect(try await connection.tables(in: "main").contains("records"))
        #expect(try await connection.columns(in: "records", database: "main").count == 4)
        #expect(try await connection.showCreateTable("records", database: "main").contains("CREATE TABLE"))
        #expect(!(try await connection.serverVersion()).isEmpty)
        #expect(!(try await connection.explain("SELECT * FROM records", parameters: [])).rows.isEmpty)

        await #expect(throws: DatabaseError.self) {
            try await connection.execute(
                """
                WITH RECURSIVE counter(value) AS (
                    VALUES(0) UNION ALL SELECT value + 1 FROM counter WHERE value < 1000000000
                ) SELECT sum(value) FROM counter
                """,
                parameters: [],
                timeout: .milliseconds(1)
            )
        }

        let longQuery = Task {
            try await connection.execute(
                """
                WITH RECURSIVE counter(value) AS (
                    VALUES(0) UNION ALL SELECT value + 1 FROM counter WHERE value < 1000000000
                ) SELECT sum(value) FROM counter
                """
            )
        }
        try await Task.sleep(for: .milliseconds(10))
        try await connection.cancelCurrentQuery()
        await #expect(throws: CancellationError.self) { try await longQuery.value }

        await #expect(throws: DatabaseError.self) {
            try await SQLiteEngine().connect(
                host: path,
                port: 0,
                username: "",
                password: "",
                database: nil,
                tlsPolicy: .requiredSystemTrust
            )
        }
        try await connection.close()
    }
}

/// Live-engine settings, supplied by the environment so the suite can aim at the project's test VM
/// (see the Stage 3 VM note) rather than a hardcoded localhost port. Absent password disables the test.
/// A self-signed CA that signed nothing. Used to prove that the CA-only mode still verifies the
/// chain: pointed at a real server it must fail, exactly as the server's own CA must succeed.
/// Generated with `openssl req -x509 -newkey rsa:2048 -nodes -days 7300`; the private key was
/// discarded and never existed in this repository. Carries no secret.
private let unrelatedCertificateAuthorityPEM = """
-----BEGIN CERTIFICATE-----
MIIDVzCCAj+gAwIBAgIUV3wDIwbSRLq92vNQjAI7pW2jApswDQYJKoZIhvcNAQEL
BQAwOzE5MDcGA1UEAwwwR2xhc3MgUG93ZXIgVG9vbHMgVGVzdCBDQSAobm90IGEg
cmVhbCBhdXRob3JpdHkpMB4XDTI2MDkxMjE5MzE1NVoXDTQ2MDkwNzE5MzE1NVow
OzE5MDcGA1UEAwwwR2xhc3MgUG93ZXIgVG9vbHMgVGVzdCBDQSAobm90IGEgcmVh
bCBhdXRob3JpdHkpMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqAqJ
8fpDJY5Rn2EHZlqyHmK/7m3dbM3jtBEVq06n/zkvzMa44+wF4qsGvl94vHwO9qV6
kJdNUIH4+QQtsfpoln6ULCJ0KGeIpG8ALQp6vIEOAmLy2HRNkZG/AEDYZ2hxaoBo
GMnREfEeMoUotPpE+tgDWE28/K3kta9wIEQCZAITL6FCupI1fogvBZhEJLWF40p3
KbuWQENBS4X1B+ZknIFAem7t6SFHKCQfBroObfhJfBYSVb2c1KfUkbiqlwikvKK8
2ERqmhaSYT283kaRYCMN3oBroahgkMIVEYG8dyuXXFMzGVuiT7ioWtwCcHRPC0eq
abPnNA/GnX/m9Q4l3QIDAQABo1MwUTAdBgNVHQ4EFgQUJfKynwiJ4zo0PUrtXF4P
DCC1E4EwHwYDVR0jBBgwFoAUJfKynwiJ4zo0PUrtXF4PDCC1E4EwDwYDVR0TAQH/
BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAXfdyHs0O/RcjXNf7HUFbgKEm1fQ2
EZ2iNjJsm8lPZl1Q+V/WSP3c/oDK/X1JdEO+nWP2JAAAfqEXn/jd9pVqIaqTRNhn
Mbn8jJNL8yhNYtTBuuzaEKqRl5uAWmuKaDiK59TM3FPtpWAuivzd9JYTUxXyit0m
8MTDkQFE/aCtjJyUFQMuw3i1N54vwfjmUY013EW0SUpd66pztIqeKffXkM+ztNkw
CAYTtMs2R+RUqIzOL/kK6V6Gltv5esnXLyhD7huTs/7TrgCyJAv2UnjL5RsQw4vl
DshIAueLo5G03I6meg5BZwifBCfJTQzcITj7WsfYg6s35c8puZ8uFpDIPw==
-----END CERTIFICATE-----
"""

private enum LiveDatabaseEnvironment {
    static func value(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }

    static var host: String { value("GPT_DB_TEST_HOST") ?? "127.0.0.1" }

    static func port(_ name: String, default fallback: Int) -> Int {
        value(name).flatMap(Int.init) ?? fallback
    }

    static var mysqlPassword: String? { value("GPT_DB_TEST_MYSQL_PASSWORD") }
    static var mysqlPort: Int { port("GPT_DB_TEST_MYSQL_PORT", default: 3_306) }
    static var mysqlUser: String { value("GPT_DB_TEST_MYSQL_USER") ?? "gpt_test" }
    static var mysqlDatabase: String { value("GPT_DB_TEST_MYSQL_DB") ?? "gpt_test" }
    /// Where a test may CREATE and DROP. Deliberately **not** the seeded database: on MySQL a
    /// database-scoped DROP also permits DROP DATABASE, so a test that can drop its own table can
    /// drop the fixture with it. The scratch database holds nothing that is not ephemeral.
    static var mysqlScratchDatabase: String { value("GPT_DB_TEST_MYSQL_SCRATCH_DB") ?? "gpt_scratch" }

    static var postgresPassword: String? { value("GPT_DB_TEST_PG_PASSWORD") }
    static var postgresPort: Int { port("GPT_DB_TEST_PG_PORT", default: 5_432) }
    static var postgresUser: String { value("GPT_DB_TEST_PG_USER") ?? "gpt_test" }
    static var postgresDatabase: String { value("GPT_DB_TEST_PG_DB") ?? "gpt_test" }
    static var postgresScratchDatabase: String { value("GPT_DB_TEST_PG_SCRATCH_DB") ?? "gpt_scratch" }

    /// A pinned CA for the MySQL server, when one has been fetched. MySQL 8.4's auto-generated
    /// certificate is self-signed, so system trust cannot validate it and the server name must be
    /// the certificate's own, not the address.
    static var mysqlCAPath: String? { value("GPT_DB_TEST_MYSQL_CA_PATH") }
    static var mysqlTLSServerName: String? { value("GPT_DB_TEST_MYSQL_TLS_SERVER_NAME") }
}

@Suite struct LiveEngineIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPT_DB_TEST_MYSQL_PASSWORDLESS"] == "1"))
    func mysqlPasswordlessCachingSHA2RoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        let host = environment["GPT_DB_TEST_MYSQL_PASSWORDLESS_HOST"] ?? "127.0.0.1"
        let loopbackHosts = ["127.0.0.1", "::1", "localhost"]
        try #require(loopbackHosts.contains(host))
        let port: Int
        if let configuredPort = environment["GPT_DB_TEST_MYSQL_PASSWORDLESS_PORT"] {
            port = try #require(Int(configuredPort))
            try #require((1...65_535).contains(port))
        } else {
            port = 13_306
        }
        // A test user made for this, never root: root is not a credential the tests use, and the
        // old default reached root on whatever MySQL listened on this Mac's 13306.
        let username = try #require(environment["GPT_DB_TEST_MYSQL_PASSWORDLESS_USER"],
                                    "set GPT_DB_TEST_MYSQL_PASSWORDLESS_USER to a passwordless test user")
        try #require(username != "root", "not root: a passwordless test user made for this")
        let engine = MySQLEngine()
        let connection = try await engine.connect(
            host: host,
            port: port,
            username: username,
            password: "",
            database: nil,
            tlsPolicy: .disabled
        )
        do {
            let result = try await connection.execute("SELECT CURRENT_USER(), @@port")
            let row = try #require(result.rows.first)
            #expect(result.rows.count == 1)
            #expect(row.count == 2)
            #expect(row[0].displayString.hasPrefix("\(username)@"))
            #expect(row[1].displayString == String(port))
            #expect(await connection.isConnected)
            try await connection.close()
        } catch {
            try? await connection.close()
            throw error
        }
    }

    /// Metadata lookups bind the schema and table names. They used to splice them in with hand
    /// escaping that doubles backslashes, which is wrong under NO_BACKSLASH_ESCAPES: a name holding
    /// a backslash then matched nothing and the table showed no columns.
    @Test(.enabled(if: LiveDatabaseEnvironment.mysqlPassword != nil))
    func mysqlMetadataLookupsBindNamesUnderNoBackslashEscapes() async throws {
        let password = try #require(LiveDatabaseEnvironment.mysqlPassword)
        let connection = try await MySQLEngine().connect(
            host: LiveDatabaseEnvironment.host,
            port: LiveDatabaseEnvironment.mysqlPort,
            username: LiveDatabaseEnvironment.mysqlUser,
            password: password,
            database: LiveDatabaseEnvironment.mysqlScratchDatabase,
            tlsPolicy: .disabled
        )
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let parent = "gpt_meta_\(suffix)_p"
        let child = "gpt_meta_\(suffix)_it's\\odd"
        let schema = LiveDatabaseEnvironment.mysqlScratchDatabase
        do {
            _ = try await connection.execute("SET SESSION sql_mode = CONCAT(@@sql_mode, ',NO_BACKSLASH_ESCAPES')")
            _ = try await connection.execute("CREATE TABLE \(connection.quotedIdentifier(parent)) (id INT PRIMARY KEY)")
            _ = try await connection.execute(
                "CREATE TABLE \(connection.quotedIdentifier(child)) (id INT PRIMARY KEY, parent_id INT, " +
                "FOREIGN KEY (parent_id) REFERENCES \(connection.quotedIdentifier(parent)) (id))")

            let columns = try await connection.columns(in: child, database: schema)
            #expect(columns.map(\.name) == ["id", "parent_id"])
            let keys = try await connection.foreignKeys(in: child, database: schema)
            #expect(keys.map(\.referencedTable) == [parent])
        } catch {
            Issue.record(error)
        }
        _ = try? await connection.execute("DROP TABLE IF EXISTS \(connection.quotedIdentifier(child))")
        _ = try? await connection.execute("DROP TABLE IF EXISTS \(connection.quotedIdentifier(parent))")
        try? await connection.close()
    }

    @Test(.enabled(if: LiveDatabaseEnvironment.mysqlPassword != nil))
    func mysql8LiveRoundTrip() async throws {
        let password = try #require(LiveDatabaseEnvironment.mysqlPassword)
        let engine = MySQLEngine()
        let connection = try await engine.connect(
            host: LiveDatabaseEnvironment.host,
            port: LiveDatabaseEnvironment.mysqlPort,
            username: LiveDatabaseEnvironment.mysqlUser,
            password: password,
            database: LiveDatabaseEnvironment.mysqlScratchDatabase,
            tlsPolicy: .disabled
        )
        let table = "gpt_live_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let quoted = connection.quotedIdentifier(table)
        _ = try await connection.execute(
            "CREATE TABLE \(quoted) (id BIGINT PRIMARY KEY AUTO_INCREMENT, payload TEXT NOT NULL, amount DECIMAL(40,18), bytes BLOB, flag BOOLEAN)"
        )
        let injection = "x'); DROP TABLE \(table);--"
        let insert = try await connection.execute(
            "INSERT INTO \(quoted) (payload, amount, bytes, flag) VALUES (?, ?, ?, ?)",
            parameters: [
                .string(injection),
                .decimal("12345678901234567890.000000000123456789"),
                .data(Data([0, 255])),
                .bool(true),
            ]
        )
        #expect(insert.affectedRows == 1)
        #expect(insert.lastInsertID != nil)
        let selected = try await connection.execute(
            "SELECT payload, amount, bytes, flag FROM \(quoted) WHERE payload = ?",
            parameters: [.string(injection)]
        )
        #expect(selected.rows.first?[0] == .string(injection))
        #expect(selected.rows.first?[1] == .decimal("12345678901234567890.000000000123456789"))
        #expect(selected.rows.first?[2] == .data(Data([0, 255])))

        try await connection.beginTransaction()
        _ = try await connection.execute(
            "INSERT INTO \(quoted) (payload) VALUES (?)",
            parameters: [.string("rolled back")]
        )
        try await connection.rollbackTransaction()
        #expect(try await connection.rowCount(table: table, database: LiveDatabaseEnvironment.mysqlScratchDatabase) == 1)
        #expect(try await connection.tables(in: LiveDatabaseEnvironment.mysqlScratchDatabase).contains(table))
        #expect(!(try await connection.columns(in: table, database: LiveDatabaseEnvironment.mysqlScratchDatabase)).isEmpty)
        #expect(try await connection.showCreateTable(table, database: LiveDatabaseEnvironment.mysqlScratchDatabase).contains("CREATE TABLE"))
        #expect(!(try await connection.serverVersion()).isEmpty)
        #expect(!(try await connection.explain("SELECT * FROM \(quoted)", parameters: [])).rows.isEmpty)
        _ = try await connection.execute("DROP TABLE \(quoted)")

        let timeoutStart = ContinuousClock.now
        await #expect(throws: DatabaseError.self) {
            try await connection.execute("SELECT SLEEP(5)", parameters: [], timeout: .milliseconds(25))
        }
        #expect(ContinuousClock.now - timeoutStart < .seconds(2))
        #expect(!(await connection.isConnected))

        // A self-signed server must fail system trust. Pointed at the real server, this now tests
        // the policy; pointed at a closed localhost port it only ever tested "connection refused".
        await #expect(throws: Error.self) {
            let tlsConnection = try await engine.connect(
                host: LiveDatabaseEnvironment.host,
                port: LiveDatabaseEnvironment.mysqlPort,
                username: LiveDatabaseEnvironment.mysqlUser,
                password: password,
                database: LiveDatabaseEnvironment.mysqlScratchDatabase,
                tlsPolicy: .requiredSystemTrust
            )
            try await tlsConnection.close()
        }

        // The pinned-CA path, which is what a user with a self-signed server actually uses.
        // D13 was recorded here with `withKnownIssue`; the wrapper is gone because the defect is.
        //
        // Two assertions, and the pair is the point. A stock MySQL 8.4 certificate has no
        // subjectAltName and a CN that is not a DNS name, so every name-matching mode must still
        // fail — including with the CN itself, which NIOSSL rejects as a string before contacting
        // the server. Only the CA-only mode connects. If the first assertion ever stops throwing,
        // the second one is no longer evidence of anything.
        if let caPath = LiveDatabaseEnvironment.mysqlCAPath,
           let serverName = LiveDatabaseEnvironment.mysqlTLSServerName {
            let ca = try Data(contentsOf: URL(fileURLWithPath: caPath))

            await #expect(throws: Error.self, "A CN that is not a DNS name cannot be matched") {
                let tlsConnection = try await engine.connect(
                    host: LiveDatabaseEnvironment.host,
                    port: LiveDatabaseEnvironment.mysqlPort,
                    username: LiveDatabaseEnvironment.mysqlUser,
                    password: password,
                    database: LiveDatabaseEnvironment.mysqlScratchDatabase,
                    tlsPolicy: .requiredCertificates(
                        [DatabaseTLSCertificate(bytes: ca, format: .pem)],
                        serverName: serverName
                    )
                )
                try await tlsConnection.close()
            }

            let tlsConnection = try await engine.connect(
                host: LiveDatabaseEnvironment.host,
                port: LiveDatabaseEnvironment.mysqlPort,
                username: LiveDatabaseEnvironment.mysqlUser,
                password: password,
                database: LiveDatabaseEnvironment.mysqlScratchDatabase,
                tlsPolicy: .requiredCertificatesWithoutHostnameVerification(
                    [DatabaseTLSCertificate(bytes: ca, format: .pem)]
                )
            )
            #expect(await tlsConnection.isConnected)
            // Not merely connected: the session is usable and really is over TLS, which the
            // server reports for its own connection rather than the client asserting it.
            let cipher = try await tlsConnection.execute("SHOW SESSION STATUS LIKE 'Ssl_cipher'", parameters: [])
            #expect(cipher.rows.first?[1] != .string(""))
            #expect(cipher.rows.first?[1] != .null)
            try await tlsConnection.close()

            // The chain is genuinely checked: a syntactically valid CA that did not sign this
            // server must be refused by the same mode. Without this, "CA-only" and "no
            // verification at all" would look identical from the outside.
            await #expect(throws: Error.self, "An unrelated CA must not validate this server") {
                let unrelated = try await engine.connect(
                    host: LiveDatabaseEnvironment.host,
                    port: LiveDatabaseEnvironment.mysqlPort,
                    username: LiveDatabaseEnvironment.mysqlUser,
                    password: password,
                    database: LiveDatabaseEnvironment.mysqlScratchDatabase,
                    tlsPolicy: .requiredCertificatesWithoutHostnameVerification(
                        [DatabaseTLSCertificate(bytes: Data(unrelatedCertificateAuthorityPEM.utf8), format: .pem)]
                    )
                )
                try await unrelated.close()
            }
        }
    }

    @Test(.enabled(if: LiveDatabaseEnvironment.postgresPassword != nil))
    func postgres17LiveRoundTrip() async throws {
        let password = try #require(LiveDatabaseEnvironment.postgresPassword)
        let engine = PostgreSQLEngine()
        let connection = try await engine.connect(
            host: LiveDatabaseEnvironment.host,
            port: LiveDatabaseEnvironment.postgresPort,
            username: LiveDatabaseEnvironment.postgresUser,
            password: password,
            database: LiveDatabaseEnvironment.postgresScratchDatabase,
            tlsPolicy: .disabled
        )
        let table = "gpt_live_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let quoted = connection.quotedIdentifier(table)
        _ = try await connection.execute(
            "CREATE TABLE \(quoted) (id BIGSERIAL PRIMARY KEY, payload TEXT NOT NULL, amount NUMERIC(40,18), bytes BYTEA, document JSONB, flag BOOLEAN)"
        )
        let injection = "x'); DROP TABLE \(table);--"
        let insert = try await connection.execute(
            "INSERT INTO \(quoted) (payload, amount, bytes, document, flag) VALUES ($1, $2, $3, $4, $5)",
            parameters: [
                .string(injection),
                .decimal("12345678901234567890.000000000123456789"),
                .data(Data([0, 255])),
                .json("{\"safe\":true}"),
                .bool(true),
            ]
        )
        #expect(insert.affectedRows == 1)
        let selected = try await connection.execute(
            "SELECT payload, amount, bytes, document, flag FROM \(quoted) WHERE payload = $1",
            parameters: [.string(injection)]
        )
        #expect(selected.rows.first?[0] == .string(injection))
        #expect(selected.rows.first?[1] == .decimal("12345678901234567890.000000000123456789"))
        #expect(selected.rows.first?[2] == .data(Data([0, 255])))
        #expect(selected.rows.first?[3] == .json("{\"safe\": true}"))
        #expect(selected.rows.first?[4] == .bool(true))

        try await connection.beginTransaction()
        _ = try await connection.execute(
            "INSERT INTO \(quoted) (payload) VALUES ($1)",
            parameters: [.string("rolled back")]
        )
        try await connection.rollbackTransaction()
        #expect(try await connection.rowCount(table: table, database: "public") == 1)
        #expect(try await connection.databases().contains("public"))
        #expect(try await connection.tables(in: "public").contains(table))
        #expect(!(try await connection.columns(in: table, database: "public")).isEmpty)
        #expect(!(try await connection.serverVersion()).isEmpty)
        #expect(!(try await connection.explain("SELECT * FROM \(quoted)", parameters: [])).rows.isEmpty)
        await #expect(throws: DatabaseError.self) {
            try await connection.execute(
                "SELECT pg_sleep(1)",
                parameters: [],
                timeout: .milliseconds(10)
            )
        }
        await #expect(throws: DatabaseError.self) {
            try await connection.showCreateTable(table, database: "public")
        }
        _ = try await connection.execute("DROP TABLE \(quoted)")

        let query = Task {
            try await connection.execute("SELECT pg_sleep(5)", parameters: [])
        }
        try await Task.sleep(for: .milliseconds(100))
        let cancellationStart = ContinuousClock.now
        try await connection.cancelCurrentQuery()
        await #expect(throws: Error.self) {
            _ = try await query.value
        }
        #expect(ContinuousClock.now - cancellationStart < .seconds(2))
        #expect(!(await connection.isConnected))

        // As on MySQL: a self-signed server must fail system trust, tested against the real server
        // rather than a closed port that would have thrown for an unrelated reason.
        await #expect(throws: Error.self) {
            let tlsConnection = try await engine.connect(
                host: LiveDatabaseEnvironment.host,
                port: LiveDatabaseEnvironment.postgresPort,
                username: LiveDatabaseEnvironment.postgresUser,
                password: password,
                database: LiveDatabaseEnvironment.postgresScratchDatabase,
                tlsPolicy: .requiredSystemTrust
            )
            try await tlsConnection.close()
        }
    }
}

private struct TestConnection: DatabaseConnection {
    var isConnected: Bool { get async { true } }

    func execute(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        QueryResult(query: query, executionTime: 0)
    }

    func close() async throws {}
    func databases() async throws -> [String] { [] }
    func tables(in database: String) async throws -> [String] { [] }
    func columns(in table: String, database: String) async throws -> [ColumnInfo] { [] }
    func showCreateTable(_ table: String, database: String) async throws -> String { "" }
    func indexes(in table: String, database: String) async throws -> [IndexInfo] { [] }
    func foreignKeys(in table: String, database: String) async throws -> [ForeignKeyInfo] { [] }
    func tableStatus(in database: String) async throws -> [TableStatus] { [] }
    func rowCount(table: String, database: String) async throws -> Int { 0 }
}
