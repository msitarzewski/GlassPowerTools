//
//  GlassSpatialColumnsUITests.swift
//  GlassPowerToolsUITests
//
//  The headset's own columns (W33): Connections, the database, the editor and Files lay out their
//  sidebar and content themselves so Glass can clear them, and give back what the system's split
//  view did — a sidebar toggle, the column's search field, a heading per column. Driven on the
//  visionOS simulator from seeded hosts and `--demo-open editor-project`, which connect to nothing.
//
//  The visionOS simulator cannot photograph from inside a test (rule 11): captures are taken from
//  outside with `Tools/Screenshots/shoot.sh`.
//

#if os(visionOS)
import XCTest

@MainActor
final class GlassSpatialColumnsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh|bravo@192.0.2.20:ssh"] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func attachTree(_ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// The toggle in the details' header hides the list and brings it back, as the split view's
    /// sidebar did; the list's title is a heading.
    func testConnectionsSidebarHidesAndComesBack() {
        launch()
        let alpha = element("host-row-alpha")
        XCTAssertTrue(alpha.waitForExistence(timeout: 30), "alpha is not in the library")
        let heading = app.staticTexts["All Connections"].firstMatch
        XCTAssertTrue(heading.exists, "the list has no title")
        XCTAssertTrue(heading.elementType == .staticText)

        let toggle = element("sidebar-toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no sidebar toggle in the details' header")
        toggle.tap()
        XCTAssertTrue(waitForAbsence(alpha), "the toggle did not hide the list")
        attachTree("sidebar-hidden")

        element("sidebar-toggle").tap()
        XCTAssertTrue(alpha.waitForExistence(timeout: 10), "the toggle did not bring the list back")
    }

    /// The list's own search field, where `.searchable` drew nothing on the headset.
    func testConnectionsSearchFieldFiltersTheList() {
        launch()
        XCTAssertTrue(element("host-row-bravo").waitForExistence(timeout: 30), "bravo is not in the library")
        let search = element("glass-library-search")
        XCTAssertTrue(search.waitForExistence(timeout: 10), "no search field above the list")
        search.tap()
        search.typeText("alp")
        XCTAssertTrue(waitForAbsence(element("host-row-bravo")), "the search did not filter bravo out")
        XCTAssertTrue(element("host-row-alpha").exists, "the search filtered out its own match")
        attachTree("searched")

        let clear = app.buttons["Clear text"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "no way to clear the search")
        clear.tap()
        XCTAssertTrue(element("host-row-bravo").waitForExistence(timeout: 10), "clearing did not bring bravo back")
    }

    /// The editor with a project: "Files" over the list, the project over its overview, and the
    /// toggle that hides the list with its filter.
    func testEditorColumnsHaveTheirTitlesAndTheToggle() {
        launch(["--demo-open", "editor-project"])
        let filter = element("editor-files-filter")
        XCTAssertTrue(filter.waitForExistence(timeout: 40), "the editor's file list has no filter field")
        XCTAssertTrue(app.staticTexts["Files"].firstMatch.exists, "the file list has no title")
        XCTAssertTrue(app.staticTexts["shop"].firstMatch.exists, "the overview's column is not titled with the project")
        attachTree("editor-project")

        let toggle = app.buttons.matching(identifier: "sidebar-toggle").allElementsBoundByIndex.first { $0.isHittable }
        guard let toggle else { return XCTFail("no sidebar toggle in reach") }
        toggle.tap()
        XCTAssertTrue(waitForAbsence(filter), "the toggle did not hide the file list")
    }
}
#endif
