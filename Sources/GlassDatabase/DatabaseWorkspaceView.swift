//
//  DatabaseWorkspaceView.swift
//  glassdb
//
//  Unified workspace: schema sidebar + context-sensitive detail surface
//  Selection in sidebar drives the detail view (DBeaver-style model)
//

import SwiftUI
import GlassLayers
import GlassShell
import GlassDBKit
import UniformTypeIdentifiers
import GlassConnectionUI
#if os(iOS)
import UIKit
#endif

// MARK: - Selection Model

enum WorkspaceSelection: Hashable, Codable, Sendable {
    case connection
    case database(String)
    case table(database: String, table: String)
    case query(id: UUID)

    var title: String {
        switch self {
        case .connection: "Overview"
        case .database(let database): database
        case .table(_, let table): table
        case .query: "SQL"
        }
    }

    var systemImage: String {
        switch self {
        case .connection: "externaldrive.connected.to.line.below"
        case .database: "cylinder"
        case .table: "tablecells"
        case .query: "text.page"
        }
    }

    var helpText: String {
        switch self {
        case .connection: "Connection overview"
        case .database(let database): "Database inspector for \(database)"
        case .table(let database, let table): "Table editor for \(database).\(table)"
        case .query: "SQL editor"
        }
    }

    var isClosable: Bool {
        switch self {
        case .connection: false
        case .database, .table, .query: true
        }
    }

    var commandWEditorTarget: DatabaseCommandWEditorTarget {
        switch self {
        case .connection: .none
        case .query, .database, .table: .workspace
        }
    }

    var usesOverviewRefreshAction: Bool {
        switch self {
        case .connection, .database: true
        case .table, .query: false
        }
    }
}

enum DatabaseCommandWEditorTarget: Equatable {
    case none
    case workspace
}

/// Scene value for a database workspace. The session identifies the shared
/// live connection while `id` identifies one independent window over it.
struct DatabaseWorkspaceWindowRequest: Hashable, Codable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let initialSelection: WorkspaceSelection

    static func primary(sessionID: UUID) -> Self {
        Self(id: sessionID, sessionID: sessionID, initialSelection: .connection)
    }

    static func additional(
        sessionID: UUID,
        initialSelection: WorkspaceSelection = .connection,
        id: UUID = UUID()
    ) -> Self {
        Self(id: id, sessionID: sessionID, initialSelection: initialSelection)
    }
}

struct WorkspaceTabState: Equatable {
    private(set) var tabs: [WorkspaceSelection]
    private(set) var selected: WorkspaceSelection
    private(set) var previewed: WorkspaceSelection?

    var displayed: WorkspaceSelection {
        previewed ?? selected
    }

    init(initialSelection: WorkspaceSelection = .connection) {
        // Overview is the only seeded tab; SQL documents are created on
        // demand (⌘N, sidebar, or Overview) per the unified-workspace
        // fallback decision.
        tabs = initialSelection == .connection
            ? [.connection]
            : [.connection, initialSelection]
        selected = initialSelection
        previewed = nil
    }

    mutating func open(_ destination: WorkspaceSelection) {
        previewed = nil
        if case .database = destination {
            tabs.removeAll { existing in
                if case .database = existing { return true }
                return false
            }
        }
        if !tabs.contains(destination) {
            tabs.append(destination)
        }
        selected = destination
    }

    /// Puts durable drafts back as tabs without stealing the selection: reopening a workspace
    /// lands on the overview it was opened with, with the restored SQL waiting in the tab strip.
    mutating func restore(_ destinations: [WorkspaceSelection]) {
        for destination in destinations where !tabs.contains(destination) {
            tabs.append(destination)
        }
    }

    mutating func preview(_ destination: WorkspaceSelection) {
        switch destination {
        case .database, .table:
            // SwiftUI can deliver the single-click callback after the
            // simultaneous double-click callback. Once activation has opened
            // and selected this destination, that trailing click must not
            // cover the live tab with an ephemeral preview.
            guard selected != destination || !tabs.contains(destination) else {
                previewed = nil
                return
            }
            previewed = destination
        case .connection, .query:
            open(destination)
        }
    }

    mutating func clearPreview() {
        previewed = nil
    }

    /// The SQL document whose editor is visible and interactive. Previews
    /// overlay the tab strip's selection, so no document is active while one
    /// is shown. Menu-bar command routing consults only this document's
    /// registered editor handlers.
    var activeQueryDocumentID: UUID? {
        guard previewed == nil,
              case .query(let id) = selected else { return nil }
        return id
    }

    @discardableResult
    mutating func close(_ destination: WorkspaceSelection) -> Bool {
        guard destination.isClosable,
              let index = tabs.firstIndex(of: destination) else { return false }
        let wasSelected = selected == destination
        tabs.remove(at: index)
        previewed = nil
        if wasSelected {
            selected = tabs[min(index, tabs.count - 1)]
        }
        return true
    }
}

enum DatabaseWorkspaceConnectionsRoute: Equatable {
    case inAppRouter
    case window

    static func resolve(isPhone: Bool) -> Self {
        isPhone ? .inAppRouter : .window
    }
}

// MARK: - Workspace View

struct DatabaseWorkspaceView: View {
    let sessionID: UUID

