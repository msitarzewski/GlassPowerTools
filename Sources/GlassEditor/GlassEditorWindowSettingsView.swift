//
//  GlassEditorWindowSettingsView.swift
//  Glass Power Tools — GlassEditor
//
//  **Editor Settings**, from the gear in an editor window's toolbar (W23): **This Window** — the
//  window's own glass and text, built from GlassLayers' shared rows as the terminal's is — then
//  **This File** (the file in front, or the project when no file is open) and **All Editors**,
//  Settings ▸ Editor itself. It opens on This Window, as a terminal's Settings does: the owner, on
//  the Vision Pro, looked for window-level controls first (2026-10-10).
//
//  On a phone there are no windows, so there is no This Window either — as a terminal on a phone
//  has none — and the sheet opens on This File.
//

import SwiftUI
import GlassLayers
import GlassShell
import GlassConnectionUI
import GlassEditorCore

/// The sections of an editor window's Settings, the window's own first.
enum GlassEditorSettingsSection: String, CaseIterable, Hashable {
    case thisWindow
    case thisFile
    case allEditors

    /// This Window only where windows exist; the rest everywhere.
    static func offered(hasWindows: Bool) -> [Self] {
        hasWindows ? allCases : [.thisFile, .allEditors]
    }

    /// Where the sheet opens: on the window's own settings, when there are any to show.
    static func first(hasWindows: Bool) -> Self {
        offered(hasWindows: hasWindows)[0]
    }
}

/// The toolbar gear's sheet.
struct GlassEditorSettingsSheet: View {
    let workspace: GlassEditorWorkspace
    @Binding var isPresented: Bool
    @Environment(GlassEditorRuntime.self) private var runtime: GlassEditorRuntime?
    @State private var section: GlassEditorSettingsSection?

    /// Whether this device has windows: the runtime's answer, asked when it is needed (rule 54).
    private var hasWindows: Bool {
        runtime?.closesWorkspaceWithItsWindow ?? GlassWindowPresentation.canOpenWindows
    }

    var body: some View {
        let offered = GlassEditorSettingsSection.offered(hasWindows: hasWindows)
        // Laid out as every window's Settings sheet is (W27): title, Done, one size.
        GlassSettingsSheet("Editor Settings", doneIdentifier: "editor-settings-done", done: { isPresented = false }) {
            GlassSettingsSections(
                selection: Binding(get: { section ?? GlassEditorSettingsSection.first(hasWindows: hasWindows) },
                                   set: { section = $0 }),
                options: offered,
                title: title(of:),
                pickerIdentifier: "editor-settings-section-picker"
            ) { section in
                switch section {
                case .thisWindow:
                    GlassEditorWindowSettingsView(workspace: workspace)
                case .thisFile:
                    GlassEditorFileSettingsPage(workspace: workspace)
                case .allEditors:
                    GlassEditorSettingsView(preferences: workspace.preferences)
                }
            }
        }
        .accessibilityIdentifier("editor-settings-sheet")
    }

    /// What each section is called. The second is what it shows: the file in front, or the project
    /// when no file is open.
    private func title(of section: GlassEditorSettingsSection) -> String {
        switch section {
        case .thisWindow: "This Window"
        case .thisFile: workspace.selectedDocument == nil && !workspace.projects.isEmpty ? "This Project" : "This File"
        case .allEditors: "All Editors"
        }
    }
}

/// **This Window**: everything an editor window can keep for itself, each over the setting it
/// follows. A change applies at once to every document in the window, and the window keeps it with
/// its project on this device (`GlassEditorWindowSettings`).
struct GlassEditorWindowSettingsView: View {
    let workspace: GlassEditorWorkspace
    @Environment(\.glassLayers) private var layers
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Where each setting lives for every window, as This Window names it.
    enum Source {
        static let appearance = "Appearance"
        static let allEditors = "All Editors"
    }

