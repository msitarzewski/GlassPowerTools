#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import GlassTerminal

/// W12, 2026-10-09: after an update the terminal windows came back with the right tabs at the
/// default place ("Windows restored, just not position"), and on several launches they did not
/// come back at all: the reopen list was read only by the Connections window, which did not
/// always appear, and then each time it did. Each test here is one part of bringing the same
/// windows back where they were — after a quit, and after a crash.
///
/// No tmux runs: the windows' terminals are SSH panes that name tmux sessions, which nothing
/// connects, and no test swaps `MacLocalTmux.server`.
extension LocalTmuxServerSuites {
@MainActor
@Suite("Terminal windows come back where they were", .serialized)
struct MacWorkspaceWindowPlacementTests {
    private let alpha = MacWorkspaceDisplay(id: "display-alpha",
                                            frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
                                            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 970))
    private let bravo = MacWorkspaceDisplay(id: "display-bravo",
                                            frame: CGRect(x: 1600, y: 0, width: 2400, height: 1350),
                                            visibleFrame: CGRect(x: 1600, y: 0, width: 2400, height: 1325))
    private let serverID = UUID()
    private let swiftUIsPlace = CGRect(x: 30, y: 40, width: 1180, height: 760)

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let suite = "MacWorkspaceWindowPlacementTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    private func intent(_ session: String?) -> MacWorkspacePaneIntent {
        var intent = MacWorkspacePaneIntent.ssh(serverID: serverID)
        intent.sshTmuxSession = session
        return intent
    }

    /// A window of one tab per session, on screen once, so saved: what the last run left.
    private func savedWindow(_ defaults: UserDefaults, sessions: [String?]) -> MacWorkspaceWindowController {
        let window = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(tabs: sessions.map { MacWorkspaceTabRequest(initialPaneIntent: intent($0)) }),
            defaults: defaults)
        window.windowDidOpen()
        return window
    }

    /// The same window at the next launch: made from its record alone, no view built.
    private func relaunched(_ id: UUID, _ defaults: UserDefaults) -> MacWorkspaceWindowController {
        MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(windowID: id, tabs: []), defaults: defaults)
    }

    private func nsWindow(_ frame: CGRect? = nil) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .resizable, .closable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.setFrame(frame ?? swiftUIsPlace, display: false)
        return window
    }

    private func tracker(enterFullScreen: @escaping @MainActor (NSWindow) -> Void = { _ in }) -> MacWorkspaceWindowPlacementTracker {
        MacWorkspaceWindowPlacementTracker(settleDelay: .milliseconds(50), displays: { [alpha, bravo] },
                                           displayOf: { _ in alpha }, enterFullScreen: enterFullScreen)
    }

    private func savedPlacement(_ defaults: UserDefaults, _ id: UUID) -> MacWorkspaceWindowPlacement? {
        let key = "\(UserDefaultsKeys.macWorkspaceRestoration).window.\(id.uuidString.lowercased())"
        return defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(MacWorkspaceWindowRestorationState.self, from: $0) }?.placement
    }

    /// True once `condition` holds, polled until a deadline well past any settle delay.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func listed(_ defaults: UserDefaults) -> [UUID] {
        (defaults.stringArray(forKey: MacLocalTmux.reopenKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    // MARK: Where a window was

    @Test("a window's place is saved when a move settles, when a resize ends, and at quit; a relaunch reads it from defaults")
    func placeIsSaved() async throws {
        try await withDefaults { defaults in
            let window = savedWindow(defaults, sessions: ["glass-71"])
            let shown = nsWindow()
            let keeper = tracker()
            defer { keeper.stop() }
            keeper.track(shown, controller: window)
            #expect(savedPlacement(defaults, window.windowID) == nil, "a new window keeps SwiftUI's place until it moves")

            let moved = CGRect(x: 140, y: 120, width: 1180, height: 760)
            shown.setFrame(moved, display: false)
            NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: shown)
            #expect(savedPlacement(defaults, window.windowID) == nil, "not at every step of a move")
            #expect(keeper.isWaitingToSave)
            // Waited for, not timed: with the whole suite running, the main actor is busy.
            #expect(try await eventually { savedPlacement(defaults, window.windowID) != nil })
            #expect(savedPlacement(defaults, window.windowID)?.frame == moved, "saved once the move settles")
            #expect(savedPlacement(defaults, window.windowID)?.display == "display-alpha")
            #expect(savedPlacement(defaults, window.windowID)?.displayFrame == alpha.frame)

            let resized = CGRect(x: 140, y: 120, width: 1300, height: 820)
            shown.setFrame(resized, display: false)
            NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: shown)
            #expect(savedPlacement(defaults, window.windowID)?.frame == resized, "saved as a live resize ends")

            // Moved by something that sent no notice: quitting saves where it is.
            let atQuit = CGRect(x: 300, y: 200, width: 1300, height: 820)
            shown.setFrame(atQuit, display: false)
            let registry = MacWorkspacePreviewRegistry()
            registry.register(window, window: shown)
            MacWindowsToReopen(defaults: defaults, registry: registry).prepareForQuit(displayOf: { _ in alpha })
            #expect(savedPlacement(defaults, window.windowID)?.frame == atQuit, "saved at quit")

            let next = relaunched(window.windowID, defaults)
            #expect(next.tabs.map(\.workspaceID) == window.tabs.map(\.workspaceID), "the tabs, as before")
            let placement = try #require(next.takePlacementToRestore())
            #expect(placement.frame == atQuit && placement.display == "display-alpha" && !placement.isFullScreen)
            #expect(next.takePlacementToRestore() == nil, "given back once")
        }
    }

    @Test("reopened, a window goes back exactly where it was; with its display gone, moved or smaller, it is fitted")
    func restoredFrames() {
        let onBravo = MacWorkspaceWindowPlacement(frame: CGRect(x: 2000, y: 300, width: 1200, height: 800),
                                                  display: "display-bravo", displayFrame: bravo.frame)
        #expect(onBravo.restoredFrame(on: [alpha, bravo]) == onBravo.frame, "exactly where it was")

        let bravoToTheLeft = MacWorkspaceDisplay(id: "display-bravo",
                                                 frame: CGRect(x: -2400, y: 0, width: 2400, height: 1350),
                                                 visibleFrame: CGRect(x: -2400, y: 0, width: 2400, height: 1325))
        #expect(onBravo.restoredFrame(on: [alpha, bravoToTheLeft]) == CGRect(x: -2000, y: 300, width: 1200, height: 800),
                "a display moved in the arrangement takes the window with it")

        // Gone: the main display, the same place from the top-left, kept inside its visible area.
        #expect(onBravo.restoredFrame(on: [alpha]) == CGRect(x: 400, y: 0, width: 1200, height: 800))
        let larger = MacWorkspaceWindowPlacement(frame: CGRect(x: 1700, y: 50, width: 2200, height: 1250),
                                                 display: "display-bravo", displayFrame: bravo.frame)
        #expect(larger.restoredFrame(on: [alpha]) == alpha.visibleFrame, "shrunk only to the visible area")

        // Its display is there but smaller: fitted onto it, not sent to another.
        let bravoSmaller = MacWorkspaceDisplay(id: "display-bravo",
                                               frame: CGRect(x: 1600, y: 0, width: 1920, height: 1080),
                                               visibleFrame: CGRect(x: 1600, y: 0, width: 1920, height: 1055))
        let wide = MacWorkspaceWindowPlacement(frame: CGRect(x: 1700, y: 300, width: 2200, height: 800),
                                               display: "display-bravo", displayFrame: bravo.frame)
        let fitted = wide.restoredFrame(on: [alpha, bravoSmaller])
        #expect(fitted == CGRect(x: 1600, y: 30, width: 1920, height: 800))
        #expect(fitted.map { bravoSmaller.visibleFrame.contains($0) } == true)

        // A display that could not be named: where it was, when that fits a display.
        let unnamed = MacWorkspaceWindowPlacement(frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        #expect(unnamed.restoredFrame(on: [alpha]) == unnamed.frame)
        let offScreen = MacWorkspaceWindowPlacement(frame: CGRect(x: 5000, y: 3000, width: 800, height: 600))
        #expect(offScreen.restoredFrame(on: [alpha]).map { alpha.visibleFrame.contains($0) } == true)
        #expect(onBravo.restoredFrame(on: []) == nil, "no display: SwiftUI's place")
    }

    @Test("the saved place is given back once, as the window first appears; a window opened fresh keeps SwiftUI's")
    func placedOnceAsItAppears() async throws {
        try await withDefaults { defaults in
            let before = savedWindow(defaults, sessions: ["glass-72"])
            let place = CGRect(x: 200, y: 150, width: 900, height: 600)
            before.savePlacement(MacWorkspaceWindowPlacement(frame: place, on: alpha, isFullScreen: false))

            let reopened = relaunched(before.windowID, defaults)
            let first = nsWindow()
            let keeper = tracker()
            defer { keeper.stop() }
            keeper.track(first, controller: reopened)
            #expect(first.frame == place)

            let again = nsWindow()
            let secondKeeper = tracker()
            defer { secondKeeper.stop() }
            secondKeeper.track(again, controller: reopened)
            #expect(again.frame == swiftUIsPlace, "the same controller shown again is not placed again")

            let fresh = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(startsEmpty: true), defaults: defaults)
            let freshWindow = nsWindow()
            let freshKeeper = tracker()
            defer { freshKeeper.stop() }
            freshKeeper.track(freshWindow, controller: fresh)
            #expect(freshWindow.frame == swiftUIsPlace, "+, ⌘N and workgroups keep today's placement")
        }
    }

    @Test("a window in full screen keeps the frame it had before, and goes back into full screen when reopened")
    func fullScreen() async throws {
        try await withDefaults { defaults in
            let window = savedWindow(defaults, sessions: ["glass-73"])
            let windowed = CGRect(x: 120, y: 90, width: 1000, height: 700)
            let shown = nsWindow(windowed)
            let keeper = tracker()
            defer { keeper.stop() }
            keeper.track(shown, controller: window)

            NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: shown)
            // AppKit's animation to the display's frame: not a place to come back to.
            shown.setFrame(alpha.frame, display: false)
            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: shown)
            #expect(!keeper.isWaitingToSave, "nothing waits to be saved from the animation")
            NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: shown)
            #expect(savedPlacement(defaults, window.windowID) == MacWorkspaceWindowPlacement(frame: windowed, on: alpha, isFullScreen: true))

            var entered: [NSWindow] = []
            let reopened = relaunched(window.windowID, defaults)
            let next = nsWindow()
            let nextKeeper = tracker { entered.append($0) }
            defer { nextKeeper.stop() }
            nextKeeper.track(next, controller: reopened)
            #expect(next.frame == windowed, "the frame it had before, so leaving full screen comes back to it")
            #expect(entered == [next], "and into full screen, once")

            NotificationCenter.default.post(name: NSWindow.willExitFullScreenNotification, object: shown)
            shown.setFrame(windowed, display: false)
            NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: shown)
            #expect(savedPlacement(defaults, window.windowID) == MacWorkspaceWindowPlacement(frame: windowed, on: alpha, isFullScreen: false))
        }
    }

    @Test("a place that can't be read costs the window its place, never its tabs")
    func damagedPlace() async throws {
        try await withDefaults { defaults in
            let window = savedWindow(defaults, sessions: ["glass-74", nil])
            window.savePlacement(MacWorkspaceWindowPlacement(frame: CGRect(x: 10, y: 10, width: 900, height: 600), on: alpha, isFullScreen: false))
            let key = "\(UserDefaultsKeys.macWorkspaceRestoration).window.\(window.windowID.uuidString.lowercased())"
            let data = try #require(defaults.data(forKey: key))
            var record = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            for damaged: Any in [["frame": "here"], ["frame": [[0, 0], [-5, 1e9]]]] {
                record["placement"] = damaged
                defaults.set(try JSONSerialization.data(withJSONObject: record), forKey: key)
                let next = relaunched(window.windowID, defaults)
                #expect(next.restorationFailure == nil)
                #expect(next.tabs.map(\.workspaceID) == window.tabs.map(\.workspaceID))
                #expect(next.takePlacementToRestore() == nil)
            }
        }
    }

    // MARK: Which windows come back

    @Test("the reopen list is taken once per process, whichever window asks first")
    func takenOnce() async throws {
        try await withDefaults { defaults in
            let saved = savedWindow(defaults, sessions: ["glass-75"])
            defaults.set([saved.windowID.uuidString], forKey: MacLocalTmux.reopenKey)

            let reopen = MacWindowsToReopen(defaults: defaults, registry: MacWorkspacePreviewRegistry())
            #expect(reopen.takeOnce(askedBy: "a terminal window") == [saved.windowID])
            #expect(reopen.takeOnce(askedBy: "the Connections window") == nil, "the next window to appear opens nothing")
            #expect(reopen.takeOnce(askedBy: "the Connections window") == nil, "nor does Connections appearing again")
            #expect(listed(defaults) == [saved.windowID], "still listed while it opens: a crash now loses nothing")
        }
    }

    @Test("the list follows windows as they open, close and gain tmux sessions, without a quit; closing for a quit leaves it")
    func keptCurrent() async throws {
        try await withDefaults { defaults in
            let registry = MacWorkspacePreviewRegistry()
            let reopen = MacWindowsToReopen(defaults: defaults, registry: registry)
            #expect(reopen.takeOnce(askedBy: "the Connections window") == [])
            var held: [NSWindow] = []
            @MainActor func show(_ window: MacWorkspaceWindowController) {
                held.append(nsWindow())
                registry.register(window, window: held[held.count - 1])
            }
            let first = savedWindow(defaults, sessions: ["glass-76"])
            let second = savedWindow(defaults, sessions: ["glass-77"])
            let plain = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(startsEmpty: true), defaults: defaults)
            plain.windowDidOpen()

            show(first)
            #expect(listed(defaults) == [first.windowID], "listed as it opens")
            show(second)
            show(plain)
            #expect(Set(listed(defaults)) == [first.windowID, second.windowID], "a window with nothing in tmux is not")

            registry.remove(first.windowID)
            #expect(listed(defaults) == [second.windowID], "closed by hand: no longer listed")

            // The empty tab gets a terminal that names a tmux session — an SSH terminal claims one
            // once it connects: listed when the tab is saved.
            plain.tabs[0].addPane(intent: intent("glass-78"), axis: .horizontal)
            #expect(Set(listed(defaults)) == [second.windowID, plain.windowID])

            reopen.prepareForQuit(displayOf: { _ in alpha })
            registry.remove(second.windowID)
            registry.remove(plain.windowID)
            #expect(Set(listed(defaults)) == [second.windowID, plain.windowID], "windows closing for the quit stay listed")
            withExtendedLifetime(held) {}
        }
    }

    @Test("after a crash — the list written while running, no quit — the same windows reopen where they were")
    func crash() async throws {
        try await withDefaults { defaults in
            let registry = MacWorkspacePreviewRegistry()
            var firstRun: MacWindowsToReopen? = MacWindowsToReopen(defaults: defaults, registry: registry)
            #expect(firstRun?.takeOnce(askedBy: "the Connections window") == [])
            let left = savedWindow(defaults, sessions: ["glass-79"])
            let right = savedWindow(defaults, sessions: ["glass-80", "glass-81"])
            let leftWindow = nsWindow(CGRect(x: 40, y: 60, width: 900, height: 700))
            let rightWindow = nsWindow(CGRect(x: 980, y: 60, width: 600, height: 900))
            let leftKeeper = tracker(), rightKeeper = tracker()
            defer { leftKeeper.stop(); rightKeeper.stop() }
            for (window, shown, keeper) in [(left, leftWindow, leftKeeper), (right, rightWindow, rightKeeper)] {
                registry.register(window, window: shown)
                keeper.track(shown, controller: window)
                NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: shown)
            }

            // The crash: no quit, nothing more written.
            firstRun = nil
            let nextRun = MacWindowsToReopen(defaults: defaults, registry: MacWorkspacePreviewRegistry())
            let reopening = try #require(nextRun.takeOnce(askedBy: "the Connections window"))
            #expect(Set(reopening) == [left.windowID, right.windowID])
            for (window, frame) in [(left, leftWindow.frame), (right, rightWindow.frame)] {
                let next = relaunched(window.windowID, defaults)
                #expect(next.tabs.map(\.workspaceID) == window.tabs.map(\.workspaceID))
                #expect(next.takePlacementToRestore()?.frame == frame)
            }
        }
    }

    @Test("nothing reopens twice: not a window already open, nor one whose every tab shows sessions already shown")
    func neverTwice() async throws {
        try await withDefaults { defaults in
            let first = savedWindow(defaults, sessions: ["glass-82"])
            let copy = savedWindow(defaults, sessions: ["glass-82"])
            let open = savedWindow(defaults, sessions: ["glass-83"])
            let partly = savedWindow(defaults, sessions: ["glass-83", "glass-84"])
            let alreadyShown = savedWindow(defaults, sessions: ["glass-83"])
            let registry = MacWorkspacePreviewRegistry()
            let shown = nsWindow()
            registry.register(open, window: shown)
            defaults.set([first, copy, open, partly, alreadyShown].map(\.windowID.uuidString), forKey: MacLocalTmux.reopenKey)

            let reopen = MacWindowsToReopen(defaults: defaults, registry: registry)
            #expect(reopen.takeOnce(askedBy: "the Connections window") == [first.windowID, partly.windowID],
                    "the copy shows the first one's session, one is open, one shows only the open one's")
            #expect(reopen.takeOnce(askedBy: "a terminal window") == nil)
            withExtendedLifetime(shown) {}
        }
    }

    // MARK: Why the list went unread

    @Test("the terminal window policy leaves restorability to SwiftUI")
    func policyLeavesRestorability() {
        let window = nsWindow()
        window.isRestorable = false
        MacTerminalWindowPolicy.apply(window, tabbingIdentifier: "test")
        #expect(!window.isRestorable,
                "forced on, AppKit brought terminal windows back empty after a crash, and Connections never appeared")
    }
}
}
#endif
