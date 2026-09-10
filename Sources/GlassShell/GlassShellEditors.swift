import SwiftUI
import GlassConnectionKit

/// Add or edit a host: name, aliases and collection tags. No endpoint fields —
/// those belong to the capability that owns each service.
public struct GlassShellHostEditor: View {
    private let model: GlassShellModel
    private let host: HostProfile?
    private let onSave: (HostID) -> Void
    @State private var displayName: String
    @State private var aliases: String
    @State private var tags: String
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    public init(model: GlassShellModel, host: HostProfile?, onSave: @escaping (HostID) -> Void) {
        self.model = model
        self.host = host
        self.onSave = onSave
        _displayName = State(initialValue: host?.displayName ?? "")
        _aliases = State(initialValue: host?.aliases.joined(separator: ", ") ?? "")
        _tags = State(initialValue: host?.tags.joined(separator: ", ") ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $displayName).accessibilityIdentifier("host-editor-name")
                TextField("Also known as (comma separated)", text: $aliases).accessibilityIdentifier("host-editor-aliases")
                TextField("Collections (comma separated)", text: $tags).accessibilityIdentifier("host-editor-tags")
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
                let aliasList = Self.split(aliases), tagList = Self.split(tags)
                if let host {
                    try await model.updateHost(host.id, displayName: displayName, aliases: aliasList, tags: tagList)
                    onSave(host.id)
                } else {
                    let created = try await model.addHost(displayName: displayName, aliases: aliasList, tags: tagList)
                    onSave(created.id)
                }
                dismiss()
            } catch { self.error = GlassShellError.message(for: error) }
        }
    }

    static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

/// "Add a service…": a kind and a display name. Replaces glassDT's "Pair a
/// Service", which chose among other apps' saved endpoints; here the service is
/// created on the host and its capability fills in the endpoint later.
public struct GlassShellServiceEditor: View {
    private let model: GlassShellModel
    private let host: HostProfile
    @State private var kind = HostServiceKind.ssh
    @State private var displayName = ""
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    public init(model: GlassShellModel, host: HostProfile) {
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
