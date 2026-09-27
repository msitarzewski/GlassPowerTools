//
//  SettingsManager.swift
//  glassdb
//
//  Application settings persistence + SSH key management
//  Pattern adapted from glas.sh SettingsManager
//

import SwiftUI
import Foundation
import Observation
import GlasSecretStore
import os
import GlassConnectionUI
import GlassLayers

enum QueryFailureNotificationPreference: String, Sendable {
    case undecided
    case enabled
    case disabled
}

@MainActor
@Observable
class SettingsManager {
    var maxQueryHistoryItems: Int = 500
    var resultRowLimit: Int = 1000
    /// Appearance is the shell's, not this module's. These are computed over the one
    /// `GlassLayerStore` so a database canvas and a terminal canvas cannot drift apart, exactly as
    /// `GlassTerminal.SettingsManager` already does (`SettingsManager.swift:169-185`). They used to
    /// be stored here with their own `UserDefaults` persistence — a second copy of the same state,
    /// and the reason the Appearance page had nowhere to write when the shell took it over.
    var windowOpacity: Double {
        get { layers.state.effectiveOpacity }
        set { layers.state.opacity = min(max(newValue, 0), 1) }
    }
    var blurBackground: Double {
        get { layers.state.frost }
        set { layers.state.frost = min(max(newValue, 0), 1) }
    }
    var showSidebarByDefault: Bool = true
    var editorFontSize: Double = 14.0
    var dataGridFontSize: Double = 13.0
    var showLineNumbers: Bool = true
    var autoFormatJSONInRecordEditor: Bool = true
    /// On unless turned off (2026-09-27): history is kept on disk, and a literal can be a password
    /// (`ALTER USER … IDENTIFIED BY '…'`) or a customer's data.
    var redactQueryHistoryLiterals: Bool = QueryHistoryRedaction.defaultValue
    private(set) var queryFailureNotificationPreference: QueryFailureNotificationPreference = .undecided
    var savedQueries: [SavedQuery] = []

    private var hasLoaded = false
    private let defaults: UserDefaults

    var queryFailureNotificationsEnabled: Bool {
        queryFailureNotificationPreference == .enabled
    }

    var shouldOfferQueryFailureNotifications: Bool {
        queryFailureNotificationPreference == .undecided
    }

    let layers: GlassLayerStore

