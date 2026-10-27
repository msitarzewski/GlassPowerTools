//
//  GlassWindowSettingRows.swift
//  Glass Power Tools — GlassLayers
//
//  This Window, built the same way in every kind of window (W22, W27). Each row's control shows
//  the value the window uses now. While the window sets the value, a tiny ↺ beside the setting's
//  name returns it to the setting it follows, with "Reset to All Terminals" (or Appearance, …) as
//  its tooltip; a row the window does not set shows its name alone. The page ends with Reset This
//  Window and one footer that says so. A capability builds its page from these and its own
//  controls, so every This Window reads and behaves alike.
//
//  The owner, on the Vision Pro (2026-10-10): the tab already says "This Window", so a caption
//  under every row saying "This window only" or "Same as …" was redundant; it is gone.
//

import SwiftUI
import GlassConnectionUI

/// The binding a This Window control edits: the window's value, else `global`; setting it sets
/// the window's own (even to the same value as the setting: the person chose it for this window).
public enum GlassWindowSettingBinding {
    public static func value<Value>(_ setting: GlassWindowSetting<Value>,
                                    in overrides: Binding<GlassWindowOverrides>,
                                    over global: Value) -> Binding<Value> {
        Binding(
            get: { overrides.wrappedValue.value(of: setting, over: global) },
            set: { overrides.wrappedValue[setting] = $0 }
        )
    }

    /// The way back a row offers beside its setting's name: none while the window follows the
    /// setting; while the window sets its own, a reset that makes it follow `inheritsFrom` again.
    public static func reset<Value>(_ setting: GlassWindowSetting<Value>,
                                    in overrides: Binding<GlassWindowOverrides>,
                                    inheritsFrom: String) -> GlassSettingReset? {
        guard overrides.wrappedValue.sets(setting) else { return nil }
        return GlassSettingReset(settingTitle: setting.title, source: inheritsFrom,
                                 identifier: "window-setting-reset.\(setting.key)") {
            overrides.wrappedValue[setting] = nil
        }
    }
}

/// One row of a window's own settings: `control` bound to the value the window uses. While the
/// window sets the value, the control's name carries a ↺ back to `inheritsFrom`'s, so the control
/// draws its name with `GlassSettingTitle` (`GlassSettingSlider` does; a system control goes in
/// `GlassSettingLabeled`).
///
/// ```swift
/// GlassWindowSettingRow(EditorWindowSettings.wrapsLines, overrides: $overrides,
///                       global: settings.wrapsLines, inheritsFrom: "All Editors") { value in
///     GlassSettingLabeled("Wrap Long Lines") { Toggle("Wrap Long Lines", isOn: value) }
/// }
/// ```
public struct GlassWindowSettingRow<Value: GlassWindowSettingValue, Control: View>: View {
    private let setting: GlassWindowSetting<Value>
    @Binding private var overrides: GlassWindowOverrides
    private let global: Value
    private let inheritsFrom: String
    private let control: (Binding<Value>) -> Control

    /// - Parameters:
    ///   - global: the setting's own value now, which the window follows until it sets one.
    ///   - inheritsFrom: where the setting lives, as the person knows it: "All Terminals",
    ///     "Appearance", "Settings". The reset's tooltip is "Reset to <inheritsFrom>".
    public init(_ setting: GlassWindowSetting<Value>,
                overrides: Binding<GlassWindowOverrides>,
                global: Value,
                inheritsFrom: String,
                @ViewBuilder control: @escaping (Binding<Value>) -> Control) {
        self.setting = setting
        _overrides = overrides
        self.global = global
        self.inheritsFrom = inheritsFrom
        self.control = control
    }

    public var body: some View {
        control(GlassWindowSettingBinding.value(setting, in: $overrides, over: global))
            .environment(\.glassSettingReset,
                         GlassWindowSettingBinding.reset(setting, in: $overrides, inheritsFrom: inheritsFrom))
    }
}

/// **Reset This Window**: every setting the window sets goes back to following its setting.
public struct GlassWindowResetButton: View {
    @Binding private var overrides: GlassWindowOverrides

    public init(overrides: Binding<GlassWindowOverrides>) {
        _overrides = overrides
    }

    public var body: some View {
        Button("Reset This Window", role: .destructive) {
            overrides = GlassWindowOverrides()
        }
        .disabled(overrides.isEmpty)
        .accessibilityIdentifier("window-settings-reset")
    }
}

/// The footer under Reset This Window, one pattern on every This Window page: what the settings
/// follow, how to go back, then what the window keeps and for how long, in the capability's words.
public struct GlassWindowSettingsFooter: View {
    private let sources: String
    private let keeps: String

