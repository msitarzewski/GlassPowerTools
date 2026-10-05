//
//  LiveDatabaseIntegrationTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  The capability against real servers. Everything else in this target is compiled-and-reasoned;
//  this is the only file that proves the module talks to a database at all.
//
//  Gated on `GPT_DB_TEST_*` the way the engine's own live tests are, so a checkout without the
//  environment skips rather than fails. Credentials come from `~/.config/gpt-db-test.env`, which
//  lives outside the repository and is never read into any note, log or assertion message.
//
//  `gpt_test` holds the seeded `teams`/`members` with a foreign key and is DML-only.
//  `gpt_scratch` is the only place CREATE and DROP are permitted — on MySQL a database-scoped
//  DROP also permits DROP DATABASE, so a test that can drop its own table could drop the fixture.
//  Nothing here writes to `gpt_test`: every test against it reads, or proves a write was refused.
//  One test creates and drops a pair of tables in `gpt_scratch`, and cleans up after itself.
//

import Foundation
import os
import Testing
import GlassDBKit
import GlassShell
import GlassSSHTransport
import GlasSecretStore
@testable import GlassDatabase

private enum LiveDB {
    static func value(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }
    static var host: String { value("GPT_DB_TEST_HOST") ?? "127.0.0.1" }

    static var mysqlPassword: String? { value("GPT_DB_TEST_MYSQL_PASSWORD") }
    static var mysqlPort: Int { value("GPT_DB_TEST_MYSQL_PORT").flatMap(Int.init) ?? 3_306 }
    static var mysqlUser: String { value("GPT_DB_TEST_MYSQL_USER") ?? "gpt_test" }
    static var mysqlDatabase: String { value("GPT_DB_TEST_MYSQL_DB") ?? "gpt_test" }

    static var postgresPassword: String? { value("GPT_DB_TEST_PG_PASSWORD") }
    static var postgresPort: Int { value("GPT_DB_TEST_PG_PORT").flatMap(Int.init) ?? 5_432 }
    static var postgresUser: String { value("GPT_DB_TEST_PG_USER") ?? "gpt_test" }
    static var postgresDatabase: String { value("GPT_DB_TEST_PG_DB") ?? "gpt_test" }
    static var postgresScratchDatabase: String { value("GPT_DB_TEST_PG_SCRATCH_DB") ?? "gpt_scratch" }
    static var mysqlScratchDatabase: String { value("GPT_DB_TEST_MYSQL_SCRATCH_DB") ?? "gpt_scratch" }

    /// Where a test may create and drop: the scratch database on both engines, named as SQL sees
    /// it. On PostgreSQL the namespace inside `gpt_scratch` is `public`; on MySQL it is the
    /// database itself.
    static func scratchNamespace(_ engine: DatabaseEngineType) -> String {
        engine == .postgresql ? "public" : mysqlScratchDatabase
    }

    static func scratchDatabase(_ engine: DatabaseEngineType) -> String {
        engine == .postgresql ? postgresScratchDatabase : mysqlScratchDatabase
    }

    static var hasMySQL: Bool { mysqlPassword != nil }
    static var hasPostgres: Bool { postgresPassword != nil }

    /// The MySQL server's own CA, fetched to `~/.config` by the wave-1 VM setup, and the CN on
    /// its auto-generated certificate. Never read into a note or an assertion message.
    static var mysqlCAPath: String? { value("GPT_DB_TEST_MYSQL_CA_PATH") }
    static var mysqlTLSServerName: String? { value("GPT_DB_TEST_MYSQL_TLS_SERVER_NAME") }
    static var hasMySQLCA: Bool { hasMySQL && mysqlCAPath != nil && mysqlTLSServerName != nil }

    /// The service record the capability would have written for this engine, built the way
    /// `DatabaseServiceDraft.configuration(id:address:name:)` builds it — the host's address on
    /// the record, no SSH fields anywhere.
    static func config(_ engine: DatabaseEngineType, readOnly: Bool = false,
                       usesHostTunnel: Bool = false) -> DatabaseConnectionConfig {
        switch engine {
        case .mysql:
            DatabaseConnectionConfig(name: "Live MySQL", engine: .mysql, host: host, port: mysqlPort,
                                     username: mysqlUser, defaultDatabase: mysqlDatabase,
                                     usesHostTunnel: usesHostTunnel, isReadOnly: readOnly)
        case .postgresql:
            DatabaseConnectionConfig(name: "Live PostgreSQL", engine: .postgresql, host: host,
                                     port: postgresPort, username: postgresUser,
                                     defaultDatabase: postgresDatabase,
                                     usesHostTunnel: usesHostTunnel, isReadOnly: readOnly)
        case .sqlite:
            DatabaseConnectionConfig(name: "unused", engine: .sqlite, host: "", port: 0, username: "")
        }
    }

    static func password(_ engine: DatabaseEngineType) -> String {
        switch engine {
        case .mysql: mysqlPassword ?? ""
        case .postgresql: postgresPassword ?? ""
        case .sqlite: ""
        }
    }

    /// PostgreSQL's `databases()` reports schemas, so the namespace holding the fixture is
    /// `public` there and the database name on MySQL. Modelling that honestly is the whole
    /// reason the survey flagged it.
    static func fixtureNamespace(_ engine: DatabaseEngineType) -> String {
        engine == .postgresql ? "public" : mysqlDatabase
    }
}

@MainActor
@Suite("Live database (gated)", .serialized)
struct LiveDatabaseIntegrationTests {

