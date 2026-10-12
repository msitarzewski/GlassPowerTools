import SwiftUI
import GlassConnectionUI
import GlassLayers
import GlassRDPTransport

struct DesktopGlassAppearanceControls: View {
    @Binding var opacity: Double
    @Binding var frost: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Section {
            GlassSettingSlider(title: "Opacity", value: $opacity,
                leadingAccessibilityLabel: "Transparent", trailingAccessibilityLabel: "Opaque",
                accessibilityIdentifier: "display.glass.opacity")
            GlassSettingSlider(title: GlassLayerSettings.frost.title, value: $frost,
                leadingAccessibilityLabel: "No glass", trailingAccessibilityLabel: "Full glass",
                accessibilityIdentifier: "display.glass.frost")
            HStack {
                Button("Clear") { frost = 0 }.accessibilityIdentifier("display.glass.clear")
                Button("Frosted") { frost = 0.5 }.accessibilityIdentifier("display.glass.frosted")
            }.buttonStyle(.borderless)
        } header: {
            Text("Appearance")
        } footer: {
            if reduceTransparency {
                Text("Reduce Transparency is on in Accessibility. The desktop uses an opaque Original presentation.")
            } else {
                Text("Opacity fades the entire desktop, and Glass is the glass behind it. Set both to 0% for a clear canvas; controls stay visible.")
            }
        }.disabled(reduceTransparency)
    }
}

/// Settings ▸ Desktops on this device (**All Desktops**), where it is read and written: the
/// Settings page, each desktop window's All Desktops, and every desktop window, which follows it
/// until it sets its own (W25). Under glassDT's keys (`DesktopPreferenceKey`), unchanged.
struct DesktopAllDesktopsStorage: DynamicProperty {
    @AppStorage(DesktopPreferenceKey.opacity, store: GlassUITestRun.settingsDefaults) var opacity = DesktopDefaults.standard.opacity
    @AppStorage(DesktopPreferenceKey.frost, store: GlassUITestRun.settingsDefaults) var frost = DesktopDefaults.standard.frost
    @AppStorage(DesktopPreferenceKey.backgroundRemoval, store: GlassUITestRun.settingsDefaults) var backgroundRemoval = TransparencyMode.original.rawValue
    @AppStorage(DesktopPreferenceKey.keyRed, store: GlassUITestRun.settingsDefaults) var red = Double(DesktopDefaults.standard.keyColor.x)
    @AppStorage(DesktopPreferenceKey.keyGreen, store: GlassUITestRun.settingsDefaults) var green = Double(DesktopDefaults.standard.keyColor.y)
    @AppStorage(DesktopPreferenceKey.keyBlue, store: GlassUITestRun.settingsDefaults) var blue = Double(DesktopDefaults.standard.keyColor.z)
    @AppStorage(DesktopPreferenceKey.tolerance, store: GlassUITestRun.settingsDefaults) var tolerance = DesktopDefaults.standard.tolerance
    @AppStorage(DesktopPreferenceKey.edgeSoftness, store: GlassUITestRun.settingsDefaults) var edgeSoftness = DesktopDefaults.standard.edgeSoftness
    @AppStorage(DesktopPreferenceKey.detail, store: GlassUITestRun.settingsDefaults) var detail = DesktopSourceScale.automatic.rawValue
    @AppStorage(DesktopPreferenceKey.pointer, store: GlassUITestRun.settingsDefaults) var pointer = ""
    @AppStorage(DesktopPreferenceKey.quality, store: GlassUITestRun.settingsDefaults) var quality = GlassDesktopStreamQuality.automatic.rawValue
    @AppStorage(DesktopPreferenceKey.displays, store: GlassUITestRun.settingsDefaults) var displays = ""
    @AppStorage(DesktopPreferenceKey.retina, store: GlassUITestRun.settingsDefaults) var retina = ""
    @AppStorage(DesktopPreferenceKey.keepProportions, store: GlassUITestRun.settingsDefaults) var keepProportions = true
    @AppStorage(DesktopPreferenceKey.macScreenSharing, store: GlassUITestRun.settingsDefaults) var macScreenSharing = ""

