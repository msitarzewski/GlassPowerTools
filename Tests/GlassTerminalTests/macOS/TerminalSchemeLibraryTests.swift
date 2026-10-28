#if os(macOS)
import AppKit
import Foundation
import GlassLayers
import GlassShell
import Testing
@testable import GlassTerminal

/// The Terminal Themes folder (2026-10-28, a user's 148 Terminal color schemes: "Let's make these
/// work, first class style!"): any number of `.terminal` files, chosen for All Terminals or a window
/// by an identifier made from the file's name, synced as that identifier.
@Suite("Terminal schemes in a folder of their own")
@MainActor
struct TerminalSchemeLibraryTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("schemes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A Terminal profile as Terminal writes one, in `folder`.
    @discardableResult
    private func profile(_ name: String, background: NSColor, text: NSColor, in folder: URL, fileName: String? = nil) throws -> URL {
        let settings: [String: Any] = [
            "name": name, "type": "Window Settings",
            "BackgroundColor": try NSKeyedArchiver.archivedData(withRootObject: background, requiringSecureCoding: true),
            "TextColor": try NSKeyedArchiver.archivedData(withRootObject: text, requiringSecureCoding: true),
            "SelectionColor": try NSKeyedArchiver.archivedData(withRootObject: NSColor(deviceRed: 0.2, green: 0.3, blue: 0.9, alpha: 1),
                                                                requiringSecureCoding: true),
        ]
        let url = folder.appendingPathComponent(fileName ?? "\(name).terminal")
        try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0).write(to: url)
        return url
    }

    /// Until every scheme listed has been read, or a few seconds.
    private func read(_ library: TerminalSchemeLibrary) async {
        for _ in 0..<100 where library.schemes.contains(where: { $0.theme == nil && $0.problem == nil }) {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    @Test("A scheme's identifier is its file's name, the same on every device, however the name is composed")
    func identifiers() {
        let tango = TerminalSchemeFiles.id(forFileNamed: "Tango Dark.terminal")
        #expect(tango == TerminalSchemeFiles.id(forFileNamed: "Tango Dark.terminal"))
        #expect(tango != TerminalSchemeFiles.id(forFileNamed: "Tango Light.terminal"))
        #expect(TerminalSchemeFiles.id(forFileNamed: "Caf\u{E9}.terminal") == TerminalSchemeFiles.id(forFileNamed: "Cafe\u{301}.terminal"),
                "a name the Finder decomposed is the same scheme")
        #expect(tango.uuidString.dropFirst(14).first == "5", "a name-based UUID")
        #expect(TerminalSchemeFiles.entry(named: "Glacier.terminal")?.isDownloaded == true)
        #expect(TerminalSchemeFiles.entry(named: ".Glacier.terminal.icloud")?.fileName == "Glacier.terminal")
        #expect(TerminalSchemeFiles.entry(named: ".Glacier.terminal.icloud")?.isDownloaded == false)
        #expect(TerminalSchemeFiles.entry(named: "notes.txt") == nil)
        #expect(TerminalSchemeFiles.entry(named: ".terminal") == nil)
    }

    @Test("Importing a folder brings its profiles in, says which it couldn't and why, and reads each in its own colors")
    func importingAFolder() async throws {
        let source = try folder(), destination = try folder()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: destination) }
        try profile("Night", background: NSColor(deviceRed: 0, green: 0.1, blue: 0.2, alpha: 1),
                    text: NSColor(deviceRed: 0.9, green: 0.9, blue: 0.8, alpha: 1), in: source)
        try profile("Day", background: NSColor(deviceRed: 0.98, green: 0.97, blue: 0.94, alpha: 1),
                    text: NSColor(deviceRed: 0.1, green: 0.1, blue: 0.1, alpha: 1), in: source)
        try Data("not a profile".utf8).write(to: source.appendingPathComponent("Broken.terminal"))
        try Data("notes".utf8).write(to: source.appendingPathComponent("README.txt"))

        let library = TerminalSchemeLibrary(deviceFolder: destination)
        let outcome = await library.add([source])
        #expect(outcome.added.sorted() == ["Day.terminal", "Night.terminal"])
        #expect(outcome.problems.map(\.name) == ["Broken.terminal"])
        #expect(outcome.problems.first?.problem.contains("isn't a Terminal profile") == true, "\(outcome.problems)")
        await read(library)
        #expect(library.schemes.map(\.name) == ["Day", "Night"])
        let night = try #require(library.schemes.last?.theme)
        #expect(abs(night.background.blue - 0.2) < 1e-6, "its own background")
        #expect(night.preferredAppearance == .dark)
        #expect(library.schemes.first?.theme?.preferredAppearance == .light)
    }

    @Test("Importing a profile again by the same name replaces it, keeping its identifier, so choices of it stay")
    func importingAgainReplaces() async throws {
        let source = try folder(), destination = try folder()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: destination) }
        let file = try profile("Glacier", background: NSColor(deviceRed: 0, green: 0, blue: 0.3, alpha: 1),
                               text: NSColor.white.usingColorSpace(.deviceRGB)!, in: source)
        let library = TerminalSchemeLibrary(deviceFolder: destination)
        await library.add([file])
        await read(library)
        let id = try #require(library.schemes.first?.id)
        try profile("Glacier", background: NSColor(deviceRed: 0.3, green: 0, blue: 0, alpha: 1),
                    text: NSColor.white.usingColorSpace(.deviceRGB)!, in: source)
        await library.add([file])
        await read(library)
        #expect(library.schemes.count == 1)
        #expect(library.schemes.first?.id == id)
        #expect(abs((library.schemes.first?.theme?.background.red ?? 0) - 0.3) < 1e-6, "the new colors")

        library.remove(try #require(library.schemes.first))
        #expect(library.schemes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Glacier.terminal").path))
    }

    @Test("A scheme is drawn in the font it is given; a window that chose it draws it, one that chose a scheme not here draws All Terminals'")
    func windowsDrawTheirScheme() async throws {
        let source = try folder(), destination = try folder()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: destination) }
        try profile("Ocean", background: NSColor(deviceRed: 0.1, green: 0.2, blue: 0.5, alpha: 1),
                    text: NSColor(deviceRed: 0.8, green: 0.9, blue: 1, alpha: 1), in: source)
        let library = TerminalSchemeLibrary(deviceFolder: destination)
        await library.add([source])
        await read(library)
        let ocean = try #require(library.schemes.first)

        var global = TerminalTheme.default
        global.fontName = "Menlo"
        global.fontSize = 17
        let drawn = try #require(library.theme(forID: ocean.id, font: global))
        #expect(drawn.fontName == "Menlo" && drawn.fontSize == 17, "colors only: the font is yours")
        #expect(abs(drawn.background.blue - 0.5) < 1e-6)
        #expect(drawn.name == "Ocean" && drawn.id == ocean.id)

        var window = GlassWindowOverrides()
        window[TerminalWindowSettings.theme] = ocean.id.uuidString
        let themes = TerminalThemeLibrary.initial()
        let windowTheme = TerminalWindowProfile.theme(window, over: global, library: themes, schemes: library)
        #expect(windowTheme.id == ocean.id && windowTheme.fontName == "Menlo")
        #expect(!TerminalWindowProfile.isMissingTheme(window, library: themes, schemes: library))

        window[TerminalWindowSettings.theme] = TerminalSchemeFiles.id(forFileNamed: "Elsewhere.terminal").uuidString
        #expect(TerminalWindowProfile.theme(window, over: global, library: themes, schemes: library) == global)
        #expect(TerminalWindowProfile.isMissingTheme(window, library: themes, schemes: library),
                "named but not on this device yet")
    }

    @Test("All Terminals' scheme is kept on this device; choosing one of your themes clears it; sync carries it, empty for none and absent from older devices")
    func choosingAndSyncing() throws {
        let suite = "TerminalSchemes.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func settings() -> SettingsManager {
            SettingsManager(loadImmediately: true, settingsDefaults: defaults, sshKeyDefaults: defaults,
                            iCloudSettingsSyncService: ICloudSettingsSyncService(store: InMemorySettingsStore(), writerID: UUID()),
                            workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: InMemorySettingsStore()),
                            layers: GlassLayerStore.forTest())
        }
        let id = TerminalSchemeFiles.id(forFileNamed: "Tango Dark.terminal")
        let first = settings()
        #expect(first.terminalScheme == nil)
        first.chooseScheme(id)
        #expect(settings().terminalScheme == id, "kept")
        // Not on this device: All Terminals draw with your theme meanwhile.
        #expect(first.allTerminalsTheme == first.currentTheme)
        first.chooseTheme(TerminalTheme.defaultID)
        #expect(first.terminalScheme == nil)
        #expect(settings().terminalScheme == nil)

        #expect(SettingsManager.scheme(synced: id.uuidString, current: nil) == id)
        #expect(SettingsManager.scheme(synced: "", current: id) == nil, "another device chose your theme")
        #expect(SettingsManager.scheme(synced: nil, current: id) == id, "a device from before schemes leaves it be")

        var preferences = ICloudPortableTerminalPreferences(
            autoReconnect: true, confirmBeforeClosing: true, saveScrollback: true,
            maximumScrollbackLines: 10_000, bellEnabled: false, visualBell: true,
            cursorStyle: "Block", blinkingCursor: true, glassFrost: "regular",
            windowOpacity: 0, blurBackground: 1, interactiveGlass: true, glassTint: "None",
            terminalScheme: id.uuidString)
        try preferences.validate()
        let decoded = try JSONDecoder().decode(ICloudPortableTerminalPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(decoded.terminalScheme == id.uuidString)
        preferences.terminalScheme = ""
        try preferences.validate()
        preferences.terminalScheme = "Tango Dark"
        #expect(throws: ICloudSettingsSyncError.self) { try preferences.validate() }
        preferences.terminalScheme = nil
        let older = try JSONEncoder().encode(preferences)
        #expect(!String(decoding: older, as: UTF8.self).contains("terminalScheme"))
        #expect(try JSONDecoder().decode(ICloudPortableTerminalPreferences.self, from: older).terminalScheme == nil)
    }
}
#endif
