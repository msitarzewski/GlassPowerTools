#if os(iOS)
import XCTest

/// All Windows on a phone (the owner, 2026-10-14: "drag down from an empty space in the toolbar
/// … slide in like a separate transparent pane", and the ⚡ "hold pattern"). Driven as a person
/// does it: a pull that starts on the top bar's empty middle, and a hold on the bolt. Screenshots
/// are kept, because whether the pane arrives is what a screenshot says.
@MainActor
final class GlassAllWindowsPaneUITests: XCTestCase {
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("glass-\(name).png")
        try? app.screenshot().pngRepresentation.write(to: url)
        print("SHOT \(name) -> \(url.path)")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        return app
    }

    private func pane(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "all-windows").firstMatch
    }

    func testPullingDownOnTheTopBarOpensAllWindows() throws {
        let app = launch()
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "the library has no top bar")
        shoot(app, "pull-01-library")

        // The bar's middle, where the title is: empty space as far as touches go.
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)))
        XCTAssertTrue(pane(app).waitForExistence(timeout: 5), "a pull on the top bar did not open All Windows")
        shoot(app, "pull-02-pane")

        app.buttons["all-windows-done"].firstMatch.tap()
        XCTAssertTrue(pane(app).waitForNonExistence(timeout: 5), "Done did not close All Windows")
        shoot(app, "pull-03-closed")
    }

    func testHoldingTheBoltOpensAllWindows() throws {
        let app = launch()
        let bolt = app.buttons["active-connections-bolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 20), "no ⚡ in the library's toolbar")
        bolt.press(forDuration: 1.0)
        XCTAssertTrue(pane(app).waitForExistence(timeout: 5), "holding the ⚡ did not open All Windows")
        shoot(app, "hold-01-pane")
        app.buttons["all-windows-done"].firstMatch.tap()
        XCTAssertTrue(pane(app).waitForNonExistence(timeout: 5))
    }

    /// A ⚡ under a sheet is covered, and a hold there is the sheet's. On the Duo's outer display
    /// the Add Host sheet's bar lies over the library's ⚡, and a hold on the bar opened All Windows
    /// over the sheet (2026-10-25: a database test's press for the edit menu landed there, the pane
    /// took the screen, and the field kept its old text). The hold knows a ⚡ that SwiftUI draws by
    /// the view behind it, and a sheet does not take that view out of the window.
    func testHoldingASheetOverTheBoltIsNotAHoldOnTheBolt() throws {
        let app = launch()
        let bolt = app.buttons["active-connections-bolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 20), "no ⚡ in the library's toolbar")
        let under = bolt.frame

        let empty = app.descendants(matching: .any).matching(identifier: "connection-library-add-host-empty").firstMatch
        if empty.waitForExistence(timeout: 3) {
            empty.tap()
        } else {
            app.descendants(matching: .any).matching(identifier: "connection-library-add-host").firstMatch.tap()
        }
        let name = app.textFields["host-editor-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the Add Host sheet")
        shoot(app, "covered-01-sheet")

        // A part of the ⚡ clear of the sheet's own buttons: on the Duo's outer display Cancel lies
        // over most of it, and a hold on Cancel is Cancel.
        let sheetButtons = ["host-editor-cancel", "host-editor-save"].map { app.buttons[$0].firstMatch.frame }
        let spot = stride(from: under.minX + 2, through: under.maxX - 2, by: 2)
            .map { CGPoint(x: $0, y: under.midY) }
            .first { point in !sheetButtons.contains { $0.contains(point) } }
        guard let spot else {
            XCTFail("the sheet's Cancel and Add cover the whole ⚡ (\(under)); this test needs another spot here")
            return
        }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: spot.x, dy: spot.y)).press(forDuration: 1.0)
        XCTAssertFalse(pane(app).waitForExistence(timeout: 3),
                       "a hold on the sheet, where the library's ⚡ is underneath, opened All Windows")
        XCTAssertTrue(name.exists, "the sheet is still there")
        shoot(app, "covered-02-after-hold")
    }

    /// The pull waits on a touch that starts on the bar; a tap on the bar's buttons must still be
    /// a tap, at once.
    func testTappingTheBoltStillOpensActive() throws {
        let app = launch()
        let bolt = app.buttons["active-connections-bolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 20))
        bolt.tap()
        let active = app.descendants(matching: .any).matching(identifier: "active-connections").firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 5), "a tap on the ⚡ did not open Active")
        XCTAssertFalse(pane(app).exists, "a tap is not a hold")
        shoot(app, "tap-01-active")
    }

    /// The owner (2026-10-14): "i didnt see a preview". A terminal left for the library keeps a
    /// picture, and All Windows shows it. Judged by the screenshot; the card must at least be there.
    func testATerminalLeftShowsItsPicture() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "terminal"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let bolt = app.buttons["active-connections-bolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 30), "the demo terminal did not open")
        sleep(2)
        shoot(app, "left-01-terminal")
        // On screen first: All Windows over the terminal itself.
        bolt.press(forDuration: 1.0)
        XCTAssertTrue(pane(app).waitForExistence(timeout: 5))
        shoot(app, "left-02-over-terminal")
        app.buttons["all-windows-done"].firstMatch.tap()
        XCTAssertTrue(pane(app).waitForNonExistence(timeout: 5))
        // Then left: the ⚡'s tap goes to Active, and All Windows is pulled down from its top bar.
        bolt.tap()
        sleep(2)
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)))
        XCTAssertTrue(pane(app).waitForExistence(timeout: 5), "a pull over Active did not open All Windows")
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'all-windows-card-'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the terminal left has no card")
        shoot(app, "left-03-card-from-library")
    }

    /// The owner (2026-10-14): "It should also take a 'toss' to close it… a quick flip". A short,
    /// fast flick up on the pane's bottom edge closes it; a slow push far enough does too.
    func testTossingOrPushingThePaneUpClosesIt() throws {
        let app = launch()
        let bolt = app.buttons["active-connections-bolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 20))
        let grabber = app.descendants(matching: .any).matching(identifier: "all-windows-grabber").firstMatch

        bolt.press(forDuration: 1.0)
        XCTAssertTrue(pane(app).waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))
        let edge = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        edge.press(forDuration: 0.02, thenDragTo: edge.withOffset(CGVector(dx: 0, dy: -70)),
                   withVelocity: 1600, thenHoldForDuration: 0)
        XCTAssertTrue(pane(app).waitForNonExistence(timeout: 5), "a toss did not close it")

        bolt.press(forDuration: 1.0)
        XCTAssertTrue(pane(app).waitForExistence(timeout: 5))
        sleep(1)
        shoot(app, "push-01-open")
        let edge2 = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        edge2.press(forDuration: 0.05, thenDragTo: edge2.withOffset(CGVector(dx: 0, dy: -500)),
                    withVelocity: 250, thenHoldForDuration: 0.3)
        XCTAssertTrue(pane(app).waitForNonExistence(timeout: 5), "a push far enough did not close it")
    }
}
#endif
