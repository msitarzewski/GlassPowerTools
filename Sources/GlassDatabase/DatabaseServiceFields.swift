//
//  DatabaseServiceFields.swift
//  Glass Power Tools — GlassDatabase
//
//  The rows the database contributes to the shell's setup sheet. Shaped and laid out to match
//  `Sources/GlassTerminal/ServerFormViews.swift:431-780` so the two tabs of one sheet look and
//  behave like one sheet: the same required-label treatment, the same validation message row,
//  the same macOS 340-point control column, the same `focusRequest` handoff.
//
//  Field bodies are glassdb's (`../glassdb/glassdb/ConnectionFormView.swift`), rebound from the
//  form's `@State` onto the draft.
//

import SwiftUI
import GlassLayers
import GlassShell

// MARK: - Required

/// What a database service cannot be created without: which engine, which database, and the
/// account to open it with. Rows for a grouped `Form` section; the caller provides the section.
struct DatabaseRequiredFields: View {
    @Bindable var draft: DatabaseServiceDraft
    @FocusState private var focusedField: DatabaseServiceDraft.Field?
    @State private var showingSQLiteImporter = false

    /// The address is the host's and the sheet validates it separately, so the placeholder here
    /// only has to be non-empty for the rows this view owns.
    private var issues: [DatabaseServiceDraft.Field: String] { draft.issues(address: "-") }
    private var identifierPrefix: String { draft.isEditing ? "edit-database" : "add-database" }

