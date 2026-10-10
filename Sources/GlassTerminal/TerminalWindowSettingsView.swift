//
//  TerminalWindowSettingsView.swift
//  Glass Power Tools — GlassTerminal
//
//  **This Window** (W20, W22): every setting a terminal window can keep for itself, built from
//  GlassLayers' shared rows. Each row's control shows what the window uses now; under it, "Same as
//  All Terminals" (or Appearance, or Settings) until it is changed here, then "This window only"
//  with its own Reset. Reset This Window, at the end, returns them all. A change applies at once to
//  every tab in the window, and stays with the window.
//

import SwiftUI
import GlassLayers
import GlassConnectionUI

/// This Window: the window's own settings, each over the setting it follows.
struct TerminalOverridesSettingsView: View {
    @Binding var settings: GlassWindowOverrides
    @Environment(SettingsManager.self) private var settingsManager

    /// Where each kind of setting lives for every window, as This Window names it.
    enum Source {
        static let appearance = "Appearance"
        static let allTerminals = "All Terminals"
        /// Bell and scrollback: Settings ▸ Connections, for every terminal.
        static let settings = "Settings"
    }

    init(settings: Binding<GlassWindowOverrides>) {
        _settings = settings
    }

    var body: some View {
        let global = settingsManager
        let effective = TerminalWindowProfile.resolved(settings, settings: global)
        // The font the window's theme brings, which its own font follows until set here.
        let themeFont = TerminalWindowProfile.theme(
            settings.removing([TerminalWindowSettings.fontFamily.key, TerminalWindowSettings.fontSize.key]),
            over: global.currentTheme, library: global.themeLibrary)

        Form {
            Section {
                GlassWindowSettingRow(GlassLayerSettings.opacity, overrides: $settings,
                                      global: global.windowOpacity, inheritsFrom: Source.appearance) { value in
                    GlassSettingSlider(title: "Opacity", value: value, detents: [0, 0.5, 1],
                                       leadingAccessibilityLabel: "Transparent", trailingAccessibilityLabel: "Opaque",
                                       accessibilityIdentifier: "terminal-window-opacity")
                }
                GlassWindowSettingRow(GlassLayerSettings.frost, overrides: $settings,
                                      global: global.blurBackground, inheritsFrom: Source.appearance) { value in
                    GlassSettingSlider(title: "Blur", value: value, detents: [0, 0.5, 1],
                                       leadingAccessibilityLabel: "None", trailingAccessibilityLabel: "Maximum",
                                       accessibilityIdentifier: "terminal-window-blur")
                }
                #if !os(macOS)
                // The canvas's material off the Mac; a Mac terminal blurs with the window behind it.
                GlassWindowSettingRow(GlassLayerSettings.material, overrides: $settings,
                                      global: GlassLayerMaterial(rawValue: global.glassFrost) ?? GlassLayerState.default.material,
                                      inheritsFrom: Source.appearance) { value in
                    Picker("Frost", selection: value) {
                        ForEach(GlassLayerMaterial.allCases) { material in
                            Text(material.title).tag(material)
                        }
                    }
                    .accessibilityIdentifier("terminal-window-frost")
                }
                #endif
                GlassWindowSettingRow(TerminalWindowSettings.tint, overrides: $settings,
                                      global: global.glassTint, inheritsFrom: Source.allTerminals) { value in
                    GlassTintPicker(value: value)
                }
                #if os(visionOS)
                GlassWindowSettingRow(TerminalWindowSettings.interactiveGlass, overrides: $settings,
                                      global: global.interactiveGlass, inheritsFrom: Source.allTerminals) { value in
                    Toggle("Interactive glass", isOn: value)
                }
                #endif
            } header: {
                Text("Glass")
            } footer: {
                #if os(visionOS)
                Text("Only this window changes: every tab in it, and it keeps these after a relaunch. Opacity and blur remain independent; set both to zero, with no tint, for a completely transparent terminal.")
                #else
                Text("Only this window changes: every tab in it, and it keeps these after a relaunch. Tint, opacity and blur affect the terminal canvas; the window's chrome stays system glass.")
                #endif
            }

            Section("Theme") {
                GlassWindowSettingRow(TerminalWindowSettings.theme, overrides: $settings,
                                      global: global.currentTheme.id.uuidString, inheritsFrom: Source.allTerminals) { value in
                    Picker("Theme", selection: themeSelection(value, global: global)) {
                        ForEach(global.themeLibrary.activeRecords) { record in
                            Text(record.theme.name).tag(record.id.uuidString)
                        }
                    }
                    .accessibilityIdentifier("terminal-window-theme")
                }
                if TerminalWindowProfile.isMissingTheme(settings, library: global.themeLibrary) {
                    Text("This window's theme isn't on this device yet, so it uses All Terminals' theme until it arrives.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GlassWindowSettingRow(TerminalWindowSettings.fontFamily, overrides: $settings,
                                      global: themeFont.fontName, inheritsFrom: Source.allTerminals) { value in
                    Picker("Font Family", selection: value) {
                        ForEach(fontFamilies(including: value.wrappedValue), id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .accessibilityIdentifier("terminal-window-font-family")
                }
                GlassWindowSettingRow(TerminalWindowSettings.fontSize, overrides: $settings,
                                      global: Double(themeFont.fontSize), inheritsFrom: Source.allTerminals) { value in
                    Slider(value: value, in: 10...24, step: 1) {
                        Text("Font Size")
                    } minimumValueLabel: {
                        Text("10")
                    } maximumValueLabel: {
                        Text("24")
                    }
                    .accessibilityValue("\(Int(value.wrappedValue)) points")
                    .accessibilityIdentifier("terminal-window-font-size")
                }
            }

            Section("Cursor") {
                GlassWindowSettingRow(TerminalWindowSettings.cursorStyle, overrides: $settings,
                                      global: global.cursorStyle, inheritsFrom: Source.allTerminals) { value in
                    Picker("Cursor Style", selection: value) {
                        ForEach(TerminalWindowSettings.cursorStyles, id: \.self) { style in
                            Text(style).tag(style)
                        }
                    }
                    .accessibilityIdentifier("terminal-window-cursor-style")
                }
                GlassWindowSettingRow(TerminalWindowSettings.blinkingCursor, overrides: $settings,
                                      global: global.blinkingCursor, inheritsFrom: Source.allTerminals) { value in
                    Toggle("Blinking cursor", isOn: value)
                }
            }

            Section {
                GlassWindowSettingRow(TerminalWindowSettings.bell, overrides: $settings,
                                      global: global.bellEnabled, inheritsFrom: Source.settings) { value in
                    Toggle("Bell enabled", isOn: value)
                }
                GlassWindowSettingRow(TerminalWindowSettings.visualBell, overrides: $settings,
                                      global: global.visualBell, inheritsFrom: Source.settings) { value in
                    Toggle("Visual bell", isOn: value)
                        .disabled(!effective.bellEnabled)
                }
                GlassWindowSettingRow(TerminalWindowSettings.keepsScrollback, overrides: $settings,
                                      global: global.saveScrollback, inheritsFrom: Source.settings) { value in
                    Toggle("Keep scrollback during session", isOn: value)
                }
                GlassWindowSettingRow(TerminalWindowSettings.scrollbackLines, overrides: $settings,
                                      global: global.maxScrollbackLines, inheritsFrom: Source.settings) { value in
                    Stepper("Max scrollback lines: \(value.wrappedValue)", value: value, in: 1000...100_000, step: 1000)
                        .disabled(effective.scrollbackLines == 0)
                }
            } header: {
                Text("Bell and Scrollback")
            } footer: {
                Text("For every terminal, these are in Settings ▸ Connections.")
            }

            Section {
                GlassWindowResetButton(overrides: $settings)
            } footer: {
                Text("Every setting here follows All Terminals, Appearance or Settings until you change it for this window. To change every window, use All Terminals, or Appearance in Settings.")
            }
        }
        .formStyle(.grouped)
        // No extra padding: a grouped form brings its own margins (as All Terminals).
    }

    /// The theme picker's selection: the window's theme while the library has it, else the one it
    /// draws with — All Terminals' — so the picker always shows a theme it lists.
    private func themeSelection(_ value: Binding<String>, global: SettingsManager) -> Binding<String> {
        Binding(
            get: {
                let id = value.wrappedValue
                return global.themeLibrary.activeRecords.contains { $0.id.uuidString == id }
                    ? id : global.currentTheme.id.uuidString
            },
            set: { value.wrappedValue = $0 }
        )
    }

    /// All Terminals' four fonts, and the window's own if a theme or another device gave it another.
    private func fontFamilies(including current: String) -> [String] {
        let offered = ["SF Mono", "Monaco", "Menlo", "Courier New"]
        return offered.contains(current) ? offered : offered + [current]
    }
}
