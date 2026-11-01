//
//  WorkgroupServicesUITests.swift
//  GlassPowerToolsUITests
//
//  A saved workgroup with a database and no terminals (B-F40, 2026-11-01): the database added in
//  the workgroup's editor from the library, listed in the workgroup, and connected when it opens,
//  as the library's Connect connects it. Runs on an iPhone simulator.
//

#if os(iOS)
import XCTest

@MainActor
final class WorkgroupServicesUITests: XCTestCase {
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

    /// What is on screen, as the accessibility tree has it.
    private func shoot(_ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    func testAWorkgroupOpensItsDatabase() throws {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh+database"]
        app.launch()
        XCTAssertTrue(element("connection-library-settings").waitForExistence(timeout: 30), "the library")

        let workgroups = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'glass-library-panel-' AND label BEGINSWITH 'Workgroups'")).firstMatch
        XCTAssertTrue(workgroups.waitForExistence(timeout: 10), "Workgroups in the library")
        workgroups.tap()
        // The plus above the list.
        let new = element("connection-library-add-workgroup")
        let found = new.waitForExistence(timeout: 10)
        shoot("workgroups")
        XCTAssertTrue(found, "New Workgroup")
        new.tap()

        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the editor's name")
        name.tap()
        name.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        name.typeText("Data\n")
        let add = element("workgroup-add-service")
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Add Database or Desktop")
        add.tap()
        let database = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'alpha'")).firstMatch
        let listed = database.waitForExistence(timeout: 10)
        shoot("menu")
        XCTAssertTrue(listed, "alpha's database in the menu")
        database.tap()
        shoot("editor")
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.isEnabled, "a database alone is enough to save")
        save.tap()

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Data, 1 database or desktop'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the workgroup, saying what it holds")
        row.tap()
        XCTAssertTrue(app.staticTexts["Databases and Desktops"].waitForExistence(timeout: 10), "its databases in the detail")
        shoot("detail")
        let open = app.buttons["Open Workgroup"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Open Workgroup")
        open.tap()

        // Connected as Connect connects it: the database's workspace, its sign-in, or what the
        // database says of the service. The seeded machines' services carry no database settings,
        // so here it says that, of alpha's database, as Connect in the library does.
        let databaseScreens = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["db-workspace-tab-connection", "database-workspace-settings",
                                         "database-workspace-connections", "database-workspace-disconnect"]))
        let signIn = app.secureTextFields.firstMatch
        let answer = app.alerts["Database"].staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Database on alpha'")).firstMatch
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            databaseScreens.firstMatch.exists || signIn.exists || answer.exists
        }, object: nil)
        let result = XCTWaiter().wait(for: [opened], timeout: 30)
        shoot("opened")
        XCTAssertEqual(result, .completed, "the database was not asked to connect alpha's database")
    }
}
#endif
