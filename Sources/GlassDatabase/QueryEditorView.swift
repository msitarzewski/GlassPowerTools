//
//  QueryEditorView.swift
//  glassdb
//
//  SQL query editor with execution and inline results
//

import SwiftUI
import GlassShell
import GlassDBKit
import UniformTypeIdentifiers
import GlassLayers

struct SQLRunAvailability: Equatable {
    var canRun = false
    var hasSelection = false
    var title: String { hasSelection ? "Run Selection" : "Run Statement" }
    func buttonTitle(runAll: Bool) -> String {
        runAll ? "All Statements" : (hasSelection ? "Selection" : "Statement")
    }
}

struct SQLRunAvailabilityKey: PreferenceKey {
    static let defaultValue = SQLRunAvailability()
    static func reduce(value: inout SQLRunAvailability, nextValue: () -> SQLRunAvailability) {
        let next = nextValue()
        if next.canRun { value = next }
    }
}

/// Shared native execution control for table editors and SQL documents.
struct SQLRunControl: View {
    let availability: SQLRunAvailability
    let run: (SQLExecutionMode) -> Void
    @State private var runAll = false

    var body: some View {
        Menu {
            Button("Run Statement") { run(.statement) }
            Button("Run Selection") { run(.selection) }
                .disabled(!availability.hasSelection)
            Button("Run All Statements") { run(.all) }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
        } label: {
            // Native toolbar menus flatten label stacks, ignoring HStack spacing.
            // Keep the gap in the title so the AppKit menu-button bridge retains it.
            Label("\u{2002}\(availability.buttonTitle(runAll: runAll))", systemImage: "play.fill")
        } primaryAction: {
            run(runAll ? .all : .automatic)
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!availability.canRun)
        .labelStyle(.titleAndIcon)
        .help("\(availability.title) (Command-Return); Run All Statements (Shift-Command-Return)")
        .accessibilityLabel(runAll ? "Run All Statements" : availability.title)
        .accessibilityIdentifier("db-query-run")
        #if os(macOS)
        .onModifierKeysChanged(mask: [.command, .shift]) { _, modifiers in
            runAll = modifiers.contains([.command, .shift])
        }
        #endif
        .onDisappear { runAll = false }
    }
}

struct SQLTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= 10 * 1_024 * 1_024,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    var utf8Data: Data { Data(text.utf8) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: utf8Data)
    }
}

struct QueryFailurePresentation: Equatable, Sendable {
    let title: String
    let detail: String

    init(message: String) {
        let normalized = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{0000}", with: "")
        detail = normalized.isEmpty
            ? "The database did not provide an error description."
            : String(normalized.prefix(16_384))

        let lowercase = normalized.lowercased()
        if lowercase.contains("syntax") || lowercase.contains("parse error") {
            title = "Invalid SQL Syntax"
        } else if lowercase.contains("access denied") || lowercase.contains("authentication") {
            title = "Authentication Failed"
        } else if lowercase.contains("timed out") || lowercase.contains("timeout") {
            title = "Query Timed Out"
        } else if lowercase.contains("duplicate") || lowercase.contains("unique constraint") {
            title = "Duplicate Value"
        } else if lowercase.contains("foreign key") {
            title = "Foreign Key Constraint"
        } else {
            title = "Query Failed"
        }
    }
}

struct QueryErrorCard: View {
    let error: String
    let query: String
    let schemaContext: SchemaContext
    let aiAssistant: AIAssistant?
    var summary = "The database rejected this query."
    var offersNotifications = true
    var offersAISuggestion = true
    let onUseSuggestedSQL: (String) -> Void
    let onDismiss: () -> Void

    @Environment(SettingsManager.self) private var settingsManager
    @State private var requestedAISuggestion = false
    @State private var handledNotification = false
    @State private var notificationAuthorizationFailed = false

    private var presentation: QueryFailurePresentation {
        QueryFailurePresentation(message: error)
    }

    private var suggestedSQL: String? {
        guard let raw = aiAssistant?.lastError?.suggestedFix else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("```") {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            return lines
                .dropFirst()
                .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                .dropLast(lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Dismiss this error")
                .accessibilityLabel("Dismiss query error")
            }

            Text(presentation.detail)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    PlatformClipboard.copy(presentation.detail)
                } label: {
                    Label("Copy Error", systemImage: "doc.on.doc")
                }

                if offersAISuggestion, aiAssistant?.isAvailable == true {
                    Button {
                        requestAISuggestion()
                    } label: {
                        Label("Suggest Fix", systemImage: "apple.intelligence")
                    }
                    .disabled(aiAssistant?.isProcessing == true || query.isEmpty)
                    .help("Ask the on-device model for a potential correction")
                }
            }
            .controlSize(.small)