    /// Optional: the scenes inject it, and a preview or a test may not.
    @Environment(GlassDatabaseRuntime.self) private var runtime: GlassDatabaseRuntime?
    @Environment(DatabaseSessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(DatabaseIOSRouter.self) private var iOSRouter
    #endif
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var appliedInitialSidebarVisibility = false
    @State private var tableRunAvailability = SQLRunAvailability()
    @State private var tabState: WorkspaceTabState
    @State private var queryDocuments: [UUID: QueryDocumentTab]
    @State private var tableSQLDrafts: [WorkspaceSelection: QueryDocumentTab] = [:]
    @State private var databases: [String] = []
    @State private var overviewRefreshTrigger = 0
    @State private var queryPendingClose: WorkspaceSelection?
    @State private var queryPendingExport: WorkspaceSelection?
    @State private var closeQueryAfterExport = false
    @State private var showingQueryExporter = false
    @State private var showingSQLImporter = false
    @State private var queryDocumentError: String?
    /// Editor-private verbs registered per document id for each alive editor,
    /// including hidden ZStack members. Only the active tab's bundle is ever
    /// consulted, so stale registrations cannot clobber command routing.
    @State private var editorCommandHandlers: [UUID: QueryEditorCommandHandlers] = [:]
    /// This window's identity for the draft store's restore claim. `@State` because a SwiftUI
    /// `View` is a value that is rebuilt constantly; a stored `let` would mint a new UUID per
    /// rebuild and every window would look like a new claimant.
    @State private var workspaceInstanceID = UUID()
    /// The connection whose drafts this workspace owns, captured once. Read from here rather than
    /// from `session`, which goes away on a dropped connection while the drafts must not.
    @State private var draftConnectionID: UUID?
    @State private var hasRestoredDrafts = false

    private var session: DatabaseSession? {
        sessionManager.session(for: sessionID)
    }

    init(sessionID: UUID, initialSelection: WorkspaceSelection = .connection) {
        self.sessionID = sessionID
        let initialTabState = WorkspaceTabState(initialSelection: initialSelection)
        _tabState = State(initialValue: initialTabState)
        _queryDocuments = State(initialValue: Dictionary(uniqueKeysWithValues: initialTabState.tabs.compactMap {
            guard case .query(let id) = $0 else { return nil }
            return (id, QueryDocumentTab(id: id))
        }))
    }

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The phone's stack: databases, the tables inside one, and the detail of what was chosen.
    ///
    /// **`NavigationPath`, not `[DatabaseCompactRoute]`.** A typed path accepts only its own
    /// type, and the schema browser pushes a destination of its own for a database's tables
    /// (`SchemaBrowserView.compactDatabaseList`) — against a typed path those links silently do
    /// nothing, which is precisely what "now the databases can't be clicked" was (2026-09-19).
    @State private var compactPath = NavigationPath()
    /// The depth the detail sits at, or nil when it is not on the stack. A `NavigationPath` will
    /// not say what is in it, and "is the detail already showing" has to be answered before
    /// pushing a second one.
    @State private var detailDepth: Int?
    #endif

    var body: some View {
        layout
        .databaseWorkspaceWindowBackground()
        .onPreferenceChange(SQLRunAvailabilityKey.self) { tableRunAvailability = $0 }
        .databaseWorkspaceWindowChrome()
        #if os(macOS)
        .focusedSceneValue(\.macCommandCenterEntries, commandCenterDestinations)
        // ⌘N, while a database workspace is focused, means a new SQL document. The shell owns the
        // one File ▸ New item and each window says what it makes (`GlassShellFileCommands`).
        .focusedSceneValue(\.glassNewItem, GlassNewItemAction(title: "New SQL Document") {
            openQueryDocument()
        })
        #endif
        // ⌘W closes the active tab, not the workspace window with every tab in it. The
        // interception that makes this possible moved to the shell on 2026-09-16
        // (`GlassCloseCommandRouter`), because every window needs it and only this one had it.
        .glassCloseCommandTarget(priority: .workspace) {
            closeFocusedEditor()
        }
        .overlay {
            connectionRecoveryOverlay
        }
        .navigationTitle(detailTitle)
        #if os(macOS)
        .navigationSubtitle(detailSubtitle)
        // The passive AppKit material supplies frost. Do not paint a second
        // SwiftUI toolbar background over it or change toolbar visibility.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        #endif
        .databaseSidebarChrome()
        .focusedSceneValue(\.databaseWorkspaceCommandActions, workspaceCommandActions)
        .task(id: sessionID) {
            await monitorConnectionState()
        }
        .onAppear {
            guard !appliedInitialSidebarVisibility else { return }
            appliedInitialSidebarVisibility = true
            #if os(macOS)
            columnVisibility = .all
            #else
            columnVisibility = settingsManager.showSidebarByDefault ? .all : .detailOnly
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .glassdbOpenSQLDraft)) { notification in
            guard let request = notification.object as? SQLDraftRequest,
                  request.sessionID == sessionID else { return }
            openQueryDocument(QueryDocumentTab(text: request.sql))
        }
        .onReceive(NotificationCenter.default.publisher(for: .glassdbOpenTable)) { notification in
            // Following a foreign key opens a *different* table, and the tab strip is the
            // workspace's. Same seam as `.glassdbOpenSQLDraft` above, so a detail view still does
            // not reach into navigation itself. The `sessionID` guard matters: with several
            // workspaces open, only the one the request names may act on it.
            guard let request = notification.object as? OpenTableRequest,
                  request.sessionID == sessionID else { return }
            openWorkspace(.table(database: request.database, table: request.table))
        }
        .fileExporter(
            isPresented: $showingQueryExporter,
            document: queryPendingExport.flatMap { sqlDocument(for: $0) }.map {
                SQLTextDocument(text: $0.text)
            },
            contentType: .plainText,
            defaultFilename: queryExportFilename
        ) { result in
            completeQueryExport(result)
        }
        .fileImporter(
            isPresented: $showingSQLImporter,
            allowedContentTypes: QueryEditorView.sqlDocumentTypes,
            allowsMultipleSelection: false
        ) { result in
            importSQLDocument(result)
        }
        .alert("Save Changes?", isPresented: .init(
            get: { queryPendingClose != nil },
            set: { if !$0 { queryPendingClose = nil } }
        )) {
            Button("Cancel", role: .cancel) { queryPendingClose = nil }
                .keyboardShortcut(.cancelAction)
            Button("Don't Save", role: .destructive) {
                guard let id = queryPendingClose else { return }
                queryPendingClose = nil
                performCloseWorkspace(id)
            }
            .keyboardShortcut("d", modifiers: .command)
            Button("Save…") {
                guard let id = queryPendingClose else { return }
                queryPendingClose = nil
                queryPendingExport = id
                closeQueryAfterExport = true
                showingQueryExporter = true
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("Closing this editor discards its SQL. Save it to a file to keep a copy.")
        }
        .alert("SQL Document Error", isPresented: .init(
            get: { queryDocumentError != nil },
            set: { if !$0 { queryDocumentError = nil } }
        )) {
            Button("OK", role: .cancel) { queryDocumentError = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(queryDocumentError ?? "")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    _ = await sessionManager.validateSessionAfterForeground(
                        sessionID: sessionID
                    )
                }
            } else {
                // Leaving the foreground is the last reliable moment before a quit, so the
                // debounced draft writes are forced out here rather than waited on.
                SQLDraftStore.shared.flush()
                sessionManager.noteSessionSuspended(sessionID: sessionID)
            }
        }
        .onChange(of: session?.connectionConfig.id, initial: true) { _, _ in
            restoreDraftsIfNeeded()
        }
        .onDisappear {
            SQLDraftStore.shared.flush()
            if let draftConnectionID {
                SQLDraftStore.shared.releaseDrafts(
                    connectionID: draftConnectionID,
                    workspace: workspaceInstanceID
                )
            }
        }
    }

