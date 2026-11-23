//
//  TerminalSwipeOnIPhoneUITests.swift
//  GlassPowerToolsUITests
//
//  A swipe over a program that has the mouse scrolls it (the owner, 2026-11-22: a terminal running
//  Claude Code in its full-screen mode wouldn't scroll on the iPhone). The headset has turned such a
//  swipe into the mouse wheel since 2026-10-15; the iPhone sent the finger's drag to the program as
//  a mouse drag, which a program that selects with the mouse takes as a selection.
//
//  Driven from `--demo-open terminal-tmux`: the alternate screen with the mouse asked for, which
//  shows the wheel it is sent on its status line (`DemoWheelAnswer`).
//

#if os(iOS)
import XCTest

@MainActor
final class TerminalSwipeOnIPhoneUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private var terminal: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Terminal")).firstMatch
    }

    /// The status line once the program has been sent the wheel turned `direction`.
    private func wheel(_ direction: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@", "[wheel \(direction)]")).firstMatch
    }

    /// The terminal while it has a selection of its own (UI-testing runs only).
    private var selected: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-selection-active")).firstMatch
    }

    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testASwipeScrollsAProgramThatHasTheMouse() {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", "terminal-tmux"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCTAssertTrue(terminal.waitForExistence(timeout: 40), "no terminal")
        // The demo's screen drawn and the mouse asked for before the swipe.
        sleep(3)

        // Above where the keyboard comes up.
        let top = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let lower = top.withOffset(CGVector(dx: 0, dy: 220))
        // Fingers moving down bring earlier output into view: the wheel turned up.
        top.press(forDuration: 0.05, thenDragTo: lower)
        let up = wheel("up").waitForExistence(timeout: 5)
        if !up { attachScreen("after a swipe down") }
        XCTAssertTrue(up, "a swipe down didn't reach the program as its wheel")
        XCTAssertFalse(selected.exists, "the swipe selected")

        lower.press(forDuration: 0.05, thenDragTo: top)
        let down = wheel("down").waitForExistence(timeout: 5)
        if !down { attachScreen("after a swipe up") }
        XCTAssertTrue(down, "a swipe up didn't turn the program's wheel down")
    }
}
#endif
