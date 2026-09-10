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

/// The one settings surface. Pages are the glassDT set; capabilities add
/// sections to these pages in later stages rather than adding surfaces.
public struct GlassShellSettingsView: View {
    private let model: GlassShellModel
    @State private var page = GlassShellSettingsPage.general

    public init(model: GlassShellModel) { self.model = model }

    public var body: some View {
        GlassSettingsSections(selection: $page, options: GlassShellSettingsPage.allCases,
                              title: \.title, pickerIdentifier: "settings-sections") { page in
            Form {
                switch page {
                case .general: general
                case .appearance: GlassLayerControls()
                case .privacy: privacy
                case .about: about
                }
            }
            .formStyle(.grouped)
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
