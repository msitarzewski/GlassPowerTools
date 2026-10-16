//
//  TerminalWindowSettingsView.swift
//  Glass Power Tools — GlassTerminal
//
//  **This Window** (W20, W22, W27): every setting a terminal window can keep for itself, built
//  from GlassLayers' shared rows. Each row's control shows what the window uses now; once it is
//  changed here, a ↺ beside its name returns it to All Terminals (or Appearance, or Settings).
//  Reset This Window, at the end, returns them all. A change applies at once to every tab in the
//  window, and stays with the window.
//
//  Not offered on Vision Pro, though stored and synced for other devices: Material, since the
//  window's glass there is Apple's own, and Interactive Glass, which changes nothing since the
//  window draws that glass itself (D59).
//

import SwiftUI
import GlassLayers
import GlassConnectionUI
import GlassTerminalEmulator

/// This Window: the window's own settings, each over the setting it follows.
struct TerminalOverridesSettingsView: View {
    @Binding var settings: GlassWindowOverrides
    @Environment(SettingsManager.self) private var settingsManager
    /// The window's workgroup, whose saved Workgroup's Auto-focus on activity it follows (visionOS).
    @Environment(\.terminalWorkgroupID) private var workgroupID

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

    /// What the window follows until it sets Auto-focus on activity: its saved Workgroup's.
    private var workgroupFollowsActivity: Bool {
        settingsManager.layoutPresets.first { $0.id == workgroupID }?.autoFocusOnActivity ?? false
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
                    GlassSettingSlider(title: GlassLayerSettings.frost.title, value: value, detents: [0, 0.5, 1],
                                       leadingAccessibilityLabel: "No glass", trailingAccessibilityLabel: "Full glass",
                                       accessibilityIdentifier: "terminal-window-blur")
                }
                #if os(iOS)
                // The canvas's material on iPad. A Mac terminal blurs with the window behind it, and
                // a Vision Pro window's glass is Apple's own, so neither has a material to choose.
                GlassWindowSettingRow(GlassLayerSettings.material, overrides: $settings,
                                      global: GlassLayerMaterial(rawValue: global.glassFrost) ?? GlassLayerState.default.material,
                                      inheritsFrom: Source.appearance) { value in
                    GlassSettingLabeled(GlassLayerSettings.material.title) {
                        Picker(GlassLayerSettings.material.title, selection: value) {
                            ForEach(GlassLayerMaterial.allCases) { material in
                                Text(material.title).tag(material)
                            }
                        }
                        .accessibilityIdentifier("terminal-window-frost")
                    }
                }
                #endif
                GlassWindowSettingRow(TerminalWindowSettings.tint, overrides: $settings,
                                      global: global.glassTint, inheritsFrom: Source.allTerminals) { value in
                    GlassTintPicker(value: value)
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text(GlassWindowGlassFooter.text(opacity: "paints the terminal's background color",
                                                 clearAlso: "with no tint"))
            }

