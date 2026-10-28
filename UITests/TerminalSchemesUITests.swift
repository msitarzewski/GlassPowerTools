//
//  TerminalSchemesUITests.swift
//  GlassPowerToolsUITests
//
//  Terminal color schemes (2026-10-28, a user's folder of 148: "Let's make these work, first class
//  style!"): Terminal profiles imported as a folder (`--demo-terminal-schemes` writes three and
//  imports them, as Import does a folder the person picks), listed in Choose Theme in their own
//  colors, chosen for All Terminals, and offered to one window in This Window.
//

#if os(visionOS)
import XCTest

@MainActor
final class TerminalSchemesUITests: XCTestCase {
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
                                "--demo-open", surface, "--demo-terminal-schemes"] + more
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func words(_ element: XCUIElement) -> String {
        element.exists ? "\(element.label) \(element.value as? String ?? "")" : "(gone)"
    }

    private func said(by element: XCUIElement, _ text: String, within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if words(element).contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return false
    }

    func testAnImportedSchemeIsChosenForAllTerminals() {
        launch("terminal-settings", ["--demo-settings-tab", "terminal"])
        let choose = element("terminal-settings-choose-theme")
        XCTAssertTrue(choose.waitForExistence(timeout: 40), "Terminal Settings has no Choose")
        choose.tap()

        let paper = element("terminal-scheme-Demo Paper")
        XCTAssertTrue(paper.waitForExistence(timeout: 30), "the imported schemes aren't listed")
        for name in ["Demo Solarized", "Demo Neon"] {
            XCTAssertTrue(element("terminal-scheme-\(name)").exists, "\(name) isn't listed")
        }
        XCTAssertTrue(element("terminal-theme-Glass Terminal").exists, "your themes aren't listed")
        XCTAssertTrue(paper.wait(for: \.isEnabled, toEqual: true, timeout: 20), "Demo Paper was never read")
        paper.tap()
        XCTAssertTrue(said(by: paper, "Chosen", within: 10), "choosing it didn't mark it: \(words(paper))")
        element("terminal-theme-chooser-done").tap()

        let name = element("terminal-settings-theme-name")
        XCTAssertTrue(said(by: name, "Demo Paper", within: 10), "All Terminals' theme: \(words(name))")
        XCTAssertFalse(app.navigationBars["Themes"].exists, "Choose opened the theme editor too")
        // Back to the built-in, so nothing is left for the next run.
        choose.tap()
        let builtIn = element("terminal-theme-Glass Terminal")
        XCTAssertTrue(builtIn.waitForExistence(timeout: 10))
        builtIn.tap()
        element("terminal-theme-chooser-done").tap()
        XCTAssertTrue(said(by: name, "Glass Terminal", within: 10), words(name))

        // One window: This Window offers the schemes beside your themes.
        app.buttons["This Window"].tap()
        let picker = element("terminal-window-theme")
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        for _ in 0..<6 where !(picker.exists && picker.isHittable) { list.swipeUp() }
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "This Window has no theme picker")
        picker.tap()
        let neon = app.buttons["Demo Neon"].firstMatch
        XCTAssertTrue(neon.waitForExistence(timeout: 10), "This Window doesn't offer the imported schemes")
        neon.tap()
        XCTAssertTrue(said(by: picker, "Demo Neon", within: 10), "the window's theme: \(words(picker))")
    }
}
#endif
