//
//  FocusRoomLife.swift
//  Glass Power Tools — GlassTerminal
//
//  A living room in Focus Mode (the owner, 2026-10-27: "Is there a way to animate these somehow?
//  Maybe make a clock show system time? … Cars moving, people walking. Occasional birds and planes
//  (random)", and "What about audio?"). A room file carries its own motion, which plays round and
//  round from a different place each time; two things no file can carry, the host adds: a wall
//  clock's hands on the headset's time, and sound from a folder beside the file.
//
//  What a room promises (the GlassSpaceMaker session's handoff, `2026-10-27_living-rooms-handoff.md`):
//  everything animated under an Xform named `moving`; a `clock` Xform whose child Xforms
//  `clock_hour`, `clock_minute` and optionally `clock_second` point to 12 as loaded, turning about
//  their local Z (negative is clockwise, seen facing the dial); empty `snd_<id>` Xforms where sounds
//  come from; and `<Room>.sounds/sounds.json` beside `<Room>.usdz`.
//
//  And, from the handoff's third phase (the owner, 2026-10-27: "go ahead with phase 3"): a digital
//  clock and date panel at an empty Xform named `clock_digital` (its centre; local +Z into the room,
//  +Y up; 0.5 m wide, times the Xform's own scale); and events that happen now and then, from
//  `<Room>.events/events.json` beside the file: each a small file of its own, shown at one of its
//  `event_<name>` Xforms, a random number of seconds apart, for as long as its motion lasts.
//

import Foundation
#if canImport(RealityKit)
import RealityKit
#endif

/// A wall clock's hands at a moment, in radians clockwise from 12, each sweeping rather than ticking.
nonisolated enum FocusRoomClock {
    static func angles(at date: Date, in calendar: Calendar) -> (hour: Double, minute: Double, second: Double) {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let seconds = Double((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0))
            + Double(parts.nanosecond ?? 0) / 1_000_000_000
        let turn = 2 * Double.pi
        return (turn * seconds.truncatingRemainder(dividingBy: 43_200) / 43_200,
                turn * seconds.truncatingRemainder(dividingBy: 3_600) / 3_600,
                turn * seconds.truncatingRemainder(dividingBy: 60) / 60)
    }
}

/// The folders beside a room file: `Loft.sounds`, `Loft.events`.
nonisolated enum FocusRoomSidecar {
    static func folder(beside room: URL, kind: String) -> URL {
        room.deletingPathExtension().appendingPathExtension(kind)
    }

    /// A list's contents, when everything in its folder is on this device. A folder iCloud hasn't
    /// brought is asked for, and nothing is read this time; the next opening has it. No folder is
    /// nothing to read, not a problem.
    static func manifest(named name: String, in folder: URL) -> Data? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.path) else { return nil }
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        let waiting = names.filter { $0.hasPrefix(".") && $0.hasSuffix(".icloud") }
        for standIn in waiting {
            let file = String(standIn.dropFirst().dropLast(".icloud".count))
            try? manager.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(file))
        }
        guard waiting.isEmpty else { return nil }
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: folder.appendingPathComponent(name), options: [], error: nil) { url in
            data = try? Data(contentsOf: url)
        }
        return data
    }

    /// A file a list names is one in its own folder: no path, nothing hidden.
    static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".")
    }

    /// `every`'s seconds apart, `[from, to]`; nil for anything else.
    static func interval(_ every: [Double]?) -> ClosedRange<Double>? {
        guard let every, every.count == 2, every[0].isFinite, every[1].isFinite,
              every[0] >= 0, every[0] <= every[1] else { return nil }
        return every[0]...every[1]
    }
}

