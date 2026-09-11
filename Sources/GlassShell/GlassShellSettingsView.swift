import GlassLayers
import SwiftUI
import GlassConnectionUI
import GlasSecretStore

public enum GlassShellSettingsPage: String, CaseIterable, Hashable, Sendable {
    case general, appearance, privacy, about

    public var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }
}

/// A page in the one settings surface: the shell's own, or one a capability contributes.
public enum GlassShellSettingsSelection: Hashable, Sendable {
    case shell(GlassShellSettingsPage)
    case capability(String)

    /// The shell's pages first, then every registered capability's, in kind order.
    public static func options(shell: [GlassShellSettingsPage] = GlassShellSettingsPage.allCases,
                               capabilityPages: [GlassCapabilitySettingsPage]) -> [GlassShellSettingsSelection] {
        shell.map(GlassShellSettingsSelection.shell) + capabilityPages.map { .capability($0.id) }
    }
}

/// The one settings surface. Pages are the glassDT set plus whatever the registered
/// capabilities contribute; nothing adds a second surface.
public struct GlassShellSettingsView: View {
    private let model: GlassShellModel
    @State private var page = GlassShellSettingsSelection.shell(.general)
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(model: GlassShellModel) { self.model = model }

    private var capabilityPages: [GlassCapabilitySettingsPage] { model.registry.settingsPages }

    private func title(_ selection: GlassShellSettingsSelection) -> String {
        switch selection {
        case .shell(let page): page.title
        case .capability(let id): capabilityPages.first { $0.id == id }?.title ?? id
        }
    }

    public var body: some View {
        GlassSettingsSections(selection: $page,
                              options: GlassShellSettingsSelection.options(capabilityPages: capabilityPages),
                              title: title, pickerIdentifier: "settings-sections") { selection in
            Form {
                switch selection {
                case .shell(.general): general
                case .shell(.appearance): GlassLayerControls()
                case .shell(.privacy): privacy
                case .shell(.about): about
                case .capability(let id):
                    if let page = capabilityPages.first(where: { $0.id == id }) {
                        page.makeView().accessibilityIdentifier("settings-page-\(id)")
                    }
                }
            }
            .formStyle(.grouped)
            #if os(iOS)
            // A compact iPhone pushes each page onto the sheet's stack, and the presenter's Done
            // button stays behind on the root. A modal must be dismissable from wherever the user
            // is, so every pushed page carries its own Done beside the back button.
            .toolbar {
                if horizontalSizeClass == .compact {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("settings-done")
                    }
                }
            }
            #endif
        }
        .navigationTitle("Settings")
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 380)
        #endif
    }

    private var general: some View {
        Section("Host Library") {
            LabeledContent("Sharing", value: model.hasSharedContainer ? "Shared with the Glass family" : "This app only")
            Text(model.hostLibraryStatus).font(.footnote).foregroundStyle(.secondary)
            LabeledContent("Hosts", value: model.hosts.count, format: .number)
            if model.records.count != model.hosts.count {
                // Diagnostics only: the family apps each published their own record per machine.
                LabeledContent("Catalog records", value: model.records.count, format: .number)
                Text("Records that describe the same machine are shown as one host. They are combined here, not rewritten in the shared library.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let problem = model.preferencesProblem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private var privacy: some View {
        Section("Credentials") {
            LabeledContent("Store", value: "GlasSecretStore in the Keychain")
            LabeledContent("Access group", value: model.secretConfiguration.accessGroup ?? "Not shared (no access group)")
            LabeledContent("Default mobility", value: model.secretConfiguration.mobilityPolicy == .deviceOnly ? "This device only" : "iCloud Keychain")
            Text("Each service keeps its own credential and trust. Nothing here reads a secret; capabilities ask for what they need when connecting.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var about: some View {
        Section {
            LabeledContent("Glass Power Tools", value: Self.versionString)
            LabeledContent("Library file", value: model.catalogFileURL.lastPathComponent)
            LabeledContent("Appearance migrated from", value: model.layers.migrationSource == .none ? "Defaults" : model.layers.migrationSource.rawValue)
            Text("Terminal, databases and remote desktops for every machine you own — on Mac, iPad, iPhone and Vision Pro.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}
