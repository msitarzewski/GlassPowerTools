//
//  ServerFormViews.swift
//  glas.sh
//
//  Views for adding and editing server configurations
//

import SwiftUI
import GlasSecretStore
import GlassConnectionKit
import GlassShell
import os
import GlassLayers

extension View {
    @ViewBuilder
    func terminalTextInputDefaults() -> some View {
        #if canImport(UIKit)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func terminalNumericInput() -> some View {
        #if canImport(UIKit)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func terminalPlatformGlassBackground(cornerRadius: CGFloat) -> some View {
        #if os(visionOS)
        self.glassBackgroundEffect(in: .rect(cornerRadius: cornerRadius))
        #else
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

}

private let supportedAuthenticationMethods: [AuthenticationMethod] = [.password, .sshKey]

@ViewBuilder
private func serverFormLabeledContent<Content: View>(
    _ label: String,
    @ViewBuilder content: () -> Content
) -> some View {
    #if os(macOS)
    LabeledContent(label) {
        content()
    }
    #else
    content()
    #endif
}

private struct TerminalInitialSizeEditor: View {
    @Binding var usesAppDefault: Bool
    @Binding var columns: Int
    @Binding var rows: Int
    let appDefault: TerminalGeometry

    var body: some View {
        Toggle("Use App Default Size", isOn: $usesAppDefault)

        if usesAppDefault {
            LabeledContent(
                "Initial Size",
                value: "\(appDefault.columns) × \(appDefault.rows)"
            )
            .foregroundStyle(.secondary)
        } else {
            Stepper(
                value: $columns,
                in: TerminalGeometry.columnRange,
                step: 5
            ) {
                LabeledContent("Columns", value: "\(columns)")
            }
            Stepper(value: $rows, in: TerminalGeometry.rowRange) {
                LabeledContent("Rows", value: "\(rows)")
            }
        }

        Text("This is the fallback for a new PTY. The visible terminal's measured size takes precedence before the shell starts.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - The terminal's service draft

/// The shell's host, as the standalone server form sees it (a Tailscale import that already
/// knows the machine). The address is the machine's and lives on the host.
struct ServerFormHostContext {
    let hostName: String
    let address: String
}

/// Everything the terminal needs to create or update one saved server, and nothing the host
/// owns: no address, ever — the shell passes it in at commit time. The same draft backs the
/// shell's host sheet (required fields + Advanced) and glas.sh's standalone form, so the fields,
/// validation and persistence exist once.
@MainActor @Observable
final class TerminalServiceDraft: GlassServiceDraft {
    enum Field: String, Hashable, Sendable {
        case name, host, port, username, authentication, password, sshKey, terminalSize
    }

    struct ValidationInput {
        let name: String
        let host: String
        let port: String
        let username: String
        let authMethod: AuthenticationMethod
        let password: String
        let sshKeyID: UUID?
        let availableSSHKeyIDs: Set<UUID>
        let usesAppDefaultTerminalSize: Bool
        let initialTerminalColumns: Int
        let initialTerminalRows: Int
    }

    static let orderedFields: [Field] = [.name, .host, .port, .username, .authentication, .password, .sshKey, .terminalSize]

    let kind: HostServiceKind = .ssh
    /// The saved server being edited; nil for a new one.
    let editing: ServerConfiguration?
    /// Where an imported draft came from (Tailscale), carried through to the saved server.
    let provenance: ServerConnectionProvenance?
    let serverManager: ServerManager
    let settingsManager: SettingsManager

    /// Optional from the shell (a default is derived from the host); required standalone.
    var name: String
    /// Standalone form only. From the shell the host's address replaces it at commit.
    var host: String
    var port: String
    var username: String
    var authMethod: AuthenticationMethod
    var password = ""
    var sshKeyID: UUID?
    var colorTag: ServerColorTag
    var tags: [String]
    var isFavorite: Bool
    var allowLegacyAlgorithms: Bool
    var keepsSessionsInTmux: Bool
    /// What the last connection found (D44); nil before any. Read-only here.
    let tmuxAvailable: Bool?
    var jumpHostIDs: [UUID]
    var usesAppDefaultTerminalSize: Bool
    var initialTerminalColumns: Int
    var initialTerminalRows: Int

    var attemptedSave = false
    var touchedFields: Set<Field> = []
    var requiresPasswordUpgrade = false
    var saveError: String?
    /// Set by `focusFirstIssue`; the field views move focus and clear it.
    var focusRequest: Field?
    private var didLoadStoredPassword = false

    init(editing: ServerConfiguration? = nil, imported: ServerConfiguration? = nil,
         serverManager: ServerManager, settingsManager: SettingsManager) {
        self.editing = editing
        self.serverManager = serverManager
        self.settingsManager = settingsManager
        let source = editing ?? imported
        provenance = source?.provenance
        name = source?.name ?? ""
        host = source?.host ?? ""
        port = source.map { String($0.port) } ?? "22"
        username = source?.username ?? ""
        authMethod = source?.authMethod == .sshKey ? .sshKey : .password
        sshKeyID = source?.sshKeyID
        colorTag = source?.colorTag ?? .blue
        tags = source?.tags ?? []
        isFavorite = source?.isFavorite ?? false
        allowLegacyAlgorithms = source?.legacyAlgorithmsEnabled ?? false
        keepsSessionsInTmux = source?.keepsSessionsInTmux ?? false
        tmuxAvailable = source?.tmuxAvailable
        jumpHostIDs = source?.resolvedJumpHostIDs ?? []
        let hasTerminalSize = source?.initialTerminalColumns != nil && source?.initialTerminalRows != nil
        usesAppDefaultTerminalSize = !hasTerminalSize
        initialTerminalColumns = source?.initialTerminalColumns ?? TerminalGeometry.default.columns
        initialTerminalRows = source?.initialTerminalRows ?? TerminalGeometry.default.rows
        normalizeSelectedSSHKey()
        loadStoredPasswordIfNeeded()
    }

    var isEditing: Bool { editing != nil }

    // MARK: Validation

    static func normalizedEndpointValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    static func validationIssues(for input: ValidationInput, nameRequired: Bool = true) -> [Field: String] {
        var issues: [Field: String] = [:]
        if nameRequired, normalizedEndpointValue(input.name).isEmpty {
            issues[.name] = "Enter a name for this connection."
        }
        if normalizedEndpointValue(input.host).isEmpty {
            issues[.host] = "Enter the SSH server hostname or IP address."
        }
        if normalizedEndpointValue(input.username).isEmpty {
            issues[.username] = "Enter the SSH username."
        }
        if Int(input.port).map({ (1...65_535).contains($0) }) != true {
            issues[.port] = "Enter a port from 1 through 65535."
        }
        switch input.authMethod {
        case .password:
            if input.password.isEmpty { issues[.password] = "Enter the SSH password." }
        case .sshKey:
            if let sshKeyID = input.sshKeyID, input.availableSSHKeyIDs.contains(sshKeyID) { break }
            issues[.sshKey] = "Choose an SSH key that is available to Glass Power Tools."
        case .agent:
            issues[.authentication] = "Choose Password or SSH Key."
        }
        if !input.usesAppDefaultTerminalSize,
           !TerminalGeometry.contains(rows: input.initialTerminalRows, columns: input.initialTerminalColumns) {
            issues[.terminalSize] = "Choose terminal dimensions within 20 through 500 columns and 8 through 300 rows."
        }
        return issues
    }

    static func nextField(after field: Field, in authMethod: AuthenticationMethod) -> Field? {
        switch field {
        case .name: .host
        case .host: .port
        case .port: .username
        case .username: authMethod == .sshKey ? .sshKey : .password
        case .authentication, .password, .sshKey, .terminalSize: nil
        }
    }

    /// Issues for the standalone form (its own Host field and a required Name).
    var standaloneIssues: [Field: String] { issues(address: host, nameRequired: true) }

    /// Issues as the shell sees them: the address is the host's, the name is optional.
    func issues(address: String, nameRequired: Bool) -> [Field: String] {
        Self.validationIssues(for: ValidationInput(
            name: name, host: address, port: port, username: username, authMethod: authMethod,
            password: password, sshKeyID: sshKeyID, availableSSHKeyIDs: Set(settingsManager.sshKeys.map(\.id)),
            usesAppDefaultTerminalSize: usesAppDefaultTerminalSize,
            initialTerminalColumns: initialTerminalColumns, initialTerminalRows: initialTerminalRows), nameRequired: nameRequired)
    }

    /// The message a view shows for a field: only once the field was touched or a save tried.
    func message(for field: Field, in issues: [Field: String]) -> String? {
        guard attemptedSave || touchedFields.contains(field) else { return nil }
        return issues[field]
    }

    func markTouched(_ field: Field) { touchedFields.insert(field) }

    func revealIssuesAndFocus(_ issues: [Field: String]) {
        attemptedSave = true
        touchedFields.formUnion(issues.keys)
        guard let first = Self.orderedFields.first(where: { issues[$0] != nil }) else { return }
        switch first {
        case .name, .host, .port, .username, .password: focusRequest = first
        case .authentication, .sshKey, .terminalSize: focusRequest = nil
        }
    }

    // MARK: GlassServiceDraft

    func serviceDisplayName(hostName: String) -> String {
        let trimmed = Self.normalizedEndpointValue(name)
        return trimmed.isEmpty ? "Terminal on \(hostName)" : trimmed
    }

    func requiredFields() -> AnyView { AnyView(TerminalRequiredFields(draft: self)) }

    func advancedFields() -> AnyView { AnyView(TerminalAdvancedFields(draft: self, showsName: true)) }

    func validate(address: String) -> [GlassSetupIssue] {
        let issues = self.issues(address: address, nameRequired: false)
        return Self.orderedFields.compactMap { field in
            issues[field].map { GlassSetupIssue(field: field.rawValue, message: $0) }
        }
    }

    func focusFirstIssue(_ issues: [GlassSetupIssue]) {
        var byField: [Field: String] = [:]
        for issue in issues { if let field = Field(rawValue: issue.field) { byField[field] = issue.message } }
        revealIssuesAndFocus(byField)
    }

    func commit(endpointID: EndpointID, host: HostProfile, address: String) async throws {
        let issues = self.issues(address: address, nameRequired: false)
        guard issues.isEmpty else {
            revealIssuesAndFocus(issues)
            throw TerminalServiceDraftError.invalid(issues.values.sorted().joined(separator: " "))
        }
        try await persist(id: endpointID.rawValue, address: address, name: serviceDisplayName(hostName: host.displayName))
    }

    func rollback(endpointID: EndpointID) async {
        guard let server = serverManager.server(for: endpointID.rawValue) else { return }
        do { try await serverManager.deleteServer(server) } catch {
            Logger.servers.error("Rollback of \(endpointID.rawValue.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Persistence (shared by the shell's sheet and the standalone form)

    /// Saves the standalone form: its own Host field and required Name. Returns false with
    /// `saveError` set when the server could not be saved.
    func saveStandalone() async -> Bool {
        let issues = standaloneIssues
        guard issues.isEmpty else { revealIssuesAndFocus(issues); return false }
        let address = Self.normalizedEndpointValue(host)
        let name = Self.normalizedEndpointValue(name)

        // D27: a server made here becomes a machine in the library. An edit keeps the id it
        // already has — its host record exists — so only a new one is adopted.
        var discardAdoption: (@MainActor () async -> Void)?
        let id: UUID
        do {
            if let editing {
                id = editing.id
            } else {
                let adopted = try await serverManager.adoptedIdentity(
                    hostName: name.isEmpty ? address : name, address: address,
                    serviceName: serviceDisplayName(hostName: name.isEmpty ? address : name))
                id = adopted.id
                discardAdoption = adopted.discard
            }
        } catch {
            Logger.servers.error("Could not add the machine to the library: \(error.localizedDescription)")
            saveError = "The server was not added because its machine could not be created: \(error.localizedDescription)"
            return false
        }

        do {
            try await persist(id: id, address: address, name: name)
            return true
        } catch {
            // The machine was put in the library a moment ago and its service cannot be saved;
            // leaving the link behind would be exactly the orphan D25 exists to prevent.
            await discardAdoption?()
            Logger.servers.error("Failed to save server transactionally: \(error.localizedDescription)")
            saveError = isEditing ? "The server changes were not saved: \(error.localizedDescription)"
                                  : "The server was not added: \(error.localizedDescription)"
            return false
        }
    }

    /// Writes the server and its password through `ServerManager`'s transactional paths.
    private func persist(id: UUID, address: String, name: String) async throws {
        guard let parsedPort = Int(port) else { throw TerminalServiceDraftError.invalid("Enter a port from 1 through 65535.") }
        let normalizedUsername = Self.normalizedEndpointValue(username)
        if let original = editing {
            var updated = original
            updated.name = name
            updated.host = address
            updated.port = parsedPort
            updated.username = normalizedUsername
            updated.authMethod = authMethod
            updated.sshKeyID = authMethod == .sshKey ? sshKeyID : nil
            updated.sshKeyPath = nil
            updated.colorTag = colorTag
            updated.tags = tags
            updated.isFavorite = isFavorite
            updated.allowLegacyAlgorithms = allowLegacyAlgorithms
            updated.tmux = keepsSessionsInTmux
            updated.jumpHostID = jumpHostIDs.first
            updated.jumpHostIDs = jumpHostIDs.isEmpty ? nil : jumpHostIDs
            updated.initialTerminalColumns = usesAppDefaultTerminalSize ? nil : initialTerminalColumns
            updated.initialTerminalRows = usesAppDefaultTerminalSize ? nil : initialTerminalRows
            try await serverManager.updateServerOrThrow(updated, password: authMethod == .password ? password : nil)
            requiresPasswordUpgrade = false
        } else {
            var server = ServerConfiguration(
                id: id,   // the shell's endpoint id when created from the host sheet
                name: name,
                host: address,
                port: parsedPort,
                username: normalizedUsername,
                authMethod: authMethod,
                sshKeyPath: nil,
                sshKeyID: authMethod == .sshKey ? sshKeyID : nil,
                isFavorite: isFavorite,
                colorTag: colorTag,
                tags: tags,
                provenance: provenance,
                jumpHostID: jumpHostIDs.first,
                jumpHostIDs: jumpHostIDs.isEmpty ? nil : jumpHostIDs,
                initialTerminalColumns: usesAppDefaultTerminalSize ? nil : initialTerminalColumns,
                initialTerminalRows: usesAppDefaultTerminalSize ? nil : initialTerminalRows
            )
            server.allowLegacyAlgorithms = allowLegacyAlgorithms
            server.tmux = keepsSessionsInTmux
            try await serverManager.addServerOrThrow(server, password: authMethod == .password ? password : nil)
        }
    }

    /// The configuration this draft would save (for tests: draft → configuration → draft).
    func configuration(id: UUID, address: String, name: String) -> ServerConfiguration? {
        guard let parsedPort = Int(port) else { return nil }
        var server = ServerConfiguration(id: id, name: name, host: address, port: parsedPort,
                                         username: Self.normalizedEndpointValue(username), authMethod: authMethod,
                                         sshKeyPath: nil, sshKeyID: authMethod == .sshKey ? sshKeyID : nil,
                                         isFavorite: isFavorite, colorTag: colorTag, tags: tags, provenance: provenance,
                                         jumpHostID: jumpHostIDs.first, jumpHostIDs: jumpHostIDs.isEmpty ? nil : jumpHostIDs,
                                         initialTerminalColumns: usesAppDefaultTerminalSize ? nil : initialTerminalColumns,
                                         initialTerminalRows: usesAppDefaultTerminalSize ? nil : initialTerminalRows)
        server.allowLegacyAlgorithms = allowLegacyAlgorithms
        server.tmux = keepsSessionsInTmux
        return server
    }

    func loadStoredPasswordIfNeeded() {
        guard !didLoadStoredPassword, authMethod == .password, let server = editing else { return }
        didLoadStoredPassword = true
        do {
            password = try serverManager.password(for: server)
            requiresPasswordUpgrade = false
        } catch SecretStoreError.notFound {
            requiresPasswordUpgrade = true
        } catch {
            saveError = "The saved password could not be read: \(error.localizedDescription)"
        }
    }

    func normalizeSelectedSSHKey() {
        guard authMethod == .sshKey else { return }
        let availableIDs = Set(settingsManager.sshKeys.map(\.id))
        if let selected = sshKeyID, availableIDs.contains(selected) { return }
        sshKeyID = settingsManager.sshKeys.first?.id
    }

    var availableJumpHosts: [ServerConfiguration] {
        guard let editingID = editing?.id else { return serverManager.servers }
        return serverManager.servers.filter { $0.id != editingID }
    }
}

enum TerminalServiceDraftError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

// MARK: - Field views (shared by the shell's host sheet and the standalone form)

/// What a terminal cannot be created without: the user and how to authenticate. Rows for a
/// grouped `Form` section; the caller provides the section.
struct TerminalRequiredFields: View {
    @Bindable var draft: TerminalServiceDraft
    @FocusState private var focusedField: TerminalServiceDraft.Field?
    @State private var showingAddSSHKey = false

    private var issues: [TerminalServiceDraft.Field: String] { draft.issues(address: "-", nameRequired: false) }
    private var identifierPrefix: String { draft.isEditing ? "edit-server" : "add-server" }

    var body: some View {
        Group {
            TerminalFormTextField(label: "Username", text: $draft.username, field: .username,
                                  identifier: "\(identifierPrefix)-username", isRequired: true,
                                  message: draft.message(for: .username, in: issues), focus: $focusedField) {
                focusedField = TerminalServiceDraft.nextField(after: .username, in: draft.authMethod)
            }
            observing(serverFormLabeledContent("Method") {
                Picker("Method", selection: $draft.authMethod) {
                    ForEach(supportedAuthenticationMethods, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .serverFormControlPresentation()
                .accessibilityIdentifier("\(identifierPrefix)-auth-method")
            })
            TerminalValidationMessage(message: draft.message(for: .authentication, in: issues),
                                      identifier: "\(identifierPrefix)-authentication-validation")
            if draft.authMethod == .password {
                passwordField
                if draft.requiresPasswordUpgrade {
                    Label {
                        Text("Re-enter this password once to upgrade it. Earlier releases used an address-based Keychain account shared with the separate apps; the ambiguous credential is not imported.")
                    } icon: {
                        Image(systemName: "key.horizontal")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else if draft.authMethod == .sshKey {
                sshKeyEditor
            }
        }
    }

    /// Modifiers that must exist once: on the Method row, never on the `Group` (a modifier on a
    /// `Group` is applied to every row, which presented the key sheet from several places at once
    /// on iOS and never showed it).
    private func observing<V: View>(_ view: V) -> some View {
        view
            .onChange(of: draft.username) { _, _ in draft.markTouched(.username) }
            .onChange(of: draft.password) { _, _ in draft.markTouched(.password) }
            .onChange(of: draft.sshKeyID) { _, _ in draft.markTouched(.sshKey) }
            .onChange(of: draft.authMethod) { _, _ in
                draft.markTouched(.authentication)
                draft.markTouched(draft.authMethod == .sshKey ? .sshKey : .password)
                draft.normalizeSelectedSSHKey()
            }
            .onChange(of: draft.settingsManager.sshKeys.map(\.id)) { previous, current in
                // A key the user just added from this form is the one they mean: select it rather
                // than the catalog's first key.
                if draft.authMethod == .sshKey, let added = current.first(where: { !previous.contains($0) }) {
                    draft.sshKeyID = added
                }
                draft.normalizeSelectedSSHKey()
            }
            .onChange(of: draft.focusRequest) { _, request in
                guard let request, [.username, .password].contains(request) else { return }
                focusedField = request
                draft.focusRequest = nil
            }
    }

    @ViewBuilder
    private var passwordField: some View {
        LabeledContent {
            SecureField("Password", text: $draft.password)
                .textContentType(.init(rawValue: ""))
                .focused($focusedField, equals: .password)
                .serverFormTextFieldPresentation()
                .accessibilityIdentifier("\(identifierPrefix)-password")
        } label: {
            TerminalRequiredFieldLabel(title: "Password", isRequired: true)
        }
        TerminalValidationMessage(message: draft.message(for: .password, in: issues),
                                  identifier: "\(identifierPrefix)-password-validation")
    }

    @ViewBuilder
    private var sshKeyEditor: some View {
        #if os(macOS)
        // The label is plain text on purpose. `TerminalRequiredFieldLabel` folds its two texts
        // into one accessibility element with an explicit label; on a `LabeledContent` whose
        // content is not a single control (this text-and-button stack) that makes SwiftUI's
        // label resolution on macOS 27 recurse until the stack overflows (W4, 2026-09-10).
        LabeledContent {
            sshKeyEditorContent
                .serverFormControlPresentation()
        } label: {
            HStack(spacing: 6) {
                Text("SSH Key")
                Text("Required")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        #else
        VStack(alignment: .leading, spacing: 8) {
            TerminalRequiredFieldLabel(title: "SSH Key", isRequired: true)
            sshKeyEditorContent
        }
        #endif
    }

    private var sshKeyEditorContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft.settingsManager.sshKeys.isEmpty {
                Text("No SSH keys available. Add one to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("SSH Key", selection: $draft.sshKeyID) {
                    Text("Select a key").tag(nil as UUID?)
                    ForEach(draft.settingsManager.sshKeys) { key in
                        Text("\(key.name) (\(key.keyTypeBadge))").tag(key.id as UUID?)
                    }
                }
                .serverFormControlPresentation()
                .accessibilityIdentifier("\(identifierPrefix)-ssh-key")
            }
            TerminalValidationMessage(message: draft.message(for: .sshKey, in: issues),
                                      identifier: "\(identifierPrefix)-sshKey-validation")
            Button("Add SSH Key", systemImage: "plus.circle") { showingAddSSHKey = true }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showingAddSSHKey) {
                    // A sheet over this sheet on every platform: the macOS crash once blamed on
                    // nesting was the SSH Key row's accessibility label (W4, 2026-09-10).
                    AddSSHKeyView()
                        .environment(draft.settingsManager)
                }
        }
    }
}

/// Everything optional: the shell's "Advanced" disclosure and the standalone form's sections.
struct TerminalAdvancedFields: View {
    /// What the tmux setting needs, in the state the last connection left it.
    static func tmuxFootnote(available: Bool?) -> String {
        switch available {
        case true?: "Each terminal runs in its own tmux session on this host, so it keeps going when you disconnect, and you can pick it up from Active on any device."
        case false?: "tmux wasn't installed on this host when you last connected. Install it there, connect again, and this becomes available."
        case nil: "Connect to this host once and Glass Power Tools checks whether it has tmux."
        }
    }

    @Bindable var draft: TerminalServiceDraft
    /// The shell's sheet offers the service name here (optional, defaulted from the host); the
    /// standalone form has it up top as a required field.
    var showsName = true
    @FocusState private var focusedField: TerminalServiceDraft.Field?
    @State private var showingJumpHostPicker = false

    private var issues: [TerminalServiceDraft.Field: String] { draft.issues(address: "-", nameRequired: false) }
    private var identifierPrefix: String { draft.isEditing ? "edit-server" : "add-server" }

    var body: some View {
        Group {
            if showsName {
                TerminalFormTextField(label: "Name", text: $draft.name, field: .name,
                                      identifier: "\(identifierPrefix)-display-name", isRequired: false,
                                      message: nil, focus: $focusedField, prompt: "Terminal on this host") {}
            }
            observing(LabeledContent("Port") {
                TextField("Port", text: $draft.port)
                    .terminalNumericInput()
                    .focused($focusedField, equals: .port)
                    .serverFormTextFieldPresentation()
                    .accessibilityIdentifier("\(identifierPrefix)-port")
            })
            TerminalValidationMessage(message: draft.message(for: .port, in: issues),
                                      identifier: "\(identifierPrefix)-port-validation")
            Toggle("Allow Legacy SSH Algorithms", isOn: $draft.allowLegacyAlgorithms)
                .accessibilityIdentifier("\(identifierPrefix)-legacy-algorithms")
            // Persistent, not conditional: the July 2026 audit asked that this option never look
            // like a plain compatibility switch. It enables group-14 KEX and AES-128-CTR for this
            // host only (SSHConnectionOptions.allowLegacyAlgorithms); host-key policy is unaffected.
            Label {
                Text("Weakens the cryptography used to reach this host. Only for old servers that reject modern algorithms. Opening this connection asks you to confirm, and a Workgroup that includes it will not open.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.footnote)
            .foregroundStyle(draft.allowLegacyAlgorithms ? .orange : .secondary)
            .accessibilityIdentifier("\(identifierPrefix)-legacy-algorithms-warning")

            // D44: only offered where a connection has found tmux; always free to turn off.
            Toggle("Keep Sessions Running with tmux", isOn: $draft.keepsSessionsInTmux)
                .disabled(draft.tmuxAvailable != true && !draft.keepsSessionsInTmux)
                .accessibilityIdentifier("\(identifierPrefix)-tmux")
            Text(Self.tmuxFootnote(available: draft.tmuxAvailable))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(identifierPrefix)-tmux-note")

            #if os(macOS)
            serverFormLabeledContent("Route") { routingEditor.serverFormControlPresentation() }
            #else
            routingEditor
            #endif

            TerminalInitialSizeEditor(
                usesAppDefault: $draft.usesAppDefaultTerminalSize,
                columns: $draft.initialTerminalColumns,
                rows: $draft.initialTerminalRows,
                appDefault: TerminalGeometry(rows: draft.settingsManager.initialTerminalRows,
                                             columns: draft.settingsManager.initialTerminalColumns)
            )
            TerminalValidationMessage(message: draft.message(for: .terminalSize, in: issues),
                                      identifier: "\(identifierPrefix)-terminalSize-validation")

            #if os(macOS)
            serverFormLabeledContent("Color tag") { colorTagPicker.serverFormControlPresentation() }
            #else
            colorTagPicker
            #endif
        }
    }

    /// Once, on the Port row (see `TerminalRequiredFields.observing`).
    private func observing<V: View>(_ view: V) -> some View {
        view
            .onChange(of: draft.name) { _, _ in draft.markTouched(.name) }
            .onChange(of: draft.port) { _, _ in draft.markTouched(.port) }
            .onChange(of: draft.usesAppDefaultTerminalSize) { _, usesDefault in
                draft.markTouched(.terminalSize)
                guard !usesDefault else { return }
                draft.initialTerminalColumns = draft.settingsManager.initialTerminalColumns
                draft.initialTerminalRows = draft.settingsManager.initialTerminalRows
            }
            .onChange(of: draft.initialTerminalColumns) { _, _ in draft.markTouched(.terminalSize) }
            .onChange(of: draft.initialTerminalRows) { _, _ in draft.markTouched(.terminalSize) }
            .onChange(of: draft.focusRequest) { _, request in
                guard let request, [.name, .port].contains(request) else { return }
                focusedField = request
                draft.focusRequest = nil
            }
    }

    private var routingEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft.jumpHostIDs.isEmpty {
                Text("Direct connection").foregroundStyle(.secondary)
            } else {
                ForEach(Array(draft.jumpHostIDs.enumerated()), id: \.offset) { index, hopID in
                    if let hop = draft.serverManager.servers.first(where: { $0.id == hopID }) {
                        HStack {
                            Label("Hop \(index + 1): \(hop.name)", systemImage: "\(index + 1).circle.fill")
                            Spacer()
                            Button("Remove hop \(index + 1)", systemImage: "minus.circle.fill") {
                                draft.jumpHostIDs.remove(at: index)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }
                }
                .onMove { from, to in draft.jumpHostIDs.move(fromOffsets: from, toOffset: to) }
            }
            Button("Add Jump Host", systemImage: "plus.circle") { showingJumpHostPicker = true }
                .sheet(isPresented: $showingJumpHostPicker) {
                    JumpHostPickerView(servers: draft.availableJumpHosts, excludedIDs: Set(draft.jumpHostIDs)) { selectedID in
                        draft.jumpHostIDs.append(selectedID)
                    }
                }
        }
    }

    private var colorTagPicker: some View {
        Picker("Color tag", selection: $draft.colorTag) {
            ForEach(ServerColorTag.allCases, id: \.self) { tag in
                GlassColorTagRow(title: tag.rawValue.capitalized, color: tag.color)
                    .tag(tag)
            }
        }
    }
}

/// One labelled text row with its validation message.
struct TerminalFormTextField: View {
    let label: String
    @Binding var text: String
    let field: TerminalServiceDraft.Field
    let identifier: String
    let isRequired: Bool
    let message: String?
    var focus: FocusState<TerminalServiceDraft.Field?>.Binding
    var prompt: String? = nil
    let onSubmit: () -> Void

    @ViewBuilder
    var body: some View {
        LabeledContent {
            TextField(label, text: $text, prompt: prompt.map(Text.init))
                .terminalTextInputDefaults()
                .focused(focus, equals: field)
                .serverFormTextFieldPresentation()
                .accessibilityIdentifier(identifier)
                .onSubmit(onSubmit)
        } label: {
            TerminalRequiredFieldLabel(title: label, isRequired: isRequired)
        }
        TerminalValidationMessage(message: message, identifier: "\(identifier)-validation")
    }
}

/// Plain text on purpose: folding the two texts into one accessibility element with an explicit
/// label made SwiftUI's label resolution recurse on macOS 27 whenever the row's content was more
/// than one control (W4, 2026-09-10; seen again on 2026-09-11 in the host sheet).
struct TerminalRequiredFieldLabel: View {
    let title: String
    let isRequired: Bool

    var body: some View {
        if isRequired {
            HStack(spacing: 6) {
                Text(title)
                Text("Required")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text(title)
        }
    }
}

struct TerminalValidationMessage: View {
    let message: String?
    let identifier: String

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel("Error: \(message)")
        }
    }
}

// MARK: - Standalone form (glas.sh's own Add/Edit Server: Tailscale import, command palette)

struct AddServerView: View {
    @Bindable var serverManager: ServerManager
    private let draft: ServerConfiguration?

    init(serverManager: ServerManager, draft: ServerConfiguration? = nil) {
        self.serverManager = serverManager
        self.draft = draft
    }

    var body: some View {
        ServerFormView(mode: .add(draft), serverManager: serverManager)
    }
}

struct EditServerView: View {
    let server: ServerConfiguration
    @Bindable var serverManager: ServerManager
    var hostContext: ServerFormHostContext? = nil

    var body: some View {
        ServerFormView(mode: .edit(server), serverManager: serverManager, hostContext: hostContext)
    }
}

/// glas.sh's standalone server form, built from the same field views as the shell's host sheet.
/// It keeps its own Host field because nothing else defines the machine here.
struct ServerFormView: View {
    enum Mode {
        case add(ServerConfiguration?)
        case edit(ServerConfiguration)

        var isEditing: Bool { if case .edit = self { true } else { false } }
        var isImporting: Bool { if case .add(.some) = self { true } else { false } }
        var navigationTitle: String {
            if isEditing { return "Edit Connection" }
            return isImporting ? "Import Connection" : "Add Server"
        }
        var confirmationTitle: String {
            if isEditing { return "Save Changes" }
            return isImporting ? "Save Connection" : "Add Server"
        }
    }

    private let mode: Mode
    private let hostContext: ServerFormHostContext?
    private let serverManager: ServerManager
    @Environment(SettingsManager.self) private var settingsManager
    /// Built on first appearance from the environment's settings (the key catalog).
    @State private var draft: TerminalServiceDraft?
    @FocusState private var focusedField: TerminalServiceDraft.Field?
    @State private var newTag = ""
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, serverManager: ServerManager, hostContext: ServerFormHostContext? = nil) {
        self.mode = mode
        self.hostContext = hostContext
        self.serverManager = serverManager
    }

    private func makeDraft() -> TerminalServiceDraft {
        switch mode {
        case .add(let imported):
            TerminalServiceDraft(imported: imported, serverManager: serverManager, settingsManager: settingsManager)
        case .edit(let server):
            TerminalServiceDraft(editing: server, serverManager: serverManager, settingsManager: settingsManager)
        }
    }

    private var identifierPrefix: String { mode.isEditing ? "edit-server" : "add-server" }

    var body: some View {
        platformEditor
            .onAppear {
                if draft == nil { draft = makeDraft() }
                focusedField = mode.isImporting ? .username : .name
            }
    }

    @ViewBuilder
    private var platformEditor: some View {
        #if os(macOS)
        editor.frame(minWidth: 600, idealWidth: 640, maxWidth: 680, minHeight: 620, idealHeight: 720, maxHeight: 820)
        #else
        editor
        #endif
    }

    @ViewBuilder
    private var editor: some View {
        if let draft {
            ServerFormContent(mode: mode, hostContext: hostContext, draft: draft, focusedField: $focusedField,
                              newTag: $newTag, save: save)
        } else {
            ProgressView()
        }
    }

    private func save() {
        guard let draft else { return }
        commitPendingTag()
        if let hostContext { draft.host = hostContext.address }
        // `saveStandalone` reports its own failures through `draft.saveError`, so the only thing
        // that changes by awaiting it here is that the dismissal happens once the catalog write
        // has actually landed rather than before it.
        Task { @MainActor in
            if await draft.saveStandalone() { dismiss() }
        }
    }

    private func commitPendingTag() {
        guard let draft else { return }
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { newTag = ""; return }
        if !draft.tags.contains(trimmed) { draft.tags.append(trimmed) }
        newTag = ""
    }
}

/// The standalone form's body, once the draft exists.
private struct ServerFormContent: View {
    let mode: ServerFormView.Mode
    let hostContext: ServerFormHostContext?
    @Bindable var draft: TerminalServiceDraft
    var focusedField: FocusState<TerminalServiceDraft.Field?>.Binding
    @Binding var newTag: String
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var identifierPrefix: String { mode.isEditing ? "edit-server" : "add-server" }
    private var issues: [TerminalServiceDraft.Field: String] { draft.standaloneIssues }

    private var navigationTitle: String {
        if let hostContext {
            return mode.isEditing ? "Edit Terminal on \(hostContext.hostName)" : "Add Terminal to \(hostContext.hostName)"
        }
        return mode.navigationTitle
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TerminalFormTextField(label: "Name", text: $draft.name, field: .name,
                                          identifier: "\(identifierPrefix)-display-name", isRequired: true,
                                          message: draft.message(for: .name, in: issues), focus: focusedField) {
                        focusedField.wrappedValue = .host
                    }
                    if let hostContext {
                        LabeledContent("Address") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(hostContext.address).textSelection(.enabled)
                                    .accessibilityIdentifier("\(identifierPrefix)-host")
                                    .accessibilityValue(hostContext.address)
                                Text("From the host \(hostContext.hostName)").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .accessibilityElement(children: .contain)
                    } else {
                        TerminalFormTextField(label: "Host", text: $draft.host, field: .host,
                                              identifier: "\(identifierPrefix)-host", isRequired: true,
                                              message: draft.message(for: .host, in: issues), focus: focusedField) {
                            focusedField.wrappedValue = .port
                        }
                    }
                    TerminalRequiredFields(draft: draft)
                }
                Section("Advanced") {
                    TerminalAdvancedFields(draft: draft, showsName: false)
                }
                Section("Preferences") {
                    #if os(macOS)
                    serverFormLabeledContent("Collections") { collectionEditor.serverFormControlPresentation() }
                    #else
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags").font(.headline)
                        collectionEditor
                    }
                    #endif
                    Toggle("Favorite", systemImage: "heart.fill", isOn: $draft.isFavorite)
                        .accessibilityIdentifier("\(identifierPrefix)-favorite")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.confirmationTitle) { save() }
                        .disabled(!issues.isEmpty)
                        // Return saves the sheet wherever there is a keyboard to press it on.
                        .keyboardShortcut(.defaultAction)
                }
            }
            .alert("Save Failed", isPresented: Binding(
                get: { draft.saveError != nil },
                set: { if !$0 { draft.saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(draft.saveError ?? "The server could not be saved.")
            }
            .onChange(of: draft.host) { _, _ in draft.markTouched(.host) }
            .onChange(of: draft.focusRequest) { _, request in
                guard let request, request == .host else { return }
                focusedField.wrappedValue = .host
                draft.focusRequest = nil
            }
        }
    }

    private var collectionEditor: some View {
        FlowLayout(spacing: 8) {
            ForEach(draft.tags, id: \.self) { tag in
                TagChip(tag: tag) { draft.tags.removeAll { $0 == tag } }
            }
            HStack(spacing: 4) {
                TextField("Add collection", text: $newTag)
                    .textFieldStyle(.plain)
                    .frame(width: 110)
                    .accessibilityIdentifier("\(identifierPrefix)-tag")
                    .onSubmit { commitPendingTag() }
                if !newTag.isEmpty {
                    Button("Add collection", systemImage: "plus.circle.fill") { commitPendingTag() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add collection")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
        }
    }

    private func commitPendingTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { newTag = ""; return }
        if !draft.tags.contains(trimmed) { draft.tags.append(trimmed) }
        newTag = ""
    }
}

extension View {
    @ViewBuilder
    func serverFormControlPresentation() -> some View {
        // A picker or toggle sits trailing in a form row on every Apple platform, and
        // sizes itself. The fixed 340 pt left-aligned box matched the text fields' old
        // override rather than the platform.
        self.labelsHidden()
    }

    @ViewBuilder
    func serverFormTextFieldPresentation() -> some View {
        // Native: the label leads, the value sits trailing, and the field takes the
        // width the form gives it. The previous fixed `.frame(width: 340, alignment:
        // .leading)` with `.roundedBorder` was a macOS-only override that neither macOS
        // nor any other platform lays a form out like, and on a narrow sheet it forced
        // the content wider than its container. Kept: the Required badge and the
        // validation message, which are behaviour rather than styling.
        self
            .labelsHidden()
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - Supporting Views

struct TagChip: View {
    let tag: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .accessibilityLabel("Remove \(tag)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag: \(tag)")
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                    y: bounds.minY + result.frames[index].minY),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + lineHeight)
        }
    }
}

// MARK: - Jump Host Picker

struct JumpHostPickerView: View {
    let servers: [ServerConfiguration]
    let excludedIDs: Set<UUID>
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    private var availableServers: [ServerConfiguration] {
        servers.filter { !excludedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableServers.isEmpty {
                    Text("No available servers to add as a jump host.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableServers) { server in
                        Button {
                            onSelect(server.id)
                            dismiss()
                        } label: {
                            HStack {
                                Circle()
                                    .fill(server.colorTag.color)
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading) {
                                    Text(server.name)
                                    Text("\(server.username)@\(server.host):\(server.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Jump Host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
