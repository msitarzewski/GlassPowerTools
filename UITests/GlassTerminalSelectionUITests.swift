//
//  GlassTerminalSelectionUITests.swift
//  GlassPowerToolsUITests
//
//  Selection and the link menu on Vision Pro (the owner, 2026-10-15: "the vision pro needs the data
//  detector and selection work … I have to triple pinch or click with the trackpad to get it to
//  select at all"). Driven on the visionOS simulator from `--demo-open terminal-links`: a terminal
//  that connects to nothing and shows one long address on the rows around its middle.
//
//  What the simulator's runner can't drive is the owner's to check on the headset: it pressed at
//  an element's middle whatever point it was given, a hold on the `terminal-paths` demo reached
//  the terminal in one run of three, and a held SwiftUI menu button (the +, the layout toggle) came
//  out as a pinch. The path menu's contents are unit-tested (`TerminalLinkLookupTests`).
//

#if os(visionOS)
import XCTest

@MainActor
final class GlassTerminalSelectionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    /// `terminal-links` fills the screen with one long address, `terminal-paths` with a log path.
    private func launch(_ surface: String = "terminal-links") {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", surface]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        // The demo's output drawn and the terminal's gestures installed before any is made.
        XCTAssertTrue(terminal.waitForExistence(timeout: 40), "no terminal")
        sleep(3)
    }

    private var terminal: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Terminal")).firstMatch
    }

    /// The terminal while it has a selection (set in UI-testing runs only, as the highlight can't be
    /// read): `terminal-selection-active-<characters selected>`.
    private var selected: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-selection-active")).firstMatch
    }

    /// How many characters are selected now; nil without a selection.
    private var selectedCount: Int? {
        guard selected.exists else { return nil }
        return Int(selected.identifier.split(separator: "-").last ?? "")
    }

    /// The terminal's middle: the visionOS simulator's runner holds and taps an element there,
    /// whatever point within it is asked for (the hold's own log: row 19 of 41, column 64).
    private var middle: XCUICoordinate {
        // Asked as an offset from the corner, the way the run that reached the hold asked it; the
        // normalized middle reached none of the terminal's gestures.
        terminal.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 24, dy: 9))
    }

    private func attachTree(_ name: String) {
        // Into the log too: what the screen offered, for reading without the result bundle.
        let lines = app.debugDescription.split(separator: "\n")
            .filter { $0.contains("Button") || $0.contains("MenuItem") || $0.contains("Menu") || $0.contains("Terminal") }
        print("TREE \(name):\n" + lines.prefix(60).joined(separator: "\n"))
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// A menu's item by its title — never a tab or a button of the window that shares it ("alpha"
    /// is the terminal's tab too).
    private func menuItem(_ title: String) -> XCUIElement {
        app.menuItems.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    func testHoldingAnAddressOffersItsActions() {
        launch()
        XCTAssertTrue(terminal.waitForExistence(timeout: 40), "no terminal")
        middle.press(forDuration: 1.0)
        let found = menuItem("Copy Link").waitForExistence(timeout: 5)
        if !found { attachTree("after holding the address") }
        XCTAssertTrue(found, "holding an address offered no Copy Link")
    }

    /// The owner, 2026-10-15: "selecting text is still broken wholly in the terminal in visionOS with
    /// tmux". SwiftTerm dropped a selection at every write while a program had the mouse, and tmux
    /// writes all the time. `terminal-tmux` redraws a status line every 0.4 s with the mouse asked for.
    func testAWordSelectedInTmuxStaysThroughItsRedraws() {
        launch("terminal-tmux")
        middle.doubleTap()
        XCTAssertTrue(menuItem("Copy").waitForExistence(timeout: 5), "a double pinch offered no Copy")
        sleep(2)
        XCTAssertTrue(selected.exists, "the word's selection went at tmux's next redraw")
    }

    /// With tmux's mouse on, a pinch went to tmux as a click and the selection stayed; it clears it.
    func testAPinchClearsASelectionInTmux() {
        launch("terminal-tmux")
        middle.doubleTap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5), "a double pinch selected nothing")
        sleep(2)
        middle.tap()
        XCTAssertTrue(selected.waitForNonExistence(timeout: 5), "a pinch left the selection, sent to tmux as a click")
    }

    /// The owner, 2026-10-15: "Now I can't scroll at all in visionpro". tmux 3.8 turns its mouse on
    /// with no config, and a pinch-drag went to it as a drag, which selects in tmux's copy mode.
    /// The demo answers the mouse wheel on its status line, as a program with the mouse would see it.
    func testAPinchDragScrollsAProgramThatHasTheMouse() {
        launch("terminal-tmux")
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: 180)))
        let answered = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value CONTAINS %@", "[wheel up]")).firstMatch
        let reached = answered.waitForExistence(timeout: 5)
        if !reached { attachTree("after a pinch-drag in tmux") }
        XCTAssertTrue(reached, "the drag didn't reach the program as its wheel")
        XCTAssertFalse(selected.exists, "the drag selected")
    }

    /// Apple's text: pinch and hold, and "the word you tap is highlighted" (Apple Vision Pro User
    /// Guide). It selected one character, which hardly showed (the owner, 2026-10-16: "text
    /// selection in vision pro is still not working"). The demo's middle is the word "screen".
    func testAHoldSelectsTheWordHeld() {
        launch("terminal-tmux")
        middle.press(forDuration: 1.0)
        XCTAssertTrue(selected.waitForExistence(timeout: 5), "a hold selected nothing")
        XCTAssertEqual(selectedCount, 6, "a hold selects the word held, \"screen\"")
    }

    /// Apple's text: pinch and drag either end of a selection to change it, with no hold first. It
    /// scrolled, and the scroll took the selection away.
    func testDraggingAnEndOfTheSelectionMovesIt() {
        launch("terminal-tmux")
        middle.doubleTap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5), "a double pinch selected nothing")
        XCTAssertEqual(selectedCount, 6, "the word \"screen\"")
        sleep(1)
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 160, dy: 0)))
        sleep(1)
        let count = selectedCount ?? 0
        if count <= 6 { attachTree("after dragging the selection's end") }
        XCTAssertGreaterThan(count, 6, "dragging the selection's end did not move it")
    }

    /// A hold whose hand moves a little before it counts: the drag tmux is sent when it has the mouse
    /// waits for the hold, as scrolling does, rather than taking the pinch into tmux's copy mode.
    func testAHoldThatDriftsSelectsInTmux() {
        launch("terminal-tmux")
        middle.press(forDuration: 0.15, thenDragTo: middle.withOffset(CGVector(dx: 24, dy: 0)),
                     withVelocity: 40, thenHoldForDuration: 1.0)
        sleep(2)
        if !selected.exists { attachTree("after a drifting hold in tmux") }
        XCTAssertTrue(selected.exists, "a hold that drifted selected nothing")
    }

    func testAPinchTwiceSelectsAWordAndOffersCopy() {
        launch()
        XCTAssertTrue(terminal.waitForExistence(timeout: 40), "no terminal")
        middle.doubleTap()
        let found = menuItem("Copy").waitForExistence(timeout: 5)
        if !found { attachTree("after a double pinch") }
        XCTAssertTrue(found, "a double pinch offered no Copy")
    }
}
#endif
