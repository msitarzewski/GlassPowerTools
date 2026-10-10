//
//  DatabaseWindowSettingsView.swift
//  Glass Power Tools — GlassDatabase
//
//  **This Window** (W24): every setting a database window can keep for itself, built from
//  GlassLayers' shared rows (W22) the way the terminal's is. Each row's control shows what the
//  window uses now; under it, "Same as All Databases" (or Appearance) until it is changed here,
//  then "This window only" with its own Reset. Reset This Window, at the end, returns them all.
//
//  Reached from the gear in the window's toolbar, which opens **Database Settings**: This Window
//  first, then All Databases (the same page as Settings ▸ Databases). On the Mac the gear was a
//  `SettingsLink` to the app's Settings, as the terminal's local tab gear was until W20; the app's
//  Settings stay on ⌘,. On iPhone the workspace is a screen, not a window, so the gear opens All
//  Databases alone — as the terminal offers This Window on iPad and not on iPhone.
//

import SwiftUI
import GlassLayers
import GlassConnectionUI
#if canImport(UIKit)
import UIKit
#endif

/// The sections of a database window's Settings, the window's own first: the owner, on the Vision
/// Pro, found the terminal's window-level controls only once they came first and said what they
/// change (2026-10-10).
enum DatabaseSettingsModalTab: String, CaseIterable, Hashable {
    case thisWindow
    case allDatabases

    var title: String {
        switch self {
        case .thisWindow: "This Window"
        case .allDatabases: "All Databases"
        }
    }

    /// This Window only where the workspace is a window that keeps settings.
    static func offered(hasWindowSettings: Bool) -> [Self] {
        hasWindowSettings ? allCases : [.allDatabases]
    }

    static func firstTab(hasWindowSettings: Bool) -> Self {
        offered(hasWindowSettings: hasWindowSettings)[0]
    }
}

/// Opens the Settings of the database window a view is in (W24). The workspace sets it, so the
/// gear each detail surface puts in its own toolbar on the Mac opens the window's Settings.
struct DatabaseShowSettingsAction {
    let action: @MainActor () -> Void

    @MainActor func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var databaseShowSettings: DatabaseShowSettingsAction? = nil
}

/// **Database Settings**, from the gear in a database window's toolbar: the window's own settings
/// (**This Window**) and the settings every database window shares (**All Databases**).
struct DatabaseSettingsSheet: View {
    /// The window's own settings; nil where the workspace is not a window (iPhone).
    let windowSettings: Binding<GlassWindowOverrides>?
    let done: () -> Void

    @Environment(SettingsManager.self) private var settingsManager
    @State private var tab: DatabaseSettingsModalTab

    init(windowSettings: Binding<GlassWindowOverrides>?, done: @escaping () -> Void) {
        self.windowSettings = windowSettings
        self.done = done
        _tab = State(initialValue: .firstTab(hasWindowSettings: windowSettings != nil))
    }

    var body: some View {
        NavigationStack {
            sections
                .navigationTitle("Database Settings")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: done)
                            .accessibilityIdentifier("database-settings-done")
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #else
        .frame(width: 760, height: 560)
        #endif
    }

    @ViewBuilder private var sections: some View {
        #if os(iOS)
        if let windowSettings {
            List {
                NavigationLink("This Window") {
                    DatabaseWindowSettingsView(settings: windowSettings)
                        .environment(settingsManager)
                        .navigationTitle("This Window")
                }
                NavigationLink("All Databases") {
                    allDatabases.navigationTitle("All Databases")
                }
            }
        } else {
            allDatabases
        }
        #else
        GlassSettingsSections(
            selection: $tab,
            options: DatabaseSettingsModalTab.offered(hasWindowSettings: windowSettings != nil),
            title: { $0.title },
            pickerIdentifier: "database-settings-section-picker"
        ) { tab in
            switch tab {
            case .thisWindow:
                if let windowSettings {
                    DatabaseWindowSettingsView(settings: windowSettings)
                        .environment(settingsManager)
                }
            case .allDatabases:
                allDatabases
            }
        }
        #endif
    }

