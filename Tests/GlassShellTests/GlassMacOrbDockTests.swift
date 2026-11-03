#if os(macOS)
import Foundation
import SwiftUI
import Testing
@testable import GlassShell

/// The orb dock on the Mac (D95; the owner, 2026-11-02: "We should consider a dock on Mac, exactly like
/// visionOS for the same reason!"): a window put into it is hidden, not closed, and comes back by its
/// orb or any other way; Connections goes in too; a relaunch puts back what was there.
///
/// Nothing is drawn: a stand-in window records what the dock asks of it.
@MainActor
@Suite("The orb dock on the Mac")
struct GlassMacOrbDockTests {
    final class StandIn: GlassDockableWindow {
        var isOnScreen = true
        var putAway = 0
        var broughtForward = 0
        /// Fading out, until the test lets it finish.
        var fading: (@MainActor () -> Void)?
        var finishesAtOnce = true
        var hasPicture = true

        func putAway(animated: Bool, done: @escaping @MainActor () -> Void) {
            putAway += 1
            if finishesAtOnce {
                isOnScreen = false
                done()
            } else {
                fading = { [weak self] in
                    self?.isOnScreen = false
                    done()
                }
            }
        }

        func bringForward() {
            broughtForward += 1
            isOnScreen = true
        }

        func picture() -> Image? { hasPicture ? Image(systemName: "square") : nil }
    }

    private func withDock(_ body: (GlassOrbDockModel, UserDefaults) throws -> Void) throws {
        let suite = "GlassMacOrbDockTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(GlassOrbDockModel(defaults: defaults), defaults)
    }

    private func face(_ title: String = "Terminal", picture: Image? = nil) -> GlassOrbFaceSource {
        GlassOrbFaceSource(GlassSessionOrbFace(title: title, symbolName: "apple.terminal", dockID: title) { picture })
    }

    @Test("A docked window is hidden, not closed, and its orb's click shows that window again")
    func docksAndComesBack() throws {
        try withDock { dock, _ in
            var shown: [Bool] = []
            dock.presence = { shown.append($0) }
            let window = StandIn()
            dock.dock("terminal-window:a", window: window, face: face())
            #expect(window.putAway == 1 && !window.isOnScreen)
            #expect(dock.docked == ["terminal-window:a"] && dock.isDocked("terminal-window:a"))
            #expect(shown == [true], "the dock comes up with its first orb")

            dock.dock("terminal-window:a", window: window, face: face())
            #expect(window.putAway == 1, "asked again while it waits, nothing")

            #expect(dock.bringBack("terminal-window:a"))
            #expect(window.broughtForward == 1 && window.isOnScreen)
            #expect(dock.docked.isEmpty && dock.isEmpty)
            #expect(shown == [true, false], "and goes with its last")
            #expect(!dock.bringBack("terminal-window:a"), "not in the dock any more")
        }
    }

    @Test("Choosing a tab on the orb's ring chooses it, then shows the window")
    func aTabComesBackOnIt() throws {
        try withDock { dock, _ in
            let window = StandIn()
            dock.dock("terminal-window:a", window: window, face: face())
            var order: [String] = []
            dock.bringBack("terminal-window:a", first: {
                order.append(window.isOnScreen ? "shown" : "chosen")
            })
            order.append(window.isOnScreen ? "shown" : "hidden")
            #expect(order == ["chosen", "shown"])
        }
    }

    @Test("A window shown another way — Active, Show All Windows, the Window menu — leaves the dock; one fading into it doesn't")
    func shownAnotherWayLeaves() throws {
        try withDock { dock, _ in
            let window = StandIn()
            window.finishesAtOnce = false
            dock.dock("database:a", window: window, face: face())
            dock.windowsChanged()
            #expect(dock.isDocked("database:a"), "still on screen while it fades into the dock")
            window.fading?()
            dock.windowsChanged()
            #expect(dock.isDocked("database:a"))

            window.bringForward()
            dock.windowsChanged()
            #expect(!dock.isDocked("database:a"))
        }
    }

