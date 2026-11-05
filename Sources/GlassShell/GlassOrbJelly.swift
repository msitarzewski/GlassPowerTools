//
//  GlassOrbJelly.swift
//  Glass Power Tools — GlassShell
//
//  The orbs as drops of liquid (the owner, 2026-11-05: "can we give the dock resize animation and the pulsing actual
//  liquid effects with metal or reality kit? like awesome water effects, not cheesy animations", then "Like a snap to
//  wobble jelly feel?"). His choices: Metal shaders with Apple's glass, on the Mac and Vision Pro alike; a busy orb as
//  drops falling into it, rings spreading across its picture and its rim shivering as each reaches it; a window docking
//  or leaving sends a wave of wobble along the dock's line.
//
//  The physics, apart from drawing it, so it is tested without a screen. A drop's rim wobbles in its surface modes, as
//  Rayleigh worked out for a drop held round by surface tension: an oval (mode 2), three lobes (3), four (4), five (5),
//  each ringing faster than the one before and dying sooner. A kick sets them going from round, as a push does; the
//  drop keeps its area as it wobbles. `GlassOrbLiquid.swift` draws it: the rim as a shape Apple's glass takes, the
//  picture inside stretched with it and rippled by a shader (`Resources/GlassOrbLiquid.metal`).
//

import Foundation

/// A drop's rim at a moment, as a share of a round drop's radius at each angle: 1 + `mean` + Σ cₙ cos nθ + sₙ sin nθ
/// for n = 2…5. Angles run as SwiftUI draws them: 0 toward the trailing side, π/2 down.
public struct GlassDropletDeformation: Equatable, Sendable {
    /// The modes, in the order of `cosines` and `sines`.
    public static let modes = [2, 3, 4, 5]

    public var cosines: [Double] = [0, 0, 0, 0]
    public var sines: [Double] = [0, 0, 0, 0]

    public init() {}

    public static let round = GlassDropletDeformation()

    /// What keeps the drop's area a round one's as it wobbles: a squashed drop is pulled in a little all round.
    public var mean: Double {
        let squared = zip(cosines, sines).reduce(0) { $0 + $1.0 * $1.0 + $1.1 * $1.1 }
        return (max(1 - squared / 2, 0)).squareRoot() - 1
    }

    /// The rim's distance from the middle at `angle`, as a share of the round drop's radius.
    public func radius(at angle: Double) -> Double {
        var radius = 1 + mean
        for (index, n) in Self.modes.enumerated() {
            radius += cosines[index] * cos(Double(n) * angle) + sines[index] * sin(Double(n) * angle)
        }
        return radius
    }

    /// The most the rim stands from round anywhere, roughly: the sum of the modes' sizes.
    public var reach: Double {
        zip(cosines, sines).reduce(0) { $0 + ($1.0 * $1.0 + $1.1 * $1.1).squareRoot() }
    }

    /// Nothing to see.
    public var isRound: Bool { reach < 0.0005 }

    /// Mode `n` at `size`, pulling the rim in along `angle` when `size` is positive.
    mutating func add(mode n: Int, size: Double, along angle: Double) {
        guard let index = Self.modes.firstIndex(of: n) else { return }
        cosines[index] -= size * cos(Double(n) * angle)
        sines[index] -= size * sin(Double(n) * angle)
    }
}

/// A push that sets a drop wobbling, from round: as it lands, or as a neighbour bumps it.
public struct GlassJellyKick: Equatable, Sendable {
    /// When it lands.
    public var start: Date
    /// How hard: how far the rim is pulled in along `angle` at the first squash, as a share of the radius.
    public var size: Double
    /// Along which way it is squashed first (0 along the row, π/2 from above).
    public var angle: Double
    /// How much of the push goes into each of the modes 2…5.
    public var shares: [Double]

    public init(start: Date, size: Double, angle: Double, shares: [Double] = GlassOrbJelly.bump) {
        self.start = start
        self.size = size
        self.angle = angle
        self.shares = shares
    }

    /// When it has died away.
    public var end: Date { start.addingTimeInterval(GlassOrbJelly.settle) }
}

public enum GlassOrbJelly {
    /// A landing: mostly the oval's squash, some three-lobed, a touch of the rest.
    public static let landing: [Double] = [1, 0.4, 0.16, 0.06]
    /// A bump from a neighbour: the oval, a little three-lobed.
    public static let bump: [Double] = [1, 0.25, 0, 0]
    /// The rim's shiver as a ring of ripples reaches it: the small, quick modes.
    public static let shiver: [Double] = [0, 0.7, 1, 0.2]

    /// The oval's wobble: about three times a second, a jelly's.
    public static let ovalFrequency = 2 * Double.pi * 3.0
    /// How fast the oval dies away (per second): within about a second.
    public static let ovalDamping = 4.4
    /// Long enough for every kick to have died away to nothing seen.
    public static let settle: TimeInterval = 1.4

    /// How fast mode `n` rings: Rayleigh's ωₙ² ∝ n(n − 1)(n + 2) for a drop held round by its surface tension.
    public static func frequency(of n: Int) -> Double {
        ovalFrequency * (Double(n * (n - 1) * (n + 2)) / 8).squareRoot()
    }

