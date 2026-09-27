//
//  DesktopServiceFields.swift
//  Glass Power Tools — GlassDesktop
//
//  The rows the desktop contributes to the shell's setup sheet. Laid out to match
//  `Sources/GlassDatabase/DatabaseServiceFields.swift` — which matches the terminal's — so every
//  tab of one sheet looks and behaves like one sheet: the same Required treatment, the same
//  validation message row, the same native trailing controls, the same `focusRequest` handoff.
//
//  Field bodies are glassDT's (`ConnectionEditor.swift`), rebound from the editor's own `@State`
//  onto the draft.
//

import SwiftUI
import GlassShell
import GlasSecretStore

// MARK: - Required

/// What a desktop cannot be created without: which protocol, and the account to sign in with.
/// A VNC server may be password-only, so the account row is required for RDP alone.
struct DesktopRequiredFields: View {
    @Bindable var draft: DesktopServiceDraft
    @FocusState private var focusedField: DesktopServiceDraft.Field?

    /// The address is the host's and the sheet validates it separately, so a non-empty
    /// placeholder is enough for the rows this view owns.
    private var issues: [DesktopServiceDraft.Field: String] { draft.issues(address: "-") }
    private var identifierPrefix: String { draft.editing == nil ? "add-desktop" : "edit-desktop" }

