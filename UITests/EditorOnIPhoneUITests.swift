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

        // The editor must be showing the project, not an empty column with the title above it.
        let files = app.buttons["editor-files"].firstMatch
        XCTAssertTrue(files.waitForExistence(timeout: 10),
                      "the editor did not present its own layout")
        files.tap()
        Thread.sleep(forTimeInterval: 2)
        shoot(app, "04-files-sheet")

        // The file tree should be reachable, and a file openable.
        let readme = app.staticTexts["README.md"].firstMatch
        XCTAssertTrue(readme.waitForExistence(timeout: 10), "the project's files are not listed")
        readme.tap()
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "05-file-open")
    }
}
