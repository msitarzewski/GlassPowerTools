//
//  DatabaseSessionManager.swift
//  glassdb
//
//  Manages active database sessions and query execution
//

import Foundation
import Observation
import GlasSecretStore
import os
import GlassDBKit
import GlassShell

@MainActor
@Observable
class DatabaseSessionManager {
    var sessions: [UUID: DatabaseSession] = [:]
    var paletteConnectionRequest: UUID?
    private(set) var workspaceRequests: [UUID: DatabaseWorkspaceWindowRequest] = [:]
    private(set) var persistentQueryHistory: [QueryHistoryEntry] = []

    private var hasLoaded = false
    private let defaults: UserDefaults
    private var statisticsLoads: [DatabaseStatisticsLoadKey: DatabaseStatisticsLoad] = [:]
    private var aggregateStatisticsLoads: [UUID: AggregateStatisticsLoad] = [:]

    /// Where the driver's socket goes and what the transport verifies. Nothing else: it carried
    /// `tunnelRemoteHost`/`tunnelRemotePort` until 2026-09-12, written at every return and
    /// **never read**. They were worse than dead weight — they read as the forward's target and
    /// are not one. The forward is opened with `openForward("127.0.0.1", config.port)`: loopback
    /// **as the host's machine sees it**, which is the whole of D7. A later maintainer
    /// "correcting" the forward to use a remembered remote host would silently break every
    /// database bound only to the server's own loopback.
    struct TransportPlan: Equatable, Sendable {
        let databaseHost: String
        let databasePort: Int
        let tlsPolicy: DatabaseTLSPolicy
    }

    enum ForegroundValidationResult: Equatable, Sendable {
        case connected
        case disconnected
        case missingSession
    }