    /// Reconnect works on an ordinary direct connection.
    ///
    /// **Nothing had ever exercised `reconnect`** — there was no test of it anywhere, tunnelled or
    /// direct — so this exists to say which of the two is broken when one of them is. It is the
    /// discriminator for the tunnelled case in `LiveTunnelIntegrationTests`.
    /// **Disabled deliberately — read the reason before enabling it.**
    ///
    /// `reconnect` does not reuse the password it was given; it re-reads one from the Keychain via
    /// `storedCredentials`. These tests pass the password straight to `connect` and never store it,
    /// so reconnect authenticates with an **empty** password — `storedCredentials` catches
    /// `SecretStoreError.notFound` and substitutes `""` rather than reporting it
    /// (`DatabaseSessionManager.swift:994-996`). PostgreSQL then rejects the login and PostgresNIO
    /// trips its own "PostgresConnection deinitialized before being closed" assertion, which
    /// **aborts the process** instead of failing the test.
    ///
    /// Making this runnable means writing a credential to the real Keychain, and since 2026-09-13
    /// credentials synchronize (D18/D21) — a test password would propagate to the user's own
    /// devices. That is not a side effect a test may have. The honest options are a fake credential
    /// store behind the `store:` seam that already exists on the mutation entry points, or running
    /// this by hand against a connection the user has saved.
    @Test("A direct connection reconnects", .disabled("needs a stored credential; see the note above"),
          .enabled(if: LiveDB.hasPostgres))
    func directReconnect() async throws {
        let (manager, sessionID, _) = try await connect(.postgresql)
        try await manager.reconnect(sessionID: sessionID)

        let session = try #require(manager.sessions[sessionID])
        #expect(session.state.isConnected, "the session reconnects")

        let result = try await manager.executeQuery("SELECT * FROM teams", sessionID: sessionID,
                                                    editorRowLimit: 100)
        #expect(result.error == nil)
        #expect(!result.rows.isEmpty, "real rows through the reconnected transport")

        await manager.disconnect(sessionID: sessionID)
    }

    /// Connects through the session manager — the capability's own connect path, minus only the
    /// window the bootstrap would open — and hands the session back for inspection.
    private func connect(_ engine: DatabaseEngineType, readOnly: Bool = false,
                         openForward: DatabaseSessionManager.PortForwardProvider? = nil)
    async throws -> (DatabaseSessionManager, UUID, any DatabaseConnection) {
        let manager = DatabaseSessionManager(loadImmediately: false)
        let sessionID = try await manager.connect(config: LiveDB.config(engine, readOnly: readOnly,
                                                                       usesHostTunnel: openForward != nil),
                                                  password: LiveDB.password(engine),
                                                  openForward: openForward)
        let session = try #require(manager.sessions[sessionID])
        #expect(session.state.isConnected)
        let connection = try #require(session.connection)
        return (manager, sessionID, connection)
    }

    // MARK: 1 — a direct connection to both engines, through the capability's path

    @Test("MySQL: the capability connects directly and reports a real server version",
          .enabled(if: LiveDB.hasMySQL))
    func mysqlConnects() async throws {
        let (manager, sessionID, connection) = try await connect(.mysql)
        let version = try await connection.serverVersion()
        #expect(!version.isEmpty)
        #expect(connection.dialect == .mysql)
        await manager.disconnect(sessionID: sessionID)
        #expect(manager.sessions[sessionID] == nil, "disconnect tears the session down")
    }

    @Test("PostgreSQL: the capability connects directly and reports a real server version",
          .enabled(if: LiveDB.hasPostgres))
    func postgresConnects() async throws {
        let (manager, sessionID, connection) = try await connect(.postgresql)
        let version = try await connection.serverVersion()
        #expect(!version.isEmpty)
        #expect(connection.dialect == .postgresql)
        await manager.disconnect(sessionID: sessionID)
    }

    // MARK: 1b — D13: a saved service that pins the server's CA actually connects

    /// The end of R7, through the capability's own path rather than the engine's.
    ///
    /// This is the test that matters: `GlassDBKitTests` proves the *engine* can do VERIFY_CA, and
    /// this proves a **saved record** carrying the user's choice reaches it — record →
    /// `transportPlan` → policy → real server. Until `transportPlan` mapped the mode, every piece
    /// existed and nothing joined them, and only a test at this level could tell the difference.
    @Test("MySQL: a service pinning the server's CA connects, and the server confirms it is TLS",
          .enabled(if: LiveDB.hasMySQLCA))
    func mysqlPinnedCertificateAuthorityConnects() async throws {
        let caPath = try #require(LiveDB.mysqlCAPath)
        let ca = try Data(contentsOf: URL(fileURLWithPath: caPath))

        var config = LiveDB.config(.mysql)
        config.useTLS = true
        config.tlsVerification = .pinnedCertificateAuthorityOnly
        config.tlsCertificate = ca

        let manager = DatabaseSessionManager(loadImmediately: false)
        let sessionID = try await manager.connect(config: config, password: LiveDB.password(.mysql))
        let connection = try #require(manager.sessions[sessionID]?.connection)

        // Not "it connected": the server is asked what it negotiated for this very session, so a
        // silently plaintext connection could not pass.
        let cipher = try await connection.execute("SHOW SESSION STATUS LIKE 'Ssl_cipher'", parameters: [])
        let negotiated = try #require(cipher.rows.first?[1])
        #expect(negotiated != .string(""), "an empty Ssl_cipher means the session is not encrypted")
        #expect(negotiated != .null)

        // And it is a working session, not merely an open socket.
        #expect(!(try await connection.serverVersion()).isEmpty)
        await manager.disconnect(sessionID: sessionID)
    }

