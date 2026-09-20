import XCTest

/// The editor on a phone, driven end to end.
///
/// Reported 2026-09-17: *"the editor doesn't actually work at all. The file title shows but no
/// content."* The editor is a `NavigationSplitView`, and on a compact width SwiftUI collapses one
/// of those into a single stack showing the **sidebar** first — which for a file with no project
/// is an empty list under a navigation bar. This walks the same path a person does and photographs
/// what arrives, because that claim is only worth what a screenshot says.
///
/// It needs a project it can open without the system file picker, seeded into the app's own
/// `UserDefaults` and container before the run.
@MainActor
final class EditorOnIPhoneUITests: XCTestCase {

    /// Both an attachment and a file.
    ///
    /// The attachment is for a person reading a result bundle; the file is because those bundles
    /// have repeatedly arrived unfinalised, and a screenshot that cannot be opened is not evidence.
    /// `NSTemporaryDirectory()` here is the *runner's* container, which the host can reach with
    /// `xcrun simctl get_app_container <device> <runner-bundle-id> data`.
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glass-\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
        print("SHOT \(name) -> \(url.path)")
    }

    func testOpeningAProjectShowsItsFiles() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        // The project is made by the app, in its own container. A path seeded from here dies with
        // the container the next time the app is installed.
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-project"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        // Into Projects, which on a phone is the editor's only door.
        // By identifier, not by text: the section header and the row both say "Projects", and
        // `firstMatch` takes the header, which does nothing when tapped.
        let projects = app.descendants(matching: .any)
            .matching(identifier: "glass-library-panel-editor-projects").firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 15), "the Projects panel is not in the library")
        projects.tap()
        shoot(app, "01-projects-panel")

        let row = app.staticTexts["DemoProject"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the seeded project is not listed")
        row.tap()
        shoot(app, "02-project-selected")

        // Open is in the detail; on a phone the detail is pushed after the row is chosen, which
        // is its own fix — a panel's selection is a push nobody else can make for it.
        let open = app.buttons["project-open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15), "the project's detail never appeared")
        open.tap()
        Thread.sleep(forTimeInterval: 4)
        shoot(app, "03-editor")

        // **The project's files are the screen it lands on**, not the editor's empty state with
        // the list behind a toggle (reported 2026-09-18). The toggle is gone with the sheet it
        // opened, so its absence is part of the claim.
        let readme = app.staticTexts["README.md"].firstMatch
        XCTAssertTrue(readme.waitForExistence(timeout: 15),
                      "opening the project did not land on its files")
        XCTAssertFalse(app.buttons["editor-files"].exists,
                       "the Files toggle is still there, so the file list is still hidden behind it")
        shoot(app, "04-project-files")

        // The header says where you are: the folder large, the path to it beneath.
        let header = app.descendants(matching: .any).matching(identifier: "glass-path-header").firstMatch
        XCTAssertTrue(header.exists, "the folder screen has no header saying where it is")

        // A folder is a push, and the back button is the way out — the Files browser's navigation.
        let sources = app.staticTexts["Sources"].firstMatch
        XCTAssertTrue(sources.waitForExistence(timeout: 10), "the project's folder is not listed")
        sources.tap()
        let nested = app.staticTexts["main.swift"].firstMatch
        XCTAssertTrue(nested.waitForExistence(timeout: 10),
                      "tapping a folder did not open it")
        shoot(app, "05-folder-pushed")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(readme.waitForExistence(timeout: 10), "the back button did not return to the project")

        // And a file is a push onto the editor, with the file in it.
        readme.tap()
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "06-file-open")
        XCTAssertTrue(app.buttons["editor-save"].waitForExistence(timeout: 10),
                      "choosing a file did not open the editor")
    }
}

extension EditorOnIPhoneUITests {
    /// **A refusal must not swallow the next click.**
    ///
    /// Reported 2026-09-18: *"I tried to connect to a Mac desktop project (for fun) and was given
    /// an appropriate error. Then I tried to open another project and it just absorbed the click."*
    /// Reproduced here with a project whose folder is gone, which raises the same alert on the
    /// same screen without needing a host.
    func testAProjectThatRefusesToOpenDoesNotBlockTheNextOne() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-project", "--ui-testing-seed-missing-project"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let projects = app.descendants(matching: .any)
            .matching(identifier: "glass-library-panel-editor-projects").firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 15), "the Projects panel is not in the library")
        projects.tap()

        // The one that cannot open.
        let gone = app.staticTexts["GoneProject"].firstMatch
        XCTAssertTrue(gone.waitForExistence(timeout: 10), "the missing-folder project is not listed")
        gone.tap()
        let open = app.buttons["project-open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15), "the project's detail never appeared")
        open.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "a project with no folder must say so")
        shoot(app, "10-refusal")
        alert.buttons["OK"].firstMatch.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10), "the alert stays on screen")

        // Back to the list, and open the one that works.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let demo = app.staticTexts["DemoProject"].firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 10), "the working project is not listed")
        demo.tap()
        let openAgain = app.buttons["project-open"].firstMatch
        XCTAssertTrue(openAgain.waitForExistence(timeout: 15))
        openAgain.tap()
        Thread.sleep(forTimeInterval: 4)
        shoot(app, "11-after-refusal")

        XCTAssertTrue(app.staticTexts["README.md"].firstMatch.waitForExistence(timeout: 15),
                      "the click after a refusal was absorbed: the editor never opened")
    }
}
