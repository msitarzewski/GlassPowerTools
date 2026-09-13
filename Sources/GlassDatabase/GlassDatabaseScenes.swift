//
//  GlassDatabaseScenes.swift
//  Glass Power Tools — GlassDatabase
//
//  glassdb's window scenes (`../glassdb/glassdb/glassdbApp.swift:56-99`), minus the Connections
//  window and Settings, which the shell owns. The app includes this scene next to the shell's
//  and the terminal's, exactly as it includes `GlassTerminalScenes`.
//

import SwiftUI
import GlassShell
import GlassLayers
import GlasSecretStore

public struct GlassDatabaseScenes: Scene {
    private let runtime: GlassDatabaseRuntime
    private var sessionManager: DatabaseSessionManager { runtime.sessionManager }
    private var settingsManager: SettingsManager { runtime.settingsManager }

    public init(runtime: GlassDatabaseRuntime) { self.runtime = runtime }

    public var body: some Scene {
        // The database workspace: schema sidebar, tabs, query editor and results.
        WindowGroup(id: "database-workspace", for: UUID.self) { $workspaceID in
            if let workspaceID {
                let request = sessionManager.workspaceRequest(for: workspaceID)
                DatabaseWorkspaceView(sessionID: request.sessionID,
                                      initialSelection: request.initialSelection)
                    .environment(runtime)
                    .environment(sessionManager)
                    .environment(settingsManager)
                    .glassLayers(runtime.layers)
                    .onDisappear { sessionManager.releaseWorkspace(workspaceID) }
            } else {
                ContentUnavailableView(
                    "Database Workspace Not Found",
                    systemImage: "cylinder.split.1x2",
                    description: Text("Open a database from the library to begin.")
                )
            }
        }
        #if os(visionOS)
        .windowStyle(.plain)
        #endif
        #if !os(iOS)
        .defaultSize(width: 1400, height: 900)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif
        // The Database menu bar. `DatabaseCommands` was written, guarded for macOS, and then
        // attached to nothing: until 2026-09-12 its only reference anywhere in the codebase was
        // its own declaration, so the Query menu, ⌘↩ Run Statement, ⌘N/⌘O/⌘S for SQL documents
        // and the database command palette were all unreachable. The terminal attaches its
        // equivalent at `GlassTerminalScenes.swift:57`; this is the line that was missing.
        //
        // Found by the first UI test that opened a window on this capability — no unit test can
        // see an unattached `Commands`, because the type is perfectly valid on its own.
        #if os(macOS)
        .commands {
            DatabaseCommands(connectionManager: runtime.connectionManager,
                             sessionManager: sessionManager)
        }
        #endif

        // Detached result grids — pin a result beside the query that produced it.
        WindowGroup(id: "database-results", for: UUID.self) { $resultSetID in
            if let resultSetID {
                ResultsGridView(resultSetID: resultSetID)
                    .environment(sessionManager)
                    .environment(settingsManager)
                    .glassLayers(runtime.layers)
            } else {
                ContentUnavailableView(
                    "Result Not Found",
                    systemImage: "tablecells",
                    description: Text("Detach a result from a query to open it here.")
                )
            }
        }
        #if !os(iOS)
        .defaultSize(width: 1000, height: 600)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif
    }
}

/// Wraps the shell's library window with the database's request handling: the connect the shell
/// asked for, the workspace window it opens, and the failure alert when there is nothing behind
/// a link. The mirror of `GlassTerminalBootstrap`, and the only place that calls `openWindow`
/// for this capability — a capability cannot reach the environment itself.
public struct GlassDatabaseBootstrap<Content: View>: View {
    private let runtime: GlassDatabaseRuntime
    private let content: Content
    @Environment(\.openWindow) private var openWindow
    @State private var failureMessage: String?
    #if os(iOS)
    @State private var router = DatabaseIOSRouter()
    #endif

