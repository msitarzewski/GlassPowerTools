//
//  DesktopOnIPhoneUITests.swift
//  GlassPowerToolsUITests
//
//  A remote desktop on an iPhone with the software keyboard up (the owner, 2026-10-15, with a
//  screenshot of two rows of the same controls: "this is kind of a mess"). The window's status bar
//  steps aside while the keyboard's own bar is up, as a terminal's does. Driven from
//  `--demo-open desktop`, a desktop that connects to nothing.
//

#if os(iOS)
import XCTest

@MainActor
final class DesktopOnIPhoneUITests: XCTestCase {
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

    func testTheStatusBarStepsAsideWhileTheKeyboardsBarIsUp() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("an iPhone's layout") }
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "desktop"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let keyboard = element("session.keyboard")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 30), "no status bar with its Keyboard button")
        XCTAssertTrue(keyboard.isEnabled, "the demo desktop is not connected")
        keyboard.tap()

        XCTAssertTrue(element("session.keyboard-dismiss").waitForExistence(timeout: 10), "the keyboard's bar did not come up")
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "two bars of the same controls")
        // For the capture from outside.
        sleep(3)

        element("session.keyboard-dismiss").tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "the status bar did not come back with the keyboard gone")
    }
}
#endif
