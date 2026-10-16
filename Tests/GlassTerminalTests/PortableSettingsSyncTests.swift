import Foundation
import Testing
import GlassShell
@testable import GlassTerminal

/// W18 (2026-10-10): every launch logged "Failed to synchronize portable settings … Code=3" —
/// `invalidPayload`. The key-value store is shared with glas.sh and with this app's builds from
/// before 2026-09-27, and both send the built-in terminal theme under its former identifier. A
/// push unions this device's records with the stored ones by identifier, so it held the built-in
/// theme twice, `validate()` refused that, and no push from a current build could ever land.
@MainActor
@Suite("Portable settings sync")
struct PortableSettingsSyncTests {
    /// iCloud's key-value store, in memory. Nothing here reaches the real one.
    @MainActor final class Store: GlassSettingsKeyValueStore {
        var values: [String: Data] = [:]
        var writes = 0
        var isAvailable: Bool { true }
        var isAccountAvailable: Bool { true }
        func data(forKey key: String) -> Data? { values[key] }
        func set(_ data: Data, forKey key: String) {
            values[key] = data
            writes += 1
        }
        func synchronize() async -> Bool { true }
        func observeExternalChanges(
            _ handler: @escaping @MainActor @Sendable (GlassSettingsStoreChange) -> Void
        ) -> NSObjectProtocol { NSObject() }
        func removeExternalChangeObserver(_ observer: NSObjectProtocol) {}
    }

    // Whole seconds: the store keeps dates to the millisecond.
    private let early = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let late = Date(timeIntervalSinceReferenceDate: 800_000_100)
    private let latest = Date(timeIntervalSinceReferenceDate: 800_000_200)

    private func cloud(_ theme: TerminalTheme) -> ICloudTerminalTheme {
        func color(_ c: CodableColor) -> ICloudTerminalColor {
            ICloudTerminalColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
        }
        return ICloudTerminalTheme(
            id: theme.id, name: theme.name,
            background: color(theme.background), foreground: color(theme.foreground),
            cursor: color(theme.cursor), selection: color(theme.selection),
            ansiColors: theme.ansiColors.map(color),
            fontName: theme.fontName, fontSize: Double(theme.fontSize),
            preferredAppearance: theme.preferredAppearance)
    }

    private func preferences(cursorStyle: String) -> ICloudPortableTerminalPreferences {
        ICloudPortableTerminalPreferences(
            autoReconnect: true, confirmBeforeClosing: true, saveScrollback: true,
            maximumScrollbackLines: 10_000, bellEnabled: false, visualBell: true,
            cursorStyle: cursorStyle, blinkingCursor: true, glassFrost: "regular",
            windowOpacity: 0, blurBackground: 1, interactiveGlass: true, glassTint: "None")
    }

    /// The built-in theme as an older build or glas.sh sends it: under `legacyDefaultID`.
    private func olderBuildPayload(
        builtInFontSize: CGFloat, builtInAt: Date, custom: TerminalTheme, cursorStyle: String
    ) -> ICloudSettingsSyncPayload {
        var builtIn = TerminalTheme.default.reidentified(id: TerminalTheme.legacyDefaultID)
        builtIn.fontSize = builtInFontSize
        return ICloudSettingsSyncPayload(
            themeRecords: [
                ICloudTerminalThemeRecord(theme: cloud(builtIn), origin: .builtIn, modifiedAt: builtInAt, deletedAt: nil),
                ICloudTerminalThemeRecord(theme: cloud(custom), origin: .appleTerminal, modifiedAt: early, deletedAt: nil),
            ],
            selectedThemeID: TerminalTheme.legacyDefaultID,
            selectionModifiedAt: early,
            preferences: preferences(cursorStyle: cursorStyle))
    }

    private func currentBuildPayload(builtInFontSize: CGFloat, builtInAt: Date) -> ICloudSettingsSyncPayload {
        var builtIn = TerminalTheme.default
        builtIn.fontSize = builtInFontSize
        return ICloudSettingsSyncPayload(
            themeRecords: [
                ICloudTerminalThemeRecord(theme: cloud(builtIn), origin: .builtIn, modifiedAt: builtInAt, deletedAt: nil),
            ],
            selectedThemeID: TerminalTheme.defaultID,
            selectionModifiedAt: early,
            preferences: preferences(cursorStyle: "Block"))
    }

