//
//  GlassConnectionsOrbUITests.swift
//  GlassPowerToolsUITests
//
//  The headset's Connections window shrinking into its orb when idle, and coming back as it was
//  (W29). Driven on the visionOS simulator with the idle time cut to seconds
//  (`--demo-idle-seconds`, DEBUG and `--ui-testing` only). `--demo-open orb-later` opens a
//  terminal 20 s after launch (`orb-later-desktop`, a remote desktop), so Connections is not the
//  app's only window; each test uses Connections before it arrives, because it opens in front and
//  the runner's taps reach only the window in front.
//
//  The visionOS simulator cannot photograph from inside a test (rule 11): captures for the help
//  are taken from outside with `Tools/Screenshots/shoot.sh`.
//

#if os(visionOS)
import XCTest

@MainActor
final class GlassConnectionsOrbUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    /// `surface` opens the other window 20 s after launch: `orb-later` a terminal, whose
    /// Connections control is a way back; `orb-later-desktop` a remote desktop, whose ⚡ is.
    private func launch(idleSeconds: Int, surface: String = "orb-later") {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh+database|bravo@192.0.2.20:ssh",
                                "--demo-open", surface, "--demo-idle-seconds", String(idleSeconds)]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCTAssertTrue(element("host-row-bravo").waitForExistence(timeout: 30), "bravo is not in the library")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The orb, whatever its count says.
    private var orb: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open Connections")).firstMatch
    }

    /// A terminal window's own Connections control: `openWindow(id: "main")`, as every "Open
    /// Connections" in the app is.
    private var terminalsConnections: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "server.rack", "Connections")).firstMatch
    }

    private var bravoRows: XCUIElementQuery { app.staticTexts.matching(identifier: "host-row-bravo") }

    private func attachTree(_ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// Selects bravo and waits for its details.
    private func selectBravo(file: StaticString = #filePath, line: UInt = #line) {
        element("host-row-bravo").tap()
        XCTAssertTrue(bravoIsShowing(), "bravo's details did not show", file: file, line: line)
    }

    private func bravoIsShowing() -> Bool {
        let address = element("host-detail-address")
        guard address.waitForExistence(timeout: 10) else { return false }
        return "\(address.label) \(address.value ?? "")".contains("192.0.2.20")
    }

    private func waitForTerminals(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(terminalsConnections.waitForExistence(timeout: 40), "the demo terminals did not open",
                      file: file, line: line)
    }

    /// Asserts the orb does not appear in `seconds`, several idle intervals.
    private func assertNoOrb(for seconds: TimeInterval, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let appears = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: orb)
        XCTAssertNotEqual(XCTWaiter().wait(for: [appears], timeout: seconds), .completed, message, file: file, line: line)
    }

    private func assertOrbGoes(file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: orb)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed,
                       "the orb stayed after Connections came back", file: file, line: line)
    }

    private func assertOneConnectionsWindow(file: StaticString = #filePath, line: UInt = #line) {
        let one = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: bravoRows)
        XCTAssertEqual(XCTWaiter().wait(for: [one], timeout: 10), .completed,
                       "\(bravoRows.count) Connections windows", file: file, line: line)
    }

    /// While Connections is the only window it stays put; once the terminals open it shrinks into
    /// an orb that carries Active's count, and a pinch on the orb brings the same window back with
    /// bravo still selected.
    func testIdleConnectionsShrinksAndAPinchBringsItBackAsItWas() {
        launch(idleSeconds: 6)
        selectBravo()
        assertNoOrb(for: 12, "Connections shrank while it was the app's only window")

        waitForTerminals()
        XCTAssertTrue(orb.waitForExistence(timeout: 40), "Connections did not shrink into its orb")
        attachTree("orb-up")
        // A terminal is open: Active's count, said with the orb's name.
        XCTAssertNotNil(orb.label.wholeMatch(of: /Open Connections, [1-9][0-9]* active/),
                        "the orb's label carries no count: \(orb.label)")

        orb.tap()
        assertOrbGoes()
        XCTAssertTrue(bravoIsShowing(), "Connections came back without bravo selected")
        assertOneConnectionsWindow()
        attachTree("restored-by-pinch")
    }

    /// Asking for Connections from anywhere else — a terminal's own control — brings the window
    /// back as it was and puts the orb away, rather than leaving a second window beside the first.
    func testAskingForConnectionsElsewhereBringsTheSameWindowBack() {
        launch(idleSeconds: 6)
        selectBravo()
        waitForTerminals()
        XCTAssertTrue(orb.waitForExistence(timeout: 40), "Connections did not shrink into its orb")

        terminalsConnections.tap()
        assertOrbGoes()
        // The same window, not a second one beside it.
        assertOneConnectionsWindow()
        XCTAssertTrue(bravoIsShowing(), "Connections came back without bravo selected")
        attachTree("restored-from-terminal")
    }

    /// The desktop's ⚡ while the orb is up: the same window comes back, showing Active.
    func testTheBoltBringsTheSameWindowBackOnActive() {
        launch(idleSeconds: 6, surface: "orb-later-desktop")
        selectBravo()
        XCTAssertTrue(orb.waitForExistence(timeout: 60), "Connections did not shrink into its orb")

        // The library's own ⚡ is in the tree too, behind the orb; the desktop's is the one in reach.
        var bolt: XCUIElement?
        for _ in 0..<20 where bolt == nil {
            bolt = app.buttons.matching(identifier: "active-connections-bolt").allElementsBoundByIndex.first { $0.isHittable }
            if bolt == nil { Thread.sleep(forTimeInterval: 1) }
        }
        guard let bolt else { return XCTFail("no ⚡ in reach") }
        bolt.tap()
        assertOrbGoes()
        XCTAssertTrue(element("active-connections").waitForExistence(timeout: 10), "Connections came back without Active")
        attachTree("restored-by-bolt")
        // One window, on Active: the same one, not a second.
        let active = app.descendants(matching: .any).matching(identifier: "active-connections")
        let one = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: active)
        XCTAssertEqual(XCTWaiter().wait(for: [one], timeout: 10), .completed, "\(active.count) Connections windows on Active")
    }

    // MARK: One Connections window (W29b)

    /// With no orb up, a terminal's Connections control brings the one window forward, however
    /// often it is pressed. `openWindow(id: "main")` opened a second window every time.
    func testATerminalsConnectionsControlNeverOpensASecondWindow() {
        launch(idleSeconds: 600)
        waitForTerminals()
        for press in 1...2 {
            let control = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@",
                                                           "server.rack", "Connections"))
                .allElementsBoundByIndex.first { $0.isHittable }
            guard let control else { return XCTFail("press \(press): the terminal's Connections control is out of reach") }
            control.tap()
            Thread.sleep(forTimeInterval: 3)
            assertOneConnectionsWindow()
        }
        attachTree("one-window-from-terminal")
    }

    /// The same for a desktop's ⚡: one window, on Active.
    func testTheBoltNeverOpensASecondWindow() {
        launch(idleSeconds: 600, surface: "orb-later-desktop")
        // The desktop's ⚡, in the control bar beside its Input button — not the library's own.
        let desktopBar = app.windows.containing(NSPredicate(format: "elementType == %d AND label == %@",
                                                            XCUIElement.ElementType.button.rawValue, "Input"))
        let bolt = desktopBar.buttons.matching(identifier: "active-connections-bolt").firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 40), "the demo desktop did not open")
        for press in 1...2 {
            XCTAssertTrue(bolt.isHittable, "press \(press): the desktop's ⚡ is out of reach")
            bolt.tap()
            XCTAssertTrue(element("active-connections").waitForExistence(timeout: 10), "press \(press): no Active")
            Thread.sleep(forTimeInterval: 3)
            let active = app.descendants(matching: .any).matching(identifier: "active-connections")
            XCTAssertEqual(active.count, 1, "press \(press): \(active.count) Connections windows on Active")
            XCTAssertEqual(bravoRows.count, 0, "press \(press): a Connections window not on Active")
        }
        attachTree("one-window-from-bolt")
    }

    /// A sheet over Connections holds it at full size.
    func testASheetHoldsConnectionsOpen() {
        launch(idleSeconds: 6)
        let add = element("connection-library-add-host")
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 10), "Add Host did not open")

        waitForTerminals()
        assertNoOrb(for: 20, "Connections shrank under an open sheet")
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists, "the sheet closed by itself; the hold proved nothing")
        attachTree("sheet-held")
    }

    /// An open menu holds Connections at full size.
    func testAMenuHoldsConnectionsOpen() {
        launch(idleSeconds: 6)
        let chevron = element("host-connect-menu")
        XCTAssertTrue(chevron.waitForExistence(timeout: 10), "alpha has no service menu")
        chevron.tap()
        XCTAssertTrue(element("host-connect-menu-ssh").waitForExistence(timeout: 10), "the service menu did not open")

        waitForTerminals()
        assertNoOrb(for: 20, "Connections shrank under an open menu")
        attachTree("menu-held")
        XCTAssertTrue(element("host-connect-menu-ssh").exists, "the menu closed by itself; the hold proved nothing")
    }

    /// A row's context menu (pinch and hold) holds Connections at full size.
    func testAContextMenuHoldsConnectionsOpen() {
        launch(idleSeconds: 6)
        element("host-row-bravo").press(forDuration: 1.5)
        let favorite = app.buttons["Add Favorite"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 10), "the row's menu did not open")

        waitForTerminals()
        assertNoOrb(for: 20, "Connections shrank under an open context menu")
        attachTree("context-menu-held")
        XCTAssertTrue(favorite.exists, "the menu closed by itself; the hold proved nothing")
    }
}
#endif
