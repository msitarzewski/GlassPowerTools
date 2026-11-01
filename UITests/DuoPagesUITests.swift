//
//  DuoPagesUITests.swift
//  GlassPowerToolsUITests
//
//  Two pages on an iPhone Duo held like a book (D93): a library on each, and whatever each opens.
//  Run on the Duo simulator held like a book (Device Hub: Partially Open); anywhere else there is
//  one page, and the tests skip. Driven from the demo surfaces, which connect to nothing.
//

#if os(iOS)
import XCTest

@MainActor
final class DuoPagesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Where page `index` is (a UI-test mark, `glass-page-<index>`).
    private func page(_ index: Int) -> CGRect { element("glass-page-\(index)").frame }

    private func launch(_ surface: String) throws {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh+database",
                                "--demo-open", surface]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        guard element("glass-page-1").waitForExistence(timeout: 30) else {
            throw XCTSkip("needs an iPhone Duo held like a book")
        }
        shoot("launched")
    }

    /// The terminal windows on screen, wherever they are.
    private var terminals: XCUIElementQuery {
        app.textViews.matching(NSPredicate(format: "label == 'Terminal'"))
    }

    /// The first of `query`'s elements on page `index`: left of the fold, or right of it, where
    /// the system's column, and the bar a page beside it puts there, count as the second page's.
    private func onPage(_ index: Int, _ query: XCUIElementQuery) -> XCUIElement? {
        let fold = (page(0).maxX, page(1).minX)
        return query.allElementsBoundByIndex.first { element in
            let middle = element.frame.midX
            return element.frame.width > 0 && (index == 0 ? middle < fold.0 : middle > fold.1)
        }
    }

    /// What is on screen, as the accessibility tree has it: a screenshot taken here on the Duo
    /// simulator comes out black.
    private func shoot(_ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func within(_ inner: CGRect, _ outer: CGRect) -> Bool {
        inner.minX >= outer.minX - 1 && inner.maxX <= outer.maxX + 1
    }

    /// A terminal on a page is the page's width. Its bar, kept off the fold for a terminal across
    /// both halves, was pushed past the page and made the terminal wider than it, its text clipped
    /// at both edges (2026-10-31).
    func testATerminalFitsItsPage() throws {
        try launch("terminal")
        let terminal = terminals.firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 30), "the terminal")
        sleep(2)
        XCTAssertTrue(within(terminal.frame, page(0)), "the terminal at \(terminal.frame) is wider than its page at \(page(0))")
    }

    /// A session is on one page at a time: chosen on the other, it moves there, and the page it
    /// left goes back to its library.
    func testASessionMovesToThePageThatAsks() throws {
        try launch("terminal")
        XCTAssertTrue(terminals.firstMatch.waitForExistence(timeout: 30), "the terminal")
        XCTAssertNotNil(onPage(0, terminals), "the terminal opened on the first page")

        // The second page's library: Active, and the terminal's window there.
        let active = try XCTUnwrap(onPage(1, app.staticTexts.matching(identifier: "Active")) ??
                                   onPage(1, app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Active'"))),
                                   "Active in the second page's library")
        active.tap()
        shoot("active")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'active-session-terminal:'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "the terminal's window under Active")
        rows.firstMatch.tap()
        sleep(2)
        shoot("chosen")

        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.onPage(1, self.terminals) != nil && self.onPage(0, self.terminals) == nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 15), .completed,
                       "the terminal is on the second page alone (\(terminals.count) shown)")
        XCTAssertNotNil(onPage(0, app.staticTexts.matching(identifier: "All Connections")),
                        "the first page went back to its library")
    }

    /// The page's handle: Use Both Pages puts a tool alone across both halves, the other page
    /// waiting under it, and Use Two Pages puts it back.
    func testUseBothPages() throws {
        try launch("terminal")
        let terminal = terminals.firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 30), "the terminal")
        let page = page(0)
        let handle = element("glass-page-handle-0")
        XCTAssertTrue(handle.waitForExistence(timeout: 10), "the first page's handle")
        handle.tap()
        let both = app.buttons["Use Both Pages"].firstMatch
        XCTAssertTrue(both.waitForExistence(timeout: 10), "Use Both Pages in the handle's menu")
        both.tap()
        let spread = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let terminal = self.terminals.firstMatch
            return terminal.exists && terminal.frame.maxX > page.maxX + 100
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [spread], timeout: 15), .completed,
                       "the terminal across both halves (\(terminals.firstMatch.frame), its page \(page))")
        XCTAssertFalse(element("glass-page-1").exists, "the other page waits under it")
        shoot("both")

        element("glass-page-handle-0").tap()
        let two = app.buttons["Use Two Pages"].firstMatch
        XCTAssertTrue(two.waitForExistence(timeout: 10), "Use Two Pages in the handle's menu")
        two.tap()
        let back = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.element("glass-page-1").exists && self.within(self.terminals.firstMatch.frame, self.page(0))
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 15), .completed, "two pages again, the terminal on its own")
    }

    /// Swap Pages: the terminal on the left goes to the right, the library comes to the left, and
    /// each keeps what it shows.
    func testSwapPages() throws {
        try launch("terminal")
        XCTAssertTrue(terminals.firstMatch.waitForExistence(timeout: 30), "the terminal")
        let fold = (page(0).maxX, page(1).minX)
        XCTAssertLessThan(terminals.firstMatch.frame.midX, fold.0, "the terminal starts on the left")
        element("glass-page-handle-0").tap()
        let swap = app.buttons["Swap Pages"].firstMatch
        XCTAssertTrue(swap.waitForExistence(timeout: 10), "Swap Pages in the handle's menu")
        swap.tap()
        let swapped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.terminals.firstMatch.exists && self.terminals.firstMatch.frame.midX > fold.1
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [swapped], timeout: 15), .completed, "the terminal on the right")
        let library = app.staticTexts.matching(identifier: "glass-library-scope-all-connections").firstMatch
        XCTAssertTrue(library.exists && library.frame.midX < fold.0, "the library on the left")
        shoot("swapped")
    }

    /// Show on the Other Page, from the second page's Active: the database it shows goes to the
    /// first page, which puts away its terminal for it.
    func testShowOnTheOtherPage() throws {
        try launch("pages")
        let queries = app.descendants(matching: .any).matching(identifier: "db-query-editor")
        XCTAssertTrue(queries.firstMatch.waitForExistence(timeout: 30), "the database")
        XCTAssertNotNil(onPage(1, queries), "the database opened on the second page")

        // The database's ⚡: the second page's library, on Active.
        let bolts = app.buttons.matching(identifier: "active-connections-bolt")
        let bolt = try XCTUnwrap(onPage(1, bolts), "the database's ⚡")
        bolt.tap()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'active-session-database:'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "the database under Active")
        shoot("active")
        rows.firstMatch.press(forDuration: 1.2)
        let other = app.buttons["Show on the Other Page"].firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 10), "Show on the Other Page in the row's menu")
        other.tap()
        sleep(2)
        shoot("shown")

        // Switch To opens a database's workspace at its root: its databases.
        let roots = app.navigationBars.matching(identifier: "Databases")
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.onPage(0, roots) != nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 15), .completed, "the database is on the first page")
        XCTAssertNil(onPage(0, terminals), "the first page put its terminal away for it")
    }
}
#endif