    @Test("MySQL: the same service verifying the name still fails — the pair is the evidence",
          .enabled(if: LiveDB.hasMySQLCA))
    func mysqlPinnedCertificateWithNameStillFails() async throws {
        let caPath = try #require(LiveDB.mysqlCAPath)
        let ca = try Data(contentsOf: URL(fileURLWithPath: caPath))

        // A stock MySQL 8.4 certificate has no subjectAltName and a CN that is not a DNS name.
        // If this ever stops failing, the CA-only mode has stopped being necessary — and the test
        // above stops being evidence that it works.
        var config = LiveDB.config(.mysql)
        config.useTLS = true
        config.tlsVerification = .pinnedCertificate
        config.tlsCertificate = ca

        let manager = DatabaseSessionManager(loadImmediately: false)
        await #expect(throws: (any Error).self) {
            _ = try await manager.connect(config: config, password: LiveDB.password(.mysql))
        }
    }

    @Test("A pinned service whose certificate is missing refuses rather than connecting weaker",
          .enabled(if: LiveDB.hasMySQL))
    func mysqlPinnedWithoutCertificateRefuses() async throws {
        var config = LiveDB.config(.mysql)
        config.useTLS = true
        config.tlsVerification = .pinnedCertificateAuthorityOnly
        config.tlsCertificate = nil

        let manager = DatabaseSessionManager(loadImmediately: false)
        await #expect(throws: (any Error).self) {
            _ = try await manager.connect(config: config, password: LiveDB.password(.mysql))
        }
        // Against a real, reachable server: the refusal is the policy's, not the network's, and
        // no session is left behind that a caller could mistake for a working one.
        #expect(manager.sessions.isEmpty)
    }

    // MARK: 2 — what the schema browser shows: the seeded tables and the foreign key

    @Test("MySQL: the seeded tables and the members → teams foreign key are visible",
          .enabled(if: LiveDB.hasMySQL))
    func mysqlSchemaAndForeignKey() async throws {
        let (manager, sessionID, connection) = try await connect(.mysql)
        defer { Task { await manager.disconnect(sessionID: sessionID) } }

        let namespace = LiveDB.fixtureNamespace(.mysql)
        let databases = try await connection.databases()
        #expect(databases.contains(namespace))

        let tables = try await connection.tables(in: namespace)
        #expect(tables.contains("teams"))
        #expect(tables.contains("members"))

        let keys = try await connection.foreignKeys(in: "members", database: namespace)
        let toTeams = try #require(keys.first { $0.referencedTable == "teams" })
        #expect(!toTeams.constraintName.isEmpty)
        #expect(!toTeams.columnName.isEmpty)
        #expect(!toTeams.referencedColumn.isEmpty)
    }

    @Test("The schema diagram reads the seeded tables and draws members → teams", .enabled(if: LiveDB.hasMySQL || LiveDB.hasPostgres),
          arguments: [DatabaseEngineType.mysql, .postgresql])
    func schemaDiagramOnRealServers(engine: DatabaseEngineType) async throws {
        guard engine == .mysql ? LiveDB.hasMySQL : LiveDB.hasPostgres else { return }
        let (manager, sessionID, connection) = try await connect(engine)
        defer { Task { await manager.disconnect(sessionID: sessionID) } }
        let namespace = engine == .postgresql ? "public" : LiveDB.fixtureNamespace(.mysql)

        let diagram = try await SchemaDiagramLoader.load(connection: connection, database: namespace)
        #expect(diagram.table(named: "teams") != nil && diagram.table(named: "members") != nil)
        let key = try #require(diagram.relationships.first { $0.fromTable == "members" && $0.toTable == "teams" })
        #expect(!key.fromColumns.isEmpty && key.fromColumns.count == key.toColumns.count)
        #expect(key.toColumns.allSatisfy { !$0.isEmpty && $0 != "NULL" })
        let members = try #require(diagram.table(named: "members"))
        #expect(members.columns.contains { $0.isForeignKey && key.fromColumns.contains($0.name) })
        #expect(diagram.table(named: "teams")?.columns.contains(where: \.isPrimaryKey) == true)
    }

    @Test("PostgreSQL: databases() reports schemas, and the foreign key is visible in `public`",
          .enabled(if: LiveDB.hasPostgres))
    func postgresSchemaAndForeignKey() async throws {
        let (manager, sessionID, connection) = try await connect(.postgresql)
        defer { Task { await manager.disconnect(sessionID: sessionID) } }

        // The survey's finding, confirmed against a real server rather than read from the code:
        // this returns schemas, not databases, so the browser must label it as schemas.
        let namespaces = try await connection.databases()
        #expect(namespaces.contains("public"))
        #expect(!namespaces.contains("information_schema"))

        let tables = try await connection.tables(in: "public")
        #expect(tables.contains("teams"))
        #expect(tables.contains("members"))

        // This assertion found a real defect and now guards the fix. The adapter used to inner-join
        // `information_schema.constraint_column_usage`, which PostgreSQL restricts to tables the
        // current user **owns**: the constraint was visible in `table_constraints` and invisible in
        // `constraint_column_usage`, the join dropped it, and the Foreign Keys tab rendered empty —
        // indistinguishable from a table that genuinely has none, for exactly the least-privilege
        // accounts a careful user connects with. The adapter now reads `pg_catalog`. The test user
        // deliberately does **not** own these tables; that is the condition under test, so do not
        // "simplify" it by seeding as the connecting account.
        let keys = try await connection.foreignKeys(in: "members", database: "public")
        let toTeams = try #require(keys.first { $0.referencedTable == "teams" })
        #expect(!toTeams.constraintName.isEmpty)
        #expect(toTeams.columnName == "team_id")
        #expect(toTeams.referencedColumn == "id")
    }

    @Test("PostgreSQL: a composite foreign key pairs its columns rather than crossing them",
          .enabled(if: LiveDB.hasPostgres))
    func postgresCompositeForeignKeyPairsColumns() async throws {
        // Connect to the **scratch** database: `gpt_test` is DML-only and holds the fixture, and
        // nothing here may risk it.
        var scratchConfig = LiveDB.config(.postgresql)
        scratchConfig.defaultDatabase = LiveDB.postgresScratchDatabase
        let manager = DatabaseSessionManager(loadImmediately: false)
        let sessionID = try await manager.connect(config: scratchConfig,
                                                  password: LiveDB.password(.postgresql))
        defer { Task { await manager.disconnect(sessionID: sessionID) } }
        let connection = try #require(manager.sessions[sessionID]?.connection)

        // The second defect the live run found, and the one the privilege fix also resolves:
        // the old query joined the referenced columns with **no ordinal correlation**, so a
        // two-column key `(x, y) → (a, b)` came back as a four-row cross product asserting
        // `x → b` and `y → a`. Empty is merely unhelpful; this was confidently wrong, and
        // foreign-key navigation built on it would have followed the wrong column.
        //
        // Proven at the time against a table the account owned, so privileges were not the
        // cause. Nothing else covers this, so it is guarded here.
        func exec(_ sql: String) async throws {
            _ = try await connection.execute(sql, parameters: [])
        }
        // Cleanup is awaited, not deferred into a detached `Task`: a `defer { Task { … } }` is
        // not awaited before the test ends, and an earlier version of this test left a table
        // behind in the scratch database because of exactly that. Child first — the foreign key
        // depends on the parent.
        func dropFixtures() async {
            _ = try? await connection.execute("DROP TABLE IF EXISTS gpt_fk_child", parameters: [])
            _ = try? await connection.execute("DROP TABLE IF EXISTS gpt_fk_parent", parameters: [])
        }
        await dropFixtures()
        try await exec("CREATE TABLE gpt_fk_parent (a int, b int, PRIMARY KEY (a, b))")
        try await exec("""
            CREATE TABLE gpt_fk_child (x int, y int,
              CONSTRAINT gpt_fk_two FOREIGN KEY (x, y) REFERENCES gpt_fk_parent (a, b))
            """)

        let keys = try await connection.foreignKeys(in: "gpt_fk_child", database: "public")
            .filter { $0.constraintName == "gpt_fk_two" }
            .sorted { $0.ordinalPosition < $1.ordinalPosition }

        #expect(keys.count == 2, "a two-column key is two rows, not a four-row cross product")
        #expect(keys.map(\.columnName) == ["x", "y"])
        #expect(keys.map(\.referencedColumn) == ["a", "b"], "x pairs with a and y with b")
        #expect(keys.map(\.ordinalPosition) == [1, 2])

        await dropFixtures()
        let remaining = try await connection.execute(
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'gpt_fk_%'",
            parameters: [])
        #expect(remaining.rows.isEmpty, "the scratch database is left as it was found")
    }

    // MARK: 3 — a query returning real rows

    @Test("MySQL: a SELECT through the session manager returns the seeded rows",
          .enabled(if: LiveDB.hasMySQL))
    func mysqlQueryReturnsRows() async throws {
        let (manager, sessionID, _) = try await connect(.mysql)
        defer { Task { await manager.disconnect(sessionID: sessionID) } }

        let result = try await manager.executeQuery("SELECT * FROM teams", sessionID: sessionID,
                                                    editorRowLimit: 100)
        #expect(result.error == nil)
        #expect(!result.columns.isEmpty)
        #expect(!result.rows.isEmpty, "the fixture seeds teams")
    }

    @Test("PostgreSQL: a SELECT through the session manager returns the seeded rows",
          .enabled(if: LiveDB.hasPostgres))
    func postgresQueryReturnsRows() async throws {
        let (manager, sessionID, _) = try await connect(.postgresql)
        defer { Task { await manager.disconnect(sessionID: sessionID) } }

        let result = try await manager.executeQuery("SELECT * FROM members", sessionID: sessionID,
                                                    editorRowLimit: 100)
        #expect(result.error == nil)
        #expect(!result.rows.isEmpty)
    }

    // MARK: 4 — the read-only guard, against a real server
    //
    // The claim a user's data depends on. The unit tests prove the wrapper classifies; only this
    // proves that a service marked read-only leaves a real table unchanged — including through
    // the direct `connection.execute` route that five of the app's write paths use and that a
    // guard in the session manager would never have seen.

    @Test("MySQL: a read-only service refuses a real UPDATE, and the row is provably unchanged",
          .enabled(if: LiveDB.hasMySQL))
    func mysqlReadOnlyRefusesARealWrite() async throws {
        try await readOnlyRefusesARealWrite(.mysql)
    }

    @Test("PostgreSQL: a read-only service refuses a real UPDATE, and the row is provably unchanged",
          .enabled(if: LiveDB.hasPostgres))
    func postgresReadOnlyRefusesARealWrite() async throws {
        try await readOnlyRefusesARealWrite(.postgresql)
    }

    private func readOnlyRefusesARealWrite(_ engine: DatabaseEngineType) async throws {
        let namespace = LiveDB.fixtureNamespace(engine)

        // Read the current state through an ordinary session.
        let (reader, readerID, readerConnection) = try await connect(engine)
        defer { Task { await reader.disconnect(sessionID: readerID) } }
        let quote = readerConnection.identifierQuoteCharacter
        let table = "\(quote)teams\(quote)"
        let before = try await reader.executeQuery("SELECT * FROM \(table) ORDER BY 1",
                                                   sessionID: readerID, editorRowLimit: 100)
        #expect(!before.rows.isEmpty)

        // Now a read-only session over the same database.
        let (guarded, guardedID, guardedConnection) = try await connect(engine, readOnly: true)
        defer { Task { await guarded.disconnect(sessionID: guardedID) } }
        #expect(guardedConnection is ReadOnlyDatabaseConnection,
                "a read-only service must be handed the guarded connection")

        let update = "UPDATE \(table) SET \(quote)name\(quote) = 'read-only guard breach' WHERE 1=1"

        // Through the session manager, as the query editor would.
        await #expect(throws: ReadOnlyServiceError.self) {
            _ = try await guarded.executeQuery(update, sessionID: guardedID, editorRowLimit: 100)
        }
        // And straight at the driver, as the grid, record editor and schema tools do. This is the
        // route a session-manager guard would have missed entirely.
        await #expect(throws: ReadOnlyServiceError.self) {
            _ = try await guardedConnection.execute(update, parameters: [])
        }
        await #expect(throws: ReadOnlyServiceError.self) {
            _ = try await guardedConnection.execute("DELETE FROM \(table)", parameters: [])
        }

        // The server's own state is the only proof that matters.
        let after = try await reader.executeQuery("SELECT * FROM \(table) ORDER BY 1",
                                                  sessionID: readerID, editorRowLimit: 100)
        #expect(after.rows.count == before.rows.count)
        #expect(after.rows.map(\.description) == before.rows.map(\.description),
                "the read-only service must have left every row exactly as it was")

        // A read on the guarded session still works: read-only is not disconnected.
        let stillReadable = try await guarded.executeQuery("SELECT * FROM \(table)",
                                                           sessionID: guardedID, editorRowLimit: 10)
        #expect(stillReadable.error == nil)
        #expect(!stillReadable.rows.isEmpty)
        _ = namespace
    }
}

