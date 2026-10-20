#if os(iOS) || os(visionOS)
import XCTest

/// What VoiceOver and Voice Control are told about controls the accessibility audit found
/// unnamed or misnamed (2026-10-18, `AccessibilityAuditUITests`), each checked against the screen
/// a person uses: the demo's made-up machines and files.
@MainActor
final class AccessibilityLabelsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func open(_ surface: String, _ extra: [String] = []) {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh+database|bravo@192.0.2.20:ssh+rdp",
                                "--demo-open", surface] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        self.app = app
        Thread.sleep(forTimeInterval: 12)
    }

    private func labelled(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// A button by its label: the tab itself, not the words drawn inside it.
    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// The audit's "Element has no description", for this screen only.
    private func undescribed() throws -> [String] {
        var found: [String] = []
        try app.performAccessibilityAudit(for: .sufficientElementDescription) { issue in
            // No name at all; "label not human-readable" (a file name such as compose.yaml) is
            // the same audit type and not what this checks.
            if issue.element?.label.isEmpty ?? true {
                found.append(issue.element.map { "\($0.elementType.rawValue) \(NSCoder.string(for: $0.frame))" } ?? "no element")
            }
            return true
        }
        return found
    }

    /// An editor tab is read by its file's name. Its label was the file's folder, so every tab from
    /// one folder sounded the same, and "Close" named the folder rather than the file.
    func testEditorTabsAreNamedByTheirFiles() throws {
        open("editor")
        XCTAssertTrue(button("compose.yaml").waitForExistence(timeout: 10), "the compose.yaml tab, by name")
        XCTAssertTrue(button("README.md").exists, "the README.md tab, by name")
        XCTAssertTrue(button("Close compose.yaml").exists, "its close button names the file")
    }

    /// A database tab is read as it is shown ("orders"), which is what Voice Control acts on; it
    /// was "Table editor for main.orders".
    func testDatabaseTabsAreNamedAsShown() throws {
        open("database")
        XCTAssertTrue(button("orders").waitForExistence(timeout: 10), "the orders tab, by its title")
        XCTAssertTrue(button("Close orders").exists, "its close button names it")
        XCTAssertTrue(app.descendants(matching: .any)["db-workspace-tab-table-main.orders"].exists,
                      "the tab's identifier says what it is")
    }

    /// A machine's page: each service's icon is named, as the library row's are. The drawn
    /// database icon had no name, so VoiceOver read only its status.
    func testServiceIconsOnAMachinesPageAreNamed() throws {
        open("connections-host")
        XCTAssertEqual(try undescribed(), [], "unnamed elements on a machine's page")
    }

    /// No window hides an empty element the size of the window. On visionOS the Connections
    /// window's probe and a session window's sizer, invisible helpers in the background, took the
    /// window's size and were offered to VoiceOver as nameless elements.
    func testTheLibraryHasNoUnnamedElements() throws {
        open("library-history")
        XCTAssertEqual(try undescribed(), [], "unnamed elements in the library")
    }

    func testATerminalWindowHasNoUnnamedElements() throws {
        open("btop", ["--demo-close-connections"])
        XCTAssertEqual(try undescribed(), [], "unnamed elements in a terminal window")
    }

    /// The file browser's title, a menu of the folders above, is named by its folder.
    func testTheFileBrowsersTitleIsNamed() throws {
        open("files")
        XCTAssertEqual(try undescribed(), [], "unnamed elements in the file browser")
    }

    /// A data grid's column-width handles are named and say their width. (Their swipe-up and
    /// swipe-down adjustment is VoiceOver's own gesture, which XCUITest on iOS cannot send.)
    func testColumnWidthHandlesAreNamed() throws {
        open("database")
        XCTAssertEqual(try undescribed(), [], "unnamed elements in the data grid")
        let handle = labelled("Width of customer")
        XCTAssertTrue(handle.waitForExistence(timeout: 10), "the customer column's width handle")
        XCTAssertTrue((handle.value as? String)?.hasSuffix(" points") == true,
                      "it says its width: \(String(describing: handle.value))")
    }
}
#endif
