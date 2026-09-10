import XCTest

@MainActor
final class LaunchSmokeUITests: XCTestCase {
    /// The app launches, reaches the foreground, and shows the host library (the kit's scope
    /// list is present on every platform; on iPhone it is the first screen).
    func testMainWindowAppears() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString]
        #if os(macOS)
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let scope = app.descendants(matching: .any).matching(identifier: "glass-library-scope-all-connections").firstMatch
        let add = app.descendants(matching: .any).matching(identifier: "connection-library-add-host").firstMatch
        let addEmpty = app.descendants(matching: .any).matching(identifier: "connection-library-add-host-empty").firstMatch
        XCTAssertTrue(scope.waitForExistence(timeout: 15) || add.waitForExistence(timeout: 5) || addEmpty.waitForExistence(timeout: 5),
                      "library scopes or the Add Host control should be on screen")
    }
}