// MARK: - 4b. Row deletion against a real server
//
// `RowMutationSQLTests` proves the SQL's shape. Only this proves what the guard is actually for:
// that a real server reports **exactly one** affected row for a real delete, and **zero** for a
// predicate that has gone stale — which is the whole optimistic conflict check, and the only
// evidence that deletion cannot quietly remove more than the user chose.
//
// Everything here happens in `gpt_scratch`. `gpt_test` holds the fixture and is DML-only; a
// deletion test must never point at it.

@MainActor
@Suite("Live row deletion (gated)", .serialized)
struct LiveRowDeletionTests {

    @Test("MySQL: a delete affects exactly one row, and a stale predicate affects none",
          .enabled(if: LiveDB.hasMySQL))
    func mysqlDeleteAffectsExactlyOneRow() async throws {
        try await deleteAffectsExactlyOneRow(.mysql)
    }

    @Test("PostgreSQL: a delete affects exactly one row, and a stale predicate affects none",
          .enabled(if: LiveDB.hasPostgres))
    func postgresDeleteAffectsExactlyOneRow() async throws {
        try await deleteAffectsExactlyOneRow(.postgresql)
    }

    private func deleteAffectsExactlyOneRow(_ engine: DatabaseEngineType) async throws {
        var config = LiveDB.config(engine)
        config.defaultDatabase = LiveDB.scratchDatabase(engine)
        let manager = DatabaseSessionManager(loadImmediately: false)
        let sessionID = try await manager.connect(config: config, password: LiveDB.password(engine))
        defer { Task { await manager.disconnect(sessionID: sessionID) } }
        let connection = try #require(manager.sessions[sessionID]?.connection)
        let namespace = LiveDB.scratchNamespace(engine)
        let quote = connection.identifierQuoteCharacter
        let table = "gpt_delete_probe"
        let qualified = "\(quote)\(namespace)\(quote).\(quote)\(table)\(quote)"

        func exec(_ sql: String, _ parameters: [DatabaseValue] = []) async throws -> QueryResult {
            try await connection.execute(sql, parameters: parameters)
        }
        // Awaited, not deferred into a detached Task — the composite-key test above was left
        // behind by exactly that mistake once already.
        func dropProbe() async {
            _ = try? await connection.execute("DROP TABLE IF EXISTS \(qualified)", parameters: [])
        }
        await dropProbe()

        let textType = engine == .postgresql ? "text" : "varchar(40)"
        _ = try await exec("CREATE TABLE \(qualified) (id int PRIMARY KEY, name \(textType), score int)")
        _ = try await exec("INSERT INTO \(qualified) (id, name, score) VALUES (1, 'one', 10)")
        _ = try await exec("INSERT INTO \(qualified) (id, name, score) VALUES (2, 'two', 20)")
        _ = try await exec("INSERT INTO \(qualified) (id, name, score) VALUES (3, NULL, 30)")

        let columns = try await connection.columns(in: table, database: namespace)
        #expect(columns.contains { $0.name == "id" && $0.isPrimaryKey },
                "the probe must have a primary key or the predicate builder refuses outright")