/// A room's sounds, as its `sounds.json` lists them.
nonisolated struct FocusRoomSounds: Decodable, Equatable, Sendable {
    var version: Int
    var sounds: [Sound]

    struct Sound: Decodable, Equatable, Sendable {
        var id: String
        /// The file's name in the room's sounds folder.
        var file: String
        /// The `snd_<id>` entity it comes from; none for a `channel` sound.
        var entity: String?
        var kind: Kind
        /// Decibels, at or below 0.
        var gain: Double
        var loop: Bool
        /// Played once at a time, a random number of seconds in this range apart; nil plays it
        /// from the start (round and round, when `loop`).
        var every: [Double]?

        enum Kind: String, Decodable, Sendable {
            /// From its entity, placed in the room.
            case spatial
            /// A bed around the person that stays with the room as the head turns.
            case ambient
            /// A bed that turns with the head.
            case channel
        }

        /// Its gain, kept within −60…0 dB.
        var clampedGain: Double { gain.isFinite ? Swift.min(0, Swift.max(-60, gain)) : -60 }

        /// The wait range of a sound played now and then; nil for one that plays from the start.
        var interval: ClosedRange<Double>? { FocusRoomSidecar.interval(every) }

        /// The next wait before a sound played now and then.
        func nextWait(using generator: inout some RandomNumberGenerator) -> Double? {
            interval.map { Double.random(in: $0, using: &generator) }
        }
    }

    /// The folder a room's sounds are in: `Loft.sounds` beside `Loft.usdz`.
    static func folder(beside room: URL) -> URL {
        FocusRoomSidecar.folder(beside: room, kind: "sounds")
    }

    /// The sounds that can play here: a `channel` sound always; one placed at an entity only when
    /// the room has it (one missing is skipped, and said in the log); none named by a path.
    func playable(hasEntity: (String) -> Bool) -> [Sound] {
        sounds.filter { sound in
            FocusRoomSidecar.isPlainFileName(sound.file) && (sound.kind == .channel || sound.entity.map(hasEntity) == true)
        }
    }

    /// Settings' sound level as decibels over every sound: 0 is silence, nil.
    static func masterGain(level: Double) -> Double? {
        guard level.isFinite, level > 0 else { return nil }
        return 20 * log10(Swift.min(level, 1))
    }

    static func decoded(from data: Data) -> FocusRoomSounds? {
        try? JSONDecoder().decode(FocusRoomSounds.self, from: data)
    }

    /// The sounds beside a room file, when they are all on this device (`FocusRoomSidecar`): this
    /// opening is silent while iCloud brings them.
    static func read(beside room: URL) -> FocusRoomSounds? {
        FocusRoomSidecar.manifest(named: "sounds.json", in: folder(beside: room)).flatMap(decoded(from:))
    }
}

/// What happens in a room now and then, as its `events.json` lists it: a flock crossing the sky, a
/// light in the next tower.
nonisolated struct FocusRoomEvents: Decodable, Equatable, Sendable {
    var version: Int
    var events: [Event]

    struct Event: Decodable, Equatable, Sendable {
        var id: String
        /// The event's own file in the events folder (USDZ or Reality), its root at the anchor.
        var file: String
        /// The `event_<name>` Xforms it may happen at; one is chosen each time.
        var anchors: [String]
        /// Seconds apart, `[from, to]`.
        var every: [Double]
        /// How long it stays; by default as long as its motion lasts, or 10 s when it has none.
        var seconds: Double?

        var interval: ClosedRange<Double>? { FocusRoomSidecar.interval(every) }

        func nextWait(using generator: inout some RandomNumberGenerator) -> Double? {
            interval.map { Double.random(in: $0, using: &generator) }
        }

        /// How long it shows: `seconds` when given, else its motion's length, else 10 s; never past
        /// ten minutes.
        static func showing(motionSeconds: Double?, declared: Double?) -> Double {
            for seconds in [declared, motionSeconds] {
                if let seconds, seconds.isFinite, seconds > 0 { return Swift.min(seconds, 600) }
            }
            return 10
        }
    }

    static func folder(beside room: URL) -> URL {
        FocusRoomSidecar.folder(beside: room, kind: "events")
    }

    /// The events that can happen here: a plain file name, a wait to go by, and at least one of its
    /// anchors in the room.
    func playable(hasEntity: (String) -> Bool) -> [Event] {
        events.filter { event in
            FocusRoomSidecar.isPlainFileName(event.file) && event.interval != nil && event.anchors.contains(where: hasEntity)
        }
    }

    static func decoded(from data: Data) -> FocusRoomEvents? {
        try? JSONDecoder().decode(FocusRoomEvents.self, from: data)
    }

    static func read(beside room: URL) -> FocusRoomEvents? {
        FocusRoomSidecar.manifest(named: "events.json", in: folder(beside: room)).flatMap(decoded(from:))
    }
}

#if canImport(RealityKit)
/// What in a room is alive, and what to stand on.
@MainActor
enum FocusRoomLife {
    /// The Xforms whose insides move or are the host's: never stood on, never pinched (a car, a bird,
    /// a clock's hand, the digital clock's panel), and each `event_<name>` with what happens there.
    static let livingNames: Set<String> = ["moving", "clock", digitalClockName]
    static let eventPrefix = "event_"

    static func isLiving(_ name: String) -> Bool {
        livingNames.contains(name) || name.hasPrefix(eventPrefix)
    }

    /// Everything under `entity` but what moves: the surfaces a room can be stood on.
    static func standableDescendants(of entity: Entity) -> [Entity] {
        entity.children.flatMap { child -> [Entity] in
            isLiving(child.name) ? [] : [child] + standableDescendants(of: child)
        }
    }

    /// Where a room's digital clock and date panel goes.
    static let digitalClockName = "clock_digital"
    /// The panel's width, metres, before its Xform's own scale.
    static let digitalClockWidth: Float = 0.5