    /// How fast mode `n` dies away: the finer modes sooner, as in a jelly.
    public static func damping(of n: Int) -> Double { ovalDamping * Double(n - 1) }

    /// The drop at `now`, from `kicks` and the rings of ripples that have reached its rim (`rings`;
    /// `GlassOrbPulseClock.atRim`).
    /// `turn` sets which way this orb's shivers go, so orbs busy together don't shiver alike.
    public static func deformation(at now: Date, kicks: [GlassJellyKick],
                                   rings: [GlassOrbPulseClock.Drop] = [], turn: Double = 0) -> GlassDropletDeformation {
        var drop = GlassDropletDeformation()
        for kick in kicks {
            add(kick.size, shares: kick.shares, along: kick.angle, after: now.timeIntervalSince(kick.start), to: &drop)
        }
        for ring in rings {
            // Each drop's shiver squashes its own way, the golden angle on from the last, so the rim never shivers the
            // same way twice running.
            add(GlassOrbRipple.shiver, shares: shiver, along: turn + Double(ring.number) * 2.39996, after: ring.age, to: &drop)
        }
        return drop
    }

    /// A push of `size` some `time` after it: each mode starting from round, as a push sets a drop going, ringing at its
    /// own pace and dying away at its own.
    static func add(_ size: Double, shares: [Double], along angle: Double, after time: TimeInterval,
                    to drop: inout GlassDropletDeformation) {
        guard time > 0, time < settle else { return }
        for (index, n) in GlassDropletDeformation.modes.enumerated() where index < shares.count && shares[index] != 0 {
            let omega = frequency(of: n)
            // Scaled so the first squash reaches `size` × share: sin peaks at a quarter turn.
            let peak = exp(-damping(of: n) * Double.pi / (2 * omega))
            let amount = size * shares[index] / peak * exp(-damping(of: n) * time) * sin(omega * time)
            drop.add(mode: n, size: amount, along: angle)
        }
    }

    /// How hard a change at `source` bumps the orb at `index` along the dock's line, and when: the wave of wobble going
    /// out along the line from where a window landed, or from the gap one left (a source between two orbs). Smaller and
    /// later each orb further on; none past where it would show.
    public static func wave(from source: Double, count: Int, at start: Date, along angle: Double,
                            landing: Int? = nil) -> [Int: GlassJellyKick] {
        var kicks: [Int: GlassJellyKick] = [:]
        for index in 0..<count {
            if index == landing {
                // Its own landing: squashed from above, where it fell from.
                kicks[index] = GlassJellyKick(start: start.addingTimeInterval(landingDelay), size: landingSize,
                                              angle: Double.pi / 2, shares: Self.landing)
                continue
            }
            let distance = abs(Double(index) - source)
            let size = bumpSize * pow(falloff, distance)
            guard size >= 0.008 else { continue }
            let delay = (landing == nil ? 0 : landingDelay) + waveDelay * distance
            kicks[index] = GlassJellyKick(start: start.addingTimeInterval(delay), size: size, angle: angle)
        }
        return kicks
    }

    /// The landing's squash, and when it lands after the orb appears (`GlassOrbDropArrival`'s fall).
    public static let landingSize = 0.15
    public static let landingDelay: TimeInterval = 0.28
    /// A neighbour's bump next to it, and how much less each orb further on.
    public static let bumpSize = 0.09
    public static let falloff = 0.62
    /// How long the wave takes from one orb to the next.
    public static let waveDelay: TimeInterval = 0.07
}

/// The rings of ripples in a busy orb: a drop falls into its middle every `period` while its session is busy, and its
/// rings spread to the rim, reaching it after `GlassOrbRipple.reach`, where the rim shivers. When the session goes
/// quiet, no more drops fall, and the last rings run out.
public struct GlassOrbPulseClock: Equatable, Sendable {
    /// Busy since, and quiet since (nil while busy).
    public private(set) var since: Date?
    public private(set) var until: Date?

    public init() {}

    /// A drop every so often.
    public static let period: TimeInterval = 1.5
    /// How long after a drop falls its rings are seen: to the rim and a little past, fading.
    public static let lifetime: TimeInterval = GlassOrbRipple.reach + 0.45
    /// The drops the shader is told about.
    public static let drops = 4
    /// How long after it falls a drop is seen at all: its rings, then the rim's shiver.
    static var seen: TimeInterval { max(lifetime, GlassOrbRipple.reach + GlassOrbRipple.shiverLength) }

    public mutating func busy(_ busy: Bool, at now: Date) {
        if busy {
            if since == nil || until != nil { since = now; until = nil }
        } else if since != nil, until == nil {
            until = now
        }
    }

    /// A drop that fell: its number since the session went busy, and how long ago, in seconds.
    public struct Drop: Equatable, Sendable {
        public var number: Int
        public var age: Double
    }