            Section("Theme") {
                GlassWindowSettingRow(TerminalWindowSettings.theme, overrides: $settings,
                                      global: global.currentTheme.id.uuidString, inheritsFrom: Source.allTerminals) { value in
                    GlassSettingLabeled("Theme") {
                        Picker("Theme", selection: themeSelection(value, global: global)) {
                            ForEach(global.themeLibrary.activeRecords) { record in
                                Text(record.theme.name).tag(record.id.uuidString)
                            }
                        }
                        .accessibilityIdentifier("terminal-window-theme")
                    }
                }
                if TerminalWindowProfile.isMissingTheme(settings, library: global.themeLibrary) {
                    Text("This window's theme isn't on this device yet, so it uses All Terminals' theme until it arrives.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GlassWindowSettingRow(TerminalWindowSettings.fontFamily, overrides: $settings,
                                      global: themeFont.fontName, inheritsFrom: Source.allTerminals) { value in
                    GlassSettingLabeled("Font Family") {
                        Picker("Font Family", selection: value) {
                            ForEach(fontFamilies(including: value.wrappedValue), id: \.self) { family in
                                Text(family).tag(family)
                            }
                        }
                        .accessibilityIdentifier("terminal-window-font-family")
                    }
                }
                GlassWindowSettingRow(TerminalWindowSettings.fontSize, overrides: $settings,
                                      global: Double(themeFont.fontSize), inheritsFrom: Source.allTerminals) { value in
                    GlassSettingLabeled("Font Size") {
                        Slider(value: value, in: 10...24, step: 1) {
                            Text("Font Size")
                        } minimumValueLabel: {
                            Text("10")
                        } maximumValueLabel: {
                            Text("24")
                        }
                        .frame(maxWidth: 280)
                        .accessibilityValue("\(Int(value.wrappedValue)) points")
                        .accessibilityIdentifier("terminal-window-font-size")
                    }
                }
            }

            Section("Cursor") {
                GlassWindowSettingRow(TerminalWindowSettings.cursorStyle, overrides: $settings,
                                      global: global.cursorStyle, inheritsFrom: Source.allTerminals) { value in
                    GlassSettingLabeled("Cursor Style") {
                        Picker("Cursor Style", selection: value) {
                            ForEach(TerminalWindowSettings.cursorStyles, id: \.self) { style in
                                Text(style).tag(style)
                            }
                        }
                        .accessibilityIdentifier("terminal-window-cursor-style")
                    }
                }
                GlassWindowSettingRow(TerminalWindowSettings.blinkingCursor, overrides: $settings,
                                      global: global.blinkingCursor, inheritsFrom: Source.allTerminals) { value in
                    GlassSettingLabeled("Blinking cursor") { Toggle("Blinking cursor", isOn: value) }
                }
            }

            #if os(macOS)
            Section {
                // A printed path's file over the terminal (2026-10-16), this window's way.
                GlassWindowSettingRow(TerminalWindowSettings.pathPreviews, overrides: $settings,
                                      global: global.pathPreviews.rawValue, inheritsFrom: Source.allTerminals) { value in
                    GlassSettingLabeled("Show previews") {
                        Picker("Show previews", selection: value) {
                            ForEach(TerminalPathPreviews.allCases, id: \.self) { choice in
                                Text(choice.title).tag(choice.rawValue)
                            }
                        }
                        .accessibilityIdentifier("terminal-window-path-previews")
                    }
                }
            }
            #endif

            Section {
                GlassWindowSettingRow(TerminalWindowSettings.bell, overrides: $settings,
                                      global: global.bellEnabled, inheritsFrom: Source.settings) { value in
                    GlassSettingLabeled("Bell enabled") { Toggle("Bell enabled", isOn: value) }
                }
                GlassWindowSettingRow(TerminalWindowSettings.visualBell, overrides: $settings,
                                      global: global.visualBell, inheritsFrom: Source.settings) { value in
                    GlassSettingLabeled("Visual bell") {
                        Toggle("Visual bell", isOn: value)
                            .disabled(!effective.bellEnabled)
                    }
                }
                GlassWindowSettingRow(TerminalWindowSettings.keepsScrollback, overrides: $settings,
                                      global: global.saveScrollback, inheritsFrom: Source.settings) { value in
                    GlassSettingLabeled("Keep scrollback during session") {
                        Toggle("Keep scrollback during session", isOn: value)
                    }
                }
                GlassWindowSettingRow(TerminalWindowSettings.scrollbackLines, overrides: $settings,
                                      global: global.maxScrollbackLines, inheritsFrom: Source.settings) { value in
                    GlassSettingLabeled("Max scrollback lines") {
                        HStack(spacing: 8) {
                            Text(value.wrappedValue, format: .number.grouping(.automatic))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Stepper("Max scrollback lines", value: value, in: 1000...100_000, step: 1000)
                                .fixedSize()
                                .accessibilityValue(Text(value.wrappedValue, format: .number))
                        }
                        .disabled(effective.scrollbackLines == 0)
                    }
                }
            } header: {
                Text("Bell and Scrollback")
            } footer: {
                Text("For every terminal, these are in Settings ▸ Connections.")
            }

            #if os(visionOS)
            Section {
                GlassWindowSettingRow(TerminalWindowSettings.autoFocusOnActivity, overrides: $settings,
                                      global: workgroupFollowsActivity, inheritsFrom: "Workgroup") { value in
                    GlassSettingLabeled("Auto-focus on activity") {
                        Toggle("Auto-focus on activity", isOn: value)
                            .accessibilityIdentifier("terminal-window-auto-focus")
                    }
                }
            } header: {
                Text("Activity")
            } footer: {
                Text("While a terminal in this window prints, the grid and carousel bring it forward, and the window's orb pulses.")
            }
            #endif

            Section {
                GlassWindowResetButton(overrides: $settings)
            } footer: {
                GlassWindowSettingsFooter(
                    follows: "All Terminals, Appearance or Settings",
                    keeps: "Every tab in this window changes, and the window keeps its settings after a relaunch.")
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