    public init(runtime: GlassDatabaseRuntime, @ViewBuilder content: () -> Content) {
        self.runtime = runtime
        self.content = content()
    }

    public var body: some View {
        platformRoot
            .environment(runtime)
            .environment(runtime.connectionManager)
            .environment(runtime.sessionManager)
            .environment(runtime.settingsManager)
            #if os(iOS)
            .environment(router)
            #endif
            .task {
                runtime.connectionManager.loadIfNeeded()
                runtime.sessionManager.loadIfNeeded()
                runtime.settingsManager.loadIfNeeded()
            }
            // One drain per enqueue. `requestSerial` rather than the array so a request that
            // arrives while another is in flight is still seen.
            .onChange(of: runtime.requestSerial) { _, _ in
                for request in runtime.takeRequests() { handle(request) }
            }
            .alert("Database", isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { failureMessage = nil } }
            )) {
                Button("OK", role: .cancel) { failureMessage = nil }
            } message: {
                Text(failureMessage ?? "")
            }
    }

    @ViewBuilder
    private var platformRoot: some View {
        #if os(iOS)
        // iPhone routes the workspace inside the primary scene; iPad keeps `openWindow`.
        if let request = router.workspaceRequest,
           runtime.sessionManager.sessions[request.sessionID] != nil {
            DatabaseWorkspaceView(sessionID: request.sessionID, initialSelection: request.initialSelection)
                .id(request.id)
        } else {
            content
        }
        #else
        content
        #endif
    }

    private func handle(_ request: GlassDatabaseRuntime.Request) {
        switch request {
        case .connect(let connectionID, let openForward, let report):
            connect(connectionID: connectionID, openForward: openForward, report: report)
        case .openQueryEditor(let sessionID):
            present(DatabaseWorkspaceWindowRequest.primary(sessionID: sessionID))
        case .showFailure(let message):
            failureMessage = message
        }
    }

    /// Connects, then opens the workspace. `report` is called exactly once, at the attempt's
    /// terminal state, so the shell stamps "last connected" only on a real connection.
    private func connect(connectionID: UUID,
                         openForward: DatabaseSessionManager.PortForwardProvider?,
                         report: GlassDatabaseReport?) {
        guard let config = runtime.connectionManager.connection(for: connectionID) else {
            let message = "The saved database connection is no longer available."
            failureMessage = message
            report?(.failed(message))
            return
        }
        Task {
            do {
                let password = try Self.storedPassword(for: config)
                let sessionID = try await runtime.sessionManager.connect(
                    config: config, password: password, openForward: openForward)
                runtime.connectionManager.updateLastConnected(connectionID)
                report?(.connected)
                present(DatabaseWorkspaceWindowRequest.primary(sessionID: sessionID))
            } catch {
                let message = error.localizedDescription
                failureMessage = message
                report?(.failed(message))
            }
        }
    }

    /// SQLite has no credential; every other engine reads the one this service saved. A missing
    /// password is passed through as empty so the server's own refusal is what the user sees,
    /// rather than this layer guessing that the password is the problem.
    private static func storedPassword(for config: DatabaseConnectionConfig) throws -> String {
        guard config.engine.supportsCredentials else { return "" }
        // Deliberately NOT caught here, unlike before: `notFound` used to become `""`, which a
        // server configured for passwordless auth will happily accept — connecting with no
        // credential where the user believes one is required. A password the user *chose* to leave
        // empty is found and returns "" from this call; only a genuinely absent one throws, and the
        // caller reports it rather than guessing. See `DatabaseSessionManager.storedCredentials`.
        return try KeychainManager.retrievePassword(for: config)
    }

    private func present(_ request: DatabaseWorkspaceWindowRequest) {
        let windowID = runtime.sessionManager.registerWorkspace(request)
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            router.showWorkspace(request)
            return
        }
        #endif
        openWindow(id: "database-workspace", value: windowID)
    }
}
