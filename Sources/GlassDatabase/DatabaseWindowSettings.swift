//
//  DatabaseWindowSettings.swift
//  Glass Power Tools — GlassDatabase
//
//  W24 (owner, 2026-10-10): "the original idea was that anything in the system settings could be
//  overridden per window", for every kind of window. A database window keeps a
//  `GlassWindowOverrides` (GlassLayers, W22): its glass, which is Appearance's own
//  (`GlassLayerSettings`), and every database setting that can sensibly differ between windows —
//  the result row limit, the SQL editor's and the results grid's text sizes, line numbers, and
//  JSON formatting in the record editor. Each resolves as the window's value, else the setting's,
//  for every surface in the window (`DatabaseWindowProfile`).
//
//  **Where a window keeps them.** A database window is never reopened at launch: its scene has
//  `.restorationBehavior(.disabled)` and `.defaultLaunchBehavior(.suppressed)`
//  (`GlassDatabaseScenes.swift`), and its session ends with the app. So it has no record of its own
//  that outlives it. What does outlive it is the database it showed — its SQL drafts are kept per
//  connection for the same reason (`SQLDraftStore`). So a window's settings are kept for its
//  database (`DatabaseWindowSettingsStore`): the next window on that database opens with them,
//  after a relaunch too. **Open in New Window** carries its own window's settings instead. Kept on
//  this device only.
//
//  Not per window, and why:
//  - Appearance's **Material**: the database canvas frosts with a material of its own — AppKit's
//    under-window material on the Mac, ultra-thin elsewhere (`DatabaseWorkspaceBackground`) — and
//    has never followed Appearance's Material, so a window's Material would change nothing.
//  - **Query history limit** and **Redact literals in query history**: they govern the one history
//    this device keeps for every window. A window can't keep a history of its own, nor redact what
//    every window shares differently.
//  - **Notify when a query fails**: the system's notification permission, which is the app's.
//  - **Show schema sidebar when space allows** (iPad): it only decides how a new window starts; a
//    window that is open has its own sidebar button.
//  - **Read-only** and **rows per page**: a service's own settings, set on the service. Read-only is
//    a promise about the connection, and no window may loosen it.
//  - Connections, credentials, TLS and tunnels: they belong to the service and its machine.
//

import Foundation
import os
import GlassLayers

/// The database settings a window can override (W24), each under a stable key: stored with the
/// database the window shows. The window's glass is Appearance's (`GlassLayerSettings`).
nonisolated enum DatabaseWindowSettings {
    /// The text sizes All Databases offers (`SettingsManager.saveSettings` clamps to the same).
    static let textSizes: ClosedRange<Double> = 10...32

    static let resultRowLimit = GlassWindowSetting<Int>("database.resultRowLimit", title: "Result row limit") {
        let limits = SQLHighlighter.validEditorResultRowLimits
        return min(limits.upperBound, max(limits.lowerBound, $0))
    }
    static let editorFontSize = GlassWindowSetting<Double>("database.editorFontSize", title: "SQL editor text") {
        textSize($0)
    }
    static let dataGridFontSize = GlassWindowSetting<Double>("database.dataGridFontSize", title: "Results grid text") {
        textSize($0)
    }
    static let showLineNumbers = GlassWindowSetting<Bool>("database.showLineNumbers", title: "Show line numbers")
    static let formatsJSON = GlassWindowSetting<Bool>("database.formatsJSON",
                                                      title: "Format JSON automatically while editing")

    /// Every database key a window can set, beside Appearance's.
    static var keys: Set<String> {
        [resultRowLimit.key, editorFontSize.key, dataGridFontSize.key, showLineNumbers.key, formatsJSON.key]
    }

    private static func textSize(_ size: Double) -> Double? {
        size.isFinite ? min(textSizes.upperBound, max(textSizes.lowerBound, size.rounded())) : nil
    }
}

// MARK: - What a database window uses

/// Everything a database window is drawn and behaves with (W24): each of its settings over the
/// one it overrides. The same for the workspace's canvas and tab strip, the SQL editor, the
/// results grid, the structure's DDL and the record editor, so a window's surfaces always agree.
struct DatabaseWindowProfile: Equatable {
    /// The canvas's paint and frost: Appearance's opacity and frost, the window's over the app's.
    let glass: DatabaseGlassAppearance
    let resultRowLimit: Int
    let editorFontSize: Double
    let dataGridFontSize: Double
    let showLineNumbers: Bool
    let formatsJSON: Bool

    init(window: GlassWindowOverrides, appearance: GlassLayerState, resultRowLimit: Int,
         editorFontSize: Double, dataGridFontSize: Double, showLineNumbers: Bool, formatsJSON: Bool) {
        let layers = appearance.overlaid(by: window)
        glass = DatabaseGlassAppearance(opacity: layers.effectiveOpacity, blur: layers.frost)
        self.resultRowLimit = window.value(of: DatabaseWindowSettings.resultRowLimit, over: resultRowLimit)
        self.editorFontSize = window.value(of: DatabaseWindowSettings.editorFontSize, over: editorFontSize)
        self.dataGridFontSize = window.value(of: DatabaseWindowSettings.dataGridFontSize, over: dataGridFontSize)
        self.showLineNumbers = window.value(of: DatabaseWindowSettings.showLineNumbers, over: showLineNumbers)
        self.formatsJSON = window.value(of: DatabaseWindowSettings.formatsJSON, over: formatsJSON)
    }