    init(loadImmediately: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if loadImmediately {
            loadIfNeeded()
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        loadQueryHistory()
    }

    /// Registers the richer workspace launch context while keeping the scene's
    /// external value a plain UUID. UUID-valued WindowGroups are the proven
    /// spatial-window contract used by the Vision Pro terminal sibling app.
    @discardableResult
    func registerWorkspace(_ request: DatabaseWorkspaceWindowRequest) -> UUID {
        workspaceRequests[request.id] = request
        return request.id
    }

    /// Schema diagram windows (D43), keyed like workspaces: the scene's value is a plain UUID.
    private(set) var diagramRequests: [UUID: SchemaDiagramRequest] = [:]

    @discardableResult
    func registerDiagram(_ request: SchemaDiagramRequest) -> UUID {
        diagramRequests[request.id] = request
        return request.id
    }

    func diagramRequest(for windowID: UUID) -> SchemaDiagramRequest? { diagramRequests[windowID] }

    /// Supports windows opened by older builds, where the scene UUID was the
    /// database session UUID and the workspace always used its default tab.
    func workspaceRequest(for windowID: UUID) -> DatabaseWorkspaceWindowRequest {
        workspaceRequests[windowID] ?? .primary(sessionID: windowID)
    }

    /// **Closing the last window on a session ends the session.** The desktop's and the editor's
    /// rule, and until 2026-09-22 not the database's: the red close button flushed the drafts and
    /// left the connection open, findable only in Active (*"everything else has an actual close
    /// button for the connection"*). A second workspace window on the same session closing leaves
    /// it alone — glassdb's "Open New Workspace Window", kept. A phone registers a workspace and
    /// never releases it, because leaving a screen there is not closing it (D31); its ⋯ menu ends
    /// the session on purpose.
    @discardableResult
    func releaseWorkspace(_ windowID: UUID) -> Task<Void, Never>? {
        guard let released = workspaceRequests.removeValue(forKey: windowID) else { return nil }
        guard !workspaceRequests.values.contains(where: { $0.sessionID == released.sessionID }) else { return nil }
        return Task { await disconnect(sessionID: released.sessionID) }
    }

    /// Opens a local port that reaches `remoteHost:port` from the host's machine. Supplied by
    /// the capability from `GlassCapabilityHostAccess.forwardPort`, so the session manager can
    /// tunnel without knowing — or importing — whichever capability owns the host's SSH service.
    typealias PortForwardProvider = @MainActor (_ remoteHost: String, _ port: Int) async throws -> any GlassHostPortForward

    func connect(
        config: DatabaseConnectionConfig,
        password: String,
        openForward: PortForwardProvider? = nil
    ) async throws -> UUID {
        let sessionID = UUID()
        let session = DatabaseSession(connectionConfig: config)
        // Retained so `reconnect` can open a second forward through the same broker.
        //
        // `DatabaseSession.openForward` was declared and read by `reconnect` and **never assigned**,
        // so every tunnelled database failed to reconnect: `reconnect` passed nil, `connect` hit the
        // `usesHostTunnel` guard, and the user was told no Terminal service was available to tunnel
        // through — about the very service they had just connected through. It failed closed, which
        // is the right direction, but Reconnect is an explicit user action (`:360`) and it did not
        // work.
        session.openForward = openForward
        sessions[sessionID] = session

        do {
            let engine = Self.makeEngine(for: config.engine)
            var tunnelLocalPort: Int?

            if config.engine == .sqlite {
                guard !config.usesHostTunnel, !config.useTLS else {
                    throw SessionError.invalidConfiguration(
                        "SQLite is a local file database and cannot use TLS or an SSH tunnel."
                    )
                }
                let sqliteURL: URL
                do {
                    sqliteURL = try SQLiteFileImporter.validatedURL(forPath: config.host)
                } catch {
                    throw SessionError.invalidConfiguration(error.localizedDescription)
                }
                do {
                    session.state = .connecting(stage: .authenticating)
                    let connection = try await engine.connect(
                        host: sqliteURL.path,
                        port: 0,
                        username: "",
                        password: "",
                        database: nil,
                        tlsPolicy: .disabled
                    )
                    session.engine = engine
                    session.connection = Self.applyingReadOnly(connection, config: config)
                    session.currentDatabase = "main"
                    session.state = .connected
                    Logger.database.info("Opened SQLite database \(sqliteURL.lastPathComponent, privacy: .public)")
                } catch {
                    throw error
                }
                return sessionID
            }

            // D7: a database the host does not publish is reached through the host's own
            // Terminal service. This module opens no SSH connection, stores no SSH credential
            // and pins no host key — the shell brokers the forward and the capability that
            // owns `.ssh` performs it, under the trust that machine already has.
            if config.usesHostTunnel {
                guard let openForward else {
                    throw SessionError.invalidConfiguration(
                        "\(config.name) is set to connect through this machine's Terminal service, but no Terminal service is available to tunnel through. Add one to the machine, or turn the setting off and connect directly."
                    )
                }
                session.state = .connecting(stage: .openingHostTunnel)
                Logger.database.info("Opening a tunnel to the database through the host's Terminal service")
                // Loopback as the tunnelling machine sees it: the database is on that machine.
                // A database tunnelled through *another* machine (`tunnelServiceID`) gets a
                // forward that ends at its own address instead; the capability builds that one
                // and ignores the loopback asked for here.
                let forward = try await openForward("127.0.0.1", config.port)
                session.hostTunnel = forward
                tunnelLocalPort = forward.localPort
                Logger.database.info("Tunnel open on local port \(forward.localPort)")
            }

            // Connect to the selected network engine (directly or through tunnel)
            let transportPlan = try Self.transportPlan(
                for: config,
                tunnelLocalPort: tunnelLocalPort
            )
            session.state = .connecting(stage: .authenticating)
            Logger.database.info("Connecting to \(config.engine.displayName, privacy: .public) at \(transportPlan.databaseHost):\(transportPlan.databasePort) as \(config.username) (config host: \(config.host):\(config.port))")
            let connection = try await engine.connect(
                host: transportPlan.databaseHost,
                port: transportPlan.databasePort,
                username: config.username,
                password: password,
                database: config.defaultDatabase,
                tlsPolicy: transportPlan.tlsPolicy
            )
            session.engine = engine
            session.connection = Self.applyingReadOnly(connection, config: config)
            session.state = .connected
            Logger.database.info("Connected to \(config.host):\(config.port)")
        } catch {
            // Clean up on failure.
            //
            // The connection is closed, not merely dropped: everything after the driver connects —
            // selecting the database, the read-only wrap, the transport validation — can throw with
            // a live connection already in hand, and releasing the last reference to an open one
            // trips PostgresNIO's "deinitialized before being closed" assertion, which aborts the
            // process rather than surfacing an error.
            do {
                try await session.connection?.close()
            } catch {
                Logger.database.error("Closing a failed connection: \(error)")
            }
            session.connection = nil
            await session.hostTunnel?.close()
            session.hostTunnel = nil
            session.engine = nil
            let propagatedError = Self.actionableConnectionError(error, config: config)
            session.state = .error(propagatedError.localizedDescription)
            sessions.removeValue(forKey: sessionID)
            Logger.database.error("Connection failed: \(propagatedError)")
            throw propagatedError
        }

        return sessionID
    }

    /// Wraps a freshly opened connection when the service is read-only, so every later caller
    /// — including the five that reach the driver directly — is holding the guarded one.
    nonisolated static func applyingReadOnly(_ connection: any DatabaseConnection,
                                             config: DatabaseConnectionConfig) -> any DatabaseConnection {
        guard config.isReadOnly else { return connection }
        return ReadOnlyDatabaseConnection(wrapping: connection, connectionName: config.name)
    }

    static func makeEngine(for type: DatabaseEngineType) -> any DatabaseEngine {
        switch type {
        case .mysql: MySQLEngine()
        case .postgresql: PostgreSQLEngine()
        case .sqlite: SQLiteEngine()
        }
    }

    nonisolated static func transportPlan(
        for config: DatabaseConnectionConfig,
        tunnelLocalPort: Int? = nil
    ) throws -> TransportPlan {
        if config.engine == .sqlite {
            guard !config.usesHostTunnel, !config.useTLS else {
                throw SessionError.invalidConfiguration(
                    "SQLite is a local file database and cannot use TLS or an SSH tunnel."
                )
            }
            return TransportPlan(
                databaseHost: config.host,
                databasePort: 0,
                tlsPolicy: .disabled
            )
        }

        // The one place a saved record becomes a transport-security decision. Keep it that way:
        // a second place that decides what is verified is the D15 mistake in a new spot.
        //
        // Through a tunnel the socket goes to 127.0.0.1, so the certificate is still checked
        // against the machine's real name rather than loopback — `config.host` in every pinned
        // case, for the same reason.
        let tlsPolicy: DatabaseTLSPolicy
        if config.useTLS {
            switch config.tlsVerification {
            case .systemTrust:
                tlsPolicy = config.usesHostTunnel
                    ? .requiredSystemTrustForHost(config.host)
                    : .requiredSystemTrust
            case .pinnedCertificate:
                guard let certificate = config.tlsCertificateMaterial else {
                    throw SessionError.invalidConfiguration(
                        "\(config.name) is set to verify with a pinned certificate, but no usable certificate is saved. Re-import it, or change the verification mode."
                    )
                }
                tlsPolicy = .requiredCertificates([certificate], serverName: config.host)
            case .pinnedCertificateAuthorityOnly:
                guard let certificate = config.tlsCertificateMaterial else {
                    throw SessionError.invalidConfiguration(
                        "\(config.name) is set to verify the certificate authority only, but no usable certificate is saved. Re-import it, or change the verification mode."
                    )
                }
                // Chain verified against the supplied roots; no name matched. Reached only because
                // the user chose it — there is no path here from a failed full verification.
                tlsPolicy = .requiredCertificatesWithoutHostnameVerification([certificate])
            }
        } else {
            tlsPolicy = .disabled
        }

        if config.usesHostTunnel {
            guard let tunnelLocalPort, tunnelLocalPort > 0 else {
                throw SessionError.invalidConfiguration(
                    "The tunnel through the host did not provide a valid local database port."
                )
            }
            return TransportPlan(
                databaseHost: "127.0.0.1",
                databasePort: tunnelLocalPort,
                tlsPolicy: tlsPolicy
            )
        }

        return TransportPlan(
            databaseHost: config.host,
            databasePort: config.port,
            tlsPolicy: tlsPolicy
        )
    }

    func testConnection(config: DatabaseConnectionConfig, password: String,
                        openForward: PortForwardProvider? = nil) async throws {
        let sessionID = try await connect(config: config, password: password, openForward: openForward)
        await disconnect(sessionID: sessionID)
    }

    /// Re-establishes the transport behind an existing logical session. Keeping
    /// the `DatabaseSession` instance intact means every workspace window over
    /// that session recovers together without losing tabs, history, or AI context.
    func reconnect(sessionID: UUID) async throws {
        guard let session = sessions[sessionID] else {
            throw SessionError.notConnected
        }
        guard !session.state.isConnecting else { return }

        let config = session.connectionConfig
        let selectedDatabase = session.currentDatabase
        session.lastConnectionError = nil
        session.state = .connecting(stage: .resolvingHost)

        do {
            let credentials = try Self.storedCredentials(for: config)
            let replacementID = try await connect(
                config: config,
                password: credentials.database,
                openForward: session.openForward
            )
            guard let replacement = sessions.removeValue(forKey: replacementID),
                  let connection = replacement.connection else {
                throw SessionError.notConnected
            }

            do {
                // MySQL can change its active database within one connection. Put a
                // reconnected editor back where the user left it before publishing
                // the recovered transport to any sibling workspace windows.
                if config.engine == .mysql,
                   let selectedDatabase,
                   !selectedDatabase.isEmpty,
                   selectedDatabase != config.defaultDatabase {
                    let result = try await connection.execute(
                        "USE \(connection.quotedIdentifier(selectedDatabase))",
                        parameters: []
                    )
                    if let error = result.error {
                        throw DatabaseError.unexpectedResult(error)
                    }
                }
            } catch {
                try? await connection.close()
                await replacement.hostTunnel?.close()
                replacement.connection = nil
                replacement.engine = nil
                replacement.hostTunnel = nil
                throw error
            }

            // Close the connection this reconnect replaces, exactly as `disconnect` does at `:420`.
            //
            // Assigning over `session.connection` drops the old driver without closing it, and
            // PostgresNIO asserts on precisely that — "PostgresConnection deinitialized before being
            // closed" — which is how this was found: the reconnect test crashed the suite rather
            // than failing it. The old connection is usually already dead, since a dead connection
            // is why anyone reconnects, so the close is best-effort and logged like the one in
            // `disconnect`.
            // No identity check: `replacement` came from a fresh `connect`, so its connection is a
            // different instance by construction. `DatabaseConnection` is a protocol with no class
            // constraint, so there is nothing to compare anyway.
            if let superseded = session.connection {
                    do {
                    try await superseded.close()
                } catch {
                    Logger.database.error("Closing the superseded connection failed: \(error)")
                }
            }
            session.connection = connection
            session.engine = replacement.engine
            // Close the forward this reconnect replaces before overwriting the reference.
            // Assigning over it drops the `SSHTunnel` — whose deinit closes the listener — but
            // never runs `GlassTerminalPortForward.close()`, so the capability's
            // `transport.release(owner:)` is never called and the forward outlives the session
            // that authorised it. Unreachable while `openForward` was never assigned; assigning it
            // above is exactly what would have made it reachable.
            if let superseded = session.hostTunnel, superseded !== replacement.hostTunnel {
                await superseded.close()
            }
            session.hostTunnel = replacement.hostTunnel
            session.currentDatabase = config.engine == .sqlite
                ? "main"
                : (selectedDatabase ?? replacement.currentDatabase)
            session.requiresTransportValidation = false
            session.state = .connected

            // Ownership moved to the retained session above.
            replacement.connection = nil
            replacement.engine = nil
            replacement.hostTunnel = nil
            Logger.database.info("Reconnected session \(sessionID)")
        } catch {
            let message = error.localizedDescription
            session.lastConnectionError = message
            session.state = .error(message)
            Logger.database.error("Reconnect failed for session \(sessionID): \(message, privacy: .public)")
            throw error
        }
    }

    /// Records that the owning scene may be suspended. The transport is not
    /// closed here because another iPad window can still own the same logical
    /// session; every subsequent request performs validation before use.
    func noteSessionSuspended(sessionID: UUID) {
        guard let session = sessions[sessionID], session.state.isConnected else { return }
        session.requiresTransportValidation = true
    }

    /// Revalidates a possibly suspended transport without issuing a query or
    /// silently reconnecting. Reconnect remains one explicit, bounded user action.
    func validateSessionAfterForeground(sessionID: UUID) async -> ForegroundValidationResult {
        guard sessions[sessionID] != nil else { return .missingSession }
        guard await refreshConnectionState(sessionID: sessionID) else { return .disconnected }
        return .connected
    }

    /// Checks the local transport state without issuing a keepalive query. This
    /// catches sockets the driver already knows are closed while respecting the
    /// server's configured idle-timeout policy.
    @discardableResult
    func refreshConnectionState(sessionID: UUID) async -> Bool {
        guard let session = sessions[sessionID],
              session.state.isConnected,
              let connection = session.connection else {
            return false
        }
        guard await connection.isConnected else {
            await invalidateTransport(
                for: session,
                reason: "The database connection timed out or was closed."
            )
            return false
        }
        session.requiresTransportValidation = false
        return true
    }

    /// Lets metadata surfaces that call the driver directly report a terminal
    /// transport error through the same shared session state as query execution.
    func handleConnectionFailure(_ error: any Error, sessionID: UUID) async {
        guard let session = sessions[sessionID],
              let connection = session.connection else { return }
        let isOpen = await connection.isConnected
        guard !isOpen || Self.isTerminalConnectionError(error.localizedDescription) else { return }
        await invalidateTransport(for: session, reason: error.localizedDescription)
    }

    func disconnect(sessionID: UUID) async {
        guard let session = sessions[sessionID] else { return }
        cancelStatisticsLoads(sessionID: sessionID)
        do {
            try await session.connection?.close()
        } catch {
            Logger.database.error("Disconnect error: \(error)")
        }
        // Close the host tunnel if one is active.
        await session.hostTunnel?.close()
        session.state = .disconnected
        session.connection = nil
        session.engine = nil
        session.hostTunnel = nil
        sessions.removeValue(forKey: sessionID)
        Logger.database.info("Disconnected session \(sessionID)")
    }

    func executeQuery(
        _ sql: String,
        parameters: [DatabaseValue] = [],
        sessionID: UUID,
        editorRowLimit: Int? = nil
    ) async throws -> QueryResult {
        guard let session = sessions[sessionID] else {
            throw SessionError.notConnected
        }
        guard session.state.isConnected,
              let connection = session.connection else {
            throw SessionError.connectionLost
        }
        guard await refreshConnectionState(sessionID: sessionID) else {
            throw SessionError.connectionLost
        }

        if let editorRowLimit,
           !SQLHighlighter.validEditorResultRowLimits.contains(editorRowLimit) {
            throw SessionError.invalidConfiguration(
                "Editor result limits must be between 1 and 100,000 rows."
            )
        }

        let boundedPlan = editorRowLimit.flatMap {
            SQLHighlighter.boundedReadPlan(
                for: sql,
                rowLimit: $0,
                dialect: connection.dialect
            )
        }
        let executionSQL = boundedPlan?.executionSQL ?? sql
        let querySafety = SQLHighlighter.safetyClassification(of: sql)
        let startedAt = Date()
        let result: QueryResult
        do {
            let rawResult = try await connection.execute(executionSQL, parameters: parameters)
            if let boundedPlan {
                let truncated = rawResult.rows.count > boundedPlan.rowLimit
                result = QueryResult(
                    id: rawResult.id,
                    query: sql,
                    columns: rawResult.columns,
                    rows: Array(rawResult.rows.prefix(boundedPlan.rowLimit)),
                    affectedRows: rawResult.affectedRows,
                    lastInsertID: rawResult.lastInsertID,
                    warningCount: rawResult.warningCount,
                    executionTime: rawResult.executionTime,
                    timestamp: rawResult.timestamp,
                    error: rawResult.error,
                    appliedRowLimit: boundedPlan.rowLimit,
                    isTruncated: truncated
                )
            } else {
                result = rawResult
            }
        } catch {
            if querySafety.requiresConfirmation {
                // A transport failure can arrive after a write reached the server.
                // Never retain statistics when the resulting server state is unknown.
                invalidateTableStatistics(sessionID: sessionID)
            }
            recordHistory(
                sql: sql,
                session: session,
                timestamp: startedAt,
                duration: Date().timeIntervalSince(startedAt),
                rowCount: nil,
                affectedRows: nil,
                error: error.localizedDescription
            )
            await handleConnectionFailure(error, sessionID: sessionID)
            if !session.state.isConnected {
                throw SessionError.connectionLost
            }
            throw error
        }

        if let error = result.error,
           Self.isTerminalConnectionError(error) {
            await invalidateTransport(for: session, reason: error)
        }

        // Track USE database switches so the UI shows the current database
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("USE ") && result.error == nil {
            let dbName = trimmed.dropFirst(4)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "`;"))
                .replacingOccurrences(of: "`", with: "")
            session.currentDatabase = dbName
        }