        // The row exactly as the grid would hold it, in the column order the metadata gives.
        func probeRow(id: Int64, name: DatabaseValue, score: Int64) -> [DatabaseValue] {
            columns.map { column in
                switch column.name {
                case "id": return .int(id)
                case "name": return name
                default: return .int(score)
                }
            }
        }

        // 1 — a current row deletes, and the server says exactly one.
        let statement = try RowMutationSQL.delete(
            database: namespace, table: table, columns: columns,
            row: probeRow(id: 2, name: .string("two"), score: 20),
            identifierQuote: quote, dialect: connection.dialect)
        let deleted = try await exec(statement.sql, statement.predicate.parameters)
        #expect(deleted.error == nil)
        #expect(deleted.affectedRows == 1, "exactly one row, which is the guard the UI enforces")

        let afterDelete = try await exec("SELECT id FROM \(qualified) ORDER BY id")
        #expect(afterDelete.rows.count == 2)
        #expect(!afterDelete.rows.contains { $0.first?.displayString == "2" }, "row 2 is the one that went")

        // 2 — a NULL column takes part in the predicate as IS NULL, and still matches its row.
        let nullStatement = try RowMutationSQL.delete(
            database: namespace, table: table, columns: columns,
            row: probeRow(id: 3, name: .null, score: 30),
            identifierQuote: quote, dialect: connection.dialect)
        #expect(nullStatement.sql.contains("IS NULL"), "a NULL is compared, never bound as a parameter")
        let deletedNull = try await exec(nullStatement.sql, nullStatement.predicate.parameters)
        #expect(deletedNull.affectedRows == 1, "`= NULL` would have matched nothing; IS NULL matches the row")

        // 3 — the optimistic check. Someone else edits row 1; the grid still holds the old values.
        _ = try await exec("UPDATE \(qualified) SET \(quote)score\(quote) = 99 WHERE \(quote)id\(quote) = 1")
        let staleStatement = try RowMutationSQL.delete(
            database: namespace, table: table, columns: columns,
            row: probeRow(id: 1, name: .string("one"), score: 10),
            identifierQuote: quote, dialect: connection.dialect)
        let staleDelete = try await exec(staleStatement.sql, staleStatement.predicate.parameters)
        #expect(staleDelete.affectedRows == 0,
                "a row changed underneath the user matches no predicate, so the UI's == 1 guard fails it")

        let survivors = try await exec("SELECT id, score FROM \(qualified) ORDER BY id")
        #expect(survivors.rows.count == 1, "the concurrently edited row is still there")
        #expect(survivors.rows.first?.last?.displayString == "99", "and still carries the other edit")

        await dropProbe()
        let remaining = try await connection.tables(in: namespace)
        #expect(!remaining.contains(table), "the scratch database is left as it was found")
    }
}

// MARK: - 4c. Following a composite foreign key, end to end against a real server
//
// The unit tests prove the pairing logic against the exact cross product the PostgreSQL adapter
// used to return. This proves the whole chain on a live server: real `foreignKeys()` rows → real
// ordinals → `ForeignKeyNavigation.relationships` → `filters(following:)` → the browsing SELECT
// the grid builds → the row that actually comes back.
//
// The fixture is built so a wrong pairing returns **a different real row** rather than nothing:
// the parent holds both `(1, 2)` and `(2, 1)`. Swapping the pairs — which is precisely what the
// cross-product defect did — lands on a row that exists, so the failure would have been silent and
// confident rather than empty. Everything happens in `gpt_scratch`.

