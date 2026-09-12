//
//  ConnectionFormView.swift
//  glassdb
//
//  Add/Edit database connection form — sheet presentation
//  Pattern adapted from glas.sh ServerFormViews.swift (EditServerView)
//

import SwiftUI
import UniformTypeIdentifiers
import os
import GlasSecretStore
import GlassDBKit
#if os(iOS)
import UIKit
#endif

enum SQLiteFileImporter {
    enum ImportError: LocalizedError {
        case sourceIsNotAFile
        case managedCopyMissing
        case outsideManagedDirectory

        var errorDescription: String? {
            switch self {
            case .sourceIsNotAFile:
                return "The selected SQLite item is not a readable file."
            case .managedCopyMissing:
                return "The imported SQLite database is missing. Import it again."
            case .outsideManagedDirectory:
                return "The SQLite database is outside this app’s managed storage. Import it again."
            }
        }
    }

    static func managedDirectory(
        fileManager: FileManager = .default,
        create: Bool
    ) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let directory = applicationSupport
            .appendingPathComponent("glassdb", isDirectory: true)
            .appendingPathComponent("SQLite Databases", isDirectory: true)
        if create {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func importFile(
        at sourceURL: URL,
        fileManager: FileManager = .default,
        destinationID: UUID = UUID()
    ) throws -> URL {
        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw ImportError.sourceIsNotAFile }

        let directory = try managedDirectory(fileManager: fileManager, create: true)
        let fileExtension = sourceURL.pathExtension.isEmpty ? "sqlite" : sourceURL.pathExtension
        let importedURL = directory
            .appendingPathComponent(destinationID.uuidString)
            .appendingPathExtension(fileExtension)
        do {
            try SQLiteEngine.createManagedSnapshot(
                from: sourceURL,
                at: importedURL,
                fileManager: fileManager
            )
            return try validatedURL(forPath: importedURL.path, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: importedURL)
            throw error
        }
    }

    static func validatedURL(
        forPath path: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let candidate = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: candidate.path) else {
            throw ImportError.managedCopyMissing
        }
        let root = try managedDirectory(fileManager: fileManager, create: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count > rootComponents.count,
              candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents) else {
            throw ImportError.outsideManagedDirectory
        }
        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw ImportError.sourceIsNotAFile }
        return candidate
    }
}

struct ConnectionFormView: View {
    enum Mode {
        case add
        case edit(DatabaseConnectionConfig)
    }

    let mode: Mode
    let onSave: (DatabaseConnectionConfig, String) throws -> Void
    /// How to open a forward through the host's Terminal service (D7). Supplied by the
    /// capability, which knows the host; nil here means Test and Save & Connect can only
    /// reach the database directly, and the form says so rather than failing obscurely.
    let openForward: DatabaseSessionManager.PortForwardProvider?

    enum FormField: Hashable {
        case name
        case host
        case port
        case username
        case password
        case defaultDatabase
    }

    struct ValidationInput {
        let name: String
        let engine: DatabaseEngineType
        let host: String
        let port: String
        let username: String
        let sqliteFileExists: Bool
    }

