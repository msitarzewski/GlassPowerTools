import CoreGraphics
import Testing
@testable import GlassShell

/// A two-handed pinch on Vision Pro, in Show All Windows' steps (2026-10-21): in opens it, further in
/// takes the window around the person, out steps back. Each step once per gesture.
@Suite("Show All Windows by hand")
struct GlassPinchStepsTests {
    private func run(_ scales: [CGFloat]) -> [GlassPinchSteps.Step] {
        var steps = GlassPinchSteps()
        return scales.compactMap { steps.track($0) }
    }

    @Test("a pinch in opens it once; held there, nothing more")
    func inward() {
        #expect(run([0.98, 0.9, 0.79, 0.75, 0.7, 0.72]) == [.inward])
    }

    @Test("pinched further, it goes around; a fast pinch goes straight there")
    func deeper() {
        #expect(run([0.95, 0.78, 0.6, 0.5, 0.4]) == [.inward, .deeper])
        #expect(run([1, 0.5]) == [.deeper], "a pinch that passes both in one moment goes around at once")
    }

    @Test("a pinch out steps back, once")
    func outward() {
        #expect(run([1.05, 1.2, 1.3, 1.6]) == [.outward])
    }

    @Test("a hand that drifts does nothing, and a gesture ended starts again")
    func driftAndReset() {
        #expect(run([1.02, 0.97, 0.88, 1.1, 0.95]).isEmpty)
        var steps = GlassPinchSteps()
        #expect(steps.track(0.7) == .inward)
        #expect(steps.track(0.7) == nil)
        steps.reset()
        #expect(steps.track(0.7) == .inward, "the next gesture opens it again")
    }

    @Test("nonsense from the system is ignored")
    func nonsense() {
        #expect(run([.nan, .infinity, 0, -1]).isEmpty)
    }
}
