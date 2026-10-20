//
//  GlassDatabaseCapability.swift
//  Glass Power Tools — GlassDatabase
//
//  The database capability's public surface: the runtime the app owns, and the capability the
//  shell routes Connect through. Everything else in this module stays internal.
//
//  Shaped after `Sources/GlassTerminal/GlassTerminalCapability.swift`, which is the worked
//  example of every hook here.
//

import SwiftUI
import OSLog
import GlassConnectionKit
import GlassShell
import GlassConnectionUI
import GlassLayers

/// The shell's outcome callback for one connect attempt (see `GlassCapabilityOutcome`).
public typealias GlassDatabaseReport = @MainActor (GlassCapabilityOutcome) -> Void

/// Owns the database managers for the process. One per app, created in the composition root.
@MainActor @Observable
public final class GlassDatabaseRuntime {
    let connectionManager: ConnectionManager
    let sessionManager: DatabaseSessionManager
    let settingsManager: SettingsManager

    /// How to send the user back to the machine a connection belongs to, by its endpoint id.
    ///
    /// Supplied by the composition root, because answering "which host owns this connection?"
    /// needs the catalog and the database deliberately does not hold it — the same seam the
    /// editor's `openFolderAsProject` uses in the other direction.
    public var showHostForConnection: (@MainActor (UUID) -> Void)?

    /// The ⚡ in the workspace's toolbar. Supplied by the composition root.
    public var showActiveConnections: GlassShowActiveConnections?

    /// Everything the shell and the module's own surfaces can ask the database to do. One
    /// queue, consumed by the scenes in stage 3, so opening a workspace — and the failure
    /// alert when it cannot be opened — exists in exactly one place.
    enum Request {
        /// Connect to the saved connection behind this endpoint and open its workspace.
        /// `openForward` is nil when the host cannot lend one; `report` is the shell's callback.
        case connect(connectionID: UUID,
                     openForward: DatabaseSessionManager.PortForwardProvider?,
                     report: GlassDatabaseReport?)
        /// Open a SQL editor against an already-connected session.
        case openQueryEditor(sessionID: UUID)
        /// Show the failure alert with this message (a link with nothing behind it).
        case showFailure(String)
        #if DEBUG
        /// Screenshots (App/GlassDemoMode.swift): connect to this configuration without saving it,
        /// in a window with these settings of its own (W24), and This Window open over it.
        case demoConnect(DatabaseConnectionConfig, showsDiagram: Bool, windowSettings: GlassWindowOverrides?,
                         opensSettings: Bool, start: DemoStart)
        #endif
    }
    private(set) var requestSerial = 0
    private var pendingRequests: [Request] = []

    /// The one layering state, shared with the shell so no second material system exists.
    public let layers: GlassLayerStore

    /// How to ask the shell what a capability may do with a host. Set by the composition root,
    /// because the shell model owns the brokering and a capability must not hold the model.
    /// Only the setup sheet needs it: `open` is handed a `GlassCapabilityHostAccess` directly.
    public var hostAccess: (@MainActor (HostProfile) -> GlassCapabilityHostAccess)?
    /// The same, for a database being added with a machine that does not exist yet (the Add Host
    /// sheet): the machines another could tunnel through, and their trust, but no address.
    public var tunnelAccess: (@MainActor () -> GlassCapabilityHostAccess)?

    /// D26: points the saved-connection store at the shell's catalog. Called once, by the
    /// composition root — the only place that can see both. A method rather than an init parameter
    /// because the shell model does not exist when this runtime is built; the runtime is
    /// registered *with* the model.
    @MainActor
    public func connectToLibrary(store: any GlassServiceStore) {
        connectionManager.attach(store: .catalog(store))
    }