    /// Puts `panel`, `panelWidth` metres across as drawn, at the room's `clock_digital`, facing as
    /// it faces; false when the room has none.
    @discardableResult
    static func placeDigitalClock(_ panel: Entity, panelWidth: Float, in model: Entity) -> Bool {
        guard let anchor = model.findEntity(named: digitalClockName) else { return false }
        anchor.addChild(panel)
        let scale = panelWidth.isFinite && panelWidth > 0 ? digitalClockWidth / panelWidth : 1
        panel.transform = Transform(scale: SIMD3(repeating: scale))
        return true
    }
}

/// A room's wall clock, set to the headset's time each frame.
@MainActor
final class FocusRoomClockHands {
    /// Each hand found, as it rested, and which it is: 0 hour, 1 minute, 2 second.
    private var hands: [(entity: Entity, rest: simd_quatf, which: Int)] = []
    private let calendar: Calendar

    /// The hands under the room's `clock`, or nil when it has none. A hand's mesh carries its name
    /// too: the hand is the `clock`'s own child.
    init?(in model: Entity, calendar: Calendar = .current) {
        self.calendar = calendar
        guard let clock = model.findEntity(named: "clock") else { return nil }
        for (which, name) in ["clock_hour", "clock_minute", "clock_second"].enumerated() {
            if let hand = clock.children.first(where: { $0.name == name }) {
                hands.append((hand, hand.orientation, which))
            }
        }
        guard !hands.isEmpty else { return nil }
    }

    func tick(now: Date) {
        let angles = FocusRoomClock.angles(at: now, in: calendar)
        let byHand = [angles.hour, angles.minute, angles.second]
        for hand in hands {
            hand.entity.orientation = hand.rest * simd_quatf(angle: -Float(byHand[hand.which]), axis: [0, 0, 1])
        }
    }
}
#endif

#if os(visionOS)
import OSLog
import SwiftUI

/// A room's sounds playing: each from its entity, as a bed, or turning with the head; now and then
/// for those that come and go. Only in Focus Mode's immersive space, where RealityKit plays audio.
@MainActor
final class FocusRoomSoundscape {
    /// Sounds playing round and round, paused while the level is 0.
    private var loops: [AudioPlaybackController] = []
    /// Sounds played now and then, while they play.
    private var oneShots: [AudioPlaybackController] = []
    private var tasks: [Task<Void, Never>] = []
    /// Over every sound's own gain; nil is silence.
    private var master: Double?
    /// Each sound's own entity, under the one it comes from, so two sounds there keep their own
    /// gains (the loft's city bed and its distant siren share `snd_city`).
    private var emitters: [(entity: Entity, sound: FocusRoomSounds.Sound)] = []
    private static let log = Logger(subsystem: "com.glasspowertools", category: "FocusEnvironments")

    /// Starts `sounds` from `folder` in `model`, at Settings' `level` (0 is none).
    init(_ sounds: FocusRoomSounds, folder: URL, in model: Entity, level: Double) {
        for sound in sounds.sounds where sound.kind != .channel {
            if let entity = sound.entity, model.findEntity(named: entity) == nil {
                Self.log.info("Room sound \(sound.id, privacy: .public) skipped: no entity \(entity, privacy: .public)")
            }
        }
        for sound in sounds.playable(hasEntity: { model.findEntity(named: $0) != nil }) {
            let parent = sound.entity.flatMap { model.findEntity(named: $0) } ?? model
            let emitter = Entity()
            emitter.name = "sound-\(sound.id)"
            parent.addChild(emitter)
            emitters.append((emitter, sound))
        }
        setLevel(level)
        for (emitter, sound) in emitters {
            let file = folder.appendingPathComponent(sound.file)
            tasks.append(Task { [weak self] in
                await self?.play(sound, from: file, on: emitter)
            })
        }
    }

    /// Settings' level, as it changes: every sound's gain over its own.
    func setLevel(_ level: Double) {
        master = FocusRoomSounds.masterGain(level: level)
        for (emitter, sound) in emitters {
            let gain = master.map { $0 + sound.clampedGain } ?? -120
            switch sound.kind {
            case .spatial: emitter.components.set(SpatialAudioComponent(gain: gain))
            case .ambient: emitter.components.set(AmbientAudioComponent(gain: gain))
            case .channel: emitter.components.set(ChannelAudioComponent(gain: gain))
            }
        }
        for controller in loops {
            if master == nil { controller.pause() } else if !controller.isPlaying { controller.play() }
        }
        if master == nil {
            oneShots.forEach { $0.stop() }
            oneShots = []
        }
    }

