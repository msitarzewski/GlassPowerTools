import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlassRDPTransport
import GlassShell
@testable import GlassDesktop

/// W25 (owner, 2026-10-10): "the original idea was that anything in the system settings could be
/// overridden per window." A desktop window keeps its own glass, background removal, Detail and
/// pointer over Settings ▸ Desktops (All Desktops); the session draws and connects with them; they
/// are kept on this device by the desktop's endpoint, which is the window's identity, and come back
/// the next time that desktop opens.
@MainActor
@Suite("A desktop window keeps its own settings", .serialized)
struct DesktopWindowSettingsTests {
    /// All Desktops, with nothing at its standard value, so a window that follows it is visible.
    private static let allDesktops: DesktopDefaults = {
        var value = DesktopDefaults()
        value.opacity = 0.7
        value.frost = 0.4
        value.backgroundRemoval = .removeBlack
        value.keyColor = [0, 1, 0]
        value.tolerance = 0.1
        value.edgeSoftness = 0.05
        value.detail = .standard
        value.pointer = .trackpad
        return value
    }()

    /// A window that sets every setting, each to something All Desktops is not.
    private static var everything: GlassWindowOverrides {
        var window = GlassWindowOverrides()
        window[DesktopWindowSettings.opacity] = 0.35
        window[DesktopWindowSettings.frost] = 0.9
        window[DesktopWindowSettings.backgroundRemoval] = .removeColor
        window[DesktopWindowSettings.keyColor] = "#0000FF"
        window[DesktopWindowSettings.tolerance] = 0.2
        window[DesktopWindowSettings.edgeSoftness] = 0.1
        window[DesktopWindowSettings.detail] = .double
        window[DesktopWindowSettings.pointer] = .directTouch
        return window
    }

    private func profile(_ window: GlassWindowOverrides, defaults: DesktopDefaults = allDesktops,
                         glass: Bool = true, touch: Bool = true, compact: Bool = false,
                         reduceTransparency: Bool = false) -> DesktopWindowProfile {
        DesktopWindowProfile(window: window, defaults: defaults, glass: glass, touch: touch,
                             compactScreen: compact, reduceTransparency: reduceTransparency)
    }

    @MainActor private final class Fixture {
        let root: URL
        let suite: String
        let defaults: UserDefaults
        var connects: [GlassRDPConfiguration] = []

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("DesktopWindowSettings-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            suite = "DesktopWindowSettingsTests-\(UUID().uuidString)"
            defaults = try #require(UserDefaults.forTest(suiteName: suite))
        }

        func clean() { try? FileManager.default.removeItem(at: root) }

        /// A process's desktop model, its window settings kept in this test's defaults: a second
        /// call over the same fixture is the app after a relaunch.
        @MainActor func launch() async -> DesktopAppModel {
            let app = DesktopAppModel(storageDirectory: root, credentialAccess: .inMemory(),
                                      windowSettings: DesktopWindowSettingsStore(defaults: defaults))
            await app.attach(store: GlassInMemoryServiceStore(defaultKind: .rdp))
            return app
        }

        /// No host: connect records the configuration; nothing else happens.
        @MainActor var operations: DesktopSessionOperations {
            var value = DesktopSessionOperations()
            value.connect = { _, configuration in if let rdp = configuration.rdp { self.connects.append(rdp) } }
            value.disconnect = { _ in }
            value.resize = { _, _, _ in }
            value.delay = { _ in }
            value.recordConnection = { _, _, _ in }
            return value
        }

        @MainActor func session(_ connection: DesktopConnection, app: DesktopAppModel) -> DesktopSessionModel {
            DesktopSessionModel(connection: connection, app: app, operations: operations,
                                wallpaperRoot: root.appendingPathComponent("wallpapers"))
        }

