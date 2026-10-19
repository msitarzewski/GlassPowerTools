#if os(iOS)
import XCTest

/// A database on iPad, which opens in a window of its own.
///
/// Found 2026-10-18 while making the App Store screenshots: on iPad, opening a database stopped the
/// app ("No Observable object of type DatabaseIOSRouter found"). The workspace read the phone's
/// in-place router as required, and only the library's window supplies it, while an iPad opens the
/// workspace in a scene of its own. Driven from the demo's database (`--demo-open database`), which
/// connects and opens the workspace the way a tap on Connect does.
@MainActor
final class DatabaseOnIPadUITests: XCTestCase {

    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
    }

    func testOpeningADatabaseOpensItsWindow() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad,
                          "An iPad opens a database in its own window; an iPhone shows it in place")
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh+database",
                                "--demo-open", "database"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let workspace = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["database-workspace-settings", "database-workspace-connections"])
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 30), "the database's window did not appear")
        XCTAssertEqual(app.state, .runningForeground, "the app stopped while opening the database")
    }
}
#endif
