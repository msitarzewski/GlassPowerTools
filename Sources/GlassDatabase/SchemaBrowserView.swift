//
//  SchemaBrowserView.swift
//  glassdb
//
//  Tree navigation: databases -> tables
//  Selection drives the workspace detail surface
//

import SwiftUI
import GlassDBKit
import os

private struct SchemaMutationTarget: Identifiable {
    let database: String
    let table: String
    var id: String { "\(database.utf8.count):\(database)\(table)" }
}

private struct SchemaTableKey: Hashable {
    let database: String
    let table: String
}

private struct ExactRowCountSnapshot {
    let value: Int
    let capturedAt: Date
}

private enum SchemaMutationOperation: String {
    case truncate
    case drop
}

private struct SchemaMutationFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

#if os(iOS)
private struct CompactSchemaDatabaseDestination: Hashable {
    let name: String
}
#endif

struct SchemaBrowserView: View {
    let sessionID: UUID
    let selection: WorkspaceSelection
    var onSelectionChanged: ((WorkspaceSelection) -> Void)?
    var onOpenSelection: ((WorkspaceSelection) -> Void)?

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @Environment(\.openWindow) private var openWindow
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var databases: [String] = []
    @State private var expandedDatabases: Set<String> = []
    @State private var tablesCache: [String: [String]] = [:]
    @State private var exactRowCounts: [SchemaTableKey: ExactRowCountSnapshot] = [:]
    @State private var loadErrors: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filterText = ""
    @State private var confirmingTruncate: SchemaMutationTarget?
    @State private var confirmingDrop: SchemaMutationTarget?
    @State private var confirmingExactCount: SchemaMutationTarget?
    @State private var exactCountTarget: SchemaMutationTarget?
    @State private var exactCountTask: Task<Void, Never>?
    @State private var destructiveOperation: String?
    @State private var operationError: String?
    @State private var showingMutationAudit = false

    private var session: DatabaseSession? {
        sessionManager.session(for: sessionID)
    }

    private var schemaSelection: Binding<WorkspaceSelection?> {
        Binding(
            get: { selection },
            set: { newSelection in
                guard let newSelection else { return }
                onSelectionChanged?(newSelection)
            }
        )
    }