    /// What is stored, kept in range.
    var defaults: DesktopDefaults {
        DesktopDefaults(storedOpacity: opacity, frost: frost, backgroundRemoval: backgroundRemoval,
                        red: red, green: green, blue: blue, tolerance: tolerance, edgeSoftness: edgeSoftness,
                        detail: detail, pointer: pointer, quality: quality, displays: displays,
                        retina: retina, keepProportions: keepProportions, macScreenSharing: macScreenSharing)
    }

    var macScreenSharingMode: Binding<GlassDesktopMacScreenSharing> {
        Binding(get: { defaults.macScreenSharing }, set: { macScreenSharing = $0.rawValue })
    }

    var retinaDisplays: Binding<GlassDesktopRetinaDisplays> {
        Binding(get: { defaults.retina }, set: { retina = $0.rawValue })
    }

    var streamQuality: Binding<GlassDesktopStreamQuality> {
        Binding(get: { defaults.quality }, set: { quality = $0.rawValue })
    }

    var displayWindows: Binding<DesktopDisplayWindows> {
        Binding(get: { defaults.resolvedDisplays }, set: { displays = $0.rawValue })
    }

    var mode: Binding<TransparencyMode> {
        Binding(get: { defaults.backgroundRemoval }, set: { backgroundRemoval = $0.rawValue })
    }

    var keyColor: Binding<SIMD3<Float>> {
        Binding(get: { defaults.keyColor }, set: { color in
            red = Double(color.x); green = Double(color.y); blue = Double(color.z)
        })
    }

    var sourceScale: Binding<DesktopSourceScale> {
        Binding(get: { defaults.detail }, set: { detail = $0.rawValue })
    }

    /// Nil is Automatic.
    var pointerMode: Binding<DesktopPointerMode?> {
        Binding(get: { defaults.pointer }, set: { pointer = $0?.rawValue ?? "" })
    }

    /// Glass and background removal back to where they start. Detail and Pointer have Automatic.
    func resetAppearance() {
        let standard = DesktopDefaults.standard
        opacity = standard.opacity
        frost = standard.frost
        backgroundRemoval = standard.backgroundRemoval.rawValue
        red = Double(standard.keyColor.x); green = Double(standard.keyColor.y); blue = Double(standard.keyColor.z)
        tolerance = standard.tolerance
        edgeSoftness = standard.edgeSoftness
    }
}

