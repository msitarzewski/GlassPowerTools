#if os(iOS)
import XCTest

/// Every page of the library and Settings on an iPhone or iPad, photographed, for a person to look at.
///
/// Written for the iPhone Duo (2026-10-18, the owner: "Every app page in the Duo. Front, and inside"),
/// and usable on any iOS simulator. The session windows (terminal, database, desktop, editor) are the
/// demo's (`Tools/Screenshots/shoot.sh`). This walks what the demo cannot open: the library's sections,
/// a host's detail and editor, Add Host, and each Settings page. A page that cannot be reached is
/// recorded and the tour goes on, so one run shows everything that renders.
///
/// The pictures are the app's window (`app.windows.firstMatch`): on a Duo, `XCUIScreen.main` is the
/// outer display whatever the pose. Each is attached, and written to the runner's temporary folder as
/// `tour-w<window width>-NN-<page>.png`. The host reads them with
/// `xcrun simctl get_app_container <device> <runner bundle id> data`.
@MainActor
final class PhoneTourUITests: XCTestCase {
    private var app: XCUIApplication!
    private var index = 0
    private var missing: [String] = []

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    func testEveryLibraryAndSettingsPage() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-hosts",
                                "alpha@192.0.2.10:ssh+database|bravo@192.0.2.20:ssh+rdp|nas@192.0.2.30:ssh"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCTAssertTrue(identified("connection-library-settings").waitForExistence(timeout: 30), "the library")
        shoot("library")

        for section in ["All Connections", "Favorites", "Recent", "Active", "SSH Keys", "Workgroups", "Projects"] {
            guard open(section) else { continue }
            shoot(section)
            if section == "All Connections", open(identified("host-row-alpha"), "host alpha") {
                shoot("host-detail")
                if open(identified("host-edit"), "Edit") {
                    shoot("host-editor")
                    _ = open(identified("host-editor-cancel"), "Cancel")
                }
                back()
            }
            back()
        }

        if open(identified("connection-library-add-host"), "Add Host") {
            shoot("add-host")
            dismissSheet()
        }

        if open(identified("connection-library-settings"), "Settings") {
            shoot("settings")
            let picker = identified("settings-sections")
            let titles = picker.waitForExistence(timeout: 10)
                ? picker.buttons.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty } : []
            for title in titles {
                let button = picker.buttons[title]
                guard open(button, "Settings ▸ \(title)") else { continue }
                shoot("settings-\(title)")
                back()
            }
            _ = open(identified("settings-done"), "Done")
        }

        let summary = XCTAttachment(string: missing.isEmpty ? "every page opened" : "not reached:\n" + missing.joined(separator: "\n"))
        summary.name = "tour-summary"
        summary.lifetime = .keepAlways
        add(summary)
        print("TOUR not reached: \(missing)")
    }

    // MARK: - Helpers

    private func identified(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Opens a library section by its row, not the section heading of the same name (Workgroups and
    /// Projects are both), scrolling the list when the row is below the fold.
    private func open(_ title: String) -> Bool {
        let named = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, "\(title),")
        for attempt in 0..<3 {
            // A row is a button or a cell; the heading of the same name is static text, never either.
            // Panels (SSH Keys, Workgroups, Projects) are one combined element each, with an identifier
            // (`glass-library-panel-<id>`, GlassConnectionLibrary.panelRow) and the panel's name.
            let panel = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH 'glass-library-panel-' AND (label == %@ OR label BEGINSWITH %@)",
                title, "\(title),")).firstMatch
            // The categories (All Connections, Favorites, Recent) are cells holding the name as text.
            let candidates = [panel, app.buttons.matching(named).firstMatch, app.cells.matching(named).firstMatch,
                              app.cells.containing(.staticText, identifier: title).firstMatch]
            let wide = app.windows.firstMatch.frame.width >= 600
            if let row = candidates.first(where: { $0.exists && (wide || $0.isHittable) }) {
                // A row at the foot of a short screen sits under the sidebar's footer (an inset the
                // list scrolls clear of): scroll it up first, or the tap lands on the footer.
                if !wide, row.frame.maxY > app.windows.firstMatch.frame.maxY * 0.82, attempt < 2 {
                    app.swipeUp()
                    continue
                }
                row.tap()
                return true
            }
            if attempt == 0 {
                // Two columns with the sidebar hidden (the unfolded Duo in landscape, an iPad): show it.
                let toggle = identified("sidebar-toggle")
                if app.windows.firstMatch.frame.width >= 600, !candidates.contains(where: \.exists), toggle.exists {
                    toggle.tap()
                }
                _ = candidates[0].waitForExistence(timeout: 3)
            } else if attempt == 1 { app.swipeUp() }
        }
        if missing.isEmpty { print("TREE for \(title):\n\(app.debugDescription)") }
        missing.append(title)
        return false
    }

    private func open(_ element: XCUIElement, _ name: String) -> Bool {
        // Existence, not hittability: on the unfolded Duo XCUITest reports elements on the inner
        // display as not hittable (its screen is the outer one), and the tap still lands.
        guard element.waitForExistence(timeout: 5) else {
            missing.append(name)
            return false
        }
        element.tap()
        return true
    }

    /// Back one level on a stacked (compact) screen; on a split screen there is nothing to go back from.
    /// The system's back button, wherever iOS puts it: on the folded Duo's outer display it is in the
    /// column beside the status bar, not in a navigation bar. Failing that, the edge swipe.
    private func back() {
        let button = app.buttons.matching(identifier: "BackButton").firstMatch
        // It can be gone by the time it is tapped, mid-animation; look again just before.
        if button.waitForExistence(timeout: 1), button.exists {
            button.tap()
            return
        }
        // Two columns (the unfolded Duo, an iPad): a section is chosen beside the list, not pushed.
        guard app.windows.firstMatch.frame.width < 600 else { return }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
    }

    private func dismissSheet() {
        for label in ["Cancel", "Close", "Done"] where app.buttons[label].firstMatch.exists {
            app.buttons[label].firstMatch.tap()
            return
        }
        app.swipeDown(velocity: .fast)
    }

    private func shoot(_ page: String) {
        // A pushed page slides in; a picture taken at once catches it halfway.
        Thread.sleep(forTimeInterval: 1.5)
        let window = app.windows.firstMatch
        let screenshot = window.exists ? window.screenshot() : XCUIScreen.main.screenshot()
        let name = String(format: "tour-w%d-%02d-%@", Int(window.frame.width), index,
                          page.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "▸", with: ""))
        index += 1
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name).png"))
    }
}
#endif
