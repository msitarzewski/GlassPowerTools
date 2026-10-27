//
//  GlassSessionOrbUITests.swift
//  GlassPowerToolsUITests
//
//  A session window shrunk into its orb on Vision Pro, and grown back (the owner, 2026-10-15: "a
//  persistent system level session/service icon that shrinks a window into a small preview").
//  Driven on the visionOS simulator from `--demo-open terminal`, a terminal that connects to
//  nothing. The orb is captured from outside while the test waits (rule 11).
//

#if os(visionOS)
import XCTest

@MainActor
final class GlassSessionOrbUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testATerminalWindowShrinksIntoItsOrbAndGrowsBack() {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let shrink = element("session-orb-shrink")
        XCTAssertTrue(shrink.waitForExistence(timeout: 40), "no Shrink to Orb in the terminal's bar")
        XCTAssertTrue(element("terminal-footer-new-tab").exists, "the bar is not the terminal's")
        shrink.tap()

        let orb = element("session-orb")
        XCTAssertTrue(orb.waitForExistence(timeout: 10), "the window did not become its orb")
        // Its bar goes with it.
        XCTAssertTrue(element("terminal-footer-new-tab").waitForNonExistence(timeout: 5), "the bar stayed beside the orb")
        // For the capture from outside.
        sleep(8)

