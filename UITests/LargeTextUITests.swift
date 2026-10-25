#if os(iOS)
import XCTest

/// The app at the largest accessibility text size (2026-10-19). There, a service's name was cut to
/// "T…" beside buttons that kept their width, a database's Filter and More broke a letter or two to
/// a line, and the status bars read "Line 1,…", "Conn…" and "Not synced on t…". The owner approved
/// Apple's remedies (`GlassLargeText.swift`): rows stack, bars stay one line with the Large Content
/// Viewer, names wrap. Each test here failed before its remedy.
///
/// The app is launched at a text size with `-UIPreferredContentSizeCategoryName`, as
/// `AccessibilityAuditUITests` does. Rule 21: never alongside another XCUITest run.
@MainActor
final class LargeTextUITests: XCTestCase {
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"
    private var app: XCUIApplication!

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func launch(_ demo: String? = nil, size: String? = largest) {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh+database|bravo@192.0.2.20:ssh+rdp"]
        if let demo { app.launchArguments += ["--demo-open", demo] }
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        self.app = app
        Thread.sleep(forTimeInterval: 12)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The labels of the elements Xcode's audit finds clipped on this screen.
    private func clipped() throws -> [String] {
        var labels: [String] = []
        try app.performAccessibilityAudit(for: .textClipped) { issue in
            labels.append(issue.element?.label ?? "")
            return true
        }
        return labels
    }

    // MARK: - Rows stack

    /// At the largest size a service's buttons go under its name, at the leading edge, and the name
    /// has the row's width.
    func testAServicesButtonsGoUnderItsNameAtTheLargestText() throws {
        launch("connections-host")
        let connect = element("host-service-connect-ssh")
        XCTAssertTrue(connect.waitForExistence(timeout: 10), "the Terminal's Connect")
        let icon = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Terminal'")).firstMatch
        XCTAssertTrue(icon.exists, "the Terminal's icon")
        XCTAssertGreaterThanOrEqual(connect.frame.minY, icon.frame.maxY - 2,
                                    "Connect is under the name: \(connect.frame) against \(icon.frame)")
        // Measured from the icon, not the window: on an iPad the page is the right-hand column.
        XCTAssertLessThan(connect.frame.minX, icon.frame.maxX, "Connect is at the row's leading edge")
    }

    /// At the default size the row is as it was: Connect beside the name, at the trailing edge.
    func testAServicesRowIsUnchangedAtTheDefaultSize() throws {
        launch("connections-host", size: nil)
        let connect = element("host-service-connect-ssh")
        XCTAssertTrue(connect.waitForExistence(timeout: 10), "the Terminal's Connect")
        let icon = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Terminal'")).firstMatch
        XCTAssertTrue(icon.exists, "the Terminal's icon")
        XCTAssertLessThan(abs(connect.frame.midY - icon.frame.midY), 16, "Connect is beside the name")
        XCTAssertGreaterThan(connect.frame.minX, icon.frame.maxX + 100, "Connect is at the trailing edge, past the name")
    }

    /// Your Library's overview, beside the list on an iPad: two figures to a row broke "Ma-chines"
    /// with its symbol over the word, and the services' counts broke "Desktop" a letter or two to
    /// a line. One figure to a row, and the counts one under another.
    func testTheOverviewsFiguresAreWholeAtTheLargestText() throws {
        launch()
        guard element("library-overview").waitForExistence(timeout: 10) else {
            // Beside the list only where there is room: a phone shows the list, and that is checked.
            XCTAssertEqual(UIDevice.current.userInterfaceIdiom, .phone, "an iPad shows the overview beside the list")
            XCTAssertTrue(app.libraryScope("all-connections").exists, "a phone shows the library's list instead")
            return
        }
        let figure = { (name: String) in
            self.app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        }
        let machines = figure("Machines"), services = figure("Services")
        XCTAssertTrue(machines.exists && services.exists, "the Machines and Services figures")
        XCTAssertGreaterThanOrEqual(services.frame.minY, machines.frame.maxY,
                                    "Services under Machines: \(services.frame) against \(machines.frame)")
        let desktops = app.staticTexts.matching(NSPredicate(format: "label == '1 Desktop'")).firstMatch
        XCTAssertTrue(desktops.exists, "the desktops' count")
        XCTAssertLessThan(desktops.frame.height, 100, "\"1 Desktop\" is one line: \(desktops.frame)")
    }

    // MARK: - Bars stay one line

    /// The phone's bar above a table's rows: Filter and More, one line, icons only.
    func testTheDatabasesFilterBarIsOneLineAtTheLargestText() throws {
        launch("database")
        let filter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Filter'")).firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 10), "Filter")
        let more = app.buttons.matching(NSPredicate(format: "label == 'More'")).allElementsBoundByIndex
            .first { abs($0.frame.midY - filter.frame.midY) < 12 && $0.frame.minX > filter.frame.maxX }
        XCTAssertNotNil(more, "More, on Filter's line")
        XCTAssertLessThan(filter.frame.height, 64, "Filter is one line: \(filter.frame)")
        XCTAssertLessThan(more?.frame.height ?? .infinity, 64, "More is one line: \(String(describing: more?.frame))")
    }

    func testTheEditorsStatusBarIsNotClippedAtTheLargestText() throws {
        launch("editor")
        XCTAssertTrue(element("editor-keyboard-toggle").waitForExistence(timeout: 10), "the status bar")
        XCTAssertEqual(try clipped().filter { $0.hasPrefix("Line ") }, [], "the cursor's line and column")
    }

    func testTheDesktopsStatusBarIsNotClippedAtTheLargestText() throws {
        launch("desktop")
        XCTAssertTrue(element("session.keyboard").waitForExistence(timeout: 10), "the status bar")
        XCTAssertEqual(try clipped().filter { $0 == "Connected" }, [], "the desktop's state")
    }

    // MARK: - Text a person sizes themselves

    /// The results grid's text follows the system's size (the owner, 2026-10-19), and its rows grow
    /// with it: at the largest size a row holds text at least twice the default's.
    func testTheGridsRowsGrowAtTheLargestText() throws {
        launch("database")
        let cell = element("db-grid-cell-1-customer")
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "the first row's customer")
        // Tall enough for text twice the default 13 points (`DatabaseGridMetrics.rowHeight(26)`).
        XCTAssertGreaterThanOrEqual(cell.frame.height, 44, "a row at the largest size: \(cell.frame)")
    }