    // MARK: - Durable Drafts

    /// Restores this connection's drafts once, the first time a connection identity is known.
    ///
    /// Only `.query` drafts become tabs. A `.table` draft goes back into `tableSQLDrafts`, where
    /// it reappears when the user opens that table again — restoring it as a tab would open table
    /// editors the user never asked for.
    private func restoreDraftsIfNeeded() {
        guard !hasRestoredDrafts, let connectionID = session?.connectionConfig.id else { return }
        hasRestoredDrafts = true
        draftConnectionID = connectionID
        let restored = SQLDraftStore.shared.claimDrafts(
            connectionID: connectionID,
            workspace: workspaceInstanceID
        )
        guard !restored.isEmpty else { return }
        var restoredTabs: [WorkspaceSelection] = []
        for record in restored {
            switch record.selection {
            case .query(let id):
                guard queryDocuments[id] == nil else { continue }
                queryDocuments[id] = QueryDocumentTab(
                    id: id,
                    text: record.sql,
                    isSaved: !record.isUnsavedEdit,
                    selectedRange: record.clampedSelection
                )
                restoredTabs.append(record.selection)
            case .table:
                guard tableSQLDrafts[record.selection] == nil else { continue }
                // `isSaved` is what keeps the grid able to rewrite its own query: a restored
                // *baseline* may be replaced by the next page, and a restored *edit* may not.
                tableSQLDrafts[record.selection] = QueryDocumentTab(
                    text: record.sql,
                    isSaved: !record.isUnsavedEdit,
                    selectedRange: record.clampedSelection
                )
            case .connection, .database:
                continue
            }
        }
        guard !restoredTabs.isEmpty else { return }
        var updatedState = tabState
        updatedState.restore(restoredTabs)
        tabState = updatedState
    }

    /// Writes one editor's text through to the draft store, which debounces it. Called from the
    /// document bindings, so every edit path — typing, Format, history insertion, Clear — is
    /// covered by the one choke point rather than by each command remembering to save.
    private func recordDraft(_ document: QueryDocumentTab, for destination: WorkspaceSelection) {
        guard let draftConnectionID else { return }
        SQLDraftStore.shared.record(
            sql: document.text,
            selection: destination,
            selectedRange: document.selectedRange,
            connectionID: draftConnectionID,
            // The document already knows: text that differs from what was marked saved was
            // typed, and everything else is the generated browsing query.
            isUnsavedEdit: document.hasUnsavedChanges
        )
    }

    // MARK: - Connection Recovery

