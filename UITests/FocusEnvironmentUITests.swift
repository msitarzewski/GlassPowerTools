//
//  FocusEnvironmentUITests.swift
//  GlassPowerToolsUITests
//
//  Focus Mode's environments on Vision Pro (2026-10-26): the library in Terminal Settings ▸ All
//  Terminals, its built-ins listed with the room dimmed chosen, a choice there marked, and This
//  Window following it until the window chooses its own; Open Immersed, off at first; Try Out fitting
//  a room and keeping its fit. Driven from `--demo-open`, which connects to nothing. What an
//  environment looks like is seen from outside, with `--demo-focus <environment>` (the simulator
//  can't photograph from inside a test).
//

#if os(visionOS)
import XCTest

@MainActor
final class FocusEnvironmentUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func launch(_ surface: String, _ more: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", surface] + more
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scrolls the settings, on (or `back`), until `target` can be pinched.
    private func reveal(_ target: XCUIElement, back: Bool = false) {
        // The settings' list; the app itself can't be swiped on visionOS ("invalid scene ID").
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        for _ in 0..<8 where !(target.exists && target.isHittable) {
            if back { list.swipeDown() } else { list.swipeUp() }
        }
    }

    func testTheLibraryChoosesForEveryWindowAndThisWindowFollows() {
        launch("terminal-settings", ["--demo-settings-tab", "terminal"])
        let dimmed = element("focus-environment-builtin.dimmed")
        let night = element("focus-environment-builtin.nightSky")
        XCTAssertTrue(app.buttons["All Terminals"].waitForExistence(timeout: 40), "Terminal Settings didn't open")
        reveal(night)
        XCTAssertTrue(night.waitForExistence(timeout: 10), "the library isn't in All Terminals")
        for name in ["dimmed", "nightSky", "dusk", "grid", "studio"] {
            XCTAssertTrue(element("focus-environment-builtin.\(name)").exists, "\(name) isn't in the library")
        }
        XCTAssertTrue(dimmed.isSelected, "the room, dimmed, should be chosen to begin with")
        let add = element("focus-environment-add")
        reveal(add)
        XCTAssertTrue(add.exists, "Add Environment… is missing")
        let immersed = element("focus-environment-opens-immersed")
        reveal(immersed)
        XCTAssertTrue(immersed.exists, "Open Immersed is missing")
        XCTAssertEqual(immersed.value as? String, "0", "Open Immersed should start off, as Focus Mode always opened")
        immersed.tap()
        XCTAssertEqual(immersed.value as? String, "1", "Open Immersed didn't turn on")
        // Room Sound (2026-10-27): how loud a living room's own sounds are, 70% to begin with.
        let sound = app.sliders["focus-environment-sound"].firstMatch
        reveal(sound)
        XCTAssertTrue(sound.exists, "Room Sound is missing")
        XCTAssertEqual(sound.value as? String, "70%", "Room Sound should start at 70%")
        reveal(night, back: true)

        night.tap()
        XCTAssertTrue(NSPredicate(format: "isSelected == true").evaluate(with: night) ||
                      XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: night)],
                                     timeout: 5) == .completed, "Night Sky wasn't marked")
        XCTAssertFalse(dimmed.isSelected, "two environments are marked")

        // This Window follows All Terminals' choice.
        app.buttons["This Window"].tap()
        let picker = element("terminal-window-focus-environment")
        reveal(picker)
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "This Window has no Focus Mode environment")
        let shown = "\(picker.label) \(picker.value as? String ?? "")"
        XCTAssertTrue(shown.contains("Night Sky"), "This Window shows \(shown), not All Terminals' Night Sky")
    }

    /// Try Out (the owner, 2026-10-26: a "try out" room with sliders for scale): a 3D room opened all
    /// the way round with a window to fit it. Saying what its numbers are in changes its size at once,
    /// and Done keeps the fit beside the file for the next time. The simulator's room is made by
    /// `--demo-environment-room`, 6.1 m across as its file says. Nothing can pinch its floor here, so
    /// moving about inside is seen in captures (`--demo-teleport`), not tested.
    func testTryOutFitsARoomAndKeepsTheFit() {
        let room = ["--demo-environment-room", "--demo-try-out", "file:Test Room.reality", "-blinkingCursor", "NO"]
        launch("terminal", room)
        XCTAssertTrue(element("focus-fit-size").waitForExistence(timeout: 60), "Try Out's window didn't open")
        // A fit left by an earlier run that stopped part way.
        if said(by: element("focus-fit-size"), "6.1 m wide", within: 20) == false {
            element("focus-fit-reset").tap()
        }
        XCTAssertTrue(said(by: element("focus-fit-size"), "6.1 m wide, 3.0 m tall, 6.1 m deep", within: 20),
                      "the room's own size: \(words(element("focus-fit-size")))")

        element("focus-fit-units").tap()
        let centimetres = app.buttons["Centimetres"].firstMatch
        XCTAssertTrue(centimetres.waitForExistence(timeout: 10), "the units aren't offered")
        centimetres.tap()
        XCTAssertTrue(said(by: element("focus-fit-size"), "6 cm wide", within: 10),
                      "in centimetres it should be a hundredth the size: \(words(element("focus-fit-size")))")
        element("focus-fit-done").tap()
        XCTAssertTrue(element("focus-fit-size").waitForNonExistence(timeout: 15), "Done didn't close Try Out")

        app.terminate()
        launch("terminal", room)
        XCTAssertTrue(element("focus-fit-size").waitForExistence(timeout: 60), "Try Out's window didn't open again")
        XCTAssertTrue(said(by: element("focus-fit-size"), "6 cm wide", within: 20),
                      "the fit wasn't kept: \(words(element("focus-fit-size")))")
        // Back to the file's own, so nothing is left for the next run.
        element("focus-fit-reset").tap()
        XCTAssertTrue(said(by: element("focus-fit-size"), "6.1 m wide", within: 10))
        element("focus-fit-done").tap()
    }

    private func words(_ element: XCUIElement) -> String {
        element.exists ? "\(element.label) \(element.value as? String ?? "")" : "(gone)"
    }

    /// Whether an element's label or value says `text` within `seconds`.
    private func said(by element: XCUIElement, _ text: String, within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if words(element).contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return false
    }
}
#endif