    @Environment(SettingsManager.self) private var settingsManager
    @Environment(DatabaseSessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    #if os(iOS)
    @Environment(DatabaseIOSRouter.self) private var iOSRouter
    #endif

    // MARK: - Form Fields

    @State private var name: String = ""
    @State private var engine: DatabaseEngineType = .mysql
    @State private var host: String = "127.0.0.1"
    @State private var port: String = "3306"
    @State private var username: String = "root"
    @State private var password: String = ""
    @State private var databaseCredentialPolicy: CredentialStoragePolicy = .appOnly
    @State private var defaultDatabase: String = ""
    @State private var useTLS: Bool = false
    /// D7: reach the database through the host's own Terminal service. One switch replaces
    /// glassdb's entire SSH Tunnel section — there is nothing left to configure here, because
    /// that service already holds the address, the credential and the host-key trust.
    @State private var usesHostTunnel: Bool = false

    @State private var colorTag: ConnectionColorTag = .none
    @State private var tagsText: String = ""
    @State private var showPassword = false
    @State private var showingSQLiteImporter = false
    @State private var stagedSQLiteURL: URL?
    @State private var attemptedSave = false
    @State private var touchedFields: Set<FormField> = []
    @State private var isSavingAndConnecting = false
    @State private var saveAndConnectTask: Task<Void, Never>?
    @FocusState private var focusedField: FormField?

    // MARK: - Test State

    enum TestResult: Equatable {
        case testing
        case success
        case failure(String)

        var statusTitle: String {
            switch self {
            case .testing:
                return "Testing…"
            case .success:
                return "Passed"
            case .failure:
                return "Failed"
            }
        }

        var errorMessage: String? {
            guard case .failure(let message) = self else { return nil }
            return message
        }
    }

    @State private var dbTestResult: TestResult?

    private var isTestingConnection: Bool {
        dbTestResult == .testing
    }

    // MARK: - Connection Error

    @State private var connectionError: String?
    @State private var databaseCredentialLoadFailed = false
    @State private var didLoadStoredCredentials = false

    // MARK: - Computed

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingConnection: DatabaseConnectionConfig? {
        if case .edit(let connection) = mode { return connection }
        return nil
    }

    static func validationIssues(for input: ValidationInput) -> [FormField: String] {
        var issues: [FormField: String] = [:]
        if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues[.name] = "Enter a name for this connection."
        }
        if input.engine == .sqlite {
            if input.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues[.host] = "Choose a SQLite database file."
            } else if !input.sqliteFileExists {
                issues[.host] = "The imported SQLite file is no longer available."
            }
            return issues
        }
        if input.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues[.host] = "Enter a database hostname or IP address."
        }
        if input.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues[.username] = "Enter the database username."
        }
        if let parsedPort = Int(input.port), (1...65_535).contains(parsedPort) {
            // Valid TCP port.
        } else {
            issues[.port] = "Enter a port from 1 through 65535."
        }
        return issues
    }

    /// Submitting a field only advances focus. It never implies Save, Test, or
    /// Save & Connect, which are deliberately separate explicit actions.
    static func nextField(after field: FormField, in order: [FormField]) -> FormField? {
        guard let index = order.firstIndex(of: field),
              order.indices.contains(index + 1) else { return nil }
        return order[index + 1]
    }

    private var validationInput: ValidationInput {
        ValidationInput(
            name: name,
            engine: engine,
            host: host,
            port: port,
            username: username,
            sqliteFileExists: FileManager.default.fileExists(atPath: host)
        )
    }

    private var validationIssues: [FormField: String] {
        Self.validationIssues(for: validationInput)
    }

    private var isFormValid: Bool {
        validationIssues.isEmpty
    }

    init(mode: Mode,
         openForward: DatabaseSessionManager.PortForwardProvider? = nil,
         onSave: @escaping (DatabaseConnectionConfig, String) throws -> Void) {
        self.mode = mode
        self.openForward = openForward
        self.onSave = onSave

        // Pre-populate @State from connection in edit mode (glas.sh EditServerView:277-289 pattern)
        if case .edit(let connection) = mode {
            _name = State(initialValue: connection.name)
            _engine = State(initialValue: connection.engine)
            _host = State(initialValue: connection.host)
            _port = State(initialValue: String(connection.port))
            _username = State(initialValue: connection.username)
            // Defensive clamp mirroring the decoder: database passwords are
            // never shared with glas.sh.
            _databaseCredentialPolicy = State(
                initialValue: connection.databaseCredentialPolicy == .sharedWithGlas
                    ? .appOnly
                    : connection.databaseCredentialPolicy
            )
            _defaultDatabase = State(initialValue: connection.defaultDatabase ?? "")
            _useTLS = State(initialValue: connection.useTLS)
            _usesHostTunnel = State(initialValue: connection.usesHostTunnel)
            _colorTag = State(initialValue: connection.colorTag)
            _tagsText = State(initialValue: connection.tags.joined(separator: ", "))
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            platformForm
                .navigationTitle(isEditing ? "Edit Connection" : "Add Connection")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancelForm() }
                            .connectionFormCancelShortcut()
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isEditing ? "Save Changes" : "Save Connection") { save() }
                            .disabled(!isFormValid || isSavingAndConnecting)
                            .connectionFormDefaultShortcut()
                            .accessibilityIdentifier("connection-form.save")
                    }
                }
        }
        .connectionFormSheetSize()
        .onAppear {
            loadKeychainCredentials()
            #if os(macOS)
            focusedField = .name
            #endif
        }
        .onChange(of: engine) { _, newEngine in
            if newEngine != .sqlite {
                discardStagedSQLiteFile()
            }
            host = newEngine.defaultHost
            port = String(newEngine.defaultPort)
            username = newEngine.defaultUsername
            defaultDatabase = ""
            useTLS = false
            usesHostTunnel = false
            dbTestResult = nil
        }
        .onChange(of: name) { _, _ in markTouched(.name) }
        .onChange(of: host) { _, _ in markTouched(.host) }
        .onChange(of: port) { _, _ in markTouched(.port) }
        .onChange(of: username) { _, _ in markTouched(.username) }
        .onChange(of: password) { _, _ in markTouched(.password) }
        .onChange(of: defaultDatabase) { _, _ in markTouched(.defaultDatabase) }
        .onChange(of: usesHostTunnel) { _, _ in
            dbTestResult = nil
        }
        .onChange(of: useTLS) { _, _ in
            dbTestResult = nil
        }
        .fileImporter(
            isPresented: $showingSQLiteImporter,
            allowedContentTypes: Self.sqliteContentTypes,
            allowsMultipleSelection: false
        ) { result in
            importSQLiteFile(result)
        }
        .onDisappear {
            saveAndConnectTask?.cancel()
            discardStagedSQLiteFile()
        }
        .alert("Connection Error", isPresented: .init(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK", role: .cancel) { connectionError = nil }
        } message: {
            Text(connectionError ?? "")
        }
    }

    @ViewBuilder
    private var platformForm: some View {
        #if os(macOS)
        Form {
            macConnectionSection
            macDatabaseAuthenticationSection
            macAdvancedSection
            macAppearanceSection
            macTestSection
        }
        .formStyle(.grouped)
        #else
        Form {
            connectionSection
            databaseAuthSection
            hostTunnelSection
            appearanceSection
            testSection
        }
        #endif
    }

    #if os(macOS)
    // MARK: - macOS Form

    private var macConnectionSection: some View {
        Section {
            macTextField(
                "Name",
                prompt: "Production database",
                text: $name,
                field: .name,
                help: "A recognizable name used in the connection list.",
                isRequired: true
            )
            LabeledContent("Database engine") {
                Picker("Database engine", selection: $engine) {
                    ForEach(DatabaseEngineType.allCases) { candidate in
                        Text(candidate.displayName).tag(candidate)
                    }
                }
                .labelsHidden()
                .frame(width: 340, alignment: .leading)
                .help("Select the database protocol to use.")
            }
            if engine == .sqlite {
                LabeledContent("Database file") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: host.isEmpty ? "doc.badge.plus" : "cylinder")
                                .foregroundStyle(.secondary)
                            Text(host.isEmpty ? "No file selected" : URL(fileURLWithPath: host).lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Button(host.isEmpty ? "Choose…" : "Replace…") {
                                showingSQLiteImporter = true
                            }
                        }
                        .frame(width: 340)
                        macValidationMessage(for: .host)
                    }
                }
                .help("A private working copy is imported; the original file is not modified.")
            } else {
                macTextField(
                    "Host",
                    prompt: "127.0.0.1",
                    text: $host,
                    field: .host,
                    help: "Database server hostname, IPv4 address, or IPv6 address.",
                    isRequired: true
                )
                macTextField(
                    "Port",
                    prompt: String(engine.defaultPort),
                    text: $port,
                    field: .port,
                    help: "TCP port used by the database server."
                )
            }
        } header: {
            Text("Connection")
        } footer: {
            if engine == .sqlite {
                Text("SQLite databases are copied into this app’s managed application storage before use.")
            }
        }
    }

    @ViewBuilder
    private var macDatabaseAuthenticationSection: some View {
        if engine.supportsCredentials {
            Section("Database Authentication") {
                macTextField(
                    "Username",
                    prompt: engine.defaultUsername,
                    text: $username,
                    field: .username,
                    help: "Account name sent to the database server.",
                    isRequired: true
                )
                passwordField(
                    label: "Password",
                    text: $password,
                    showPlaintext: $showPassword
                )
                credentialPolicyPicker(
                    label: "Password storage",
                    selection: $databaseCredentialPolicy,
                    options: CredentialStoragePolicy.databasePolicies
                )
                macTextField(
                    "Default database",
                    prompt: "Optional",
                    text: $defaultDatabase,
                    field: .defaultDatabase,
                    help: "Database or schema opened immediately after connecting."
                )
            }
        }
    }

    private var macAdvancedSection: some View {
        Section("Advanced") {
            if engine.supportsTLS {
                Toggle("Encrypt the database connection", isOn: $useTLS)
                    .help("Use TLS for traffic between this app and the database server.")
            }
            hostTunnelToggle
        }
    }

    private var macAppearanceSection: some View {
        Section("Appearance") {
            LabeledContent("Color tag") {
                Picker("Color tag", selection: $colorTag) {
                    ForEach(ConnectionColorTag.allCases, id: \.self) { tag in
                        Label(tag.displayName, systemImage: "circle.fill")
                            .foregroundStyle(tag.color)
                            .tag(tag)
                    }
                }
                .labelsHidden()
                .frame(width: 340, alignment: .leading)
                .help("Color used to identify this connection in the sidebar.")
            }
            LabeledContent("Collections") {
                TextField("Production, Client A", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 340, alignment: .leading)
                    .help("Comma-separated collections used to organize and find this connection.")
            }
        }
    }

    private var macTestSection: some View {
        Section {
            testDBButton
            saveAndConnectButton
        } header: {
            Text("Connection Actions")
        } footer: {
            Text("Test checks the current values without saving. Save & Connect stores the connection, then opens a session only when you choose it explicitly.")
        }
    }

    private func macTextField(
        _ label: String,
        prompt: String,
        text: Binding<String>,
        field: FormField,
        help: String,
        isRequired: Bool = false
    ) -> some View {
        LabeledContent {
            VStack(alignment: .leading, spacing: 6) {
                TextField(label, text: text, prompt: Text(prompt))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .autocorrectionDisabled()
                    .databaseNoAutocapitalization()
                    .focused($focusedField, equals: field)
                    .onSubmit { advanceFocus(after: field) }
                    .frame(width: 340)
                macValidationMessage(for: field)
            }
        } label: {
            requiredFieldLabel(label, isRequired: isRequired)
        }
        .help(help)
    }

    @ViewBuilder
    private func macValidationMessage(for field: FormField) -> some View {
        if (attemptedSave || touchedFields.contains(field)),
           let message = validationIssues[field] {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Error: \(message)")
        }
    }

    #endif

    /// Requirements are stated up front rather than revealed after a failed
    /// save, so a disabled Save button is self-explanatory: the form says what
    /// it needs before anything is attempted. Optional fields stay unmarked,
    /// which is meaningful too — a blank Password never blocks saving.
    @ViewBuilder
    private func requiredFieldLabel(_ label: String, isRequired: Bool = true) -> some View {
        if isRequired {
            HStack(spacing: 6) {
                Text(label)
                Text("Required")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label), required")
        } else {
            Text(label)
        }
    }

    // MARK: - Connection Section

    @ViewBuilder
    private var connectionSection: some View {
        Section("Connection") {
            LabeledContent {
                TextField("Display Name", text: $name)
                    .multilineTextAlignment(.leading)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { advanceFocus(after: .name) }
            } label: {
                requiredFieldLabel("Name")
            }
            Picker("Engine", selection: $engine) {
                ForEach(DatabaseEngineType.allCases) { eng in
                    Text(eng.displayName).tag(eng)
                }
            }
            if engine == .sqlite {
                LabeledContent("Database File") {
                    Text(host.isEmpty ? "No file selected" : URL(fileURLWithPath: host).lastPathComponent)
                        .foregroundStyle(host.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                }
                Button {
                    showingSQLiteImporter = true
                } label: {
                    Label(host.isEmpty ? "Choose SQLite File" : "Choose Different File", systemImage: "folder")
                }
            } else {
                LabeledContent {
                    TextField("127.0.0.1", text: $host)
                        .multilineTextAlignment(.leading)
                        .autocorrectionDisabled()
                        .databaseNoAutocapitalization()
                        .databaseASCIICapableKeyboard()
                        .textContentType(.URL)
                        .focused($focusedField, equals: .host)
                        .submitLabel(.next)
                        .onSubmit { advanceFocus(after: .host) }
                } label: {
                    requiredFieldLabel("Host")
                }
                LabeledContent("Port") {
                    TextField("\(engine.defaultPort)", text: $port)
                        .multilineTextAlignment(.leading)
                        .autocorrectionDisabled()
                        .databaseNoAutocapitalization()
                        .connectionPortKeyboard()
                        .focused($focusedField, equals: .port)
                        .submitLabel(.next)
                        .onSubmit { advanceFocus(after: .port) }
                }
            }
        }
    }

    private static var sqliteContentTypes: [UTType] {
        var types: [UTType] = [.data]
        for filenameExtension in ["sqlite", "sqlite3", "db"] {
            if let type = UTType(filenameExtension: filenameExtension) {
                types.insert(type, at: 0)
            }
        }
        return types
    }

    private func importSQLiteFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let importedURL = try SQLiteFileImporter.importFile(at: url)
            discardStagedSQLiteFile()
            stagedSQLiteURL = importedURL
            host = importedURL.path
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
            dbTestResult = nil
        } catch {
            connectionError = "The SQLite file could not be imported. \(error.localizedDescription)"
        }
    }

    // MARK: - Database Auth Section

    @ViewBuilder
    private var databaseAuthSection: some View {
        if engine != .sqlite {
            Section("Database Authentication") {
            LabeledContent {
                TextField("root", text: $username)
                    .multilineTextAlignment(.leading)
                    .autocorrectionDisabled()
                    .databaseNoAutocapitalization()
                    .databaseASCIICapableKeyboard()
                    .textContentType(.username)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { advanceFocus(after: .username) }
            } label: {
                requiredFieldLabel("Username")
            }
            passwordField(
                label: "Password",
                text: $password,
                showPlaintext: $showPassword
            )
            credentialPolicyPicker(
                label: "Password Storage",
                selection: $databaseCredentialPolicy,
                options: CredentialStoragePolicy.databasePolicies
            )
            LabeledContent("Default Database") {
                TextField("Optional", text: $defaultDatabase)
                    .multilineTextAlignment(.leading)
                    .autocorrectionDisabled()
                    .databaseNoAutocapitalization()
                    .databaseASCIICapableKeyboard()
                    .focused($focusedField, equals: .defaultDatabase)
                    .submitLabel(.done)
                    .onSubmit { advanceFocus(after: .defaultDatabase) }
            }
            Toggle("Use TLS", isOn: $useTLS)
            }
        } else {
            Section("Local Database") {
                Text("A private working copy of the selected SQLite file is imported. The original file is left unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - SSH Tunnel Section


    /// D7's whole replacement for glassdb's SSH Tunnel section: one switch, shown only for an
    /// engine that speaks over a network. Everything the tunnel needs — address, credential,
    /// host-key trust — already belongs to the host's Terminal service.
    @ViewBuilder
    private var hostTunnelToggle: some View {
        if engine.supportsNetworkTransport {
            Toggle("Reach it through this machine's Terminal service", isOn: $usesHostTunnel)
                .help("Open the database connection over a port forward through the machine's own SSH service, for a database that only listens on that machine.")
                .accessibilityIdentifier("connection-form.host-tunnel")
            if usesHostTunnel, openForward == nil {
                Text("This machine has no Terminal service to tunnel through yet. Add one, or turn this off and connect directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var hostTunnelSection: some View {
        if engine.supportsNetworkTransport {
            Section("Tunnel") {
                hostTunnelToggle
            }
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Color Tag", selection: $colorTag) {
                ForEach(ConnectionColorTag.allCases, id: \.self) { tag in
                    Label(tag.displayName, systemImage: "circle.fill")
                        .foregroundStyle(tag.color)
                        .tag(tag)
                }
            }
            LabeledContent("Collections") {
                TextField("Production, Client A", text: $tagsText)
                    .multilineTextAlignment(.leading)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
        }
    }

    // MARK: - Test Section

    private var testSection: some View {
        Section {
            testDBButton
            saveAndConnectButton
        } header: {
            Text("Connection Actions")
        } footer: {
            Text("Test checks the current values without saving. Save & Connect stores the connection, then opens a session only when you choose it explicitly.")
        }
    }

    // MARK: - Password Field (reusable, glas.sh SecureField + eye toggle + paste)

    private func passwordField(
        label: String,
        text: Binding<String>,
        showPlaintext: Binding<Bool>
    ) -> some View {
        #if os(macOS)
        LabeledContent(label) {
            passwordControl(label: label, text: text, showPlaintext: showPlaintext)
                .frame(width: 340)
        }
        .help("The password is stored according to the selected Keychain policy.")
        #else
        passwordControl(label: label, text: text, showPlaintext: showPlaintext)
        #endif
    }

    private func passwordControl(
        label: String,
        text: Binding<String>,
        showPlaintext: Binding<Bool>
    ) -> some View {
        let field: FormField = .password
        let prompt = isEditing ? "Leave blank to keep saved password" : label
        return HStack(spacing: 8) {
            if showPlaintext.wrappedValue {
                TextField(label, text: text, prompt: Text(prompt))
                    .connectionPasswordFieldPresentation()
                    .autocorrectionDisabled()
                    .databaseNoAutocapitalization()
                    .textContentType(.password)
                    .focused($focusedField, equals: field)
                    .onSubmit { advanceFocus(after: field) }
            } else {
                SecureField(label, text: text, prompt: Text(prompt))
                    .connectionPasswordFieldPresentation()
                    .textContentType(.password)
                    .focused($focusedField, equals: field)
                    .onSubmit { advanceFocus(after: field) }
            }
            Button {
                showPlaintext.wrappedValue.toggle()
            } label: {
                Image(systemName: showPlaintext.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showPlaintext.wrappedValue ? "Hide password" : "Show password")
            PasteButton(payloadType: String.self) { strings in
                if let value = strings.first {
                    text.wrappedValue = value
                }
            }
            .buttonBorderShape(.circle)
            .labelStyle(.iconOnly)
            .accessibilityLabel("Paste from clipboard")
        }
    }

    private func credentialPolicyPicker(
        label: String,
        selection: Binding<CredentialStoragePolicy>,
        options: [CredentialStoragePolicy]
    ) -> some View {
        #if os(macOS)
        LabeledContent(label) {
            VStack(alignment: .leading, spacing: 6) {
                Menu {
                    ForEach(options) { policy in
                        Button {
                            selection.wrappedValue = policy
                        } label: {
                            if selection.wrappedValue == policy {
                                Label(policy.displayName, systemImage: "checkmark")
                            } else {
                                Text(policy.displayName)
                            }
                        }
                        .disabled(
                            policy == .sharedWithGlas
                                && !KeychainManager.sharedCredentialAccessAvailable
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selection.wrappedValue.displayName)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 316, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .accessibilityLabel(label)
                .accessibilityValue(selection.wrappedValue.displayName)
                Text(credentialPolicyDescription(selection.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 340, alignment: .leading)
        }
        .help("Choose which Keychain access policy protects this password.")
        #else
        VStack(alignment: .leading, spacing: 6) {
            Picker(label, selection: selection) {
                ForEach(options) { policy in
                    Text(policy.displayName).tag(policy)
                        .disabled(
                            policy == .sharedWithGlas
                                && !KeychainManager.sharedCredentialAccessAvailable
                        )
                }
            }
            Text(credentialPolicyDescription(selection.wrappedValue))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        #endif
    }

    private func credentialPolicyDescription(_ policy: CredentialStoragePolicy) -> String {
        if policy == .sharedWithGlas, !KeychainManager.sharedCredentialAccessAvailable {
            return "Shared Keychain access is unavailable in this unsigned or unprovisioned build. This credential remains in the current app’s default Keychain."
        }
        return policy.policyDescription
    }

    // MARK: - Shared SSH Credential Catalog
    //
    // Deliberately absent. glassdb let a database connection borrow a glas.sh SSH identity
    // (`../glassdb/glassdb/ConnectionFormView.swift:1248-1340`) and pick one of its own SSH
    // keys. Under D7 there is nothing to pick: the tunnel is the host's Terminal service, and
    // that service's own setup already chose the identity.

    // MARK: - Test Buttons


    private var testDBButton: some View {
        HStack {
            Button {
                testDB()
            } label: {
                Label("Test Connection", systemImage: "bolt")
            }
            .disabled(!isFormValid || isTestingConnection)
            .help("Verify the complete database connection without saving.")
            .accessibilityIdentifier("connection-form.test")

            Spacer()

            testResultIndicator(dbTestResult, accessibilityName: "Database connection")
        }
    }

    private var saveAndConnectButton: some View {
        Button {
            saveAndConnect()
        } label: {
            if isSavingAndConnecting {
                Label("Saving & Connecting…", systemImage: "bolt.horizontal.circle")
            } else {
                Label("Save & Connect", systemImage: "bolt")
            }
        }
        .disabled(!isFormValid || isTestingConnection || isSavingAndConnecting)
        .connectionFormConnectShortcut()
        .help("Save this connection, then connect using the current credentials.")
        .accessibilityHint("This is the only form action that saves and starts a database connection.")
        .accessibilityIdentifier("connection-form.save-and-connect")
    }

    @ViewBuilder
    private func testResultIndicator(
        _ result: TestResult?,
        accessibilityName: String
    ) -> some View {
        switch result {
        case .none:
            EmptyView()
        case .testing:
            ProgressView(result?.statusTitle ?? "Testing…")
                .controlSize(.small)
                .accessibilityLabel("\(accessibilityName) test in progress")
        case .success:
            Label(result?.statusTitle ?? "Passed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
                .accessibilityLabel("\(accessibilityName) test succeeded")
        case .failure:
            Button {
                connectionError = result?.errorMessage
            } label: {
                Label(result?.statusTitle ?? "Failed", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(accessibilityName) test failed")
            .accessibilityHint("Shows error details")
        }
    }

    // MARK: - Keychain Load (glas.sh EditServerView pattern)

    private func loadKeychainCredentials() {
        guard !didLoadStoredCredentials, let connection = editingConnection else { return }
        didLoadStoredCredentials = true

        if connection.engine.supportsCredentials {
            do {
                password = try KeychainManager.retrievePassword(for: connection)
                databaseCredentialLoadFailed = false
            } catch SecretStoreError.notFound {
                password = ""
                databaseCredentialLoadFailed = false
            } catch {
                databaseCredentialLoadFailed = true
                connectionError = "The saved database password could not be loaded. Enter and save a replacement password. \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Build Connection Config

    private func buildConnection() -> DatabaseConnectionConfig {
        DatabaseConnectionConfig(
            id: editingConnection?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            engine: engine,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(port) ?? engine.defaultPort,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultDatabase: defaultDatabase.isEmpty ? nil : defaultDatabase.trimmingCharacters(in: .whitespacesAndNewlines),
            usesHostTunnel: engine.supportsNetworkTransport && usesHostTunnel,
            databaseCredentialPolicy: databaseCredentialPolicy,
            useTLS: engine.supportsTLS && useTLS,
            isFavorite: editingConnection?.isFavorite ?? false,
            colorTag: colorTag,
            dateAdded: editingConnection?.dateAdded ?? Date(),
            lastConnected: editingConnection?.lastConnected,
            tags: DatabaseConnectionLibraryProjection.normalizedTags(
                tagsText
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map(String.init)
            )
        )
    }

    // MARK: - Save

    private func save() {
        guard validateForAction() else { return }
        guard credentialMaterialIsReadyForSave else { return }
        let config = buildConnection()
        do {
            try onSave(config, engine.supportsCredentials ? password : "")
            stagedSQLiteURL = nil
            dismiss()
        } catch {
            connectionError = "The connection was not saved safely. \(error.localizedDescription)"
        }
    }

    private func saveAndConnect() {
        guard validateForAction() else { return }
        guard credentialMaterialIsReadyForSave else { return }
        let config = buildConnection()
        let connectionPassword: String
        do {
            connectionPassword = try passwordForExplicitConnection(using: config)
        } catch {
            connectionError = "Saved credentials are unavailable. Enter replacement credentials before connecting. \(error.localizedDescription)"
            return
        }
        do {
            try onSave(config, engine.supportsCredentials ? password : "")
            stagedSQLiteURL = nil
        } catch {
            connectionError = "The connection was not saved safely. \(error.localizedDescription)"
            return
        }

        isSavingAndConnecting = true
        saveAndConnectTask = Task {
            do {
                let sessionID = try await sessionManager.connect(
                    config: config,
                    password: connectionPassword,
                    openForward: openForward
                )
                if Task.isCancelled {
                    await sessionManager.disconnect(sessionID: sessionID)
                    return
                }
                // updateLastConnected handled by ConnectionManagerView's onSave
                isSavingAndConnecting = false
                saveAndConnectTask = nil
                dismiss()
                let request = DatabaseWorkspaceWindowRequest.primary(sessionID: sessionID)
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .phone {
                    iOSRouter.showWorkspace(request)
                    return
                }
                #endif
                openWindow(
                    id: "query-editor",
                    value: sessionManager.registerWorkspace(request)
                )
            } catch {
                guard !Task.isCancelled else { return }
                isSavingAndConnecting = false
                saveAndConnectTask = nil
                connectionError = "The connection was saved, but the database could not be reached. \(error.localizedDescription)"
            }
        }
    }

    private func cancelForm() {
        saveAndConnectTask?.cancel()
        saveAndConnectTask = nil
        isSavingAndConnecting = false
        dismiss()
    }

    private func validateForAction() -> Bool {
        attemptedSave = true
        guard !validationIssues.isEmpty else { return true }
        touchedFields.formUnion(validationIssues.keys)
        let order = orderedFormFields
        focusedField = order.first(where: { validationIssues[$0] != nil })
        return false
    }

    private var orderedFormFields: [FormField] {
        var fields: [FormField] = [.name]
        if engine != .sqlite {
            fields.append(contentsOf: [.host, .port, .username, .password, .defaultDatabase])
        }
        return fields
    }

    private func advanceFocus(after field: FormField) {
        guard let nextField = Self.nextField(after: field, in: orderedFormFields) else {
            // Return/Next only advances or dismisses field editing. Saving,
            // testing, and connecting always require an explicit button.
            focusedField = nil
            return
        }
        focusedField = nextField
    }

    private func markTouched(_ field: FormField) {
        touchedFields.insert(field)
        dbTestResult = nil
    }

    private func discardStagedSQLiteFile() {
        guard let stagedSQLiteURL else { return }
        do {
            try FileManager.default.removeItem(at: stagedSQLiteURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Already removed by a concurrent cleanup path.
        } catch {
            Logger.connections.error(
                "Failed to remove abandoned SQLite import: \(error.localizedDescription, privacy: .public)"
            )
        }
        self.stagedSQLiteURL = nil
    }

    private var credentialMaterialIsReadyForSave: Bool {
        if engine.supportsCredentials, databaseCredentialLoadFailed, password.isEmpty {
            connectionError = "Authenticate again or enter a replacement database password before changing this connection."
            return false
        }
        return true
    }

    private func passwordForExplicitConnection(
        using connection: DatabaseConnectionConfig
    ) throws -> String {
        guard connection.engine.supportsCredentials else { return "" }
        if !password.isEmpty || !isEditing { return password }
        do {
            return try KeychainManager.retrievePassword(for: connection)
        } catch SecretStoreError.notFound {
            return ""
        }
    }


    // MARK: - Test Actions


    private func testDB() {
        guard validateForAction() else { return }
        connectionError = nil
        let config = buildConnection()
        let connectionPassword: String
        do {
            connectionPassword = try passwordForExplicitConnection(using: config)
        } catch {
            connectionError = "Saved credentials are unavailable. Enter replacement credentials before testing. \(error.localizedDescription)"
            return
        }
        dbTestResult = .testing
        Task {
            do {
                try await sessionManager.testConnection(
                    config: config,
                    password: connectionPassword,
                    openForward: openForward
                )
                dbTestResult = .success
            } catch {
                let message = "Database connection test failed.\n\n\(error.localizedDescription)"
                dbTestResult = .failure(message)
            }
        }
    }

}

private extension View {
    @ViewBuilder
    func connectionPortKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func connectionPasswordFieldPresentation() -> some View {
        #if os(macOS)
        self
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
        #else
        self.multilineTextAlignment(.leading)
        #endif
    }

    @ViewBuilder
    func connectionFormSheetSize() -> some View {
        #if os(macOS)
        self.frame(
            minWidth: 600,
            idealWidth: 640,
            maxWidth: 680,
            minHeight: 620,
            idealHeight: 720,
            maxHeight: 820
        )
        #else
        self
        #endif
    }

    @ViewBuilder
    func connectionFormCancelShortcut() -> some View {
        #if os(macOS)
        self.keyboardShortcut(.cancelAction)
        #else
        self
        #endif
    }

    @ViewBuilder
    func connectionFormDefaultShortcut() -> some View {
        #if os(macOS)
        self.keyboardShortcut(.defaultAction)
        #else
        self
        #endif
    }

    @ViewBuilder
    func connectionFormConnectShortcut() -> some View {
        #if os(macOS)
        self.keyboardShortcut(.return, modifiers: [.command])
        #else
        self
        #endif
    }
}
