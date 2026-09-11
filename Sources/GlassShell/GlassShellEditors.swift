import SwiftUI
import GlassConnectionKit
import GlassConnectionUI

/// Add or edit a host: name, address, aliases and collection tags. The address is the machine's
/// network identity (DNS name or IP), entered here once and inherited by every service; ports,
/// usernames and credentials stay with the capability that owns each service. Aliases and
/// collections are token fields: collections draw their suggestions from the library's
/// system-wide tag vocabulary.
public struct GlassShellHostEditor: View {
    private let model: GlassShellModel
    private let host: GlassShellHost?
    private let onSave: (HostID) -> Void
    @State private var displayName: String
    @State private var address: String
    @State private var aliases: [String]
    @State private var tags: [String]
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    public init(model: GlassShellModel, host: GlassShellHost?, onSave: @escaping (HostID) -> Void) {
        self.model = model
        self.host = host
        self.onSave = onSave
        _displayName = State(initialValue: host?.displayName ?? "")
        _address = State(initialValue: host?.address ?? "")
        _aliases = State(initialValue: GlassTagList.normalized(host?.aliases ?? []))
        _tags = State(initialValue: GlassTagList.normalized(host?.tags ?? []))
    }

    public var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $displayName).accessibilityIdentifier("host-editor-name")
                LabeledContent("Address") {
                    TextField("Address", text: $address, prompt: Text("Hostname or IP"))
                        .labelsHidden()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("host-editor-address")
                }
                if let host, host.addresses.count > 1 {
                    Text("The records that make up this host disagree: \(host.addresses.joined(separator: ", ")). Saving applies one address to all of them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Also known as") {
                    GlassTagField(tags: $aliases, placeholder: "Add a name…",
                                  accessibilityIdentifier: "host-editor-aliases")
                }
                Section("Collections") {
                    GlassTagField(tags: $tags, suggestions: model.tagVocabulary, placeholder: "Add a collection…",
                                  accessibilityIdentifier: "host-editor-tags")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle(host == nil ? "Add Host" : "Edit Host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(saving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("host-editor-save")
                }
            }
            .frame(minWidth: 320, idealWidth: 460, minHeight: 260)
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                let aliasList = GlassTagList.normalized(aliases), tagList = GlassTagList.normalized(tags)
                if let host {
                    try await model.updateHost(host.id, displayName: displayName, address: address, aliases: aliasList, tags: tagList)
                    onSave(host.id)
                } else {
                    let created = try await model.addHost(displayName: displayName, address: address, aliases: aliasList, tags: tagList)
                    onSave(created.id)
                }
                dismiss()
            } catch { self.error = GlassShellError.message(for: error) }
        }
    }
}

/// "Add a service…": a kind and a display name. Replaces glassDT's "Pair a
/// Service", which chose among other apps' saved endpoints; here the service is
/// created on the host and its capability fills in the endpoint later.
public struct GlassShellServiceEditor: View {
    private let model: GlassShellModel
    private let host: GlassShellHost
    @State private var kind = HostServiceKind.ssh
    @State private var displayName = ""
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    public init(model: GlassShellModel, host: GlassShellHost) {
        self.model = model
        self.host = host
    }

    public var body: some View {
        NavigationStack {
            Form {
                Picker("Service", selection: $kind) {
                    ForEach(HostServiceKind.allCases, id: \.self) { kind in
                        Label(GlassServicePresentation.displayName(for: kind), systemImage: GlassServicePresentation.symbolName(for: kind)).tag(kind)
                    }
                }
                .accessibilityIdentifier("service-editor-kind")
                TextField("Name", text: $displayName, prompt: Text(defaultName)).accessibilityIdentifier("service-editor-name")
                if model.registry.capability(for: kind) == nil {
                    Text("\(GlassServicePresentation.displayName(for: kind)) is not part of this build yet. The service is saved on the host and becomes usable when its capability arrives.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("Add a Service to \(host.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(saving).accessibilityIdentifier("service-editor-save")
                }
            }
            .frame(minWidth: 320, idealWidth: 460, minHeight: 260)
        }
    }

    private var defaultName: String { "\(GlassServicePresentation.displayName(for: kind)) on \(host.displayName)" }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                let name = displayName.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName : displayName
                try await model.addService(kind: kind, displayName: name, to: host.id)
                dismiss()
            } catch { self.error = GlassShellError.message(for: error) }
        }
    }
}


/// "Address for <host>": the one place the machine's address is collected when a host has none
/// and something needs it (a service setup is about to open, or the user asked from the detail).
/// Saves to the host through the same validation as the host editor, then resumes the connect
/// that was interrupted. No service form ever asks for an address.
public struct GlassShellAddressPrompt: View {
    private let model: GlassShellModel
    private let request: GlassShellAddressRequest
    @State private var address = ""
    @State private var error: String?
    @State private var saving = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(model: GlassShellModel, request: GlassShellAddressRequest) {
        self.model = model
        self.request = request
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $address, prompt: Text("Hostname or IP"))
                        .focused($focused)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit { if canContinue { save() } }
                        .accessibilityIdentifier("host-address-prompt-field")
                } footer: {
                    Text("\(request.host.displayName) has no address yet. It is saved on the host and shared by every service: terminal, database and desktop.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("Address for \(request.host.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("host-address-prompt-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(request.endpointID == nil ? "Save" : "Continue") { save() }
                        .disabled(!canContinue)
                        .accessibilityIdentifier("host-address-prompt-continue")
                }
            }
            .frame(minWidth: 320, idealWidth: 440, minHeight: 160)
            .onAppear { focused = true }
        }
    }

    private var canContinue: Bool { !saving && !address.trimmingCharacters(in: .whitespaces).isEmpty }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await model.setHostAddress(address, for: request.host.id)
                dismiss()
                if let endpointID = request.endpointID {
                    model.connect(hostID: request.host.id, endpointID: endpointID)
                }
            } catch { self.error = GlassShellError.message(for: error) }
        }
    }
}