    /// `settingsDefaults` is where the database's own settings and saved queries live: the person's
    /// store, or a test's own suite.
    public init(layers: GlassLayerStore? = nil, settingsDefaults: UserDefaults = GlassUITestRun.settingsDefaults) {
        let resolvedLayers = layers ?? GlassLayerStore()
        self.layers = resolvedLayers
        connectionManager = ConnectionManager(loadImmediately: false)
        sessionManager = DatabaseSessionManager(loadImmediately: false)
        // The same store the shell uses, so appearance cannot drift between a database canvas
        // and a terminal canvas.
        settingsManager = SettingsManager(loadImmediately: false, defaults: settingsDefaults, layers: resolvedLayers)
        #if os(macOS)
        // The one Command Palette's search into the open connections' schemas and tables
        // (2026-10-13). Its connections are the library's (`registerPaletteConnections`).
        let sessionManager = self.sessionManager
        GlassCommandPaletteSources.register(id: "database", entries: { _ in [] }, destinations: { openWindow in
            let catalog = MacDatabasePaletteCatalog(sessionManager: sessionManager) { id, selection in
                let request = DatabaseWorkspaceWindowRequest.additional(sessionID: id, initialSelection: selection)
                openWindow(id: "database-workspace", value: sessionManager.registerWorkspace(request))
            }
            return { try await catalog.entries(for: $0) }
        })
        #endif
    }

    #if DEBUG
    /// Screenshots only: the real SQLite engine on a demo file, in a workspace, with nothing saved
    /// to the library. The file is imported the way a person's own would be. With
    /// `windowSettings`, the window keeps them as its own (W24); with `opensSettings`, Settings ▸
    /// This Window opens over it. `start` is what the window shows first.
    public func requestDemoDatabase(file: URL, name: String, showsDiagram: Bool = false,
                                    windowSettings: GlassWindowOverrides? = nil, opensSettings: Bool = false,
                                    start: DemoStart = .table) {
        do {
            let imported = try SQLiteFileImporter.importFile(at: file)
            enqueue(.demoConnect(DatabaseConnectionConfig(name: name, engine: .sqlite, host: imported.path,
                                                          port: 0, username: ""), showsDiagram: showsDiagram,
                                 windowSettings: windowSettings, opensSettings: opensSettings, start: start))
        } catch {
            enqueue(.showFailure("The demo database could not be opened: \(error.localizedDescription)"))
        }
    }

    /// Screenshots only: a database window's own settings (W24) — lighter glass, larger text and
    /// a smaller row limit — over the demo's Appearance.
    public static var demoWindowSettings: GlassWindowOverrides {
        var window = GlassWindowOverrides()
        window[GlassLayerSettings.opacity] = 0.35
        window[DatabaseWindowSettings.dataGridFontSize] = 16
        window[DatabaseWindowSettings.editorFontSize] = 16
        window[DatabaseWindowSettings.resultRowLimit] = 500
        return window
    }

    /// Screenshots only: what a demo database window shows first — the orders table's data, the
    /// server's overview (which shows the demo file's path on this device), or the `main`
    /// database's overview (W32).
    public enum DemoStart: Sendable {
        case table, server, database
    }

    /// Screenshots only: This Window opens over the next workspace window, once.
    @ObservationIgnored var demoOpensSettings = false

    func takeDemoOpensSettings() -> Bool {
        defer { demoOpensSettings = false }
        return demoOpensSettings
    }
    #endif

    func enqueue(_ request: Request) {
        pendingRequests.append(request)
        requestSerial &+= 1
    }

    func takeRequests() -> [Request] {
        defer { pendingRequests.removeAll() }
        return pendingRequests
    }

    /// True when a saved database connection exists for this endpoint id.
    public func hasConnection(id: UUID) -> Bool {
        connectionManager.connection(for: id) != nil
    }

    /// Saved connections the shell can surface (command palette, service actions).
    public var savedConnectionIDs: [UUID] { connectionManager.connections.map(\.id) }
    public func savedConnectionName(id: UUID) -> String? { connectionManager.connection(for: id)?.name }

    /// A live session over this saved connection, if one is open.
    func liveSessionID(for connectionID: UUID) -> UUID? {
        sessionManager.sessions.first { $0.value.connectionConfig.id == connectionID }?.key
    }

    // MARK: Saved queries for Shortcuts and Siri (D72)

    /// The saved queries Shortcuts and Siri can open: each one whose database is still saved, by name.
    /// Never the SQL — this goes into the App Group for the system to read.
    public var savedQueryEntries: [GlassDatabaseSavedQueryEntry] {
        settingsManager.loadIfNeeded()
        return settingsManager.savedQueries.compactMap { query in
            guard let connectionID = query.connectionID, hasConnection(id: connectionID) else { return nil }
            return GlassDatabaseSavedQueryEntry(id: query.id, name: query.name, connectionID: connectionID)
        }
    }

