//
//  SettingsView.swift
//  glassdb
//
//  App settings window
//

import SwiftUI
import GlassConnectionUI
import GlasSecretStore
import GlassDBKit

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager


    var body: some View {
        @Bindable var settings = settingsManager

        Group {
            #if os(macOS)
            macSettings
            #elseif os(iOS)
            iOSSettings
            #else
            spatialSettings
            #endif
        }
        .onChange(of: settings.resultRowLimit) { _, _ in settingsManager.saveSettings() }
        .onChange(of: settings.maxQueryHistoryItems) { _, _ in settingsManager.saveSettings() }
        .onChange(of: settings.redactQueryHistoryLiterals) { _, _ in settingsManager.saveSettings() }
        .onChange(of: settings.editorFontSize) { _, _ in settingsManager.saveSettings() }
        .onChange(of: settings.dataGridFontSize) { _, _ in settingsManager.saveSettings() }
        .onChange(of: settings.showLineNumbers) { _, _ in settingsManager.saveSettings() }
        .onChange(of: settings.autoFormatJSONInRecordEditor) { _, _ in settingsManager.saveSettings() }
        .onChange(of: settings.showSidebarByDefault) { _, _ in settingsManager.saveSettings() }
    }

    #if os(macOS)
    private var macSettings: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                generalSettingsForm
            }

            Tab("Editor", systemImage: "text.cursor") {
                editorSettingsForm
            }

            Tab("About", systemImage: "info.circle") {
                aboutSettingsForm
            }
        }
        .accessibilityIdentifier("settings.tab-view")
    }
    #endif

    #if os(iOS)
    private var iOSSettings: some View {
        Form {
            querySection
            editorSection
            iOSWorkspaceSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var iOSWorkspaceSection: some View {
        Section {
            @Bindable var settings = settingsManager
            Toggle("Show schema sidebar when space allows", isOn: $settings.showSidebarByDefault)
        } header: {
            Text("Workspace")
        } footer: {
            Text("On iPad, the schema browser starts beside the workspace when the window is wide enough. iPhone always uses compact navigation.")
        }
    }
    #endif

    private var spatialSettings: some View {
        NavigationStack {
            Form {
                querySection
                editorSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    private var generalSettingsForm: some View {
        Form {
            querySection

            Section("Windows") {
                Text("New database workspaces show the schema sidebar. Use the sidebar button to hide it while working.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var editorSettingsForm: some View {
        Form {
            editorSection
        }
        .formStyle(.grouped)
    }



    private var aboutSettingsForm: some View {
        Form {
            aboutSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var querySection: some View {
        @Bindable var settings = settingsManager

        Section {
            BoundedStepperRow(
                title: "Result row limit",
                value: $settings.resultRowLimit,
                range: 1...100_000,
                step: 100,
                accessibilityHint: "Limits rows returned to the results grid"
            )
            BoundedStepperRow(
                title: "Query history limit",
                value: $settings.maxQueryHistoryItems,
                range: 1...10_000,
                step: 100,
                accessibilityHint: "Limits locally retained query history"
            )
            Toggle("Redact literals in query history", isOn: $settings.redactQueryHistoryLiterals)
                .help("Replaces quoted strings and numeric values before queries are stored in history.")
            Toggle(
                "Notify when a query fails",
                isOn: Binding(
                    get: { settingsManager.queryFailureNotificationsEnabled },
                    set: { enabled in
                        if enabled {
                            Task { await settingsManager.enableQueryFailureNotifications() }
                        } else {
                            settingsManager.disableQueryFailureNotifications()
                        }
                    }
                )
            )
            .help("Shows a private system notification without SQL, schema names, or server diagnostics.")
        } header: {
            Text("Query")
        } footer: {
            Text("Limits protect memory use. Literal redaction applies only to history; it never changes SQL sent to a database. Query-failure notifications contain no database details.")
        }
    }

    @ViewBuilder
    private var editorSection: some View {
        @Bindable var settings = settingsManager

        Section {
            BoundedDoubleStepperRow(
                title: "SQL editor text",
                value: $settings.editorFontSize,
                range: 10...32,
                suffix: "pt"
            )
            BoundedDoubleStepperRow(
                title: "Results grid text",
                value: $settings.dataGridFontSize,
                range: 10...32,
                suffix: "pt"
            )
            Toggle("Show line numbers", isOn: $settings.showLineNumbers)
            Toggle(
                "Format JSON automatically while editing",
                isOn: $settings.autoFormatJSONInRecordEditor
            )
            .help("Pretty-prints JSON and JSONB values when the record editor opens.")
        } header: {
            Text("Editor")
        } footer: {
            Text("Text sizes apply to newly rendered editors and results grids. Valid JSON is always compacted before it is sent to the database, regardless of its editor formatting.")
        }
    }


    @ViewBuilder
    private var aboutSection: some View {
        Section("Database") {
            LabeledContent("Version", value: "0.1.0")
            LabeledContent("Database engines", value: "MySQL, PostgreSQL, SQLite")
            LabeledContent("Platforms", value: "Apple silicon")
        }
    }

    // MARK: - SSH Keys Section


}

private struct BoundedStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let accessibilityHint: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(value, format: .number.grouping(.automatic))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 64, alignment: .trailing)
                    .accessibilityHidden(true)
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel(title)
                    .accessibilityValue(Text(value, format: .number))
                    .accessibilityHint(accessibilityHint)
            }
        }
    }
}

private struct BoundedDoubleStepperRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("\(Int(value.rounded())) \(suffix)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 52, alignment: .trailing)
                    .accessibilityHidden(true)
                Stepper("", value: $value, in: range, step: 1)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel(title)
                    .accessibilityValue("\(Int(value.rounded())) \(suffix)")
            }
        }
    }
}

// MARK: - Add SSH Key Sheet

