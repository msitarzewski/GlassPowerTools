#if os(iOS)
import XCTest

/// A terminal's coding agent wherever a terminal's icon is shown, as its tab marks it (the owner, 2026-11-16, on the
/// iPhone: "the terminals don't reflect the coding agent like the tabs do. That should be a constant when a terminal
/// icon is shown"): Active's rows — a window's, and a session running on a machine — and the name menu's items. The
/// marks are hidden from VoiceOver, as a tab's are, so the pictures are judged by eye; the test checks that each
/// surface is there to be pictured.
@MainActor
final class ActiveAgentMarksUITests: XCTestCase {
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The machines' made-up sessions (`--demo-open active`): Claude Code on alpha, Codex on build, a shell on each.
    /// The demo lists them under the library's machines, so the library has them.
    func testRunningSessionsShowTheirAgents() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh|build@192.0.2.11:ssh|nas@192.0.2.12:ssh",
                                "--demo-open", "active"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'active-running-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Active lists no running session")
        sleep(1)
        shoot(app, "01-running")
    }

    /// A window whose terminal runs Claude Code (`--demo-open agent`): its row in Active, and the name menu's item.
    func testAWindowAndItsNameMenuShowTheAgent() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "agent"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let menu = app.descendants(matching: .any)["terminal-workgroup-session-switcher"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "the demo terminal did not open")
        sleep(2)
        menu.tap()
        sleep(1)
        shoot(app, "02-name-menu")
        // Closed by choosing its only terminal, the one shown.
        let item = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Claude'")).firstMatch
        if item.waitForExistence(timeout: 5) { item.tap() } else { app.tap() }
        let bolt = app.buttons["active-connections-bolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 15))
        bolt.tap()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'active-session-terminal'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the terminal's window is not under Active")
        sleep(1)
        shoot(app, "03-window-row")
    }
}
#endif