    /// Silence: every sound stopped and every wait given up.
    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        (loops + oneShots).forEach { $0.stop() }
        loops = []
        oneShots = []
        emitters.forEach { $0.entity.removeFromParent() }
        emitters = []
    }

    private func play(_ sound: FocusRoomSounds.Sound, from file: URL, on emitter: Entity) async {
        let resource: AudioFileResource
        // A bed playing round and round streams: decoded whole, the loft's 120 s city alone is about 46 MB,
        // beside a room of a million faces. One played now and then is short, kept to play again.
        let streams = sound.interval == nil
        do {
            resource = try await AudioFileResource(contentsOf: file,
                                                   configuration: .init(loadingStrategy: streams ? .stream : .preload,
                                                                        shouldLoop: sound.loop && streams))
        } catch {
            Self.log.error("Room sound \(sound.id, privacy: .public) couldn't be read: \(String(describing: error), privacy: .public)")
            return
        }
        guard !Task.isCancelled else { return }
        var generator = SystemRandomNumberGenerator()
        guard sound.interval != nil else {
            let controller = emitter.playAudio(resource)
            if master == nil { controller.pause() }
            loops.append(controller)
            Self.log.info("Room sound \(sound.id, privacy: .public) \(controller.isPlaying ? "playing" : "paused", privacy: .public), round and round")
            return
        }
        while let wait = sound.nextWait(using: &generator) {
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            oneShots.removeAll { !$0.isPlaying }
            guard master != nil else { continue }
            let controller = emitter.playAudio(resource)
            oneShots.append(controller)
            Self.log.info("Room sound \(sound.id, privacy: .public) \(controller.isPlaying ? "playing" : "not playing", privacy: .public), once")
        }
    }
}
/// A room's events happening: each loaded once and kept out of sight at one of its anchors, then, a
/// random number of seconds apart, shown at one chosen at random, its motion played once, and hidden
/// again. Not with Reduce Motion, which leaves them out.
@MainActor
final class FocusRoomHappenings {
    private var tasks: [Task<Void, Never>] = []
    private var events: [Entity] = []
    private static let log = Logger(subsystem: "com.glasspowertools", category: "FocusEnvironments")

    init(_ list: FocusRoomEvents, folder: URL, in model: Entity) {
        let playable = list.playable(hasEntity: { model.findEntity(named: $0) != nil })
        for event in list.events where !playable.contains(event) {
            Self.log.info("Room event \(event.id, privacy: .public) skipped: no anchor, a bad file name or no wait")
        }
        for event in playable {
            let file = folder.appendingPathComponent(event.file)
            tasks.append(Task { [weak self] in await self?.run(event, from: file, in: model) })
        }
    }

    /// Nothing more happens, and nothing is left showing.
    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        events.forEach { $0.removeFromParent() }
        events = []
    }

    private func run(_ event: FocusRoomEvents.Event, from file: URL, in model: Entity) async {
        let entity: Entity
        do {
            entity = try await Entity(contentsOf: file)
        } catch {
            Self.log.error("Room event \(event.id, privacy: .public) couldn't be read: \(String(describing: error), privacy: .public)")
            return
        }
        let anchors = event.anchors.compactMap { model.findEntity(named: $0) }
        guard !Task.isCancelled, let first = anchors.first else { return }
        entity.isEnabled = false
        first.addChild(entity)
        events.append(entity)
        let motion = entity.availableAnimations
        let seconds = FocusRoomEvents.Event.showing(motionSeconds: motion.map(\.definition.duration).max(),
                                                    declared: event.seconds)
        var generator = SystemRandomNumberGenerator()
        while let wait = event.nextWait(using: &generator) {
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            let anchor = anchors.randomElement(using: &generator) ?? first
            anchor.addChild(entity)
            entity.isEnabled = true
            let playing = motion.map { entity.playAnimation($0, transitionDuration: 0) }
            Self.log.info("Room event \(event.id, privacy: .public) at \(anchor.name, privacy: .public) for \(seconds, privacy: .public) s")
            let ended: Bool
            do { try await Task.sleep(for: .seconds(seconds)); ended = false } catch { ended = true }
            playing.forEach { $0.stop() }
            entity.isEnabled = false
            if ended { return }
        }
    }
}

/// The digital clock and date panel a room can have (`FocusRoomLife.placeDigitalClock`): the time
/// large, the day and date under it, on a dark face, as a clock on a wall reads.
struct FocusRoomDigitalClockView: View {
    static let attachmentID = "focus-room-digital-clock"

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 4) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 120, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 34, weight: .regular, design: .rounded))
                    .opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 56)
            .padding(.vertical, 32)
            .background(.black.opacity(0.6), in: .rect(cornerRadius: 32))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.attachmentID)
    }
}
#endif