    /// The drops still seen at `now`, or still shivering the rim, newest first.
    public func drops(at now: Date) -> [Drop] {
        guard let since, now >= since else { return [] }
        let last = Int(((min(now, until ?? now)).timeIntervalSince(since) / Self.period).rounded(.down))
        return stride(from: last, through: max(last - Self.drops + 1, 0), by: -1).compactMap { number in
            let age = now.timeIntervalSince(since) - Double(number) * Self.period
            return age <= Self.seen ? Drop(number: number, age: age) : nil
        }
    }

    /// The rings the picture shows at `now`: each drop's age, while its rings are seen.
    public func ages(at now: Date) -> [Double] {
        drops(at: now).map(\.age).filter { $0 <= Self.lifetime }
    }

    /// The rings that have reached the rim, each with how long since: what shivers it.
    public func atRim(at now: Date) -> [Drop] {
        drops(at: now).compactMap { drop in
            let since = drop.age - GlassOrbRipple.reach
            return since > 0 && since < GlassOrbRipple.shiverLength ? Drop(number: drop.number, age: since) : nil
        }
    }

    /// Whether the rim shivers at `now`. Only then is the rim, and Apple's glass around it, drawn again with the
    /// display; the picture's ripples alone redraw only the picture.
    public func rimMoves(at now: Date) -> Bool { !atRim(at: now).isEmpty }

    /// When the rim next starts or stops shivering after `now`: nil once it won't again.
    public func nextRimChange(after now: Date) -> Date? {
        guard let since else { return nil }
        let first = Int((now.timeIntervalSince(since) - GlassOrbRipple.reach - GlassOrbRipple.shiverLength) / Self.period)
        var changes: [Date] = []
        for number in max(first, 0)...(max(first, 0) + 2) {
            let fell = since.addingTimeInterval(Double(number) * Self.period)
            if let until, fell > until { break }
            let start = fell.addingTimeInterval(GlassOrbRipple.reach)
            changes += [start, start.addingTimeInterval(GlassOrbRipple.shiverLength)]
        }
        return changes.filter { $0 > now }.min()
    }

    /// Whether anything moves at `now`: busy, or rings and shivers still running out.
    public func isLive(at now: Date) -> Bool {
        guard since != nil else { return false }
        guard let quietAt else { return true }
        return now < quietAt
    }

    /// When the last ring and shiver have run out; nil while busy, or never busy.
    public var quietAt: Date? {
        until.map { $0.addingTimeInterval(Self.seen) }
    }
}

/// The ripples' measures, shared with the shader.
public enum GlassOrbRipple {
    /// How long a ring takes from the middle to the rim.
    public static let reach: TimeInterval = 0.8
    /// The rim's shiver as each ring reaches it: a tremble, not a wobble (at 0.028, mostly four and five lobes, the drop
    /// went lumpy every drop in the Vision Pro simulator, 2026-11-05; at 0.012 it was a third of a point on the Mac).
    public static let shiver = 0.02
    /// How long a shiver is seen: its modes have all but died away by then.
    public static let shiverLength: TimeInterval = 0.5
}

/// The pushes each orb in a dock has had, by its identifier: as windows dock and leave, a wave along the line (the owner,
/// 2026-11-05: "A wave through the row"). Connections is first in the line, and wobbles with the rest.
public struct GlassOrbJellyField: Equatable, Sendable {
    public private(set) var kicks: [String: [GlassJellyKick]] = [:]

    public init() {}

    public func kicks(for id: String) -> [GlassJellyKick] { kicks[id] ?? [] }

    /// The line went from `old` to `new` (identifiers in order, Connections first) at `now`, along `orientation`: each
    /// orb that came lands, and its neighbours feel it; the gap each one that left closes, and its neighbours feel
    /// that; an orb carried to another place lands there.
    public mutating func changed(from old: [String], to new: [String], along orientation: GlassOrbDockOrientation,
                                 at now: Date = .now) {
        let angle = orientation == .horizontal ? 0 : Double.pi / 2
        var waves: [[Int: GlassJellyKick]] = []
        for (index, id) in new.enumerated() where !old.contains(id) {
            waves.append(GlassOrbJelly.wave(from: Double(index), count: new.count, at: now, along: angle, landing: index))
        }
        for (index, id) in old.enumerated() where !new.contains(id) {
            // Where the gap is in the new line: between the orbs that stood either side of it.
            let before = old[..<index].filter(new.contains).count
            waves.append(GlassOrbJelly.wave(from: Double(before) - 0.5, count: new.count, at: now, along: angle))
        }
        if waves.isEmpty, Set(old) == Set(new), old != new {
            let moved = new.indices.max { a, b in
                abs((old.firstIndex(of: new[a]) ?? a) - a) < abs((old.firstIndex(of: new[b]) ?? b) - b)
            }
            if let moved {
                waves.append(GlassOrbJelly.wave(from: Double(moved), count: new.count, at: now, along: angle, landing: moved))
            }
        }
        guard !waves.isEmpty else { return }
        var kept = kicks.filter { new.contains($0.key) }.mapValues { $0.filter { $0.end > now } }
        for wave in waves {
            for (index, kick) in wave { kept[new[index], default: []].append(kick) }
        }
        kicks = kept.filter { !$0.value.isEmpty }
    }
}
