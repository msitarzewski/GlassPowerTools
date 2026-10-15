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
