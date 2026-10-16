import Foundation
import Testing
import GlassLayers
import GlassShell
import GlassTerminalEmulator
@testable import GlassTerminal

/// W22 (owner, 2026-10-10): "the original idea was that anything in the system settings could be
/// overridden per window." A terminal window keeps its own theme, font, cursor, bell, scrollback,
/// tint and glass; W20's look became five of them, read and written so a build from W20 on still
/// reads the look; every tab in the window draws and behaves with them.
@MainActor
@Suite("A terminal window keeps its own settings")
struct TerminalWindowSettingsTests {
    /// W20's look with every field set.
    private let look = TerminalSessionOverride(glassFrost: "thick", windowOpacity: 0.3, blurBackground: 0.6,
                                               interactiveGlass: false, glassTint: "#FF2D55")

    /// A window that sets something of everything.
    private var everything: GlassWindowOverrides {
        var window = look.windowSettings
        window[TerminalWindowSettings.theme] = Self.dusk.id.uuidString
        window[TerminalWindowSettings.fontFamily] = "Menlo"
        window[TerminalWindowSettings.fontSize] = 18
        window[TerminalWindowSettings.cursorStyle] = "Bar"
        window[TerminalWindowSettings.blinkingCursor] = false
        window[TerminalWindowSettings.bell] = true
        window[TerminalWindowSettings.visualBell] = false
        window[TerminalWindowSettings.keepsScrollback] = true
        window[TerminalWindowSettings.scrollbackLines] = 50_000
        return window
    }

    private static let dusk: TerminalTheme = {
        var theme = TerminalTheme.default.reidentified(name: "Dusk")
        theme.fontName = "Monaco"
        theme.fontSize = 12
        return theme
    }()

    private var library: TerminalThemeLibrary {
        var library = TerminalThemeLibrary.initial()
        library.upsert(Self.dusk)
        return library
    }

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    // MARK: W20's look, migrated

    @Test("W20's look becomes the window's settings value for value, and goes back to the same look")
    func lookMigratesLosslessly() throws {
        let settings = look.windowSettings
        #expect(settings[GlassLayerSettings.opacity] == 0.3)
        #expect(settings[GlassLayerSettings.frost] == 0.6, "W20's blur is Appearance's frost")
        #expect(settings[GlassLayerSettings.material] == .thick, "W20's frost is Appearance's material")
        #expect(settings[TerminalWindowSettings.interactiveGlass] == false)
        #expect(settings[TerminalWindowSettings.tint] == "#FF2D55")
        #expect(settings.keys == TerminalWindowSettings.lookKeys)
        #expect(TerminalSessionOverride(windowSettings: settings) == look, "back to the same look")
        #expect(TerminalSessionOverride(windowSettings: GlassWindowOverrides()) == nil)

        // As W20 drew it: every field the look set, none it left unset.
        let drawn = TerminalLook(window: settings, frost: "regular", opacity: 0.9, blur: 0.1, interactiveGlass: true, tint: "None")
        #expect(drawn.frost == "thick" && drawn.opacity == 0.3 && drawn.blur == 0.6)
        #expect(!drawn.interactiveGlass && drawn.tint == "#FF2D55")
    }