            if offersNotifications, settingsManager.shouldOfferQueryFailureNotifications {
                notificationOffer
            } else if notificationAuthorizationFailed {
                Label(
                    "Notifications remain off. You can allow them in System Settings.",
                    systemImage: "bell.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if requestedAISuggestion {
                aiSuggestion
            }
        }
        .padding(20)
        .frame(maxWidth: 760, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .padding(24)
        .task(id: error) {
            guard offersNotifications,
                  !handledNotification,
                  settingsManager.queryFailureNotificationsEnabled else { return }
            handledNotification = true
            await settingsManager.postQueryFailureNotification()
        }
    }

    private var notificationOffer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Get notified when a query fails", systemImage: "bell.badge")
                .font(.subheadline.weight(.semibold))
            Text("Notifications contain no SQL, schema names, literals, or server diagnostics.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Not Now") {
                    settingsManager.declineQueryFailureNotifications()
                }
                Button("Enable Notifications") {
                    Task {
                        let enabled = await settingsManager.enableQueryFailureNotifications()
                        notificationAuthorizationFailed = !enabled
                        if enabled {
                            handledNotification = true
                            await settingsManager.postQueryFailureNotification()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var aiSuggestion: some View {
        Divider()
        if aiAssistant?.isProcessing == true {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Apple Intelligence is reviewing the query and schema metadata…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if let explanation = aiAssistant?.lastError,
                  let suggestedSQL {
            VStack(alignment: .leading, spacing: 12) {
                Label("Potential Fix", systemImage: "apple.intelligence")
                    .font(.headline)

                Text(explanation.problem)
                    .font(.callout)

                Text(suggestedSQL)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))

                let safety = SQLHighlighter.safetyClassification(of: suggestedSQL)
                if safety.requiresConfirmation {
                    Label(
                        "This suggestion can modify database state and will still require confirmation.",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                HStack {
                    Button("Copy Suggested SQL", systemImage: "doc.on.doc") {
                        PlatformClipboard.copy(suggestedSQL)
                    }
                    Button("Use in Editor", systemImage: "arrow.up.doc") {
                        onUseSuggestedSQL(suggestedSQL)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)

                DisclosureGroup("Why this may work") {
                    Text(explanation.reasoning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                }
            }
        } else if let message = aiAssistant?.errorMessage {
            Label(message, systemImage: "apple.intelligence")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func requestAISuggestion() {
        guard let aiAssistant else { return }
        requestedAISuggestion = true
        aiAssistant.reset()
        Task {
            await aiAssistant.explainError(
                error: presentation.detail,
                query: query,
                context: schemaContext
            )
        }
    }
}

struct QueryDocumentTab: Identifiable {
    let id: UUID
    var text: String {
        didSet {
            guard text != oldValue else { return }
            generatedTitle = nil
            fallbackTitle = QueryDocumentTitle.fallback(for: text)
        }
    }
    private(set) var generatedTitle: String?
    private var fallbackTitle: String
    private(set) var savedText: String
    var selectedRange: NSRange
    var result: QueryResult?
    var isExecuting: Bool

    init(
        id: UUID = UUID(),
        text: String = "",
        isSaved: Bool = false,
        selectedRange: NSRange = NSRange(location: 0, length: 0),
        result: QueryResult? = nil,
        isExecuting: Bool = false
    ) {
        self.id = id
        self.text = text
        self.fallbackTitle = QueryDocumentTitle.fallback(for: text)
        self.savedText = isSaved ? text : ""
        self.selectedRange = selectedRange
        self.result = result
        self.isExecuting = isExecuting
    }

    var hasUnsavedChanges: Bool { text != savedText }

    mutating func markSaved() {
        savedText = text
    }

    var title: String {
        generatedTitle ?? fallbackTitle
    }

    mutating func applyGeneratedTitle(_ title: String, for source: String) {
        guard source == text, let title = QueryDocumentTitle.validated(title) else { return }
        generatedTitle = title
    }
}

enum QueryDocumentTitle {
    static func fallback(for sql: String) -> String {
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Untitled SQL" }
        guard sql.utf8.count <= 16_384 else { return "SQL Script" }
        let statements = SQLHighlighter.statements(in: sql)
        if statements.count > 1 { return "SQL Script · \(statements.count) statements" }
        let tokens = SQLHighlighter.tokenize(sql).filter { $0.kind != .comment }
        guard let first = tokens.first else { return "Untitled SQL" }
        let operation = String(sql[first.range]).uppercased()
        let label = ["SELECT": "Query", "WITH": "Query", "INSERT": "Insert", "UPDATE": "Update",
                     "DELETE": "Delete", "CREATE": "Create", "ALTER": "Alter", "DROP": "Drop"]
        // Only name a direct SELECT source. Complex queries get a neutral title
        // until the on-device model supplies a concise description.
        if operation == "SELECT", let from = tokens.firstIndex(where: { sql[$0.range].uppercased() == "FROM" }) {
            var index = from + 1
            var parts: [String] = []
            while index < tokens.count, tokens[index].kind == .identifier || tokens[index].kind == .plain {
                let part = String(sql[tokens[index].range]).trimmingCharacters(in: CharacterSet(charactersIn: "`\"[]"))
                parts.append(part)
                index += 1
                guard index < tokens.count, sql[tokens[index].range] == "." else { break }
                index += 1
            }
            if !parts.isEmpty { return String(parts.joined(separator: ".").prefix(64)) }
        }
        return label[operation].map { "\($0) SQL" } ?? "SQL Query"
    }

    static func modelInput(for sql: String) -> String? {
        guard !sql.isEmpty, sql.utf8.count <= 16_384 else { return nil }
        // Values and comments aren't needed to name a query, and may contain secrets.
        let pieces = SQLHighlighter.tokenize(sql).compactMap { token -> String? in
            switch token.kind {
            case .comment: return nil
            case .string, .number: return "?"
            case .error: return nil
            default:
                let value = String(sql[token.range])
                // MySQL can treat double quotes as literals, depending on mode.
                return value.hasPrefix("\"") ? "?" : value
            }
        }
        let input = pieces.joined(separator: " ")
        return input.isEmpty ? nil : input
    }

    static func validated(_ candidate: String) -> String? {
        let title = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 64,
              !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !title.contains(";"), !title.contains("`"), !title.contains("\n"),
              !title.uppercased().contains("SELECT "), !title.uppercased().contains("INSERT INTO ") else { return nil }
        return title
    }
}

struct QueryEditorView: View {
    let sessionID: UUID
    @Binding var document: QueryDocumentTab
    var isWorkspaceActive = true
    var onOpenSQLEditor: (() -> Void)?
    var onRequestClose: (() -> Void)?
    var onCreateDocument: ((QueryDocumentTab) -> Void)?
    var onRegisterCommandHandlers: ((QueryEditorCommandHandlers?) -> Void)?

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    /// This window's own settings (W24): its result row limit.
    @Environment(\.glassWindowOverrides) private var windowSettings
    @Environment(\.openWindow) private var openWindow

    @State private var showingHistory = false
    @State private var showingSavedQueries = false
    @State private var showingSaveQuery = false
    @State private var showingSQLImporter = false
    @State private var showingSQLExporter = false
    @State private var savedQueryName = ""
    @FocusState private var savedQueryNameFocused: Bool
    @State private var documentError: String?
    @State private var schemaCompletionIdentifiers: [String] = []
    @State private var editorController = SQLEditorController()
    @State private var completionLoadError: String?
    @State private var statementsAwaitingConfirmation: [SQLStatement] = []
    @State private var showingExecutionConfirmation = false

    private var session: DatabaseSession? {
        sessionManager.session(for: sessionID)
    }

    /// Document-level actions (Format, history/saved insertion, Clear, open)
    /// replace editor content through the shared handle; the editor model is
    /// the source of truth and state follows it (see SQLEditorController).
    private var queryText: String {
        get { document.text }
        nonmutating set {
            document.text = newValue
            editorController.setText(newValue)
        }
    }

    private var selectedRange: NSRange {
        get { document.selectedRange }
        nonmutating set {
            document.selectedRange = newValue
            editorController.setSelection(newValue)
        }
    }

    private var currentResult: QueryResult? {
        get { document.result }
        nonmutating set { document.result = newValue }
    }

    private var isExecuting: Bool {
        get { document.isExecuting }
        nonmutating set { document.isExecuting = newValue }
    }

    private var normalizedSavedQueryName: String {
        savedQueryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveCurrentQuery: Bool {
        !normalizedSavedQueryName.isEmpty
            && !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canCloseCurrentTab: Bool {
        !isExecuting
    }

    var body: some View {
        Group {
            if session != nil {
                DataTabView(
                    sessionID: sessionID,
                    document: $document,
                    isWorkspaceActive: isWorkspaceActive,
                    completionIdentifiers: schemaCompletionIdentifiers,
                    completionError: completionLoadError,
                    editorController: editorController
                )
                .environment(\.sqlEditorFocusToken, document.id)
            } else {
                ContentUnavailableView(
                    "Session Disconnected",
                    systemImage: "cable.connector.slash",
                    description: Text("This database session is no longer active.")
                )
            }
        }
        .glassActiveConnectionsLastInToolbar(isActive: isWorkspaceActive)
        .toolbar {
            if isWorkspaceActive {
                #if os(macOS)
                ToolbarSpacer(.flexible, placement: databaseToolbarPlacement)
                DatabasePersistentToolbar {
                    onOpenSQLEditor?()
                }
                #endif
                ToolbarItem(placement: databaseToolbarPlacement) {
                    SQLRunControl(availability: SQLRunAvailability(
                        canRun: session?.state.isConnected == true && !isExecuting
                            && !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        hasSelection: selectedRange.length > 0
                    )) { mode in
                        prepareExecution(SQLHighlighter.statementsToExecute(in: queryText, selectedRange: selectedRange, mode: mode))
                    }
                }
                .glassKeepVisibleWhenCompact()

                ToolbarItemGroup(placement: databaseToolbarPlacement) {
                    Button {
                        prepareExplainExecution()
                    } label: {
                        Label("Explain Plan", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .disabled(
                        session?.state.isConnected != true
                            || queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isExecuting
                    )
                    // The Query menu's key (⌥⌘E); ⇧⌘E is New Editor Window.
                    .keyboardShortcut("e", modifiers: [.command, .option])

                    if isExecuting,
                       session?.connection?.capabilities.contains(.cancellation) == true {
                        Button(role: .destructive) {
                            Task { await cancelExecution() }
                        } label: {
                            Label("Cancel Query", systemImage: "stop.fill")
                        }
                    }

                    Menu {
                        Button("Open SQL Document", systemImage: "folder") {
                            showingSQLImporter = true
                        }
                        Button("Save SQL Document", systemImage: "square.and.arrow.down") {
                            exportCurrentTab()
                        }
                        .disabled(queryText.isEmpty)
                        Divider()
                        Button("Query History", systemImage: "clock.arrow.circlepath") {
                            showingHistory = true
                        }
                        Button("Saved Queries", systemImage: "bookmark") {
                            showingSavedQueries = true
                        }
                        Divider()
                        Button("Save Current Query", systemImage: "bookmark.fill") {
                            savedQueryName = queryText
                                .split(whereSeparator: \.isNewline)
                                .first
                                .map { String($0.prefix(48)) } ?? ""
                            showingSaveQuery = true
                        }
                        .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } label: {
                        Label("Queries", systemImage: "books.vertical")
                    }

                    if let result = currentResult, result.error == nil {
                        Button {
                            openWindow(id: "database-results", value: result.id)
                        } label: {
                            Label("Detach Results", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .help("Open this result in a separate window")
                    }

                    Button {
                        queryText = ""
                        currentResult = nil
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(queryText.isEmpty && currentResult == nil)

                    Button {
                        let formatted = SQLHighlighter.formatted(queryText)
                        queryText = formatted
                        selectedRange = NSRange(location: (formatted as NSString).length, length: 0)
                    } label: {
                        Label("Format SQL", systemImage: "text.alignleft")
                    }
                    .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExecuting)
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                    Divider()

                    Button {
                        onCreateDocument?(QueryDocumentTab())
                    } label: {
                        Label("New Query Tab", systemImage: "plus.square.on.square")
                    }
                    .disabled(isExecuting)

                    Button {
                        onRequestClose?()
                    } label: {
                        Label("Close Query Tab", systemImage: "xmark.square")
                    }
                    .disabled(!canCloseCurrentTab)
                }
            }
        }
        // The workspace publishes the single focused-scene command value, so
        // this editor only registers its private verbs for its lifetime.
        // Hidden ZStack members register too; the workspace consults only the
        // active tab's bundle, so they can never clobber its routing.
        .onAppear {
            onRegisterCommandHandlers?(commandHandlers)
        }
        .onDisappear {
            onRegisterCommandHandlers?(nil)
        }
        .task(id: session?.currentDatabase) {
            await loadCompletionIdentifiers()
        }
        .task(id: isWorkspaceActive ? document.text : "") {
            guard isWorkspaceActive, document.generatedTitle == nil,
                  let input = QueryDocumentTitle.modelInput(for: document.text) else { return }
            let source = document.text
            do {
                try await Task.sleep(for: .milliseconds(1_200))
                guard let title = await AIAssistant.queryTitle(for: input), !Task.isCancelled else { return }
                document.applyGeneratedTitle(title, for: source)
            } catch {
                // Editing or switching tabs cancels obsolete naming work.
                return
            }
        }
        .onChange(of: session?.state) {
            guard session?.state.isConnected == true else { return }
            if let error = currentResult?.error,
               DatabaseSessionManager.isTerminalConnectionError(error) {
                currentResult = nil
            }
        }
        .fileImporter(
            isPresented: $showingSQLImporter,
            allowedContentTypes: Self.sqlDocumentTypes,
            allowsMultipleSelection: false
        ) { result in
            importSQLDocument(result)
        }
        .fileExporter(
            isPresented: $showingSQLExporter,
            document: SQLTextDocument(text: queryText),
            contentType: .plainText,
            defaultFilename: documentFilename
        ) { result in
            completeExport(result)
        }
        .sheet(isPresented: $showingHistory) {
            QueryHistoryView(
                connectionID: session?.connectionConfig.id,
                onSelect: { entry in
                    queryText = entry.sql
                    selectedRange = NSRange(location: (entry.sql as NSString).length, length: 0)
                    showingHistory = false
                }
            )
        }
        .sheet(isPresented: $showingSavedQueries) {
            SavedQueriesView(connectionID: session?.connectionConfig.id) { query in
                queryText = query.sql
                selectedRange = NSRange(location: (query.sql as NSString).length, length: 0)
                settingsManager.useSavedQuery(query.id)
                showingSavedQueries = false
            }
        }
        #if os(macOS)
        .sheet(isPresented: $showingSaveQuery) {
            saveQuerySheet
        }
        #else
        .alert("Save Query", isPresented: $showingSaveQuery) {
            TextField("Name", text: $savedQueryName)
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
            Button("Save") { saveCurrentQuery() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSaveCurrentQuery)
        } message: {
            Text("Saved queries remain available after the app restarts.")
        }
        #endif
        .alert("Review SQL Before Executing", isPresented: $showingExecutionConfirmation) {
            Button("Cancel", role: .cancel) {
                statementsAwaitingConfirmation = []
            }
            .keyboardShortcut(.cancelAction)
            Button("Execute", role: .destructive) {
                let statements = statementsAwaitingConfirmation
                statementsAwaitingConfirmation = []
                Task { await execute(statements) }
            }
            .help("Execute the reviewed SQL against the connected database")
        } message: {
            let classifications = Set(statementsAwaitingConfirmation.map(\.safety.displayName)).sorted()
            Text("This script contains SQL classified as \(classifications.joined(separator: ", ")). Review it carefully before continuing.")
        }
        .alert("SQL Document Error", isPresented: .init(
            get: { documentError != nil },
            set: { if !$0 { documentError = nil } }
        )) {
            Button("OK", role: .cancel) { documentError = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(documentError ?? "")
        }
    }

    #if os(macOS)
    private var saveQuerySheet: some View {
        NavigationStack {
            Form {
                Section("Saved Query") {
                    TextField("Name", text: $savedQueryName)
                        .focused($savedQueryNameFocused)
                        .onSubmit { saveCurrentQuery() }
                        .accessibilityLabel("Saved query name")
                        .help("Enter a name used to find this query later")
                    if normalizedSavedQueryName.isEmpty {
                        Label("Enter a name before saving.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("SQL Preview") {
                    Text(queryText)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(6)
                        .textSelection(.enabled)
                }
                Section {
                    Text("Saved queries remain available after the app restarts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Save Query")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSaveQuery = false }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCurrentQuery() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSaveCurrentQuery)
                }
            }
        }
        .frame(width: 520, height: 400)
        .onAppear { savedQueryNameFocused = true }
    }
    #endif

    private func saveCurrentQuery() {
        guard canSaveCurrentQuery else { return }
        settingsManager.addSavedQuery(SavedQuery(
            name: normalizedSavedQueryName,
            sql: queryText,
            connectionID: session?.connectionConfig.id
        ))
        showingSaveQuery = false
    }

    private var commandHandlers: QueryEditorCommandHandlers {
        QueryEditorCommandHandlers(
            executeStatement: prepareCurrentStatementExecution,
            executeScript: prepareScriptExecution,
            explainPlan: prepareExplainExecution,
            cancel: { Task { await cancelExecution() } },
            showHistory: { showingHistory = true },
            showSavedQueries: { showingSavedQueries = true },
            executeSelection: {
                prepareExecution(SQLHighlighter.statementsToExecute(in: queryText, selectedRange: selectedRange, mode: .selection))
            },
            executeCurrentStatement: {
                prepareExecution(SQLHighlighter.statementsToExecute(in: queryText, selectedRange: selectedRange, mode: .statement))
            }
        )
    }

    private var activeTabTitle: String {
        document.title
    }

    static var sqlDocumentTypes: [UTType] {
        if let sql = UTType(filenameExtension: "sql") {
            return [sql, .plainText]
        }
        return [.plainText]
    }

    static let maximumSQLDocumentBytes = 10 * 1_024 * 1_024

    static func decodedSQLDocumentText(_ data: Data) throws -> String {
        // Recheck the bytes actually read: the file may grow after the metadata
        // preflight and before Data(contentsOf:) completes.
        guard data.count <= maximumSQLDocumentBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    private var documentFilename: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let title = activeTabTitle
        let sanitized = title.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let basename = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return (basename.isEmpty ? "query" : basename) + ".sql"
    }

    private func exportCurrentTab() {
        showingSQLExporter = true
    }

    private func completeExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            document.markSaved()
        case .failure(let error):
            let cocoaError = error as? CocoaError
            if cocoaError?.code != .userCancelled {
                documentError = error.localizedDescription
            }
        }
    }

    /// Reads a user-selected SQL file into a fresh saved document tab. Shared
    /// by the editor's toolbar importer and the workspace's File-menu ⌘O
    /// importer, which must work even when no editor exists yet.
    static func importedSQLDocument(from result: Result<[URL], Error>) throws -> QueryDocumentTab? {
        guard let url = try result.get().first else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size <= maximumSQLDocumentBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return QueryDocumentTab(text: try decodedSQLDocumentText(data), isSaved: true)
    }

    private func importSQLDocument(_ result: Result<[URL], Error>) {
        do {
            guard let document = try Self.importedSQLDocument(from: result) else { return }
            onCreateDocument?(document)
        } catch {
            documentError = error.localizedDescription
        }
    }

    // MARK: - Execution

    private func prepareCurrentStatementExecution() {
        prepareExecution(SQLHighlighter.statementsToExecute(in: queryText, selectedRange: selectedRange))
    }

    private func prepareScriptExecution() {
        prepareExecution(SQLHighlighter.statements(in: queryText))
    }

    private func prepareExplainExecution() {
        guard session?.state.isConnected == true,
              let statement = SQLHighlighter.statementsToExecute(
            in: queryText,
            selectedRange: selectedRange
        ).first else { return }
        Task { await explain(statement.text) }
    }

    private func prepareExecution(_ statements: [SQLStatement]) {
        guard session?.state.isConnected == true, !isExecuting, !statements.isEmpty else { return }
        if statements.contains(where: { $0.safety.requiresConfirmation }) {
            statementsAwaitingConfirmation = statements
            showingExecutionConfirmation = true
        } else {
            Task { await execute(statements) }
        }
    }

    private func execute(_ statements: [SQLStatement]) async {
        guard !isExecuting else { return }
        isExecuting = true
        defer { isExecuting = false }

        var executingSQL = ""
        do {
            for statement in statements {
                executingSQL = statement.text
                currentResult = try await sessionManager.executeQuery(
                    statement.text,
                    sessionID: sessionID,
                    editorRowLimit: DatabaseWindowProfile.resolved(windowSettings, settings: settingsManager)
                        .resultRowLimit
                )
                // Keep a server-error result visible and stop the batch even
                // when the adapter reports it without throwing.
                if currentResult?.error != nil { return }
            }
        } catch {
            currentResult = QueryResult(
                query: executingSQL,
                executionTime: 0,
                error: error.localizedDescription
            )
        }
    }

    private func explain(_ statement: String) async {
        isExecuting = true
        defer { isExecuting = false }
        do {
            currentResult = try await sessionManager.explainQuery(statement, sessionID: sessionID)
        } catch {
            currentResult = QueryResult(
                query: statement,
                executionTime: 0,
                error: error.localizedDescription
            )
        }
    }

    private func cancelExecution() async {
        do {
            try await sessionManager.cancelQuery(sessionID: sessionID)
        } catch {
            currentResult = QueryResult(
                query: queryText,
                executionTime: 0,
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Completion

    private func loadCompletionIdentifiers() async {
        guard let connection = session?.connection else { return }
        do {
            schemaCompletionIdentifiers = try await SchemaCompletionIdentifiers.load(
                connection: connection,
                database: session?.currentDatabase
            )
            completionLoadError = nil
        } catch {
            schemaCompletionIdentifiers = []
            completionLoadError = error.localizedDescription
        }
    }

}

// MARK: - Durable History

private struct QueryHistoryView: View {
    let connectionID: UUID?
    let onSelect: (QueryHistoryEntry) -> Void

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var status: QueryHistoryStatus = .all
    @State private var confirmingDeleteAll = false

    private var entries: [QueryHistoryEntry] {
        sessionManager.queryHistory(
            matching: searchText,
            connectionID: connectionID,
            status: status
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Query History" : "No Matches",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(searchText.isEmpty
                            ? "Executed queries appear here and persist across launches."
                            : "Try a different query or status filter.")
                    )
                } else {
                    List(entries) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.sql)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 10) {
                                    Text(entry.timestamp, format: .dateTime.month().day().hour().minute().second())
                                    if let database = entry.database { Text(database) }
                                    Text("\(entry.duration, format: .number.precision(.fractionLength(3)))s")
                                    if let rowCount = entry.rowCount { Text("\(rowCount) rows") }
                                    if let affectedRows = entry.affectedRows { Text("\(affectedRows) affected") }
                                    if entry.error != nil {
                                        Label("Failed", systemImage: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                sessionManager.deleteQueryHistory(id: entry.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Query History")
            .searchable(text: $searchText, prompt: "SQL, database, or error")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Status", selection: $status) {
                            ForEach(QueryHistoryStatus.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        Divider()
                        Button("Clear This Connection", role: .destructive) {
                            confirmingDeleteAll = true
                        }
                        .disabled(connectionID == nil || entries.isEmpty)
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .help("Filter history by execution status or clear this connection's history")
                }
            }
        }
        #if os(macOS)
        .frame(width: 760, height: 560)
        #else
        .frame(minWidth: 720, minHeight: 520)
        #endif
        .alert("Clear Query History?", isPresented: $confirmingDeleteAll) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
            Button("Clear", role: .destructive) {
                sessionManager.deleteAllQueryHistory(connectionID: connectionID)
            }
        } message: {
            Text("This permanently removes saved history for this connection.")
        }
    }
}

private struct SavedQueriesView: View {
    let connectionID: UUID?
    let onSelect: (SavedQuery) -> Void

    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var queries: [SavedQuery] {
        settingsManager.savedQueries
            .filter { query in
                (query.connectionID == nil || query.connectionID == connectionID)
                    && (searchText.isEmpty
                        || query.name.localizedCaseInsensitiveContains(searchText)
                        || query.sql.localizedCaseInsensitiveContains(searchText))
            }
            .sorted {
                ($0.lastUsed ?? $0.createdAt) > ($1.lastUsed ?? $1.createdAt)
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if queries.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Saved Queries" : "No Matches",
                        systemImage: "bookmark",
                        description: Text(searchText.isEmpty
                            ? "Use Save Current Query from the editor toolbar to add one."
                            : "Try a different name or SQL search.")
                    )
                } else {
                    List(queries) { query in
                        Button {
                            onSelect(query)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(query.name)
                                    .font(.headline)
                                Text(query.sql)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(3)
                                HStack {
                                    Text("Used \(query.useCount) times")
                                    Text(query.lastUsed ?? query.createdAt, style: .relative)
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                settingsManager.deleteSavedQuery(query)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Queries")
            .searchable(text: $searchText, prompt: "Name or SQL")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        #if os(macOS)
        .frame(width: 760, height: 560)
        #else
        .frame(minWidth: 720, minHeight: 520)
        #endif
    }
}