    var body: some View {
        Group {
            if session != nil {
                VStack(spacing: 0) {
                    if isLoading && databases.isEmpty {
                        ProgressView("Loading schema...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = errorMessage {
                        ContentUnavailableView(
                            "Error",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                    } else {
                        platformSchemaTree
                    }
                }
            } else {
                ContentUnavailableView(
                    "Session Disconnected",
                    systemImage: "cable.connector.slash",
                    description: Text("This database session is no longer active.")
                )
            }
        }
        .navigationTitle(session?.connection?.dialect == .postgresql ? "Schemas" : "Databases")
        .schemaSearchable(text: $filterText)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshExpandedSchema() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload databases and tables")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingMutationAudit = true
                } label: {
                    Label("Mutation Log", systemImage: "list.bullet.rectangle.portrait")
                }
                .help("Review every row and schema change this app has made")
            }
        }
        .sheet(isPresented: $showingMutationAudit) {
            MutationAuditView(connectionID: session?.connectionConfig.id,
                              connectionName: session?.connectionConfig.name)
        }
        .task {
            await loadDatabases()
        }
        .onChange(of: session?.state) {
            guard session?.state.isConnected == true else { return }
            tablesCache.removeAll()
            exactRowCounts.removeAll()
            loadErrors.removeAll()
            Task { await loadDatabases() }
        }
        .overlay {
            if let destructiveOperation {
                ProgressView(destructiveOperation)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if let exactCountTarget {
                VStack(spacing: 12) {
                    ProgressView("Counting \(exactCountTarget.table)…")
                    Button("Cancel", role: .cancel) { cancelExactRowCount() }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("Calculate Exact Row Count?", isPresented: .init(
            get: { confirmingExactCount != nil },
            set: { if !$0 { confirmingExactCount = nil } }
        )) {
            Button("Calculate") {
                if let target = confirmingExactCount {
                    exactCountTask = Task { await calculateExactRowCount(target) }
                }
                confirmingExactCount = nil
            }
            Button("Cancel", role: .cancel) { confirmingExactCount = nil }
        } message: {
            Text("This runs SELECT COUNT(*) against the entire table. On a large production table it may scan an index or the table itself. Prefer a read replica when available; the query is stopped after 30 seconds.")
        }
        .alert("Truncate Table?", isPresented: .init(
            get: { confirmingTruncate != nil },
            set: { if !$0 { confirmingTruncate = nil } }
        )) {
            Button("Truncate", role: .destructive) {
                if let target = confirmingTruncate {
                    Task { await executeSchemaMutation(.truncate, target: target) }
                }
                confirmingTruncate = nil
            }
            Button("Cancel", role: .cancel) { confirmingTruncate = nil }
        } message: {
            Text(schemaMutationPreview(operation: "TRUNCATE", target: confirmingTruncate))
        }
        .alert("Drop Table?", isPresented: .init(
            get: { confirmingDrop != nil },
            set: { if !$0 { confirmingDrop = nil } }
        )) {
            Button("Drop", role: .destructive) {
                if let target = confirmingDrop {
                    Task { await executeSchemaMutation(.drop, target: target) }
                }
                confirmingDrop = nil
            }
            Button("Cancel", role: .cancel) { confirmingDrop = nil }
        } message: {
            Text(schemaMutationPreview(operation: "DROP TABLE", target: confirmingDrop))
        }
        .alert("Database Operation Failed", isPresented: .init(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    // MARK: - Filtered Data

    private var filteredDatabases: [String] {
        guard !filterText.isEmpty else { return databases }
        return databases.filter { db in
            if db.localizedCaseInsensitiveContains(filterText) { return true }
            if let tables = tablesCache[db] {
                return tables.contains { $0.localizedCaseInsensitiveContains(filterText) }
            }
            return false
        }
    }

    private func filteredTables(for database: String) -> [String]? {
        guard let tables = tablesCache[database] else { return nil }
        guard !filterText.isEmpty else { return tables }
        return tables.filter { $0.localizedCaseInsensitiveContains(filterText) }
    }

    // MARK: - Schema Tree

    @ViewBuilder
    private var platformSchemaTree: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            compactDatabaseList
        } else {
            schemaTree
        }
        #else
        schemaTree
        #endif
    }

    #if os(iOS)
    private var compactDatabaseList: some View {
        List(filteredDatabases, id: \.self) { database in
            NavigationLink(value: CompactSchemaDatabaseDestination(name: database)) {
                Label(database, systemImage: "cylinder")
            }
            .accessibilityIdentifier("db-schema-database-\(database)")
            .contextMenu {
                Button("Open Database Overview", systemImage: "info.circle") {
                    onSelectionChanged?(.database(database))
                }
                Button("Open Database in Tab", systemImage: "rectangle.on.rectangle") {
                    onOpenSelection?(.database(database))
                }
                Button("Open SQL Editor", systemImage: "text.page") {
                    onOpenSelection?(.query(id: UUID()))
                }
                Button("Refresh Tables", systemImage: "arrow.clockwise") {
                    Task { await refreshDatabase(database) }
                }
            }
        }
        .navigationDestination(for: CompactSchemaDatabaseDestination.self) { destination in
            compactTableList(for: destination.name)
        }
    }

    private func compactTableList(for database: String) -> some View {
        Group {
            if let error = loadErrors[database] {
                ContentUnavailableView(
                    "Tables Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let tables = filteredTables(for: database) {
                List(tables, id: \.self) { table in
                    compactTableRow(table, database: database)
                }
            } else {
                ProgressView("Loading tables…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(database)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTables(for: database) }
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button("Database Overview", systemImage: "info.circle") {
                    onSelectionChanged?(.database(database))
                }
                Button("Refresh Tables", systemImage: "arrow.clockwise") {
                    Task { await refreshDatabase(database) }
                }
            }
        }
    }

    private func compactTableRow(_ table: String, database: String) -> some View {
        return HStack(spacing: 8) {
            Button {
                onSelectionChanged?(.table(database: database, table: table))
            } label: {
                HStack {
                    Label(table, systemImage: "tablecells")
                    Spacer()
                    rowCountLabel(table: table, database: database, font: .caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu("Table Actions", systemImage: "ellipsis.circle") {
                tableActionMenu(table, database: database)
            }
            .labelStyle(.iconOnly)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onOpenSelection?(.table(database: database, table: table))
        })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("db-schema-table-\(table)")
        .accessibilityAction(named: "Open Table") {
            onOpenSelection?(.table(database: database, table: table))
        }
    }
    #endif

    private var schemaTree: some View {
        List(selection: schemaSelection) {
            ForEach(filteredDatabases, id: \.self) { database in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedDatabases.contains(database) },
                        set: { expanded in
                            if expanded {
                                expandedDatabases.insert(database)
                                Task { await loadTables(for: database) }
                            } else {
                                expandedDatabases.remove(database)
                            }
                        }
                    )
                ) {
                    if let tables = filteredTables(for: database) {
                        ForEach(tables, id: \.self) { table in
                            tableRow(table, database: database)
                        }
                    } else if let error = loadErrors[database] {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } label: {
                    HStack {
                        Label(database, systemImage: "cylinder")
                            .font(.headline)
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectionChanged?(.database(database))
                    }
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        onOpenSelection?(.database(database))
                    })
                    .accessibilityAction(named: "Open Database in Tab") {
                        onOpenSelection?(.database(database))
                    }
                    .help("Single-click for statistics; double-click to open a database tab")
                    .accessibilityIdentifier("db-schema-database-\(database)")
                    .contextMenu {
                        databaseActionMenu(database)
                    }
                }
                .tag(WorkspaceSelection.database(database))
            }
        }
        .databaseLookScrollEnabled()
    }

    private func tableRow(_ table: String, database: String) -> some View {
        return HStack {
            Label(table, systemImage: "tablecells")
            Spacer()
            rowCountLabel(table: table, database: database, font: .caption2)
        }
        .contentShape(Rectangle())
        .tag(WorkspaceSelection.table(database: database, table: table))
        .onTapGesture {
            onSelectionChanged?(.table(database: database, table: table))
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onOpenSelection?(.table(database: database, table: table))
        })
        .accessibilityAction(named: "Open Table") {
            onOpenSelection?(.table(database: database, table: table))
        }
        .help("Single-click for statistics; double-click to open the Data workspace")
        .accessibilityIdentifier("db-schema-table-\(table)")
        .contextMenu {
            tableActionMenu(table, database: database)
        }
    }

    @ViewBuilder
    private func rowCountLabel(table: String, database: String, font: Font) -> some View {
        let key = SchemaTableKey(database: database, table: table)
        if let exact = exactRowCounts[key] {
            Text(exact.value.formatted())
                .font(font)
                .foregroundStyle(.secondary)
                .help("Exact count calculated \(exact.capturedAt.formatted(date: .abbreviated, time: .shortened))")
        } else if let snapshot = session?.databaseStatistics[database],
                  let status = snapshot.status(for: table) {
            Text(status.rowCountAccuracy == .estimated
                ? "~\(status.rowCount.formatted())"
                : status.rowCount.formatted())
                .font(font)
                .foregroundStyle(.tertiary)
                .help("\(status.rowCountAccuracy == .estimated ? "Server estimate" : "Exact server statistic") cached \(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    @ViewBuilder
    private func databaseActionMenu(_ database: String) -> some View {
        Button("Open Database in Tab", systemImage: "rectangle.on.rectangle") {
            onOpenSelection?(.database(database))
        }
        if session?.connection?.dialect == .mysql {
            Button("Set as Active Database", systemImage: "checkmark.circle") {
                Task {
                    do {
                        guard let connection = session?.connection else { return }
                        let result = try await sessionManager.executeQuery(
                            "USE \(connection.quotedIdentifier(database))",
                            sessionID: sessionID
                        )
                        if let serverError = result.error {
                            operationError = serverError
                        }
                    } catch {
                        operationError = "Could not select ‘\(database)’: \(error.localizedDescription)"
                    }
                }
            }
        }
        Button("Open SQL Editor", systemImage: "text.page") {
            onOpenSelection?(.query(id: UUID()))
        }
        Button("Open in New Window", systemImage: "macwindow.badge.plus") {
            let request = DatabaseWorkspaceWindowRequest.additional(
                sessionID: sessionID,
                initialSelection: .database(database)
            )
            openWindow(
                id: "database-workspace",
                value: sessionManager.registerWorkspace(request)
            )
        }
        .help("Open \(database) in another window on this connection")
        Divider()
        Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await refreshDatabase(database) }
        }
    }

    @ViewBuilder
    private func tableActionMenu(_ table: String, database: String) -> some View {
        Button("Browse Data", systemImage: "tablecells") {
            onOpenSelection?(.table(database: database, table: table))
        }
        Button("Copy Table Name", systemImage: "doc.on.doc") {
            guard let connection = session?.connection else { return }
            PlatformClipboard.copy(
                "\(connection.quotedIdentifier(database)).\(connection.quotedIdentifier(table))"
            )
        }
        Button("Copy SELECT Statement", systemImage: "text.page") {
            guard let connection = session?.connection else { return }
            let object = "\(connection.quotedIdentifier(database)).\(connection.quotedIdentifier(table))"
            PlatformClipboard.copy("SELECT * FROM \(object) LIMIT 100;")
        }
        Divider()
        Button("Calculate Exact Row Count…", systemImage: "number") {
            confirmingExactCount = SchemaMutationTarget(database: database, table: table)
        }
        Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await refreshDatabase(database) }
        }
        Divider()
        if session?.connection?.capabilities.contains(.truncateTable) == true {
            Button("Truncate Table…", systemImage: "trash", role: .destructive) {
                confirmingTruncate = SchemaMutationTarget(database: database, table: table)
            }
        }
        Button("Drop Table…", systemImage: "xmark.bin", role: .destructive) {
            confirmingDrop = SchemaMutationTarget(database: database, table: table)
        }
    }

    // MARK: - Data Loading

    private func schemaMutationPreview(operation: String, target: SchemaMutationTarget?) -> String {
        guard let target else { return "" }
        let connection = session?.connectionConfig
        let transactionWarning = connection?.engine == .mysql
            ? "MySQL DDL may commit implicitly and cannot be rolled back"
            : "DDL transaction behavior follows the connected engine"
        return "Connection: \(connection?.name ?? "Disconnected")\nEnvironment tag: \(connection?.colorTag.displayName ?? "None")\nDatabase: \(target.database)\nTable: \(target.table)\nOperation: \(operation)\nEstimated scope: the entire table\nTransaction: \(transactionWarning)\n\nThis action is permanent."
    }

    private func executeSchemaMutation(_ operation: SchemaMutationOperation, target: SchemaMutationTarget) async {
        guard let connection = session?.connection, let config = session?.connectionConfig else { return }
        if operation == .truncate, !connection.capabilities.contains(.truncateTable) {
            operationError = "\(connection.engineName) does not support TRUNCATE TABLE."
            return
        }
        destructiveOperation = operation == .truncate ? "Truncating table…" : "Dropping table…"
        defer { destructiveOperation = nil }

        let object = "\(connection.quotedIdentifier(target.database)).\(connection.quotedIdentifier(target.table))"
        let sql = operation == .truncate ? "TRUNCATE TABLE \(object)" : "DROP TABLE \(object)"
        do {
            let result = try await connection.execute(sql, parameters: [])
            if let serverError = result.error { throw SchemaMutationFailure(message: serverError) }
            MutationAuditStore.append(MutationAuditRecord(
                connectionID: config.id,
                database: target.database,
                object: target.table,
                normalizedOperation: operation.rawValue,
                source: "schema-browser",
                outcome: .committed,
                affectedRows: result.affectedRows
            ))
            if operation == .drop {
                tablesCache.removeValue(forKey: target.database)
                exactRowCounts.removeValue(forKey: SchemaTableKey(database: target.database, table: target.table))
                await loadTables(for: target.database)
            } else {
                exactRowCounts[SchemaTableKey(database: target.database, table: target.table)] =
                    ExactRowCountSnapshot(value: 0, capturedAt: Date())
            }
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: target.database)
            await loadStatistics(for: target.database, forceRefresh: true)
        } catch {
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: target.database)
            exactRowCounts.removeValue(forKey: SchemaTableKey(database: target.database, table: target.table))
            MutationAuditStore.append(MutationAuditRecord(
                connectionID: config.id,
                database: target.database,
                object: target.table,
                normalizedOperation: operation.rawValue,
                source: "schema-browser",
                outcome: .serverStateUnknown,
                affectedRows: nil
            ))
            operationError = "\(operation == .truncate ? "Truncate" : "Drop") failed. Verify the table state before retrying. \(error.localizedDescription)"
        }
    }

