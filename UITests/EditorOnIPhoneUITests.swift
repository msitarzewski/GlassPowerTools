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

        app.backButton.tap()
        XCTAssertTrue(readme.waitForExistence(timeout: 10), "the back button did not return to the project")

        // And a file is a push onto the editor, with the file in it.
        readme.tap()
        Thread.sleep(forTimeInterval: 3)
        shoot(app, "06-file-open")
        XCTAssertTrue(app.buttons["editor-position"].waitForExistence(timeout: 10),
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
        app.backButton.tap()
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
                let back = app.backButton
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

        app.backButton.tap()
        Thread.sleep(forTimeInterval: 2)

        openProject("OtherProject")
        XCTAssertTrue(app.staticTexts["NOTES.md"].firstMatch.waitForExistence(timeout: 15),
                      "the second project did not open on its files")

        let bolts = app.buttons.matching(identifier: "active-connections-bolt")
        XCTAssertTrue(bolts.firstMatch.waitForExistence(timeout: 10), "no bolt in the editor's toolbar")
        // The one a person can reach: the library's own stays in the tree under the editor, and on
        // the Duo's outer display it comes first while the editor's is in iOS's column.
        let bolt = bolts.allElementsBoundByIndex.first { $0.isHittable } ?? bolts.firstMatch
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
        app.backButton.tap()
        #endif
        let markdown = app.staticTexts["PREVIEW.md"].firstMatch
        XCTAssertTrue(markdown.waitForExistence(timeout: 10))
        markdown.tap()
        #if os(visionOS)
        // A headset window has no subtitle; the file's project and folder are in the status line.
        let location = app.staticTexts["editor-status-location"].firstMatch
        if location.waitForExistence(timeout: 10) {
            XCTAssertTrue(location.label.contains("DemoProject"), "the status line names \(location.label), not the project")
        } else {
            XCTFail("the status line does not say where the file is")
        }
        #endif
        // On the headset this used to stop here: none of the editor's toolbar reached the
        // accessibility tree, because it was given to the split view and visionOS draws a
        // column's toolbar, not a split view's. It is the window's toolbar ornament now
        // (2026-10-09), so the same walk runs on every platform.
        let toggle = app.buttons["editor-preview-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Markdown offers no Preview button")
        toggle.tap()
        let preview = app.descendants(matching: .any).matching(identifier: "editor-preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Preview did not appear")
        // The page itself, not only its frame: the table's header, and a node of the diagram,
        // which exists as its own text only once Mermaid has drawn it (the fence is one string).
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.staticTexts["Machine"].waitForExistence(timeout: 15), "the preview page drew no table")
        XCTAssertTrue(page.staticTexts["Library"].waitForExistence(timeout: 15), "Mermaid did not draw the diagram")
        shoot(app, "21-markdown-preview")
        #if os(visionOS)
        // Room beside the text: beside, then alone, then gone.
        toggle.tap()
        toggle.tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 10), "a third press did not return to the text")
        #else
        toggle.tap()
        XCTAssertTrue(app.buttons["editor-position"].waitForExistence(timeout: 10), "a second press did not return to the text")
        #endif
    }
}

