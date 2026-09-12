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

    static var hasMySQL: Bool { mysqlPassword != nil }
    static var hasPostgres: Bool { postgresPassword != nil }

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
    init(tunnel: SSHTunnel, transport: SSHTransport, owner: UUID) {
        localPort = tunnel.localPort
        self.tunnel = tunnel
        self.transport = transport
        self.owner = owner
    }
    func close() async {
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