    /// Opens a saved query in a new SQL tab on its database, unrun. Returns the connection the shell
    /// should connect, the way the library's Connect does, when none is live; nil when the live
    /// workspace was brought forward, or when there is nothing to open — which the failure alert says.
    public func openSavedQuery(_ id: UUID) -> UUID? {
        settingsManager.loadIfNeeded()
        guard let query = settingsManager.savedQueries.first(where: { $0.id == id }) else {
            enqueue(.showFailure("That saved query is no longer saved on this device."))
            return nil
        }
        guard let connectionID = query.connectionID, hasConnection(id: connectionID) else {
            enqueue(.showFailure("The database this query was saved for is no longer in your library. Open “\(query.name)” from another database's Saved Queries."))
            return nil
        }
        sessionManager.queueQuery(name: query.name, sql: query.sql, for: connectionID)
        settingsManager.useSavedQuery(id)
        if let sessionID = liveSessionID(for: connectionID) {
            enqueue(.openQueryEditor(sessionID: sessionID))
            return nil
        }
        return connectionID
    }
}

// MARK: - SQL from a terminal (2026-10-20)

/// A saved database SQL from a terminal can open in.
public struct GlassDatabaseSQLDestination: Sendable, Equatable {
    public let id: UUID
    public let title: String
}

extension GlassDatabaseRuntime {
    /// The saved databases SQL in a terminal opens in: `machineDatabases` — the Database services of
    /// the terminal's machine, which the shell's catalog knows — then those reached through the
    /// terminal's server or servers (D45; This Mac's machine's SSH too, D86), which only the
    /// database's own records say. Each once, by name, with
    /// its engine and the database it opens in.
    public func sqlDestinations(machineDatabases: [UUID], reachedThrough terminalEndpoints: Set<UUID>) -> [GlassDatabaseSQLDestination] {
        var ids = machineDatabases.filter { hasConnection(id: $0) }
        for config in connectionManager.connections
        where config.tunnelServiceID.map(terminalEndpoints.contains) == true && !ids.contains(config.id) {
            ids.append(config.id)
        }
        return ids.compactMap { id in
            connectionManager.connection(for: id).map { config in
                let detail = [config.engine.displayName, config.defaultDatabase].compactMap { $0 }.filter { !$0.isEmpty }
                return GlassDatabaseSQLDestination(id: id, title: "\(config.name) — \(detail.joined(separator: " · "))")
            }
        }
    }

    /// Open in SQL Editor: `sql` in a new query tab on that database, never run; the table it names,
    /// where the server has it, opened beside it with its database the active one. Returns the
    /// connection the shell should connect, as `openSavedQuery` does, when none is live.
    public func openSQL(_ sql: String, connectionID: UUID) -> UUID? {
        guard hasConnection(id: connectionID) else {
            enqueue(.showFailure("That database is no longer in your library. Add it again from its machine's Services."))
            return nil
        }
        sessionManager.queueQuery(name: QueryDocumentTitle.fallback(for: sql), sql: sql, for: connectionID, findsTable: true)
        if let sessionID = liveSessionID(for: connectionID) {
            enqueue(.openQueryEditor(sessionID: sessionID))
            return nil
        }
        return connectionID
    }
}

/// A saved query as the system sees it: its name and the database it belongs to.
public struct GlassDatabaseSavedQueryEntry: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let connectionID: UUID
}

/// The shell's database capability. A service is created complete through the shell's host
/// sheet: the draft commits the connection record and its password under the shell's endpoint
/// id, which is the link. `open` connects to that record; a link with nothing behind it is
/// reported as such rather than silently doing nothing.
@MainActor
public final class GlassDatabaseCapability: GlassCapability {
    public let kind: HostServiceKind = .database
    public let displayName = "Database"
    /// The database's real icon is Heroicons' `circle-stack`, vendored in the kit and drawn
    /// through `GlassServiceIcon` — `GlassServicePresentation.symbol(for: .database)` returns
    /// it. That is not an SF Symbol name, and this property is one: the shell's tool rows feed
    /// names like it straight to `Image(systemName:)` (`GlassShellLibraryView.swift:214`), where
    /// "circle-stack" would render nothing at all. So this is a real SF Symbol that reads the
    /// same way, and the vendored icon stays the canonical one.
    public let symbolName = "cylinder.split.1x2"
    private let runtime: GlassDatabaseRuntime