@MainActor
@Suite("Live foreign-key navigation (gated)", .serialized)
struct LiveForeignKeyNavigationTests {

    @Test("MySQL: a composite key opens the one row it references, not the transposed one",
          .enabled(if: LiveDB.hasMySQL))
    func mysqlCompositeFollow() async throws {
        try await compositeFollowLandsOnOneRow(.mysql)
    }

    @Test("PostgreSQL: a composite key opens the one row it references, not the transposed one",
          .enabled(if: LiveDB.hasPostgres))
    func postgresCompositeFollow() async throws {
        try await compositeFollowLandsOnOneRow(.postgresql)
    }

    private func compositeFollowLandsOnOneRow(_ engine: DatabaseEngineType) async throws {
        var config = LiveDB.config(engine)
        config.defaultDatabase = LiveDB.scratchDatabase(engine)
        let manager = DatabaseSessionManager(loadImmediately: false)
        let sessionID = try await manager.connect(config: config, password: LiveDB.password(engine))
        defer { Task { await manager.disconnect(sessionID: sessionID) } }
        let connection = try #require(manager.sessions[sessionID]?.connection)
        let namespace = LiveDB.scratchNamespace(engine)
        let quote = connection.identifierQuoteCharacter
        func qualified(_ table: String) -> String {
            "\(quote)\(namespace)\(quote).\(quote)\(table)\(quote)"
        }
        func exec(_ sql: String, _ parameters: [DatabaseValue] = []) async throws -> QueryResult {
            try await connection.execute(sql, parameters: parameters)
        }
        // Child first: the foreign key depends on the parent. Awaited, never deferred.
        func dropFixtures() async {
            _ = try? await connection.execute("DROP TABLE IF EXISTS \(qualified("gpt_nav_child"))", parameters: [])
            _ = try? await connection.execute("DROP TABLE IF EXISTS \(qualified("gpt_nav_parent"))", parameters: [])
        }
        await dropFixtures()

        let textType = engine == .postgresql ? "text" : "varchar(40)"
        _ = try await exec("""
            CREATE TABLE \(qualified("gpt_nav_parent"))
              (a int, b int, label \(textType), PRIMARY KEY (a, b))
            """)
        // Both (1, 2) and (2, 1) exist, so a transposed pairing finds a real, wrong row.
        _ = try await exec("INSERT INTO \(qualified("gpt_nav_parent")) (a, b, label) VALUES (1, 1, 'one-one')")
        _ = try await exec("INSERT INTO \(qualified("gpt_nav_parent")) (a, b, label) VALUES (1, 2, 'one-two')")
        _ = try await exec("INSERT INTO \(qualified("gpt_nav_parent")) (a, b, label) VALUES (2, 1, 'two-one')")
        _ = try await exec("""
            CREATE TABLE \(qualified("gpt_nav_child"))
              (x int PRIMARY KEY, y int, name \(textType),
               CONSTRAINT gpt_nav_two FOREIGN KEY (x, y) REFERENCES \(qualified("gpt_nav_parent")) (a, b))
            """)
        _ = try await exec("INSERT INTO \(qualified("gpt_nav_child")) (x, y, name) VALUES (1, 2, 'child')")

        // 1 — the real catalog, through the real adapter.
        let keys = try await connection.foreignKeys(in: "gpt_nav_child", database: namespace)
        let relationships = ForeignKeyNavigation.relationships(from: keys)
            .filter { $0.constraintName == "gpt_nav_two" }
        let relationship = try #require(relationships.first,
                                        "a live composite key must survive the ordinal check")
        #expect(relationship.isComposite)
        #expect(relationship.pairs.map(\.column) == ["x", "y"])
        #expect(relationship.pairs.map(\.referencedColumn) == ["a", "b"],
                "x pairs with a and y with b, on a real server")

        // 2 — the row the user would have selected, as the grid holds it.
        let childColumns = try await connection.columns(in: "gpt_nav_child", database: namespace)
        let parentColumns = try await connection.columns(in: "gpt_nav_parent", database: namespace)
        let childRows = try await exec("SELECT * FROM \(qualified("gpt_nav_child"))")
        let childRow = try #require(childRows.rows.first)

        let filters = try ForeignKeyNavigation.filters(
            following: relationship, row: childRow,
            columns: childColumns, referencedColumns: parentColumns)
        #expect(filters.map(\.columnName) == ["a", "b"])
        #expect(filters.map(\.value) == ["1", "2"])

        // 3 — the browsing SELECT the grid builds from those filters, run for real.
        let query = try GridServerQueryBuilder.select(
            database: namespace, table: "gpt_nav_parent", columns: parentColumns,
            filters: filters, sorts: [], page: 1, pageSize: 100,
            identifierQuote: quote, dialect: connection.dialect)
        let opened = try await exec(query.sql, query.parameters)
        #expect(opened.error == nil)
        #expect(opened.rows.count == 1, "a composite follow lands on exactly one row")

        let labelIndex = try #require(opened.columns.firstIndex { $0.name == "label" })
        let label = opened.rows[0][labelIndex].displayString
        #expect(label == "one-two")
        #expect(label != "two-one",
                "the transposed pairing the old adapter produced would have opened this row instead")

        await dropFixtures()
        let remaining = try await connection.tables(in: namespace)
        #expect(!remaining.contains("gpt_nav_child"))
        #expect(!remaining.contains("gpt_nav_parent"))
    }
}

// MARK: - 5. The D7 tunnel, over a real SSH forward to a real database
//
// The seam this whole stage turns on: the session manager asks for a forward, something else
// entirely opens it, and the driver connects to the local end. Here the forward is a genuine
// `-L` over SSH to the VM, opened the way `GlassTerminalCapability.openPortForward` opens one —
// but built here rather than imported, because `GlassDatabase` must never import `GlassTerminal`
// and this test is held to the same rule as the module it tests.
//
// Gated on `GPT_SSH_TEST_*` in addition to the database variables.