    @Test("a Workgroup saved by W20 reads into the window's settings, legacy keys and all")
    func w20WorkgroupReads() throws {
        var object = try json(LayoutPreset(name: "Builds", serverIDs: [UUID()]))
        // What W20 wrote, and the older names it still read.
        object["look"] = ["appearanceVersion": 2, "glassMaterialStyle": "thin", "backgroundFill": 0.5,
                          "blurBackground": true, "interactiveGlassEffects": false, "glassTint": "Blue"]
        let preset = try JSONDecoder().decode(LayoutPreset.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(preset.windowSettings[GlassLayerSettings.material] == .thin)
        #expect(preset.windowSettings[GlassLayerSettings.opacity] == 0.5)
        #expect(preset.windowSettings[GlassLayerSettings.frost] == 1)
        #expect(preset.windowSettings[TerminalWindowSettings.interactiveGlass] == false)
        #expect(preset.windowSettings[TerminalWindowSettings.tint] == "Blue")
        #expect(preset.isValidForPersistence)
    }

    @Test("a Workgroup keeps every window setting; W20's part is under look, in W20's format, the rest beside it")
    func workgroupKeepsEverything() throws {
        var preset = LayoutPreset(name: "Builds", serverIDs: [UUID()])
        let without = try json(preset)
        preset.windowSettings = everything
        let decoded = try JSONDecoder().decode(LayoutPreset.self, from: JSONEncoder().encode(preset))
        #expect(decoded.windowSettings == everything)
        #expect(decoded == preset)

        var object = try json(preset)
        #expect(object["schemaVersion"] as? Int == without["schemaVersion"] as? Int, "the schema an earlier build reads")
        // A build from W20 on reads the look with its own type, unchanged.
        let lookData = try JSONSerialization.data(withJSONObject: try #require(object["look"]))
        #expect(try JSONDecoder().decode(TerminalSessionOverride.self, from: lookData) == look)
        // The rest beside it, never W20's five twice.
        let rest = try #require(object["windowSettings"] as? [String: Any])
        #expect(Set(rest.keys).isDisjoint(with: TerminalWindowSettings.lookKeys))
        #expect(rest.count == everything.keys.count - TerminalWindowSettings.lookKeys.count)
        // Nothing else changes: an earlier build ignores both keys it doesn't know.
        object.removeValue(forKey: "look")
        object.removeValue(forKey: "windowSettings")
        #expect(NSDictionary(dictionary: object).isEqual(to: without))
    }

    @Test("a build before W22 that saves the Workgroup again keeps its look; settings that can't be read cost only themselves")
    func earlierBuildsKeepTheLook() throws {
        var preset = LayoutPreset(name: "Builds", serverIDs: [UUID()])
        preset.windowSettings = everything
        var object = try json(preset)
        // W20 decodes what it knows and writes it back: `windowSettings` goes, `look` stays.
        object.removeValue(forKey: "windowSettings")
        let resaved = try JSONDecoder().decode(LayoutPreset.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(resaved.windowSettings == look.windowSettings)

        object["windowSettings"] = "unreadable"
        let unreadable = try JSONDecoder().decode(LayoutPreset.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(unreadable.windowSettings == look.windowSettings && unreadable.isValidForPersistence)
    }

    @Test("every window setting travels with a saved Workgroup to another device (D51)")
    func everythingTravels() async throws {
        let shared = WorkgroupsSyncTests.SharedStore()
        func device() throws -> (SettingsManager, UserDefaults, String) {
            let suite = "TerminalWindowSettings.sync.\(UUID())"
            let defaults = try #require(UserDefaults.forTest(suiteName: suite))
            let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults,
                                           workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: shared.device()))
            return (settings, defaults, suite)
        }
        let (mac, macDefaults, macSuite) = try device()
        let (headset, headsetDefaults, headsetSuite) = try device()
        defer {
            macDefaults.removePersistentDomain(forName: macSuite)
            headsetDefaults.removePersistentDomain(forName: headsetSuite)
        }
        mac.startWorkgroupsSync()
        headset.startWorkgroupsSync()
        try await Task.sleep(for: .milliseconds(50))

        var preset = LayoutPreset(name: "Builds", serverIDs: [UUID()])
        preset.windowSettings = everything
        mac.upsertLayoutPreset(preset)
        for _ in 0..<200 where !headset.layoutPresets.contains(where: { $0.id == preset.id }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(headset.layoutPresets.first { $0.id == preset.id }?.windowSettings == everything)
    }

    @Test("the reopen list keeps every window setting; a list W20 wrote reads its look")
    func reopenRecordKeepsEverything() throws {
        let record = TerminalWorkgroupReopenRecord(
            id: UUID(), name: "alpha", colorTag: .blue,
            terminals: [.init(serverID: UUID(), tmuxSession: "glass-1", label: nil, name: nil)],
            selectedIndex: 0, isShown: false, windowSettings: everything)
        let data = try JSONEncoder().encode([record])
        let back = try #require(try JSONDecoder().decode([TerminalWorkgroupReopenRecord].self, from: data).first)
        #expect(back == record)

        var object = try json(record)
        object.removeValue(forKey: "windowSettings")
        let w20 = try JSONDecoder().decode(TerminalWorkgroupReopenRecord.self,
                                           from: JSONSerialization.data(withJSONObject: object))
        #expect(w20.windowSettings == look.windowSettings && w20.terminals == record.terminals)

        object["look"] = 42
        let unreadable = try JSONDecoder().decode(TerminalWorkgroupReopenRecord.self,
                                                  from: JSONSerialization.data(withJSONObject: object))
        #expect(unreadable.windowSettings.isEmpty && unreadable.terminals == record.terminals,
                "settings that can't be read cost only themselves")
    }

    #if os(macOS)
    @Test("a Mac window's record keeps every window setting; one W20 saved reads its look")
    func macRecordKeepsEverything() throws {
        let tab = MacWorkspaceTabDescriptor(MacWorkspaceTabRequest(workspaceID: UUID()))
        let state = MacWorkspaceWindowRestorationState(tabs: [tab], selectedTabID: tab.id, windowSettings: everything)
        let back = try JSONDecoder().decode(MacWorkspaceWindowRestorationState.self, from: JSONEncoder().encode(state))
        #expect(back.windowSettings == everything)

        var object = try json(state)
        #expect(object["look"] != nil && object["windowSettings"] != nil)
        object.removeValue(forKey: "windowSettings")
        let w20 = try JSONDecoder().decode(MacWorkspaceWindowRestorationState.self,
                                           from: JSONSerialization.data(withJSONObject: object))
        #expect(w20.windowSettings == look.windowSettings && w20.validated() != nil)
    }
    #endif

    // MARK: What a terminal in the window uses

    private func profile(_ window: GlassWindowOverrides) -> TerminalWindowProfile {
        let look = TerminalLook(window: window, frost: "regular", opacity: 0, blur: 1, interactiveGlass: true, tint: "None")
        return TerminalWindowProfile(window: window, look: look, theme: .default, library: library,
                                     cursorStyle: "Block", blinkingCursor: true, keepsScrollback: true,
                                     scrollbackLines: 10_000, bellEnabled: false, visualBell: true)
    }

    @Test("a window that sets nothing uses every terminal setting")
    func followsTheSettings() {
        let plain = profile(GlassWindowOverrides())
        #expect(plain.theme == .default)
        #expect(plain.cursorStyle == "Block" && plain.blinkingCursor && plain.scrollbackLines == 10_000)
        #expect(!plain.bellEnabled && plain.visualBell)
        #expect(plain.runtimeSettings == SwiftTermRuntimeSettings(cursorStyle: "Block", blinkingCursor: true,
                                                                  scrollbackLines: 10_000))
    }

