#if os(macOS)
import CoreGraphics
import SwiftUI
import Testing
@testable import GlassTerminal

/// The window's overview as a carousel (the owner, 2026-11-02: "i really wanted the carousel to work like the old
/// album view in itunes"): the tab in front flat and large, the rest turned toward it and stacked close, a tab
/// travelling through the middle as the row flows, and a click landing on the tab whose strip it hits.
@Suite("The terminal window's carousel")
struct MacTerminalCarouselTests {
    let geometry = MacTerminalCarouselGeometry(tile: CGSize(width: 480, height: 300))

    @Test("A tab moves through the middle without a jump, the first either side well apart, the rest stacked close")
    func flowsThroughTheMiddle() {
        // Across the row in small steps, as a swipe moves it: never a jump, always the same way.
        var last = geometry.x(-6)
        for step in 1...1200 {
            let d = -6 + Double(step) / 100
            let x = geometry.x(d)
            #expect(x > last && x - last < 4, "at \(d): \(last) to \(x)")
            last = x
        }
        #expect(geometry.x(0) == 0)
        #expect(geometry.x(1) == -geometry.x(-1), "the same either side")
        // The front stands clear of its neighbours; those further out are stacked far closer.
        let opening = geometry.x(1) - geometry.x(0)
        let stacked = geometry.x(3) - geometry.x(2)
        #expect(opening > geometry.tile.width / 2, "a neighbour starts past the front's edge: \(opening)")
        #expect(stacked < opening / 3, "\(stacked) against \(opening)")
    }

    /// Each tab beside the front faces the middle, as Apple's album view turns its covers: its outer edge comes
    /// toward you, drawn taller, and its inner edge goes back (the owner, 2026-11-02: "should the rear windows be
    /// angled like this vs out?" — they had faced out). Measured on the transform the row draws with.
    @Test("The front faces you, flat and largest; either side faces the middle, outer edge toward you, and stands back")
    func facesTheMiddle() {
        #expect(geometry.angle(0) == 0 && geometry.depth(0) == 0 && geometry.scale(0) == 1)
        #expect(abs(geometry.angle(1)) == geometry.turn && geometry.angle(5) == geometry.angle(1), "no further than the first")
        #expect(abs(geometry.angle(0.5)) > 0 && abs(geometry.angle(0.5)) < geometry.turn, "turning as it leaves the front")
        #expect(geometry.depth(3) < 0 && geometry.scale(3) < 1)
        #expect(geometry.turn >= 55, "turned steeply, as the row stacks: \(geometry.turn)")
        let size = geometry.tile
        func seen(_ d: Double, x: CGFloat) -> CGFloat {
            let t = MacTerminalCarouselPlacement(d: d, geometry: geometry).effectValue(size: size)
            func y(_ y: CGFloat) -> CGFloat { (t.m12 * x + t.m22 * y + t.m32) / (t.m13 * x + t.m23 * y + t.m33) }
            return y(size.height) - y(0)
        }
        // On the right the outer edge is the tile's right; on the left, its left.
        #expect(seen(1, x: size.width) > seen(1, x: 0) * 1.1, "the right one's outer edge toward you")
        #expect(seen(-1, x: 0) > seen(-1, x: size.width) * 1.1, "the left one's outer edge toward you")
        #expect(abs(seen(0, x: 0) - seen(0, x: size.width)) < 0.5, "the front square on")
        let still = MacTerminalCarouselGeometry(tile: geometry.tile, turn: 0)
        #expect(still.angle(1) == 0, "Reduce Motion: the row slides, nothing turns")
    }

    @Test("A click lands on the front within its width, past it on the tab whose strip is there, never past the row")
    func clicksLandOnTheTabShown() {
        let front = 5, count = 12
        #expect(geometry.tab(at: 0, front: front, count: count) == front)
        #expect(geometry.tab(at: geometry.tile.width / 2 - 1, front: front, count: count) == front)
        // Just past the front's edge, the first beside it shows.
        #expect(geometry.tab(at: geometry.tile.width / 2 + 2, front: front, count: count) == front + 1)
        #expect(geometry.tab(at: -(geometry.tile.width / 2 + 2), front: front, count: count) == front - 1)
        // Past the first one's strip, each further tab in turn.
        let second = geometry.x(2) + geometry.outerHalf - 1
        #expect(geometry.tab(at: second, front: front, count: count) == front + 2)
        let third = geometry.x(3) + geometry.outerHalf - 1
        #expect(geometry.tab(at: third, front: front, count: count) == front + 3)
        #expect(geometry.tab(at: 5000, front: front, count: count) == count - 1)
        #expect(geometry.tab(at: -5000, front: front, count: count) == 0)
    }