    var body: some View {
        Group {
            observing(databaseLabeledContent("Engine") {
                Picker("Engine", selection: $draft.engine) {
                    ForEach(DatabaseEngineType.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .databaseControlPresentation()
                .accessibilityIdentifier("\(identifierPrefix)-engine")
            })

            if draft.engine == .sqlite {
                sqliteFileRow
            } else {
                // Optional: connecting without naming one opens the server, and the browser
                // lists what is there. Only SQLite must name its file.
                DatabaseFormTextField(label: "Database", text: $draft.database, field: .database,
                                      identifier: "\(identifierPrefix)-database", isRequired: false,
                                      message: draft.message(for: .database, in: issues),
                                      focus: $focusedField, prompt: "Optional — all databases if blank") {
                    focusedField = .username
                }
                DatabaseFormTextField(label: "Username", text: $draft.username, field: .username,
                                      identifier: "\(identifierPrefix)-username", isRequired: true,
                                      message: draft.message(for: .username, in: issues),
                                      focus: $focusedField, prompt: draft.engine.defaultUsername) {
                    focusedField = .password
                }
                passwordField
            }
        }
    }

    /// Modifiers that must exist once, on a single row rather than on the `Group` — a modifier
    /// on a `Group` is applied to every row (W4's finding, and the reason the terminal's own
    /// fields do the same).
    private func observing<V: View>(_ view: V) -> some View {
        view
            .onChange(of: draft.engine) { _, newEngine in
                draft.markTouched(.engine)
                draft.engineDidChange(to: newEngine)
            }
            .onChange(of: draft.database) { _, _ in draft.markTouched(.database) }
            .onChange(of: draft.username) { _, _ in draft.markTouched(.username) }
            .onChange(of: draft.password) { _, _ in draft.markTouched(.password) }
            .onChange(of: draft.focusRequest) { _, request in
                guard let request, [.database, .username, .password].contains(request) else { return }
                focusedField = request
                draft.focusRequest = nil
            }
            .fileImporter(isPresented: $showingSQLiteImporter,
                          allowedContentTypes: DatabaseServiceDraft.sqliteContentTypes,
                          allowsMultipleSelection: false) { result in
                draft.importSQLiteFile(result)
            }
    }

    @ViewBuilder
    private var sqliteFileRow: some View {
        LabeledContent {
            Text(draft.sqlitePath.isEmpty
                 ? "No file selected"
                 : URL(fileURLWithPath: draft.sqlitePath).lastPathComponent)
                .foregroundStyle(draft.sqlitePath.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .accessibilityIdentifier("\(identifierPrefix)-sqlite-file")
        } label: {
            DatabaseRequiredFieldLabel(title: "Database File", isRequired: true)
        }
        Button {
            showingSQLiteImporter = true
        } label: {
            Label(draft.sqlitePath.isEmpty ? "Choose SQLite File" : "Choose Different File", systemImage: "folder")
        }
        .accessibilityIdentifier("\(identifierPrefix)-sqlite-choose")
        DatabaseValidationMessage(message: draft.message(for: .databaseFile, in: issues),
                                  identifier: "\(identifierPrefix)-sqlite-file-validation")
        if let importError = draft.importError {
            DatabaseValidationMessage(message: importError, identifier: "\(identifierPrefix)-sqlite-import-error")
        }
        Text("A private working copy of the selected file is imported. The original is left unchanged.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var passwordField: some View {
        LabeledContent {
            SecureField("Password", text: $draft.password,
                        prompt: Text(draft.isEditing ? "Leave blank to keep saved password" : "Password"))
                .textContentType(.init(rawValue: ""))
                .focused($focusedField, equals: .password)
                .databaseTextFieldPresentation()
                .accessibilityIdentifier("\(identifierPrefix)-password")
        } label: {
            DatabaseRequiredFieldLabel(title: "Password", isRequired: !draft.isEditing)
        }
        DatabaseValidationMessage(message: draft.message(for: .password, in: issues),
                                  identifier: "\(identifierPrefix)-password-validation")
    }
}

// MARK: - Advanced

/// Everything optional, shown under the sheet's Advanced disclosure. No SSH section: the host's
/// Terminal service owns the tunnel (D7), so the only thing to decide here is whether to use it.
struct DatabaseAdvancedFields: View {
    @Bindable var draft: DatabaseServiceDraft
    @FocusState private var focusedField: DatabaseServiceDraft.Field?

    private var issues: [DatabaseServiceDraft.Field: String] { draft.issues(address: "-") }
    private var identifierPrefix: String { draft.isEditing ? "edit-database" : "add-database" }

    var body: some View {
        Group {
            DatabaseFormTextField(label: "Name", text: $draft.name, field: .name,
                                  identifier: "\(identifierPrefix)-name", isRequired: false,
                                  message: draft.message(for: .name, in: issues),
                                  focus: $focusedField, prompt: "Optional") {}

            if draft.engine.supportsNetworkTransport {
                observing(DatabaseFormTextField(label: "Port", text: $draft.port, field: .port,
                                                identifier: "\(identifierPrefix)-port", isRequired: false,
                                                message: draft.message(for: .port, in: issues),
                                                focus: $focusedField,
                                                prompt: String(draft.engine.defaultPort)) {})
                tunnelRow
            }
            if draft.engine.supportsTLS {
                Toggle("Encrypt the database connection", isOn: $draft.useTLS)
                    .accessibilityIdentifier("\(identifierPrefix)-tls")
            }

            readOnlyRow
            rowPageSizeRow

            databaseLabeledContent("Color tag") {
                Picker("Color tag", selection: $draft.colorTag) {
                    ForEach(ConnectionColorTag.allCases, id: \.self) { tag in
                        GlassColorTagRow(title: tag.displayName,
                                         color: tag == .none ? nil : tag.color)
                            .tag(tag)
                    }
                }
                .databaseControlPresentation()
                .accessibilityIdentifier("\(identifierPrefix)-color-tag")
            }
        }
    }

    private func observing<V: View>(_ view: V) -> some View {
        view
            .onChange(of: draft.port) { _, _ in draft.markTouched(.port) }
            .onChange(of: draft.rowPageSize) { _, _ in draft.markTouched(.rowPageSize) }
            .onChange(of: draft.focusRequest) { _, request in
                guard let request, [.name, .port, .rowPageSize].contains(request) else { return }
                focusedField = request
                draft.focusRequest = nil
            }
    }

    /// D7's whole replacement for glassdb's SSH Tunnel section: one switch. Everything a tunnel
    /// needs — the address, the credential, the host-key trust — already belongs to the
    /// machine's Terminal service, so there is nothing else to ask for.
    @ViewBuilder
    private var tunnelRow: some View {
        Toggle("Reach it through this machine's Terminal service", isOn: $draft.usesHostTunnel)
            .accessibilityIdentifier("\(identifierPrefix)-host-tunnel")
            // D14: settle the machine's fingerprint here, once, so connecting later just works.
            .onChange(of: draft.usesHostTunnel) { _, isOn in
                guard isOn else { draft.hostTrustOutcome = nil; return }
                Task { await draft.resolveHostTrustIfPossible() }
            }
        if draft.usesHostTunnel, draft.hostCanForwardPorts == false {
            // Said here rather than discovered at connect time. Not a validation error: the
            // machine may gain a Terminal service before this one is next opened.
            DatabaseValidationMessage(
                message: "This machine has no Terminal service to tunnel through yet. Add one, or turn this off to connect directly.",
                identifier: "\(identifierPrefix)-host-tunnel-warning")
        } else if draft.usesHostTunnel {
            hostTrustCaption
        } else {
            Text("For a database that only listens on the machine itself. The connection is forwarded over the machine's own SSH service.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the trust resolution said. None of these block Save — the service is saveable in
    /// every case, and an unsettled fingerprint is simply settled at first connect instead.
    @ViewBuilder
    private var hostTrustCaption: some View {
        Group {
            if draft.isResolvingHostTrust {
                Text("Checking this machine's SSH host key…")
            } else {
                switch draft.hostTrustOutcome {
                case .trusted:
                    Label("This machine's SSH host key is trusted.", systemImage: "checkmark.shield")
                case .declined:
                    Text("The host key was not trusted, so the tunnel will not open. You will be asked again the first time you connect.")
                case .unavailable, nil:
                    Text("The host key is checked the first time you connect, where you can review its fingerprint.")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("\(identifierPrefix)-host-trust-status")
    }

    @ViewBuilder
    private var readOnlyRow: some View {
        Toggle("Read-only", isOn: $draft.isReadOnly)
            .accessibilityIdentifier("\(identifierPrefix)-read-only")
        if draft.isReadOnly {
            Text("Every statement that is not a read is refused before it is sent, including from the grid, the record editor and the schema tools.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var rowPageSizeRow: some View {
        DatabaseFormTextField(label: "Rows per page", text: $draft.rowPageSize, field: .rowPageSize,
                              identifier: "\(identifierPrefix)-row-page-size", isRequired: false,
                              message: draft.message(for: .rowPageSize, in: issues),
                              focus: $focusedField, prompt: "App setting") {}
    }
}

// MARK: - Shared row views

/// One labelled text row with its validation message.
struct DatabaseFormTextField: View {
    let label: String
    @Binding var text: String
    let field: DatabaseServiceDraft.Field
    let identifier: String
    let isRequired: Bool
    let message: String?
    var focus: FocusState<DatabaseServiceDraft.Field?>.Binding
    var prompt: String? = nil
    let onSubmit: () -> Void

    @ViewBuilder
    var body: some View {
        LabeledContent {
            TextField(label, text: $text, prompt: prompt.map(Text.init))
                .databaseTextInputDefaults()
                .focused(focus, equals: field)
                .databaseTextFieldPresentation()
                .accessibilityIdentifier(identifier)
                .onSubmit(onSubmit)
        } label: {
            DatabaseRequiredFieldLabel(title: label, isRequired: isRequired)
        }
        DatabaseValidationMessage(message: message, identifier: "\(identifier)-validation")
    }
}

/// Plain text on purpose — see `TerminalRequiredFieldLabel`: folding the two texts into one
/// accessibility element with an explicit label made SwiftUI's label resolution recurse on
/// macOS 27 whenever a row's content was more than one control.
struct DatabaseRequiredFieldLabel: View {
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

struct DatabaseValidationMessage: View {
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

@ViewBuilder
func databaseLabeledContent<Content: View>(
    _ label: String,
    @ViewBuilder content: () -> Content
) -> some View {
    #if os(macOS)
    LabeledContent(label) { content() }
    #else
    content()
    #endif
}

private extension View {
    @ViewBuilder
    func databaseTextInputDefaults() -> some View {
        #if canImport(UIKit)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }

    @ViewBuilder
    func databaseTextFieldPresentation() -> some View {
        #if os(macOS)
        self
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 340, alignment: .leading)
        #else
        self
        #endif
    }
}

private extension View {
    @ViewBuilder
    func databaseControlPresentation() -> some View {
        #if os(macOS)
        self
            .labelsHidden()
            .frame(width: 340, alignment: .leading)
        #else
        self
        #endif
    }
}
