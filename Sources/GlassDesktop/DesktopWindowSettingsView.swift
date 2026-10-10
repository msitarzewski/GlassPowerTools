//
//  DesktopWindowSettingsView.swift
//  Glass Power Tools — GlassDesktop
//
//  **This Window** (W25, W27): Desktop Settings' first page, in every desktop window. Every desktop
//  setting the window can keep for itself is a GlassLayers row (W22): its control shows what the
//  window uses now, and once it is changed here a ↺ beside its name returns it to All Desktops.
//  Beside them, this session's live controls — Match Window Size, the display shown, Desktop
//  Resolution, Local Scale — which were already this page's ("This Window", Local Scale) and are
//  not settings. Show Original, under Presentation, was glassDT's toolbar button. Reset This
//  Window, at the end, returns every row.
//

import SwiftUI
import GlassLayers
import GlassConnectionUI
import GlassRDPTransport

/// This Window: the desktop window's own settings over All Desktops', and its session's controls.
struct DesktopWindowSettingsView: View {
    @Bindable var session: DesktopSessionModel
    /// All Desktops now, which each row follows until it is set here.
    let defaults: DesktopDefaults
    let compactScreen: Bool
    /// Closes Desktop Settings and asks for the wallpaper image: the file importer is the window's.
    let chooseWallpaper: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Where every row's setting lives, as This Window names it: Settings ▸ Desktops, which is
    /// also Desktop Settings' second page.
    static let allDesktops = "All Desktops"

    var body: some View {
        Form {
            if DesktopWindowSettings.offersGlass { glass }
            backgroundRemoval
            remoteDesktop
            zoom
            if DesktopWindowSettings.offersTouchPointer { touch }
            Section {
                GlassWindowResetButton(overrides: $session.windowSettings)
            } footer: {
                GlassWindowSettingsFooter(
                    follows: Self.allDesktops,
                    keeps: "The window keeps its settings on this device and has them again the next time this desktop opens. Match Window Size, the display shown, the resolution and Local Scale last for this session.")
            }
        }
        .formStyle(.grouped)
        // No extra padding: a grouped form brings its own margins, as every This Window's does.
    }

    /// What the window draws with now, for Show Original.
    private var profile: DesktopWindowProfile {
        DesktopWindowProfile(window: session.windowSettings, defaults: defaults, compactScreen: compactScreen,
                             reduceTransparency: reduceTransparency)
    }

    /// The presentation the window chose, before Reduce Transparency: what the sections below
    /// it are about.
    private var chosenMode: TransparencyMode {
        session.windowSettings.value(of: DesktopWindowSettings.backgroundRemoval, over: defaults.backgroundRemoval)
    }

    // MARK: Glass (Mac and Vision Pro)

    private var glass: some View {
        Section {
            GlassWindowSettingRow(DesktopWindowSettings.opacity, overrides: $session.windowSettings,
                                  global: defaults.opacity, inheritsFrom: Self.allDesktops) { value in
                GlassSettingSlider(title: DesktopWindowSettings.opacity.title, value: value, detents: [0, 0.5, 1],
                                   leadingAccessibilityLabel: "Transparent", trailingAccessibilityLabel: "Opaque",
                                   accessibilityIdentifier: "desktop-window-opacity")
            }
            GlassWindowSettingRow(DesktopWindowSettings.frost, overrides: $session.windowSettings,
                                  global: defaults.frost, inheritsFrom: Self.allDesktops) { value in
                GlassSettingSlider(title: DesktopWindowSettings.frost.title, value: value, detents: [0, 0.5, 1],
                                   leadingAccessibilityLabel: "No glass", trailingAccessibilityLabel: "Full glass",
                                   accessibilityIdentifier: "desktop-window-frost")
            }
        } header: {
            Text("Appearance")
        } footer: {
            if reduceTransparency {
                Text("Reduce Transparency is on in Accessibility, so the desktop is opaque, with Original presentation, while it stays on.")
            } else {
                Text(GlassWindowGlassFooter.text(opacity: "fades the desktop"))
            }
        }
        .disabled(reduceTransparency)
    }

    // MARK: Background removal

