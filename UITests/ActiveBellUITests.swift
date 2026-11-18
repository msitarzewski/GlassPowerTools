#if os(iOS)
import XCTest

/// Active shows which open windows have a terminal whose bell rang out of sight (the owner, 2026-11-15, on the
/// iPhone: the Active list "doesn't highlight which terminals need attention / have alerts (the orange
/// pulse/highlight)"). The row glows orange beneath, as a tab does (`GlassBell`), and VoiceOver says "Bell rang"; the
/// glow goes once the terminal has been seen. Screenshots are kept: the glow itself is judged by eye.
@MainActor
final class ActiveBellUITests: XCTestCase {
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("glass-active-bell-\(name).png")
        try? app.screenshot().pngRepresentation.write(to: url)
        print("SHOT \(name) -> \(url.path)")
    }

    func testAWindowWhoseBellRangOutOfSightIsMarkedInActive() throws {
        let app = XCUIApplication()
        // The demo window of two tabs (the bell's demo is that window's); its first terminal, the one shown, rings 12 s
        // after it opens: by then Active is in front, and it is out of sight.
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal-tabs", "--demo-bell", "0@12"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let bolt = app.buttons["active-connections-bolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 30), "the demo terminal did not open")
        bolt.tap()

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'active-session-terminal'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the terminal's window is not under Active")
        XCTAssertNotEqual(row.value as? String, "Bell rang", "marked before its bell rang")
        shoot(app, "01-before")

        let rang = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Bell rang'"), object: row)
        XCTAssertEqual(XCTWaiter().wait(for: [rang], timeout: 30), .completed,
                       "the window's row does not say its bell rang (value: \(String(describing: row.value)))")
        shoot(app, "02-rang")

        // Seen: chosen, its terminal is in front, and back on Active the mark is gone.
        row.tap()
        XCTAssertTrue(bolt.waitForExistence(timeout: 15), "choosing the row did not bring the terminal back")
        sleep(2)
        bolt.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the window left Active")
        XCTAssertNotEqual(row.value as? String, "Bell rang", "still marked after its terminal was seen")
        shoot(app, "03-seen")
    }
}
#endif