    private var allDatabases: some View {
        SettingsView(isShellPage: true)
            .environment(settingsManager)
    }
}

/// This Window: the window's own settings, each over the setting it follows.
struct DatabaseWindowSettingsView: View {
    @Binding var settings: GlassWindowOverrides
    @Environment(SettingsManager.self) private var settingsManager

    /// Where each kind of setting lives for every window, as This Window names it.
    enum Source {
        static let appearance = "Appearance"
        static let allDatabases = "All Databases"
    }

    init(settings: Binding<GlassWindowOverrides>) {
        _settings = settings
    }

    /// Whether this device's database workspace is a window with settings of its own: everywhere
    /// but iPhone, where it is a screen in the library's window.
    @MainActor static var isOffered: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
        #else
        true
        #endif
    }

    var body: some View {
        let global = settingsManager
        let sizes = DatabaseWindowSettings.textSizes

        Form {
            Section {
                GlassWindowSettingRow(GlassLayerSettings.opacity, overrides: $settings,
                                      global: global.windowOpacity, inheritsFrom: Source.appearance) { value in
                    GlassSettingSlider(title: "Opacity", value: value, detents: [0, 0.5, 1],
                                       leadingAccessibilityLabel: "Transparent", trailingAccessibilityLabel: "Opaque",
                                       accessibilityIdentifier: "database-window-opacity")
                }
                GlassWindowSettingRow(GlassLayerSettings.frost, overrides: $settings,
                                      global: global.blurBackground, inheritsFrom: Source.appearance) { value in
                    GlassSettingSlider(title: "Frost", value: value, detents: [0, 0.5, 1],
                                       leadingAccessibilityLabel: "Clear", trailingAccessibilityLabel: "Frosted",
                                       accessibilityIdentifier: "database-window-frost")
                }
            } header: {
                Text("Glass")
            } footer: {
                Text("Only this window changes. Opacity paints the canvas behind its tabs, editor and results; Frost blurs what is behind the window. The schema sidebar keeps the system's material.")
            }

            Section {
                GlassWindowSettingRow(DatabaseWindowSettings.resultRowLimit, overrides: $settings,
                                      global: global.resultRowLimit, inheritsFrom: Source.allDatabases) { value in
                    BoundedStepperRow(title: "Result row limit", value: value,
                                      range: SQLHighlighter.validEditorResultRowLimits, step: 100,
                                      accessibilityHint: "Limits rows returned to this window's results grid")
                }
            } header: {
                Text("Query")
            }

            Section {
                GlassWindowSettingRow(DatabaseWindowSettings.editorFontSize, overrides: $settings,
                                      global: global.editorFontSize, inheritsFrom: Source.allDatabases) { value in
                    BoundedDoubleStepperRow(title: "SQL editor text", value: value, range: sizes, suffix: "pt")
                }
                GlassWindowSettingRow(DatabaseWindowSettings.dataGridFontSize, overrides: $settings,
                                      global: global.dataGridFontSize, inheritsFrom: Source.allDatabases) { value in
                    BoundedDoubleStepperRow(title: "Results grid text", value: value, range: sizes, suffix: "pt")
                }
                GlassWindowSettingRow(DatabaseWindowSettings.showLineNumbers, overrides: $settings,
                                      global: global.showLineNumbers, inheritsFrom: Source.allDatabases) { value in
                    Toggle("Show line numbers", isOn: value)
                }
                GlassWindowSettingRow(DatabaseWindowSettings.formatsJSON, overrides: $settings,
                                      global: global.autoFormatJSONInRecordEditor,
                                      inheritsFrom: Source.allDatabases) { value in
                    Toggle("Format JSON automatically while editing", isOn: value)
                }
            } header: {
                Text("Editor")
            }

            Section {
                GlassWindowResetButton(overrides: $settings)
            } footer: {
                Text("Every setting here follows All Databases or Appearance until you change it for this window. The next window on this database opens with them, after a relaunch too, and Open in New Window gives its window this one's. To change every window, use All Databases, or Appearance in Settings.")
            }
        }
        .formStyle(.grouped)
    }
}