extension EditorOnIPhoneUITests {
    /// **A blank document without a project** (2026-10-09, Vision Pro). Off the Mac, Projects is
    /// the editor's only door, and it opened folders and nothing else; the Mac has ⇧⌘E. The plus
    /// button now offers New Document, which opens an editor on an empty, unsaved document.
    func testProjectsOpensANewDocument() throws {
        #if os(macOS)
        throw XCTSkip("The Mac's way in is File ▸ New Editor Window (⇧⌘E).")
        #else
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-project"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        #if os(visionOS)
        let projects = app.tabBars.buttons["Projects"].waitForExistence(timeout: 15)
            ? app.tabBars.buttons["Projects"] : app.buttons["Projects"].firstMatch
        #else
        let projects = app.descendants(matching: .any)
            .matching(identifier: "glass-library-panel-editor-projects").firstMatch
        #endif
        XCTAssertTrue(projects.waitForExistence(timeout: 15))
        projects.tap()

        let add = app.buttons["projects-add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Projects has no plus button")
        add.tap()
        let newDocument = app.buttons["projects-new-document"].firstMatch
        XCTAssertTrue(newDocument.waitForExistence(timeout: 10), "the plus button offers no New Document")
        XCTAssertTrue(app.buttons["projects-open"].firstMatch.exists, "the plus button offers no Open…")
        newDocument.tap()

        // An editor on one untitled document.
        XCTAssertTrue(app.buttons["editor-position"].firstMatch.waitForExistence(timeout: 15),
                      "New Document did not open an editor")
        XCTAssertTrue(app.staticTexts["Untitled"].firstMatch.waitForExistence(timeout: 10),
                      "the new editor is not on an Untitled document")
        #endif
    }
}

extension EditorOnIPhoneUITests {
    #if os(iOS)
    /// How many pixels are near the seeded SVG's red, #b5412b.
    static func reddish(in image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4)
        where abs(Int(pixels[index]) - 181) < 40 && abs(Int(pixels[index + 1]) - 65) < 40 && abs(Int(pixels[index + 2]) - 43) < 40 {
            count += 1
        }
        return count
    }
    #endif

    /// A one-line, ~2 MB SVG opens on a phone and the app stays alive and responsive (2026-09-23: the
    /// same shape froze the Mac until lines over 20,000 characters stopped being coloured).
    ///
    /// A phone's text view cannot draw a line that long, so such a file opens as its picture with the
    /// text one press away (`GlassEditorWorkspace`, the owner on 2026-09-23: "previews only on iOS,
    /// that's fine"). This waited for the text first and missed that; it now checks the picture is
    /// drawn — the path's red — not merely that a preview view exists.
    func testAOneLineMegabyteSVGOpensWithoutHanging() throws {
        #if os(iOS)
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
        let preview = app.descendants(matching: .any).matching(identifier: "editor-preview").firstMatch
        let toggle = app.buttons["editor-preview-toggle"].firstMatch
        if UIDevice.current.userInterfaceIdiom != .phone {
            // Elsewhere it opens as text, as any file does; Preview draws the picture.
            XCTAssertTrue(app.buttons["editor-position"].waitForExistence(timeout: 20), "the SVG did not open")
            XCTAssertFalse(preview.exists, "an iPad opens it as text")
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            toggle.tap()
        }
        XCTAssertTrue(preview.waitForExistence(timeout: 20), "the SVG did not open as its picture")
        XCTAssertTrue(app.buttons["editor-position"].exists, "the file is open in the editor")
        // The app's whole screen: the identifier is on the pane's group, so the first element
        // carrying it can be a piece of the web view with no frame, which has no picture to take.
        let drawn = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Self.reddish(in: app.screenshot().image) > 200
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [drawn], timeout: 30), .completed, "the picture was not drawn")
        shoot(app, "30-large-svg-preview")
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            toggle.tap()
            XCTAssertTrue(preview.waitForNonExistence(timeout: 20), "the text is not one press away")
            shoot(app, "31-large-svg-text")
            toggle.tap()
            XCTAssertTrue(preview.waitForExistence(timeout: 20), "a second press did not bring the picture back")
        }
        // Alive and answering: the app is still in front and the editor answers a query.
        XCTAssertEqual(app.state, .runningForeground, "the app is no longer running")
        XCTAssertTrue(app.buttons["editor-position"].waitForExistence(timeout: 10), "the editor stopped answering")
        print("LARGE-SVG seconds: \(Int(Date().timeIntervalSince(started)))")
        #else
        throw XCTSkip("the picture is counted from a UIImage; the Mac's editor opens such a file as text")
        #endif
    }
}

