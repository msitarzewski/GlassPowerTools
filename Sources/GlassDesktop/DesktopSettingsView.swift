import SwiftUI
import GlassConnectionUI

/// Existing preference keys are shared by app settings and the live desktop.
enum DesktopGlassPreferenceKey {
    static let opacity = "display.glass.opacity"
    static let material = "display.glass.material"
}

struct DesktopGlassAppearanceControls: View {
    @Binding var opacity: Double
    @Binding var frost: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Section {
            GlassSettingSlider(title: "Opacity", value: $opacity,
                leadingAccessibilityLabel: "Transparent", trailingAccessibilityLabel: "Opaque",
                accessibilityIdentifier: "display.glass.opacity")
            GlassSettingSlider(title: "Background Frost", value: $frost,
                leadingAccessibilityLabel: "Clear", trailingAccessibilityLabel: "Frosted",
                accessibilityIdentifier: "display.glass.frost")
            HStack {
                Button("Clear") { frost = 0 }.accessibilityIdentifier("display.glass.clear")
                Button("Frosted") { frost = 0.5 }.accessibilityIdentifier("display.glass.frosted")
            }.buttonStyle(.borderless)
        } header: {
            Text("Glass")
        } footer: {
            if reduceTransparency {
                Text("Reduce Transparency is on in Accessibility. The desktop uses an opaque Original presentation.")
            } else {
                Text("Opacity fades the entire desktop. Frost changes the material behind it. Set both to 0% for a clear canvas; controls stay visible.")
            }
        }.disabled(reduceTransparency)
    }
}

public struct DesktopSettingsView: View {
    @State private var notices = DesktopNotices.shared
    @State private var selectedPage = Page.general
    #if os(visionOS)
    @AppStorage(DesktopGlassPreferenceKey.opacity) private var opacity = 1.0
    @AppStorage(DesktopGlassPreferenceKey.material) private var frost = 0.25
    #endif

    public init() {}

    public var body: some View {
        Group {
            #if os(iOS)
            List {
                ForEach(pages, id: \.self) { page in
                    NavigationLink {
                        settingsForm(page).navigationTitle(page.title)
                    } label: {
                        Label(page.title, systemImage: page.symbol)
                    }
                }
            }
            #elseif os(visionOS)
            GlassSettingsSections(selection: $selectedPage, options: pages,
                title: { $0.title }, pickerIdentifier: "desktop.settings.section") { page in
                settingsForm(page)
            }
            #else
            TabView {
                ForEach(pages, id: \.self) { page in
                    settingsForm(page)
                        .tabItem { Label(page.title, systemImage: page.symbol) }
                }
            }.accessibilityIdentifier("desktop.settings.tabs")
                .frame(width: 760, height: 560)
            #endif
        }.navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var pages: [Page] {
        #if os(visionOS)
        [.general, .appearance, .privacy, .about]
        #else
        [.general, .privacy, .about]
        #endif
    }

    @ViewBuilder private func settingsForm(_ page: Page) -> some View {
        Form {
            switch page {
            case .general:
                Section {
                    Toggle("Important Session Notices", isOn: Binding(
                        get: { notices.isEnabled },
                        set: { enabled in Task { await notices.setEnabled(enabled) } }
                    )).disabled(notices.isRequestingAuthorization)
                        .accessibilityIdentifier("settings.notifications")
                    if let status = notices.statusMessage {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Receive a system notification when a connection needs attention. Notices omit host names, account details, and server diagnostics.")
                }
                Section {
                    Text("Edit a saved desktop to change its account, credential storage, clipboard, and audio settings.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Connections")
                }
            case .appearance:
                #if os(visionOS)
                DesktopGlassAppearanceControls(opacity: $opacity, frost: $frost)
                Section {
                    Button("Reset Appearance") { opacity = 1; frost = 0.25 }
                } footer: {
                    Text("These choices are saved on this device. Background removal and remote resolution are available in each desktop's settings.")
                }
                #else
                EmptyView()
                #endif
            case .privacy:
                Section {
                    Text("Passwords are stored in Keychain. iCloud Keychain can sync eligible credentials according to your Apple Account and device settings.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Credentials")
                }
                Section {
                    Text("Saved desktops, appearance settings, and service pairings stay on this device. Pairing services does not share their passwords or grant access to another account.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Saved Settings")
                }
            case .about:
                Section("Desktop") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                    LabeledContent("Remote Desktop Protocol", value: "RDP")
                    LabeledContent("App License", value: "MIT")
                }
            }
        }.formStyle(.grouped).padding()
    }

    private enum Page: Hashable {
        case general, appearance, privacy, about
        var title: String {
            switch self { case .general: "General"; case .appearance: "Appearance"; case .privacy: "Privacy"; case .about: "About" }
        }
        var symbol: String {
            switch self { case .general: "gearshape"; case .appearance: "paintbrush"; case .privacy: "hand.raised"; case .about: "info.circle" }
        }
    }
}
