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
    /// terminal windows, each shrunk into the dock as it opens (`--demo-session-orb`). The hold is
    /// UIKit's since 2026-10-26, so a quick drag scrolls the dock, and the runner's hold reaches no
    /// UIKit recognizer (a press came out as a pinch), so `--demo-dock-carry` carries the last orb
    /// onto the first through what a hold does; the hold itself is the headset's to show.
    func testAnOrbCarriedOntoAnotherTakesItsPlace() {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal-move",
                                "--demo-session-orb", "--demo-dock-carry", "-com.glasspowertools.orbs.inDock", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let dock = element("orb-dock")
        XCTAssertTrue(dock.waitForExistence(timeout: 40), "the dock did not open")
        let orbs = dock.descendants(matching: .any).matching(identifier: "session-orb")
        let both = expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: orbs)
        XCTAssertEqual(XCTWaiter().wait(for: [both], timeout: 20), .completed, "two windows, two orbs in the dock")
        sleep(1)
        func names() -> [String] {
            orbs.allElementsBoundByIndex.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }.map(\.label)
        }
        let before = names()
        XCTAssertEqual(Set(before).count, 2, "each orb named for its window: \(before)")
        let moved = expectation(for: NSPredicate { _, _ in names() == before.reversed() }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 20), .completed,
                       "the orb carried onto the first did not take its place: \(names()) from \(before)")
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

    // MARK: The dock's line, scroll, Connections menu and sides (the owner, 2026-10-26; 2026-11-05)

    /// Two terminal windows shrunk into the dock as they open: a row, or a column (`vertical`); its longest
    /// shortened to `longest`, so one orb is out of sight; resized to `size` (a hand on its corner, which the runner
    /// cannot drag).
    private func dockTwoTerminals(vertical: Bool = false, longest: Int? = nil,
                                  resizedTo size: String? = nil) -> (dock: XCUIElement, orbs: XCUIElementQuery, connections: XCUIElement) {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal-move",
                                "--demo-session-orb", "-com.glasspowertools.orbs.inDock", "YES"]
            + (vertical ? ["-com.glasspowertools.orbs.dockOrientation", "vertical"] : [])
            + (longest.map { ["--demo-dock-longest", String($0)] } ?? [])
            + (size.map { ["--demo-dock-resize", $0] } ?? [])
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let dock = element("orb-dock")
        XCTAssertTrue(dock.waitForExistence(timeout: 40), "the dock did not open")
        let orbs = dock.descendants(matching: .any).matching(identifier: "session-orb")
        let both = expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: orbs)
        XCTAssertEqual(XCTWaiter().wait(for: [both], timeout: 20), .completed, "two windows, two orbs in the dock")
        let connections = dock.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open Connections")).firstMatch
        XCTAssertTrue(connections.waitForExistence(timeout: 10), "no Connections orb in the dock")
        // The landing, and the resize asked for four seconds after the dock opened.
        sleep(size == nil ? 3 : 7)
        return (dock, orbs, connections)
    }

    /// "An orientation selection for the dock. horizontal or vertical" (2026-11-05): a row, Connections then each orb
    /// beside the last; a column, each below the last.
    func testTheDockIsARowOrAColumn() {
        let (_, orbs, connections) = dockTwoTerminals()
        let row = orbs.allElementsBoundByIndex.map(\.frame).sorted { $0.minX < $1.minX }
        let lead = connections.frame
        XCTAssertTrue(row.allSatisfy { abs($0.midY - lead.midY) < lead.height / 2 }, "not one row: \(row) \(lead)")
        XCTAssertGreaterThan(row[0].minX, lead.maxX, "the first orb is not beside Connections")
        XCTAssertGreaterThan(row[1].minX, row[0].maxX - 20, "the second orb is not beside the first: \(row)")
        app.terminate()

        let (_, column, top) = dockTwoTerminals(vertical: true)
        let stacked = column.allElementsBoundByIndex.map(\.frame).sorted { $0.minY < $1.minY }
        XCTAssertGreaterThan(stacked[0].minY, top.frame.maxY - 20, "the first orb is not below Connections")
        XCTAssertGreaterThan(stacked[1].minY, stacked[0].maxY - 20, "the second orb is not below the first: \(stacked)")
        // For the capture from outside.
        sleep(6)
    }

    /// "Make sure the a pinch and drag scrolls the dock 100% of the time": a dock too short for its
    /// orbs scrolls under a quick drag that starts on an orb, and the orb is not carried.
    func testAQuickDragOnAnOrbScrollsTheDock() {
        // Connections and one orb in view, the other below.
        let (_, orbs, connections) = dockTwoTerminals(vertical: true, longest: 700)
        let highest = orbs.allElementsBoundByIndex.min { $0.frame.minY < $1.frame.minY }!
        let before = connections.frame.minY
        let names = orbs.allElementsBoundByIndex.map(\.label)
        highest.swipeUp()
        sleep(2)
        XCTAssertLessThan(connections.frame.minY, before - 40, "the dock did not scroll: Connections stayed at \(before)")
        XCTAssertEqual(orbs.allElementsBoundByIndex.map(\.label), names, "a quick drag carried an orb")
    }

    /// Resized by hand to 600x900 (a hand on its corner, which the runner can't drag), the dock goes back to fitting
    /// its orbs in its row once the hand lets go (2026-11-05: a size given isn't kept; it had snapped within it, and a
    /// window docked again landed on a new row).
    func testAResizedDockGoesBackToFittingItsOrbs() {
        let (dock, orbs, connections) = dockTwoTerminals(resizedTo: "600x900")
        let back = expectation(for: NSPredicate { _, _ in dock.frame.height < 400 }, evaluatedWith: nil)
        _ = XCTWaiter().wait(for: [back], timeout: 15)
        let size = dock.frame.size
        XCTAssertEqual(size.height, 320 + 2 * 16, accuracy: 2, "the dock is not one row of orbs tall: \(size)")
        XCTAssertGreaterThan(size.width, 600 + 10, "the dock kept the width it was given, not its orbs': \(size)")
        let lead = connections.frame
        XCTAssertTrue(orbs.allElementsBoundByIndex.allSatisfy { abs($0.frame.midY - lead.midY) < lead.height / 2 },
                      "the orbs are not in Connections' row")
        // For the capture from outside.
        sleep(4)
    }

    /// "We need end arrows to show that there's more to scroll to in the dock": a column showing two of
    /// its three orbs has an arrow at its foot and none at its head; a pinch on it scrolls an orb, and
    /// the arrow at its head comes.
    func testTheDockShowsArrowsWhereThereIsMore() {
        let (_, _, connections) = dockTwoTerminals(vertical: true, longest: 700)
        let below = element("orb-dock-more-below"), above = element("orb-dock-more-above")
        XCTAssertTrue(below.waitForExistence(timeout: 10), "no arrow where there is more below")
        XCTAssertFalse(above.exists, "an arrow above, with nothing there")
        let before = connections.frame.minY
        below.tap()
        XCTAssertTrue(above.waitForExistence(timeout: 5), "no arrow above after scrolling down")
        XCTAssertLessThan(connections.frame.minY, before - 100, "the arrow did not scroll the dock a row")
        XCTAssertFalse(below.exists, "an arrow below, with nothing more there")
    }

    /// "Clicking the orb icon puts the window into the dock, but because the dock 'window' shrunk when the window was
    /// moved out of the dock, it gets reinserted on a new row. That's not expected behavior" (2026-11-05): an orb
    /// brings its window back, the dock shrinks, and the window goes into the dock again, into the same row.
    func testAWindowDockedAgainGoesBackIntoTheRow() {
        let (dock, orbs, connections) = dockTwoTerminals()
        let before = dock.frame.size
        orbs.firstMatch.tap()
        let shrink = element("session-orb-shrink")
        XCTAssertTrue(shrink.waitForExistence(timeout: 15), "the window did not come back")
        let shrunk = expectation(for: NSPredicate { _, _ in dock.frame.width < before.width - 100 }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shrunk], timeout: 15), .completed, "the dock did not shrink: \(dock.frame)")
        shrink.tap()
        let back = expectation(for: NSPredicate { _, _ in orbs.count == 2 && dock.frame.width > before.width - 2 }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 20), .completed, "the dock did not grow back: \(dock.frame)")
        XCTAssertEqual(dock.frame.height, before.height, accuracy: 2, "the dock grew a row: \(dock.frame)")
        let lead = connections.frame
        for orb in orbs.allElementsBoundByIndex {
            XCTAssertLessThan(abs(orb.frame.midY - lead.midY), lead.height / 2, "an orb is not in Connections' row: \(orb.frame)")
        }
        // For the capture from outside.
        sleep(4)
    }

    /// "Give it functionality with pinch and hold actions": held, Connections in the dock offers Dock
    /// Settings (the owner, 2026-10-27: "No menu on the connections icon
    /// with pinch and hold").
    func testHoldingConnectionsInTheDockOpensItsMenu() {
        let (_, _, connections) = dockTwoTerminals(resizedTo: nil)
        connections.press(forDuration: 1.5)
        // A menu's items are found by their words, as the library's row menu is.
        let settings = app.buttons["Dock Settings"].firstMatch
        let appeared = settings.waitForExistence(timeout: 10)
        XCTAssertTrue(appeared, "pinch and hold on Connections showed no menu")
        // For the capture from outside.
        sleep(4)
    }

    /// "The windows (in dock mode) should know not to appear on the top in a vertical oriented dock,
    /// it should appear to the left or right": from a vertical dock, a window comes back beside it. The
    /// simulator's head faces straight ahead, so it comes back to the dock's trailing side. The
    /// runner reads each window's frame in that window's own space, so the dock says the side it
    /// chose (`orb-dock-last-side`); where the window stands is the capture's to show.
    func testAWindowFromATallDockComesBackBesideIt() {
        let (dock, orbs, _) = dockTwoTerminals(vertical: true)
        XCTAssertEqual(dock.value as? String, "tall")
        orbs.firstMatch.tap()
        XCTAssertTrue(element("terminal-footer-new-tab").waitForExistence(timeout: 15), "the window did not come back")
        XCTAssertEqual(element("orb-dock-last-side").value as? String, "trailing",
                       "a window from a tall dock did not come back beside it")
        // For the capture from outside.
        sleep(4)
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
        // With two terminals the orb is the view menu's own action (a pinch on it, 2026-10-21). It was
        // shrunk by the demo four seconds in, which raced the runner: once it waited eight seconds for
        // the app to settle, the bar was gone before it looked (2026-10-26).
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal-tabs"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let views = element("vision-terminal-presentation")
        XCTAssertTrue(views.waitForExistence(timeout: 40), "no view menu in the bar")
        XCTAssertEqual(element("session-orb-shrink").exists, false, "Shrink to Orb beside a view menu that offers the orb")
        views.tap()
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