private enum LiveTunnel {
    static func value(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }
    static var host: String? { value("GPT_SSH_TEST_HOST") }
    static var user: String? { value("GPT_SSH_TEST_USER") }
    static var port: Int { value("GPT_SSH_TEST_PORT").flatMap(Int.init) ?? 22 }
    static var keyPath: String? { value("GPT_SSH_TEST_KEY_PATH") }
    static var isConfigured: Bool { host != nil && user != nil && keyPath != nil }
}

private struct TunnelKeyResolver: SSHCredentialResolver {
    func resolve(_ reference: SSHCredentialReference, for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential {
        guard let keyPath = LiveTunnel.keyPath else {
            throw SSHTransportError.credentialUnavailable("no test key")
        }
        return .privateKey(SSHKeyMaterial(privateKey: SecureBytes(try Data(contentsOf: URL(fileURLWithPath: keyPath))),
                                          passphrase: nil))
    }
}

/// Trusts only for this run and pins nothing, so a test never writes to the real trust store.
private struct TrustForThisRun: SSHHostTrustDecider {
    func decide(_ challenge: SSHHostTrustChallenge) async -> SSHHostTrustDecision { .trust(remember: false) }
}

/// The same `GlassHostPortForward` shape `GlassTerminalPortForward` has, over a real tunnel.
private final class LiveForward: GlassHostPortForward {
    let localPort: Int
    private let tunnel: SSHTunnel
    private let transport: SSHTransport
    private let owner: UUID
    /// Whether `close()` actually ran.
    ///
    /// The distinction this records is the whole point of the reconnect test: dropping the last
    /// reference to an `SSHTunnel` closes its listener through deinit, so the port stops accepting
    /// and everything *looks* tidy — while `close()` never runs and the transport is never
    /// released. Only an explicit flag tells "closed" apart from "collected".
    private let closed = OSAllocatedUnfairLock(initialState: false)
    var isClosed: Bool { closed.withLock { $0 } }

    init(tunnel: SSHTunnel, transport: SSHTransport, owner: UUID) {
        localPort = tunnel.localPort
        self.tunnel = tunnel
        self.transport = transport
        self.owner = owner
    }
    func close() async {
        closed.withLock { $0 = true }
        await tunnel.close()
        await transport.release(owner: owner)
    }
}

@MainActor
@Suite("Live tunnel (gated)", .serialized)
struct LiveTunnelIntegrationTests {

    /// Opens a real forward to `127.0.0.1:port` as the VM sees it — D7's exact call.
    private func openForward(to port: Int) async throws -> any GlassHostPortForward {
        let endpoint = SSHEndpoint(host: LiveTunnel.host!, port: LiveTunnel.port, username: LiveTunnel.user!)
        let hop = SSHHop(displayName: "tunnel host", endpoint: endpoint, credential: .custom("live-tunnel"),
                         options: SSHConnectionOptions(keepAliveInterval: 15))
        let transport = SSHTransport(route: SSHRoute(target: hop), credentials: TunnelKeyResolver(),
                                     trustStore: InMemoryHostTrustStore(), trustDecider: TrustForThisRun())
        let owner = UUID()
        _ = await transport.acquire(owner: owner)
        try await transport.connect()
        let tunnel = try await transport.forward(localPort: 0, toHost: "127.0.0.1", port: port)
        return LiveForward(tunnel: tunnel, transport: transport, owner: owner)
    }

    /// A measurement, not a pass mark (2026-10-05: 100 rows of serialized cache values took 9.5 s
    /// through a tunnel to a production server). 100 rows of 512 KB, read with the app's own MySQL
    /// path directly and through a real forward, so the app's share of a slow read can be seen.
    /// Writes only a table of its own in the scratch database, and drops it.
    @Test("MySQL: large rows, directly and through the tunnel (probe)",
          .enabled(if: LiveTunnel.isConfigured && LiveDB.hasMySQL && ProcessInfo.processInfo.environment["GPT_DB_PERF_PROBE"] != nil))
    func mysqlLargeRowsProbe() async throws {
        let table = "\(LiveDB.mysqlScratchDatabase).gpt_perf_\(UUID().uuidString.prefix(8).lowercased())"
        let direct = DatabaseSessionManager(loadImmediately: false)
        let directID = try await direct.connect(config: LiveDB.config(.mysql), password: LiveDB.password(.mysql))
        let setup = try #require(direct.sessions[directID]?.connection)
        _ = try await setup.execute("CREATE TABLE \(table) (id INT PRIMARY KEY, value LONGTEXT)", parameters: [])
        for id in 1...100 {
            _ = try await setup.execute("INSERT INTO \(table) VALUES (\(id), REPEAT('x', 524288))", parameters: [])
        }
        func time(_ connection: any DatabaseConnection) async throws -> (Double, Int) {
            let result = try await connection.execute("SELECT * FROM \(table) LIMIT 100", parameters: [])
            return (result.executionTime, result.rows.count)
        }
        let (directSeconds, directRows) = try await time(setup)

        let tunnelled = DatabaseSessionManager(loadImmediately: false)
        nonisolated(unsafe) var opened: (any GlassHostPortForward)?
        let tunnelID = try await tunnelled.connect(
            config: LiveDB.config(.mysql, usesHostTunnel: true), password: LiveDB.password(.mysql),
            openForward: { [self] _, port in let forward = try await openForward(to: port); opened = forward; return forward })
        let viaTunnel = try #require(tunnelled.sessions[tunnelID]?.connection)
        let (tunnelSeconds, tunnelRows) = try await time(viaTunnel)
        print(String(format: "MYSQL 100 x 512 KB — direct %.3f s (%d rows), tunnel %.3f s (%d rows)",
                     directSeconds, directRows, tunnelSeconds, tunnelRows))

        _ = try await setup.execute("DROP TABLE \(table)", parameters: [])
        await tunnelled.disconnect(sessionID: tunnelID)
        await direct.disconnect(sessionID: directID)
        await opened?.close()
        #expect(directRows == 100 && tunnelRows == 100)
    }

