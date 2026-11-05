import CoreGraphics
import Foundation
import Testing
@testable import GlassShell

/// The orb dock's geometry (D88; the owner, 2026-10-26 and 27, 2026-11-05): orbs in one line, a row or a
/// column, the dock fitting them and scrolling past its longest; a carried orb landing in any direction,
/// names opening toward the room, and the side a window comes back on from a vertical dock.
@Suite("The orb dock's line, landings, names and sides")
struct GlassOrbDockGeometryTests {
    private let connections = CGSize(width: 240, height: 320)
    private let ringed = CGSize(width: 280, height: 320)
    private let plain = CGSize(width: 200, height: 320)

    @Test("a row: Connections, its gap, then each orb beside the last, every middle on one line")
    func row() {
        let short = CGSize(width: 200, height: 200)
        let frames = GlassOrbLine.frames(of: [connections, ringed, short, ringed], .horizontal, gapAfterFirst: 24)
        #expect(frames.map(\.minX) == [0, 264, 544, 744], "Connections, its gap, then each beside the last")
        #expect(Set(frames.map(\.midY)) == [160], "one line, a shorter orb on its middle")
        #expect(GlassOrbLine.size(of: [connections, ringed, short, ringed], .horizontal, gapAfterFirst: 24)
                == CGSize(width: 1024, height: 320))
    }

    @Test("a column: each orb below the last, on one line down the middle, Connections set apart above")
    func column() {
        let frames = GlassOrbLine.frames(of: [connections, ringed, plain], .vertical, gapAfterFirst: 24)
        #expect(frames.map(\.minY) == [0, 344, 664], "each below the last, the gap after Connections")
        #expect(Set(frames.map(\.midX)) == [140], "on one line down the middle of the widest")
    }

    @Test("the dock fits every orb along its line, one orb thick; past its longest, the whole orbs that fit")
    func fits() {
        let sizes = [connections, ringed, ringed]
        #expect(GlassOrbLine.fitted(sizes, .horizontal, inset: 16, gapAfterFirst: 24) == CGSize(width: 856, height: 352))
        #expect(GlassOrbLine.fitted(sizes, .horizontal, inset: 16, gapAfterFirst: 24, longest: 700)
                == CGSize(width: 576, height: 352), "Connections and one orb (544) fit in 668; the third is scrolled to")
        #expect(GlassOrbLine.fitted(sizes, .vertical, inset: 16, gapAfterFirst: 24) == CGSize(width: 312, height: 1016))
        #expect(GlassOrbLine.fitted(sizes, .vertical, inset: 16, gapAfterFirst: 24, longest: 700)
                == CGSize(width: 312, height: 696))
        #expect(GlassOrbLine.fitted(sizes, .horizontal, inset: 16, gapAfterFirst: 24, longest: 100).width == 272,
                "at least Connections")
        #expect(GlassOrbLine.fitted([plain], .horizontal, inset: 16, minimum: CGSize(width: 320, height: 320))
                == CGSize(width: 320, height: 352), "never narrower than visionOS makes a window")
        // Connections a third larger, as in the dock: a fraction of a point wide.
        let larger = [CGSize(width: 184 * 4.0 / 3, height: 320), ringed]
        let rounded = GlassOrbLine.fitted(larger, .horizontal, inset: 16, gapAfterFirst: 24)
        #expect(rounded.width == (184 * 4.0 / 3 + 24 + 280 + 32).rounded(.up), "whole points, rounded up")
        #expect(GlassOrbLine.fitted(larger, .horizontal, inset: 16, gapAfterFirst: 24, longest: rounded.width) == rounded,
                "given its own size as its longest, the same orbs fit")
    }

    @Test("a window taken out of the dock and docked again goes back into the row, not onto a new one")
    func dockedAgain() {
        // The owner, 2026-11-05: "because the dock 'window' shrunk when the window was moved out of the dock, it gets
        // reinserted on a new row." The dock's size comes from its orbs alone, never from the size it was left at.
        let four = [connections, ringed, ringed, plain, ringed]
        for orientation in GlassOrbDockOrientation.allCases {
            let before = GlassOrbLine.fitted(four, orientation, inset: 16, gapAfterFirst: 24)
            let out = GlassOrbLine.fitted(Array(four.dropLast()), orientation, inset: 16, gapAfterFirst: 24)
            let again = GlassOrbLine.fitted(four, orientation, inset: 16, gapAfterFirst: 24)
            #expect(out != before, "it shrank as the window left")
            #expect(again == before, "\(orientation): back to the size it had")
            let frames = GlassOrbLine.frames(of: four, orientation, gapAfterFirst: 24)
            let across = orientation == .horizontal ? frames.map(\.midY) : frames.map(\.midX)
            #expect(Set(across).count == 1, "\(orientation): one line")
        }
    }

    @Test("the dock is a row until a column is chosen")
    func orientationSetting() {
        let name = "GlassOrbDockOrientation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(GlassOrbDockOrientation.current(in: defaults) == .horizontal)
        defaults.set("vertical", forKey: GlassOrbDockOrientation.key)
        #expect(GlassOrbDockOrientation.current(in: defaults) == .vertical)
        defaults.set("diagonal", forKey: GlassOrbDockOrientation.key)
        #expect(GlassOrbDockOrientation.current(in: defaults) == .horizontal, "anything else: a row")
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
