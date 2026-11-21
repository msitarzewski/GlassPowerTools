#if os(iOS)
import XCTest

/// Get Info from a terminal's menu on iPhone (the owner, 2026-11-19: "a right click > Get Info... on the tabs so
/// finding its tmux name is easier"): the name menu offers it, and the sheet says the terminal's session and machine.
@MainActor
final class TerminalGetInfoUITests: XCTestCase {
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testGetInfoFromTheNameMenu() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "agent"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let menu = app.descendants(matching: .any)["terminal-workgroup-session-switcher"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "the demo terminal did not open")
        sleep(2)
        menu.tap()
        let getInfo = app.buttons["Get Info…"].firstMatch
        XCTAssertTrue(getInfo.waitForExistence(timeout: 10), "the name menu offers Get Info")
        shoot(app, "01-name-menu")
        getInfo.tap()
        let done = app.buttons["terminal-info-done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the sheet opens")
        XCTAssertTrue(app.staticTexts["Machine"].firstMatch.exists, "it says the machine")
        sleep(1)
        shoot(app, "02-get-info")
        done.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Done closes it, back to the terminal")
    }
}
#endif