    var body: some View {
        Group {
            observing(desktopLabeledContent("Protocol") {
                Picker("Protocol", selection: $draft.desktopProtocol) {
                    ForEach(DesktopProtocol.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .desktopControlPresentation()
                .accessibilityIdentifier("\(identifierPrefix)-protocol")
                .onChange(of: draft.desktopProtocol) { _, _ in draft.protocolDidChange() }
            })
            if draft.desktopProtocol == .vnc {
                // Said where the choice is made: the RFB security types this client speaks protect
                // the password at sign-in and nothing after it.
                Label("VNC protects the password at sign-in, not what follows: the screen and your typing cross the network readable. Use it on a network you trust.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifierPrefix)-vnc-unencrypted")
            }

            DesktopFormTextField(
                // glassDT's own wording: a Mac being screen-shared takes a Mac account, and
                // calling it "Username" there sent people looking for something that does not exist.
                label: draft.showsRDPOnlyFields ? "Username" : "Mac user name",
                text: $draft.username, field: .username,
                identifier: "\(identifierPrefix)-username",
                isRequired: draft.showsRDPOnlyFields,
                message: draft.message(for: .username, in: issues),
                focus: $focusedField,
                prompt: draft.showsRDPOnlyFields ? nil : "Optional — blank for a password-only server"
            ) { focusedField = .password }

            LabeledContent {
                SecureField("Password", text: $draft.password)
                    .focused($focusedField, equals: .password)
                    .desktopTextFieldPresentation()
                    .accessibilityIdentifier("\(identifierPrefix)-password")
            } label: {
                DesktopRequiredFieldLabel(title: "Password", isRequired: draft.editing == nil)
            }
            DesktopValidationMessage(message: draft.message(for: .password, in: issues),
                                     identifier: "\(identifierPrefix)-password-validation")
        }
        .onChange(of: draft.focusRequest) { _, request in
            guard let request else { return }
            focusedField = request
            draft.focusRequest = nil
        }
    }

    /// Marks a field touched once the user leaves it, so a message appears when they have had a
    /// chance to fill it in rather than the moment the sheet opens.
    private func observing<V: View>(_ view: V) -> some View { view }
}

// MARK: - Advanced

/// Everything optional. The RDP-only rows are *hidden* for VNC rather than disabled: a Windows
/// domain and an NLA choice have no meaning in RFB, and a dead control is worse than no control.
struct DesktopAdvancedFields: View {
    @Bindable var draft: DesktopServiceDraft
    @FocusState private var focusedField: DesktopServiceDraft.Field?

    private var issues: [DesktopServiceDraft.Field: String] { draft.issues(address: "-") }
    private var identifierPrefix: String { draft.editing == nil ? "add-desktop" : "edit-desktop" }

    var body: some View {
        Group {
            DesktopFormTextField(label: "Name", text: $draft.name, field: .name,
                                 identifier: "\(identifierPrefix)-name", isRequired: false,
                                 message: draft.message(for: .name, in: issues),
                                 focus: $focusedField,
                                 prompt: "Optional — the machine's name if blank") {
                focusedField = .port
            }

            DesktopFormTextField(label: "Port", text: $draft.portText, field: .port,
                                 identifier: "\(identifierPrefix)-port", isRequired: false,
                                 message: draft.message(for: .port, in: issues),
                                 focus: $focusedField,
                                 prompt: "\(draft.desktopProtocol.defaultPort)") {
                focusedField = nil
            }

            if draft.showsRDPOnlyFields {
                DesktopFormTextField(label: "Domain", text: $draft.domain, field: .domain,
                                     identifier: "\(identifierPrefix)-domain", isRequired: false,
                                     message: draft.message(for: .domain, in: issues),
                                     focus: $focusedField, prompt: "Optional") {
                    focusedField = nil
                }

                desktopLabeledContent("Authentication") {
                    Picker("Authentication", selection: $draft.authentication) {
                        Text("Network Level (NLA)").tag(DesktopAuthentication.networkLevel)
                        Text("Allow TLS fallback").tag(DesktopAuthentication.tls)
                    }
                    .desktopControlPresentation()
                    .accessibilityIdentifier("\(identifierPrefix)-authentication")
                }
            }

            desktopLabeledContent("Desktop size") {
                HStack(spacing: 6) {
                    TextField("Width", text: $draft.desktopWidthText)
                        .focused($focusedField, equals: .desktopWidth)
                        .desktopTextFieldPresentation()
                        .accessibilityIdentifier("\(identifierPrefix)-desktop-width")
                    Text("×").foregroundStyle(.secondary)
                    TextField("Height", text: $draft.desktopHeightText)
                        .focused($focusedField, equals: .desktopHeight)
                        .desktopTextFieldPresentation()
                        .accessibilityIdentifier("\(identifierPrefix)-desktop-height")
                }
            }
            DesktopValidationMessage(message: draft.message(for: .desktopWidth, in: issues),
                                     identifier: "\(identifierPrefix)-desktop-validation")

            // VNC has no audio channel, so the toggle is not offered for it.
            Toggle("Share clipboard text", isOn: $draft.clipboardEnabled)
                .accessibilityIdentifier("\(identifierPrefix)-clipboard")
            if draft.showsRDPOnlyFields {
                Toggle("Remote audio", isOn: $draft.audioEnabled)
                    .accessibilityIdentifier("\(identifierPrefix)-audio")
            }

            desktopLabeledContent("Credential storage") {
                Picker("Credential storage", selection: $draft.mobility) {
                    Text("iCloud Keychain").tag(SecretMobilityPolicy.iCloudKeychain)
                    Text("This device only").tag(SecretMobilityPolicy.deviceOnly)
                }
                .desktopControlPresentation()
                .accessibilityIdentifier("\(identifierPrefix)-mobility")
            }
        }
    }
}

// MARK: - Shared rows

struct DesktopFormTextField: View {
    let label: String
    @Binding var text: String
    let field: DesktopServiceDraft.Field
    let identifier: String
    let isRequired: Bool
    let message: String?
    var focus: FocusState<DesktopServiceDraft.Field?>.Binding
    var prompt: String? = nil
    let onSubmit: () -> Void

    @ViewBuilder
    var body: some View {
        LabeledContent {
            TextField(label, text: $text, prompt: prompt.map(Text.init))
                .desktopTextInputDefaults()
                .focused(focus, equals: field)
                .desktopTextFieldPresentation()
                .accessibilityIdentifier(identifier)
                .onSubmit(onSubmit)
        } label: {
            DesktopRequiredFieldLabel(title: label, isRequired: isRequired)
        }
        DesktopValidationMessage(message: message, identifier: "\(identifier)-validation")
    }
}

/// Plain text on purpose — see `DatabaseRequiredFieldLabel`: folding the two texts into one
/// accessibility element made SwiftUI's label resolution recurse on macOS 27 whenever a row held
/// more than one control.
struct DesktopRequiredFieldLabel: View {
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

struct DesktopValidationMessage: View {
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
func desktopLabeledContent<Content: View>(
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
    func desktopTextInputDefaults() -> some View {
        #if canImport(UIKit)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }

    /// Native: the label leads, the value sits trailing, and the field takes the width the form
    /// gives it. No fixed 340-point column — that was a macOS-only override that overflowed a
    /// narrow sheet.
    @ViewBuilder
    func desktopTextFieldPresentation() -> some View {
        self
            .labelsHidden()
            .multilineTextAlignment(.trailing)
    }

    @ViewBuilder
    func desktopControlPresentation() -> some View {
        self.labelsHidden()
    }
}
