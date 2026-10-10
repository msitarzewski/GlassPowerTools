import Foundation
import Testing
import GlassLayers
@testable import GlassDatabase

/// W24 (owner, 2026-10-10): "the original idea was that anything in the system settings could be
/// overridden per window." A database window keeps its own glass, result row limit, text sizes,
/// line numbers and JSON formatting; every surface in it resolves them the same way; and, since a
/// database window is not reopened at launch, its database keeps them for its next window.
@MainActor
@Suite("A database window keeps its own settings")
struct DatabaseWindowSettingsTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults.forTest(suiteName: "DatabaseWindowSettingsTests-\(UUID().uuidString)"))
    }

    /// All Databases and Appearance, as a person might have set them.
    private func allDatabases(_ defaults: UserDefaults) -> SettingsManager {
        let layers = GlassLayerStore(defaults: defaults, legacyDefaults: [])
        layers.state = GlassLayerState(opacity: 0.8, frost: 0.2, material: .regular)
        let settings = SettingsManager(loadImmediately: false, defaults: defaults, layers: layers)
        settings.resultRowLimit = 1000
        settings.editorFontSize = 14
        settings.dataGridFontSize = 13
        settings.showLineNumbers = true
        settings.autoFormatJSONInRecordEditor = true
        return settings
    }

    /// A window that sets something of everything, each different from `allDatabases`.
    private var everything: GlassWindowOverrides {
        var window = GlassWindowOverrides()
        window[GlassLayerSettings.opacity] = 0.3
        window[GlassLayerSettings.frost] = 0.9
        window[DatabaseWindowSettings.resultRowLimit] = 250
        window[DatabaseWindowSettings.editorFontSize] = 20
        window[DatabaseWindowSettings.dataGridFontSize] = 18
        window[DatabaseWindowSettings.showLineNumbers] = false
        window[DatabaseWindowSettings.formatsJSON] = false
        return window
    }

    /// A profile's fields by name, to say which of them a setting moved.
    private func fields(_ profile: DatabaseWindowProfile) -> [String: AnyHashable] {
        ["opacity": profile.glass.opacity, "frost": profile.glass.blur, "rows": profile.resultRowLimit,
         "editor": profile.editorFontSize, "grid": profile.dataGridFontSize,
         "lineNumbers": profile.showLineNumbers, "json": profile.formatsJSON]
    }

    // MARK: Resolving

    @Test("a window that sets nothing draws and behaves exactly as All Databases and Appearance")
    func emptyWindowFollowsEverything() throws {
        let settings = allDatabases(try defaults())
        let profile = DatabaseWindowProfile.resolved(GlassWindowOverrides(), settings: settings)
        #expect(profile.glass == DatabaseGlassAppearance(opacity: settings.windowOpacity, blur: settings.blurBackground))
        #expect(profile.glass == DatabaseGlassAppearance(opacity: 0.8, blur: 0.2))
        #expect(profile.resultRowLimit == 1000)
        #expect(profile.editorFontSize == 14 && profile.dataGridFontSize == 13)
        #expect(profile.showLineNumbers && profile.formatsJSON)
    }

    @Test("each setting a window keeps wins over the one it overrides, and moves nothing else")
    func windowWinsSettingBySetting() throws {
        let settings = allDatabases(try defaults())
        let profile = DatabaseWindowProfile.resolved(everything, settings: settings)
        #expect(profile.glass == DatabaseGlassAppearance(opacity: 0.3, blur: 0.9), "the window's own Appearance")
        #expect(profile.resultRowLimit == 250)
        #expect(profile.editorFontSize == 20 && profile.dataGridFontSize == 18)
        #expect(!profile.showLineNumbers && !profile.formatsJSON)

        // One at a time: each key moves its own field and no other.
        let baseline = fields(DatabaseWindowProfile.resolved(GlassWindowOverrides(), settings: settings))
        let moves: [String: String] = [
            GlassLayerSettings.opacity.key: "opacity", GlassLayerSettings.frost.key: "frost",
            DatabaseWindowSettings.resultRowLimit.key: "rows", DatabaseWindowSettings.editorFontSize.key: "editor",
            DatabaseWindowSettings.dataGridFontSize.key: "grid", DatabaseWindowSettings.showLineNumbers.key: "lineNumbers",
            DatabaseWindowSettings.formatsJSON.key: "json",
        ]
        #expect(Set(moves.keys) == everything.keys)
        for (key, field) in moves {
            let one = fields(DatabaseWindowProfile.resolved(everything.restricted(to: [key]), settings: settings))
            let moved = Set(one.keys.filter { one[$0] != baseline[$0] })
            #expect(moved == [field], "\(key) moves \(field) alone")
        }

        // What the window doesn't set follows All Databases as it changes.
        var some = GlassWindowOverrides()
        some[DatabaseWindowSettings.editorFontSize] = 20
        settings.editorFontSize = 16
        settings.dataGridFontSize = 15
        settings.layers.state.frost = 0.6
        let followed = DatabaseWindowProfile.resolved(some, settings: settings)
        #expect(followed.editorFontSize == 20 && followed.dataGridFontSize == 15 && followed.glass.blur == 0.6)
    }

    @Test("a window keeps only values the database can use, however they arrive")
    func checkedValues() throws {
        var window = GlassWindowOverrides()
        window[DatabaseWindowSettings.resultRowLimit] = 0
        #expect(window[DatabaseWindowSettings.resultRowLimit] == 1)
        window[DatabaseWindowSettings.resultRowLimit] = 5_000_000
        #expect(window[DatabaseWindowSettings.resultRowLimit] == 100_000, "the editor's own ceiling")
        window[DatabaseWindowSettings.editorFontSize] = 99
        #expect(window[DatabaseWindowSettings.editorFontSize] == 32)
        window[DatabaseWindowSettings.dataGridFontSize] = 3
        #expect(window[DatabaseWindowSettings.dataGridFontSize] == 10)
        window[DatabaseWindowSettings.dataGridFontSize] = 13.6
        #expect(window[DatabaseWindowSettings.dataGridFontSize] == 14, "whole points, as All Databases steps")
        window[DatabaseWindowSettings.editorFontSize] = .nan
        #expect(!window.sets(DatabaseWindowSettings.editorFontSize), "not a number keeps nothing")

        // From a record another device or a newer build wrote: checked on the way out too.
        let written = Data(#"{"database.resultRowLimit": -4, "database.editorFontSize": 400, "database.showLineNumbers": 1}"#.utf8)
        let read = try JSONDecoder().decode(GlassWindowOverrides.self, from: written)
        #expect(read[DatabaseWindowSettings.resultRowLimit] == 1)
        #expect(read[DatabaseWindowSettings.editorFontSize] == 32)
        #expect(read[DatabaseWindowSettings.showLineNumbers] == nil, "a number is not a switch")
    }

    @Test("keys never change and are the database's own; Appearance's are shared")
    func stableKeys() {
        #expect(DatabaseWindowSettings.keys == [
            "database.resultRowLimit", "database.editorFontSize", "database.dataGridFontSize",
            "database.showLineNumbers", "database.formatsJSON",
        ])
        #expect(DatabaseWindowSettings.keys.isDisjoint(with: GlassLayerSettings.keys))
    }

    // MARK: Kept for the database

    @Test("a database keeps its window's settings, and a relaunch reads them back")
    func keptAcrossRelaunch() throws {
        let defaults = try defaults()
        let shop = UUID()
        let store = DatabaseWindowSettingsStore(defaults: defaults)
        store.record(everything, for: shop)
        #expect(store.settings(for: shop) == everything)

        let relaunched = DatabaseWindowSettingsStore(defaults: defaults)
        #expect(relaunched.settings(for: shop) == everything)
        #expect(relaunched.settings(for: UUID()).isEmpty, "another database keeps nothing of it")
    }

    @Test("a window that sets nothing leaves no record; Reset This Window removes it")
    func emptyLeavesNoRecord() throws {
        let defaults = try defaults()
        let shop = UUID(), crm = UUID()
        let store = DatabaseWindowSettingsStore(defaults: defaults)
        store.record(GlassWindowOverrides(), for: shop)
        #expect(defaults.data(forKey: UserDefaultsKeys.windowSettings) == nil, "nothing written for nothing set")

        store.record(everything, for: shop)
        store.record(everything, for: crm)
        store.record(GlassWindowOverrides(), for: shop)
        let relaunched = DatabaseWindowSettingsStore(defaults: defaults)
        #expect(relaunched.settings(for: shop).isEmpty)
        #expect(relaunched.settings(for: crm) == everything)
        let stored = try JSONSerialization.jsonObject(
            with: try #require(defaults.data(forKey: UserDefaultsKeys.windowSettings))) as? [[String: Any]]
        #expect(stored?.map { $0["connection"] as? String } == [crm.uuidString])

        store.record(GlassWindowOverrides(), for: crm)
        #expect(defaults.data(forKey: UserDefaultsKeys.windowSettings) == nil)
    }

    @Test("a record that can't be read costs only itself; a newer build's settings are kept")
    func readsLeniently() throws {
        let defaults = try defaults()
        let shop = UUID(), crm = UUID(), erp = UUID()
        let written: [Any] = [
            ["connection": "not an identifier", "windowSettings": ["database.editorFontSize": 18]],
            ["connection": shop.uuidString, "windowSettings": ["database.editorFontSize": 18, "database.nullText": "∅"]],
            ["connection": crm.uuidString, "windowSettings": "unreadable"],
            "not a record",
            ["connection": erp.uuidString, "windowSettings": ["database.showLineNumbers": false]],
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: written), forKey: UserDefaultsKeys.windowSettings)

        let store = DatabaseWindowSettingsStore(defaults: defaults)
        #expect(store.settings(for: shop)[DatabaseWindowSettings.editorFontSize] == 18)
        #expect(store.settings(for: erp)[DatabaseWindowSettings.showLineNumbers] == false)
        #expect(store.settings(for: crm).isEmpty, "settings that can't be read are a window that sets nothing")

        // Saving another database keeps what a newer build wrote for this one.
        store.record(everything, for: crm)
        let relaunched = DatabaseWindowSettingsStore(defaults: defaults)
        #expect(relaunched.settings(for: shop).keys.contains("database.nullText"))
        #expect(relaunched.records.map(\.connectionID) == [shop, erp, crm])

        defaults.set(Data("{}".utf8), forKey: UserDefaultsKeys.windowSettings)
        #expect(DatabaseWindowSettingsStore(defaults: defaults).records.isEmpty, "not a list: no records, no failure")
    }

    @Test("the store keeps the databases changed most recently, up to its limit")
    func bounded() throws {
        let defaults = try defaults()
        let store = DatabaseWindowSettingsStore(defaults: defaults)
        let databases = (0..<(DatabaseWindowSettingsStore.maximumCount + 3)).map { _ in UUID() }
        for database in databases { store.record(everything, for: database) }
        #expect(store.records.count == DatabaseWindowSettingsStore.maximumCount)
        #expect(store.settings(for: databases[0]).isEmpty, "the longest unchanged went first")
        #expect(store.settings(for: databases[3]) == everything)

        // Changing one again makes it the newest.
        var changed = everything
        changed[DatabaseWindowSettings.editorFontSize] = 24
        store.record(changed, for: databases[3])
        store.record(everything, for: UUID())
        #expect(store.settings(for: databases[3]) == changed)
        #expect(store.settings(for: databases[4]).isEmpty)
        #expect(DatabaseWindowSettingsStore(defaults: defaults).records.count == DatabaseWindowSettingsStore.maximumCount)
    }

    @Test("a window opens with what its opener hands it, else what its database kept")
    func opening() throws {
        let store = DatabaseWindowSettingsStore(defaults: try defaults())
        let config = DatabaseConnectionConfig(name: "shop", engine: .sqlite)
        store.record(everything, for: config.id)
        let sessionID = UUID()
        var carried = GlassWindowOverrides()
        carried[DatabaseWindowSettings.editorFontSize] = 24

        #expect(store.opening(.additional(sessionID: sessionID, windowSettings: carried), connectionID: config.id) == carried,
                "Open in New Window: the opener's own")
        #expect(store.opening(.additional(sessionID: sessionID, windowSettings: GlassWindowOverrides()),
                              connectionID: config.id).isEmpty, "an opener that keeps nothing hands over nothing")
        #expect(store.opening(.primary(sessionID: sessionID), connectionID: config.id) == everything)
        #expect(store.opening(.primary(sessionID: sessionID), connectionID: nil).isEmpty)

        // Through the session it shows: the database is the session's connection.
        let manager = DatabaseSessionManager(loadImmediately: false)
        manager.sessions[sessionID] = DatabaseSession(connectionConfig: config)
        #expect(manager.openingWindowSettings(for: .primary(sessionID: sessionID), store: store) == everything)
        #expect(manager.openingWindowSettings(for: .primary(sessionID: UUID()), store: store).isEmpty)
    }

    // MARK: Reaching it

    @Test("Settings opens on This Window where the workspace is a window; All Databases alone where it isn't")
    func settingsSections() {
        #expect(DatabaseSettingsModalTab.offered(hasWindowSettings: true) == [.thisWindow, .allDatabases])
        #expect(DatabaseSettingsModalTab.firstTab(hasWindowSettings: true) == .thisWindow)
        #expect(DatabaseSettingsModalTab.offered(hasWindowSettings: false) == [.allDatabases])
        #expect(DatabaseSettingsModalTab.firstTab(hasWindowSettings: false) == .allDatabases)
        #expect(DatabaseSettingsModalTab.allCases.map(\.title) == ["This Window", "All Databases"])
    }
}