        session.queryHistory.append(result)
        recordHistory(
            sql: sql,
            session: session,
            timestamp: result.timestamp,
            duration: result.executionTime,
            rowCount: result.rowCount,
            affectedRows: result.affectedRows,
            error: result.error
        )

        if result.error == nil, querySafety.requiresConfirmation {
            // Arbitrary SQL can qualify an object outside the active database.
            // Conservatively discard every cached namespace for this session.
            invalidateTableStatistics(sessionID: sessionID)
        }

        return result
    }

    // MARK: - Table Statistics

    func cachedTableStatistics(
        sessionID: UUID,
        database: String
    ) -> DatabaseStatisticsSnapshot? {
        sessions[sessionID]?.databaseStatistics[database]
    }

    func tableStatistics(
        sessionID: UUID,
        database: String,
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async throws -> DatabaseStatisticsSnapshot {
        guard let session = sessions[sessionID],
              session.state.isConnected,
              let connection = session.connection else {
            throw SessionError.connectionLost
        }

        if !forceRefresh,
           let cached = session.databaseStatistics[database],
           cached.isFresh(at: now) {
            return cached
        }

        let key = DatabaseStatisticsLoadKey(sessionID: sessionID, database: database)
        if let existing = statisticsLoads[key] {
            return try await existing.task.value
        }

        let loadID = UUID()
        let task = Task {
            let statuses = try await connection.tableStatus(in: database)
            try Task.checkCancellation()
            return DatabaseStatisticsSnapshot(
                database: database,
                statuses: statuses,
                capturedAt: now
            )
        }
        statisticsLoads[key] = DatabaseStatisticsLoad(id: loadID, task: task)

        do {
            let snapshot = try await task.value
            guard statisticsLoads[key]?.id == loadID else { throw CancellationError() }
            statisticsLoads.removeValue(forKey: key)
            guard sessions[sessionID] === session else { throw SessionError.connectionLost }
            session.databaseStatistics[database] = snapshot
            return snapshot
        } catch {
            if statisticsLoads[key]?.id == loadID {
                statisticsLoads.removeValue(forKey: key)
            }
            throw error
        }
    }

    /// Fills the per-database snapshot cache for every requested namespace from
    /// one aggregate round trip. Existing per-database `tableStatistics(...)`
    /// consumers keep reading the same cache with unchanged semantics.
    func aggregateTableStatistics(
        sessionID: UUID,
        namespaces: [String],
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async throws -> [String: DatabaseStatisticsSnapshot] {
        guard let session = sessions[sessionID],
              session.state.isConnected,
              let connection = session.connection else {
            throw SessionError.connectionLost
        }
        guard connection.capabilities.contains(.aggregateTableStatistics) else {
            throw DatabaseError.unsupportedCapability(
                .aggregateTableStatistics,
                engine: connection.engineName
            )
        }

        if !forceRefresh {
            var cached: [String: DatabaseStatisticsSnapshot] = [:]
            for namespace in namespaces {
                guard let snapshot = session.databaseStatistics[namespace],
                      snapshot.isFresh(at: now) else { break }
                cached[namespace] = snapshot
            }
            if cached.count == namespaces.count {
                return cached
            }
        }

        // Concurrent callers share one in-flight server query. Matching the
        // per-database dedup, only the initiating caller writes the cache;
        // joiners derive their own snapshots from the shared grouped result.
        if let existing = aggregateStatisticsLoads[sessionID] {
            let grouped = try await existing.task.value
            return Self.statisticsSnapshots(
                for: namespaces,
                grouped: grouped,
                capturedAt: existing.startedAt
            )
        }

        let task = Task {
            let grouped = try await connection.tableStatusByNamespace()
            try Task.checkCancellation()
            return grouped
        }
        let load = AggregateStatisticsLoad(id: UUID(), startedAt: now, task: task)
        aggregateStatisticsLoads[sessionID] = load

        do {
            let grouped = try await task.value
            guard aggregateStatisticsLoads[sessionID]?.id == load.id else { throw CancellationError() }
            aggregateStatisticsLoads.removeValue(forKey: sessionID)
            guard sessions[sessionID] === session else { throw SessionError.connectionLost }
            let snapshots = Self.statisticsSnapshots(
                for: namespaces,
                grouped: grouped,
                capturedAt: load.startedAt
            )
            for (namespace, snapshot) in snapshots {
                session.databaseStatistics[namespace] = snapshot
            }
            return snapshots
        } catch {
            if aggregateStatisticsLoads[sessionID]?.id == load.id {
                aggregateStatisticsLoads.removeValue(forKey: sessionID)
            }
            throw error
        }
    }

    /// Fans one grouped aggregate result out into per-database snapshots. A
    /// namespace with no tables yields no aggregate rows; it still gets an
    /// empty snapshot so it reads as "statistics available", matching an empty
    /// per-database status query.
    private nonisolated static func statisticsSnapshots(
        for namespaces: [String],
        grouped: [String: [TableStatus]],
        capturedAt: Date
    ) -> [String: DatabaseStatisticsSnapshot] {
        var snapshots: [String: DatabaseStatisticsSnapshot] = [:]
        for namespace in namespaces {
            snapshots[namespace] = DatabaseStatisticsSnapshot(
                database: namespace,
                statuses: grouped[namespace] ?? [],
                capturedAt: capturedAt
            )
        }
        return snapshots
    }

    func invalidateTableStatistics(sessionID: UUID, database: String? = nil) {
        guard let session = sessions[sessionID] else { return }
        if let database {
            session.databaseStatistics.removeValue(forKey: database)
            let key = DatabaseStatisticsLoadKey(sessionID: sessionID, database: database)
            statisticsLoads.removeValue(forKey: key)?.task.cancel()
            // An in-flight aggregate load would repopulate this namespace with
            // data captured before the invalidating mutation; discard it too.
            aggregateStatisticsLoads.removeValue(forKey: sessionID)?.task.cancel()
        } else {
            session.databaseStatistics.removeAll()
            cancelStatisticsLoads(sessionID: sessionID)
        }
    }

    private func cancelStatisticsLoads(sessionID: UUID) {
        let keys = statisticsLoads.keys.filter { $0.sessionID == sessionID }
        for key in keys {
            statisticsLoads.removeValue(forKey: key)?.task.cancel()
        }
        aggregateStatisticsLoads.removeValue(forKey: sessionID)?.task.cancel()
    }

    func explainQuery(_ sql: String, sessionID: UUID) async throws -> QueryResult {
        guard let session = sessions[sessionID] else {
            throw SessionError.notConnected
        }
        guard session.state.isConnected,
              let connection = session.connection else {
            throw SessionError.connectionLost
        }
        guard await refreshConnectionState(sessionID: sessionID) else {
            throw SessionError.connectionLost
        }
        guard connection.capabilities.contains(.explain) else {
            throw DatabaseError.unsupportedCapability(
                .explain,
                engine: connection.engineName
            )
        }

        let startedAt = Date()
        do {
            let result = try await connection.explain(sql, parameters: [])
            session.queryHistory.append(result)
            recordHistory(
                sql: "EXPLAIN \(sql)",
                session: session,
                timestamp: result.timestamp,
                duration: result.executionTime,
                rowCount: result.rowCount,
                affectedRows: result.affectedRows,
                error: result.error
            )
            return result
        } catch {
            recordHistory(
                sql: "EXPLAIN \(sql)",
                session: session,
                timestamp: startedAt,
                duration: Date().timeIntervalSince(startedAt),
                rowCount: nil,
                affectedRows: nil,
                error: error.localizedDescription
            )
            await handleConnectionFailure(error, sessionID: sessionID)
            if !session.state.isConnected {
                throw SessionError.connectionLost
            }
            throw error
        }
    }

    func cancelQuery(sessionID: UUID) async throws {
        guard let session = sessions[sessionID],
              let connection = session.connection else {
            throw SessionError.notConnected
        }
        guard connection.capabilities.contains(.cancellation) else {
            throw DatabaseError.unsupportedCapability(
                .cancellation,
                engine: connection.engineName
            )
        }
        try await connection.cancelCurrentQuery()
        guard !(await connection.isConnected) else { return }

        // Drivers without a native cancellation packet abort by closing their
        // transport. Reflect that terminal state immediately and tear down any
        // tunnel so the UI never presents a dead connection as usable.
        await session.hostTunnel?.close()
        session.state = .disconnected
        session.connection = nil
        session.engine = nil
        session.hostTunnel = nil
    }

    // MARK: - Durable Query History

    func queryHistory(
        matching searchText: String = "",
        connectionID: UUID? = nil,
        database: String? = nil,
        status: QueryHistoryStatus = .all
    ) -> [QueryHistoryEntry] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return persistentQueryHistory.reversed().filter { entry in
            if let connectionID, entry.connectionID != connectionID { return false }
            if let database, entry.database != database { return false }
            if status == .succeeded, entry.error != nil { return false }
            if status == .failed, entry.error == nil { return false }
            guard !needle.isEmpty else { return true }
            return entry.sql.localizedCaseInsensitiveContains(needle)
                || entry.database?.localizedCaseInsensitiveContains(needle) == true
                || entry.error?.localizedCaseInsensitiveContains(needle) == true
        }
    }

    func deleteQueryHistory(id: UUID) {
        persistentQueryHistory.removeAll { $0.id == id }
        saveQueryHistory()
    }

    func deleteAllQueryHistory(connectionID: UUID? = nil) {
        if let connectionID {
            persistentQueryHistory.removeAll { $0.connectionID == connectionID }
        } else {
            persistentQueryHistory.removeAll()
        }
        saveQueryHistory()
    }

    func enforceQueryHistoryLimit() {
        let maxHistory = configuredHistoryLimit
        if persistentQueryHistory.count > maxHistory {
            persistentQueryHistory.removeFirst(persistentQueryHistory.count - maxHistory)
            saveQueryHistory()
        }
        for session in sessions.values where session.queryHistory.count > maxHistory {
            session.queryHistory.removeFirst(session.queryHistory.count - maxHistory)
        }
    }

    private var configuredHistoryLimit: Int {
        let stored = defaults.integer(forKey: UserDefaultsKeys.maxQueryHistoryItems)
        return min(max(stored > 0 ? stored : 500, 1), 10_000)
    }

    func recordHistory(
        sql: String,
        session: DatabaseSession,
        timestamp: Date,
        duration: TimeInterval,
        rowCount: Int?,
        affectedRows: UInt64?,
        error: String?
    ) {
        let redactLiterals = QueryHistoryRedaction.isOn(in: defaults)
        let retainedSQL = redactLiterals ? SQLHighlighter.redactingLiterals(in: sql) : sql
        persistentQueryHistory.append(QueryHistoryEntry(
            sql: retainedSQL,
            timestamp: timestamp,
            duration: duration,
            rowCount: rowCount,
            affectedRows: affectedRows,
            error: error,
            database: session.currentDatabase,
            connectionID: session.connectionConfig.id,
            safety: SQLHighlighter.safetyClassification(of: sql)
        ))
        enforceQueryHistoryLimit()
        saveQueryHistory()
    }

    private func loadQueryHistory() {
        guard let data = defaults.data(forKey: UserDefaultsKeys.queryHistory) else {
            persistentQueryHistory = []
            return
        }
        do {
            persistentQueryHistory = try JSONDecoder().decode([QueryHistoryEntry].self, from: data)
            enforceQueryHistoryLimit()
        } catch {
            Logger.database.error("Could not load query history: \(error)")
            persistentQueryHistory = []
        }
    }

    private func saveQueryHistory() {
        do {
            let data = try JSONEncoder().encode(persistentQueryHistory)
            defaults.set(data, forKey: UserDefaultsKeys.queryHistory)
        } catch {
            Logger.database.error("Could not save query history: \(error)")
        }
    }

    func session(for id: UUID) -> DatabaseSession? {
        sessions[id]
    }

    nonisolated static func isTerminalConnectionError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return [
            "connection closed",
            "connection is closed",
            "connection lost",
            "lost connection",
            "connection reset",
            "connection terminated",
            "server has gone away",
            "broken pipe",
            "channel closed",
            "channel is closed",
            "not connected",
            "timed out or was closed",
        ].contains { normalized.contains($0) }
    }

    nonisolated static func isLocalNetworkPermissionDenied(
        domain: String,
        code: Int,
        message: String
    ) -> Bool {
        let normalizedDomain = domain.lowercased()
        let normalizedMessage = message.lowercased()
        if code == -65_570 { return true } // kDNSServiceErr_PolicyDenied
        if normalizedDomain == NSPOSIXErrorDomain.lowercased(), code == 1 || code == 13 {
            return true
        }
        return normalizedMessage.contains("policy denied")
            || normalizedMessage.contains("local network access")
            || normalizedMessage.contains("local network permission")
    }

    private nonisolated static func actionableConnectionError(
        _ error: any Error,
        config: DatabaseConnectionConfig
    ) -> any Error {
        guard config.engine.supportsNetworkTransport else { return error }
        let nsError = error as NSError
        guard isLocalNetworkPermissionDenied(
            domain: nsError.domain,
            code: nsError.code,
            message: error.localizedDescription
        ) else { return error }
        return SessionError.localNetworkPermissionDenied
    }

    /// The database password only. A reconnect needs no second secret: the tunnel, when there
    /// is one, is opened by the capability that owns the host's SSH service, with its own.
    private static func storedCredentials(
        for config: DatabaseConnectionConfig
    ) throws -> (database: String, ssh: String?) {
        (try storedDatabasePassword(for: config), nil)
    }

    /// The password a saved service connects with, for the first connect and every reconnect.
    ///
    /// **Nothing stored means no password, and that is a real configuration.** `auth_socket`,
    /// `trust`, `peer`, a tunnelled local instance, root on a machine of one's own — all connect
    /// with an empty password, and the secret store refuses to write an empty value, so a
    /// service saved that way stores no keychain item at all. Refusing here made the app unable
    /// to reach servers that work everywhere else (2026-09-20, and again on 2026-09-22 when the
    /// first connect still threw *"Requested secure item was not found in Keychain"* for MySQL
    /// on the user's Mac through the tunnel, while a reconnect would have passed). Whether the server
    /// accepts an empty password is the server's to say, and it says so accurately; a stranded
    /// credential reads as that server's own rejection rather than as this layer's guess.
    ///
    /// Observed either way: a live PostgreSQL reconnect authenticated with an empty password on
    /// 2026-09-13, which is the case this rule exists for.
    static func storedDatabasePassword(
        for config: DatabaseConnectionConfig,
        retrieve: (DatabaseConnectionConfig) throws -> String = KeychainManager.retrievePassword
    ) throws -> String {
        guard config.engine.supportsCredentials else { return "" }
        do { return try retrieve(config) }
        catch SecretStoreError.notFound { return "" }
    }

    private func invalidateTransport(
        for session: DatabaseSession,
        reason: String
    ) async {
        guard session.state.isConnected || session.connection != nil else { return }
        if let sessionID = sessions.first(where: { $0.value === session })?.key {
            invalidateTableStatistics(sessionID: sessionID)
        }
        let connection = session.connection
        let tunnel = session.hostTunnel

        // Publish the terminal state before awaiting cleanup so every window
        // disables database actions immediately.
        session.lastConnectionError = reason
        session.state = .disconnected
        session.requiresTransportValidation = false
        session.connection = nil
        session.engine = nil
        session.hostTunnel = nil

        try? await connection?.close()
        await tunnel?.close()
        Logger.database.notice("Database transport became unavailable: \(reason, privacy: .public)")
    }

    enum SessionError: Error, LocalizedError {
        case notConnected
        case connectionLost
        case localNetworkPermissionDenied
        case invalidConfiguration(String)
        /// No saved password could be found for a service that needs one. Distinct from an empty
        /// password the user chose: that one is *found*, and connects.
        case credentialMissing(String)

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "No active database connection."
            case .connectionLost:
                return "The database connection timed out or was closed. Reconnect to continue."
            case .localNetworkPermissionDenied:
                return "Local Network access is off for Glass Power Tools. Allow it in Settings, then reconnect."
            case .invalidConfiguration(let message):
                return message
            case .credentialMissing(let name):
                // Kept for a caller that can genuinely tell a *missing* credential from a
                // deliberately absent one; the connect path no longer guesses that from the
                // keychain alone.
                return "No saved password was found for \(name). Open the service and enter it again."
            }
        }
    }
}