/// Settings ▸ Desktops: what glassDT's own Settings window held that the shell's pages do not, and
/// (W25) every desktop setting a window follows until it sets its own: **All Desktops** in each
/// desktop window's Desktop Settings is this page. Privacy and About are the shell's now. Until
/// 2026-09-27 this view moved in with the capability and nothing showed it, so connection-failure
/// notices could not be switched on.
public struct DesktopSettingsView: View {
    @State private var notices = DesktopNotices.shared
    private var allDesktops = DesktopAllDesktopsStorage()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
            if DesktopWindowSettings.offersGlass {
                DesktopGlassAppearanceControls(opacity: allDesktops.$opacity, frost: allDesktops.$frost)
            }
            backgroundRemoval
            Section {
                Picker("Detail", selection: allDesktops.sourceScale) {
                    ForEach(DesktopSourceScale.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("display.source-scale")
                if DesktopWindowSettings.offersProportions {
                    Toggle(DesktopWindowSettings.keepProportions.title, isOn: allDesktops.$keepProportions)
                        .accessibilityIdentifier("display.keep-proportions")
                }
            } header: {
                Text("Remote Desktop")
            } footer: {
                Text("RDP only. Detail asks for more remote pixels per point while Match Window Size is on, so text stays sharp on a high-resolution display. Automatic follows the display the window is on.\(DesktopWindowSettings.offersProportions ? " " + DesktopWindowSettingsView.proportionsFooter : "")")
            }
            // W30: what a VNC connection trades for bytes, and what a host's several displays get.
            Section {
                Picker("Quality", selection: allDesktops.streamQuality) {
                    ForEach(GlassDesktopStreamQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("display.stream-quality")
                Picker("Display Windows", selection: allDesktops.displayWindows) {
                    ForEach(DesktopDisplayWindows.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("display.display-windows")
                Picker(DesktopWindowSettings.retina.title, selection: allDesktops.retinaDisplays) {
                    ForEach(GlassDesktopRetinaDisplays.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("display.retina")
                Picker(DesktopWindowSettings.macScreenSharing.title, selection: allDesktops.macScreenSharingMode) {
                    ForEach(GlassDesktopMacScreenSharing.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("display.mac-screen-sharing")
            } header: {
                Text("Screen Sharing (VNC)")
            } footer: {
                Text("\(DesktopConnectionSettingsSections.qualityFooter) Display Windows is for a computer with several displays: one window showing them, or a window for each, opened when it connects. \(DesktopConnectionSettingsSections.retinaFooter) \(DesktopConnectionSettingsSections.macScreenSharingFooter)")
            }
            if DesktopWindowSettings.offersTouchPointer {
                Section {
                    Picker("Pointer", selection: allDesktops.pointerMode) {
                        Text("Automatic").tag(DesktopPointerMode?.none)
                        ForEach(DesktopPointerMode.allCases, id: \.self) { Text($0.title).tag(DesktopPointerMode?.some($0)) }
                    }
                    .accessibilityIdentifier("display.pointer-mode")
                } header: {
                    Text("Touch")
                } footer: {
                    Text("Automatic uses Trackpad on iPhone and in a narrow iPad window, and Direct Touch otherwise.")
                }
            }
            Section {
                Button("Reset Appearance") { allDesktops.resetAppearance() }
                    .accessibilityIdentifier("display.reset")
            } footer: {
                Text("These settings are every desktop window's, on this device. To change one window, open Settings (gear) in it and choose This Window: what it changes there stays with that window, and the rest follows these.")
            }
            Section {
                Text("Edit a desktop service in the library to change its account, credential storage, clipboard, and audio settings.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Connections")
            }
        }
        .formStyle(.grouped)
    }

    /// Remove Wallpaper is a window's, for one session: it needs an image chosen there.
    @ViewBuilder private var backgroundRemoval: some View {
        let mode = allDesktops.defaults.backgroundRemoval
        Section {
            Picker("Presentation", selection: allDesktops.mode) {
                ForEach(TransparencyMode.allCases.filter { $0 != .removeWallpaper }, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("display.presentation")
            if mode == .removeColor {
                ColorPicker("Background Color", selection: DesktopKeyColor.binding(allDesktops.keyColor), supportsOpacity: false)
                    .accessibilityIdentifier("display.glass.color")
                LabeledContent("Color Code") {
                    Text(DesktopKeyColor.hex(allDesktops.defaults.keyColor)).monospaced().textSelection(.enabled)
                        .accessibilityIdentifier("display.glass.hex")
                }
                Button("Use Magenta") { allDesktops.keyColor.wrappedValue = [1, 0, 1] }
            }
            if mode != .original {
                LabeledContent("Tolerance") {
                    Slider(value: allDesktops.$tolerance, in: DesktopDefaults.toleranceRange) { Text("Tolerance") }
                }
                LabeledContent("Edge Softness") {
                    Slider(value: allDesktops.$edgeSoftness, in: DesktopDefaults.edgeSoftnessRange) { Text("Edge Softness") }
                }
            }
        } header: {
            Text("Background Removal")
        } footer: {
            Text("Matching colors anywhere in a desktop can become transparent; with Remove Background Color, set the remote desktop's background to this solid color. Remove Wallpaper needs the remote wallpaper's image, so it is chosen in a desktop window, for that session.")
        }
        .disabled(reduceTransparency)
    }
}
