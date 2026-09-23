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

extension EditorOnIPhoneUITests {
    /// **The ⚡: from inside any session to every live connection, on the device with no windows.**
    ///
    /// Drives the only pair of sessions a simulator can have without a server — two editor
    /// windows — and checks what the bolt promises: it is in the session's own toolbar, tapping it
    /// leaves the session and lands on the library's Active list, the *other* editor is listed
    /// there under this device, and choosing it arrives.
    ///
    /// It stands on the fix underneath it: leaving the first editor used to discard its
    /// workspace, so there would have been nothing to come back to.
    func testTheBoltReachesTheOtherEditor() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-project", "--ui-testing-seed-second-project"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        func openProject(_ name: String) {
            let projects = app.descendants(matching: .any)
                .matching(identifier: "glass-library-panel-editor-projects").firstMatch
            for _ in 0..<4 where !projects.exists {
                let back = app.navigationBars.buttons.element(boundBy: 0)
                guard back.exists else { break }
                back.tap()
                Thread.sleep(forTimeInterval: 1.5)
            }
            XCTAssertTrue(projects.waitForExistence(timeout: 15), "the Projects panel is not in the library")
            projects.tap()
            let row = app.staticTexts[name].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "\(name) is not listed")
            row.tap()
            let open = app.buttons["project-open"].firstMatch
            XCTAssertTrue(open.waitForExistence(timeout: 15), "\(name) has no detail to open from")
            open.tap()
            Thread.sleep(forTimeInterval: 4)
        }

        openProject("DemoProject")
        XCTAssertTrue(app.staticTexts["README.md"].firstMatch.waitForExistence(timeout: 15),
                      "the first project did not open on its files")
        XCTAssertTrue(app.buttons["active-connections-bolt"].firstMatch.exists,
                      "the bolt belongs in every session's toolbar, whether or not anything else is open")
        shoot(app, "10-first-editor")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 2)

        openProject("OtherProject")
        XCTAssertTrue(app.staticTexts["NOTES.md"].firstMatch.waitForExistence(timeout: 15),
                      "the second project did not open on its files")

        let bolt = app.buttons["active-connections-bolt"].firstMatch
        XCTAssertTrue(bolt.waitForExistence(timeout: 10), "no bolt in the editor's toolbar")
        shoot(app, "11-bolt")
        bolt.tap()

        // Out of the editor and onto Active: both editors are live, under this device.
        let active = app.descendants(matching: .any).matching(identifier: "active-connections").firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 15), "the bolt did not land on the Active list")
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'active-session-editor:'"))
        XCTAssertEqual(rows.count, 2, "both editors should be listed as live")
        shoot(app, "12-active")

        let other = app.staticTexts["DemoProject"].firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 10), "the first editor is not under Active")
        other.tap()
        XCTAssertTrue(app.staticTexts["README.md"].firstMatch.waitForExistence(timeout: 15),
                      "choosing the live editor did not arrive at it")
        shoot(app, "13-switched")
    }
}

