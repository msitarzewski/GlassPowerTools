//
//  DuoDeckUITests.swift
//  GlassPowerToolsUITests
//
//  The deck below an iPhone Duo's fold (D93): stood like a small laptop, a remote desktop sits above
//  the fold and its trackpad below. Run on the Duo simulator stood like a laptop (Device Hub:
//  Partially Open, then Rotate Right, with Simulate Hardware Keyboard off); anywhere else there is
//  no fold, and the tests skip. Driven from `--demo-open desktop`, which connects to nothing.
//

#if os(iOS)
import XCTest

private extension XCUIElement {
    func waitForLabel(_ label: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

@MainActor
final class DuoDeckUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launchDesktop() throws -> XCUIElement {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--demo-open", "desktop", "--demo-keyboard"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let pad = element("desktop-fold-trackpad")
        guard pad.waitForExistence(timeout: 30) else {
            throw XCTSkip("needs an iPhone Duo stood like a laptop")
        }
        return pad
    }

    /// A finger on the trackpad moves the remote pointer: the pad says where it is.
    func testTheTrackpadMovesTheRemotePointer() throws {
        let pad = try launchDesktop()
        let before = pad.value as? String
        let start = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6)))
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? ""), object: pad)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 10), .completed,
                       "the pointer stayed at \(before ?? "nowhere")")
    }

    /// A terminal's fresh fold brings the keyboard up, and the deck's switch puts it away and back.
    func testATerminalsFoldBringsUpTheKeyboard() throws {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", "btop", "--demo-keyboard"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let toggle = element("glass-fold-deck-keyboard")
        guard toggle.waitForExistence(timeout: 30) else { throw XCTSkip("needs an iPhone Duo stood like a laptop") }
        let keys = app.keyboards.firstMatch
        XCTAssertTrue(keys.waitForExistence(timeout: 10), "the fold brought up the keyboard")
        toggle.tap()
        XCTAssertTrue(keys.waitForNonExistence(timeout: 10), "the switch put the keyboard away")
        toggle.tap()
        XCTAssertTrue(keys.waitForExistence(timeout: 10), "and brought it back")
    }

    /// The editor's strip types at the cursor: a key a phone's keyboard hides, one tap.
    func testTheEditorsStripTypesAtTheCursor() throws {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", "editor", "--demo-keyboard"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let strip = element("editor-fold-strip")
        guard strip.waitForExistence(timeout: 30) else { throw XCTSkip("needs an iPhone Duo stood like a laptop") }
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), "the document's text")
        // The project's files open over the left of the window on the unfolded Duo, over the strip's
        // first keys: a tap in the text, right of them, closes them and puts the cursor there.
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.3)).tap()
        sleep(1)
        let before = (text.value as? String) ?? ""
        let brace = strip.buttons["Type {"].firstMatch
        XCTAssertTrue(brace.waitForExistence(timeout: 5), "the strip's { key")
        brace.tap()
        let typed = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                ((object as? XCUIElement)?.value as? String).map { $0.filter { $0 == "{" }.count > before.filter { $0 == "{" }.count } ?? false
            }, object: text)
        XCTAssertEqual(XCTWaiter().wait(for: [typed], timeout: 10), .completed, "the { reached the document")
    }

    /// A database's strip types into its SQL: a key a phone's keyboard hides, one tap.
    func testTheDatabasesStripTypesIntoTheQuery() throws {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh+database",
                                "--demo-open", "database", "--demo-keyboard"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let strip = element("db-fold-strip")
        guard strip.waitForExistence(timeout: 30) else { throw XCTSkip("needs an iPhone Duo stood like a laptop") }
        let query = element("db-query-editor")
        XCTAssertTrue(query.waitForExistence(timeout: 10), "the query's text")
        let before = (query.value as? String) ?? ""
        let star = strip.buttons["Type *"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5), "the strip's * key")
        star.tap()
        let typed = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                ((object as? XCUIElement)?.value as? String).map { $0.filter { $0 == "*" }.count > before.filter { $0 == "*" }.count } ?? false
            }, object: query)
        XCTAssertEqual(XCTWaiter().wait(for: [typed], timeout: 10), .completed, "the * reached the query")
    }

    /// Below the fold, the desktop's own keys and the trackpad at once; a shortcut button, held,
    /// takes the next key typed with what is armed: Control, then T, makes it Ctrl+T.
    func testAShortcutRecordsFromTheKeys() throws {
        let pad = try launchDesktop()
        let keys = element("desktop-fold-keys")
        XCTAssertTrue(keys.waitForExistence(timeout: 10), "the desktop's keys")
        XCTAssertTrue(pad.exists, "and the trackpad, at once")
        let shortcut = element("desktop-fold-shortcut-0")
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5), "the first shortcut")
        XCTAssertEqual(shortcut.label, "Ctrl+C", "Copy, on a PC")
        shortcut.press(forDuration: 1.0)
        XCTAssertTrue(shortcut.waitForLabel("Recording shortcut 1", timeout: 5), "held, it records")
        element("desktop-fold-key-control").tap()
        element("desktop-fold-key-t").tap()
        XCTAssertTrue(shortcut.waitForLabel("Ctrl+T", timeout: 5), "Control and T, recorded (\(shortcut.label))")
    }

    /// The deck's switch trades the trackpad for the keyboard and back.
    func testTheSwitchTradesTheTrackpadForTheKeyboard() throws {
        let pad = try launchDesktop()
        let toggle = element("glass-fold-deck-keyboard")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the deck's switch")
        toggle.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "the keyboard came up")
        XCTAssertTrue(pad.waitForNonExistence(timeout: 10), "the trackpad gave the keyboard its room")
        toggle.tap()
        XCTAssertTrue(pad.waitForExistence(timeout: 10), "the trackpad came back")
    }
}
#endif