@MainActor
@Observable
class DatabaseSession {
    let connectionConfig: DatabaseConnectionConfig
    var state: SessionState = .disconnected
    /// What the session's workspace is looking at — "shop › articles", a SQL document's
    /// title — so Active's row says where you are and not only that you are connected
    /// (2026-09-22: Active should say which table the open workspace is on). Nil on the
    /// connection overview. The workspace publishes it on every change of its displayed tab;
    /// with two windows on one session the later change wins.
    var workspaceFocus: String?
    var connection: (any DatabaseConnection)?
    var engine: (any DatabaseEngine)?
    /// The live forward this session's transport rides, when `usesHostTunnel`. Owned here so
    /// disconnect, reconnect and a transport-closing cancel all tear it down with the socket.
    var hostTunnel: (any GlassHostPortForward)?
    /// How to open another one. Held so `reconnect` can re-open the tunnel the same way the
    /// original connect did, without the recovery UI having to re-resolve the host.
    var openForward: DatabaseSessionManager.PortForwardProvider?
    var queryHistory: [QueryResult] = []
    var currentDatabase: String?
    var lastConnectionError: String?
    var requiresTransportValidation = false
    var databaseStatistics: [String: DatabaseStatisticsSnapshot] = [:]
    let aiAssistant = AIAssistant()

