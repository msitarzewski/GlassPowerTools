import Foundation
import SwiftUI
import Testing
@testable import GlassShell

/// Every open window in the dock (the owner, 2026-11-13: "a toggle to allow all windows to show in the dock all the
/// time"). His choices: both docks; an open window's orb brings it forward; put-away orbs at full strength, open ones
/// fainter.
@Suite("Every window in the orb dock")
struct GlassOrbDockEveryWindowTests {
    @Test("off, the dock lists what was put away; on, every open window too, each once, those put away first")
    func windows() {
        let docked = ["terminal-window:b"], open = ["terminal-window:a", "terminal-window:b", "terminal-window:c"]
        #expect(GlassOrbDockEveryWindow.windows(docked: docked, open: open, everyWindow: false) == docked)
        #expect(GlassOrbDockEveryWindow.windows(docked: docked, open: open, everyWindow: true)
                == ["terminal-window:b", "terminal-window:a", "terminal-window:c"])
        #expect(GlassOrbDockEveryWindow.windows(docked: [], open: [], everyWindow: true).isEmpty)
    }

    @Test("an orb is fainter only with the setting on and none of its windows put away")
    func strength() {
        func opacity(_ ids: [String], _ everyWindow: Bool) -> Double {
            GlassOrbDockEveryWindow.opacity(of: ids, docked: { $0 == "away" }, everyWindow: everyWindow)
        }
        let off = opacity(["open"], false), awayOn = opacity(["away"], true), openOn = opacity(["open"], true)
        let machine = opacity(["open", "away"], true)
        #expect(off == 1)
        #expect(awayOn == 1)
        #expect(openOn == GlassOrbDockEveryWindow.openOpacity)
        #expect(machine == 1, "a machine's orb with one window put away")
        #expect(GlassOrbDockEveryWindow.openOpacity < 1)
    }

    @Test("off until chosen")
    func offByDefault() throws {
        let suite = "GlassOrbDockEveryWindowTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!GlassOrbDockEveryWindow.isOn(in: defaults))
        defaults.set(true, forKey: GlassOrbDockEveryWindow.key)
        #expect(GlassOrbDockEveryWindow.isOn(in: defaults))
    }
}

#if os(macOS)
/// The Mac's dock with every window shown: it learns each window as it opens, stays up, and brings an open window
/// forward where it is.
@MainActor
@Suite("Every window in the Mac's orb dock")
struct GlassMacOrbDockEveryWindowTests {
    typealias StandIn = GlassMacOrbDockTests.StandIn

    private func withDock(everyWindow: Bool, _ body: (GlassOrbDockModel, UserDefaults) throws -> Void) throws {
        let suite = "GlassMacOrbDockEveryWindowTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(everyWindow, forKey: GlassOrbDockEveryWindow.key)
        try body(GlassOrbDockModel(defaults: defaults), defaults)
    }

    private func face(_ title: String) -> GlassOrbFaceSource {
        GlassOrbFaceSource(GlassSessionOrbFace(title: title, symbolName: "apple.terminal", dockID: title) { nil })
    }

    @Test("windows that open are known, with their faces; Connections is not one")
    func learnsOpenWindows() throws {
        try withDock(everyWindow: true) { dock, _ in
            let a = StandIn(), connections = StandIn()
            dock.opened("terminal-window:a", window: a, face: face("Alpha"))
            dock.opened("terminal-window:a", window: a, face: face("Alpha"))
            dock.opened(GlassOrbDock.connectionsID, window: connections, face: face("Connections"))
            #expect(dock.openIDs == ["terminal-window:a"], "once, and not Connections")
            #expect(dock.face(of: "terminal-window:a")?.title == "Alpha")
            #expect(!dock.isDocked("terminal-window:a"), "known, not put away")
        }
    }

    @Test("an open window's orb brings that window forward where it is, after choosing its tab; it isn't put away")
    func bringsAnOpenWindowForward() throws {
        try withDock(everyWindow: true) { dock, _ in
            let a = StandIn()
            dock.opened("terminal-window:a", window: a, face: face("Alpha"))
            var chosen = false
            let brought = dock.bringForward("terminal-window:a", first: { chosen = true })
            let none = dock.bringForward("terminal-window:none")
            #expect(brought)
            #expect(chosen && a.broughtForward == 1 && a.putAway == 0)
            #expect(!none)
        }
    }

    @Test("a docked window's orb still brings it back from the dock")
    func dockedComesBack() throws {
        try withDock(everyWindow: true) { dock, _ in
            let a = StandIn()
            dock.opened("terminal-window:a", window: a, face: face("Alpha"))
            dock.dock("terminal-window:a", window: a, face: face("Alpha"))
            #expect(dock.isDocked("terminal-window:a") && !a.isOnScreen)
            #expect(dock.bringForward("terminal-window:a"))
            #expect(a.isOnScreen && !dock.isDocked("terminal-window:a"))
            #expect(dock.openIDs == ["terminal-window:a"], "still open, still listed")
        }
    }

    @Test("on, the dock comes up as a window opens and stays up when the last one put away comes back")
    func staysUp() throws {
        try withDock(everyWindow: true) { dock, _ in
            var shown: [Bool] = []
            dock.presence = { shown.append($0) }
            let a = StandIn()
            dock.opened("terminal-window:a", window: a, face: face("Alpha"))
            #expect(shown.last == true, "up with the first window")
            dock.dock("terminal-window:a", window: a, face: face("Alpha"))
            dock.bringBack("terminal-window:a")
            #expect(!shown.contains(false), "nothing in it, and still up")
            #expect(dock.keepsShown)
        }
    }

    @Test("off, nothing changes: the dock isn't brought up by a window opening, and goes with its last orb")
    func offAsBefore() throws {
        try withDock(everyWindow: false) { dock, _ in
            var shown: [Bool] = []
            dock.presence = { shown.append($0) }
            let a = StandIn()
            dock.opened("terminal-window:a", window: a, face: face("Alpha"))
            #expect(shown.isEmpty)
            dock.dock("terminal-window:a", window: a, face: face("Alpha"))
            dock.bringBack("terminal-window:a")
            #expect(shown == [true, false])
        }
    }

    @Test("turned on, the dock comes up; turned off with nothing in it, it goes")
    func turnedOnAndOff() throws {
        try withDock(everyWindow: false) { dock, defaults in
            var shown: [Bool] = []
            dock.presence = { shown.append($0) }
            defaults.set(true, forKey: GlassOrbDockEveryWindow.key)
            dock.everyWindowChanged()
            defaults.set(false, forKey: GlassOrbDockEveryWindow.key)
            dock.everyWindowChanged()
            #expect(shown == [true, false])
        }
    }

    @Test("a window that closes leaves the list")
    func closedLeaves() throws {
        try withDock(everyWindow: true) { dock, _ in
            let a = StandIn(), b = StandIn()
            dock.opened("terminal-window:a", window: a, face: face("Alpha"))
            dock.opened("terminal-window:b", window: b, face: face("Bravo"))
            dock.closed(a)
            #expect(dock.openIDs == ["terminal-window:b"])
            #expect(dock.face(of: "terminal-window:a") == nil)
        }
    }
}
#endif