    init(
        loadImmediately: Bool = true,
        defaults: UserDefaults = .standard,
        layers: GlassLayerStore? = nil
    ) {
        self.defaults = defaults
        // Without an injected store (tests, previews) the layer state lives in the same suite as
        // the rest of these settings, matching the terminal's arrangement.
        self.layers = layers ?? GlassLayerStore(defaults: defaults)
        if loadImmediately {
            loadIfNeeded()
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        let savedMaxHistory = defaults.integer(forKey: UserDefaultsKeys.maxQueryHistoryItems)
        if savedMaxHistory > 0 {
            maxQueryHistoryItems = savedMaxHistory
        }
        let savedRowLimit = defaults.integer(forKey: UserDefaultsKeys.resultRowLimit)
        if savedRowLimit > 0 {
            resultRowLimit = savedRowLimit
        }
        if defaults.object(forKey: UserDefaultsKeys.showSidebarByDefault) != nil {
            showSidebarByDefault = defaults.bool(forKey: UserDefaultsKeys.showSidebarByDefault)
        }
        if defaults.object(forKey: UserDefaultsKeys.editorFontSize) != nil {
            editorFontSize = defaults.double(forKey: UserDefaultsKeys.editorFontSize)
        }
        if defaults.object(forKey: UserDefaultsKeys.dataGridFontSize) != nil {
            dataGridFontSize = defaults.double(forKey: UserDefaultsKeys.dataGridFontSize)
        }
        if defaults.object(forKey: UserDefaultsKeys.showLineNumbers) != nil {
            showLineNumbers = defaults.bool(forKey: UserDefaultsKeys.showLineNumbers)
        }
        if defaults.object(forKey: UserDefaultsKeys.autoFormatJSONInRecordEditor) != nil {
            autoFormatJSONInRecordEditor = defaults.bool(
                forKey: UserDefaultsKeys.autoFormatJSONInRecordEditor
            )
        }
        if defaults.object(forKey: UserDefaultsKeys.redactQueryHistoryLiterals) != nil {
            redactQueryHistoryLiterals = defaults.bool(forKey: UserDefaultsKeys.redactQueryHistoryLiterals)
        }
        if let rawPreference = defaults.string(
            forKey: UserDefaultsKeys.queryFailureNotificationPreference
        ), let preference = QueryFailureNotificationPreference(rawValue: rawPreference) {
            queryFailureNotificationPreference = preference
        }

        loadSavedQueries()
    }

    func saveSettings() {
        maxQueryHistoryItems = min(max(maxQueryHistoryItems, 1), 10_000)
        resultRowLimit = min(max(resultRowLimit, 1), 100_000)
        editorFontSize = min(max(editorFontSize, 10), 32)
        dataGridFontSize = min(max(dataGridFontSize, 10), 32)
        defaults.set(maxQueryHistoryItems, forKey: UserDefaultsKeys.maxQueryHistoryItems)
        defaults.set(resultRowLimit, forKey: UserDefaultsKeys.resultRowLimit)
        defaults.set(showSidebarByDefault, forKey: UserDefaultsKeys.showSidebarByDefault)
        defaults.set(editorFontSize, forKey: UserDefaultsKeys.editorFontSize)
        defaults.set(dataGridFontSize, forKey: UserDefaultsKeys.dataGridFontSize)
        defaults.set(showLineNumbers, forKey: UserDefaultsKeys.showLineNumbers)
        defaults.set(
            autoFormatJSONInRecordEditor,
            forKey: UserDefaultsKeys.autoFormatJSONInRecordEditor
        )
        defaults.set(redactQueryHistoryLiterals, forKey: UserDefaultsKeys.redactQueryHistoryLiterals)
        defaults.set(
            queryFailureNotificationPreference.rawValue,
            forKey: UserDefaultsKeys.queryFailureNotificationPreference
        )
    }

    func declineQueryFailureNotifications() {
        queryFailureNotificationPreference = .disabled
        saveSettings()
    }

    func disableQueryFailureNotifications() {
        queryFailureNotificationPreference = .disabled
        saveSettings()
    }

    @discardableResult
    func enableQueryFailureNotifications() async -> Bool {
        do {
            let granted = try await GlassSystemNotifications.requestAuthorization()
            queryFailureNotificationPreference = granted ? .enabled : .disabled
            saveSettings()
            return granted
        } catch {
            Logger.settings.error("Notification authorization failed: \(error.localizedDescription)")
            queryFailureNotificationPreference = .disabled
            saveSettings()
            return false
        }
    }

    func postQueryFailureNotification() async {
        guard queryFailureNotificationsEnabled else { return }

        do {
            // Keep SQL, schema names, literals and server diagnostics out of notices.
            let delivered = try await GlassSystemNotifications.post(
                title: "Query Failed",
                body: "A database query failed. Open the app to review the error.",
                threadIdentifier: "app.glassdb.query-failures"
            )
            if !delivered {
                queryFailureNotificationPreference = .disabled
                saveSettings()
            }
        } catch {
            Logger.settings.error("Query failure notification could not be delivered: \(error.localizedDescription)")
        }
    }

    // MARK: - Saved Queries

    func loadSavedQueries() {
        guard let data = defaults.data(forKey: UserDefaultsKeys.savedQueries) else {
            savedQueries = []
            return
        }
        do {
            savedQueries = try JSONDecoder().decode([SavedQuery].self, from: data)
        } catch {
            Logger.settings.error("Failed to load saved queries: \(error)")
            savedQueries = []
        }
    }

    private func saveSavedQueries() {
        do {
            let data = try JSONEncoder().encode(savedQueries)
            defaults.set(data, forKey: UserDefaultsKeys.savedQueries)
        } catch {
            Logger.settings.error("Failed to save queries: \(error)")
        }
    }

    func addSavedQuery(_ query: SavedQuery) {
        savedQueries.append(query)
        saveSavedQueries()
    }

    func updateSavedQuery(_ query: SavedQuery) {
        if let index = savedQueries.firstIndex(where: { $0.id == query.id }) {
            savedQueries[index] = query
            saveSavedQueries()
        }
    }

    func deleteSavedQuery(_ query: SavedQuery) {
        savedQueries.removeAll { $0.id == query.id }
        saveSavedQueries()
    }

    func useSavedQuery(_ queryID: UUID) {
        if let index = savedQueries.firstIndex(where: { $0.id == queryID }) {
            savedQueries[index].lastUsed = Date()
            savedQueries[index].useCount += 1
            saveSavedQueries()
        }
    }

    // MARK: - SSH Keys
    //
    // Deliberately absent. glassdb kept a second SSH key catalog and a second import sheet
    // (`../glassdb/glassdb/SettingsManager.swift:347-664`, `SettingsView.swift:320-579`),
    // merged across its own and the App Group's `sshKeys` suites. The merged product has one
    // catalog, shown on the `.ssh` capability's Connections settings page. A database service
    // authenticates with a database password and tunnels through the host (D7), so it needs
    // neither the keys nor the page.
}
