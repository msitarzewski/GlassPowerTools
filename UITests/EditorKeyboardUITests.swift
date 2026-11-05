import XCTest

/// The editor with a keyboard on iPad, as TextEdit is used on a Mac (the owner, 2026-11-03: "making sure that all of
/// the expected text editor functions work in the... Editor. Like, for example, UNDO! ... like say TextEdit"; "go ahead
/// with iPad and Vision Pro"). Real key presses, through the system: ⌘Z takes typing back and ⇧⌘Z brings it back,
/// ⌘E makes the selection what to find, ⌥⌘F opens the find bar for replacing. Run on the iPad and Vision Pro simulators.
@MainActor
final class EditorKeyboardUITests: XCTestCase {
    func testUndoAndTheFindKeysWithAKeyboard() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10#Production:ssh+database",
                                "--demo-open", "editor", "--demo-keyboard"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 30), "the editor's text is not on screen")
        text.tap()
        // The caret to the very start, then a word typed there.
        text.typeKey(.upArrow, modifierFlags: .command)
        text.typeText("AUDIT")
        XCTAssertTrue(value(of: text).hasPrefix("AUDIT"), "typed at the start")

        // ⌘Z: the editor's undo, through the system's own key.
        text.typeKey(XCUIKeyboardKey(rawValue: "z"), modifierFlags: .command)
        XCTAssertFalse(value(of: text).hasPrefix("AUDIT"), "⌘Z took the typing back")
        text.typeKey(XCUIKeyboardKey(rawValue: "z"), modifierFlags: [.command, .shift])
        XCTAssertTrue(value(of: text).hasPrefix("AUDIT"), "⇧⌘Z brought it back")

        // "AUDIT" selected, then ⌘E and ⌥⌘F: the find bar opens with it as what to find.
        text.typeKey(.upArrow, modifierFlags: .command)
        for _ in 0..<5 { text.typeKey(.rightArrow, modifierFlags: .shift) }
        text.typeKey(XCUIKeyboardKey(rawValue: "e"), modifierFlags: .command)
        text.typeKey(XCUIKeyboardKey(rawValue: "f"), modifierFlags: [.command, .option])
        let find = app.textFields["editor-find-field"].firstMatch
        XCTAssertTrue(find.waitForExistence(timeout: 5), "⌥⌘F opened the find bar")
        XCTAssertEqual(find.value as? String, "AUDIT", "⌘E made the selection what to find")
        XCTAssertTrue(app.textFields["editor-replace-field"].firstMatch.exists, "with its Replace field")
    }

    private func value(of element: XCUIElement) -> String { element.value as? String ?? "" }
}