    init(connectionConfig: DatabaseConnectionConfig) {
        self.connectionConfig = connectionConfig
        self.currentDatabase = connectionConfig.engine == .sqlite
            ? "main"
            : connectionConfig.defaultDatabase
    }
}

struct DatabaseStatisticsSnapshot: Sendable {
    static let timeToLive: TimeInterval = 15 * 60

    let database: String
    let statuses: [TableStatus]
    let capturedAt: Date

    func isFresh(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(capturedAt) < Self.timeToLive
    }

    func status(for table: String) -> TableStatus? {
        statuses.first { $0.name == table }
    }
}

private struct DatabaseStatisticsLoadKey: Hashable {
    let sessionID: UUID
    let database: String
}

private struct DatabaseStatisticsLoad {
    let id: UUID
    let task: Task<DatabaseStatisticsSnapshot, any Error>
}

private struct AggregateStatisticsLoad {
    let id: UUID
    let startedAt: Date
    let task: Task<[String: [TableStatus]], any Error>
}

enum QueryHistoryStatus: String, CaseIterable, Hashable, Identifiable, Sendable {
    case all
    case succeeded
    case failed

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct QueryHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sql: String
    let timestamp: Date
    let duration: TimeInterval
    let rowCount: Int?
    let affectedRows: UInt64?
    let error: String?
    let database: String?
    let connectionID: UUID
    let safety: SQLSafetyClassification

    init(
        id: UUID = UUID(),
        sql: String,
        timestamp: Date,
        duration: TimeInterval,
        rowCount: Int?,
        affectedRows: UInt64?,
        error: String?,
        database: String?,
        connectionID: UUID,
        safety: SQLSafetyClassification
    ) {
        self.id = id
        self.sql = sql
        self.timestamp = timestamp
        self.duration = duration
        self.rowCount = rowCount
        self.affectedRows = affectedRows
        self.error = error
        self.database = database
        self.connectionID = connectionID
        self.safety = safety
    }
}
