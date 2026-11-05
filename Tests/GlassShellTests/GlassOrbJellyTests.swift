import Foundation
import Testing
@testable import GlassShell

/// The orbs as drops of liquid (the owner, 2026-11-05: "actual liquid effects ... Like a snap to wobble jelly feel?"):
/// a drop's rim wobbling in its surface modes from a push and dying away, keeping its area; drops of ripples falling
/// into a busy orb, the rim shivering as each ring reaches it; and a wave of wobble along the dock's line as windows
/// dock and leave.
@Suite("The orbs' drops: wobble, ripples and the wave along the dock")
struct GlassOrbJellyTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func area(of drop: GlassDropletDeformation) -> Double {
        let steps = 2_000
        return (0..<steps).reduce(0) { total, step in
            let r = drop.radius(at: 2 * Double.pi * Double(step) / Double(steps))
            return total + r * r / 2 * (2 * Double.pi / Double(steps))
        }
    }

    @Test("with nothing pushing it, a drop is round")
    func round() {
        let drop = GlassOrbJelly.deformation(at: start, kicks: [])
        #expect(drop.isRound)
        #expect(drop.radius(at: 0.7) == 1)
    }

    @Test("a push starts from round, squashes the drop along its way first and bulges it across, then dies away")
    func push() {
        let kick = GlassJellyKick(start: start, size: 0.1, angle: 0)
        #expect(GlassOrbJelly.deformation(at: start, kicks: [kick]).isRound, "from round: no jump at the push")
        // The oval's first squash, a quarter of its turn on.
        let squash = GlassOrbJelly.deformation(at: start.addingTimeInterval(Double.pi / 2 / GlassOrbJelly.ovalFrequency),
                                               kicks: [kick])
        #expect(squash.radius(at: 0) < 0.93, "pulled in along the push")
        #expect(squash.radius(at: Double.pi / 2) > 1.06, "bulging across it")
        #expect(GlassOrbJelly.deformation(at: start.addingTimeInterval(1.0), kicks: [kick]).reach < 0.003,
                "all but still within a second")
        #expect(GlassOrbJelly.deformation(at: kick.end, kicks: [kick]).isRound, "still once it has settled")
    }

    @Test("a wobbling drop keeps its area, as liquid does")
    func keepsArea() {
        let kick = GlassJellyKick(start: start, size: 0.15, angle: 1, shares: GlassOrbJelly.landing)
        for time in stride(from: 0.02, to: 0.6, by: 0.04) {
            let drop = GlassOrbJelly.deformation(at: start.addingTimeInterval(time), kicks: [kick])
            #expect(abs(area(of: drop) - Double.pi) / Double.pi < 0.001, "at \(time) s")
        }
    }

    @Test("the finer modes ring faster and die sooner, as Rayleigh's do")
    func modes() {
        let frequencies = GlassDropletDeformation.modes.map(GlassOrbJelly.frequency(of:))
        #expect(abs(frequencies[1] / frequencies[0] - (30.0 / 8).squareRoot()) < 1e-9, "three lobes: √(3·2·5/8) the oval's")
        #expect(frequencies == frequencies.sorted() && Set(frequencies).count == 4)
        let dampings = GlassDropletDeformation.modes.map(GlassOrbJelly.damping(of:))
        #expect(dampings == dampings.sorted() && Set(dampings).count == 4)
    }

    @Test("a busy orb has a drop fall into it every so often, and none after it goes quiet; the last rings run out")
    func drops() {
        var clock = GlassOrbPulseClock()
        #expect(!clock.isLive(at: start))
        clock.busy(true, at: start)
        #expect(clock.ages(at: start.addingTimeInterval(0.1)).count == 1)
        let period = GlassOrbPulseClock.period
        let next = start.addingTimeInterval(period + 0.2)
        let ages = clock.ages(at: next)
        #expect(ages.count == 1 && abs(ages[0] - 0.2) < 1e-9, "a second drop a period on, the first's rings gone: \(ages)")
        #expect(clock.drops(at: next).map(\.number) == [1], "the first's rings and shiver over before the next falls")
        clock.busy(true, at: start.addingTimeInterval(period + 0.3))
        #expect(clock.since == start, "busy still: the same drops")
        let quiet = start.addingTimeInterval(period + 0.5)
        clock.busy(false, at: quiet)
        let later = quiet.addingTimeInterval(0.5)
        #expect(clock.drops(at: quiet.addingTimeInterval(period)).allSatisfy { $0.number <= 1 }, "no drop falls after it goes quiet")
        #expect(clock.isLive(at: later), "the last rings and shivers still running out")
        #expect(!clock.isLive(at: clock.quietAt!), "and then nothing")
        #expect(clock.ages(at: clock.quietAt!).isEmpty)
    }

    @Test("the rim shivers only once a ring has reached it, each drop's shiver its own way")
    func shiver() {
        var clock = GlassOrbPulseClock()
        clock.busy(true, at: start)
        let before = start.addingTimeInterval(GlassOrbRipple.reach - 0.05)
        #expect(clock.atRim(at: before).isEmpty)
        #expect(GlassOrbJelly.deformation(at: before, kicks: [], rings: clock.atRim(at: before)).isRound)
        let after = start.addingTimeInterval(GlassOrbRipple.reach + 0.03)
        #expect(!GlassOrbJelly.deformation(at: after, kicks: [], rings: clock.atRim(at: after)).isRound)
        // The next drop's shiver, the same time after it reached the rim, goes another way.
        let second = after.addingTimeInterval(GlassOrbPulseClock.period)
        #expect(clock.atRim(at: after).map(\.number) == [0] && clock.atRim(at: second).map(\.number) == [1])
        let one = GlassOrbJelly.deformation(at: after, kicks: [], rings: clock.atRim(at: after))
        let two = GlassOrbJelly.deformation(at: second, kicks: [], rings: clock.atRim(at: second))
        #expect(abs(one.reach - two.reach) < 1e-9 && one != two, "as strong, another way")
    }

    @Test("the rim, and the glass around it, is drawn again only while a ring's shiver runs, not all the while it's busy")
    func rimWindows() {
        var clock = GlassOrbPulseClock()
        clock.busy(true, at: start)
        let reach = GlassOrbRipple.reach, length = GlassOrbRipple.shiverLength, period = GlassOrbPulseClock.period
        func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
        func next(_ seconds: Double) -> Double? { clock.nextRimChange(after: at(seconds))?.timeIntervalSince(start) }
        #expect(!clock.rimMoves(at: at(0.1)), "the rings still spreading")
        #expect(abs((next(0.1) ?? 0) - reach) < 1e-6, "until the first reaches the rim")
        #expect(clock.rimMoves(at: at(reach + 0.1)))
        #expect(abs((next(reach + 0.1) ?? 0) - (reach + length)) < 1e-6, "for a moment")
        #expect(!clock.rimMoves(at: at(reach + length + 0.05)))
        #expect(abs((next(reach + length + 0.05) ?? 0) - (period + reach)) < 1e-6, "until the next drop's rings reach it")
        clock.busy(false, at: at(period + 0.2))
        #expect(abs((next(period + 0.3) ?? 0) - (period + reach)) < 1e-6, "the last drop's shiver still to come")
        #expect(next(period + reach + length + 0.01) == nil, "and then never")
        #expect(clock.quietAt!.timeIntervalSince(at(period + 0.2)) >= reach + length, "quiet only after it")
    }

    @Test("a window docking lands, and the wave goes out along the line, smaller and later each orb further on")
    func wave() {
        let kicks = GlassOrbJelly.wave(from: 3, count: 6, at: start, along: 0, landing: 3)
        let landing = kicks[3]
        #expect(landing?.angle == Double.pi / 2 && landing?.size == GlassOrbJelly.landingSize, "squashed from above")
        #expect(landing?.start == start.addingTimeInterval(GlassOrbJelly.landingDelay), "as its fall ends")
        #expect(kicks[2]!.size == kicks[4]!.size && kicks[2]!.angle == 0, "the neighbours alike, along the row")
        #expect(kicks[2]!.size > kicks[1]!.size && kicks[1]!.size > kicks[0]!.size, "smaller further on")
        #expect(kicks[2]!.start < kicks[1]!.start && kicks[1]!.start < kicks[0]!.start, "later further on")
        #expect(kicks[0]!.start > landing!.start, "after it lands")
        let far = GlassOrbJelly.wave(from: 0, count: 12, at: start, along: 0)
        #expect(far[11] == nil, "none past where it would show")
    }

    @Test("the dock's field: an orb docking lands with its neighbours bumped; one leaving bumps both sides of its gap")
    func field() {
        var field = GlassOrbJellyField()
        field.changed(from: ["connections", "a", "b"], to: ["connections", "a", "b", "c"], along: .horizontal, at: start)
        #expect(field.kicks(for: "c").first?.size == GlassOrbJelly.landingSize)
        #expect(field.kicks(for: "b").count == 1 && field.kicks(for: "connections").count == 1, "Connections too")
        let later = start.addingTimeInterval(5)
        field.changed(from: ["connections", "a", "b", "c"], to: ["connections", "a", "c"], along: .vertical, at: later)
        let a = field.kicks(for: "a"), c = field.kicks(for: "c")
        #expect(a.count == 1 && c.count == 1, "the old pushes forgotten, a new one each side of the gap")
        #expect(a.first?.size == c.first?.size && a.first?.angle == Double.pi / 2, "alike, along the column")
        #expect(field.kicks(for: "b").isEmpty)
    }

    @Test("an orb carried to another place lands there")
    func carried() {
        var field = GlassOrbJellyField()
        field.changed(from: ["connections", "a", "b", "c"], to: ["connections", "c", "a", "b"], along: .horizontal, at: start)
        #expect(field.kicks(for: "c").first?.size == GlassOrbJelly.landingSize)
    }

    @Test("the same line again moves nothing")
    func unchanged() {
        var field = GlassOrbJellyField()
        field.changed(from: ["connections", "a"], to: ["connections", "a"], along: .horizontal, at: start)
        #expect(field.kicks.isEmpty)
    }
}
