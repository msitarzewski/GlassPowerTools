//
//  GlassTerminalOrnamentUITests.swift
//  GlassPowerToolsUITests
//
//  A Vision Pro terminal's controls are Apple's toolbar ornament (W31), and a window holds every
//  one of its terminals at once — the hidden ones transparent — so only the terminal in front may
//  put controls in it, or the bar would carry every tab's. Driven on the visionOS simulator from
//  `--demo-open terminal-tabs` (one window, two terminals as its tabs, the first in front) and
//  `terminal-grid` (the same in the grid), which connect to nothing.
//
//  The visionOS simulator cannot photograph from inside a test (rule 11): captures are taken from
//  outside with `Tools/Screenshots/shoot.sh`.
//

#if os(visionOS)
import XCTest

@MainActor
final class GlassTerminalOrnamentUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func launch(_ surface: String) {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", surface]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    private func elements(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    private func attachTree(_ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// The terminal's own Connections control, found as `GlassConnectionsOrbUITests` finds it.
    private var terminalsConnections: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "server.rack", "Connections"))
    }

    /// Two terminals in one window, one bar: each control once, every one still reachable by the
    /// name and identifier it had in the hand-drawn bar.
    func testOnlyTheTerminalInFrontPutsControlsInTheBar() {
        launch("terminal-tabs")
        XCTAssertTrue(elements("terminal-footer-new-tab").firstMatch.waitForExistence(timeout: 40),
                      "the terminal's bar did not appear")
        attachTree("tabs")
        XCTAssertEqual(elements("terminal-footer-new-tab").count, 1, "the bar holds more than one terminal's controls")
        XCTAssertEqual(terminalsConnections.count, 1, "the bar holds more than one terminal's controls")
        XCTAssertEqual(elements("terminal-font-size").count, 1)
        XCTAssertEqual(elements("terminal-open-folder-here").count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Tools menu")).count, 1,
                       "the bar should hold one tools menu")
        // Two terminals, so the presentation picker is in the bar too.
        XCTAssertTrue(elements("vision-terminal-presentation").firstMatch.exists, "the Tabs/Grid/Carousel picker is missing")
        // The grid's own controls are not.
        XCTAssertFalse(app.buttons["Open Terminal"].exists, "the grid's bar shows over a terminal")
    }

    /// Scale Text (D75): in the bar once, for the terminal in front, and it switches the window
    /// between Scale and Resize. Resizing the window is past the simulator's runner; the headset
    /// shows the text following it.
    func testScaleTextIsInTheBarAndSwitchesTheWindow() {
        launch("terminal-tabs")
        let scale = elements("terminal-scale-text").firstMatch
        XCTAssertTrue(scale.waitForExistence(timeout: 40), "Scale Text is not in the bar")
        attachTree("scale")
        XCTAssertEqual(elements("terminal-scale-text").count, 1, "the bar holds more than one terminal's Scale Text")
        XCTAssertEqual(scale.value as? String, "Off", "a window resizes its rows and columns until asked")
        scale.tap()
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "Scaling"), evaluatedWith: scale)], timeout: 5)
        scale.tap()
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "Off"), evaluatedWith: scale)], timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Terminal"))
                        .firstMatch.exists, "the terminal is still there")
    }

    /// Open Folder Here keeps its pinch-and-hold menu in the toolbar: the same folder in Files.
    func testOpenFolderHereStillOffersItsMenu() {
        launch("terminal-tabs")
        let folder = elements("terminal-open-folder-here").firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 40), "Open Folder Here is not in the bar")
        folder.press(forDuration: 1.5)
        let openInFiles = app.buttons["Open in Files"]
        let appeared = openInFiles.waitForExistence(timeout: 10)
        attachTree("folder-menu")
        XCTAssertTrue(appeared, "pinch and hold on Open Folder Here showed no menu")
    }

    /// In the grid no terminal is in front: the bar is the grid's alone, and Open Terminal brings
    /// the terminal's back in its place.
    func testTheGridHasItsOwnBarAndNoTerminals() {
        launch("terminal-grid")
        let openTerminal = app.buttons["Open Terminal"]
        XCTAssertTrue(openTerminal.waitForExistence(timeout: 40), "the grid's bar did not appear")
        attachTree("grid")
        XCTAssertEqual(elements("terminal-footer-new-tab").count, 0, "a terminal's controls show in the grid")
        XCTAssertEqual(terminalsConnections.count, 0, "a terminal's controls show in the grid")

        openTerminal.tap()
        XCTAssertTrue(elements("terminal-footer-new-tab").firstMatch.waitForExistence(timeout: 10),
                      "Open Terminal did not bring the terminal's bar back")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: openTerminal)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "the grid's bar stayed over the terminal")
        XCTAssertEqual(elements("terminal-footer-new-tab").count, 1)
    }
}
#endif