    /// - Parameters:
    ///   - sources: where the page's settings live for every window: "All Terminals, Appearance
    ///     or Settings".
    ///   - keeps: one sentence on what the window keeps, where and for how long.
    public init(follows sources: String, keeps: String) {
        self.sources = sources
        self.keeps = keeps
    }

    public var body: some View {
        Text("Each setting follows \(sources) until you change it here, and \(Image(systemName: "arrow.uturn.backward")) beside it sets it back. \(keeps)")
            .accessibilityLabel(Self.spoken(follows: sources, keeps: keeps))
    }

    /// The footer as VoiceOver reads it, with the icon named for what it does.
    static func spoken(follows sources: String, keeps: String) -> String {
        "Each setting follows \(sources) until you change it here, and its Reset button sets it back. \(keeps)"
    }
}

/// The footer under a This Window page's Appearance section, one pattern in every window: what
/// Opacity does there, what Glass is, and how to make the window clear.
public enum GlassWindowGlassFooter {
    /// - Parameters:
    ///   - opacity: what Opacity does in this kind of window, as a verb phrase: "paints the
    ///     terminal's background color".
    ///   - clearAlso: anything else a clear window needs, as a phrase: "with no tint".
    public static func text(opacity: String, clearAlso: String? = nil) -> String {
        let clear = clearAlso.map { "Set both to 0%, \($0), for a clear window." } ?? "Set both to 0% for a clear window."
        return "Opacity \(opacity), and Glass is the glass behind it. \(clear)"
    }

    public static let reduceTransparency =
        "Reduce Transparency is on in Accessibility, so this window is opaque while it stays on."
}

/// This Window's Appearance section, for any Glass window: Opacity, Glass and Material over
/// Settings ▸ Appearance. The window's `GlassLayeredWindow` draws with them once the window's root
/// passes its overrides down (`glassWindowOverrides(_:)`).
///
/// **No Material on Vision Pro:** there every window's glass is Apple's own and a layer paints no
/// frost over it (`7478a39`), so a material picker would change nothing. The stored key stays, so
/// a Mac or an iPad still reads what was chosen there.
public struct GlassWindowLayerControls: View {
    @Environment(\.glassLayers) private var layers
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding private var overrides: GlassWindowOverrides
    private let inheritsFrom: String
    private let title: String

    /// - Parameter title: the section's: Appearance on a This Window page; the window's name where
    ///   its own look is set in Settings (the orb dock's).
    public init(overrides: Binding<GlassWindowOverrides>, inheritsFrom: String = "Appearance",
                title: String = "Appearance") {
        _overrides = overrides
        self.inheritsFrom = inheritsFrom
        self.title = title
    }

    public var body: some View {
        let global = layers.state
        Section {
            GlassWindowSettingRow(GlassLayerSettings.opacity, overrides: $overrides, global: global.opacity,
                                  inheritsFrom: inheritsFrom) { value in
                GlassSettingSlider(title: GlassLayerSettings.opacity.title, value: value, detents: [0, 0.5, 1],
                                   leadingAccessibilityLabel: "Transparent", trailingAccessibilityLabel: "Opaque",
                                   accessibilityIdentifier: "window-layers-opacity")
            }
            GlassWindowSettingRow(GlassLayerSettings.frost, overrides: $overrides, global: global.frost,
                                  inheritsFrom: inheritsFrom) { value in
                GlassSettingSlider(title: GlassLayerSettings.frost.title, value: value, detents: [0, 0.5, 1],
                                   leadingAccessibilityLabel: "No glass", trailingAccessibilityLabel: "Full glass",
                                   accessibilityIdentifier: "window-layers-frost")
            }
            #if !os(visionOS)
            GlassWindowSettingRow(GlassLayerSettings.material, overrides: $overrides, global: global.material,
                                  inheritsFrom: inheritsFrom) { value in
                GlassSettingLabeled(GlassLayerSettings.material.title) {
                    Picker(GlassLayerSettings.material.title, selection: value) {
                        ForEach(GlassLayerMaterial.allCases) { material in
                            Text(material.title).tag(material)
                        }
                    }
                    .accessibilityIdentifier("window-layers-material")
                }
            }
            #endif
        } header: {
            Text(title)
        } footer: {
            if reduceTransparency {
                Text(GlassWindowGlassFooter.reduceTransparency)
            } else {
                Text(GlassWindowGlassFooter.text(opacity: "paints the theme color behind content"))
            }
        }
        .disabled(reduceTransparency)
    }
}
