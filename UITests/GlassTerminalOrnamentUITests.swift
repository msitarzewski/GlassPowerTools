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

    private func launch(_ surface: String, _ more: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", surface] + more
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

    /// The terminal's own ⚡ (2026-10-22; it was a Connections control), as `GlassConnectionsOrbUITests` finds it.
    private var terminalsConnections: XCUIElementQuery {
        app.buttons.matching(identifier: "terminal-active-connections")
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
        // Font Size is in Tools now, where the bar had grown to eleven (2026-10-21).
        XCTAssertEqual(elements("terminal-font-size").count, 0, "Font Size is still in the bar")
        XCTAssertEqual(elements("terminal-open-folder-here").count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Tools menu")).count, 1,
                       "the bar should hold one tools menu")
        // Two terminals, so the presentation picker is in the bar too.
        XCTAssertTrue(elements("vision-terminal-presentation").firstMatch.exists, "the Tabs/Grid/Carousel picker is missing")
        // The grid's own controls are not.
        XCTAssertFalse(app.buttons["Open Terminal"].exists, "the grid's bar shows over a terminal")
    }

    /// The keys a headset's keyboard lacks (2026-10-21): Apple shows no keyboard accessory to a
    /// visionOS app, so they are a Keys menu in the bar, once, with every key the phone's
    /// accessory has and the arrows. A demo terminal is connected to nothing, so what a press sends
    /// is seen in the app's log ("Ignoring terminal input while session is not connected").
    func testKeysAreInTheBar() {
        launch("terminal-tabs")
        let keys = elements("terminal-keys").firstMatch
        XCTAssertTrue(keys.waitForExistence(timeout: 40), "Keys is not in the bar")
        let found = elements("terminal-keys").allElementsBoundByIndex.map(\.debugDescription).joined(separator: "\n")
        XCTAssertEqual(elements("terminal-keys").count, 1, "the bar holds more than one terminal's Keys:\n\(found)")
        keys.tap()
        for title in ["Escape", "Tab", "Control for Next Key", "Navigation", "Function Keys"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 10), "\(title) is not in Keys")
        }
        attachTree("keys")
        app.buttons["Escape"].tap()
        XCTAssertTrue(keys.waitForExistence(timeout: 10), "the bar is gone after a key")
        keys.tap()
        XCTAssertTrue(app.buttons["Navigation"].waitForExistence(timeout: 10))
        app.buttons["Navigation"].tap()
        for title in ["Up", "Down", "Left", "Right"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 10), "\(title) is not under Navigation")
        }
        app.buttons["Up"].tap()
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

    /// A window's tabs are its sidebar from the second terminal on (2026-10-21), as a Mac window's
    /// are: a row per terminal, which a pinch shows; none with one terminal, and none in the grid.
    /// Apple's tab bar, which held them before, is gone.
    /// "There's no context menu in the empty space in a tab sidebar in visionOS" (the owner,
    /// 2026-10-27): held below its rows, the sidebar offers what the bar's + does.
    func testTheSidebarsEmptySpaceOffersANewTerminal() {
        launch("terminal-tabs")
        // Held by the element: a hold at a point of an ornament's own space landed elsewhere (the
        // runner, 2026-10-27).
        let empty = elements("vision-terminal-sidebar-empty").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 40), "two terminals and no space below the sidebar's rows")
        XCTAssertGreaterThan(empty.frame.height, 300, "the space below the rows doesn't reach the sidebar's foot: \(empty.frame)")
        empty.press(forDuration: 1.5)
        XCTAssertTrue(app.buttons["New Terminal Tab…"].waitForExistence(timeout: 5), "no menu in the sidebar's empty space")
        // For the capture from outside.
        sleep(4)
    }

    func testTwoTerminalsHaveASidebar() {
        launch("terminal-tabs")
        let sidebar = elements("vision-terminal-sidebar").firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 40), "two terminals and no sidebar")
        attachTree("sidebar")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                                                        "vision-terminal-sidebar-row-"))
        XCTAssertEqual(rows.count, 2, "a row per terminal")
        XCTAssertEqual(app.tabBars.count, 0, "the tab bar ornament is still there")

        // A pinch on the second row shows its terminal: its row is the one selected.
        let second = rows.element(boundBy: 1)
        second.tap()
        let selected = NSPredicate(format: "isSelected == true")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: selected, evaluatedWith: second)], timeout: 5), .completed,
                       "the row pinched isn't the one shown")

        // The bar's toggle hides it and shows it again.
        let toggle = elements("vision-terminal-sidebar-toggle").firstMatch
        XCTAssertTrue(toggle.exists, "no sidebar toggle in the bar")
        toggle.tap()
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sidebar)
        XCTAssertEqual(XCTWaiter().wait(for: [hidden], timeout: 10), .completed, "the toggle didn't hide the sidebar")
        toggle.tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), "the toggle didn't show the sidebar again")

        // A pinch on Terminal View makes the window its orb (2026-10-21): the sidebar goes with it.
        elements("vision-terminal-presentation").firstMatch.tap()
        XCTAssertTrue(elements("session-orb").firstMatch.waitForExistence(timeout: 15), "the pinch didn't make the orb")
        XCTAssertFalse(sidebar.exists, "the sidebar stayed with the orb")
    }

    /// Font Size and the AI assistant are in Tools on the headset, not the bar (2026-10-21).
    func testFontSizeIsInTools() {
        launch("terminal-tabs")
        let tools = app.buttons.matching(NSPredicate(format: "label == %@", "Tools menu")).firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 40), "no Tools menu in the bar")
        tools.tap()
        XCTAssertTrue(app.buttons["Font Size"].firstMatch.waitForExistence(timeout: 5), "no Font Size in Tools")
    }

    /// A Mermaid diagram a program printed as text has a mark beside it, which shows it drawn
    /// (2026-10-21), in a popover over the terminal.
    func testADiagramHasAMarkThatShowsIt() {
        launch("terminal-diagram")
        let mark = elements("terminal-diagram-mark").firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 40), "no mark beside the diagram")
        XCTAssertEqual(elements("terminal-diagram-mark").count, 1, "one diagram, one mark")
        mark.tap()
        XCTAssertTrue(elements("terminal-diagram").firstMatch.waitForExistence(timeout: 10),
                      "the mark didn't show the diagram")
    }

    func testOneTerminalHasNoSidebar() {
        launch("terminal")
        XCTAssertTrue(elements("terminal-footer-new-tab").firstMatch.waitForExistence(timeout: 40),
                      "the terminal's bar did not appear")
        XCTAssertFalse(elements("vision-terminal-sidebar").firstMatch.exists, "a sidebar for one terminal")
    }

    /// Quick Look leads a held path's menu on the headset, and shows its preview over the terminal
    /// (the owner, 2026-10-22: "add Quick Look on the headset"). The demo is connected to nothing,
    /// so the preview says the file couldn't be read; a real host's is checked on the headset.
    func testQuickLookOnAHeldPath() {
        launch("terminal-path")
        let terminal = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Terminal")).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 40), "no terminal")
        sleep(2)
        // The runner holds the terminal's middle whatever point is asked for (as
        // `GlassTerminalSelectionUITests` found), so the demo prints the path all over the screen.
        terminal.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 24, dy: 9)).press(forDuration: 1.0)
        // A menu's entries are menu items to the runner, not buttons.
        let quickLook = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Quick Look")).firstMatch
        let offered = quickLook.waitForExistence(timeout: 5)
        attachTree("path-menu")
        // Quick Look is offered on a path alone, so its being there says the hold found the path.
        XCTAssertTrue(offered, "no Quick Look in the held path's menu")
        quickLook.tap()
        XCTAssertTrue(elements("terminal-path-preview").firstMatch.waitForExistence(timeout: 15), "Quick Look showed nothing")
        attachTree("path-preview")
    }

    /// The grid the terminal shows (`terminal-grid-<columns>x<rows>`, a UI-test mark).
    private var shownGrid: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-grid-")).firstMatch
    }

    /// Showing and hiding the sidebar leaves the terminal as it was (2026-10-22: "The terminal
    /// content should not move or redraw"): the sidebar stands beside the window, which keeps its
    /// size, so the grid and the terminal's place in the window stay.
    func testTheSidebarLeavesTheTerminalWhereItIs() {
        launch("terminal-tabs")
        let sidebar = elements("vision-terminal-sidebar").firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 40), "two terminals and no sidebar")
        XCTAssertTrue(shownGrid.waitForExistence(timeout: 20), "the terminal has no grid")
        sleep(3)
        let grid = shownGrid.identifier
        let frame = shownGrid.frame
        let toggle = elements("vision-terminal-sidebar-toggle").firstMatch
        XCTAssertTrue(toggle.exists, "no sidebar toggle in the bar")

        toggle.tap()
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sidebar)
        XCTAssertEqual(XCTWaiter().wait(for: [hidden], timeout: 10), .completed, "the toggle didn't hide the sidebar")
        sleep(3)
        XCTAssertEqual(shownGrid.identifier, grid, "hiding the sidebar changed the terminal's rows and columns")
        XCTAssertEqual(shownGrid.frame, frame, "hiding the sidebar moved the terminal")

        toggle.tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), "the toggle didn't show the sidebar again")
        sleep(3)
        XCTAssertEqual(shownGrid.identifier, grid, "showing the sidebar changed the terminal's rows and columns")
        XCTAssertEqual(shownGrid.frame, frame, "showing the sidebar moved the terminal")
    }
}
#endif