    /// The owner's screenshot, 2026-11-02: the first tab either side tucked under the front, and through a glass
    /// terminal it showed as dark bands down the front's edges. Measured on the transform the row draws with: every
    /// corner of the first neighbour, as projected, lands clear of the front, turning or not.
    @Test("The first tab either side stands clear of the front's edge, as drawn")
    func neighboursClearTheFront() {
        for turn in [64.0, 0] {
            let geometry = MacTerminalCarouselGeometry(tile: CGSize(width: 480, height: 300), turn: turn)
            let size = geometry.tile
            for side in [1.0, -1.0] {
                let t = MacTerminalCarouselPlacement(d: side, geometry: geometry).effectValue(size: size)
                let xs = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height),
                          CGPoint(x: size.width, y: size.height)].map { p in
                    (t.m11 * p.x + t.m21 * p.y + t.m31) / (t.m13 * p.x + t.m23 * p.y + t.m33)
                }
                // The front stands on 0...width in the same frame, untransformed.
                if side > 0 {
                    #expect(xs.min()! > size.width, "turn \(turn): the right neighbour reaches \(xs.min()!) over the front's \(size.width)")
                } else {
                    #expect(xs.max()! < 0, "turn \(turn): the left neighbour reaches \(xs.max()!) over the front's 0")
                }
                #expect(abs(abs(xs.min()! - size.width / 2) - size.width) < size.width, "and not far off: \(xs)")
            }
            #expect(geometry.x(1) - geometry.innerHalf > size.width / 2, "the geometry says so too")
        }
    }

    @Test("A swipe or drag settles on the nearest whole tab, inside the row")
    func settles() {
        #expect(MacTerminalCarouselGeometry.settled(2.4, count: 6) == 2)
        #expect(MacTerminalCarouselGeometry.settled(2.6, count: 6) == 3)
        #expect(MacTerminalCarouselGeometry.settled(-0.3, count: 6) == 0)
        #expect(MacTerminalCarouselGeometry.settled(9, count: 6) == 5)
    }

    /// The front is read, not glanced at (the owner, 2026-11-02: "do we need to make the focused one larger?"): it
    /// takes the band's height but for the neighbours' outer edges, drawn taller, and the reflection's top. Measured
    /// on the transform: the outer edges stay inside the band.
    @Test("The front is as large as the band allows, the neighbours' outer edges and the reflection's top still in it")
    func tileSize() {
        let band = CGSize(width: 2000, height: 600)
        let geometry = MacTerminalCarouselGeometry(in: band)
        #expect(abs(geometry.tile.width / geometry.tile.height - 1.6) < 0.001)
        #expect(geometry.tile.height >= band.height * 0.68, "large: \(geometry.tile) in \(band)")
        // The right neighbour's outer edge, as drawn, from the row's middle line.
        let t = MacTerminalCarouselPlacement(d: 1, geometry: geometry).effectValue(size: geometry.tile)
        func y(_ y: CGFloat) -> CGFloat {
            let x = geometry.tile.width
            return (t.m12 * x + t.m22 * y + t.m32) / (t.m13 * x + t.m23 * y + t.m33)
        }
        let drawn = y(geometry.tile.height) - y(0)
        #expect(abs(drawn - geometry.outerEdgeHeight) < 1, "the geometry's own sum agrees: \(drawn) \(geometry.outerEdgeHeight)")
        let center = geometry.rowCenter(inBand: band.height)
        #expect(center - drawn / 2 >= -0.5, "the outer edges' tops inside the band: \(center - drawn / 2)")
        #expect(center + geometry.tile.height / 2 + geometry.tile.height * 0.3 <= band.height + 0.5,
                "the reflection's brightest part inside it")
        let narrow = MacTerminalCarouselGeometry(in: CGSize(width: 600, height: 900))
        #expect(narrow.tile.width <= 600 * 0.46 + 0.5, "neighbours show either side: \(narrow.tile)")
    }

    @Test("The overview's style is kept by name")
    func styleNames() {
        #expect(MacTerminalOverviewStyle(rawValue: "grid") == .grid)
        #expect(MacTerminalOverviewStyle(rawValue: "carousel") == .carousel)
    }
}
#endif
