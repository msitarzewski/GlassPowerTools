import CoreGraphics
import Foundation
import Testing
@testable import GlassShell

/// The orb dock's geometry (D88; the owner, 2026-10-26 and 27): orbs flowing into rows as the dock's
/// shape allows and the dock snapping around them, a carried orb landing in any direction, names
/// opening toward the room, and the side a window comes back on from a tall dock.
@Suite("The orb dock's flow, landings, names and sides")
struct GlassOrbDockGeometryTests {
    private let connections = CGSize(width: 240, height: 320)
    private let ringed = CGSize(width: 280, height: 320)
    private let plain = CGSize(width: 200, height: 320)

    @Test("orbs fill a row and wrap to the next when the dock is too narrow; Connections is set apart")
    func wraps() {
        let sizes = [connections, ringed, plain, ringed]
        let wide = GlassOrbFlow.frames(of: sizes, width: 2000, gapAfterFirst: 24)
        #expect(wide.map(\.minY) == [0, 0, 0, 0], "one row when it fits")
        #expect(wide.map(\.minX) == [0, 264, 544, 744], "Connections, its gap, then each beside the last")

        let narrower = GlassOrbFlow.frames(of: sizes, width: 700, gapAfterFirst: 24)
        #expect(narrower.map(\.minY) == [0, 0, 320, 320], "the third starts a row: it would end at 744")
        #expect(narrower[2].minX == 0 && narrower[3].minX == 200, "a new row starts at the leading edge")
        #expect(GlassOrbFlow.size(of: narrower) == CGSize(width: 544, height: 640))
    }

    @Test("a dock one orb wide is a column on one line, Connections set apart above")
    func column() {
        let frames = GlassOrbFlow.frames(of: [connections, ringed, plain], width: 300, gapAfterFirst: 24)
        #expect(frames.map(\.minY) == [0, 344, 664], "each below the last, the gap after Connections")
        #expect(frames.map(\.midX) == [150, 150, 150], "on one line down the middle")
    }

    @Test("an orb wider than the dock has a row of its own; orbs of different heights stand on the row's middle")
    func oddSizes() {
        let frames = GlassOrbFlow.frames(of: [CGSize(width: 100, height: 100), CGSize(width: 500, height: 300)], width: 400)
        #expect(frames[1].minY == 100, "too wide: a row of its own")
        let row = GlassOrbFlow.frames(of: [CGSize(width: 100, height: 100), CGSize(width: 100, height: 300)], width: 400)
        #expect(row[0].midY == row[1].midY)
    }

    @Test("let go, the dock snaps to the widest row its orbs make, and hugs every row when they fit")
    func snapsAround() {
        let sizes = [connections, ringed, ringed]
        // 700 inside: Connections, its gap and one orb (544); the third wraps.
        let snapped = GlassOrbFlow.snapped(sizes, within: CGSize(width: 732, height: 900), inset: 16, gapAfterFirst: 24)
        #expect(snapped == CGSize(width: 544 + 32, height: 640 + 32))
        #expect(GlassOrbFlow.snapped(sizes, within: snapped, inset: 16, gapAfterFirst: 24) == snapped,
                "snapped again, it stays: the same rows fit")

