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

/// Settings ▸ Desktops: what glassDT's own Settings window held that the shell's pages do not.
/// Privacy and About are the shell's now, so only General and (on the headset) Appearance remain,
/// as one page. Until 2026-09-27 this view moved in with the capability and nothing showed it, so
/// connection-failure notices could not be switched on.
public struct DesktopSettingsView: View {
    @State private var notices = DesktopNotices.shared
    #if os(visionOS)
    @AppStorage(DesktopGlassPreferenceKey.opacity) private var opacity = 1.0
    @AppStorage(DesktopGlassPreferenceKey.material) private var frost = 0.25
    #endif

    public init() {}

    public var body: some View {
        Form {
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
                Text("Receive a system notification when a remote desktop connection needs attention. Notices omit host names, account details, and server diagnostics.")
            }
            #if os(visionOS)
            DesktopGlassAppearanceControls(opacity: $opacity, frost: $frost)
            Section {
                Button("Reset Appearance") { opacity = 1; frost = 0.25 }
            } footer: {
                Text("These choices are saved on this device. Background removal and remote resolution are available in each desktop's settings.")
            }
            #endif
            Section {
                Text("Edit a desktop service in the library to change its account, credential storage, clipboard, and audio settings.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Connections")
            }
        }
        .formStyle(.grouped)
    }
}