        var stored: [String: Any]? {
            defaults.data(forKey: DesktopWindowSettingsStore.key)
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    // MARK: Resolving: the window's, else All Desktops'

    @Test("a window that sets nothing draws and drives exactly as All Desktops")
    func followsAllDesktops() {
        let drawn = profile(GlassWindowOverrides())
        #expect(drawn.opacity == 0.7)
        #expect(drawn.frost == 0.4)
        #expect(drawn.backgroundRemoval == .removeBlack)
        #expect(drawn.keyColor == [0, 1, 0])
        #expect(drawn.tolerance == 0.1)
        #expect(drawn.edgeSoftness == 0.05)
        #expect(drawn.detail == .standard)
        #expect(drawn.pointer == .trackpad)
    }

    @Test("each setting the window keeps wins over All Desktops, field by field")
    func eachSettingWins() {
        let drawn = profile(Self.everything)
        #expect(drawn.opacity == 0.35)
        #expect(drawn.frost == 0.9)
        #expect(drawn.backgroundRemoval == .removeColor)
        #expect(drawn.keyColor == [0, 0, 1])
        #expect(drawn.tolerance == 0.2)
        #expect(drawn.edgeSoftness == 0.1)
        #expect(drawn.detail == .double)
        #expect(drawn.pointer == .directTouch)

        // One setting: only that one changes.
        var one = GlassWindowOverrides()
        one[DesktopWindowSettings.tolerance] = 0.2
        let partly = profile(one)
        #expect(partly.tolerance == 0.2)
        #expect(partly.opacity == 0.7 && partly.backgroundRemoval == .removeBlack && partly.detail == .standard)
    }

    @Test("Reduce Transparency wins over the window and All Desktops: Original, opaque, frosted")
    func reduceTransparencyWins() {
        let drawn = profile(Self.everything, reduceTransparency: true)
        #expect(drawn.backgroundRemoval == .original)
        #expect(drawn.opacity == 1)
        #expect(drawn.frost == 1)
        #expect(drawn.detail == .double, "not a transparency setting")
    }

    @Test("off the Mac and the headset the desktop stays opaque; off iPad and iPhone the pointer is left alone")
    func platformsWithoutGlassOrTouch() {
        #expect(profile(Self.everything, glass: false).opacity == 1)
        #expect(profile(Self.everything, touch: false).pointer == nil)

        // Automatic: Trackpad on a compact screen, Direct Touch otherwise.
        var automatic = Self.allDesktops
        automatic.pointer = nil
        #expect(profile(GlassWindowOverrides(), defaults: automatic, compact: true).pointer == .trackpad)
        #expect(profile(GlassWindowOverrides(), defaults: automatic, compact: false).pointer == .directTouch)
    }

    @Test("Show Original sets this window's presentation and opacity, and only them, until it shows the original")
    func originalIsThisWindows() {
        var window = GlassWindowOverrides()
        window[DesktopWindowSettings.tolerance] = 0.2
        #expect(!profile(window).showsOriginal, "All Desktops removes black, at 70%: Show Original has work to do")
        window.showDesktopOriginal()
        #expect(window[DesktopWindowSettings.backgroundRemoval] == .original)
        #expect(window[DesktopWindowSettings.opacity] == (DesktopWindowSettings.offersGlass ? 1 : nil))
        #expect(window[DesktopWindowSettings.tolerance] == 0.2)
        let drawn = profile(window)
        #expect(drawn.backgroundRemoval == .original && drawn.opacity == 1)
        #expect(drawn.showsOriginal, "so the button is done")
    }

    // MARK: Checked on the way in and out

    @Test("values are kept in range on the way in, and anything else is not kept")
    func valuesAreChecked() throws {
        var window = GlassWindowOverrides()
        window[DesktopWindowSettings.tolerance] = 0.9
        window[DesktopWindowSettings.edgeSoftness] = -1
        window[DesktopWindowSettings.opacity] = 3
        window[DesktopWindowSettings.keyColor] = "#ff00ff"
        #expect(window[DesktopWindowSettings.tolerance] == 0.25)
        #expect(window[DesktopWindowSettings.edgeSoftness] == 0)
        #expect(window[DesktopWindowSettings.opacity] == 1)
        #expect(window[DesktopWindowSettings.keyColor] == "#FF00FF")
        window[DesktopWindowSettings.keyColor] = "magenta"
        #expect(window[DesktopWindowSettings.keyColor] == nil, "not a colour: the window follows All Desktops'")
        #expect(DesktopKeyColor.color("#FF8000") == SIMD3<Float>(1, 128.0 / 255, 0))
        #expect(DesktopKeyColor.hex([1, 0.5, 0]) == "#FF8000")

        // And on the way out: a record from elsewhere is read in range.
        let json = ##"{"desktop.tolerance": 7, "desktop.edgeSoftness": 0.5, "desktop.detail": "huge", "desktop.keyColor": "#12"}"##
        let read = try JSONDecoder().decode(GlassWindowOverrides.self, from: Data(json.utf8))
        #expect(read[DesktopWindowSettings.tolerance] == 0.25)
        #expect(read[DesktopWindowSettings.edgeSoftness] == 0.12)
        #expect(read[DesktopWindowSettings.detail] == nil)
        #expect(read[DesktopWindowSettings.keyColor] == nil)
        #expect(profile(read).detail == .standard && profile(read).keyColor == [0, 1, 0])
    }

    @Test("All Desktops reads what is stored in range, and never as Remove Wallpaper")
    func allDesktopsReadInRange() {
        let read = DesktopDefaults(storedOpacity: 4, frost: .nan, backgroundRemoval: TransparencyMode.removeWallpaper.rawValue,
                                   red: 2, green: -1, blue: .infinity, tolerance: 0.9, edgeSoftness: .nan,
                                   detail: "huge", pointer: "")
        #expect(read.opacity == 1)
        #expect(read.frost == DesktopDefaults.standard.frost)
        #expect(read.backgroundRemoval == .original, "Remove Wallpaper needs an image chosen in a session")
        #expect(read.keyColor == [1, 0, 1])
        #expect(read.tolerance == 0.25)
        #expect(read.edgeSoftness == DesktopDefaults.standard.edgeSoftness)
        #expect(read.detail == .automatic)
        #expect(read.pointer == nil, "Automatic")

        let chosen = DesktopDefaults(storedOpacity: 0.5, frost: 0.1, backgroundRemoval: "removeColor", red: 0, green: 1,
                                     blue: 0, tolerance: 0.1, edgeSoftness: 0.05, detail: "double", pointer: "trackpad")
        #expect(chosen.opacity == 0.5 && chosen.frost == 0.1 && chosen.backgroundRemoval == .removeColor)
        #expect(chosen.detail == .double && chosen.pointer == .trackpad)
    }

    // MARK: The session draws and connects with them

    @Test("the session draws its window's settings and keeps its own zoom and pan")
    func applyKeepsTheSessionsZoom() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let app = DesktopAppModel(storageDirectory: fixture.root, credentialAccess: .inMemory())
        let session = fixture.session(DesktopConnection(name: "alpha", host: "alpha.local", username: "casey"), app: app)
        session.presentation.zoom = 1.5
        session.presentation.panX = 12
        session.presentation.panY = -8

        session.apply(profile(Self.everything))
        #expect(session.presentation.mode == .removeColor)
        #expect(session.presentation.opacity == 0.35)
        #expect(session.presentation.keyColor == [0, 0, 1])
        #expect(session.presentation.threshold == 0.2)
        #expect(session.presentation.feather == 0.1)
        #expect(session.sourceScale == .double)
        #expect(session.pointerMode == .directTouch)
        #expect(session.presentation.zoom == 1.5 && session.presentation.panX == 12 && session.presentation.panY == -8,
                "zoom and pan are the session's, not a setting")

