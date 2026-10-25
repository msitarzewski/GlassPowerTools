#if os(iOS)
import XCTest

/// A database on iPad, which opens in a window of its own; on a phone, in place. Either way the
/// workspace arrives and the app goes on running.
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
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh+database",
                                "--demo-open", "database"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let workspace = app.descendants(matching: .any).matching(
            // The Overview tab is the workspace's on every device; a phone keeps Settings and the way
            // back in its bar's overflow, or the Duo's column.
            NSPredicate(format: "identifier IN %@", ["db-workspace-tab-connection", "database-workspace-settings",
                                                     "database-workspace-connections"])
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 30), "the database's workspace did not appear")
        XCTAssertEqual(app.state, .runningForeground, "the app stopped while opening the database")
    }
}
#endif
