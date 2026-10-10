//
//  GlassWindowSettingRows.swift
//  Glass Power Tools — GlassLayers
//
//  This Window, built the same way in every kind of window (W22). Each row's control shows the
//  value the window uses now; under it, whether that is the window's own or the setting it
//  follows — "Same as All Terminals", "Same as Appearance" — with a way back; and the page ends
//  with Reset This Window. A capability builds its page from these and its own controls, so
//  every This Window reads and behaves alike.
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
}

/// One row of a window's own settings: `control` bound to the value the window uses, and under it
/// whether that is the window's own or `inheritsFrom`'s, with its own reset.
///
/// ```swift
/// GlassWindowSettingRow(EditorWindowSettings.fontSize, overrides: $overrides,
///                       global: settings.fontSize, inheritsFrom: "All Editors") { size in
///     Stepper("Font Size: \(Int(size.wrappedValue))", value: size, in: 8...36)
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
    ///     "Appearance", "Settings".
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
        VStack(alignment: .leading, spacing: 6) {
            control(GlassWindowSettingBinding.value(setting, in: $overrides, over: global))
            GlassWindowSettingSource(title: setting.title, key: setting.key,
                                     isSet: overrides.sets(setting), inheritsFrom: inheritsFrom) {
                overrides[setting] = nil
            }
        }
    }
}

/// Under a This Window control: "Same as <where it lives>", or "This window only" and Reset.
public struct GlassWindowSettingSource: View {
    private let title: String
    private let key: String
    private let isSet: Bool
    private let inheritsFrom: String
    private let reset: () -> Void

    public init(title: String, key: String, isSet: Bool, inheritsFrom: String, reset: @escaping () -> Void) {
        self.title = title
        self.key = key
        self.isSet = isSet
        self.inheritsFrom = inheritsFrom
        self.reset = reset
    }

    /// The words under a row, for a test or an accessibility check: what the row says now.
    public static func caption(isSet: Bool, inheritsFrom: String) -> String {
        isSet ? "This window only" : "Same as \(inheritsFrom)"
    }

    public var body: some View {
        HStack(spacing: 8) {
            if isSet {
                Label(Self.caption(isSet: true, inheritsFrom: inheritsFrom), systemImage: "macwindow")
                    .foregroundStyle(.tint)
                Spacer(minLength: 8)
                Button("Reset", systemImage: "arrow.uturn.backward", action: reset)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset \(title) to \(inheritsFrom)")
                    .accessibilityIdentifier("window-setting-reset.\(key)")
            } else {
                Label(Self.caption(isSet: false, inheritsFrom: inheritsFrom), systemImage: "link")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("window-setting-source.\(key)")
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

/// This Window's Appearance section, for any Glass window: Opacity, Frost and Material over
/// Settings ▸ Appearance. The window's `GlassLayeredWindow` draws with them once the window's root
/// passes its overrides down (`glassWindowOverrides(_:)`).
public struct GlassWindowLayerControls: View {
    @Environment(\.glassLayers) private var layers
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding private var overrides: GlassWindowOverrides
    private let inheritsFrom: String

    public init(overrides: Binding<GlassWindowOverrides>, inheritsFrom: String = "Appearance") {
        _overrides = overrides
        self.inheritsFrom = inheritsFrom
    }

    public var body: some View {
        let global = layers.state
        Section {
            GlassWindowSettingRow(GlassLayerSettings.opacity, overrides: $overrides, global: global.opacity,
                                  inheritsFrom: inheritsFrom) { value in
                GlassSettingSlider(title: "Opacity", value: value, detents: [0, 0.5, 1],
                                   leadingAccessibilityLabel: "Transparent", trailingAccessibilityLabel: "Opaque",
                                   accessibilityIdentifier: "window-layers-opacity")
            }
            GlassWindowSettingRow(GlassLayerSettings.frost, overrides: $overrides, global: global.frost,
                                  inheritsFrom: inheritsFrom) { value in
                GlassSettingSlider(title: "Frost", value: value, detents: [0, 0.5, 1],
                                   leadingAccessibilityLabel: "Clear", trailingAccessibilityLabel: "Frosted",
                                   accessibilityIdentifier: "window-layers-frost")
            }
            GlassWindowSettingRow(GlassLayerSettings.material, overrides: $overrides, global: global.material,
                                  inheritsFrom: inheritsFrom) { value in
                Picker("Material", selection: value) {
                    ForEach(GlassLayerMaterial.allCases) { material in
                        Text(material.title).tag(material)
                    }
                }
                .accessibilityIdentifier("window-layers-material")
            }
        } header: {
            Text("Glass")
        } footer: {
            if reduceTransparency {
                Text("Reduce Transparency is on in Accessibility. Every window is opaque and frosted while it stays on.")
            } else {
                Text("Only this window changes. Each setting follows Appearance until you change it here.")
            }
        }
        .disabled(reduceTransparency)
    }
}