    /// Show previews (2026-10-16): Mouseover unless a window says otherwise; nothing it could not mean.
    @Test("Show previews: the terminal setting, the window's over it, and nothing the setting can't be")
    func showPreviews() {
        #expect(profile(GlassWindowOverrides()).pathPreviews == .mouseover, "the default")
        var never = GlassWindowOverrides()
        never[TerminalWindowSettings.pathPreviews] = TerminalPathPreviews.never.rawValue
        #expect(profile(never).pathPreviews == .never)
        #expect(profile(never).runtimeSettings.pathPreviews == .never, "and the terminal is told")
        var space = GlassWindowOverrides()
        space[TerminalWindowSettings.pathPreviews] = TerminalPathPreviews.mouseoverAndSpace.rawValue
        #expect(profile(space).pathPreviews == .mouseoverAndSpace)
        var nonsense = GlassWindowOverrides()
        nonsense[TerminalWindowSettings.pathPreviews] = "sometimes"
        #expect(nonsense[TerminalWindowSettings.pathPreviews] == nil, "not one of its choices: not kept")
        #expect(profile(nonsense).pathPreviews == .mouseover)
    }

    @Test("each setting the window sets wins: theme, font, cursor, bell and scrollback")
    func windowSettingsWin() {
        let own = profile(everything)
        #expect(own.theme.id == Self.dusk.id, "the window's theme")
        #expect(own.theme.fontName == "Menlo" && own.theme.fontSize == 18, "its font over the theme's")
        #expect(own.cursorStyle == "Bar" && !own.blinkingCursor)
        #expect(own.bellEnabled && !own.visualBell)
        #expect(own.scrollbackLines == 50_000)
        #expect(own.runtimeSettings == SwiftTermRuntimeSettings(cursorStyle: "Bar", blinkingCursor: false,
                                                                scrollbackLines: 50_000))

        var themeOnly = GlassWindowOverrides()
        themeOnly[TerminalWindowSettings.theme] = Self.dusk.id.uuidString
        #expect(profile(themeOnly).theme == Self.dusk, "its own theme brings its own font")

        var noScrollback = GlassWindowOverrides()
        noScrollback[TerminalWindowSettings.keepsScrollback] = false
        noScrollback[TerminalWindowSettings.scrollbackLines] = 50_000
        #expect(profile(noScrollback).scrollbackLines == 0, "scrollback off for this window keeps none")
    }

    @Test("a theme this device doesn't have draws with All Terminals' until it arrives")
    func missingTheme() {
        var window = GlassWindowOverrides()
        window[TerminalWindowSettings.theme] = UUID().uuidString
        #expect(profile(window).theme == .default)
        #expect(TerminalWindowProfile.isMissingTheme(window, library: library))
        #expect(!TerminalWindowProfile.isMissingTheme(everything, library: library))

        window[TerminalWindowSettings.theme] = TerminalTheme.legacyDefaultID.uuidString
        #expect(window[TerminalWindowSettings.theme] == TerminalTheme.defaultID.uuidString,
                "the built-in theme's old identifier is read as its current one (D56)")
    }

    @Test("values a window can't use are refused, as the settings refuse them")
    func valuesChecked() {
        var window = GlassWindowOverrides()
        window[TerminalWindowSettings.cursorStyle] = "Beam"
        window[TerminalWindowSettings.theme] = "not a theme"
        window[TerminalWindowSettings.fontFamily] = "   "
        #expect(window.isEmpty)
        window[TerminalWindowSettings.fontSize] = 72
        window[TerminalWindowSettings.scrollbackLines] = 5_000_000
        #expect(window[TerminalWindowSettings.fontSize] == 24 && window[TerminalWindowSettings.scrollbackLines] == 100_000)
    }

    @Test("every tab in a workgroup's window uses the window's settings, and one moved in takes them")
    func everyTab() {
        let manager = SessionManager(loadImmediately: false)
        let server = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")
        let one = TerminalSession(server: server), two = TerminalSession(server: server), three = TerminalSession(server: server)
        for session in [one, two, three] { manager.registerSession(session) }
        let window = manager.createWorkgroup(name: "alpha", colorTag: .blue, windowSettings: everything)
        let other = manager.createWorkgroup(name: "bravo", colorTag: .blue)
        manager.appendSession(one, toWorkgroup: window)
        manager.appendSession(two, toWorkgroup: window)
        manager.appendSession(three, toWorkgroup: other)
        #expect(profile(manager.windowSettings(ofWorkgroupHolding: one.id)) == profile(everything))
        #expect(profile(manager.windowSettings(ofWorkgroupHolding: two.id)) == profile(everything))
        #expect(profile(manager.windowSettings(ofWorkgroupHolding: three.id)) == profile(GlassWindowOverrides()))
        #expect(TerminalTabMoves.move(three.id, to: window, at: nil, in: manager) == .moved(sourceClosed: true))
        #expect(profile(manager.windowSettings(ofWorkgroupHolding: three.id)) == profile(everything))
    }
}
