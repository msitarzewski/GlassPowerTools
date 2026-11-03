import CoreGraphics
import SwiftUI
import Testing
@testable import GlassShell

/// A window's overview off the Mac (D99; the owner, 2026-11-03: "both seem to be missing coverflow and the new
/// expose"): the carousel's row in real depth on Vision Pro (his choice), and the overview's find.
@Suite("A window's overview off the Mac")
struct GlassTabOverviewTests {
    let geometry = GlassCarouselGeometry(tile: CGSize(width: 520, height: 325), turn: 50)

    /// The album in space: the front nearest, its neighbours on the window's plane, each turned toward the middle.
    /// A neighbour's outer edge comes toward you but never as far as the front, or it would cover it.
    @Test("In depth the front stands nearest; a neighbour's outer edge comes toward you but stays behind the front")
    func depthKeepsTheFrontNearest() {
        let front = geometry.depthPose(0)
        #expect(front.z == geometry.frontLift && front.angle == 0 && front.x == 0)
        for d in [-3.0, -1, 1, 3] {
            let pose = geometry.depthPose(d)
            #expect(pose.z == 0, "on the window's plane at \(d): \(pose.z)")
            #expect(abs(pose.angle) == geometry.turn, "turned toward the middle at \(d)")
            // Its outer edge, turned toward you about its middle.
            let outer = geometry.tile.width / 2 * pose.scale * CGFloat(sin(abs(pose.angle) * .pi / 180))
            #expect(outer > 0 && outer < front.z, "outer edge \(outer) behind the front \(front.z) at \(d)")
        }
        // Not lifted so far that the front swamps the window (twice a neighbour's reach drew it over 60%).
        let reach = geometry.tile.width / 2 * geometry.scale(1) * CGFloat(sin(geometry.turn * .pi / 180))
        #expect(geometry.frontLift < reach * 1.5, "\(geometry.frontLift) against a reach of \(reach)")
    }

    @Test("In depth an item comes down from the front's place to the plane as it leaves, without a jump")
    func depthFlows() {
        var last = geometry.depthPose(0).z
        for step in 1...100 {
            let z = geometry.depthPose(Double(step) / 100).z
            #expect(z <= last && last - z < geometry.frontLift / 50, "at \(Double(step) / 100): \(last) to \(z)")
            last = z
        }
        #expect(geometry.depthPose(0.5).z == geometry.depthPose(-0.5).z, "the same either side")
        // Turned the way the flat row turns, so the two agree on which edge comes toward you.
        #expect(geometry.depthPose(1).angle == geometry.angle(1) && geometry.depthPose(-1).angle == geometry.angle(-1))
    }

    @Test("Find keeps tabs whose name or place holds what was typed, in any case; nothing typed keeps all")
    func findNarrows() {
        func item(_ title: String, _ detail: String?) -> GlassOverviewItem {
            GlassOverviewItem(id: UUID(), title: title, detail: detail, identifier: title,
                              picture: { nil }, mark: { nil })
        }
        let items = [item("build", "shop · main · ann@alpha"), item("logs", "ann@bravo"), item("API", nil)]
        #expect(GlassOverviewItem.filtered(items, by: "").count == 3)
        #expect(GlassOverviewItem.filtered(items, by: "  ").count == 3)
        #expect(GlassOverviewItem.filtered(items, by: "api").map(\.title) == ["API"])
        #expect(GlassOverviewItem.filtered(items, by: "BRAVO").map(\.title) == ["logs"])
        #expect(GlassOverviewItem.filtered(items, by: "shop").map(\.title) == ["build"])
        #expect(GlassOverviewItem.filtered(items, by: "zzz").isEmpty)
    }

    @Test("The grid's tiles stand where Show All Windows would put one group of them, for the arrow keys")
    func gridFramesForTheArrows() {
        let size = CGSize(width: 1000, height: 700)
        let frames = GlassOverviewGrid<EmptyView>.frames(count: 5, in: size)
        #expect(frames == GlassAllWindowsLayout(tileCounts: [5], in: size).groups[0].tileFrames)
        #expect(frames.count == 5)
        let ids = Array(0..<5)
        let items = zip(ids, frames).map { (id: $0, frame: $1) }
        // From the first, right goes to the second, and down to the row below.
        #expect(GlassAllWindowsNavigation.moved(0, .right, in: items) == 1)
        let below = GlassAllWindowsNavigation.moved(0, .down, in: items)
        #expect(below.map { frames[$0].minY > frames[0].maxY } == true)
    }
}
