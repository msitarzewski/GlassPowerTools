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

    /// A living room's digital clock (2026-10-27, the handoff's third phase): the simulator's test room
    /// has a `clock_digital`, and Focus Mode puts the time and date there.
    func testARoomWithADigitalClockShowsTheTime() {
        launch("terminal", ["--demo-environment-room", "--demo-focus", "file:Test Room.reality", "--demo-focus-immersed",
                            "-blinkingCursor", "NO"])
        let clock = element("focus-room-digital-clock")
        XCTAssertTrue(clock.waitForExistence(timeout: 60), "no digital clock in the test room")
        // For the capture from outside.
        sleep(10)
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

    /// Fine Position (the owner, 2026-10-28: "How can we allow micro adjustments? Right now it's
    /// almost impossible to get the right position as it relates to the desk surface"): from the
    /// moon's pinch-and-hold menu while Focus Mode is open, steps of 2 cm and turns of 1°, held to keep
    /// going, read back as how far the person stands from their start; the room a centimetre up or
    /// down; Keep This Spot making where they stand the start.
    func testFinePositionStepsTurnsRaisesAndKeepsTheSpot() {
        launch("terminal", ["--demo-environment-room", "--demo-focus", "file:Test Room.reality", "--demo-focus-immersed",
                            "-blinkingCursor", "NO"])
        let moon = element("terminal-focus-mode")
        XCTAssertTrue(moon.waitForExistence(timeout: 30), "no moon in the terminal's bar")
        XCTAssertTrue(said(by: moon, "Exit Focus Mode", within: 30), "Focus Mode didn't open: \(words(moon))")
        moon.press(forDuration: 1.5)
        let fine = app.buttons["Fine Position…"].firstMatch
        XCTAssertTrue(fine.waitForExistence(timeout: 10), "the moon's menu has no Fine Position")
        fine.tap()

        let from = element("focus-nudge-from-start")
        let keep = element("focus-nudge-keep")
        XCTAssertTrue(from.waitForExistence(timeout: 30), "Fine Position didn't open")
        // Where the room starts the person depends on whether their head was tracked yet as it
        // opened, so the steps are counted from a spot kept first.
        XCTAssertTrue(keep.wait(for: \.isEnabled, toEqual: true, timeout: 60), "the room never opened")
        keep.tap()
        XCTAssertTrue(said(by: from, "Where you start", within: 10), "Keep This Spot didn't make it the start: \(words(from))")
        for _ in 0..<3 { element("focus-nudge-forward").tap() }
        XCTAssertTrue(said(by: from, "6 cm ahead", within: 10), words(from))
        for _ in 0..<2 { element("focus-nudge-right").tap() }
        XCTAssertTrue(said(by: from, "6 cm ahead, 4 cm right", within: 10), words(from))
        element("focus-nudge-turn-left").tap()
        XCTAssertTrue(said(by: from, "6 cm ahead, 4 cm right, turned 1° left", within: 10), words(from))
        // Held, it keeps going.
        element("focus-nudge-forward").press(forDuration: 2)
        let ahead = centimetres(ahead: words(from))
        XCTAssertGreaterThan(ahead ?? 0, 10, "holding Step Forward didn't keep stepping: \(words(from))")

        keep.tap()
        XCTAssertTrue(said(by: from, "Where you start", within: 10), "kept again: \(words(from))")

        // The room's height, from wherever an earlier run left it, and back.
        let height = element("focus-nudge-height")
        guard let before = raised(height) else { return XCTFail("the room's height reads \(words(height))") }
        element("focus-nudge-raise").tap()
        element("focus-nudge-raise").tap()
        XCTAssertTrue(waitFor(height, raisedBy: before + 2), "two raises: \(words(height))")
        element("focus-nudge-lower").tap()
        XCTAssertTrue(waitFor(height, raisedBy: before + 1), "then a lowering: \(words(height))")
        element("focus-nudge-lower").tap()
        XCTAssertTrue(waitFor(height, raisedBy: before), words(height))
        // Long enough for the height to be kept.
        sleep(2)
    }

    /// A room whose lowest point isn't its floor (the loft's sky reaches 6 km below it, Rain Garden's
    /// 400 m): a pinch on its floor lands, measured from the floor the person stands on. Nothing can
    /// pinch here, so `--demo-teleport` stands in for one, and Fine Position reads back where it went.
    func testAFloorUnderASkyIsLandedOn() {
        launch("terminal", ["--demo-environment-room", "--demo-room-sky", "--demo-focus", "file:Test Room.reality",
                            "--demo-focus-immersed", "--demo-fine-position", "--demo-teleport", "0,0,-1.5,0",
                            "-blinkingCursor", "NO"])
        let from = element("focus-nudge-from-start")
        XCTAssertTrue(from.waitForExistence(timeout: 60), "Fine Position didn't open")
        XCTAssertTrue(said(by: from, "1.5 m ahead", within: 60), "the floor ahead wasn't landed on: \(words(from))")
    }

    /// "6 cm ahead" → 6, "1.2 m ahead" → 120.
    private func centimetres(ahead text: String) -> Int? {
        if let match = text.firstMatch(of: #/(\d+) cm ahead/#) { return Int(match.1) }
        if let match = text.firstMatch(of: #/(\d+\.\d) m ahead/#) { return Double(match.1).map { Int(($0 * 100).rounded()) } }
        return nil
    }

    /// "Raised 3 cm" → 3, "Lowered 2 cm" → −2, "Standing on the floor" → 0.
    private func raised(_ element: XCUIElement) -> Int? {
        let text = words(element)
        if text.contains("Standing on the floor") { return 0 }
        guard let match = text.firstMatch(of: #/(Raised|Lowered) (\d+) cm/#), let amount = Int(match.2) else { return nil }
        return match.1 == "Raised" ? amount : -amount
    }

    private func waitFor(_ element: XCUIElement, raisedBy centimetres: Int) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if raised(element) == centimetres { return true }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return false
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
