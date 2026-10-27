import Foundation
import Testing
@testable import GlassShell

/// The dock's order (D88; the owner, 2026-10-25: "pinch/click and hold on a docked window to move its
/// order so muscle memory can land"): an orb let go on another takes its place, and every orb keeps
/// its place while it is out of the dock.
@Suite("The orb dock's order")
struct GlassOrbDockOrderTests {
    private func arranged(_ order: GlassOrbDockOrder, _ shown: [String]) -> [String] {
        order.arranged(shown, id: { $0 })
    }

    @Test("Orbs never moved stand in the order they came, after those that were")
    func unmovedOrbsComeAfter() {
        let order = GlassOrbDockOrder(["c", "a"])
        #expect(arranged(order, ["a", "b", "c", "d"]) == ["c", "a", "b", "d"])
        #expect(arranged(GlassOrbDockOrder(), ["b", "a"]) == ["b", "a"])
    }

    @Test("Let go on another, an orb takes its place, from either side")
    func takesThePlaceOfTheOneLetGoOn() {
        var order = GlassOrbDockOrder()
        let shown = ["a", "b", "c", "d"]
        order.move("d", to: "b", among: shown)
        #expect(arranged(order, shown) == ["a", "d", "b", "c"])
        order.move("a", to: "b", among: shown)
        #expect(arranged(order, shown) == ["d", "b", "a", "c"])
        // Let go on itself, or past the end, or before the first.
        order.move("c", to: "c", among: shown)
        #expect(arranged(order, shown) == ["d", "b", "a", "c"])
        order.move("d", to: nil, among: shown)
        #expect(arranged(order, shown) == ["b", "a", "c", "d"])
        order.move("c", to: nil, first: true, among: shown)
        #expect(arranged(order, shown) == ["c", "b", "a", "d"])
    }

    @Test("An orb that leaves the dock comes back where it stood")
    func comesBackToItsPlace() {
        var order = GlassOrbDockOrder()
        order.move("c", to: "a", among: ["a", "b", "c"])
        #expect(arranged(order, ["a", "b", "c"]) == ["c", "a", "b"])
        // a goes out of the dock and b moves before c; a comes back after c, where it stood.
        order.move("b", to: "c", among: ["c", "b"])
        #expect(arranged(order, ["c", "b"]) == ["b", "c"])
        #expect(arranged(order, ["c", "b", "a", "new"]) == ["b", "c", "a", "new"])
    }

    @Test("An orb not in the dock is not moved, and the places kept are bounded")
    func boundedAndOnlyWhatIsShown() {
        var order = GlassOrbDockOrder(["a", "b"])
        order.move("gone", to: "a", among: ["a", "b"])
        #expect(order.ids == ["a", "b"])

        order = GlassOrbDockOrder((0..<GlassOrbDockOrder.kept).map { "old-\($0)" })
        order.move("y", to: "x", among: ["x", "y"])
        #expect(order.ids.count == GlassOrbDockOrder.kept)
        #expect(arranged(order, ["x", "y"]) == ["y", "x"])
        #expect(order.ids.first == "old-0", "the first places kept")
    }

    @Test("A carried orb lands on the one under its middle, or before or after them all")
    func landing() {
        let widths: [CGFloat] = [280, 200, 280]
        // Not carried, or not far: where it was.
        #expect(GlassOrbDockOrder.landing(of: 1, carried: 0, widths: widths) == .on(1))
        #expect(GlassOrbDockOrder.landing(of: 1, carried: -90, widths: widths) == .on(1))
        // Its middle over the next or the one before.
        #expect(GlassOrbDockOrder.landing(of: 1, carried: 150, widths: widths) == .on(2))
        #expect(GlassOrbDockOrder.landing(of: 1, carried: -110, widths: widths) == .on(0))
        #expect(GlassOrbDockOrder.landing(of: 0, carried: 300, widths: widths) == .on(1))
        // Past the first's leading edge, over Connections; past the last's trailing edge.
        #expect(GlassOrbDockOrder.landing(of: 1, carried: -400, widths: widths) == .first)
        #expect(GlassOrbDockOrder.landing(of: 1, carried: 500, widths: widths) == .last)
        #expect(GlassOrbDockOrder.landing(of: 5, carried: 0, widths: widths) == .last, "an orb not in the row")
    }

    @Test("The order is this device's, kept between launches")
    func keptInDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "GlassOrbDockOrderTests-\(UUID().uuidString)"))
        var order = GlassOrbDockOrder(defaults: defaults)
        #expect(order.ids.isEmpty)
        order.move("b", to: "a", among: ["a", "b"])
        order.save(to: defaults)
        #expect(arranged(GlassOrbDockOrder(defaults: defaults), ["a", "b"]) == ["b", "a"])
    }
}
