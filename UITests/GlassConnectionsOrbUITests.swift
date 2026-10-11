//
//  GlassConnectionsOrbUITests.swift
//  GlassPowerToolsUITests
//
//  The headset's Connections window becoming its own orb when idle, and coming back as it was
//  (W29, W39). Driven on the visionOS simulator with the idle time cut to seconds
//  (`--demo-idle-seconds`, DEBUG and `--ui-testing` only). `--demo-open orb-later` opens a
//  terminal 20 s after launch (`orb-later-desktop`, a remote desktop), so Connections is not the
//  app's only window; each test uses Connections before it arrives, because it opens in front and
//  the runner's taps reach only the window in front.
//
//  Since W39 the orb is the Connections window itself, made small, not a second window pushed
//  over it. Each Connections window says what it is, how big its scene is and which window it is
//  (`connections-window-state`, DEBUG), so a test can tell the orb is the same window, that
//  visionOS really made it small, and that it grows back to the size it had.
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

    /// The size the tests give Connections as it opens: not its first size (960 × 700), so growing
    /// back to "the size it had" cannot pass by growing back to the first size.
    private static let librarySize = CGSize(width: 1100, height: 780)

    /// `surface` opens the other window 20 s after launch: `orb-later` a terminal, whose
    /// Connections control is a way back; `orb-later-desktop` a remote desktop, whose ⚡ is.
    private func launch(idleSeconds: Int, surface: String = "orb-later") {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh+database|bravo@192.0.2.20:ssh",
                                "--demo-open", surface, "--demo-idle-seconds", String(idleSeconds),
                                "--demo-library-size", "\(Int(Self.librarySize.width))x\(Int(Self.librarySize.height))"]
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

    /// A terminal window's own Connections control: `openWindow.openConnections()`, as every
    /// "Open Connections" in the app is.
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

    /// Each Connections window's scene phase — `active`, `inactive` or `background` — as the window
    /// reports it in a UI-test run (`connections-scene-phase`).
    private func connectionsWindowPhases() -> [String] {
        app.descendants(matching: .any).matching(identifier: "connections-scene-phase")
            .allElementsBoundByIndex.map { ($0.value as? String) ?? "" }
    }

    /// What a Connections window says it is (`connections-window-state`): "library" or "orb", its
    /// scene's size, and which window it is.
    private struct WindowState: Equatable, CustomStringConvertible {
        let mode: String
        let size: CGSize
        let window: String

        init?(_ text: String) {
            let parts = text.split(separator: " ")
            guard parts.count == 3 else { return nil }
            let sides = parts[1].split(separator: "x").compactMap { Double($0) }
            guard sides.count == 2 else { return nil }
            mode = String(parts[0])
            size = CGSize(width: sides[0], height: sides[1])
            window = String(parts[2])
        }

        var description: String { "\(mode) \(Int(size.width))x\(Int(size.height)) \(window)" }

        func isAbout(_ other: CGSize) -> Bool {
            abs(size.width - other.width) <= 2 && abs(size.height - other.height) <= 2
        }
    }

    private func connectionsWindowStates() -> [WindowState] {
        app.descendants(matching: .any).matching(identifier: "connections-window-state")
            .allElementsBoundByIndex.compactMap { WindowState(($0.value as? String) ?? "") }
    }

    /// Waits up to `seconds` for exactly one Connections window, in the state `matches` accepts.
    @discardableResult
    private func waitForConnections(_ what: String, seconds: TimeInterval = 15,
                                    file: StaticString = #filePath, line: UInt = #line,
                                    _ matches: (WindowState) -> Bool) -> WindowState? {
        let deadline = Date().addingTimeInterval(seconds)
        var states = connectionsWindowStates()
        while !(states.count == 1 && matches(states[0])), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            states = connectionsWindowStates()
        }
        guard states.count == 1, matches(states[0]) else {
            XCTFail("Connections is not \(what): its windows say \(states)", file: file, line: line)
            return nil
        }
        return states[0]
    }

    /// The library, at the size the tests gave it, before anything shrinks it.
    private func connectionsAsTheLibrary(file: StaticString = #filePath, line: UInt = #line) -> WindowState? {
        waitForConnections("the library at \(Self.librarySize)", file: file, line: line) {
            $0.mode == "library" && $0.isAbout(Self.librarySize)
        }
    }

    /// The orb stands in for Connections by being it (W39): one Connections window, the same one,
    /// now the orb and made small by visionOS, with nothing of the library left to reach — not its
    /// rows, not its toolbar ornament. Asked of the window itself, because the owner's headset
    /// showed the library beside the orb while the simulator hid it (2026-10-11).
    private func assertConnectionsIsItsOrb(_ library: WindowState?, file: StaticString = #filePath, line: UInt = #line) {
        // The orb is 184 points square, in the narrowest window visionOS makes: 320 points wide.
        let orbWindow = CGSize(width: 320, height: 184)
        let state = waitForConnections("its orb", file: file, line: line) {
            $0.mode == "orb" && $0.size.width <= orbWindow.width + 2 && $0.size.height <= orbWindow.height + 2
        }
        if let library, let state {
            XCTAssertEqual(state.window, library.window, "the orb is another window, not Connections itself",
                           file: file, line: line)
        }
        // The runner lists views kept in a window whether or not anything can see them — the
        // hidden library's rows are in its tree, as a pushed-aside window's were (W34) — so it is
        // asked whether a row can be reached, not whether it is listed. The scene's size above
        // is what says the library is gone: it cannot be drawn in a window that small.
        let row = element("host-row-bravo")
        if row.exists, row.isHittable {
            attachTree("library-in-reach-beside-the-orb")
            XCTFail("a library row can still be pinched beside the orb", file: file, line: line)
        }
        XCTAssertFalse(element("connection-library-add-host").exists, "the library's toolbar stayed beside the orb",
                       file: file, line: line)
    }

    /// Back from its orb: the same window, the library again, at the size it had.
    private func assertConnectionsIsBack(_ library: WindowState?, file: StaticString = #filePath, line: UInt = #line) {
        guard let library else { return }
        waitForConnections("back at \(library)", file: file, line: line) {
            $0.mode == "library" && $0.window == library.window && $0.isAbout(library.size)
        }
    }

    private func assertOneConnectionsWindow(file: StaticString = #filePath, line: UInt = #line) {
        let one = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: bravoRows)
        XCTAssertEqual(XCTWaiter().wait(for: [one], timeout: 10), .completed,
                       "\(bravoRows.count) Connections windows", file: file, line: line)
    }

    /// While Connections is the only window it stays put; once the terminals open it becomes its
    /// own orb, small, carrying Active's count, and a pinch on the orb grows the same window back
    /// into the library, at the size it had, with bravo still selected.
    func testIdleConnectionsShrinksAndAPinchBringsItBackAsItWas() {
        launch(idleSeconds: 6)
        selectBravo()
        let library = connectionsAsTheLibrary()
        assertNoOrb(for: 12, "Connections shrank while it was the app's only window")

        waitForTerminals()
        XCTAssertTrue(orb.waitForExistence(timeout: 40), "Connections did not shrink into its orb")
        attachTree("orb-up")
        // The orb stands in for the library: nothing of it is left beside the orb (owner,
        // 2026-10-11, on the headset: "The orb always appears as it should. The All Connections
        // window never minimizes").
        assertConnectionsIsItsOrb(library)
        // A terminal is open: Active's count, said with the orb's name.
        XCTAssertNotNil(orb.label.wholeMatch(of: /Open Connections, [1-9][0-9]* active/),
                        "the orb's label carries no count: \(orb.label)")

        orb.tap()
        assertOrbGoes()
        assertConnectionsIsBack(library)
        XCTAssertTrue(bravoIsShowing(), "Connections came back without bravo selected")
        assertOneConnectionsWindow()
        attachTree("restored-by-pinch")
    }

    /// A Mac's second display has a window of its own (W30), and its ⚡ brings the one Connections
    /// window forward on Active, as the desktop's own ⚡ does. It opened a second one, which stayed
    /// beside the orb when the first shrank into it (W34; the owner, 2026-10-11, on the headset:
    /// "The icon shows as expected, but the connections window remains, too").
    func testADisplayWindowsBoltLeavesNoSecondWindowBesideTheOrb() {
        launch(idleSeconds: 30, surface: "desktop-displays")
        // The desktop's own window and its second display's, each with ⚡ beside its Input button.
        let desktops = app.windows.containing(NSPredicate(format: "elementType == %d AND label == %@",
                                                          XCUIElement.ElementType.button.rawValue, "Input"))
        let bolts = desktops.buttons.matching(identifier: "active-connections-bolt")
        let both = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: bolts)
        XCTAssertEqual(XCTWaiter().wait(for: [both], timeout: 40), .completed, "the demo's two display windows did not open")
        for (press, bolt) in bolts.allElementsBoundByIndex.enumerated() {
            bolt.tap()
            XCTAssertTrue(element("active-connections").waitForExistence(timeout: 10), "⚡ \(press + 1): no Active")
            Thread.sleep(forTimeInterval: 3)
            let phases = connectionsWindowPhases()
            XCTAssertEqual(phases.count, 1, "⚡ \(press + 1): \(phases.count) Connections windows")
        }
        attachTree("one-window-from-display-bolts")

        XCTAssertTrue(orb.waitForExistence(timeout: 60), "Connections did not shrink into its orb")
        assertConnectionsIsItsOrb(nil)
        attachTree("display-orb-up")
    }

    /// Asking for Connections from anywhere else — a terminal's own control — grows the orb back
    /// into the library as it was, rather than leaving a second window beside the first.
    func testAskingForConnectionsElsewhereBringsTheSameWindowBack() {
        launch(idleSeconds: 6)
        selectBravo()
        let library = connectionsAsTheLibrary()
        waitForTerminals()
        XCTAssertTrue(orb.waitForExistence(timeout: 40), "Connections did not shrink into its orb")
        assertConnectionsIsItsOrb(library)

        terminalsConnections.tap()
        assertOrbGoes()
        // The same window, not a second one beside it, at the size it had.
        assertConnectionsIsBack(library)
        assertOneConnectionsWindow()
        XCTAssertTrue(bravoIsShowing(), "Connections came back without bravo selected")
        attachTree("restored-from-terminal")
    }

    /// The desktop's ⚡ while the orb is up: the same window comes back, showing Active.
    func testTheBoltBringsTheSameWindowBackOnActive() {
        launch(idleSeconds: 6, surface: "orb-later-desktop")
        selectBravo()
        let library = connectionsAsTheLibrary()
        XCTAssertTrue(orb.waitForExistence(timeout: 60), "Connections did not shrink into its orb")
        assertConnectionsIsItsOrb(library)

        // The library's own ⚡ went out of sight with it; the desktop's is the one in reach.
        var bolt: XCUIElement?
        for _ in 0..<20 where bolt == nil {
            bolt = app.buttons.matching(identifier: "active-connections-bolt").allElementsBoundByIndex.first { $0.isHittable }
            if bolt == nil { Thread.sleep(forTimeInterval: 1) }
        }
        guard let bolt else { return XCTFail("no ⚡ in reach") }
        bolt.tap()
        assertOrbGoes()
        assertConnectionsIsBack(library)
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
