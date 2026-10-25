#if os(iOS)
import XCTest
import UIKit

/// A reply copied from Claude Code or Codex arrives with a newline wherever the window ended, and a
/// paste sends each as Return. The terminal joins such lines again (2026-10-19, the owner: "We
/// recognize the pattern and (persisted with a checkbox in that modal) automatically repair the
/// text"; then "skip the review when it joins to one line, yes"). Pasted here from the terminal's
/// own menu, as a finger pastes.
///
/// Rule 21: never alongside another XCUITest run. On an iPad, in an install of its own: iPadOS brings
/// back the windows of the run before.
@MainActor
final class TerminalPasteUITests: XCTestCase {
    private var app: XCUIApplication!

    /// The owner's example, as copied: three lines at 134 columns that join to one.
    private let example = """
        • I found two separate routes: extracting and studying compiled CUDA kernels, and translating supported CUDA code to Metal. Both exist
          today. CuMetal still explicitly excludes the tensor-core instructions Nunchaku uses, so decompilation could help us understand a
          kernel, but making it fast on Apple hardware would still require a Metal implementation.
        """

    /// Two paragraphs, wrapped at 72 columns: joined, three lines — the blank one between them kept.
    private let twoParagraphs = """
        • The terminal sends each line of a paste as if Return were pressed after
          it, so a reply copied from a program that wraps its text arrives as
          several commands.

        • Joined again, each paragraph is one line, and the blank line between
          them stays where it was.
        """
    private let twoParagraphsJoined = """
        • The terminal sends each line of a paste as if Return were pressed after it, so a reply copied from a program that wraps its text arrives as several commands.

        • Joined again, each paragraph is one line, and the blank line between them stays where it was.
        """

    private var clipboard: UITestClipboard?

    override func setUp() async throws {
        try await MainActor.run { clipboard = try UITestClipboard() }
    }

    override func tearDown() async throws {
        await MainActor.run {
            app?.terminate()
            clipboard?.restore()
        }
    }

    private var terminal: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Terminal'")).firstMatch
    }

    /// Hold the terminal, then Paste from its menu.
    private func paste(_ text: String) {
        UIPasteboard.general.string = text
        terminal.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"].exists ? app.menuItems["Paste"] : app.buttons["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "the terminal's menu offers Paste")
        paste.tap()
    }

    func testAWrappedReplyIsJoinedWhenPasted() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", "terminal",
                                // A blinking cursor is a repeating animation, so the app is never
                                // idle and every step waited XCUITest's 60 seconds for it: 693 s.
                                "-blinkingCursor", "NO"]
        app.launch()
        self.app = app
        XCTAssertTrue(terminal.waitForExistence(timeout: 30), "the terminal")
        let join = app.switches["terminal-paste-join-wrapped"]
        let text = app.textViews["terminal-paste-text"]

        // One line once joined: typed, with no review.
        paste(example)
        XCTAssertFalse(app.navigationBars["Review Terminal Paste"].waitForExistence(timeout: 4),
                       "joined to one line, the paste needs no review")

        // Still more than one line: reviewed, joined, the checkbox on.
        paste(twoParagraphs)
        XCTAssertTrue(join.waitForExistence(timeout: 10), "the review offers to join the lines")
        let review = XCTAttachment(screenshot: app.screenshot())
        review.name = "paste-review"
        review.lifetime = .keepAlways
        add(review)
        XCTAssertEqual(join.value as? String, "1", "on until someone turns it off")
        XCTAssertEqual(text.value as? String, twoParagraphsJoined)
        // Off: the lines as they came.
        join.switches.firstMatch.tap()
        XCTAssertEqual(join.value as? String, "0")
        XCTAssertEqual(text.value as? String, twoParagraphs)
        app.buttons["Cancel"].tap()

        // Remembered off: the example is reviewed as it came.
        paste(example)
        XCTAssertTrue(join.waitForExistence(timeout: 10), "reviewed now")
        XCTAssertEqual(join.value as? String, "0", "as it was left")
        XCTAssertEqual((text.value as? String)?.split(separator: "\n").count, 3)
        app.buttons["Cancel"].tap()
    }
}
#endif