        // Where touch has no choice, the session's pointer is left as it is.
        session.apply(profile(GlassWindowOverrides(), touch: false))
        #expect(session.pointerMode == .directTouch)
    }

    @Test("an RDP window's Detail is the scale its session connects with")
    func detailIsWhatTheSessionConnectsWith() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let app = DesktopAppModel(storageDirectory: fixture.root, credentialAccess: .inMemory())
        let connection = DesktopConnection(name: "alpha", host: "alpha.local", username: "casey")

        let following = fixture.session(connection, app: app)
        following.apply(profile(GlassWindowOverrides(), defaults: DesktopDefaults()))
        try await following.connect(username: "casey", domain: nil, password: "test secret")

        var window = GlassWindowOverrides()
        window[DesktopWindowSettings.detail] = .double
        let own = fixture.session(connection, app: app)
        own.windowSettings = window
        own.apply(profile(own.windowSettings, defaults: DesktopDefaults()))
        try await own.connect(username: "casey", domain: nil, password: "test secret")

        #expect(fixture.connects.map(\.desktopScaleFactor) == [100, 200],
                "All Desktops' Automatic at one pixel per point, then the window's 200%")
    }

    // MARK: Kept with the desktop's window, on this device

    @Test("a window's settings come back when its desktop opens again, after a relaunch; another desktop's don't")
    func survivesARelaunch() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let alpha = DesktopConnection(name: "alpha", host: "alpha.local", username: "casey")
        let bravo = DesktopConnection(name: "bravo", host: "bravo.local", username: "casey")

        let first = await fixture.launch()
        let window = fixture.session(alpha, app: first)
        #expect(window.windowSettings.isEmpty, "a desktop never opened here follows All Desktops")
        window.windowSettings = Self.everything
        await window.close().value

        let relaunched = await fixture.launch()
        #expect(fixture.session(alpha, app: relaunched).windowSettings == Self.everything)
        #expect(fixture.session(bravo, app: relaunched).windowSettings.isEmpty)

        // Reset This Window: nothing kept, and nothing stored.
        let again = fixture.session(alpha, app: relaunched)
        again.windowSettings = GlassWindowOverrides()
        #expect(fixture.defaults.data(forKey: DesktopWindowSettingsStore.key) == nil)
        #expect(fixture.session(alpha, app: await fixture.launch()).windowSettings.isEmpty)
    }

    @Test("Remove Wallpaper lasts the session that chose its image; the rest of the window is kept")
    func removeWallpaperLastsTheSession() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let alpha = DesktopConnection(name: "alpha", host: "alpha.local", username: "casey")
        let app = await fixture.launch()
        let window = fixture.session(alpha, app: app)
        var settings = GlassWindowOverrides()
        settings[DesktopWindowSettings.backgroundRemoval] = .removeWallpaper
        settings[DesktopWindowSettings.opacity] = 0.5
        window.windowSettings = settings
        #expect(window.windowSettings[DesktopWindowSettings.backgroundRemoval] == .removeWallpaper, "this session")

        let next = fixture.session(alpha, app: await fixture.launch())
        #expect(next.windowSettings[DesktopWindowSettings.backgroundRemoval] == nil, "next time: All Desktops'")
        #expect(next.windowSettings[DesktopWindowSettings.opacity] == 0.5)
        #expect(fixture.session(alpha, app: app).windowSettings[DesktopWindowSettings.backgroundRemoval] == nil,
                "nor in this process: the image was the other session's")
    }

    @Test("the record holds only what a window sets, under windowSettings, by the desktop's endpoint")
    func recordShape() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let alpha = DesktopConnection(name: "alpha", host: "alpha.local", username: "casey")
        let app = await fixture.launch()
        let window = fixture.session(alpha, app: app)
        #expect(fixture.stored == nil, "a window that follows everything stores nothing")

        var one = GlassWindowOverrides()
        one[DesktopWindowSettings.detail] = .oneAndAHalf
        window.windowSettings = one
        let stored = try #require(fixture.stored)
        #expect(Array(stored.keys) == [alpha.id.rawValue.uuidString])
        let record = try #require(stored[alpha.id.rawValue.uuidString] as? [String: Any])
        #expect(Array(record.keys) == ["windowSettings"])
        #expect((record["windowSettings"] as? [String: Any])?["desktop.detail"] as? String == "oneAndAHalf")

        // A record with nothing set says so by saying nothing.
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DesktopWindowRecord())) as? [String: Any]
        #expect(empty?.isEmpty == true)
    }

    @Test("an entry that can't be read costs only itself, and keys a newer build wrote are kept")
    func readLeniently() throws {
        let alpha = UUID(), bravo = UUID(), charlie = UUID()
        let json = """
        {"\(alpha.uuidString)": {"windowSettings": {"desktop.opacity": 0.25, "desktop.future": "kept"}},
         "\(bravo.uuidString)": {"windowSettings": "unreadable"},
         "\(charlie.uuidString)": 42,
         "not-a-desktop": {"windowSettings": {"desktop.opacity": 0.5}}}
        """
        let records = DesktopWindowSettingsStore.read(Data(json.utf8))
        #expect(records.count == 1)
        let kept = try #require(records[EndpointID(rawValue: alpha)]?.windowSettings)
        #expect(kept[DesktopWindowSettings.opacity] == 0.25)
        #expect(kept.keys == ["desktop.opacity", "desktop.future"], "a newer build's setting survives this one")
        #expect(DesktopWindowSettingsStore.read(Data("[1, 2]".utf8)).isEmpty)
        #expect(DesktopWindowSettingsStore.read(Data("not json".utf8)).isEmpty)
    }

    @Test("removing a desktop removes what its window kept")
    func removingTheDesktopForgetsItsWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let app = await fixture.launch()
        let alpha = DesktopConnection(name: "alpha", host: "192.0.2.10", username: "casey")
        let bravo = DesktopConnection(name: "bravo", host: "192.0.2.20", username: "casey")
        try await app.save(alpha, password: "test secret")
        try await app.save(bravo, password: "test secret")
        fixture.session(alpha, app: app).windowSettings = Self.everything
        fixture.session(bravo, app: app).windowSettings = Self.everything

        let saved = try #require(app.connections.first { $0.id == alpha.id })
        await app.delete(saved)
        #expect(app.errorMessage == nil)
        #expect(app.windowSettings.settings(for: alpha.id).isEmpty)
        #expect(app.windowSettings.settings(for: bravo.id) == Self.everything, "another desktop's window is untouched")
        let relaunched = await fixture.launch()
        #expect(relaunched.windowSettings.settings(for: alpha.id).isEmpty, "and not on disk either")
        #expect(fixture.stored?.keys.contains(alpha.id.rawValue.uuidString) == false)
    }
}