    @Test("PostgreSQL over a real SSH forward: the driver connects to the local end and returns rows",
          .enabled(if: LiveTunnel.isConfigured && LiveDB.hasPostgres))
    func postgresOverATunnel() async throws {
        let manager = DatabaseSessionManager(loadImmediately: false)
        nonisolated(unsafe) var opened: (any GlassHostPortForward)?

        let sessionID = try await manager.connect(
            config: LiveDB.config(.postgresql, usesHostTunnel: true),
            password: LiveDB.password(.postgresql),
            openForward: { [self] remoteHost, port in
                // D7 asks for loopback as the host's machine sees it.
                #expect(remoteHost == "127.0.0.1")
                #expect(port == LiveDB.postgresPort)
                let forward = try await openForward(to: port)
                opened = forward
                return forward
            })

        let session = try #require(manager.sessions[sessionID])
        #expect(session.state.isConnected)
        // The session holds the forward, so tearing the session down tears the tunnel down.
        let forward = try #require(session.hostTunnel)
        #expect(forward.localPort > 0)
        #expect(forward.localPort != LiveDB.postgresPort, "the local end is a fresh OS-assigned port")

        let result = try await manager.executeQuery("SELECT * FROM teams", sessionID: sessionID,
                                                    editorRowLimit: 100)
        #expect(result.error == nil)
        #expect(!result.rows.isEmpty, "real rows, fetched through the tunnel")

        await manager.disconnect(sessionID: sessionID)
        #expect(manager.sessions[sessionID] == nil)
        await opened?.close()
    }

    /// Reconnect works for a tunnelled database, and does not leave the first forward behind.
    ///
    /// `DatabaseSession.openForward` was declared, read by `reconnect`, and **never assigned**, so
    /// this path threw "…no Terminal service is available to tunnel through" — about the very
    /// service the session had just tunnelled through. It failed closed, so nothing was exposed,
    /// but Reconnect is an explicit user action (`DatabaseSessionManager.swift:360`) and it did not
    /// work for any tunnelled database.
    ///
    /// The second assertion is the one that would have been missed by wiring alone: `reconnect`
    /// assigned over `session.hostTunnel` without closing what was there. Dropping an `SSHTunnel`
    /// closes its listener via deinit but never runs `close()`, so the capability's
    /// `release(owner:)` never fires and the forward outlives the session that authorised it.
    /// Counting the forwards this test opens is what proves the superseded one was closed.
    /// Disabled for the same reason as `directReconnect` — `reconnect` re-reads the password from
    /// the Keychain and these tests never store one, so it authenticates with `""` and PostgresNIO
    /// aborts the process. The fixes this test was written for are real and landed regardless:
    /// `DatabaseSession.openForward` is now assigned, and both the superseded connection and the
    /// superseded forward are closed before being replaced.
    @Test("A tunnelled database reconnects, and the superseded forward is closed",
          .disabled("needs a stored credential; see directReconnect"),
          .enabled(if: LiveTunnel.isConfigured && LiveDB.hasPostgres))
    func tunnelledReconnectOpensASecondForwardAndClosesTheFirst() async throws {
        let manager = DatabaseSessionManager(loadImmediately: false)
        nonisolated(unsafe) var opened: [LiveForward] = []

        let sessionID = try await manager.connect(
            config: LiveDB.config(.postgresql, usesHostTunnel: true),
            password: LiveDB.password(.postgresql),
            openForward: { [self] _, port in
                let forward = try await openForward(to: port) as! LiveForward
                opened.append(forward)
                return forward
            })

        let first = try #require(manager.sessions[sessionID]?.hostTunnel)
        #expect(opened.count == 1)

        try await manager.reconnect(sessionID: sessionID)

        let session = try #require(manager.sessions[sessionID])
        #expect(session.state.isConnected, "the tunnelled session reconnects at all")
        #expect(opened.count == 2, "reconnect asked the same broker for a second forward")
        let second = try #require(session.hostTunnel)
        #expect(second !== first, "the session holds the new forward, not the old one")

        // The query proves the new tunnel actually carries traffic, not merely that it exists.
        let result = try await manager.executeQuery("SELECT * FROM teams", sessionID: sessionID,
                                                    editorRowLimit: 100)
        #expect(result.error == nil)
        #expect(!result.rows.isEmpty, "real rows through the forward reconnect opened")

        #expect(opened[0].isClosed, "the superseded forward was closed, not orphaned")

        await manager.disconnect(sessionID: sessionID)
        for forward in opened { await forward.close() }
    }

    @Test("MySQL over a real SSH forward: the driver connects to the local end and returns rows",
          .enabled(if: LiveTunnel.isConfigured && LiveDB.hasMySQL))
    func mysqlOverATunnel() async throws {
        let manager = DatabaseSessionManager(loadImmediately: false)
        nonisolated(unsafe) var opened: (any GlassHostPortForward)?

        let sessionID = try await manager.connect(
            config: LiveDB.config(.mysql, usesHostTunnel: true),
            password: LiveDB.password(.mysql),
            openForward: { [self] _, port in
                let forward = try await openForward(to: port)
                opened = forward
                return forward
            })
        let result = try await manager.executeQuery("SELECT * FROM teams", sessionID: sessionID,
                                                    editorRowLimit: 100)
        #expect(result.error == nil)
        #expect(!result.rows.isEmpty)
        await manager.disconnect(sessionID: sessionID)
        await opened?.close()
    }

    @Test("A read-only service still refuses writes when it is reached through a tunnel",
          .enabled(if: LiveTunnel.isConfigured && LiveDB.hasPostgres))
    func readOnlyHoldsThroughATunnel() async throws {
        let manager = DatabaseSessionManager(loadImmediately: false)
        nonisolated(unsafe) var opened: (any GlassHostPortForward)?

        let sessionID = try await manager.connect(
            config: LiveDB.config(.postgresql, readOnly: true, usesHostTunnel: true),
            password: LiveDB.password(.postgresql),
            openForward: { [self] _, port in
                let forward = try await openForward(to: port)
                opened = forward
                return forward
            })
        let connection = try #require(manager.sessions[sessionID]?.connection)
        #expect(connection is ReadOnlyDatabaseConnection)
        await #expect(throws: ReadOnlyServiceError.self) {
            _ = try await connection.execute("DELETE FROM teams", parameters: [])
        }
        await manager.disconnect(sessionID: sessionID)
        await opened?.close()
    }
}
