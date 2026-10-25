//
//  GlassAllWindowsAroundUITests.swift
//  GlassPowerToolsUITests
//
//  Show All Windows on Vision Pro, in a window and around the person, with the switch between them
//  (the owner, 2026-10-21: "go! build both with the switch"). Driven from `--demo-open all-windows`
//  on the visionOS simulator: three terminals, a desktop and an editor, and All Windows over them.
//

#if os(visionOS)
import XCTest

@MainActor
final class GlassAllWindowsAroundUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func launch(_ surface: String) {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", surface]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitGone(_ element: XCUIElement, _ message: String) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 15), .completed, message)
    }

    /// Around You from the window: the cards stand around the person, every session's, and the window
    /// gives way to them.
    func testAroundYouPutsTheCardsAroundThePerson() {
        launch("all-windows")
        let aroundYou = element("all-windows-around-you")
        XCTAssertTrue(aroundYou.waitForExistence(timeout: 60), "no Around You in the All Windows window")
        aroundYou.tap()

        XCTAssertTrue(element("all-windows-around-window").waitForExistence(timeout: 20),
                      "Around You didn't put the cards around the person")
        XCTAssertTrue(element("all-windows-around-done").exists, "no Done in the arc")
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "all-windows-card-"))
        XCTAssertGreaterThanOrEqual(cards.count, 4, "the arc doesn't hold every session's card")
        waitGone(element("all-windows-done"), "the window stayed with the arc")
    }

    /// In a Window from the arc: the window comes back and the arc goes. The runner can't tap a button
    /// in an immersive space's attachment (it found In a Window and tapped, and nothing reached it), so
    /// the demo presses it (`--demo-all-windows-around-back`); a look and a pinch on the headset reach it
    /// as they reach any button.
    func testInAWindowBringsTheWindowBack() {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", "all-windows", "--demo-all-windows-around", "--demo-all-windows-around-back"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let arc = element("all-windows-around-window")
        XCTAssertTrue(arc.waitForExistence(timeout: 60), "the demo didn't go around")
        waitGone(arc, "the arc stayed")
        XCTAssertTrue(element("all-windows-done").waitForExistence(timeout: 20), "the window didn't come back")
    }

    // The two-handed pinch itself can't be driven here: XCUITest has no pinch on visionOS. Its steps
    // are `GlassPinchStepsTests`; the gesture is checked on the headset.
}
#endif