        // Connections a third larger, as in the dock: a fraction of a point wide.
        let larger = [CGSize(width: 184 * 4.0 / 3, height: 320), ringed, ringed]
        let rounded = GlassOrbFlow.snapped(larger, within: CGSize(width: 732, height: 900), inset: 16, gapAfterFirst: 24)
        #expect(rounded.width == (184 * 4.0 / 3 + 24 + 280 + 32).rounded(.up), "whole points, rounded up")
        #expect(GlassOrbFlow.snapped(larger, within: rounded, inset: 16, gapAfterFirst: 24) == rounded,
                "rounded down, the second orb would have wrapped")
    }

    @Test("too short for every row, the dock snaps to the whole rows nearest its height, at least one")
    func nearestRows() {
        // A column: Connections, then three orbs below it, ending at 320, 664, 984 and 1304.
        let sizes = [connections, ringed, ringed, ringed]
        let column = { (height: CGFloat) in
            GlassOrbFlow.snapped(sizes, within: CGSize(width: 312, height: height), inset: 16, gapAfterFirst: 24)
        }
        let nearThree = column(900 + 32), nearTwo = column(700 + 32), tiny = column(100), roomy = column(5000)
        #expect(nearThree.height == 1016, "900 is nearer three rows (984) than two")
        #expect(nearTwo.height == 696, "700 is nearer two rows (664) than three")
        #expect(tiny.height == 352, "at least one row")
        #expect(roomy.height == 1336, "every row when they fit (1304), no more")
        #expect(nearTwo.width == 312, "a column is as wide as its widest orb")
        let alone = GlassOrbFlow.snapped([plain], within: CGSize(width: 100, height: 100), inset: 16,
                                         minimum: CGSize(width: 320, height: 320))
        #expect(alone == CGSize(width: 320, height: 352), "never narrower than visionOS makes a window")
    }

    @Test("an orb docked below what a short dock shows grows it to that row, up to three rows; one shown already changes nothing")
    func showsAnArrival() {
        // Snapped to one row: Connections and an orb; the third wraps out of sight.
        let wide = [connections, ringed, ringed]
        let oneRow = CGSize(width: 576, height: 352)
        let grown = GlassOrbFlow.showing(2, of: wide, within: oneRow, inset: 16, gapAfterFirst: 24, rows: 3)
        #expect(grown == CGSize(width: 576, height: 672), "grown to its row (640)")
        #expect(GlassOrbFlow.showing(1, of: wide, within: oneRow, inset: 16, gapAfterFirst: 24, rows: 3) == oneRow,
                "already shown")

        // A column one row tall: the second orb is on the third row, the third on the fourth.
        let column = [connections, ringed, ringed, ringed]
        let short = CGSize(width: 312, height: 352)
        let third = GlassOrbFlow.showing(2, of: column, within: short, inset: 16, gapAfterFirst: 24, rows: 3)
        #expect(third.height == 1016, "to the third row (984), past the one between")
        #expect(GlassOrbFlow.showing(3, of: column, within: short, inset: 16, gapAfterFirst: 24, rows: 3) == short,
                "the fourth row is past three: it scrolls to it instead")
    }

    @Test("a carried orb lands on the one under it in any direction, first over Connections or ahead, last past them")
    func landsIn2D() {
        let frames = [CGRect(x: 0, y: 0, width: 280, height: 320), CGRect(x: 280, y: 0, width: 200, height: 320),
                      CGRect(x: 0, y: 320, width: 280, height: 320)]
        let before = CGRect(x: 0, y: -344, width: 240, height: 320)
        #expect(GlassOrbDockOrder.landing(at: CGPoint(x: 100, y: 500), frames: frames, before: before) == .on(2), "down a row")
        #expect(GlassOrbDockOrder.landing(at: CGPoint(x: 380, y: 100), frames: frames, before: before) == .on(1), "across")
        #expect(GlassOrbDockOrder.landing(at: CGPoint(x: 100, y: -200), frames: frames, before: before) == .first, "over Connections")
        #expect(GlassOrbDockOrder.landing(at: CGPoint(x: -20, y: 100), frames: frames) == .first, "ahead of the first")
        #expect(GlassOrbDockOrder.landing(at: CGPoint(x: 600, y: 500), frames: frames) == .last, "past them all")
    }

    @Test("a name opens left only when the right lacks room and the left has more")
    func nameSide() {
        let needs = GlassOrbNameSide.reach(dotDiameter: 40, nameWidth: 150)
        #expect(needs == 190)
        #expect(!GlassOrbNameSide.opensLeading(trailingRoom: 400, leadingRoom: 50, needs: needs), "room on the right")
        #expect(GlassOrbNameSide.opensLeading(trailingRoom: 60, leadingRoom: 500, needs: needs), "near the right edge")
        #expect(!GlassOrbNameSide.opensLeading(trailingRoom: 60, leadingRoom: 40, needs: needs),
                "no room either side: the right, as names open")
    }

    @Test("an open name passes under only the dots in front of it that lie on its way, and they make way")
    func makingWay() {
        // Five dots around the orb as the dock draws them: 102 from its middle, 48 across; the widest
        // name's capsule 48 + 4 + 150 + 16 long.
        func way(_ index: Int, leading: Bool, width: CGFloat) -> [Int] {
            GlassOrbRing.makingWay(for: index, count: 5, opensLeading: leading, width: width, radius: 102, dotDiameter: 48)
        }
        #expect(GlassOrbRing.standing(of: 4, count: 5) > GlassOrbRing.standing(of: 1, count: 5),
                "the upper left dot stands in front of the upper right one")
        #expect(way(1, leading: true, width: 218) == [4], "the upper right name, opening left across the orb, under the upper left dot")
        #expect(way(2, leading: true, width: 218) == [3], "the lower right name, under the lower left dot")
        #expect(way(1, leading: true, width: 100) == [], "a short name stops before the dot")
        #expect(way(4, leading: false, width: 218) == [], "opening right, a name lies over the dots, which stand behind it")
    }

    @Test("Connections' hold menu: favorites, then the most recent others, newest first, only what can open")
    func menu() {
        let now = Date()
        let last: [String: Date] = ["a": now - 50, "b": now - 10, "c": now - 30, "d": now - 5, "e": now - 1,
                                    "f": now - 40, "g": now - 20, "i": now - 60]
        let picked = GlassOrbDockMenu.machines(["a", "b", "c", "d", "e", "f", "g", "h", "i"],
                                               isFavorite: { ["c", "h"].contains($0) },
                                               lastConnected: { last[$0] },
                                               canOpen: { $0 != "e" })
        #expect(picked.favorites == ["c", "h"], "favorites, whenever used")
        #expect(picked.recents == ["d", "b", "g", "f", "a"],
                "five, newest first (not the sixth, oldest); no favorite again, nothing that can't open")
    }

    @Test("a wide dock's window comes back above it; a tall one's beside it, away from where the head turned, else on the side chosen")
    func sides() {
        #expect(GlassOrbDockSide.returning(tall: false, headYaw: 1, otherwise: .leading) == .above)
        let left = GlassOrbDockSide.heading(forwardX: -1, forwardZ: -1), right = GlassOrbDockSide.heading(forwardX: 1, forwardZ: -1)
        #expect(left > 0 && right < 0, "a head turned left has a positive heading")
        #expect(GlassOrbDockSide.returning(tall: true, headYaw: left, otherwise: .leading) == .trailing,
                "dock to the left: the window to its right, whatever was chosen")
        #expect(GlassOrbDockSide.returning(tall: true, headYaw: right, otherwise: .trailing) == .leading,
                "dock to the right: the window to its left")
        #expect(GlassOrbDockSide.returning(tall: true, headYaw: 0.05, otherwise: .leading) == .leading, "straight ahead: as chosen")
        #expect(GlassOrbDockSide.returning(tall: true, headYaw: nil, otherwise: .leading) == .leading,
                "no heading (outside Focus Mode): as chosen")
        #expect(GlassOrbDockSide.returning(tall: true, headYaw: nil) == .trailing, "nothing chosen: its right")
    }
}