    public init(runtime: GlassDatabaseRuntime) { self.runtime = runtime }

    /// Settings ▸ Databases. The page existed (glassdb's settings window) and nothing presented it,
    /// so query limits, history and the editor's settings could not be changed (help audit).
    public var settingsPages: [GlassCapabilitySettingsPage] {
        let settings = runtime.settingsManager
        return [GlassCapabilitySettingsPage(id: "database.general", title: "Databases", systemImage: "cylinder.split.1x2") {
            AnyView(SettingsView(isShellPage: true).environment(settings))
        }]
    }

    // MARK: Open sessions (D1)

    /// One row per live session, by connection name.
    ///
    /// By name rather than newest first, which is what the plan asked for: the sessions are held
    /// in a dictionary and nothing records when each was opened. A stable order that is true
    /// beats an order that looks like recency and is not.
    ///
    /// `activate` reuses `openQueryEditor`, which already means "put this session's workspace on
    /// the screen" and already routes in place on a phone. Nothing new was needed here.
    public func openSessions() -> [GlassOpenSession] {
        let manager = runtime.sessionManager
        // Keyed by the *session* id, which `connect` mints fresh — not the connection's id, so
        // one saved connection opened twice is honestly two rows. The id breaks the tie when two
        // of them share a name, so the order does not shuffle between draws.
        return manager.sessions
            .sorted {
                let byName = $0.value.connectionConfig.name.localizedStandardCompare($1.value.connectionConfig.name)
                return byName == .orderedSame ? $0.key.uuidString < $1.key.uuidString : byName == .orderedAscending
            }
            .map { sessionID, session in
                let config = session.connectionConfig
                return GlassOpenSession(
                    id: Self.sessionID(sessionID: sessionID),
                    title: config.name,
                    subtitle: Self.subtitle(engine: config.engine, state: session.state, focus: session.workspaceFocus),
                    symbolName: symbolName,
                    endpointIDs: [EndpointID(rawValue: config.id)],
                    activate: { [runtime] in runtime.enqueue(.openQueryEditor(sessionID: sessionID)) },
                    close: { Task { await manager.disconnect(sessionID: sessionID) } },
                    isConnected: session.state.isConnected,
                    lastActivity: { session.lastActivityAt }
                )
            }
    }

    /// The id this capability gives a session in the switcher; the workspace's own chrome
    /// excludes itself with it.
    public static func sessionID(sessionID: UUID) -> String {
        "database:\(sessionID.uuidString)"
    }

    /// The engine, and the state only when it is worth saying. "PostgreSQL" reads better than
    /// "PostgreSQL · Connected" on every row, and a session that is *not* connected is the case
    /// the user needs told.
    ///
    /// Connected, the row also says where the workspace is: "MySQL · shop › articles".
    static func subtitle(engine: DatabaseEngineType, state: SessionState, focus: String? = nil) -> String {
        switch state {
        case .connected: focus.map { "\(engine.displayName) · \($0)" } ?? engine.displayName
        case .connecting(let stage): "\(engine.displayName) · \(stage.rawValue)"
        case .disconnected: "\(engine.displayName) · Disconnected"
        case .error: "\(engine.displayName) · Not connected"
        }
    }

    // MARK: Setup (the shell's host sheet)

    public func makeSetupDraft() -> any GlassServiceDraft {
        // No host context here: the Add Host sheet has no host yet, so whether a forward is
        // possible is genuinely unknown and the tunnel row says nothing rather than guessing.
        let access = runtime.tunnelAccess?()
        return DatabaseServiceDraft(connectionManager: runtime.connectionManager,
                                    tunnelChoices: access?.tunnelChoices ?? [],
                                    resolveTrustThrough: Self.trustThrough(access))
    }