    private func loadDatabases() async {
        guard let connection = session?.connection else { return }
        isLoading = true
        errorMessage = nil
        do {
            databases = try await connection.databases()
        } catch {
            await sessionManager.handleConnectionFailure(error, sessionID: sessionID)
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadTables(for database: String, forceStatisticsRefresh: Bool = false) async {
        guard let connection = session?.connection else { return }
        if tablesCache[database] == nil {
            loadErrors.removeValue(forKey: database)
            do {
                tablesCache[database] = try await connection.tables(in: database)
            } catch {
                await sessionManager.handleConnectionFailure(error, sessionID: sessionID)
                loadErrors[database] = error.localizedDescription
                Logger.database.error("Failed to load tables for \(database): \(error)")
                return
            }
        }
        await loadStatistics(for: database, forceRefresh: forceStatisticsRefresh)
    }

    private func loadStatistics(for database: String, forceRefresh: Bool = false) async {
        guard let connection = session?.connection else { return }
        guard connection.capabilities.contains(.tableStatistics), connection.dialect != .sqlite else { return }
        do {
            _ = try await sessionManager.tableStatistics(
                sessionID: sessionID,
                database: database,
                forceRefresh: forceRefresh
            )
        } catch {
            await sessionManager.handleConnectionFailure(error, sessionID: sessionID)
            Logger.database.error("Failed to load table statistics for \(database): \(error)")
        }
    }

    private func refreshDatabase(_ database: String) async {
        tablesCache.removeValue(forKey: database)
        exactRowCounts = exactRowCounts.filter { $0.key.database != database }
        sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
        await loadTables(for: database, forceStatisticsRefresh: true)
    }

    private func refreshExpandedSchema() async {
        await loadDatabases()
        for database in expandedDatabases {
            await refreshDatabase(database)
        }
    }

    private func calculateExactRowCount(_ target: SchemaMutationTarget) async {
        guard let connection = session?.connection else { return }
        exactCountTarget = target
        defer {
            exactCountTarget = nil
            exactCountTask = nil
        }
        do {
            let count = try await connection.rowCount(
                table: target.table,
                database: target.database,
                timeout: .seconds(30)
            )
            try Task.checkCancellation()
            exactRowCounts[SchemaTableKey(database: target.database, table: target.table)] =
                ExactRowCountSnapshot(value: count, capturedAt: Date())
        } catch is CancellationError {
            return
        } catch {
            await sessionManager.handleConnectionFailure(error, sessionID: sessionID)
            operationError = "Exact row count failed: \(error.localizedDescription)"
        }
    }

    private func cancelExactRowCount() {
        exactCountTask?.cancel()
        exactCountTask = nil
        Task {
            do {
                try await sessionManager.cancelQuery(sessionID: sessionID)
            } catch {
                operationError = "Could not cancel the exact row count: \(error.localizedDescription)"
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func schemaSearchable(text: Binding<String>) -> some View {
        #if os(iOS)
        searchable(text: text, placement: .automatic, prompt: "Filter databases and tables")
        #else
        searchable(text: text, placement: .sidebar, prompt: "Filter")
        #endif
    }
}