    @ViewBuilder private var backgroundRemoval: some View {
        Section {
            GlassWindowSettingRow(DesktopWindowSettings.backgroundRemoval, overrides: $session.windowSettings,
                                  global: defaults.backgroundRemoval, inheritsFrom: Self.allDesktops) { value in
                GlassSettingLabeled(DesktopWindowSettings.backgroundRemoval.title) {
                    Picker(DesktopWindowSettings.backgroundRemoval.title, selection: value) {
                        ForEach(TransparencyMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("desktop-window-presentation")
                }
            }
            // glassDT's toolbar Original, here since W27: this window's Presentation and Opacity
            // at once, which is why it is not a Presentation choice.
            Button("Show Original") { session.windowSettings.showDesktopOriginal() }
                .disabled(profile.showsOriginal)
                .help("The complete desktop image, opaque, in this window")
                .accessibilityIdentifier("display.glass.original")
        } header: {
            Text("Background Removal")
        } footer: {
            Text("Matching colors anywhere in the desktop can become transparent. Show Original returns this window to the complete image, opaque.")
        }
        .disabled(reduceTransparency)
        if chosenMode == .removeColor {
            Section {
                GlassWindowSettingRow(DesktopWindowSettings.keyColor, overrides: $session.windowSettings,
                                      global: DesktopKeyColor.hex(defaults.keyColor),
                                      inheritsFrom: Self.allDesktops) { hex in
                    GlassSettingLabeled(DesktopWindowSettings.keyColor.title) {
                        ColorPicker(DesktopWindowSettings.keyColor.title, selection: DesktopKeyColor.binding(Binding(
                            get: { DesktopKeyColor.color(hex.wrappedValue) ?? defaults.keyColor },
                            set: { hex.wrappedValue = DesktopKeyColor.hex($0) }
                        )), supportsOpacity: false)
                        .accessibilityIdentifier("desktop-window-color")
                    }
                    LabeledContent("Color Code") {
                        Text(hex.wrappedValue).monospaced().textSelection(.enabled)
                            .accessibilityIdentifier("desktop-window-hex")
                        Button("Copy", systemImage: "doc.on.doc") { DesktopKeyColor.copy(hex.wrappedValue) }
                            .labelStyle(.iconOnly).help("Copy Color Code")
                    }
                    Button("Use Magenta") { hex.wrappedValue = "#FF00FF" }
                }
            } header: {
                Text("Desktop Background")
            } footer: {
                Text("Set the remote desktop background to this solid color. Matching colors inside apps are removed too.")
            }
            .disabled(reduceTransparency)
        }
        if chosenMode != .original {
            Section("Edges") {
                GlassWindowSettingRow(DesktopWindowSettings.tolerance, overrides: $session.windowSettings,
                                      global: defaults.tolerance, inheritsFrom: Self.allDesktops) { value in
                    GlassSettingLabeled(DesktopWindowSettings.tolerance.title) {
                        Slider(value: value, in: DesktopDefaults.toleranceRange) { Text("Tolerance") }
                            .accessibilityIdentifier("desktop-window-tolerance")
                    }
                }
                GlassWindowSettingRow(DesktopWindowSettings.edgeSoftness, overrides: $session.windowSettings,
                                      global: defaults.edgeSoftness, inheritsFrom: Self.allDesktops) { value in
                    GlassSettingLabeled(DesktopWindowSettings.edgeSoftness.title) {
                        Slider(value: value, in: DesktopDefaults.edgeSoftnessRange) { Text("Edge Softness") }
                            .accessibilityIdentifier("desktop-window-edge-softness")
                    }
                }
            }
            .disabled(reduceTransparency)
        }
        if chosenMode == .removeWallpaper {
            Section {
                Button("Choose Wallpaper Image", action: chooseWallpaper)
                    .accessibilityIdentifier("display.wallpaper.choose")
            } header: {
                Text("Wallpaper")
            } footer: {
                Text("Choose the remote desktop's image. It is stretched to match the desktop; different placement or compression can leave visible edges. Remove Wallpaper and its image last for this session only; next time, this window follows All Desktops' presentation.")
            }
            .disabled(reduceTransparency)
        }
    }

    // MARK: The remote desktop: this session's, and Detail

    @ViewBuilder private var remoteDesktop: some View {
        if session.screens.count > 1 {
            Section {
                Picker("Show", selection: $session.selectedScreenID) {
                    Text("All Displays").tag(UInt32?.none)
                    ForEach(session.screens) { screen in
                        Text("\(screenName(screen)) (\(screen.width) × \(screen.height))").tag(UInt32?.some(screen.id))
                    }
                }.accessibilityIdentifier("display.screen")
            } header: {
                Text("Displays")
            } footer: {
                Text("This computer sends one image covering all of its displays. Showing a single display fills the window with it, and uses no more of the network.")
            }
        }
        Section {
            if let frame = session.frame {
                LabeledContent("Current Resolution", value: "\(frame.width) × \(frame.height)")
            }
            Toggle("Match Window Size", isOn: $session.matchWindow)
                .disabled(session.capabilities == nil)
                .accessibilityIdentifier("display.match-window")
            if session.connection.protocol == .rdp {
                GlassWindowSettingRow(DesktopWindowSettings.detail, overrides: $session.windowSettings,
                                      global: defaults.detail, inheritsFrom: Self.allDesktops) { value in
                    GlassSettingLabeled(DesktopWindowSettings.detail.title) {
                        Picker(DesktopWindowSettings.detail.title, selection: value) {
                            ForEach(DesktopSourceScale.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .disabled(!session.matchWindow)
                        .accessibilityIdentifier("desktop-window-detail")
                    }
                }
            }
            Menu("Desktop Resolution") {
                ForEach([DesktopSize(width: 1280, height: 800), .standard, DesktopSize(width: 2560, height: 1440), DesktopSize(width: 3840, height: 2160)], id: \.self) { size in
                    Button("\(size.width) × \(size.height)") {
                        session.matchWindow = false
                        Task { await session.setSourceSize(size) }
                    }.disabled(!(session.capabilities?.supports(width: size.width, height: size.height) ?? false))
                }
            }.disabled(session.capabilities == nil)
        } header: {
            Text("Remote Desktop")
        } footer: {
            if session.capabilities == nil {
                Text("Source resizing becomes available when the server offers display control.")
            } else if session.connection.protocol == .rdp {
                Text("Match Window Size adjusts the remote desktop as you resize this window. Detail asks for more remote pixels per point, so text stays sharp on a high-resolution display without changing how large it looks. Automatic follows this display. Higher settings send more pixels over the network, and a server that ignores the request will show a smaller interface.")
            } else {
                Text("Match Window Size adjusts the remote desktop as you resize this window.")
            }
        }
    }

    private func screenName(_ screen: GlassRemoteScreen) -> String {
        guard let index = session.screens.firstIndex(where: { $0.id == screen.id }) else { return "Display" }
        return screen.isPrimary ? "Main Display" : "Display \(index + 1)"
    }

    // MARK: Zoom: this session's

    private var zoom: some View {
        Section {
            GlassSettingSlider(title: "Local Scale", value: $session.presentation.zoom,
                               range: DesktopZoomLimits.minimum...DesktopZoomLimits.maximum, detents: [1],
                               leadingAccessibilityLabel: "Fitted to the window",
                               trailingAccessibilityLabel: "Double size",
                               accessibilityIdentifier: "display.local-scale")
            Button("Actual Size") {
                session.presentation.zoom = 1
                session.presentation.panX = 0
                session.presentation.panY = 0
            }
                .disabled(session.presentation.zoom == 1 && session.presentation.panX == 0 && session.presentation.panY == 0)
                .accessibilityIdentifier("display.local-scale.reset")
        } header: {
            Text("Zoom")
        } footer: {
            Text("Local scale enlarges the image in this window without changing the remote resolution. 100% is the desktop fitted to the window, which is as small as it goes.")
        }
    }

    // MARK: Touch (iPad and iPhone)

    private var touch: some View {
        let pointer = session.windowSettings.value(of: DesktopWindowSettings.pointer,
                                                   over: defaults.pointer(compactScreen: compactScreen))
        return Section {
            GlassWindowSettingRow(DesktopWindowSettings.pointer, overrides: $session.windowSettings,
                                  global: defaults.pointer(compactScreen: compactScreen),
                                  inheritsFrom: Self.allDesktops) { value in
                GlassSettingLabeled(DesktopWindowSettings.pointer.title) {
                    Picker(DesktopWindowSettings.pointer.title, selection: value) {
                        ForEach(DesktopPointerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("display.pointer-mode")
                }
            }
        } header: {
            Text("Touch")
        } footer: {
            Text(pointer == .trackpad
                 ? "Drag anywhere to move the pointer, tap to click where it sits, and tap with two fingers to right click. Tap then drag to move something."
                 : "Touching the screen presses the button at that point, which suits a large screen or a stylus.")
        }
    }
}