    /// A database window with `window`'s settings. Read in a view's body, it follows both: the
    /// settings are observable, and so is whatever holds the window's.
    @MainActor
    static func resolved(_ window: GlassWindowOverrides, settings: SettingsManager) -> DatabaseWindowProfile {
        DatabaseWindowProfile(window: window, appearance: settings.layers.state,
                              resultRowLimit: settings.resultRowLimit,
                              editorFontSize: settings.editorFontSize,
                              dataGridFontSize: settings.dataGridFontSize,
                              showLineNumbers: settings.showLineNumbers,
                              formatsJSON: settings.autoFormatJSONInRecordEditor)
    }
}

// MARK: - Kept for the database

/// One database's window settings, as `DatabaseWindowSettingsStore` keeps them: the connection
/// (the service's endpoint id, which the library keeps stable) and only what its window set.
struct DatabaseWindowRecord: Codable, Equatable {
    let connectionID: UUID
    var windowSettings: GlassWindowOverrides

    private enum CodingKeys: String, CodingKey {
        case connectionID = "connection"
        case windowSettings
    }

    init(connectionID: UUID, windowSettings: GlassWindowOverrides) {
        self.connectionID = connectionID
        self.windowSettings = windowSettings
    }

    /// Leniently, as every window's settings are read: settings that can't be read are a window
    /// that sets nothing, never a record that fails.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connectionID = try container.decode(UUID.self, forKey: .connectionID)
        windowSettings = GlassWindowOverrides.lenientlyDecoded(from: container, forKey: .windowSettings)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(connectionID, forKey: .connectionID)
        try container.encodeIfNotEmpty(windowSettings, forKey: .windowSettings)
    }
}

/// A database window's settings, kept for its database once it closes (W24): database windows are
/// not reopened at launch, so the next window on the same database is the one that takes them.
/// Written on every change, so a quit loses nothing; read once, when the store is made.
@MainActor
final class DatabaseWindowSettingsStore {
    static let shared = DatabaseWindowSettingsStore()
    /// More databases than anyone keeps windows for. Past it, the longest unchanged goes first.
    static let maximumCount = 100

    private let defaults: UserDefaults
    /// Oldest change first.
    private(set) var records: [DatabaseWindowRecord]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = Self.decode(defaults.data(forKey: UserDefaultsKeys.windowSettings))
    }

    /// The settings the last window on this database kept; none when it kept none.
    func settings(for connectionID: UUID) -> GlassWindowOverrides {
        records.last { $0.connectionID == connectionID }?.windowSettings ?? GlassWindowOverrides()
    }

    /// What a workspace window opens with: the settings its request carries (Open in New Window
    /// carries its own window's), else those its database kept, else none.
    func opening(_ request: DatabaseWorkspaceWindowRequest, connectionID: UUID?) -> GlassWindowOverrides {
        if let carried = request.windowSettings { return carried }
        return connectionID.map(settings(for:)) ?? GlassWindowOverrides()
    }

    /// Keeps `settings` as this database's; a window that sets nothing leaves no record.
    func record(_ settings: GlassWindowOverrides, for connectionID: UUID) {
        var updated = records.filter { $0.connectionID != connectionID }
        if !settings.isEmpty {
            updated.append(DatabaseWindowRecord(connectionID: connectionID, windowSettings: settings))
        }
        updated = Array(updated.suffix(Self.maximumCount))
        guard updated != records else { return }
        records = updated
        save()
    }

    private func save() {
        guard !records.isEmpty else {
            defaults.removeObject(forKey: UserDefaultsKeys.windowSettings)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(records), forKey: UserDefaultsKeys.windowSettings)
        } catch {
            Logger.settings.error("Database window settings could not be saved: \(error.localizedDescription)")
        }
    }

    /// Leniently: anything that isn't a list is no records, and a record that can't be read is
    /// dropped on its own, never with the rest.
    static func decode(_ data: Data?) -> [DatabaseWindowRecord] {
        guard let data, let list = try? JSONDecoder().decode([LenientRecord].self, from: data) else { return [] }
        let kept = list.compactMap(\.record).filter { !$0.windowSettings.isEmpty }
        return Array(kept.suffix(maximumCount))
    }

    private struct LenientRecord: Decodable {
        let record: DatabaseWindowRecord?

        init(from decoder: any Decoder) {
            record = try? DatabaseWindowRecord(from: decoder)
        }
    }
}

extension DatabaseSessionManager {
    /// What the workspace window `request` opens (W24): the settings it carries, else those kept
    /// for the database its session shows.
    func openingWindowSettings(for request: DatabaseWorkspaceWindowRequest,
                               store: DatabaseWindowSettingsStore = .shared) -> GlassWindowOverrides {
        store.opening(request, connectionID: session(for: request.sessionID)?.connectionConfig.id)
    }
}