    @ViewBuilder
    private var connectionRecoveryOverlay: some View {
        if let session, !session.state.isConnected {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.22))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                connectionRecoveryCard(for: session)
                    .padding(24)
            }
            .transition(.opacity)
            .zIndex(100)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Database connection unavailable")
        } else if session == nil {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.22))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Image(systemName: "cable.connector.slash")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Connection Closed")
                        .font(.title2.bold())
                    Text("This workspace's database session has ended.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Show Connections") {
                        showConnections()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(28)
                .frame(maxWidth: 440)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
                .padding(24)
            }
            .transition(.opacity)
            .zIndex(100)
        }
    }

    private func connectionRecoveryCard(for session: DatabaseSession) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: recoveryIcon(for: session.state))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(recoveryTint(for: session.state))
                    .symbolEffect(.pulse, isActive: session.state.isConnecting)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 5) {
                    Text(recoveryTitle(for: session.state))
                        .font(.title2.bold())
                    Text(recoveryMessage(for: session.state))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let detail = session.lastConnectionError,
               !detail.isEmpty {
                Divider()
                Text(detail)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if session.state.isConnecting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Restoring the saved connection…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task {
                            try? await sessionManager.reconnect(sessionID: sessionID)
                        }
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .help("Reconnect with the credentials already saved for this connection")

                    Button("Show Connections") {
                        showConnections()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(26)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(recoveryTint(for: session.state).opacity(0.38), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 32, y: 14)
    }

    /// Back to **the machine this database is on**, not to the top of the list.
    ///
    /// The list is not where the user came from: they came from that host, and its other
    /// services are usually the reason they are going back (reported 2026-09-19). Asking the
    /// library to select the host is enough — it shows the detail for a selection change by
    /// itself, on a phone by pushing and on a Mac because the column is already there.
    private func showConnections() {
        if let showHost = runtime?.showHostForConnection, let id = session?.connectionConfig.id {
            showHost(id)
        }
        #if os(iOS)
        let route = DatabaseWorkspaceConnectionsRoute.resolve(
            isPhone: UIDevice.current.userInterfaceIdiom == .phone
        )
        if route == .inAppRouter {
            iOSRouter.showConnections()
            return
        }
        #endif
        openWindow(id: "main")
    }

    private func recoveryTitle(for state: SessionState) -> String {
        switch state {
        case .disconnected: "Disconnected"
        case .connecting: "Reconnecting…"
        case .error: "Couldn't Reconnect"
        case .connected: "Connected"
        }
    }

    private func recoveryMessage(for state: SessionState) -> String {
        switch state {
        case .disconnected:
            "The database connection timed out or was closed. Reconnect to continue without losing this workspace."
        case .connecting(let stage):
            stage.rawValue
        case .error:
            "The saved connection could not be restored. Review the detail below, then try again."
        case .connected:
            "The database connection is ready."
        }
    }

    private func recoveryIcon(for state: SessionState) -> String {
        switch state {
        case .disconnected: "cable.connector.slash"
        case .connecting: "arrow.trianglehead.2.clockwise.rotate.90"
        case .error: "exclamationmark.triangle.fill"
        case .connected: "checkmark.circle.fill"
        }
    }

    private func recoveryTint(for state: SessionState) -> Color {
        switch state {
        case .disconnected: .orange
        case .connecting: .accentColor
        case .error: .red
        case .connected: .green
        }
    }

    private func monitorConnectionState() async {
        var wasConnected = false
        var isInitialCheck = true
        while !Task.isCancelled {
            if scenePhase == .active {
                let validation = await sessionManager.validateSessionAfterForeground(
                    sessionID: sessionID
                )
                let isConnected = validation == .connected
                if isConnected && !wasConnected {
                    await loadDatabases()
                    if !isInitialCheck {
                        NotificationCenter.default.post(
                            name: .glassdbRefreshData,
                            object: sessionID
                        )
                    }
                }
                wasConnected = isConnected
                isInitialCheck = false
            } else {
                sessionManager.noteSessionSuspended(sessionID: sessionID)
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    // MARK: - Detail Surface

    /// **A phone is not a narrow Mac.** `NavigationSplitView` collapses on a compact width into a
    /// single stack showing its *sidebar*, so on an iPhone this workspace was the schema browser
    /// and nothing else: Browse Data, the SQL editor and every table selected a destination in a
    /// column that was never on screen. Reported 2026-09-19 — *"Browse data in the Database on
    /// iOS absorbs the click, too"* — and it is the same defect the editor had on 2026-09-17,
    /// still here because nobody had driven the database on a phone (rule 46).
    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact { compactLayout } else { splitLayout }
        #else
        splitLayout
        #endif
    }

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            schemaBrowser
                .databaseSidebarColumnWidth()
                .databaseWorkspaceSidebarMaterial()
                .glassLibraryColumnAutosave("com.glasspowertools.database.columns")
        } detail: {
            detailSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { workspaceToolbar }
    }

    #if os(iOS)
    /// One thing at a time: the schema, and what you chose from it. The same shape the editor
    /// uses on a phone — a stack, pushes, and the back button.
    private var compactLayout: some View {
        NavigationStack(path: $compactPath) {
            schemaBrowser
                .toolbar { workspaceToolbar }
                .navigationDestination(for: DatabaseCompactRoute.self) { _ in
                    detailSurface
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle(detailTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { workspaceToolbar }
                }
        }
        // Going back is the only way the detail leaves the stack, and the back button is the
        // system's — so the depth is what says it has gone.
        .onChange(of: compactPath.count) { _, count in
            if let depth = detailDepth, count < depth { detailDepth = nil }
        }
    }

    /// Shows whatever the workspace has selected, on a phone. Called by every route that chooses
    /// something — a tap, a double tap, the SQL Editor button — so no surface has to remember.
    private func showDetailOnCompact() {
        guard horizontalSizeClass == .compact, detailDepth == nil else { return }
        compactPath.append(DatabaseCompactRoute.detail)
        detailDepth = compactPath.count
    }
    #endif

    /// Every control this workspace contributes, in one place so both layouts can attach it.
    ///
    /// **Attached inside the navigation container, never outside it.** A `.toolbar` on a view that
    /// *contains* a `NavigationStack` does not reach the screens inside it — which on a phone
    /// would have taken the back control away entirely, and the back control is the report that
    /// started this (2026-09-19: *"there's also no back button to get from Databases back to the
    /// previous connection list"*).
    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        // **The way back.** `showConnections()` already existed and was reachable only from
        // failure states — a closed session, a reconnect card. On a phone the workspace
        // *replaces* the library rather than being pushed onto it, so a user who opened a
        // database had no way back to their machines at all (reported 2026-09-16: "there's no
        // way to go back from the databases list"). Leading, where a back control belongs.
        // On a phone this is the first screen's control only: a pushed detail has the
        // stack's own back button, and two back controls pointing at different places is a
        // puzzle rather than a convenience.
        if !isPushed {
            // `.topBarLeading` on iOS, not `.navigation`: in a collapsed split view the item
            // simply did not appear, which is what "no back button" was (photographed 2026-09-19).
            ToolbarItem(placement: backPlacement) {
                Button {
                    showConnections()
                } label: {
                    Label("Connections", systemImage: "chevron.backward")
                }
                .help("Back to Connections")
                .accessibilityIdentifier("database-workspace-connections")
            }
        }
        #if !os(macOS)
        // **No sidebar toggle where there is no sidebar.** On a compact width the schema is
        // the screen and the detail is a push; a control that reveals a column neither of
        // them has is a control for nothing.
        if !isCompact {
            ToolbarItem(placement: databaseSidebarToolbarPlacement) {
                Button {
                    withAnimation {
                        columnVisibility = columnVisibility == .detailOnly
                            ? .automatic : .detailOnly
                    }
                } label: {
                    Label("Toggle Sidebar",
                          systemImage: columnVisibility == .detailOnly
                              ? "sidebar.left" : "sidebar.leading")
                }
            }
        }
        #endif
        #if os(macOS)
        ToolbarItem {
            Text(detailTitle)
                .font(.headline)
                .lineLimit(1)
                .help("Current workspace: \(detailTitle)")
                .accessibilityLabel("Current workspace: \(detailTitle)")
        }
        .sharedBackgroundVisibility(.hidden)
        #endif
        #if !os(macOS)
        // **Not a bottom bar on a phone.** The schema browser's filter field is a floating
        // bottom search on iOS 26 and later, and a `.bottomBar` group lands in the same place:
        // the search field, the buttons and the list rows behind them were three things in one
        // strip (photographed 2026-09-19). On a compact width the SQL editor goes to the top bar
        // beside Refresh, and the rest into the overflow menu that is already there.
        ToolbarItemGroup(placement: isCompact ? .topBarTrailing : databaseToolbarPlacement) {
            Button {
                openQueryDocument()
                // The editor lives in the detail, and on a phone the detail is a push. This
                // button was as absorbed as Browse Data was.
                #if os(iOS)
                showDetailOnCompact()
                #endif
            } label: {
                Label("SQL Editor", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .help("Show the SQL editor")
            .accessibilityLabel("SQL Editor")
            .accessibilityHint("Opens the connected SQL query editor")

        }
        ToolbarItemGroup(placement: isCompact ? .secondaryAction : databaseToolbarPlacement) {
            if tabState.displayed.usesOverviewRefreshAction {
                Button {
                    overviewRefreshTrigger &+= 1
                } label: {
                    Label("Refresh Overview", systemImage: "arrow.clockwise")
                }
                .help("Reload the active overview")
                .accessibilityLabel("Refresh Overview")
                .accessibilityHint("Reloads the active connection or database overview")
            }

            Button {
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .phone {
                    iOSRouter.showSettings()
                } else {
                    openWindow(id: "settings")
                }
                #else
                openWindow(id: "settings")
                #endif
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Settings")
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens settings")
        }
        #endif
    }

    /// Where the back control goes. `.navigation` is right on a Mac; on iOS it is dropped in a
    /// collapsed split view, and the leading edge of the bar is where a phone expects it.
    private var backPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    /// True only on a phone-width layout; false everywhere else, so the toolbar reads the same on
    /// a Mac and in the headset.
    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    /// True when the compact stack is showing a pushed detail.
    private var isPushed: Bool {
        #if os(iOS)
        detailDepth != nil
        #else
        false
        #endif
    }

    private var schemaBrowser: some View {
        SchemaBrowserView(
            sessionID: sessionID,
            selection: tabState.displayed,
            onSelectionChanged: { newSelection in
                previewWorkspace(newSelection)
                // On a phone a single tap is the only gesture there is, so it opens what it
                // chose — the tab is still a preview, and the next tap replaces it.
                #if os(iOS)
                showDetailOnCompact()
                #endif
            },
            onOpenSelection: { newSelection in
                if case .query(let id) = newSelection {
                    openQueryDocument(QueryDocumentTab(id: id))
                } else {
                    openWorkspace(newSelection)
                }
                #if os(iOS)
                showDetailOnCompact()
                #endif
            }
        )
    }

    private var detailSurface: some View {
        VStack(spacing: 0) {
            if tabState.tabs.count > 1 {
                workspaceTabBar
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
            }

            if breadcrumbTrail.count > 1 {
                breadcrumbBar
                    .overlay(alignment: .bottom) { Divider() }
            }

            ZStack {
                ForEach(tabState.tabs, id: \.self) { destination in
                    let isActive = tabState.previewed == nil && destination == tabState.selected
                    workspaceContent(for: destination, isActive: isActive)
                        .id(destination)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .accessibilityHidden(!isActive)
                        .zIndex(isActive ? 1 : 0)
                }

                if let preview = tabState.previewed {
                    workspacePreviewContent(for: preview)
                        .id(preview)
                        .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Keep Apple-provided titlebar and sidebar materials intact. The SQL
        // tab strip belongs to the live database canvas and follows the same
        // user-controlled opacity and blur as its editor and results grid.
        .modifier(DatabaseWorkspaceBackground(
            material: .ultraThinMaterial,
            fillOpacity: settingsManager.windowOpacity,
            blurAmount: settingsManager.blurBackground
        ))
    }

    /// Ancestors of whatever is on screen, ending with the current surface.
    /// With the sidebar collapsed the tab strip is the only structure left,
    /// and it says nothing about which database a table belongs to — or how
    /// to get back up to it.
    private var breadcrumbTrail: [WorkspaceBreadcrumb] {
        WorkspaceBreadcrumb.trail(
            to: tabState.displayed,
            connectionName: session?.connectionConfig.name ?? "Overview"
        )
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(breadcrumbTrail.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if let destination = crumb.destination {
                    Button(crumb.title) { openWorkspace(destination) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHint("Open \(crumb.title)")
                } else {
                    Text(crumb.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace location")
    }

    /// The strip itself now lives in `GlassConnectionUI` (`GlassWorkspaceTabBar`), because the
    /// editor needed the same one and two copies of a tab bar agree only until the next change to
    /// either. What stays here is what was always local: which destinations are open, what they
    /// are called, and what selecting or closing one does.
    private var workspaceTabBar: some View {
        GlassWorkspaceTabBar(
            tabs: tabState.tabs.map { destination in
                GlassWorkspaceTabItem(id: destination,
                                      title: workspaceTitle(for: destination),
                                      symbolName: destination.systemImage,
                                      isClosable: destination.isClosable,
                                      help: workspaceHelpText(for: destination))
            },
            selection: tabState.previewed == nil ? tabState.selected : nil,
            accessibilityLabel: "Open database workspaces",
            onSelect: { openWorkspace($0) },
            onClose: { requestCloseWorkspace($0) })
    }

    @ViewBuilder
    private func workspacePreviewContent(for destination: WorkspaceSelection) -> some View {
        switch destination {
        case .database(let database):
            DatabaseDetailView(
                sessionID: sessionID,
                database: database,
                isWorkspaceActive: true,
                refreshTrigger: overviewRefreshTrigger,
                activatesDatabaseOnLoad: false,
                previewsTables: true,
                onOpenTable: { table in
                    previewWorkspace(.table(database: database, table: table))
                }
            ) {
                openQueryDocument()
            }
        case .table(let database, let table):
            TableStatisticsPreviewView(
                sessionID: sessionID,
                database: database,
                table: table,
                refreshTrigger: overviewRefreshTrigger,
                onOpenTable: {
                    openWorkspace(destination)
                },
                onOpenSQLEditor: {
                    openQueryDocument()
                }
            )
        case .connection, .query:
            EmptyView()
        }
    }

    @ViewBuilder
    private func workspaceContent(
        for destination: WorkspaceSelection,
        isActive: Bool
    ) -> some View {
        switch destination {
        case .connection:
            ConnectionOverviewView(
                sessionID: sessionID,
                isWorkspaceActive: isActive,
                refreshTrigger: overviewRefreshTrigger,
                onOpenDatabase: { database in
                    previewWorkspace(.database(database))
                },
                onOpenSQLEditor: {
                    openQueryDocument()
                }
            )
        case .table(let database, let table):
            TableDetailView(
                sessionID: sessionID,
                database: database,
                table: table,
                isWorkspaceActive: isActive,
                onOpenSQLEditor: { openQueryDocument() },
                sqlDraft: tableSQLDraftBinding(for: destination)
            )
        case .database(let database):
            DatabaseDetailView(
                sessionID: sessionID,
                database: database,
                isWorkspaceActive: isActive,
                refreshTrigger: overviewRefreshTrigger,
                onOpenTable: { table in
                    openWorkspace(.table(database: database, table: table))
                }
            ) {
                openQueryDocument()
            }
        case .query(let id):
            QueryEditorView(
                sessionID: sessionID,
                document: queryDocumentBinding(for: id),
                isWorkspaceActive: isActive,
                onOpenSQLEditor: { openQueryDocument() },
                onRequestClose: { requestCloseWorkspace(.query(id: id)) },
                onCreateDocument: { openQueryDocument($0) },
                onRegisterCommandHandlers: { handlers in
                    if let handlers {
                        editorCommandHandlers[id] = handlers
                    } else {
                        editorCommandHandlers.removeValue(forKey: id)
                    }
                }
            )
        }
    }

    /// **The thing you are looking at**, with where it lives underneath — the shape the terminal
    /// established (*"Terminal on oscar"* over `michael@192.0.2.10:22`) and the editor now
    /// follows too. A table's name was previously glued to its database with a middle dot, which
    /// put two different facts on one line and truncated the useful one first.
    private var detailTitle: String {
        switch tabState.displayed {
        case .connection:
            return session?.connectionConfig.name ?? "Overview"
        case .table(_, let table):
            return table
        case .database(let database):
            return database
        case .query(let id):
            return queryDocuments[id]?.title ?? "Untitled SQL"
        }
    }

    /// The connection, and the database when the surface belongs to one.
    private var detailSubtitle: String {
        let connection = session?.connectionConfig.name ?? ""
        switch tabState.displayed {
        case .connection:
            guard let config = session?.connectionConfig else { return "" }
            let host = config.host.isEmpty ? "" : config.host
            return config.port > 0 && !host.isEmpty ? "\(config.username)@\(host):\(config.port)" : host
        case .table(let database, _):
            return connection.isEmpty ? database : "\(connection) · \(database)"
        case .database:
            return connection
        case .query:
            return connection
        }
    }

    /// The SQL document whose editor is visible and interactive — mirroring
    /// each editor's `isWorkspaceActive` flag.
    private var activeQueryDocumentID: UUID? {
        tabState.activeQueryDocumentID
    }

    private var activeEditorHandlers: QueryEditorCommandHandlers? {
        activeQueryDocumentID.flatMap { editorCommandHandlers[$0] }
    }

    /// Single focused-scene command value for the whole workspace window.
    /// Enablement is computed from workspace-owned document state; the verbs
    /// resolve the active editor's handlers at call time so menu items stay
    /// correct however many editors are alive (including zero).
    private var workspaceCommandActions: DatabaseWorkspaceCommandActions {
        let document = activeQueryDocumentID.flatMap { queryDocuments[$0] }
        let hasQuery = document.map {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        let availability = activeQueryDocumentID == nil ? tableRunAvailability : SQLRunAvailability(
            canRun: session?.state.isConnected == true && hasQuery && document?.isExecuting != true,
            hasSelection: (document?.selectedRange.length ?? 0) > 0
        )
        return DatabaseWorkspaceCommandActions(
            canExecute: availability.canRun,
            canCancel: document?.isExecuting == true
                && session?.connection?.capabilities.contains(.cancellation) == true,
            canSave: sqlDocument(for: tabState.displayed)?.text.isEmpty == false,
            canUseQueryLibrary: activeQueryDocumentID != nil,
            canCloseTab: tabState.previewed != nil || canCloseWorkspace(tabState.selected),
            newQueryTab: {
                openQueryDocument()
                // ⌘T from a hardware keyboard on an iPad or a phone, and the same push it needs.
                #if os(iOS)
                showDetailOnCompact()
                #endif
            },
            closeTab: { closeFocusedEditor() },
            openDocument: { showingSQLImporter = true },
            saveDocument: { exportActiveQueryDocument() },
            executeStatement: { runActiveSQL(.automatic) },
            executeScript: { runActiveSQL(.all) },
            explainPlan: { activeEditorHandlers?.explainPlan() },
            cancel: { activeEditorHandlers?.cancel() },
            formatSQL: { formatActiveQueryDocument() },
            showHistory: { activeEditorHandlers?.showHistory() },
            showSavedQueries: { activeEditorHandlers?.showSavedQueries() },
            runTitle: availability.title,
            canRunSelection: availability.canRun && availability.hasSelection,
            executeSelection: { runActiveSQL(.selection) },
            executeCurrentStatement: { runActiveSQL(.statement) }
        )
    }

    private func runActiveSQL(_ mode: SQLExecutionMode) {
        if let handlers = activeEditorHandlers {
            switch mode {
            case .automatic: handlers.executeStatement()
            case .statement: handlers.executeCurrentStatement()
            case .selection: handlers.executeSelection()
            case .all: handlers.executeScript()
            }
        } else if case .table = tabState.displayed {
            NotificationCenter.default.post(name: .glassdbExecuteQuery, object: sessionID,
                                            userInfo: ["mode": mode.rawValue])
        }
    }

    /// File > Save routes through the workspace's exporter so it works from
    /// the menu bar without reaching into editor-private sheet state.
    private func exportActiveQueryDocument() {
        let destination = tabState.displayed
        guard sqlDocument(for: destination)?.text.isEmpty == false else { return }
        queryPendingExport = destination
        closeQueryAfterExport = false
        showingQueryExporter = true
    }

    /// Formatting mutates only workspace-owned document state, so the menu
    /// verb needs no editor registration.
    private func formatActiveQueryDocument() {
        guard let id = activeQueryDocumentID,
              var document = queryDocuments[id],
              !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !document.isExecuting else { return }
        let formatted = SQLHighlighter.formatted(document.text)
        document.text = formatted
        document.selectedRange = NSRange(location: (formatted as NSString).length, length: 0)
        queryDocuments[id] = document
    }

    private func importSQLDocument(_ result: Result<[URL], Error>) {
        do {
            guard let document = try QueryEditorView.importedSQLDocument(from: result) else { return }
            openQueryDocument(document)
        } catch {
            queryDocumentError = error.localizedDescription
        }
    }

    private func requestCloseWorkspace(_ destination: WorkspaceSelection) {
        guard canCloseWorkspace(destination) else { return }
        if sqlDocument(for: destination)?.hasUnsavedChanges == true {
            queryPendingClose = destination
            return
        }
        performCloseWorkspace(destination)
    }

    private func performCloseWorkspace(_ destination: WorkspaceSelection) {
        withAnimation(.snappy) {
            var updatedState = tabState
            guard updatedState.close(destination) else { return }
            tabState = updatedState
        }
        if case .query(let id) = destination {
            queryDocuments.removeValue(forKey: id)
        }
        tableSQLDrafts.removeValue(forKey: destination)
        // Closing a *tab* is the deliberate discard. Closing the window is not, and must leave
        // the draft on disk — that is the defect this store exists to fix.
        if let draftConnectionID {
            SQLDraftStore.shared.remove(selection: destination, connectionID: draftConnectionID)
        }
    }

    /// Command-W has exactly one window-level registration. Hidden workspace
    /// content remains alive in the ZStack, so child registrations would be
    /// able to shadow the selected table or database editor with stale state.
    private func closeFocusedEditor() {
        if tabState.previewed != nil {
            var updatedState = tabState
            updatedState.clearPreview()
            withAnimation(.snappy) {
                tabState = updatedState
            }
            return
        }
        switch tabState.selected.commandWEditorTarget {
        case .none:
            break
        case .workspace:
            requestCloseWorkspace(tabState.selected)
        }
    }

    /// Assign a new state value instead of mutating a nested `@State` value in
    /// an escaping sidebar/menu callback. This gives every SwiftUI scene an
    /// explicit invalidation, including regular-width iPad workspaces.
    private func openWorkspace(_ destination: WorkspaceSelection) {
        var updatedState = tabState
        updatedState.open(destination)
        withAnimation(.snappy) {
            tabState = updatedState
        }
    }

    #if os(macOS)
    private var commandCenterDestinations: [MacCommandCenterEntry] {
        var entries = tabState.tabs.map { destination in
            MacCommandCenterEntry(id: "tab.\(destination)", title: workspaceTitle(for: destination),
                                  detail: "Switch workspace tab") { openWorkspace(destination) }
        }
        entries += databases.map { database in
            MacCommandCenterEntry(id: "database.\(database)", title: database,
                                  detail: "Open database") { openWorkspace(.database(database)) }
        }
        for database in databases {
            for status in session?.databaseStatistics[database]?.statuses ?? [] {
                entries.append(MacCommandCenterEntry(id: "table.\(database).\(status.name)",
                    title: status.name, detail: "Open table · \(database)") {
                    openWorkspace(.table(database: database, table: status.name))
                })
            }
        }
        return entries
    }
    #endif

    private func previewWorkspace(_ destination: WorkspaceSelection) {
        var updatedState = tabState
        updatedState.preview(destination)
        withAnimation(.snappy) {
            tabState = updatedState
        }
    }

    private func openQueryDocument(_ document: QueryDocumentTab = QueryDocumentTab()) {
        queryDocuments[document.id] = document
        openWorkspace(.query(id: document.id))
    }

    private func queryDocumentBinding(for id: UUID) -> Binding<QueryDocumentTab> {
        Binding(
            get: { queryDocuments[id] ?? QueryDocumentTab(id: id) },
            set: { updated in
                queryDocuments[id] = updated
                recordDraft(updated, for: .query(id: id))
            }
        )
    }

    private func sqlDocument(for destination: WorkspaceSelection) -> QueryDocumentTab? {
        if case .query(let id) = destination { return queryDocuments[id] }
        return tableSQLDrafts[destination]
    }

    private func tableSQLDraftBinding(for destination: WorkspaceSelection) -> Binding<QueryDocumentTab> {
        Binding(
            get: { tableSQLDrafts[destination] ?? QueryDocumentTab() },
            set: { updated in
                tableSQLDrafts[destination] = updated
                recordDraft(updated, for: destination)
            }
        )
    }

    private func canCloseWorkspace(_ destination: WorkspaceSelection) -> Bool {
        guard destination.isClosable else { return false }
        guard case .query(let id) = destination else { return true }
        return queryDocuments[id]?.isExecuting != true
    }

    private func closeQueryDocument(_ id: UUID) {
        performCloseWorkspace(.query(id: id))
    }

    private func workspaceTitle(for destination: WorkspaceSelection) -> String {
        guard case .query(let id) = destination else { return destination.title }
        return queryDocuments[id]?.title ?? "Untitled SQL"
    }

    private func workspaceHelpText(for destination: WorkspaceSelection) -> String {
        guard case .query = destination else { return destination.helpText }
        return "SQL editor \(workspaceTitle(for: destination))"
    }

    private var queryExportFilename: String {
        guard let id = queryPendingExport,
              let document = sqlDocument(for: id) else { return "query.sql" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = document.title.unicodeScalars.map {
            allowed.contains($0) ? Character(String($0)) : "-"
        }
        let basename = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return (basename.isEmpty ? "query" : basename) + ".sql"
    }

    private func completeQueryExport(_ result: Result<URL, Error>) {
        defer {
            queryPendingExport = nil
            closeQueryAfterExport = false
        }
        switch result {
        case .success:
            guard let id = queryPendingExport,
                  sqlDocument(for: id) != nil else { return }
            if case .query(let documentID) = id {
                queryDocuments[documentID]?.markSaved()
            } else {
                tableSQLDrafts[id]?.markSaved()
            }
            if closeQueryAfterExport {
                performCloseWorkspace(id)
            }
        case .failure(let error):
            let cocoaError = error as? CocoaError
            if cocoaError?.code != .userCancelled {
                queryDocumentError = error.localizedDescription
            }
        }
    }

    private func loadDatabases() async {
        guard let connection = session?.connection else { return }
        do {
            databases = try await connection.databases()
        } catch {
            await sessionManager.handleConnectionFailure(error, sessionID: sessionID)
        }
    }
}

// MARK: - Workspace Background

/// Composites passthrough blur behind the database canvas independently from
/// its opaque fill. A zero blur amount emits no material backing.
private struct DatabaseWorkspaceBackground: ViewModifier {
    let material: Material
    let fillOpacity: Double
    let blurAmount: Double

    func body(content: Content) -> some View {
        let appearance = DatabaseGlassAppearance(opacity: fillOpacity, blur: blurAmount)
        content.background(alignment: .center) {
            ZStack {
                if appearance.compositesBlur {
                    #if os(macOS)
                    MacDatabaseCanvasVisualEffect(amount: appearance.blur)
                    #else
                    Rectangle()
                        .fill(material)
                        .opacity(appearance.blur)
                    #endif
                }

                Rectangle()
                    .fill(DatabaseCanvasPalette.background)
                    .opacity(appearance.opacity)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            #if !os(macOS)
            .ignoresSafeArea()
            #endif
        }
    }
}


/// One step of the workspace's location trail. Ancestors carry the
/// destination that reopens them; the final crumb is where you already are.
struct WorkspaceBreadcrumb: Equatable {
    let title: String
    let destination: WorkspaceSelection?

    static func trail(
        to displayed: WorkspaceSelection,
        connectionName: String
    ) -> [WorkspaceBreadcrumb] {
        switch displayed {
        case .connection, .query:
            // The overview is the root, and an SQL document belongs to the
            // connection rather than to any database.
            return []
        case .database(let database):
            return [
                WorkspaceBreadcrumb(title: connectionName, destination: .connection),
                WorkspaceBreadcrumb(title: database, destination: nil)
            ]
        case .table(let database, let table):
            return [
                WorkspaceBreadcrumb(title: connectionName, destination: .connection),
                WorkspaceBreadcrumb(title: database, destination: .database(database)),
                WorkspaceBreadcrumb(title: table, destination: nil)
            ]
        }
    }
}

#if os(iOS)
/// Where a phone can be in a database workspace: at the schema, or at what it opened.
///
/// One case, not one per destination: which table or query is showing is `tabState`'s to say, and
/// two places holding that would eventually disagree.
enum DatabaseCompactRoute: Hashable {
    case detail
}
#endif
