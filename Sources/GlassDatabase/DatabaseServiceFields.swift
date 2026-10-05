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
import GlassConnectionKit

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
            // Blank is a legitimate answer on a new service as well as an edit: `auth_socket`,
            // `trust`, and any user created without one.
            SecureField("Password", text: $draft.password,
                        prompt: Text(draft.isEditing ? "Leave blank to keep saved password" : "Optional"))
                .textContentType(.init(rawValue: ""))
                .focused($focusedField, equals: .password)
                .databaseTextFieldPresentation()
                .accessibilityIdentifier("\(identifierPrefix)-password")
        } label: {
            DatabaseRequiredFieldLabel(title: "Password", isRequired: false)
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
    @State private var showingCertificateImporter = false

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
                if draft.useTLS {
                    tlsVerificationRows
                } else if draft.sendsInTheClear {
                    Label("Not encrypted. Unless the database is on this device, its password and every query and result cross the network readable. Turn this on, or reach it through the Terminal service.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("\(identifierPrefix)-tls-off-warning")
                }
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
            .fileImporter(isPresented: $showingCertificateImporter,
                          allowedContentTypes: DatabaseCertificateImport.contentTypes,
                          allowsMultipleSelection: false) { result in
                draft.importCertificateFile(result)
            }
    }

    /// D13's user-facing half. Three named modes, each saying what it checks and what it does
    /// not, and a certificate to check against for the two that need one.
    ///
    /// **There is no automatic fallback here and there must never be one.** The app does not
    /// react to a failed handshake by verifying less; a user picks the weaker mode by name,
    /// having read what it gives up, or the connection stays broken.
    @ViewBuilder
    private var tlsVerificationRows: some View {
        observing(databaseLabeledContent("Verification") {
            Picker("Verification", selection: $draft.tlsVerification) {
                ForEach(DatabaseTLSVerification.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .databaseControlPresentation()
            .accessibilityIdentifier("\(identifierPrefix)-tls-verification")
        })

        Text(draft.tlsVerification.explanation)
            .font(.caption)
            .foregroundStyle(draft.tlsVerification.verifiesServerIdentity ? .secondary : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("\(identifierPrefix)-tls-verification-explanation")

        if draft.tlsVerification.requiresCertificate {
            LabeledContent {
                Text(draft.tlsCertificateFileName ?? "No certificate chosen")
                    .foregroundStyle(draft.tlsCertificate == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .accessibilityIdentifier("\(identifierPrefix)-tls-certificate")
            } label: {
                DatabaseRequiredFieldLabel(title: "Certificate", isRequired: true)
            }
            Button {
                showingCertificateImporter = true
            } label: {
                Label(draft.tlsCertificate == nil ? "Choose Certificate…" : "Choose Different Certificate…",
                      systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("\(identifierPrefix)-tls-certificate-choose")

            if let summary = draft.tlsCertificateSummary {
                // The fingerprint is here to be compared, not decoration: it is what the user
                // checks against the server, the way the terminal's host-key fingerprint is.
                Text(summary)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifierPrefix)-tls-certificate-summary")
            }
            DatabaseValidationMessage(message: draft.message(for: .tlsCertificate, in: issues),
                                      identifier: "\(identifierPrefix)-tls-certificate-validation")
            if let certificateImportError = draft.certificateImportError {
                DatabaseValidationMessage(message: certificateImportError,
                                          identifier: "\(identifierPrefix)-tls-certificate-import-error")
            }
        }
    }

    /// D7's whole replacement for glassdb's SSH Tunnel section: one switch. Everything a tunnel
    /// needs — the address, the credential, the host-key trust — already belongs to the
    /// machine's Terminal service, so there is nothing else to ask for.
    @ViewBuilder
    private var tunnelRow: some View {
        // A switch while the only tunnel is this machine's own; a picker once another machine's
        // Terminal service can carry it — a database on a private address reached from an app
        // server (2026-10-05).
        if draft.tunnelChoices.isEmpty {
            Toggle("Reach it through this machine's Terminal service", isOn: $draft.usesHostTunnel)
                .accessibilityIdentifier("\(identifierPrefix)-host-tunnel")
                // D14: settle the machine's fingerprint here, once, so connecting later just works.
                .onChange(of: draft.usesHostTunnel) { _, isOn in
                    guard isOn else { draft.hostTrustOutcome = nil; return }
                    Task { await draft.resolveHostTrustIfPossible() }
                }
        } else {
            Picker("Connect", selection: $draft.route) {
                Text("Directly").tag(DatabaseServiceDraft.Route.direct)
                Text("Through this machine's Terminal").tag(DatabaseServiceDraft.Route.thisMachine)
                ForEach(draft.tunnelChoices) { choice in
                    Text("Through \(choice.machineName)").tag(DatabaseServiceDraft.Route.through(choice.serviceID.rawValue))
                }
            }
            .accessibilityIdentifier("\(identifierPrefix)-host-tunnel-route")
            .onChange(of: draft.route) { _, route in
                guard route != .direct else { draft.hostTrustOutcome = nil; return }
                Task { await draft.resolveHostTrustIfPossible() }
            }
        }
        if draft.route == .thisMachine {
            // Where the database is, from this machine: blank for the machine itself, or a private
            // address it reaches — "I don't see where to provide the IP" (2026-10-05).
            LabeledContent("Database address") {
                TextField("Database address", text: $draft.tunnelTargetHost, prompt: Text("This machine"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .accessibilityIdentifier("\(identifierPrefix)-tunnel-target")
            }
            Text(draft.tunnelTargetHost.trimmingCharacters(in: .whitespaces).isEmpty
                 ? "Blank: the database is on this machine. For one on a private network this machine reaches, enter its address as this machine sees it."
                 : "This machine's Terminal service connects on to \(draft.tunnelTargetHost.trimmingCharacters(in: .whitespaces)):\(draft.port.isEmpty ? String(draft.engine.defaultPort) : draft.port) for you.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if draft.route == .thisMachine, draft.hostCanForwardPorts == false {
            // Said here rather than discovered at connect time. Not a validation error: the
            // machine may gain a Terminal service before this one is next opened.
            DatabaseValidationMessage(
                message: "This machine has no Terminal service to tunnel through yet. Add one, or turn this off to connect directly.",
                identifier: "\(identifierPrefix)-host-tunnel-warning")
        } else if let machine = draft.tunnelMachineName {
            // Where it ends, said with the address itself: the address is the machine's, typed
            // under Machine above, and the form never showed it — "I don't see where to provide
            // the IP" (2026-10-05).
            if draft.hostAddress.isEmpty {
                DatabaseValidationMessage(
                    message: "Enter the database server's private address under Machine › Address above. \(machine) connects to it there.",
                    identifier: "\(identifierPrefix)-host-tunnel-address")
            } else {
                Text("Connects to \(machine) over SSH, then to \(draft.hostAddress):\(draft.port.isEmpty ? String(draft.engine.defaultPort) : draft.port) from there. That is this machine's address, under Machine above, as \(machine) sees it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            hostTrustCaption
        } else if draft.usesHostTunnel, draft.tunnelServiceID != nil {
            DatabaseValidationMessage(
                message: "The machine this was reached through is no longer in the library. Choose how to reach it.",
                identifier: "\(identifierPrefix)-host-tunnel-gone")
        } else if draft.usesHostTunnel {
            hostTrustCaption
        } else {
            Text(draft.tunnelChoices.isEmpty
                 ? "For a database that only listens on the machine itself. The connection is forwarded over the machine's own SSH service."
                 : "Through a Terminal service: this machine's, for a database that only listens on the machine itself, or another machine's, for a database on a private network only it can reach.")
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
                    Label(draft.tunnelMachineName.map { "\($0)'s SSH host key is trusted." } ?? "This machine's SSH host key is trusted.",
                          systemImage: "checkmark.shield")
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
                              focus: $focusedField, prompt: "100") {}
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

private extension View {
    @ViewBuilder
    func databaseControlPresentation() -> some View {
        // A picker or toggle sits trailing in a form row on every Apple platform, and
        // sizes itself. The fixed 340 pt left-aligned box matched the text fields' old
        // override rather than the platform.
        self.labelsHidden()
    }
}
