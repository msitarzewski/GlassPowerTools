//
//  GlassOrbRelaunchUITests.swift
//  GlassPowerToolsUITests
//
//  Windows come back as they were left (the owner, 2026-10-26: "let's have windows respawn in their
//  last used state. In the dock vs. open?"). Each test quits the app and launches it again under the
//  same run, whose store is kept: a terminal window on the demo's machine, whose address answers
//  nobody, its terminal in tmux so the reopen list keeps it. `--demo-reopen open` stands for the run
//  before the first; every later launch (`kept`) takes the list the one before it wrote.
//

#if os(visionOS)
import XCTest

@MainActor
final class GlassOrbRelaunchUITests: XCTestCase {
    private var app: XCUIApplication!
    private let run = UUID().uuidString

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    /// Quits the app if it runs, and launches it again under this test's run.
    private func launch(_ arguments: [String]) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", run, "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh=\(Self.demoService)"] + arguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The terminal window, open: its bar's Shrink to Orb.
    private var shrink: XCUIElement { element("session-orb-shrink") }
    private var dock: XCUIElement { element("orb-dock") }
    private var orbInDock: XCUIElement {
        dock.descendants(matching: .any).matching(identifier: "session-orb").firstMatch
    }
    /// The window standing as its orb.
    private var orb: XCUIElement { element("session-orb") }
    /// Connections' orb, in the dock: the terminal's own way to Connections is no orb.
    private var connections: XCUIElement {
        dock.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open Connections")).firstMatch
    }

    /// The list kept as the window changed, before the app is quit.
    private func letTheListBeWritten() { sleep(3) }

    private static let dockOn = ["-com.glasspowertools.orbs.inDock", "YES"]
    /// The seeded machine's terminal service, whose settings `--demo-reopen` saves
    /// (`TerminalWorkgroupsToReopen.demoServerID`).
    private static let demoService = "D0D0D0D0-0000-4000-8000-0000000000A1"
    /// The demo's machine kept, and nothing standing in for the list the last launch wrote.
    private static let kept = ["--demo-reopen", "kept"]

    func testAWindowLeftInTheDockComesBackInTheDock() {
        launch(Self.dockOn + ["--demo-reopen", "open"])
        XCTAssertTrue(shrink.waitForExistence(timeout: 60), "the terminal window did not open")
        shrink.tap()
        XCTAssertTrue(orbInDock.waitForExistence(timeout: 15), "the window did not go into the dock")
        XCTAssertTrue(shrink.waitForNonExistence(timeout: 10), "the window stayed open beside the dock")
        letTheListBeWritten()

        launch(Self.dockOn + Self.kept)
        XCTAssertTrue(orbInDock.waitForExistence(timeout: 60), "the window left in the dock did not come back in it")
        XCTAssertFalse(shrink.exists, "its window opened as well")
        // For the capture from outside.
        sleep(6)
        orbInDock.tap()
        XCTAssertTrue(shrink.waitForExistence(timeout: 15), "a pinch on its orb did not bring the window back")
        letTheListBeWritten()

        launch(Self.dockOn + Self.kept)
        XCTAssertTrue(shrink.waitForExistence(timeout: 60), "the window left open did not come back open")
        XCTAssertFalse(dock.exists, "the dock came back, with nothing left in it")
    }

    func testAWindowLeftAsItsOrbComesBackAsItsOrb() {
        launch(["--demo-reopen", "open"])
        XCTAssertTrue(shrink.waitForExistence(timeout: 60), "the terminal window did not open")
        shrink.tap()
        XCTAssertTrue(orb.waitForExistence(timeout: 10), "the window did not become its orb")
        letTheListBeWritten()

        launch(Self.kept)
        XCTAssertTrue(orb.waitForExistence(timeout: 60), "the window left as its orb did not come back as its orb")
        XCTAssertTrue(element("terminal-footer-new-tab").waitForNonExistence(timeout: 10), "its bar is beside the orb")
        XCTAssertFalse(shrink.exists, "it came back open")
        // For the capture from outside.
        sleep(6)
        orb.tap()
        XCTAssertTrue(shrink.waitForExistence(timeout: 15), "a pinch on the orb did not grow the window back")
        letTheListBeWritten()

        launch(Self.kept)
        XCTAssertTrue(shrink.waitForExistence(timeout: 60), "the window left open did not come back open")
        XCTAssertFalse(orb.exists, "it came back as its orb")
    }