    private func encoded(_ envelope: GlassSettingsSyncEnvelope<ICloudSettingsSyncPayload>) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    private func decoded(_ data: Data) throws -> GlassSettingsSyncEnvelope<ICloudSettingsSyncPayload> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(GlassSettingsSyncEnvelope<ICloudSettingsSyncPayload>.self, from: data)
    }

    @Test("an older build's built-in theme converges with this one's as one theme; the newer edit wins")
    func olderBuiltInConvergesAsOneTheme() throws {
        let theirs = UUID()
        let custom = TerminalTheme.default.reidentified(id: theirs, name: "Theirs")
        // Theirs edited later: their font size survives, under the current identifier.
        let older = olderBuildPayload(builtInFontSize: 13, builtInAt: late, custom: custom, cursorStyle: "Bar")
        let current = currentBuildPayload(builtInFontSize: 14, builtInAt: early)
        for converged in [current.converged(with: older), older.converged(with: current)] {
            #expect(throws: Never.self) { try converged.validate() }
            let builtIns = converged.themeRecords.filter { $0.origin == .builtIn }
            #expect(builtIns.map(\.id) == [TerminalTheme.defaultID])
            #expect(builtIns.first?.theme.fontSize == 13)
            #expect(converged.themeRecords.contains { $0.id == theirs }, "their own theme is kept")
            #expect(converged.selectedThemeID == TerminalTheme.defaultID)
        }

        // Ours edited later: ours survives.
        let newerHere = currentBuildPayload(builtInFontSize: 16, builtInAt: latest)
        for converged in [newerHere.converged(with: older), older.converged(with: newerHere)] {
            #expect(throws: Never.self) { try converged.validate() }
            let builtIns = converged.themeRecords.filter { $0.origin == .builtIn }
            #expect(builtIns.map(\.id) == [TerminalTheme.defaultID])
            #expect(builtIns.first?.theme.fontSize == 16)
        }
    }

    /// The owner's Mac on 2026-10-09, end to end: iCloud holds an envelope an older build wrote,
    /// this device's own saved library still names the built-in theme by its former identifier
    /// too, and a theme of its own is selected.
    @Test("a launch beside an older build's settings sends them on, keeping both devices' themes")
    func launchSendsOverAnOlderBuildsSettings() async throws {
        let suite = "PortableSettingsSync.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: UserDefaultsKeys.iCloudSettingsSyncEnabled)

        let theirs = TerminalTheme.default.reidentified(name: "Theirs")
        let store = Store()
        let key = ICloudSettingsSyncService.terminalStoreKey
        store.values[key] = try encoded(GlassSettingsSyncEnvelope(
            revision: 7, writerID: UUID(), writtenAt: late,
            payload: olderBuildPayload(builtInFontSize: 14, builtInAt: early, custom: theirs, cursorStyle: "Bar")))

        // Saved before the identifier changed, as the library on disk can still be.
        let mine = TerminalTheme.default.reidentified(name: "Mine")
        var library = TerminalThemeLibrary.initial(at: early)
        library.records = [
            TerminalThemeRecord(theme: TerminalTheme.default.reidentified(id: TerminalTheme.legacyDefaultID),
                                origin: .builtIn, modifiedAt: early, deletedAt: nil),
            TerminalThemeRecord(theme: mine, origin: .custom, modifiedAt: late, deletedAt: nil),
        ]
        library.selectedThemeID = mine.id
        library.selectionModifiedAt = latest
        defaults.set(try JSONEncoder().encode(library), forKey: UserDefaultsKeys.themeLibrary)

        let service = ICloudSettingsSyncService(store: store, writerID: UUID())
        let settings = SettingsManager(
            settingsDefaults: defaults, sshKeyDefaults: defaults,
            iCloudSettingsSyncService: service,
            workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: Store()))

        // Polls rather than waits: the push runs on the main actor, which a busy suite holds.
        let deadline = ContinuousClock.now + .seconds(30)
        while store.writes == 0 || settings.iCloudSyncStatusText != "Up to date",
              service.status != .error, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(service.status == .synced, "\(service.lastErrorDescription ?? "")")
        #expect(settings.iCloudSyncStatusText == "Up to date")
        #expect(store.writes == 1)
        let sent = try decoded(try #require(store.values[key]))
        #expect(sent.revision == 8)
        #expect(sent.payload.themeRecords.filter { $0.origin == .builtIn }.map(\.id) == [TerminalTheme.defaultID])
        #expect(sent.payload.themeRecords.contains { $0.id == theirs.id && !$0.isDeleted }, "the other device's theme")
        #expect(sent.payload.themeRecords.contains { $0.id == mine.id && !$0.isDeleted }, "this device's theme")
        #expect(sent.payload.selectedThemeID == mine.id, "this device chose later")
        #expect(sent.payload.preferences.cursorStyle == "Bar", "what was already in iCloud is not overwritten")
        #expect(settings.themeLibrary.records.filter(\.isBuiltIn).map(\.id) == [TerminalTheme.defaultID])
        let persisted = try JSONDecoder().decode(
            TerminalThemeLibrary.self, from: try #require(defaults.data(forKey: UserDefaultsKeys.themeLibrary)))
        #expect(persisted.records.filter(\.isBuiltIn).map(\.id) == [TerminalTheme.defaultID])
    }

    /// When resized (D75, 2026-10-16): kept on this device, carried with the rest, and a payload
    /// from a build before it leaves it alone.
    @Test("When resized is kept on this device and travels with the settings")
    func whenResizedPersistsAndTravels() throws {
        let suite = "WhenResized.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(
            loadImmediately: false, settingsDefaults: defaults, sshKeyDefaults: defaults,
            iCloudSettingsSyncService: ICloudSettingsSyncService(store: Store(), writerID: UUID()),
            workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: Store()))
        #expect(settings.whenResized == .changeGrid, "as it always was")
        settings.whenResized = .scale
        settings.saveSettings()
        #expect(defaults.string(forKey: UserDefaultsKeys.whenResized) == "scale")
        let reopened = SettingsManager(
            settingsDefaults: defaults, sshKeyDefaults: defaults,
            iCloudSettingsSyncService: ICloudSettingsSyncService(store: Store(), writerID: UUID()),
            workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: Store()))
        #expect(reopened.whenResized == .scale)

        var carried = preferences(cursorStyle: "Block")
        carried.whenResized = TerminalResizeBehavior.scale.rawValue
        let data = try JSONEncoder().encode(carried)
        #expect(try JSONDecoder().decode(ICloudPortableTerminalPreferences.self, from: data).whenResized == "scale")
        var older = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        older.removeValue(forKey: "whenResized")
        let olderData = try JSONSerialization.data(withJSONObject: older)
        #expect(try JSONDecoder().decode(ICloudPortableTerminalPreferences.self, from: olderData).whenResized == nil)
    }
}
