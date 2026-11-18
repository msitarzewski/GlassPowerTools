#if os(iOS)
import XCTest

/// Moving a terminal into another set from the name menu at the top, on the iPhone (the owner, 2026-11-15: "the only way
/// is through the name menu and that crashed. it worked, but it crashed"). Each set holds one terminal, as Active's
/// sets do when each was opened from it: the move empties the set on screen, which closes, and the screen follows the
/// terminal into the set it went to.
@MainActor
final class TerminalMoveOnIPhoneUITests: XCTestCase {
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testMovingASetsOnlyTerminalIntoAnotherSet() throws {
        let app = XCUIApplication()
        // Two sets of one terminal each: alpha, then bravo, which is on screen.
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal-move"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let switcher = app.buttons["terminal-workgroup-session-switcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 30), "no name menu at the top")
        sleep(3)
        shoot(app, "01-before")

        switcher.tap()
        let moveTo = app.buttons["Move Tab To"].firstMatch
        XCTAssertTrue(moveTo.waitForExistence(timeout: 10), "no Move Tab To in the name menu")
        shoot(app, "02-menu")
        moveTo.tap()
        let alpha = app.buttons["alpha"].firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 10), "the other set is not offered")
        shoot(app, "03-destinations")
        alpha.tap()

        sleep(4)
        shoot(app, "04-after")
        XCTAssertEqual(app.state, .runningForeground, "the app is gone after the move")
        XCTAssertTrue(switcher.waitForExistence(timeout: 15), "the screen did not follow the terminal into its new set")
        switcher.tap()
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS 'alpha' OR label CONTAINS 'bravo'"))
        XCTAssertGreaterThanOrEqual(rows.count, 2, "the set does not hold both terminals")
        shoot(app, "05-both")
    }

    /// The owner, 2026-11-15: "the active list has a select, but it doesnt work, so i cant select multiple to add to a
    /// set." Sets open on the phone are chosen in Active and gathered into one.
    func testChoosingSetsInActiveGathersThemIntoOne() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal-move"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let bolt = app.buttons["active-connections-bolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 30), "the demo terminal did not open")
        sleep(2)
        bolt.tap()

        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'active-session-terminal:'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "no sets under Active")
        XCTAssertEqual(rows.count, 2, "two sets of one terminal each")
        let select = app.buttons["active-select"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        XCTAssertTrue(select.isEnabled, "Select is off with only sets open here")
        select.tap()
        rows.element(boundBy: 0).tap()
        rows.element(boundBy: 1).tap()
        shoot(app, "gather-01-chosen")
        let together = app.buttons["active-open-together"].firstMatch
        XCTAssertTrue(together.waitForExistence(timeout: 5), "no Open Together while choosing")
        XCTAssertEqual(together.label, "Open 2 Together")
        XCTAssertTrue(together.isEnabled, "two sets chosen, and Open Together is off")
        together.tap()

        let switcher = app.buttons["terminal-workgroup-session-switcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 15), "the gathered set is not on screen")
        sleep(2)
        shoot(app, "gather-02-set")
        switcher.tap()
        let both = app.buttons.matching(NSPredicate(format: "label CONTAINS 'alpha' OR label CONTAINS 'bravo'"))
        XCTAssertGreaterThanOrEqual(both.count, 2, "the set does not hold both terminals")
        shoot(app, "gather-03-menu")
        // Out of the menu by choosing a terminal in it: a tap on ⚡ while it is open only closes it.
        both.firstMatch.tap()
        sleep(1)
        app.buttons["active-connections-bolt"].firstMatch.tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(rows.count, 1, "Active lists one set, holding both")
        shoot(app, "gather-04-active")
    }
}
#endif