    var body: some View {
        // **Read here, in the body**, so the page follows the value it sets: a computed `Binding`'s
        // getter does not run while the body is evaluated (the trap met on 2026-09-17).
        let current = workspace.windowSettings
        let settings = Binding(get: { current }, set: { workspace.setWindowSettings($0) })
        let preferences = workspace.preferences

        Form {
            glass(settings)

            Section {
                GlassWindowSettingRow(GlassEditorWindowSettings.fontSize, overrides: settings,
                                      global: preferences.fontSize, inheritsFrom: Source.allEditors) { size in
                    LabeledContent {
                        HStack(spacing: 12) {
                            Button("Smaller", systemImage: "textformat.size.smaller") { size.wrappedValue -= 1 }
                                .labelStyle(.iconOnly)
                                .disabled(size.wrappedValue <= GlassEditorTextOverrides.fontSizeRange.lowerBound)
                            Text("\(Int(size.wrappedValue)) pt")
                                .font(.callout.monospacedDigit())
                                .frame(minWidth: 44)
                            Button("Larger", systemImage: "textformat.size.larger") { size.wrappedValue += 1 }
                                .labelStyle(.iconOnly)
                                .disabled(size.wrappedValue >= GlassEditorTextOverrides.fontSizeRange.upperBound)
                        }
                        .buttonStyle(.bordered)
                    } label: {
                        GlassSettingTitle("Text Size")
                    }
                    .accessibilityIdentifier("editor-window-text-size")
                }
                GlassWindowSettingRow(GlassEditorWindowSettings.showsLineNumbers, overrides: settings,
                                      global: preferences.showsLineNumbers, inheritsFrom: Source.allEditors) { value in
                    GlassSettingLabeled("Show Line Numbers") {
                        Toggle("Show Line Numbers", isOn: value)
                            .accessibilityIdentifier("editor-window-line-numbers")
                    }
                }
                GlassWindowSettingRow(GlassEditorWindowSettings.wrapsLines, overrides: settings,
                                      global: preferences.wrapsLines, inheritsFrom: Source.allEditors) { value in
                    GlassSettingLabeled("Wrap Long Lines") {
                        Toggle("Wrap Long Lines", isOn: value)
                            .accessibilityIdentifier("editor-window-wrap")
                    }
                }
            } header: {
                Text("Text")
            } footer: {
                Text("Every document in this window changes. A project's own text settings, and a file's, still apply over these: see \(workspace.projects.isEmpty ? "This File" : "This File and Project Settings").")
            }

            Section {
                GlassWindowResetButton(overrides: settings)
            } footer: {
                GlassWindowSettingsFooter(
                    follows: "All Editors or Appearance",
                    keeps: "The window keeps its settings with its project, on this device, and has them again the next time the project opens here.")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("editor-window-settings")
    }

    /// The window's glass. **On Vision Pro, Opacity only:** there the window's glass is the
    /// system's own and the layer paints no frost over it (`GlassLayerBackground`, since 7478a39),
    /// so Glass and Material would be controls that change nothing in an editor window.
    @ViewBuilder
    private func glass(_ settings: Binding<GlassWindowOverrides>) -> some View {
        #if os(visionOS)
        Section {
            GlassWindowSettingRow(GlassLayerSettings.opacity, overrides: settings, global: layers.state.opacity,
                                  inheritsFrom: Source.appearance) { value in
                GlassSettingSlider(title: GlassLayerSettings.opacity.title, value: value, detents: [0, 0.5, 1],
                                   leadingAccessibilityLabel: "Transparent", trailingAccessibilityLabel: "Opaque",
                                   accessibilityIdentifier: "window-layers-opacity")
            }
        } header: {
            Text("Appearance")
        } footer: {
            if reduceTransparency {
                Text(GlassWindowGlassFooter.reduceTransparency)
            } else {
                Text("Opacity paints the theme color behind the window's glass and under the text. At 0% the window is visionOS's own glass.")
            }
        }
        .disabled(reduceTransparency)
        #else
        GlassWindowLayerControls(overrides: settings, inheritsFrom: Source.appearance)
        #endif
    }
}