    /// Connections idles into the dock only beside another window: a demo terminal's, which connects
    /// to nothing and is in no reopen list.
    private func putConnectionsInTheDock() {
        launch(Self.dockOn + ["--demo-open", "terminal", "--demo-idle-seconds", "8"])
        XCTAssertTrue(shrink.waitForExistence(timeout: 60), "the demo terminal did not open")
        XCTAssertTrue(connections.waitForExistence(timeout: 60), "Connections did not idle into the dock")
        XCTAssertTrue(element("connections-window-state").waitForNonExistence(timeout: 10),
                      "the Connections window stayed open beside the dock")
        letTheListBeWritten()
    }

    func testConnectionsLeftInTheDockGoesBackIntoIt() {
        putConnectionsInTheDock()

        // Idle after two minutes, as it is out of the box: what puts it in the dock now is the launch.
        launch(Self.dockOn)
        XCTAssertTrue(connections.waitForExistence(timeout: 60), "Connections did not go back into the dock")
        XCTAssertTrue(element("connections-window-state").waitForNonExistence(timeout: 10),
                      "the Connections window stayed open beside the dock")
        // For the capture from outside.
        sleep(6)
        connections.tap()
        XCTAssertTrue(element("connections-window-state").waitForExistence(timeout: 15),
                      "a pinch on its orb did not bring Connections back")
        letTheListBeWritten()

        launch(Self.dockOn)
        XCTAssertTrue(element("connections-window-state").waitForExistence(timeout: 30), "Connections did not open")
        sleep(10)
        XCTAssertTrue(element("connections-window-state").exists, "Connections left open went into the dock")
        XCTAssertFalse(connections.exists, "Connections left open is in the dock")
    }

    /// A window the last run left asks for something as it connects — here a password, as the demo's
    /// machine has none saved — and says so on Connections, which stays open for it rather than go
    /// back into the dock with the question on it.
    func testConnectionsLeftInTheDockStaysOpenForAQuestion() {
        putConnectionsInTheDock()

        launch(Self.dockOn + ["--demo-reopen", "open"])
        XCTAssertTrue(shrink.waitForExistence(timeout: 60), "the last run's terminal window did not open")
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 60), "the terminal's failure was not said")
        // Longer than Connections waits for the last run's windows and what they say.
        sleep(10)
        XCTAssertTrue(element("connections-window-state").exists, "Connections went into the dock with a question on it")
        XCTAssertFalse(connections.exists, "Connections is in the dock")
    }

    // MARK: The dock's shape

    /// The owner, 2026-10-26: "could we make it responsive? A user could then make it vertical with
    /// simply resizing it so." Resized taller than wide (`--demo-dock-resize`, as the runner can't
    /// drag a corner), the dock stands its orbs in a column, and opens at that size next time.
    func testTheDockResizedTallStandsInAColumnAndKeepsItsSize() {
        let terminalIntoTheDock = Self.dockOn + ["--demo-open", "terminal", "--demo-session-orb"]
        launch(terminalIntoTheDock + ["--demo-dock-resize", "420x1100"])
        XCTAssertTrue(orbInDock.waitForExistence(timeout: 60), "the terminal did not go into the dock")
        let column = expectation(for: NSPredicate(format: "value == %@", "column"), evaluatedWith: dock)
        XCTAssertEqual(XCTWaiter().wait(for: [column], timeout: 20), .completed,
                       "resized taller than wide, the dock is a \(dock.value ?? "nothing")")
        assertStacked()
        // For the capture from outside.
        sleep(6)

        launch(terminalIntoTheDock)
        XCTAssertTrue(orbInDock.waitForExistence(timeout: 60), "the terminal did not go into the dock")
        sleep(3)
        XCTAssertEqual(dock.value as? String, "column", "the dock did not open at the size it was given")
        assertStacked()
    }

    /// Connections' orb above the terminal's, not beside it.
    private func assertStacked(file: StaticString = #filePath, line: UInt = #line) {
        let first = connections.frame, second = orbInDock.frame
        XCTAssertGreaterThan(second.minY, first.minY + first.height / 2,
                             "the terminal's orb is not below Connections': \(first) \(second)", file: file, line: line)
    }
}
#endif
