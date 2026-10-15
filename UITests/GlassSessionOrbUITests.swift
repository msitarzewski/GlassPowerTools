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
}
#endif