    /// At the default size a row is the 30 points it always was.
    func testTheGridsRowsAreUnchangedAtTheDefaultSize() throws {
        launch("database", size: nil)
        let cell = element("db-grid-cell-1-customer")
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "the first row's customer")
        XCTAssertEqual(cell.frame.height, 30, accuracy: 0.5, "a row at the default size: \(cell.frame)")
    }

    /// The terminal's 14-point default follows the system's size too. Measured by what fits: at the
    /// largest size, the terminal's lines are at most half as wide in characters as at the default.
    /// (The terminal tells VoiceOver its visible lines.) At about three times the text, about a
    /// third of the columns fit.
    func testTheTerminalsTextGrowsAtTheLargestText() throws {
        launch("terminal", size: nil)
        let columnsAtDefault = terminalColumnsInUse()
        app.terminate()
        launch("terminal")
        let columnsAtLargest = terminalColumnsInUse()
        XCTAssertGreaterThan(columnsAtDefault, 20, "the terminal shows its output")
        XCTAssertLessThanOrEqual(columnsAtLargest * 2, columnsAtDefault,
                                 "columns at the largest size: \(columnsAtLargest), at the default: \(columnsAtDefault)")
    }

    /// The widest line the terminal shows, in characters.
    private func terminalColumnsInUse() -> Int {
        let candidates = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Terminal'"))
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 10), "the terminal")
        let terminal = candidates.allElementsBoundByIndex.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        let text = terminal?.value as? String ?? ""
        let shown = XCTAttachment(string: text)
        shown.name = "terminal-value"
        shown.lifetime = .keepAlways
        add(shown)
        let lines = text.split(separator: "\n")
        return lines.map(\.count).max() ?? 0
    }

    /// The editor's file list on an iPad is wider at an accessibility size, so a file's name is
    /// whole: it broke "com-pose.yaml" at 340 points. A phone's list is a screen of its own, and
    /// whole there too.
    func testTheEditorsFileNamesAreWholeAtTheLargestText() throws {
        launch("editor")
        // A phone shows the list as a screen of its own, behind the file: back to it.
        if UIDevice.current.userInterfaceIdiom == .phone {
            let back = app.backButton
            if back.waitForExistence(timeout: 5) { back.tap() }
        }
        // The list's, not the tab's: the leftmost.
        let names = app.staticTexts.matching(NSPredicate(format: "label == 'compose.yaml'")).allElementsBoundByIndex
        let name = names.filter(\.exists).min { $0.frame.minX < $1.frame.minX }
        XCTAssertNotNil(name, "compose.yaml in the file list")
        if UIDevice.current.userInterfaceIdiom == .phone {
            // A phone's list is the screen's width, and at the largest size a name wraps, as the
            // Files app's do; whole, never cut off.
            XCTAssertEqual(try clipped().filter { $0 == "compose.yaml" }, [], "\"compose.yaml\" is whole")
        } else {
            XCTAssertLessThan(name?.frame.height ?? .infinity, 100,
                              "\"compose.yaml\" is one line: \(String(describing: name?.frame))")
        }
    }

    func testTheLibrarysICloudFooterIsNotClippedAtTheLargestText() throws {
        launch()
        // At the foot of the sidebar, which an iPad opens on closed (the system's Show Sidebar).
        let footer = element("library-icloud-status")
        let showSidebar = app.buttons["Show Sidebar"].firstMatch
        if !footer.waitForExistence(timeout: 5), showSidebar.exists {
            showSidebar.tap()
        }
        XCTAssertTrue(footer.waitForExistence(timeout: 10), "the footer")
        XCTAssertEqual(try clipped().filter { $0.hasPrefix("Not synced") }, [], "the iCloud line")
    }
}
#endif
