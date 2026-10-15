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
