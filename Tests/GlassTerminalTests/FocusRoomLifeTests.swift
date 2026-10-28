import Foundation
import Testing
#if canImport(RealityKit)
import RealityKit
#endif
import GlassLayers
import GlassShell
@testable import GlassTerminal

/// A living room in Focus Mode (the owner, 2026-10-27: "Maybe make a clock show system time? … Cars
/// moving … What about audio?"): its clock on the headset's time, nothing that moves to stand on, and
/// its sounds as the folder beside it lists them (`2026-10-27_living-rooms-handoff.md`).
@MainActor
@Suite("Focus Mode's living rooms")
struct FocusRoomLifeTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func at(_ hour: Int, _ minute: Int, _ second: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: hour, minute: minute, second: second))!
    }

    private static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    // MARK: - The clock

    @Test("The hands sweep clockwise from 12: three o'clock, half past nine, half a minute to midnight")
    func clockAngles() {
        let three = FocusRoomClock.angles(at: Self.at(3, 0, 0), in: Self.calendar)
        #expect(Self.near(three.hour, .pi / 2))
        #expect(Self.near(three.minute, 0))
        #expect(Self.near(three.second, 0))
        #expect(Self.near(FocusRoomClock.angles(at: Self.at(15, 0, 0), in: Self.calendar).hour, .pi / 2), "a 12-hour dial")
        let turn: Double = 2 * .pi
        let halfNine = FocusRoomClock.angles(at: Self.at(9, 30, 0), in: Self.calendar)
        let halfNineHour: Double = turn * 9.5 / 12
        #expect(Self.near(halfNine.hour, halfNineHour))
        #expect(Self.near(halfNine.minute, .pi))
        let late = FocusRoomClock.angles(at: Self.at(23, 59, 30), in: Self.calendar)
        let lateMinute: Double = turn * 59.5 / 60
        let lateSeconds: Double = 43_170
        let lateHour: Double = turn * lateSeconds / 43_200
        #expect(Self.near(late.minute, lateMinute))
        #expect(Self.near(late.second, .pi))
        #expect(Self.near(late.hour, lateHour))
    }

    #if canImport(RealityKit)
    @Test("The clock's own hands turn, not their meshes; at three the hour hand points right, seen facing the dial")
    func clockHandsTurn() throws {
        let room = Entity(), clock = Entity(), hour = Entity(), hourMesh = Entity(), minute = Entity()
        clock.name = "clock"
        hour.name = "clock_hour"
        hourMesh.name = "clock_hour"
        minute.name = "clock_minute"
        room.addChild(clock)
        clock.addChild(hour)
        hour.addChild(hourMesh)
        clock.addChild(minute)
        let hands = try #require(FocusRoomClockHands(in: room, calendar: Self.calendar))
        hands.tick(now: Self.at(3, 0, 0))
        let pointing = hour.orientation.act([0, 1, 0])
        #expect(abs(pointing.x - 1) < 1e-5 && abs(pointing.y) < 1e-5, "the hour hand points to \(pointing)")
        #expect(hourMesh.orientation == simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), "the mesh turns with its hand, not twice")
        #expect(abs(minute.orientation.act([0, 1, 0]).y - 1) < 1e-5, "the minute hand at 12")
        #expect(FocusRoomClockHands(in: Entity()) == nil, "a room with no clock")
    }

    @Test("What moves is never stood on: a room's floor is, its cars and clock hands are not")
    func nothingMovingToStandOn() {
        let room = Entity(), floor = Entity(), moving = Entity(), car = Entity(), clock = Entity(), hand = Entity()
        floor.name = "floor"
        moving.name = "moving"
        car.name = "car"
        clock.name = "clock"
        hand.name = "clock_hour"
        room.addChild(floor)
        room.addChild(moving)
        moving.addChild(car)
        room.addChild(clock)
        clock.addChild(hand)
        #expect(FocusRoomLife.standableDescendants(of: room).map(\.name) == ["floor"])
    }
    #endif

    // MARK: - Sounds

    /// The loft's own `sounds.json`, as the GlassSpaceMaker session shipped it.
    private static let loftSounds = """
    {
      "version": 1,
      "sounds": [
        { "id": "city",  "file": "city_blue_hour.m4a",  "entity": "snd_city",  "kind": "ambient", "gain": -14, "loop": true },
        { "id": "rack",  "file": "server_fans.m4a",     "entity": "snd_rack",  "kind": "spatial", "gain": -22, "loop": true },
        { "id": "hvac",  "file": "hvac_hum.m4a",                               "kind": "channel", "gain": -30, "loop": true },
        { "id": "clock", "file": "clock_tick.m4a",      "entity": "snd_clock", "kind": "spatial", "gain": -30, "loop": true },
        { "id": "heli",  "file": "helicopter_pass.m4a", "entity": "snd_heli",  "kind": "spatial", "gain": -8,  "loop": false, "every": [180, 600] },
        { "id": "siren", "file": "siren_distant.m4a",   "entity": "snd_city",  "kind": "spatial", "gain": -24, "loop": false, "every": [240, 900] }
      ]
    }
    """

    @Test("The loft's sounds read as shipped: beds, sounds placed in the room, and two that come now and then")
    func loftSoundsRead() throws {
        let sounds = try #require(FocusRoomSounds.decoded(from: Data(Self.loftSounds.utf8)))
        #expect(sounds.version == 1)
        #expect(sounds.sounds.map(\.id) == ["city", "rack", "hvac", "clock", "heli", "siren"])
        #expect(sounds.sounds[0].kind == .ambient)
        #expect(sounds.sounds[2].kind == .channel && sounds.sounds[2].entity == nil)
        #expect(sounds.sounds[4].interval == 180...600)
        #expect(sounds.sounds[0].interval == nil)
        #expect(FocusRoomSounds.decoded(from: Data("{\"sounds\": 3}".utf8)) == nil, "not a list of sounds")
    }

    @Test("Gains stay within −60…0 dB; Room Sound's level is decibels over them, 0 silence")
    func gains() throws {
        var sound = try #require(FocusRoomSounds.decoded(from: Data(Self.loftSounds.utf8))).sounds[0]
        #expect(sound.clampedGain == -14)
        sound.gain = 6
        #expect(sound.clampedGain == 0)
        sound.gain = -90
        #expect(sound.clampedGain == -60)
        sound.gain = .nan
        #expect(sound.clampedGain == -60)
        #expect(FocusRoomSounds.masterGain(level: 1) == 0)
        #expect(abs(FocusRoomSounds.masterGain(level: 0.5)! - (-6.0206)) < 0.001)
        #expect(FocusRoomSounds.masterGain(level: 0) == nil)
        #expect(FocusRoomSounds.masterGain(level: .nan) == nil)
    }

    @Test("A sound that comes now and then waits within its range; a range back to front is never played")
    func nowAndThen() throws {
        var heli = try #require(FocusRoomSounds.decoded(from: Data(Self.loftSounds.utf8))).sounds[4]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let wait = try #require(heli.nextWait(using: &generator))
            #expect((180...600).contains(wait))
        }
        heli.every = [600, 180]
        #expect(heli.interval == nil)
        heli.every = [180]
        #expect(heli.interval == nil)
    }

    @Test("A sound whose entity the room hasn't got is skipped; a bed that turns with the head needs none")
    func missingEntitySkipped() throws {
        let sounds = try #require(FocusRoomSounds.decoded(from: Data(Self.loftSounds.utf8)))
        let has: Set<String> = ["snd_city", "snd_rack"]
        #expect(sounds.playable(hasEntity: { has.contains($0) }).map(\.id) == ["city", "rack", "hvac", "siren"])
    }

    @Test("The sounds are in a folder named as the room, beside it: none is a silent room; one iCloud hasn't brought is silent this time")
    func soundsBesideTheRoom() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FocusRoomLife-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let room = folder.appendingPathComponent("Loft.usdz")
        #expect(FocusRoomSounds.folder(beside: room).lastPathComponent == "Loft.sounds")
        #expect(FocusRoomSounds.folder(beside: room).deletingLastPathComponent().lastPathComponent == folder.lastPathComponent)
        #expect(FocusRoomSounds.read(beside: room) == nil, "no folder")
        let sounds = FocusRoomSounds.folder(beside: room)
        try FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
        try Data(Self.loftSounds.utf8).write(to: sounds.appendingPathComponent("sounds.json"))
        #expect(FocusRoomSounds.read(beside: room)?.sounds.count == 6)
        try Data().write(to: sounds.appendingPathComponent(".clock_tick.m4a.icloud"))
        #expect(FocusRoomSounds.read(beside: room) == nil, "a file still in iCloud")
    }

    // MARK: - Room Sound

    @Test("Room Sound starts at 70% and is kept on this device; sync carries it and refuses one out of range")
    func roomSoundSetting() throws {
        let suite = "FocusRoomSound.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func settings() -> SettingsManager {
            SettingsManager(loadImmediately: true, settingsDefaults: defaults, sshKeyDefaults: defaults,
                            iCloudSettingsSyncService: ICloudSettingsSyncService(store: InMemorySettingsStore(), writerID: UUID()),
                            workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: InMemorySettingsStore()),
                            layers: GlassLayerStore.forTest())
        }
        let first = settings()
        #expect(first.focusEnvironmentSound == 0.7)
        first.focusEnvironmentSound = 0.25
        first.saveSettings()
        #expect(settings().focusEnvironmentSound == 0.25)

        var preferences = ICloudPortableTerminalPreferences(
            autoReconnect: true, confirmBeforeClosing: true, saveScrollback: true,
            maximumScrollbackLines: 10_000, bellEnabled: false, visualBell: true,
            cursorStyle: "Block", blinkingCursor: true, glassFrost: "regular",
            windowOpacity: 0, blurBackground: 1, interactiveGlass: true, glassTint: "None",
            focusEnvironmentSound: 0.4)
        try preferences.validate()
        let decoded = try JSONDecoder().decode(ICloudPortableTerminalPreferences.self,
                                               from: JSONEncoder().encode(preferences))
        #expect(decoded.focusEnvironmentSound == 0.4)
        preferences.focusEnvironmentSound = 1.5
        #expect(throws: ICloudSettingsSyncError.self) { try preferences.validate() }
        #if !os(visionOS)
        #expect(SettingsManager.sentFromVisionPro(0.4) == nil, "only the headset sends it")
        #endif
    }
}