    @Test("A window gone is forgotten; one closed as the app quits is still put back by the next launch")
    func goneAndClosed() throws {
        try withDock { dock, defaults in
            var gone: StandIn? = StandIn()
            dock.dock("terminal-window:gone", window: gone!, face: face())
            gone = nil
            dock.windowsChanged()
            #expect(!dock.isDocked("terminal-window:gone"))

            let closing = StandIn()
            dock.dock("terminal-window:kept", window: closing, face: face())
            dock.closed(closing)
            #expect(dock.isEmpty)
            #expect(defaults.stringArray(forKey: GlassOrbDock.dockedKey) == ["terminal-window:kept"],
                    "a quit closes the app's windows: what was docked stays to be put back")
        }
    }

    @Test("A relaunch puts back the windows and Connections the last run left in the dock, each once")
    func relaunch() throws {
        try withDock { dock, defaults in
            dock.dock("terminal-window:a", window: StandIn(), face: face())
            dock.dock(GlassOrbDock.connectionsID, window: StandIn(), face: nil)
            #expect(dock.holdsConnections && dock.docked == ["terminal-window:a"], "Connections is no window's orb")

            let next = GlassOrbDockModel(defaults: defaults)
            #expect(next.takeLastRun("terminal-window:a"))
            #expect(!next.takeLastRun("terminal-window:a"), "once")
            #expect(!next.takeLastRun("terminal-window:b"))
            #expect(next.takeLastRun(GlassOrbDock.connectionsID))
            #expect(!next.takeLastRun(GlassOrbDock.connectionsID))
        }
    }

    @Test("What the last run left stays listed until its window is back, through this run's changes")
    func lastRunKeptUntilBack() throws {
        try withDock { dock, defaults in
            defaults.set(["terminal-window:old"], forKey: GlassOrbDock.dockedKey)
            dock.reloadLastRun()
            let window = StandIn()
            dock.dock("terminal-window:new", window: window, face: face())
            dock.bringBack("terminal-window:new")
            #expect(defaults.stringArray(forKey: GlassOrbDock.dockedKey) == ["terminal-window:old"])
            #expect(dock.takeLastRun("terminal-window:old"))
            dock.dock("terminal-window:old", window: StandIn(), face: face(), animated: false)
            #expect(defaults.stringArray(forKey: GlassOrbDock.dockedKey) == ["terminal-window:old"])
        }
    }

    @Test("Connections comes back from the dock, and is found there as open")
    func connections() throws {
        try withDock { dock, _ in
            let window = StandIn()
            #expect(!dock.bringBackConnections(), "not in the dock")
            dock.dock(GlassOrbDock.connectionsID, window: window, face: nil)
            #expect(dock.holdsConnections && !dock.isEmpty)
            #expect(dock.bringBack(GlassOrbDock.connectionsID))
            #expect(window.isOnScreen && !dock.holdsConnections && dock.isEmpty)
        }
    }

    @Test("A window with no picture of its own shows the one it had as it docked")
    func keptPicture() throws {
        try withDock { dock, _ in
            let window = StandIn()
            dock.dock("editor:a", window: window, face: face(picture: nil))
            #expect(dock.face(of: "editor:a")?.picture() != nil)

            let blank = StandIn()
            blank.hasPicture = false
            dock.dock("editor:b", window: blank, face: face(picture: nil))
            #expect(dock.face(of: "editor:b")?.picture() == nil)
        }
    }

    @Test("The dock's edge is the same distance from its orbs on every side, and every orb's middle is on one line")
    func evenEdges() throws {
        // The owner, 2026-11-02: "keep the edges of the dock the same distance from the windows", and
        // Connections "centered with the other orbs". Measured to what is drawn: Connections' circle, and
        // a ring's outermost dots, from the middles the dock lays them out on.
        // Four dots: above, beside and below, so the ring reaches as far each way.
        let ringed = GlassMacOrbDockView.size(ring: 4)
        let plain = GlassMacOrbDockView.size(ring: 0)
        let sizes = [GlassMacOrbDockView.connectionsSize, ringed, plain, ringed]
        let dock = GlassMacOrbDockView.fit(sizes, within: nil)
        let inset = GlassMacOrbDockView.inset
        let frames = GlassOrbFlow.frames(of: sizes, width: dock.width - 2 * inset,
                                         gapAfterFirst: GlassMacOrbDockView.connectionsGap)
        let ring = GlassMacSessionOrbView.ringRadius + GlassMacSessionOrbView.dotDiameter / 2
        let connections = GlassOrbMetrics.orbDiameter * GlassMacOrbDockView.connectionsScale / 2
        let left = inset + frames[0].midX - connections
        let right = dock.width - (inset + frames[3].midX + ring)
        let top = inset + frames[1].midY - ring
        let bottom = dock.height - (inset + frames[1].midY + ring)
        #expect(abs(left - top) < 1 && abs(right - top) < 1 && abs(bottom - top) < 1,
                "left \(left), right \(right), top \(top), bottom \(bottom)")
        #expect(top < 20, "a narrow margin, no room kept for names: \(top)")
        #expect(Set(frames.map { $0.midY.rounded() }).count == 1, "\(frames.map(\.midY))")
        // Two dots, above and below: no room kept beside the orb.
        let pair = GlassMacOrbDockView.size(ring: 2)
        #expect(pair.width == plain.width && pair.height == ringed.height, "\(pair)")
    }

    @Test("The dock grows from Connections: it stays put as orbs come and go, the dock reaching right of it, rows below it")
    func growsFromConnections() {
        // The owner, 2026-11-02: "Let's tweak the Mac dock to grow from the Active orb out... it should act as
        // the root position." Measured to what is drawn: Connections' circle, as the dock lays it out.
        let inset = GlassMacOrbDockView.inset
        let connections = GlassMacOrbDockView.connectionsSize
        let ringed = GlassMacOrbDockView.size(ring: 4)
        let plain = GlassMacOrbDockView.size(ring: 0)
        let root = CGPoint(x: 400, y: 300)
        func placed(_ orbs: [CGSize]) -> (frame: CGRect, drawn: CGPoint) {
            let size = GlassMacOrbDockView.fit(orbs, within: nil)
            let frame = GlassOrbDockPanel.frame(of: size, placing: GlassMacOrbDockView.root(of: orbs, width: size.width), at: root)
            let laid = GlassOrbFlow.frames(of: orbs, width: size.width - 2 * inset,
                                           gapAfterFirst: GlassMacOrbDockView.connectionsGap)[0]
            return (frame, CGPoint(x: frame.minX + inset + laid.midX, y: frame.maxY - inset - laid.midY))
        }
        let alone = placed([connections])
        var widths: [CGFloat] = []
        for orbs in [[connections], [connections, plain], [connections, plain, ringed], [connections, ringed, ringed, plain],
                     [connections, ringed], [connections]] {
            let (frame, drawn) = placed(orbs)
            #expect(abs(drawn.x - root.x) < 0.5 && abs(drawn.y - root.y) < 0.5, "Connections moved to \(drawn) with \(orbs.count) orbs")
            #expect(abs(frame.minX - alone.frame.minX) < 0.5, "the dock's left edge moved, to \(frame.minX)")
            #expect(abs(frame.midY - root.y) < 0.5, "a taller row grows evenly above and below Connections: \(frame)")
            widths.append(frame.width)
        }
        #expect(widths[2] > widths[1] && widths[1] > widths[0], "each orb reaches further right: \(widths)")
        // Past the widest row: a second, below Connections' row, which stays where it was.
        let wrapped = placed([connections] + Array(repeating: ringed, count: 12))
        let oneRow = placed([connections, ringed])
        #expect(wrapped.frame.height > oneRow.frame.height * 1.5, "\(wrapped.frame)")
        #expect(abs(wrapped.frame.maxY - oneRow.frame.maxY) < 0.5 && abs(wrapped.frame.minX - oneRow.frame.minX) < 0.5)
        #expect(abs(wrapped.drawn.x - root.x) < 0.5 && abs(wrapped.drawn.y - root.y) < 0.5)
    }

    @Test("Resized, the dock takes the shape that shows every orb: as wide as made, as tall as its rows, no taller than the screen")
    func showsEveryOrb() {
        // The owner, 2026-11-02, of a column of two orbs in a dock three times their height: "it should also
        // spring back to the shape that shows all of the orbs".
        let inset = GlassMacOrbDockView.inset
        let gap = GlassMacOrbDockView.connectionsGap
        let ringed = GlassMacOrbDockView.size(ring: 5)
        let orbs = [GlassMacOrbDockView.connectionsSize, ringed]
        func bottoms(_ orbs: [CGSize], width: CGFloat) -> [CGFloat] {
            Set(GlassOrbFlow.frames(of: orbs, width: width - 2 * inset, gapAfterFirst: gap).map { ($0.maxY + 2 * inset).rounded(.up) }).sorted()
        }
        let narrow = ringed.width + 2 * inset
        let tall = GlassMacOrbDockView.fit(orbs, within: CGSize(width: narrow, height: 900))
        #expect(bottoms(orbs, width: tall.width).count == 2, "a column: \(tall)")
        #expect(tall.height == bottoms(orbs, width: tall.width).last, "as tall as both rows, not as dragged: \(tall)")
        let short = GlassMacOrbDockView.fit(orbs, within: CGSize(width: narrow, height: 60))
        #expect(short == tall, "made shorter than its rows, still every orb: \(short)")
        // A column past the screen's height: the whole rows that fit in it, the rest scrolled to.
        let many = [GlassMacOrbDockView.connectionsSize] + Array(repeating: ringed, count: 10)
        let capped = GlassMacOrbDockView.fit(many, within: CGSize(width: narrow, height: 300), tallest: 700)
        #expect(capped.height <= 700 && capped.height > 700 - ringed.height, "\(capped)")
        #expect(bottoms(many, width: capped.width).contains(capped.height), "whole rows: \(capped)")
    }

    @Test("Databases, desktops and editors stand on their machine's orb; terminal windows on their own")
    func whichOrb() {
        #expect(GlassMacOrbDockView.isMachineService("database:1"))
        #expect(GlassMacOrbDockView.isMachineService("desktop:1"))
        #expect(GlassMacOrbDockView.isMachineService("editor:1"))
        #expect(!GlassMacOrbDockView.isMachineService("terminal-window:1"))
        #expect(!GlassMacOrbDockView.isMachineService("terminal-session:1"))
        #expect(!GlassMacOrbDockView.isMachineService(GlassOrbDock.connectionsID))
    }

    /// D98 (the owner, 2026-11-02: no "actual liquid feel"): a dot buds out of its orb as it lands, from the orb's rim
    /// to its place on the ring, and comes to rest clear of it. Measured on circles.
    @Test("A dot buds out from its orb's rim, every way round the ring, and comes to rest clear of it")
    func dotsBudOutOfTheirOrb() {
        let orb = GlassOrbMetrics.orbDiameter / 2, dot = GlassMacSessionOrbView.dotDiameter / 2
        for count in 1...GlassOrbMetrics.maximumTabs {
            for index in 0..<count {
                let at = GlassOrbRing.center(of: index, count: count, radius: GlassMacSessionOrbView.ringRadius)
                let distance = hypot(at.x, at.y)
                // Its outer edge, as it starts: on the orb's rim.
                let start = distance * GlassOrbBud.start(of: CGSize(width: at.x, height: at.y))
                #expect(abs(start + dot - orb) < 0.5, "\(index) of \(count): starts with its edge \(start + dot), the rim \(orb)")
                #expect(distance - orb - dot >= GlassMacSessionOrbView.gap - 0.5, "\(index) of \(count): at rest clear of its orb")
            }
        }
        #expect(GlassOrbBud.start(of: .zero) == 0)
    }
}
#endif
