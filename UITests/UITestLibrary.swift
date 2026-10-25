//
//  UITestLibrary.swift
//  GlassPowerToolsUITests
//
//  The library's scope rows, found the same way by every suite.
//

import XCTest

extension XCUIApplication {
    /// A sidebar scope row, `glass-library-scope-<id>` (`GlassLibraryComponents`).
    ///
    /// The identifier is on the row's stack, which is not an element of its own: on iOS each child
    /// carries it, and the first is the icon, which iOS 27 reports as not hittable ("Failed to not
    /// hittable: Image … server.rack", eight tests at once on the 2026-10-24 iPhone run). The title
    /// is the part a person touches and the part that names the scope. The Mac combines the row into
    /// one element, which carries the name as its value.
    func libraryScope(_ id: String) -> XCUIElement {
        let identifier = "glass-library-scope-\(id)"
        #if os(iOS)
        return staticTexts.matching(identifier: identifier).firstMatch
        #else
        return descendants(matching: .any).matching(identifier: identifier).firstMatch
        #endif
    }
}

extension XCUIApplication {
    /// The navigation back button. By the system's identifier: on the iPhone Duo's outer display it
    /// sits in iOS's own column beside the status bar, not first in the navigation bar, and
    /// "the bar's first button" tapped something else (the 2026-10-24 Duo run).
    var backButton: XCUIElement {
        let system = buttons["BackButton"].firstMatch
        return system.waitForExistence(timeout: 2) ? system : navigationBars.buttons.element(boundBy: 0)
    }
}

extension XCUIElement {
    /// The text an element shows: its label, or its value where the label is empty (a Mac sidebar row).
    var shownText: String {
        label.isEmpty ? "\(value ?? "")" : label
    }
}

#if os(iOS)
extension XCUIApplication {
    /// Taps the button in a sheet's bar that closes the sheet, until it has, first bringing the bar
    /// back if it has gone, as a person would, by dragging the form down. Every caller has filled
    /// the form correctly; a sheet that refuses stays open, and the caller reads why.
    ///
    /// On the iPhone Duo's outer display (iOS 27.1) the host sheet's bar, title, Cancel and Add,
    /// moves up out of sight: once a field low in the form commits with Return (2026-10-24), and on
    /// its own a second or two after a password is typed, with nothing touched. It stays gone until
    /// the form is dragged down (a probe read Add at y −27, not hittable, for 20 s; 2026-10-25), and
    /// at times its buttons leave the tree altogether. Shown to the owner.
    ///
    /// Only the sheet going says a tap landed. A tap made as the bar left found no hit point, which
    /// XCUITest logs and does not fail, and its retry scrolled the form and brought the bar back,
    /// so Add on screen afterwards says nothing. Save is disabled while saving, so a second tap
    /// cannot save twice. The sheet is known by its bar's title ("Add Host", "Edit Host", "Add
    /// Terminal to …"), which stays in the tree when the bar's buttons do not.
    func tapUntilSheetCloses(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = buttons[identifier].firstMatch
        var sheet: XCUIElement?
        var tapped = false
        for _ in 0..<5 {
            if button.waitForExistence(timeout: 2) {
                if sheet == nil {
                    let title = navigationBars.containing(.button, identifier: identifier).firstMatch.identifier
                    if !title.isEmpty { sheet = navigationBars[title].firstMatch }
                }
                if isOnScreen(button) {
                    button.tap()
                    tapped = true
                    if (sheet ?? button).waitForNonExistence(timeout: 5) { return }
                    continue
                }
            }
            swipeDown(velocity: .slow)
            // Add Host does not refuse a drag down, so the drag that brings the bar back can also
            // close the sheet without saving.
            if let sheet, !sheet.exists {
                if !tapped {
                    XCTFail("dragging the form down to bring its bar back closed the sheet unsaved",
                            file: file, line: line)
                }
                return
            }
        }
        // Tapped and still open: refused, and the caller reads why.
        if !tapped {
            XCTFail("\(identifier) never came on screen, though the form was dragged down five times",
                    file: file, line: line)
        }
    }

    private func isOnScreen(_ element: XCUIElement) -> Bool {
        element.exists && element.isHittable && frame.contains(element.frame)
    }
}

extension XCUIElement {
    /// Replaces a text field's text the way a person does: Select All from the field's
    /// press-and-hold menu, then type. A tap leaves the cursor before the value of a form's
    /// trailing-aligned field (typing 2223 into "22" made 222322, "gpt_test" into "root" made
    /// gpt_testroot), and a double tap at the centre selects nothing, because the centre is empty
    /// space left of the text (the 2026-10-25 runs, iPhone and Duo). The menu works on both,
    /// whatever the alignment. Callers check the field reads what was typed.
    ///
    /// An empty field reports its placeholder as its value, so a value equal to the placeholder
    /// proves nothing: the database form fills the user name with the engine's default and shows
    /// the same default as its prompt ("root" both ways), and skipping that case typed in front of
    /// it. Only an empty value skips the menu; an empty field offers no Select All, so the wait is
    /// short when the value is the placeholder.
    func replaceText(with text: String, in app: XCUIApplication) {
        tap()
        let current = value as? String ?? ""
        if !current.isEmpty {
            press(forDuration: 1.2)
            let selectAll = app.menuItems["Select All"].firstMatch
            if selectAll.waitForExistence(timeout: current == placeholderValue ? 1.5 : 3) { selectAll.tap() }
        }
        typeText(text)
    }
}
#endif
