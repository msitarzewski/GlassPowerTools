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
            // Counted against the catalog's own hosts: this device is not one of its records
            // and would otherwise make the two numbers differ on every launch.
            if model.records.count != model.catalogHosts.count {
                // Diagnostics only: the family apps each published their own record per machine.
                LabeledContent("Catalog records", value: model.records.count, format: .number)
                Text("Records that describe the same machine are shown as one host. They are combined here, not rewritten in the shared library.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let problem = model.preferencesProblem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
            }
            // The device's own host is kept out of the shared file on purpose (D8), so its state
            // is reported separately — including when it could not be created at all.
            if let problem = model.localHostProblem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
                    .accessibilityIdentifier("settings-local-host-problem")
            } else {
                LabeledContent("This device", value: "Kept in this app only, never shared")
            }
        }
    }

    private var privacy: some View {
        Group {
            Section("Credentials") {
                LabeledContent("Store", value: "GlasSecretStore in the Keychain")
                LabeledContent("Access group", value: model.secretConfiguration.accessGroup ?? "Not shared (no access group)")
                LabeledContent("Default mobility", value: model.secretConfiguration.mobilityPolicy == .deviceOnly ? "This device only" : "iCloud Keychain")
                    .accessibilityIdentifier("settings-credential-mobility")
                Text("Each service keeps its own credential and trust. Nothing here reads a secret; capabilities ask for what they need when connecting.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            // D20: say what travels and what does not.
            //
            // With sync on by default (D21), a user is entitled to know which of their secrets
            // reaches their other devices before they find out by a connection failing on one.
            // The Secure Enclave line is the one that matters: a key protected by this device's
            // biometrics is bound to this device's hardware and CANNOT sync — `validateMobility`
            // refuses it outright — so a service set to require authentication will ask for its
            // password again elsewhere. That is correct behaviour and indefensible as a surprise.
            Section("On your other devices") {
                LabeledContent("Host library", value: model.catalogSyncStatusDescription)
                    .accessibilityIdentifier("settings-catalog-sync-status")
                Text("Passwords, SSH key passphrases and private keys travel with you through "
                     + "iCloud Keychain, encrypted so that only your devices can read them.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("A service set to require authentication does not. Its password is protected "
                     + "by this device's biometrics and cannot leave it, so you will be asked for "
                     + "that one again on another device.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-device-bound-note")
            }
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
