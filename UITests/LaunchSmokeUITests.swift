import XCTest

@MainActor
final class LaunchSmokeUITests: XCTestCase {
    func testMainWindowAppears() {
        continueAfterFailure = false
        let app = XCUIApplication()
        #if os(macOS)
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCTAssertTrue(app.staticTexts["glasspowertools-main-placeholder"].waitForExistence(timeout: 15))
    }
}