        orb.tap()
        XCTAssertTrue(element("terminal-footer-new-tab").waitForExistence(timeout: 10), "the window did not grow back")
        XCTAssertFalse(orb.exists, "the orb stayed")
    }

    /// D88: with Settings ▸ Appearance ▸ Orbs on Into the Dock, Shrink to Orb closes the terminal's
    /// window into the dock, where its orb waits; a pinch on it brings the window back, and the dock,
    /// holding nothing else, goes.
    func testATerminalWindowShrinksIntoTheDockAndComesBack() {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal",
                                "-com.glasspowertools.orbs.inDock", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let shrink = element("session-orb-shrink")
        XCTAssertTrue(shrink.waitForExistence(timeout: 40), "no Shrink to Orb in the terminal's bar")
        shrink.tap()

        let dock = element("orb-dock")
        XCTAssertTrue(dock.waitForExistence(timeout: 10), "the dock did not open")
        XCTAssertTrue(element("terminal-footer-new-tab").waitForNonExistence(timeout: 10),
                      "the terminal's window stayed open beside the dock")
        let orb = dock.descendants(matching: .any).matching(identifier: "session-orb").firstMatch
        XCTAssertTrue(orb.waitForExistence(timeout: 10), "the window has no orb in the dock")
        // For the capture from outside.
        sleep(8)

        orb.tap()
        XCTAssertTrue(element("terminal-footer-new-tab").waitForExistence(timeout: 15), "the window did not come back")
        XCTAssertTrue(dock.waitForNonExistence(timeout: 10), "the dock stayed with nothing in it")
    }

    /// D88: an orb held and let go on another takes its place in the dock (the owner, 2026-10-25:
    /// "pinch/click and hold on a docked window to move its order so muscle memory can land"). Two
    /// terminal windows, each shrunk into the dock as it opens (`--demo-session-orb`).
    func testAnOrbHeldAndLetGoOnAnotherTakesItsPlace() {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal-move",
                                "--demo-session-orb", "-com.glasspowertools.orbs.inDock", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let dock = element("orb-dock")
        XCTAssertTrue(dock.waitForExistence(timeout: 40), "the dock did not open")
        let orbs = dock.descendants(matching: .any).matching(identifier: "session-orb")
        let both = expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: orbs)
        XCTAssertEqual(XCTWaiter().wait(for: [both], timeout: 20), .completed, "two windows, two orbs in the dock")
        // The landing done.
        sleep(3)
        func names() -> [String] {
            orbs.allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }.map(\.label)
        }
        let before = names()
        XCTAssertEqual(Set(before).count, 2, "each orb named for its window: \(before)")

        let second = orbs.allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX }!
        let first = orbs.allElementsBoundByIndex.min { $0.frame.minX < $1.frame.minX }!
        second.press(forDuration: 1.2, thenDragTo: first)
        let moved = expectation(for: NSPredicate { _, _ in names() == before.reversed() }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 10), .completed,
                       "the orb let go on the first did not take its place: \(names()) from \(before)")
    }

    /// D88: a database goes into the dock as its machine's orb, and comes back with its session:
    /// until the dock, closing a database's window disconnected it, and a session that ended would
    /// leave no orb in the dock. (The demo desktop is on throwaway storage, which the app does not
    /// list, so a desktop is not driven here; such a window shrinks where it is.)
    func testADatabaseShrinksIntoTheDockAndComesBackStillConnected() {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "database",
                                "-com.glasspowertools.orbs.inDock", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let shrink = element("session-orb-shrink")
        XCTAssertTrue(shrink.waitForExistence(timeout: 40), "no Shrink to Orb in the database's bar")
        sleep(2)
        shrink.tap()

        let dock = element("orb-dock")
        XCTAssertTrue(dock.waitForExistence(timeout: 10), "the dock did not open")
        XCTAssertTrue(shrink.waitForNonExistence(timeout: 10), "the database's window stayed open")
        let orb = dock.descendants(matching: .any).matching(identifier: "session-orb").firstMatch
        XCTAssertTrue(orb.waitForExistence(timeout: 10), "the database has no orb in the dock: its session ended")
        // For the capture from outside.
        sleep(6)

        orb.tap()
        XCTAssertTrue(shrink.waitForExistence(timeout: 15), "the database did not come back")
        XCTAssertTrue(dock.waitForNonExistence(timeout: 10), "the dock stayed with nothing in it")
    }

    /// A desktop's window is held to its display's shape (W38). As its orb it is freed to take the
    /// orb's size; grown back, it is held again — it stayed free after a round trip. The hold itself
    /// is visionOS's and can't be read here: the run logs it (`app.glassdt` / `window-aspect`,
    /// `event=aspect-geometry uniform=…`), read from outside after the grow.
    func testADesktopShrinksIntoItsOrbAndGrowsBack() {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "desktop"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let shrink = element("session-orb-shrink")
        XCTAssertTrue(shrink.waitForExistence(timeout: 40), "no Shrink to Orb in the desktop's bar")
        XCTAssertTrue(element("session.display").exists, "the bar is not the desktop's")
        // The shape held first, as a desktop opens.
        sleep(3)
        shrink.tap()

        let orb = element("session-orb")
        XCTAssertTrue(orb.waitForExistence(timeout: 10), "the desktop did not become its orb")
        // For the capture from outside.
        sleep(8)

        orb.tap()
        XCTAssertTrue(element("session.display").waitForExistence(timeout: 10), "the desktop did not grow back")
        // For the shape to be held again, and logged.
        sleep(4)
    }

    /// The owner, 2026-10-15: "redraw the tabs around the orb evenly distributed with a preview in the
    /// orb on hover", and a pinch on one grows the window back on it.
    func testAWindowsTabsRingItsOrbAndOneGrowsItBack() {
        app = XCUIApplication()
        // Shrunk by the demo a few seconds in: with two terminals the orb is in the view menu, whose
        // hold the simulator's runner turns into a tap.
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal-tabs", "--demo-session-orb"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        XCTAssertTrue(element("vision-terminal-presentation").waitForExistence(timeout: 40), "no view menu in the bar")
        XCTAssertEqual(element("session-orb-shrink").exists, false, "Shrink to Orb beside a view menu that offers the orb")
        XCTAssertTrue(element("session-orb").waitForExistence(timeout: 20), "the window did not become its orb")
        let dots = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "session-orb-tab-"))
        let both = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: dots)
        XCTAssertEqual(XCTWaiter().wait(for: [both], timeout: 10), .completed, "the window's two tabs are not on the ring")
        // For the capture from outside.
        sleep(8)

        dots.element(boundBy: 1).tap()
        XCTAssertTrue(element("terminal-footer-new-tab").waitForExistence(timeout: 10), "a tab's dot did not grow the window back")
        XCTAssertEqual(dots.count, 0, "the ring stayed")
    }
}
#endif