    public func setupDraft(for service: HostServiceLink, host: HostProfile) -> (any GlassServiceDraft)? {
        guard let config = runtime.connectionManager.connection(for: service.endpointID.rawValue) else { return nil }
        // D14: this host is committed, so its fingerprint can be settled here rather than at
        // first connect. The resolver is the shell's, brokered to whichever capability owns
        // `.ssh` — this module still never imports it.
        var resolveTrust: (@MainActor @Sendable () async -> GlassHostTrustOutcome)?
        let access = runtime.hostAccess?(host)
        if let access {
            resolveTrust = { await access.resolveHostTrust() }
        }
        return DatabaseServiceDraft(editing: config,
                                    connectionManager: runtime.connectionManager,
                                    hostCanForwardPorts: hostCanForwardPorts(host),
                                    resolveHostTrust: resolveTrust,
                                    tunnelChoices: access?.tunnelChoices ?? [],
                                    resolveTrustThrough: Self.trustThrough(access))
    }

    /// The forward a connection opens, if it wants one: through this machine's own Terminal
    /// to loopback, or through another machine's to this database's own address as that machine
    /// sees it — a private IP behind an app server — whatever host the caller asks for.
    static func forwardProvider(for config: DatabaseConnectionConfig,
                                hostAccess: GlassCapabilityHostAccess) -> DatabaseSessionManager.PortForwardProvider? {
        guard config.usesHostTunnel else { return nil }
        if let through = config.tunnelServiceID {
            let address = config.host
            return { _, port in
                try await hostAccess.forwardPort(through: EndpointID(rawValue: through), toHost: address, port: port)
            }
        }
        guard hostAccess.canForwardPorts else { return nil }
        // Through this machine: to the database's address as the machine sees it, when one is
        // given, else to the loopback asked for.
        let target = config.tunnelTargetHost
        return { remoteHost, port in try await hostAccess.forwardPort(toHost: target ?? remoteHost, port: port) }
    }

    /// Settles another machine's host-key trust, for a database tunnelled through it.
    private static func trustThrough(_ access: GlassCapabilityHostAccess?)
    -> (@MainActor @Sendable (EndpointID) async -> GlassHostTrustOutcome)? {
        guard let access else { return nil }
        return { service in await access.resolveHostTrust(through: service) }
    }

    public func removeService(_ service: HostServiceLink, host: HostProfile) async throws {
        guard let config = runtime.connectionManager.connection(for: service.endpointID.rawValue) else { return }
        // Order matters: the credential first, then the record. `ConnectionManager.delete`
        // already removes the credentials and any managed SQLite working copy transactionally.
        try await runtime.connectionManager.delete(config)
    }

    /// The saved record's address, for hosts that predate addresses on the host record. SQLite's
    /// "host" is a file path, not a machine, so it is never offered as one.
    public func knownAddress(service: HostServiceLink, host: HostProfile) -> String? {
        guard let config = runtime.connectionManager.connection(for: service.endpointID.rawValue),
              config.engine != .sqlite else { return nil }
        let address = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }

    /// The server's port, for the availability dot. None for SQLite (a file) or for a database
    /// reached through the machine's SSH tunnel, whose port is not meant to answer from here.
    public func knownPort(service: HostServiceLink, host: HostProfile) -> Int? {
        guard let config = runtime.connectionManager.connection(for: service.endpointID.rawValue),
              config.engine != .sqlite, !config.usesHostTunnel else { return nil }
        return config.port
    }

    /// The machine's address changed in the shell: every saved connection that is a service of
    /// that host follows it, so the machine's identity is edited once. SQLite records are left
    /// alone — their `host` is a managed file path.
    public func hostAddressDidChange(host: HostProfile, address: String?) {
        // Same shape as the terminal's and the desktop's: the shell reports the change
        // synchronously, and each following record is a catalog write.
        let runtime = self.runtime
        Task { @MainActor in await runtime.applyHostAddress(address, to: host) }
    }

    // MARK: Connect

    public func open(service: HostServiceLink, host: HostProfile, report: @escaping GlassDatabaseReport) {
        open(service: service, host: host,
             hostAccess: GlassCapabilityHostAccess(address: host.address), report: report)
    }