extension EditorOnIPhoneUITests {
    /// A PNG opens as the picture, and Markdown's Preview draws its table and diagram — on a phone,
    /// where Preview is a toggle rather than a pane beside the text (2026-09-23).
    func testAPictureOpensAsItselfAndMarkdownPreviews() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-project"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        // A sidebar row on a phone; on visionOS the library is a tab bar in the leading ornament.
        #if os(visionOS)
        let projects = app.tabBars.buttons["Projects"].waitForExistence(timeout: 15)
            ? app.tabBars.buttons["Projects"] : app.buttons["Projects"].firstMatch
        #else
        let projects = app.descendants(matching: .any)
            .matching(identifier: "glass-library-panel-editor-projects").firstMatch
        #endif
        XCTAssertTrue(projects.waitForExistence(timeout: 15))
        projects.tap()
        let row = app.staticTexts["DemoProject"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let open = app.buttons["project-open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        let logo = app.staticTexts["logo.png"].firstMatch
        XCTAssertTrue(logo.waitForExistence(timeout: 15), "the seeded picture is not in the project")
        logo.tap()
        let viewer = app.descendants(matching: .any).matching(identifier: "editor-viewer-image").firstMatch
        XCTAssertTrue(viewer.waitForExistence(timeout: 10), "the PNG did not open as an image")
        shoot(app, "20-png-viewer")

        // A phone pushed the picture over the list; the headset keeps the list beside it.
        #if !os(visionOS)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        #endif
        let markdown = app.staticTexts["PREVIEW.md"].firstMatch
        XCTAssertTrue(markdown.waitForExistence(timeout: 10))
        markdown.tap()
        #if os(visionOS)
        // Open question, recorded 2026-09-23: in the headset simulator none of the editor's toolbar
        // buttons — Save included — reach the accessibility tree, so the Preview half cannot be
        // driven here. Whether the toolbar is in an ornament the test cannot see or is not drawn
        // is for the headset itself to answer.
        throw XCTSkip("The editor's toolbar is not visible to UI tests on visionOS; Preview checked on iPhone and Mac.")
        #endif
        let toggle = app.buttons["editor-preview-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Markdown offers no Preview button")
        toggle.tap()
        let preview = app.descendants(matching: .any).matching(identifier: "editor-preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Preview did not appear")
        Thread.sleep(forTimeInterval: 3)   // Mermaid draws after the page loads
        shoot(app, "21-markdown-preview")
        toggle.tap()
        XCTAssertTrue(app.buttons["editor-save"].waitForExistence(timeout: 10), "a second press did not return to the text")
    }
}

extension EditorOnIPhoneUITests {
    /// A one-line, ~2 MB SVG opens on a phone and the app stays alive and responsive — as text and
    /// with Preview (2026-09-23: the same shape froze the Mac until lines over 20,000 characters
    /// stopped being coloured).
    func testAOneLineMegabyteSVGOpensWithoutHanging() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-project",
                                "--ui-testing-seed-large-svg"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let projects = app.descendants(matching: .any)
            .matching(identifier: "glass-library-panel-editor-projects").firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 15))
        projects.tap()
        app.staticTexts["DemoProject"].firstMatch.tap()
        let open = app.buttons["project-open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        let svg = app.staticTexts["wide-logo.svg"].firstMatch
        XCTAssertTrue(svg.waitForExistence(timeout: 15), "the large SVG was not seeded")
        let started = Date()
        svg.tap()
        XCTAssertTrue(app.buttons["editor-save"].waitForExistence(timeout: 20), "the SVG did not open as text")
        Thread.sleep(forTimeInterval: 6)
        shoot(app, "30-large-svg-text")
        let toggle = app.buttons["editor-preview-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "editor-preview").firstMatch
            .waitForExistence(timeout: 20), "Preview did not appear")
        Thread.sleep(forTimeInterval: 10)
        shoot(app, "31-large-svg-preview")
        toggle.tap()
        // Alive and answering: the app is still in front and the editor answers a query.
        XCTAssertEqual(app.state, .runningForeground, "the app is no longer running")
        XCTAssertTrue(app.buttons["editor-save"].waitForExistence(timeout: 10), "the editor stopped answering")
        print("LARGE-SVG seconds: \(Int(Date().timeIntervalSince(started)))")
    }
}

extension EditorOnIPhoneUITests {
    /// The user's own logo — 14.6 MB on one line, almost all an embedded PNG — opened on a phone.
    /// Runs only when `GPT_SEED_FILE` names a file on the Mac (2026-09-23).
    func testTheUsersOneLineLogoOpens() throws {
        guard let path = ProcessInfo.processInfo.environment["GPT_SEED_FILE"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_GPT_SEED_FILE to a file on this Mac.")
        }
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-project",
                                "--ui-testing-seed-file", path]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let projects = app.descendants(matching: .any)
            .matching(identifier: "glass-library-panel-editor-projects").firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 15))
        projects.tap()
        app.staticTexts["DemoProject"].firstMatch.tap()
        let open = app.buttons["project-open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        let name = (path as NSString).lastPathComponent
        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the file was not copied into the project")
        let started = Date()
        row.tap()
        let opened = app.buttons["editor-save"].waitForExistence(timeout: 60)
        print("USER-FILE open seconds: \(Int(Date().timeIntervalSince(started))) opened: \(opened)")
        Thread.sleep(forTimeInterval: 6)
        shoot(app, "40-user-file-text")
        XCTAssertEqual(app.state, .runningForeground, "the app is no longer running after opening the file")
        let toggle = app.buttons["editor-preview-toggle"].firstMatch
        if toggle.waitForExistence(timeout: 10) {
            toggle.tap()
            Thread.sleep(forTimeInterval: 12)
            shoot(app, "41-user-file-preview")
        }
        XCTAssertEqual(app.state, .runningForeground, "the app is no longer running after Preview")
        let responsive = app.buttons["editor-save"].waitForExistence(timeout: 20)
        print("USER-FILE responsive after preview: \(responsive)")
    }
}