    public func open(service: HostServiceLink, host: HostProfile, hostAccess: GlassCapabilityHostAccess,
                     report: @escaping GlassDatabaseReport) {
        let connectionID = service.endpointID.rawValue
        guard let config = runtime.connectionManager.connection(for: connectionID) else {
            // A link another family app recorded with no saved connection behind it.
            let message = "\(service.displayName) has no saved database configuration. Edit the service to set it up, or remove it."
            runtime.enqueue(.showFailure(message))
            report(.failed(message))
            return
        }
        // D7: the forward, when this service wants one, is the host's own SSH service. The
        // shell brokers it; this module never learns which capability served it.
        let openForward = Self.forwardProvider(for: config, hostAccess: hostAccess)
        runtime.enqueue(.connect(connectionID: connectionID, openForward: openForward, report: report))
    }

    // MARK: Shell hooks

    /// D26: read the saved connections now that the catalog can answer. Idempotent — `load()`
    /// refuses a store that is not readable yet, and this is called after every catalog load.
    public func catalogDidLoad() {
        runtime.connectionManager.load()
    }

    /// Query is a tool rather than a service: it rides this database's connection, credentials
    /// and session, exactly as Files rides the terminal's. Offered only once the service has a
    /// saved connection behind it.
    public func serviceTools(service: HostServiceLink, host: HostProfile) -> [GlassServiceTool] {
        let connectionID = service.endpointID.rawValue
        guard runtime.hasConnection(id: connectionID) else { return [] }
        let runtime = self.runtime
        return [
            GlassServiceTool(id: "query-\(connectionID.uuidString.lowercased())",
                             title: "Query",
                             symbolName: "text.and.command.macwindow",
                             subtitle: "Write and run SQL against this database") {
                if let sessionID = runtime.liveSessionID(for: connectionID) {
                    runtime.enqueue(.openQueryEditor(sessionID: sessionID))
                } else {
                    // Nothing is connected yet, so there is nothing to query. Say that rather
                    // than opening an editor with no session behind it.
                    runtime.enqueue(.showFailure("Connect this database first, then open Query."))
                }
            }
        ]
    }

    /// Whether a forward can actually be borrowed for this machine, for telling the user in the
    /// setup sheet before they commit.
    ///
    /// **Ask the shell; never infer it from the services.** The presence of an `.ssh` service is
    /// not the same question: the built-in local host has one and is deliberately excluded from
    /// the broker (D8), because its services are already local and must never tunnel. Inferring
    /// it here produced an Advanced row offering a tunnel that would never be used — nothing
    /// failed at connect, which is precisely why it would have survived.
    private func hostCanForwardPorts(_ host: HostProfile) -> Bool {
        runtime.hostAccess?(host).canForwardPorts ?? false
    }
}

/// Which saved connections follow a host's address, and to what. Pure so it is testable without
/// a Keychain, mirroring `GlassTerminalHostAddressSync`.
enum GlassDatabaseHostAddressSync {
    /// Persists the change for every following connection; one that fails is logged and skipped
    /// so a single bad record does not stop the rest. Returns the ids updated. A cleared address
    /// leaves the records alone: they still need something to connect to.
    @MainActor @discardableResult
    static func apply(_ address: String?, to host: HostProfile, in manager: ConnectionManager) async -> [UUID] {
        guard let address else { return [] }
        var applied: [UUID] = []
        for config in connections(manager.connections, following: host, address: address) {
            do {
                try await manager.update(config)
                applied.append(config.id)
            } catch {
                Logger.connections.error(
                    "Host address sync skipped \(config.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return applied
    }

    static func connections(_ connections: [DatabaseConnectionConfig], following host: HostProfile,
                            address: String) -> [DatabaseConnectionConfig] {
        let owned = Set(host.services.filter { $0.kind == .database }.map(\.endpointID.rawValue))
        return connections.compactMap { config in
            // A SQLite record's `host` is a managed file path, not a machine address.
            guard owned.contains(config.id), config.engine != .sqlite, config.host != address else { return nil }
            var updated = config
            updated.host = address
            return updated
        }
    }
}

extension GlassDatabaseRuntime {
    @discardableResult
    func applyHostAddress(_ address: String?, to host: HostProfile) async -> [UUID] {
        await GlassDatabaseHostAddressSync.apply(address, to: host, in: connectionManager)
    }
}
