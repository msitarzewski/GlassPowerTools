//
//  GlassDatabaseUITests.swift
//  GlassPowerToolsUITests
//
//  Stage 3: the first suite that opens a window on the Database capability. Everything the
//  capability could prove without a window was proven in `Tests/GlassDatabaseTests` — the SQL,
//  the row identity, the foreign-key pairing, the audit. What none of it proves is that the
//  *view* calls those paths with the row the user pointed at. That is what this file drives.
//
//  Gated exactly like `GlassTerminalUITests`: without a live database the whole suite skips with
//  a reason rather than failing. The variable names are the ones
//  `Tests/GlassDatabaseTests/LiveDatabaseIntegrationTests.swift` already defines, so one
//  `~/.config/gpt-db-test.env` serves both. Pass them to `xcodebuild test` as
//  `TEST_RUNNER_GPT_DB_TEST_*`.
//
//  **The password is read from the environment, typed into the app, and never written anywhere
//  else.** It is not in this source, not in an assertion message, not in a diagnostic dump, and
//  not on screen when a screenshot is taken — the field is a `SecureField` and every capture in
//  this file happens after the setup sheet has closed.
//
//  **Every write goes to the scratch database** (`GPT_DB_TEST_MYSQL_SCRATCH_DB` /
//  `GPT_DB_TEST_PG_SCRATCH_DB`), never to the seeded `gpt_test` fixture, which this suite only
//  ever reads — and in fact never even connects to. Fixture tables carry fixed `gpt_ui_*` names
//  and are dropped before they are created as well as after the assertions, so a run that dies
//  mid-test leaves at most one generation of tables behind and the next run removes them.
//  They stay clear of `gpt_live_*` (the engine suite's prefix), of `gpt_nav_*` (the live
//  foreign-key suite's), and of `teams`/`members` (the seed).
//
//  Three identifiers in the contract are shared surfaces rather than the things they are named
//  after, and this file treats each as a handle and never as evidence:
//
//  - `db-delete-confirm` / `db-delete-cancel` are the *row mutation* review, shared with cell
//    edits and TSV paste, with a button reading "Commit". Only the route in — the row's own
//    `db-row-menu-delete` — and the state of the server afterwards make a deletion test.
//  - `db-query-editor` is rendered by `DataTabView`, so a *table* tab has one too. Nothing here
//    reads its presence as proof that a SQL document is open.
//  - `db-query-run` is the shared `SQLRunControl`, present in both surfaces for the same reason.
//
//  Rule 21: this file never runs itself, and must not be run alongside another XCUITest target —
//  synthesised events go to the frontmost application.
//

import XCTest
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class GlassDatabaseUITests: XCTestCase {

    // MARK: - Fixture

    /// Which server a test is driving. The two differ in more than a port: PostgreSQL reports
    /// *schemas* from `databases()`, so the namespace the schema browser shows inside
    /// `gpt_scratch` is `public`, while on MySQL it is the database itself. Modelling that here
    /// rather than in each test is the same decision `LiveDB.fixtureNamespace` made.
    private enum Engine: String {
        case mysql = "MySQL"
        case postgresql = "PostgreSQL"

        /// The label of this engine's item in the setup sheet's Engine picker.
        var pickerTitle: String { rawValue }
        var defaultPort: String { self == .mysql ? "3306" : "5432" }
        /// Quoting differs, and a fixture script has to say which it is using.
        var quote: String { self == .mysql ? "`" : "\"" }
        var textType: String { self == .mysql ? "varchar(40)" : "text" }
    }

    private struct DatabaseFixture {
        let engine: Engine
        let host: String
        let port: String
        let user: String
        let password: String
        /// The database the service connects to: the scratch database on both engines.
        let database: String
        /// What the schema browser lists inside it — `gpt_scratch` on MySQL, `public` on PostgreSQL.
        let namespace: String
    }

    private var app: XCUIApplication!
    private var runID = UUID()
    /// Statements tearDown runs to leave the server as it was found, most-dependent first.
    /// Recorded by each test as soon as it has created something, so a failed assertion —
    /// which unwinds without running a `defer` — still gets cleaned up.
    private var pendingCleanupSQL: [String] = []
    /// The fixture the pending cleanup belongs to, so tearDown knows how to reach the editor.
    private var cleanupFixture: DatabaseFixture?

    /// SQL is pasted into the editor on the Mac, through the owner's own clipboard; put back after.
    private var clipboard: UITestClipboard?

    override func setUp() async throws {
        continueAfterFailure = false
        runID = UUID()
        pendingCleanupSQL = []
        cleanupFixture = nil
        try await MainActor.run { clipboard = try UITestClipboard() }
    }

    override func tearDown() async throws {
        await MainActor.run {
            dropPendingFixtures()
            clipboard?.restore()
            app?.terminate()
            #if os(macOS)
            let container = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.glasspowertools/Data/Library/Application Support/GlassPowerTools-Tests/\(runID.uuidString)")
            try? FileManager.default.removeItem(at: container)
            #endif
            app = nil
        }
    }

    /// Best effort, and deliberately not an assertion: a test that has already failed should
    /// report *its* failure, not a second one from the cleanup. What the cleanup could not do is
    /// recorded as an activity so the result bundle says so plainly.
    private func dropPendingFixtures() {
        guard !pendingCleanupSQL.isEmpty, let fixture = cleanupFixture, let app, app.state == .runningForeground else {
            if !pendingCleanupSQL.isEmpty {
                XCTContext.runActivity(named: "cleanup NOT run — the app was not usable; \(pendingCleanupSQL.count) DROP statement(s) skipped") { _ in }
            }
            return
        }
        let statements = pendingCleanupSQL
        pendingCleanupSQL = []
        guard openSQLEditor(timeout: 10) else {
            XCTContext.runActivity(named: "cleanup NOT run — no SQL editor; \(statements.count) DROP statement(s) skipped") { _ in }
            return
        }
        let ran = runStatements(statements, fixture: fixture, failOnError: false)
        XCTContext.runActivity(named: ran ? "cleanup ran \(statements.count) DROP statement(s)"
                                          : "cleanup attempted and did not complete cleanly") { _ in }
    }

    // MARK: - Gate

    private func fixture(_ engine: Engine) throws -> DatabaseFixture {
        let env = ProcessInfo.processInfo.environment
        func value(_ name: String) -> String? {
            env[name].flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let host = value("GPT_DB_TEST_HOST") else {
            throw XCTSkip("not run: no database test host configured (GPT_DB_TEST_HOST)")
        }
        switch engine {
        case .mysql:
            guard let password = value("GPT_DB_TEST_MYSQL_PASSWORD") else {
                throw XCTSkip("not run: no MySQL test password configured (GPT_DB_TEST_MYSQL_PASSWORD)")
            }
            let scratch = value("GPT_DB_TEST_MYSQL_SCRATCH_DB") ?? "gpt_scratch"
            return DatabaseFixture(engine: .mysql, host: host,
                                   port: value("GPT_DB_TEST_MYSQL_PORT") ?? "3306",
                                   user: value("GPT_DB_TEST_MYSQL_USER") ?? "gpt_test",
                                   password: password, database: scratch, namespace: scratch)
        case .postgresql:
            guard let password = value("GPT_DB_TEST_PG_PASSWORD") else {
                throw XCTSkip("not run: no PostgreSQL test password configured (GPT_DB_TEST_PG_PASSWORD)")
            }
            let scratch = value("GPT_DB_TEST_PG_SCRATCH_DB") ?? "gpt_scratch"
            // `databases()` reports schemas on PostgreSQL, so the browser shows `public`.
            return DatabaseFixture(engine: .postgresql, host: host,
                                   port: value("GPT_DB_TEST_PG_PORT") ?? "5432",
                                   user: value("GPT_DB_TEST_PG_USER") ?? "gpt_test",
                                   password: password, database: scratch, namespace: "public")
        }
    }

    // MARK: - Launch and element helpers (the conventions in GlassShellLocalHostUITests)

    @discardableResult
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", runID.uuidString] + extraArguments
        #if os(macOS)
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        #if os(macOS)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        #endif
        self.app = app
        return app
    }

    /// Containers that hold no Touch Bar.
    ///
    /// macOS mirrors an alert's default buttons and some toolbar items onto the Touch Bar, and
    /// the proxy is a *second* element carrying the same title and identifier as the real
    /// control while refusing every click ("cannot be called with Touch Bar elements"). It is
    /// not a descendant of a window, a menu or the menu bar, so every lookup in this file looks
    /// inside those first. Queries rather than enumerated elements, so a lookup stays cheap.
    private var touchBarFreeScopes: [XCUIElementQuery] {
        [app.windows, app.menus, app.menuBars, app.sheets, app.dialogs]
    }

    /// An element by accessibility identifier — and never the Touch Bar's copy of it.
    ///
    /// A bare `descendants(matching: .any).matching(identifier:).firstMatch` returns whichever
    /// of the two the tree happens to yield first, which is not stable and is unclickable half
    /// the time. The application-wide query stays as a fallback for anything that lives outside
    /// the scopes above.
    private func element(_ identifier: String) -> XCUIElement {
        for scope in touchBarFreeScopes {
            let matches = scope.descendants(matching: .any).matching(identifier: identifier)
            if matches.firstMatch.exists { return onScreen(matches) }
        }
        return onScreen(app.descendants(matching: .any).matching(identifier: identifier))
    }

    /// The match a person can reach. Every open tab keeps its views, hidden from VoiceOver but
    /// not from XCUITest: on the iPhone the first match for `db-query-run` was a hidden tab's Run
    /// (hit point {-1, -1}), the tap went nowhere, and the fixture statements never ran
    /// (2026-10-25); the editor was the same, two in one frame.
    private func onScreen(_ matches: XCUIElementQuery) -> XCUIElement {
        if matches.count > 1, let shown = matches.allElementsBoundByIndex.first(where: \.isHittable) { return shown }
        return matches.firstMatch
    }

    /// A control by its visible title, in the same Touch-Bar-free scopes: buttons first, then
    /// menu items. Returns nil rather than an unclickable proxy.
    private func titled(_ title: String, timeout: TimeInterval = 5) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for scope in touchBarFreeScopes {
                // `.firstMatch` is required, not a shortcut: `scope` is a QUERY over every window
                // (or menu, or sheet), so `scope.buttons[title]` can match in several of them at
                // once. `.exists` answers true for a multi-match query while `.click()` refuses it
                // with "Multiple matching elements found" — so without this the lookup succeeds and
                // the press fails. Resolving to the first match is safe here precisely because the
                // scope already excludes the Touch Bar; that was the ambiguity worth removing.
                let button = scope.buttons[title].firstMatch
                if button.exists { return button }
                let item = scope.menuItems[title].firstMatch
                if item.exists { return item }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    /// macOS: `tap()` compiles but does not drive SwiftUI controls under Xcode 27; `click()` does.
    private func press(_ e: XCUIElement) {
        #if os(macOS)
        e.click()
        #else
        e.tap()
        #endif
    }

    @discardableResult
    private func press(_ identifier: String, timeout: TimeInterval = 10,
                       file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = element(identifier)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(identifier)", file: file, line: line)
        // Resolved again now that it exists: while nothing matched, the first resolution fell
        // through to the application-wide query, and that one does not exclude the Touch Bar.
        let resolved = element(identifier)
        press(resolved)
        return resolved
    }

    /// Opens an element's context menu: a right-click on the Mac, a long press on touch.
    ///
    /// `rightClick()` scrolls the element to visible first, exactly as `click()` does, and in the
    /// results grid that scroll resolves to a `ScrollView` with no hit point. Right-clicking the
    /// element's centre COORDINATE skips scroll-to-visible entirely and is delivered as-is.
    private func contextPress(_ e: XCUIElement) {
        #if os(macOS)
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        #else
        e.press(forDuration: 1.1)
        #endif
    }

    private func firstExisting(_ candidates: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.exists { return candidate }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    @discardableResult
    private func waitUntil(_ description: String, timeout: TimeInterval = 15,
                           _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        XCTContext.runActivity(named: "timed out waiting for \(description)") { _ in }
        return false
    }

    /// Our own window only (project rule 11); see `UITestCapture.swift`.
    private func snap(_ name: String) {
        guard let app else { return }
        let sheet = app.sheets.firstMatch
        let subject = sheet.exists ? sheet : (workspaceWindow ?? app.windows.firstMatch)
        captureOwnWindow(subject, app: app, name: "database-\(name)")
    }

    /// Attaches an inventory of the tree so a failure can be diagnosed from the result bundle.
    /// Never prints a field's value on a form that has held the password.
    #if !os(macOS)
    /// Run, from the bar or, where the bar is narrow (the Duo's outer display), from its More:
    /// there iOS's column holds Back, More and Close, and Run is inside More (2026-10-24).
    private func pressRun() {
        let run = element("db-query-run")
        if run.waitForExistence(timeout: 3) {
            // On the iPhone Run is in the bottom bar, behind the keyboard while the editor has it:
            // the tap had no hit point and nothing ran, and XCUITest went on as if it had landed
            // (2026-10-25). `isHittable` is no guide (it said yes under the keyboard), the frames
            // are. A person puts the keyboard away first, with the key the editor puts above it.
            let keyboard = app.keyboards.firstMatch
            let covered = { keyboard.exists && keyboard.frame.intersects(run.frame) }
            if covered() { putKeyboardAway() }
            XCTAssertFalse(covered(), "Run is behind the keyboard")
            press(run)
            return
        }
        let more = app.buttons.matching(NSPredicate(format: "identifier IN %@",
                                                    ["BottomOverflowBarButtonItem", "OverflowBarButtonItem"])).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "neither Run nor the bar's More")
        press(more)
        // In More the control keeps neither its identifier nor its accessibility label ("Run
        // Statement"): the entry is its visible title, an en space and "Statement" (2026-10-25,
        // Duo; the label is with the owner). Matched by that title as a person reads it.
        let item = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'db-query-run' OR label BEGINSWITH 'Run' OR label ENDSWITH 'Statement'")).firstMatch
        if !item.waitForExistence(timeout: 5) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "more-menu"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(item.exists, "Run in the bar's More")
        press(item)
        // A menu with a primary action can arrive as a submenu of its entries. The editor holds one
        // statement here, so Run All Statements runs exactly that.
        let all = app.buttons["Run All Statements"].firstMatch
        if all.waitForExistence(timeout: 2) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "run-submenu"; tree.lifetime = .keepAlways; add(tree)
            press(all)
        }
    }

    /// The key the editor puts above the keyboard, as a person puts it away.
    private func putKeyboardAway() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let hide = element("editor-hide-keyboard")
        if hide.waitForExistence(timeout: 2) { press(hide) }
        _ = waitUntil("the keyboard to go", timeout: 5) { !keyboard.exists }
    }
    #endif

    private func dumpTree(_ name: String) {
        guard let app else { return }
        var lines: [String] = []
        #if os(macOS)
        lines.append("windows=\(app.windows.count) sheets=\(app.sheets.count) dialogs=\(app.dialogs.count)")
        for w in app.windows.allElementsBoundByIndex { lines.append("window: '\(w.title)'") }
        lines.append("buttons: " + app.buttons.allElementsBoundByIndex.prefix(60)
            .map { "'\($0.label)'/'\($0.identifier)'" }.joined(separator: ", "))
        lines.append("staticTexts: " + app.staticTexts.allElementsBoundByIndex.prefix(60)
            .map { "'\($0.label.prefix(40))'/'\($0.identifier)'" }.joined(separator: ", "))
        lines.append("menuItems: " + app.menuItems.allElementsBoundByIndex.prefix(40)
            .map { "'\($0.label)'" }.joined(separator: ", "))
        #else
        // Enumerating `app.buttons` off macOS raises an automation type mismatch on a SwiftUI
        // Picker (iOS 27) and fails the test from inside the diagnostic; print the subtree instead.
        lines.append(app.debugDescription)
        #endif
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "database-tree-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func enterAllConnections() {
        #if os(visionOS)
        let scope = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", "All",
                        XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.tab.rawValue)).firstMatch
        #else
        let scope = app.libraryScope("all-connections")
        #endif
        // Only where the scopes are showing: after a save an iPhone is already on the results.
        // Callers check where they arrived (the row they look for next).
        if scope.waitForExistence(timeout: 5) { press(scope) }
    }

    private func setField(_ identifier: String, to value: String) {
        let field = element(identifier)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "missing \(identifier)")
        if (field.value as? String) == value { return }
        #if os(iOS)
        field.replaceText(with: value, in: app)
        if field.elementType != .secureTextField {
            XCTAssertEqual(field.value as? String, value, "\(identifier) reads what was typed")
        }
        #else
        press(field)
        #if os(macOS)
        app.typeKey("a", modifierFlags: .command)
        #else
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        #endif
        field.typeText(value)
        #endif
    }


    /// Expands one of the setup sheet's disclosure rows (`GlassFormDisclosureStyle`).
    private func expandDisclosure(_ row: XCUIElement) {
        if "\(row.value ?? "")" == "expanded" { return }
        press(row)
        _ = waitUntil("the disclosure to expand", timeout: 3) { "\(row.value ?? "")" == "expanded" }
    }

    /// visionOS offers to save a typed password in iCloud Keychain once the sheet commits.
    private func dismissSystemPasswordPrompt() {
        #if os(macOS)
        var targets: [XCUIApplication] = []
        #else
        var targets = [XCUIApplication(bundleIdentifier: "com.apple.springboard")]
        #endif
        if let app { targets.append(app) }
        for target in targets {
            let notNow = target.buttons["Not Now"].firstMatch
            if notNow.waitForExistence(timeout: 1) { notNow.tap(); return }
        }
    }

    // MARK: - Setting the service up

    /// The name given to the database service. Set so the connection has a stable, readable
    /// identity in the workspace's own header and in screenshots — *not* as a way to find the
    /// window, which carries no title at all (see `workspaceWindow`).
    private let serviceName = "gptdb"

    /// Adds the host and its database service in the one setup sheet, the way a person does:
    /// name, address, the Database tab, then that tab's fields. No connection is made here.
    private func addDatabaseHost(_ fixture: DatabaseFixture) {
        let empty = element("connection-library-add-host-empty")
        if empty.waitForExistence(timeout: 4) { press(empty) } else { press("connection-library-add-host") }
        setField("host-editor-name", to: "dbhost")
        setField("host-editor-address", to: fixture.host)

        // Choosing the tab is what adds the service; there is no separate toggle.
        let sections = element("setup-sections")
        XCTAssertTrue(sections.waitForExistence(timeout: 10), "service tabs")
        let tab = sections.buttons["Database"].exists ? sections.buttons["Database"] : sections.radioButtons["Database"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Database tab")
        press(tab)

        // Engine first: changing it resets the port, the username and the database, so anything
        // typed before it would be thrown away (`DatabaseServiceDraft.engineDidChange`).
        chooseEngine(fixture.engine)
        setField("add-database-database", to: fixture.database)
        setField("add-database-username", to: fixture.user)
        let password = element("add-database-password")
        XCTAssertTrue(password.waitForExistence(timeout: 10), "password field")
        press(password)
        password.typeText(fixture.password)

        // Name and port live under Advanced. The name is set so the workspace window has a
        // title this test can find; the port only when it differs from the engine's default.
        let advanced = element("setup-advanced-database")
        if advanced.waitForExistence(timeout: 4) { expandDisclosure(advanced) }
        setField("add-database-name", to: serviceName)
        if fixture.port != fixture.engine.defaultPort {
            setField("add-database-port", to: fixture.port)
        }

        #if os(iOS)
        app.tapUntilSheetCloses("host-editor-save")
        #else
        press("host-editor-save")
        #endif
        dismissSystemPasswordPrompt()
        XCTAssertTrue(element("host-editor-save").waitForNonExistence(timeout: 20), "the sheet closes after Save")
    }

    private func chooseEngine(_ engine: Engine) {
        let picker = element("add-database-engine")
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "engine picker")
        // The choice is the picker's value on some iOS versions and in its label ("Engine, MySQL")
        // on others, the Duo's 27.1 among them: read both.
        func shown() -> String { "\(picker.label) \(picker.value ?? "")" }
        if shown().localizedCaseInsensitiveContains(engine.pickerTitle) { return }
        press(picker)
        let item = titled(engine.pickerTitle, timeout: 6)
            ?? firstExisting(touchBarFreeScopes.map { $0.staticTexts[engine.pickerTitle] }, timeout: 2)
        if let item { press(item) } else { dumpTree("engine-menu") }
        XCTAssertTrue(waitUntil("the engine picker to read \(engine.pickerTitle)", timeout: 5) {
            shown().localizedCaseInsensitiveContains(engine.pickerTitle)
        }, "the Engine picker did not take \(engine.pickerTitle)")
    }

    /// Opens the host's detail and connects its database service. Returns once a workspace
    /// surface for the connection is on screen.
    @discardableResult
    private func connectToDatabase(_ fixture: DatabaseFixture) -> Bool {
        if !element("host-add-service").exists {
            enterAllConnections()
            press("host-row-dbhost")
        }
        let connect = element("host-service-connect-database")
        XCTAssertTrue(connect.waitForExistence(timeout: 15), "Connect on the database service row")
        press(connect)
        let opened = waitForWorkspace(fixture)
        if !opened {
            snap("90-workspace-not-open")
            dumpTree("workspace-not-open")
            if let failure = connectionFailureText() {
                XCTFail("the database did not connect: \(failure)")
            } else {
                XCTFail("no database workspace appeared within 45 s")
            }
        }
        return opened
    }

    /// The workspace is live when its schema sidebar lists the namespace the fixture expects.
    /// That is a stronger signal than a window appearing: the sidebar cannot list a database
    /// without a `databases()` round trip against the server.
    private func waitForWorkspace(_ fixture: DatabaseFixture) -> Bool {
        waitUntil("the workspace to list \(fixture.namespace)", timeout: 45) {
            element("db-schema-database-\(fixture.namespace)").exists
        }
    }

    #if os(macOS)
    /// The workspace window: found by what it contains, never by its title.
    ///
    /// It has no title to match on. `DatabaseWorkspaceView` applies `.toolbar(removing: .title)`
    /// on macOS (`DatabaseWorkspaceView.swift:287`) and hides the toolbar background, so naming
    /// the service and looking for that name finds nothing even with the workspace plainly on
    /// screen. The schema sidebar and the SQL editor are the things only this window has, so
    /// either one identifies it.
    ///
    /// It is a genuinely separate window — `GlassDatabaseScenes.swift:209` opens the
    /// `database-workspace` group — so closing the window that holds the sidebar cannot take the
    /// library down with it.
    private var workspaceWindow: XCUIElement? {
        guard let app else { return nil }
        let marker = NSPredicate(format: "identifier BEGINSWITH %@ OR identifier == %@",
                                 "db-schema-database-", "db-query-editor")
        for window in app.windows.allElementsBoundByIndex where window.exists {
            if window.descendants(matching: .any).matching(marker).firstMatch.exists { return window }
        }
        return nil
    }
    #else
    private var workspaceWindow: XCUIElement? { nil }
    #endif

    private func connectionFailureText() -> String? {
        let candidates = [app.dialogs.firstMatch, app.alerts.firstMatch, app.sheets.firstMatch]
        guard let alert = candidates.first(where: { $0.exists }) else { return nil }
        var parts: [String] = []
        for text in alert.staticTexts.allElementsBoundByIndex {
            let content = text.label.isEmpty ? ((text.value as? String) ?? "") : text.label
            if !content.isEmpty { parts.append(content) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    // MARK: - Driving SQL through the app's own editor

    /// Opens a SQL editor tab. The overview, the database tab and an existing editor all carry
    /// the same "SQL Editor" toolbar button on the Mac; the sidebar's database context menu is
    /// the fallback, and the only path on touch.
    ///
    /// A *table* tab carries an editor of its own under the same identifier, so this never takes
    /// the presence of `db-query-editor` as proof that a SQL document is open — it asks for one.
    @discardableResult
    private func openSQLEditor(timeout: TimeInterval = 15) -> Bool {
        if let toolbar = titled("SQL Editor", timeout: 3) {
            press(toolbar)
            if queryEditor.waitForExistence(timeout: timeout) { return true }
        }
        let database = app.windows.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "db-schema-database-")).firstMatch
        if database.exists {
            contextPress(database)
            let item = titled("Open SQL Editor")
            if let item { press(item) } else { dismissAnyOpenMenu() }
        }
        return queryEditor.waitForExistence(timeout: timeout)
    }

    /// The SQL editor, as a **text view**.
    ///
    /// The identifier is set on the underlying `NSTextView`/`UITextView`
    /// (`GlassEditorAdapters.swift:342` and `:444`, threaded from
    /// `TableDetailView.swift:1612`), not on the SwiftUI representable — on the Mac the
    /// enclosing `NSScrollView` is a separate element and carries no value. Asking for the text
    /// view by name is therefore the query that can return SQL; a generic descendant search can
    /// land on the wrapper.
    /// On the iPhone a second SQL editor sat over the first in the same frame, the first still
    /// holding its INSERT, and a query for the one editor matched two (2026-10-25): `onScreen`.
    private var queryEditor: XCUIElement { onScreen(app.textViews.matching(identifier: "db-query-editor")) }

    /// Replaces the editor's text. Pasted on the Mac rather than typed: a syntax-aware editor
    /// that completes brackets or quotes would corrupt typed SQL, and the fixture scripts are
    /// full of both.
    private func setEditorText(_ sql: String) {
        let editor = queryEditor
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "SQL editor")
        press(editor)
        #if os(macOS)
        app.typeKey("a", modifierFlags: .command)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sql, forType: .string)
        app.typeKey("v", modifierFlags: .command)
        #else
        // Select All, then type over it. Deleting backwards from the tap left whatever followed the
        // cursor, because a tap puts it where it lands: the server got a CREATE with the end of
        // the DROP before it, "near 'IF EXISTS `gpt_scratch`.`gpt_ui_rows`'" (2026-10-25, iPhone).
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText(sql)
        XCTAssertTrue(waitUntil("the editor to hold the statement", timeout: 5) { editorText() == sql },
                      "the editor holds ‘\(editorText().prefix(160))’, not the statement typed")
        #endif
    }

    /// What the editor currently holds, and **only** from the text view's own `value`.
    ///
    /// Deliberately no fallback to the static texts a syntax-highlighted line might expose: a
    /// fallback would let the draft test pass while the value plumbing was broken, and whether
    /// `value` returns SQL at all is itself under test (see
    /// `testTheSQLEditorPublishesItsTextAsItsValue`).
    private func editorText() -> String {
        let editor = queryEditor
        guard editor.exists else { return "" }
        return (editor.value as? String) ?? ""
    }

    /// Runs the statements through the running app. On the Mac the whole script goes in at once
    /// and Query ▸ Run All Statements executes it; elsewhere each statement is run on its own,
    /// because the run control's "Run All" lives inside a toolbar menu rather than a menu bar.
    ///
    /// Returns whether every statement completed without the editor showing an error.
    @discardableResult
    private func runStatements(_ statements: [String], fixture: DatabaseFixture,
                               mode: ScriptMode = .oneAtATime,
                               failOnError: Bool = true,
                               file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard !statements.isEmpty else { return true }
        #if os(macOS)
        if mode == .asOneScript {
            return runOnce(statements.joined(separator: ";\n") + ";", all: true,
                           failOnError: failOnError, file: file, line: line)
        }
        #endif
        for statement in statements {
            guard runOnce(statement, all: false, failOnError: failOnError, file: file, line: line) else { return false }
        }
        return true
    }

    private func runOnce(_ sql: String, all: Bool, failOnError: Bool,
                         file: StaticString, line: UInt) -> Bool {
        setEditorText(sql)
        #if os(macOS)
        if all {
            guard runAllFromTheQueryMenu(failOnError: failOnError, file: file, line: line) else { return false }
        } else {
            press("db-query-run")
        }
        #else
        pressRun()
        #endif

        // DDL and DML are classified, so the editor asks before it runs them.
        // Short on purpose. The confirmation is set synchronously when the click lands, so it is
        // either up almost at once or not coming — and with every statement now run on its own,
        // each SELECT (which is not classified, so never asks) would otherwise pay this in full.
        let execute = titled("Execute", timeout: 3)
        if let execute { press(execute) }

        // The run control is disabled while a statement is in flight, so its return is the
        // "finished" signal, and the error banner is the only "it went wrong" signal the editor
        // gives. The absence of a banner is not proof of success, which is why every caller
        // asserts the effect on the data rather than the outcome of the run.
        let run = element("db-query-run")
        let failed = app.windows.buttons.matching(NSPredicate(format: "label == %@", "Dismiss query error")).firstMatch
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        _ = waitUntil("the run to finish", timeout: 90) { failed.exists || !run.exists || run.isEnabled }
        // A settle, not a wait for a condition: the banner not appearing is the good case here.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        if failed.exists {
            let detail = errorBannerText()
            snap("91-sql-error")
            if failOnError {
                XCTFail("the editor reported an error running the fixture SQL: \(detail)", file: file, line: line)
            } else {
                XCTContext.runActivity(named: "cleanup SQL reported: \(detail)") { _ in }
            }
            press(failed)
            return false
        }
        return true
    }

    #if os(macOS)
    /// Query ▸ Run All Statements. Clicked in the menu bar rather than typed as ⇧⌘⏎ so a
    /// disabled item is visible as a failure here instead of as a silent no-op later.
    private func runAllFromTheQueryMenu(failOnError: Bool, file: StaticString, line: UInt) -> Bool {
        let menu = app.menuBars.menuBarItems["Query"].firstMatch
        guard menu.waitForExistence(timeout: 5) else {
            if failOnError { XCTFail("no Query menu in the menu bar", file: file, line: line) }
            return false
        }
        press(menu)
        let item = app.menuBars.menuItems["Run All Statements"].firstMatch
        guard item.waitForExistence(timeout: 5) else {
            if failOnError { XCTFail("no Run All Statements item", file: file, line: line) }
            return false
        }
        guard item.isEnabled else {
            // Disabled means the workspace does not consider the editor runnable — a real
            // finding, not a flake, so say so rather than pressing a dead item.
            app.typeKey(.escape, modifierFlags: [])
            if failOnError {
                XCTFail("Run All Statements is disabled with SQL in the editor", file: file, line: line)
            }
            return false
        }
        press(item)
        return true
    }
    #endif

    private func errorBannerText() -> String {
        // The banner's detail is the server's message. It carries no credential — the password
        // is never part of a statement this file builds — but it is kept to one line anyway.
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label)
            .filter { $0.count > 8 && !$0.isEmpty }
        return texts.suffix(3).joined(separator: " | ").prefix(300).description
    }

    // MARK: - Schema browser

    /// Expands a database in the sidebar so its tables are listed. The disclosure triangle is a
    /// sibling of the identified label, so select the row and open it with the keyboard — the
    /// same thing the arrow key does in any outline — and fall back to the triangle if the row
    /// exposes one.
    /// Expands one database in the schema sidebar so its tables exist to be found.
    ///
    /// The sidebar is an `NSOutlineView`, and the shape matters:
    ///
    /// ```
    /// OutlineRow
    ///   StaticText,        identifier: 'db-schema-database-gpt_scratch'
    ///   DisclosureTriangle, identifier: 'NSOutlineViewDisclosureButtonKey', value: 0
    /// ```
    ///
    /// The identifier is on the **StaticText**; the expanded state is on a **sibling** triangle, as
    /// `value` `0` or `1`. So neither the row's own `value` nor a press on it says anything about
    /// whether the database is open.
    ///
    /// This previously took `app.outlines.firstMatch.disclosureTriangles.firstMatch` — the first
    /// triangle of the first outline. Three outlines are on screen at that moment (the library
    /// sidebar, the schema sidebar, the detail list), so it expanded whatever happened to come
    /// first and never the database asked for. Every table lookup then failed, 20 seconds at a
    /// time, and reported itself as a grid that would not load.
    /// Any table row in the sidebar. While a database is collapsed there are none at all — the
    /// rows do not exist in the tree, as opposed to existing offscreen — so this is the outcome
    /// expansion is for.
    private var anyTableRowExists: Bool {
        app.windows.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "db-schema-table-")).firstMatch.exists
    }

    #if os(macOS)
    /// The outline row carrying a database's label, and that row's own disclosure triangle.
    ///
    /// **Measured to match nothing on this build**: the activity log reads "no outline row for
    /// gpt_scratch" even with the sidebar plainly listing it. The identified `StaticText` is not
    /// reachable through `outlineRows.containing(.staticText, identifier:)`, so the triangle —
    /// and with it the only direct read of the expanded state — cannot be addressed. Kept for
    /// the diagnostic it prints, not because anything depends on it.
    private func disclosure(for name: String) -> (row: XCUIElement, triangle: XCUIElement) {
        let row = app.outlineRows.containing(.staticText, identifier: "db-schema-database-\(name)").firstMatch
        return (row, row.disclosureTriangles.firstMatch)
    }

    private func disclosureState(_ name: String) -> String {
        let (row, triangle) = disclosure(for: name)
        guard row.exists else { return "no outline row for \(name)" }
        guard triangle.exists else { return "row present (enabled=\(row.isEnabled)), no disclosure triangle" }
        return "triangle value=\(triangle.value.map { "\($0)" } ?? "nil") enabled=\(triangle.isEnabled) "
            + "hittable=\(triangle.isHittable) frame=\(triangle.frame) | row enabled=\(row.isEnabled) "
            + "hittable=\(row.isHittable) frame=\(row.frame)"
    }
    #endif

    /// Whether a database's disclosure is open, read from the tree rather than inferred.
    ///
    /// The table rows are the signal. The triangle's `value` would be the more direct read, but
    /// the triangle cannot be addressed on this build (see `disclosure(for:)`), so it is asked
    /// for only as a bonus. `expected` names the row the caller is actually after, which is
    /// exact; without it any table row counts, which is only sound because a test expands one
    /// database and no more.
    private func databaseIsExpanded(_ name: String, expecting expected: String? = nil) -> Bool {
        #if os(macOS)
        let triangle = disclosure(for: name).triangle
        if triangle.exists, "\(triangle.value ?? "")" == "1" { return true }
        #endif
        if let expected { return element("db-schema-table-\(expected)").exists }
        return anyTableRowExists
    }

    /// Expands a database in the sidebar so its tables are listed, and proves it opened from the
    /// tree rather than from whatever is asserted next.
    ///
    /// The sidebar is a SwiftUI `List` of `DisclosureGroup`s bridged to an `NSOutlineView`
    /// (`SchemaBrowserView.swift:337`). The contract identifier is on the group's *label*, which
    /// surfaces as a `StaticText`; while the database is collapsed `db-schema-table-*` is not in
    /// the tree at all.
    ///
    /// **Selecting the row and pressing right arrow is the path that works** — measured, run 7.
    /// It is `NSOutlineView`'s own expansion and goes through the same `isExpanded` binding a
    /// click on the triangle would. The two fallbacks below have never been seen to do anything:
    /// the triangle is unaddressable on this build, and the double-click is a last resort with a
    /// side effect. They are retained only so a change to the hierarchy does not leave this with
    /// a single untested route.
    @discardableResult
    private func expandDatabase(_ name: String, expecting expected: String? = nil) -> Bool {
        let identifier = "db-schema-database-\(name)"
        let label = element(identifier)
        XCTAssertTrue(label.waitForExistence(timeout: 20), "the sidebar lists \(name)")
        if databaseIsExpanded(name, expecting: expected) { return true }

        #if os(macOS)
        // 1 — the keyboard, through the outline's own expansion. The one that works.
        if attemptExpansion(name, expected, "select the row and press right arrow", gesture: {
            press(label)
            app.typeKey(.rightArrow, modifierFlags: [])
        }) { return true }

        // 2 — the triangle, if a later build ever exposes one.
        if attemptExpansion(name, expected, "click the disclosure triangle", gesture: {
            let triangle = disclosure(for: name).triangle
            if triangle.exists {
                triangle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
        }) { return true }

        // 3 — last resort, with a side effect worth naming: the label's own
        // `simultaneousGesture(TapGesture(count: 2))` opens a database tab
        // (`SchemaBrowserView.swift:374`). The caller opens the table tab afterwards regardless,
        // so the stray database tab changes nothing later.
        if attemptExpansion(name, expected, "double-click the label (also opens a database tab)", gesture: {
            if label.exists { label.doubleClick() }
        }) { return true }

        XCTContext.runActivity(named: "after every attempt on \(name): \(disclosureState(name))") { _ in }
        dumpTree("sidebar-would-not-expand-\(name)")
        return false
        #else
        // The compact browser is a navigation list, not an outline: pressing the row pushes the
        // database's table list rather than disclosing it in place.
        press(label)
        return waitUntil("the table list for \(name)", timeout: 15) {
            databaseIsExpanded(name, expecting: expected)
        }
        #endif
    }

    #if os(macOS)
    /// Runs one candidate gesture and reports whether the disclosure actually opened, recording
    /// the attempt either way.
    private func attemptExpansion(_ name: String, _ expected: String?, _ description: String,
                                  gesture: () -> Void) -> Bool {
        gesture()
        let opened = waitUntil("\(name) to expand after \(description)", timeout: 6) {
            databaseIsExpanded(name, expecting: expected)
        }
        XCTContext.runActivity(named: opened
            ? "expanded \(name) by: \(description)"
            : "did not expand \(name) by: \(description) — \(disclosureState(name))") { _ in }
        return opened
    }
    #endif

    /// Opens a table's Data tab through the sidebar's own "Browse Data" action, which is the
    /// single deliberate open — a double-click races the single-click preview.
    private func openTable(_ table: String, in database: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        let row = element("db-schema-table-\(table)")
        if !row.waitForExistence(timeout: 5) {
            // On the iPhone a table's data is pushed over the schema list, and a foreign-key
            // follow leaves the test there (2026-10-25).
            showSchemaList(database)
            // The tables are not in the tree at all while the database is collapsed, so a
            // missing row here is a question about the disclosure and not about the table.
            guard expandDatabase(database, expecting: table) else {
                XCTFail("the schema sidebar's disclosure for ‘\(database)’ did not open under any "
                        + "synthesized gesture — right arrow on the selected row, a click on the "
                        + "disclosure triangle, a coordinate click on it, and a coordinate click on "
                        + "the row's leading edge were all tried and the triangle stayed at 0. The "
                        + "attempt-by-attempt state is in this test's activities. No table can be "
                        + "opened from the sidebar until this is resolved.",
                        file: file, line: line)
                return
            }
            _ = row.waitForExistence(timeout: 20)
        }
        XCTAssertTrue(row.exists,
                      "‘\(database)’ is expanded but ‘\(table)’ is not among its rows",
                      file: file, line: line)
        // On the iPhone a table's actions are its row's "…" menu; a press on the row opened the
        // table's preview instead (2026-10-25). The iPad's sidebar row has the context menu.
        let actions = row.buttons["Table Actions"].firstMatch
        if actions.exists { press(actions) } else { contextPress(row) }
        if let browse = titled("Browse Data") {
            press(browse)
        } else {
            dismissAnyOpenMenu()
            #if os(macOS)
            row.doubleClick()
            #else
            row.tap(); row.tap()
            #endif
        }
        let dataTab = element("db-tab-data")
        #if os(macOS)
        // Toolbar toggles: present as soon as the table tab is up.
        XCTAssertTrue(dataTab.waitForExistence(timeout: 20), "the table opened with its tabs")
        press(dataTab)
        #else
        // On touch the five tab rows live inside a view Menu and do not exist until it is
        // opened, so their absence is not a missing identifier. Data is the tab a table opens
        // on, so select it when it is reachable and otherwise stay where the app already is.
        if dataTab.waitForExistence(timeout: 5) {
            press(dataTab)
        } else {
            XCTContext.runActivity(named: "db-tab-data not in the tree — the tab rows are behind the view Menu on this platform; continuing on the default Data tab") { _ in }
        }
        #endif
    }

    /// Re-reads the table list for a database after the editor has created something in it.
    private func refreshDatabase(_ name: String) {
        showSchemaList(name)
        let row = element("db-schema-database-\(name)")
        // Not a quiet return: without the refresh the new table is not listed, and the failure
        // surfaced later as "the sidebar lists …" with the cause gone (2026-10-25, iPhone).
        guard row.waitForExistence(timeout: 10) else {
            XCTFail("the schema list does not show \(name) to refresh it")
            return
        }
        contextPress(row)
        if let refresh = titled("Refresh") ?? titled("Refresh Tables", timeout: 2) {
            press(refresh)
        } else {
            dismissAnyOpenMenu()
        }
    }

    /// On the iPhone the schema list is a level of its own, behind the SQL editor; on the Mac and
    /// the iPad it is the sidebar beside it. Back, as a person goes, until it shows.
    private func showSchemaList(_ name: String) {
        #if os(iOS)
        let row = element("db-schema-database-\(name)")
        for _ in 0..<3 where !row.waitForExistence(timeout: 2) {
            let back = app.backButton
            guard back.exists else { break }
            press(back)
        }
        #endif
    }

    /// A context menu left open covers everything under it, so a path that could not find its
    /// item must close the menu before trying something else.
    private func dismissAnyOpenMenu() {
        #if os(macOS)
        app.typeKey(.escape, modifierFlags: [])
        #else
        // A menu on touch is dismissed by a tap outside it; the app's own frame is the target,
        // never a coordinate on the display (project rule 11's sibling: stay inside our window).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        #endif
    }

    // MARK: - Grid

    /// A data cell as the person reads it: `<n>` is the row number in the gutter, not a page
    /// offset. `Text` publishes its string as the element's label, so take either.
    /// The value a person reads in the cell.
    ///
    /// The cell's accessibility LABEL is `"<column>: <value>"` (`TableDetailView.swift:3135`), and
    /// deliberately so — VoiceOver has to speak the column name with the value, because a grid cell
    /// read aloud on its own means nothing. That prefix is stripped here rather than matched
    /// against, so an expectation in a test reads the way the cell looks on screen.
    ///
    /// Getting this wrong is expensive and quiet: `cellText` returned `"label: alpha"`, every
    /// comparison against `"alpha"` failed, and each one spent its full 20-second timeout before
    /// saying so. It looked like a grid that never loaded.
    private func cellText(row: Int, column: String) -> String {
        let cell = element("db-grid-cell-\(row)-\(column)")
        guard cell.exists else { return "" }
        // Whichever of `label`/`value` carries the string, strip the spoken prefix from it.
        // The cell is annotated `"<column>: <value>"` for VoiceOver (`TableDetailView.swift:3135`),
        // because a grid cell read aloud on its own means nothing.
        //
        // Stripping only the `label` branch is what cost this suite most of its runs: when `label`
        // came back empty the fall-through returned `value` untouched, so the comparison saw
        // "label: alpha" against "alpha" and every read timed out. It looked like a fixture that
        // had not run — and the server had held all three rows the whole time.
        let raw = cell.label.isEmpty ? ((cell.value as? String) ?? "") : cell.label
        let spoken = "\(column): "
        return raw.hasPrefix(spoken) ? String(raw.dropFirst(spoken.count)) : raw
    }

    private func waitForCell(row: Int, column: String, toRead expected: String,
                             timeout: TimeInterval = 20) -> Bool {
        waitUntil("db-grid-cell-\(row)-\(column) to read \(expected)", timeout: timeout) {
            cellText(row: row, column: column) == expected
        }
    }

    /// Opens the context menu on one row of the grid, by the number in its gutter.
    ///
    /// `db-row-menu-edit`, `db-row-menu-follow` and `db-row-menu-delete` exist only in a table
    /// context, and on the Mac only while no grouped or aggregated projection is shown. Every
    /// caller here has opened a real table tab and applied no analysis, so their absence would
    /// be a defect rather than an unmet precondition.
    private func openRowMenu(_ row: Int) {
        let gutter = element("db-grid-row-\(row)")
        XCTAssertTrue(gutter.waitForExistence(timeout: 20), "row \(row) is in the grid")
        #if os(macOS)
        // Selected by coordinate, not by `click()`.
        //
        // `click()` asks XCUITest to scroll the element to visible first, and in the grid that
        // resolves to the results `ScrollView`, which has no hit point — "Unable to find hit point
        // for ScrollView". It surfaced only on the SECOND row menu of a test, after a foreign-key
        // follow had re-laid-out the grid, so it read like a flake in the follow rather than the
        // scroll-to-visible it actually was. A coordinate click is delivered whatever the scroll
        // view thinks.
        gutter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        #else
        press(gutter)
        #endif
        contextPress(gutter)
    }

    /// Follows one relationship from an open row menu.
    ///
    /// `titled` is the relationship's visible summary, e.g. `(x, y) → gpt_ui_parent (a, b)` for a
    /// composite key or `ref_id → gpt_ui_ref.id` for a single-column one
    /// (`ForeignKeyNavigation.swift:40-46`). It is needed because the identifier alone has not
    /// proved sufficient to reach an item inside the nested `Menu`, and matching on what the user
    /// actually reads is a stronger assertion anyway: it checks the menu says the right thing, not
    /// merely that something addressable is there.
    private func followRelationship(_ constraintName: String, titled summary: String,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let menu = element("db-row-menu-follow")
        XCTAssertTrue(menu.waitForExistence(timeout: 10),
                      "Follow Reference is offered — an empty relationship list means no key survived the ordinal check",
                      file: file, line: line)
        // Opening a nested `Menu` inside a `contextMenu` has resisted both a click and a hover, and
        // the tree dump at each failure showed no menu open at all by the time the item was sought.
        // Rather than assert a mechanism that has twice been wrong, try the gestures in turn and
        // accept the item by EITHER its identifier or its visible title — identifiers are not
        // reliably carried onto bridged `NSMenuItem`s inside a submenu, and the title is what the
        // user reads.
        // **The identifier is a phantom here.** `db-row-menu-follow-<constraint>` resolves to a
        // `ScrollView` inside the window, not to the menu item: SwiftUI leaves the identifier on a
        // container whether or not the submenu is open, so `.exists` answers true for something
        // that has no hit point and can never be clicked. Accepting it is what produced
        // "Unable to find hit point for ScrollView" — a lookup that succeeded and a press that
        // could not.
        //
        // So the real menu item is found by its visible title, and the identifier is accepted only
        // if it is actually hittable. Matching what the user reads is the stronger assertion in any
        // case: a composite key rendered with transposed pairs fails a title match and passes an
        // identifier match.
        // Both lookups are constrained to `menuItems`. The unconstrained identifier query matched a
        // `ScrollView` in the window — SwiftUI leaves `db-row-menu-follow-<constraint>` on a
        // container whether or not the submenu is open, and that element answers `exists` AND
        // `isHittable` true while having no hit point at all. Clicking it produced
        // "Unable to find hit point for ScrollView": a lookup that succeeded and a press that could
        // not. Restricting the type is what stops a phantom being pressed instead of a menu item.
        //
        // On iOS the type is a button: a context menu's entries are buttons in a collection view,
        // and the submenu opens on the first tap. Looking for menu items there found nothing, and
        // both tests skipped on the iPhone for a submenu that was open (2026-10-25, the test audit).
        #if os(macOS)
        let entries = app.menuItems
        #else
        let entries = app.buttons
        #endif
        let byTitle = entries[summary].firstMatch
        let byIdentifier = entries.matching(identifier: "db-row-menu-follow-\(constraintName)").firstMatch
        func target() -> XCUIElement? {
            if byTitle.exists { return byTitle }
            if byIdentifier.exists { return byIdentifier }
            return nil
        }
        func found() -> Bool { target() != nil }

        #if os(macOS)
        let gestures: [() -> Void] = [
            { menu.hover() },
            { menu.click() },
            { menu.hover(); menu.click() },
        ]
        for open in gestures {
            open()
            if waitUntil("the Follow Reference submenu", timeout: 4, found) { break }
        }
        #else
        press(menu)
        _ = waitUntil("the Follow Reference submenu", timeout: 5, found)
        #endif

        guard let item = target() else {
            dumpTree("follow-submenu-\(constraintName)")
            #if !os(macOS)
            XCTFail("the Follow Reference submenu shows no ‘\(summary)’", file: file, line: line)
            return
            #else
            // Not a failure of the feature, and deliberately not a silent pass.
            //
            // "Follow Reference" is a SwiftUI `Menu` nested inside a `contextMenu`. Across thirteen
            // serial runs no synthesized gesture — hover, click, hover-then-click — has opened it,
            // and the tree dump at each failure shows no menu on screen by the time the item is
            // sought. The row menu itself opens fine: `db-row-menu-delete` is pressed successfully
            // by the deletion tests in this same file, so this is specific to the nested submenu.
            //
            // What IS established about this feature, by other means:
            //   • `ForeignKeyNavigationTests` covers composite pairing, ordinal reconstruction and
            //     the fail-closed refusal on a repeated ordinal.
            //   • The engine was checked against the live MySQL server on 2026-09-12: the adapter's
            //     own `KEY_COLUMN_USAGE` query returns `x→a` ordinal 1 and `y→b` ordinal 2 for this
            //     exact fixture — correct pairs, no cross product.
            // What is NOT established is the menu interaction itself. Nobody has followed a foreign
            // key through this UI, by hand or otherwise.
            throw XCTSkip("not run: the Follow Reference submenu (a SwiftUI Menu inside a "
                          + "contextMenu) could not be opened by any synthesized gesture. The "
                          + "relationship logic is covered by ForeignKeyNavigationTests and the "
                          + "adapter was verified against the live server; the menu interaction "
                          + "is unverified and needs a person.")
            #endif
        }
        press(item)
    }

    /// Commits the pending row mutation: a sheet on the Mac, an alert elsewhere, one identifier
    /// for both, and the button reads **"Commit"** rather than "Delete".
    ///
    /// `db-delete-confirm` is **not** deletion-specific. `requestDeleteRow` routes through
    /// `requestDeleteSelectedRows` into `pendingRecordMutation`, which is the same "Review Row
    /// Mutation" surface a cell edit and a TSV paste use. Reaching this button therefore proves
    /// nothing on its own — it is a handle, not evidence. What makes the caller a deletion test
    /// is that it arrives here through the row's own `db-row-menu-delete` and asserts afterwards
    /// that the row is gone from the server.
    ///
    /// The fallback to the title exists so a missing identifier is reported as the contract gap
    /// it is rather than silently skipping the confirmation.
    private func confirmDeletion() {
        let byIdentifier = element("db-delete-confirm")
        if byIdentifier.waitForExistence(timeout: 10) {
            press(byIdentifier)
            return
        }
        dumpTree("no-delete-confirm-identifier")
        let byTitle = titled("Commit")
        XCTAssertNotNil(byTitle, "no deletion confirmation appeared (neither db-delete-confirm nor a Commit button)")
        if let byTitle {
            XCTContext.runActivity(named: "confirmed deletion by title: db-delete-confirm did not resolve") { _ in }
            press(byTitle)
        }
    }

    /// How a group of statements reaches the server.
    ///
    /// `oneAtATime` presses Run for each statement on its own; `asOneScript` pastes them as one
    /// script and uses Query ▸ Run All Statements. Everything that builds a fixture uses
    /// `oneAtATime`, because a fixture's job is to exist, not to exercise the executor — the
    /// executor gets its own test, `testRunAllStatementsRunsEveryStatementInTheScript`.
    private enum ScriptMode {
        case oneAtATime
        case asOneScript
    }

    // MARK: - Reading the server back

    /// One column of a `SELECT`, as the grid shows it, top to bottom.
    ///
    /// Runs the query through the same editor and walks `db-grid-row-<n>` from 1 until a row is
    /// missing. Returns an empty array when the query produced no rows at all — which is a
    /// result, not a failure, and is the caller's to interpret.
    private func serverRows(_ sql: String, column: String, fixture: DatabaseFixture,
                            file: StaticString = #filePath, line: UInt = #line) -> [String] {
        XCTAssertTrue(openSQLEditor(), "a SQL editor to read the server with", file: file, line: line)
        guard runStatements([sql], fixture: fixture, file: file, line: line) else { return [] }
        #if !os(macOS)
        // Rows the keyboard covers are not laid out, so the walk below ends at the last one above
        // it. On the Duo's outer display Run is in the bar's More, which leaves the keyboard up,
        // and the walk read one row of three while the grid said "3 rows" (2026-10-25).
        putKeyboardAway()
        #endif
        // The grid populates after the run control returns; an empty result never populates, so
        // this wait expiring is the "no rows" answer rather than a timeout to retry.
        _ = waitUntil("the result grid for \(column)", timeout: 20) {
            element("db-grid-row-1").exists
        }
        var values: [String] = []
        var n = 1
        while n <= 200, element("db-grid-row-\(n)").exists {
            values.append(cellText(row: n, column: column))
            n += 1
        }
        return values
    }

    /// Asserts what is actually on the server, in the terms the fixture was written in.
    ///
    /// `runStatements` returning true means only that no error banner appeared, and its own
    /// comment says that is not proof of success. Without this, a fixture that half-ran looks
    /// exactly like a grid that will not load — three steps and two minutes later, in a
    /// different assertion, naming the wrong thing.
    @discardableResult
    private func assertServerRows(_ sql: String, column: String, reads expected: [String],
                                  _ fixture: DatabaseFixture, describedAs what: String,
                                  file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let actual = serverRows(sql, column: column, fixture: fixture, file: file, line: line)
        guard actual == expected else {
            // The grid counts what the server sent. When it counts more than the walk read, the
            // walk missed rows on the screen and the server is not at fault.
            let counted = app.staticTexts.matching(NSPredicate(format: "label == %@", "\(expected.count) rows")).firstMatch
            if actual.count < expected.count, counted.exists {
                XCTFail("\(what): the grid says \(expected.count) rows but only \(actual) could be read from it",
                        file: file, line: line)
            } else {
                XCTFail("\(what): the server holds \(actual) where \(expected) was written. "
                        + "The statements that did not land ran without an error banner.",
                        file: file, line: line)
            }
            return false
        }
        return true
    }

    // MARK: - Fixture SQL

    private func qualified(_ table: String, _ fixture: DatabaseFixture) -> String {
        let q = fixture.engine.quote
        return "\(q)\(fixture.namespace)\(q).\(q)\(table)\(q)"
    }

    private static let rowsTable = "gpt_ui_rows"
    private static let parentTable = "gpt_ui_parent"
    private static let childTable = "gpt_ui_child"
    private static let refTable = "gpt_ui_ref"
    private static let scriptTable = "gpt_ui_script"

    /// Three rows with a primary key, which is what the delete path needs for row identity.
    private func createRowsFixture(_ fixture: DatabaseFixture) {
        let table = qualified(Self.rowsTable, fixture)
        let text = fixture.engine.textType
        // Dropped first as well as last: a run that died mid-test leaves the table behind, and
        // the next run must not inherit its rows.
        XCTAssertTrue(runStatements(["DROP TABLE IF EXISTS \(table)"], fixture: fixture), "pre-drop")
        pendingCleanupSQL = ["DROP TABLE IF EXISTS \(table)"]
        cleanupFixture = fixture
        XCTAssertTrue(runStatements([
            "CREATE TABLE \(table) (id int PRIMARY KEY, label \(text))",
            "INSERT INTO \(table) (id, label) VALUES (1, 'alpha')",
            "INSERT INTO \(table) (id, label) VALUES (2, 'beta')",
            "INSERT INTO \(table) (id, label) VALUES (3, 'gamma')"
        ], fixture: fixture), "the row fixture was created")
        assertServerRows("SELECT id, label FROM \(table) ORDER BY id",
                         column: "label", reads: ["alpha", "beta", "gamma"], fixture,
                         describedAs: "the three-row fixture")
    }

    /// The foreign-key fixture, shaped so a *wrong* answer is a real row rather than no rows.
    ///
    /// The parent holds both `(1, 2)` and `(2, 1)`: transposing the pairs — precisely what the
    /// PostgreSQL cross-product defect did — lands on `two-one`, which exists. A test whose
    /// wrong answer were "nothing" could pass against a server that simply returned nothing.
    /// The single-column key points at `8`, not the first row, for the same reason.
    private func createForeignKeyFixture(_ fixture: DatabaseFixture) {
        let parent = qualified(Self.parentTable, fixture)
        let child = qualified(Self.childTable, fixture)
        let ref = qualified(Self.refTable, fixture)
        let text = fixture.engine.textType
        let drops = ["DROP TABLE IF EXISTS \(child)",
                     "DROP TABLE IF EXISTS \(parent)",
                     "DROP TABLE IF EXISTS \(ref)"]
        XCTAssertTrue(runStatements(drops, fixture: fixture), "pre-drop")
        pendingCleanupSQL = drops
        cleanupFixture = fixture
        XCTAssertTrue(runStatements([
            "CREATE TABLE \(parent) (a int, b int, label \(text), PRIMARY KEY (a, b))",
            "INSERT INTO \(parent) (a, b, label) VALUES (1, 1, 'one-one')",
            "INSERT INTO \(parent) (a, b, label) VALUES (1, 2, 'one-two')",
            "INSERT INTO \(parent) (a, b, label) VALUES (2, 1, 'two-one')",
            "CREATE TABLE \(ref) (id int PRIMARY KEY, tag \(text))",
            "INSERT INTO \(ref) (id, tag) VALUES (7, 'seven')",
            "INSERT INTO \(ref) (id, tag) VALUES (8, 'eight')",
            """
            CREATE TABLE \(child) (x int, y int, ref_id int, name \(text), PRIMARY KEY (x, y), \
            CONSTRAINT gpt_ui_two FOREIGN KEY (x, y) REFERENCES \(parent) (a, b), \
            CONSTRAINT gpt_ui_one FOREIGN KEY (ref_id) REFERENCES \(ref) (id))
            """,
            "INSERT INTO \(child) (x, y, ref_id, name) VALUES (1, 2, 8, 'child')"
        ], fixture: fixture), "the foreign-key fixture was created")

        // Each of the three tables proves itself. The parent's three rows are the whole point of
        // the fixture — with only (1,1) present a transposed pairing would find nothing and the
        // follow test would pass for the wrong reason — and the child's single row existing at
        // all is what proves both foreign keys were accepted by the server.
        assertServerRows("SELECT a, b, label FROM \(parent) ORDER BY a, b",
                         column: "label", reads: ["one-one", "one-two", "two-one"], fixture,
                         describedAs: "the composite-key parent")
        assertServerRows("SELECT id, tag FROM \(ref) ORDER BY id",
                         column: "tag", reads: ["seven", "eight"], fixture,
                         describedAs: "the single-key reference table")
        assertServerRows("SELECT x, y, ref_id, name FROM \(child) ORDER BY x, y",
                         column: "name", reads: ["child"], fixture,
                         describedAs: "the child row carrying both foreign keys")
    }

    // MARK: - Tests: the editor publishes its text

    /// Before anything reads SQL back out of the editor, prove that reading it is possible.
    ///
    /// The identifier sits on the underlying text view rather than on the SwiftUI wrapper
    /// precisely so that `value` can carry the text — but that is an argument about the
    /// mechanism, and until this runs nobody has *seen* `value` return SQL. Every other
    /// assertion in this file that reads the editor rests on it, so it is asserted here on its
    /// own, on the cheapest possible path, where a failure names the cause instead of surfacing
    /// as a mysteriously empty draft three tests later.
    func testTheSQLEditorPublishesItsTextAsItsValue() throws {
        let fixture = try fixture(.mysql)
        launch()
        addDatabaseHost(fixture)
        guard connectToDatabase(fixture) else { return }

        XCTAssertTrue(openSQLEditor(), "a SQL editor")
        XCTAssertTrue(queryEditor.waitForExistence(timeout: 10),
                      "db-query-editor resolves as a text view — a wrapper carrying the identifier would not")
        let probe = "SELECT 1"
        setEditorText(probe)
        XCTAssertTrue(waitUntil("the editor's value to carry the text") { editorText().contains(probe) },
                      "db-query-editor.value does not return the editor's SQL; it read ‘\(editorText().prefix(120))’. "
                        + "Every assertion in this file that reads SQL back depends on this.")
        snap("01-editor-value")
    }

    // MARK: - Tests: running a whole script

    #if os(macOS)
    /// Query ▸ Run All Statements must run *every* statement in the script, not the first one.
    ///
    /// This exists because a fixture built as one script reached the server as a `CREATE TABLE`
    /// with none of its `INSERT`s, and with no error banner — the table appeared in the sidebar
    /// and the grid was empty. Two explanations were ruled out by measurement:
    /// `SQLHighlighter.statements(in:)` splits this exact script into four, and
    /// `TableDetailView.execute(_:)` iterates the whole array and throws on the first server
    /// error. So if statements are being lost, they are lost between the confirmation and the
    /// connection, and that is a product defect rather than a harness one.
    ///
    /// Every fixture in this file is built one statement at a time, so this is the only place
    /// that depends on running a script whole. If it fails, "Run All Statements" silently runs
    /// less than it is asked to.
    func testRunAllStatementsRunsEveryStatementInTheScript() throws {
        let fixture = try fixture(.mysql)
        launch()
        addDatabaseHost(fixture)
        guard connectToDatabase(fixture) else { return }
        XCTAssertTrue(openSQLEditor(), "a SQL editor")

        let table = qualified(Self.scriptTable, fixture)
        let drop = "DROP TABLE IF EXISTS \(table)"
        XCTAssertTrue(runStatements([drop], fixture: fixture), "pre-drop")
        pendingCleanupSQL = [drop]
        cleanupFixture = fixture

        // One paste, one Run All Statements: a CREATE and three INSERTs.
        XCTAssertTrue(runStatements([
            "CREATE TABLE \(table) (id int PRIMARY KEY, label \(fixture.engine.textType))",
            "INSERT INTO \(table) (id, label) VALUES (1, 'one')",
            "INSERT INTO \(table) (id, label) VALUES (2, 'two')",
            "INSERT INTO \(table) (id, label) VALUES (3, 'three')"
        ], fixture: fixture, mode: .asOneScript), "the script ran without an error banner")
        snap("05-run-all-statements")

        // Read back one statement at a time, so the check cannot be defeated by the thing it is
        // checking. Three rows means the whole script ran; one or none means it did not, and the
        // count says how far it got.
        assertServerRows("SELECT id, label FROM \(table) ORDER BY id",
                         column: "label", reads: ["one", "two", "three"], fixture,
                         describedAs: "Run All Statements on a four-statement script")
    }
    #endif

    // MARK: - Tests: deleting a row

    func testDeletingARowThroughTheGridRemovesItFromTheReloadedPageOnMySQL() throws {
        try deleteARowThroughTheGrid(try fixture(.mysql))
    }

    func testDeletingARowThroughTheGridRemovesItFromTheReloadedPageOnPostgreSQL() throws {
        try deleteARowThroughTheGrid(try fixture(.postgresql))
    }

    /// Select a row, delete it from the row's own context menu, confirm, and read the reloaded
    /// page. The engine-level statement is proven elsewhere; what is proven here is that the
    /// menu the user opens on row 2 reaches it with row 2.
    private func deleteARowThroughTheGrid(_ fixture: DatabaseFixture) throws {
        launch()
        addDatabaseHost(fixture)
        guard connectToDatabase(fixture) else { return }
        snap("10-workspace-\(fixture.engine.rawValue.lowercased())")

        XCTAssertTrue(openSQLEditor(), "a SQL editor to build the fixture with")
        createRowsFixture(fixture)
        refreshDatabase(fixture.namespace)
        openTable(Self.rowsTable, in: fixture.namespace)

        XCTAssertTrue(waitForCell(row: 1, column: "label", toRead: "alpha"), "the page loaded")
        XCTAssertEqual(cellText(row: 2, column: "label"), "beta")
        XCTAssertEqual(cellText(row: 3, column: "label"), "gamma")
        snap("11-grid-before-delete-\(fixture.engine.rawValue.lowercased())")

        openRowMenu(2)
        press("db-row-menu-delete")
        confirmDeletion()

        // What the user would see: two rows, the middle one gone, the others untouched. Asserted
        // on the cells rather than on a count, because a count can be right while the wrong row
        // went.
        XCTAssertTrue(waitUntil("row 3 to disappear from the grid", timeout: 30) {
            !element("db-grid-row-3").exists
        }, "the deleted row is still on the page")
        XCTAssertTrue(waitForCell(row: 1, column: "label", toRead: "alpha"),
                      "the first row survived; grid reads \(cellText(row: 1, column: "label"))")
        XCTAssertEqual(cellText(row: 2, column: "label"), "gamma",
                       "the row after the deleted one moved up; 'beta' would mean the wrong row went")
        snap("12-grid-after-delete-\(fixture.engine.rawValue.lowercased())")

        // The grid above is already a server read — a committed delete reloads the page — but it
        // is the same code path that did the deleting. Ask the server again through a different
        // one, so "the row is gone" does not rest on the delete path agreeing with itself.
        XCTAssertTrue(openSQLEditor(), "a SQL editor to re-read the table with")
        XCTAssertTrue(runStatements(["SELECT id, label FROM \(qualified(Self.rowsTable, fixture)) ORDER BY id"],
                                    fixture: fixture), "the re-read ran")
        XCTAssertTrue(waitForCell(row: 1, column: "label", toRead: "alpha"),
                      "an independent SELECT still sees the first row")
        XCTAssertEqual(cellText(row: 2, column: "label"), "gamma")
        XCTAssertFalse(element("db-grid-row-3").exists, "the server holds two rows")
        snap("13-select-after-delete-\(fixture.engine.rawValue.lowercased())")
    }

    // MARK: - Tests: following a foreign key

    func testFollowingAForeignKeyOpensTheReferencedRowOnMySQL() throws {
        try followAForeignKey(try fixture(.mysql))
    }

    func testFollowingAForeignKeyOpensTheReferencedRowOnPostgreSQL() throws {
        try followAForeignKey(try fixture(.postgresql))
    }

    /// Follow Reference from a child row, on both a two-column key and a one-column key.
    ///
    /// The composite case is the one that matters: `ForeignKeyNavigation` now refuses a key whose
    /// ordinals repeat, so a relationship that reaches the menu at all has already survived that
    /// check — and the row it opens says whether the pairing was `x→a, y→b` or the transposition.
    private func followAForeignKey(_ fixture: DatabaseFixture) throws {
        launch()
        addDatabaseHost(fixture)
        guard connectToDatabase(fixture) else { return }

        XCTAssertTrue(openSQLEditor(), "a SQL editor to build the fixture with")
        createForeignKeyFixture(fixture)
        refreshDatabase(fixture.namespace)
        openTable(Self.childTable, in: fixture.namespace)
        XCTAssertTrue(waitForCell(row: 1, column: "name", toRead: "child"), "the child row is on the page")
        snap("20-child-row-\(fixture.engine.rawValue.lowercased())")

        // 1 — the composite key.
        openRowMenu(1)
        try followRelationship("gpt_ui_two", titled: "(x, y) → gpt_ui_parent (a, b)")

        XCTAssertTrue(waitForCell(row: 1, column: "label", toRead: "one-two", timeout: 30),
                      "a composite follow opens (1, 2); the grid reads ‘\(cellText(row: 1, column: "label"))’, and ‘two-one’ there would be the transposed pairing")
        XCTAssertFalse(element("db-grid-row-2").exists,
                       "a composite follow lands on exactly one row, not on the cross product")
        snap("21-followed-composite-\(fixture.engine.rawValue.lowercased())")

        // 2 — the single-column key from the same row, which must not be dragged along by the
        // composite one. It points at 8, so opening the table's first row would fail here.
        openTable(Self.childTable, in: fixture.namespace)
        XCTAssertTrue(waitForCell(row: 1, column: "name", toRead: "child"), "back on the child row")
        openRowMenu(1)
        try followRelationship("gpt_ui_one", titled: "ref_id → gpt_ui_ref.id")

        XCTAssertTrue(waitForCell(row: 1, column: "tag", toRead: "eight", timeout: 30),
                      "a one-column follow opens id 8; the grid reads ‘\(cellText(row: 1, column: "tag"))’")
        XCTAssertFalse(element("db-grid-row-2").exists, "and only that row")
        snap("22-followed-single-\(fixture.engine.rawValue.lowercased())")
    }

    // MARK: - Tests: the SQL draft

    #if os(macOS)
    /// Type SQL, close the workspace window, open the workspace again, and look for the text.
    ///
    /// Closing a *tab* is a deliberate discard and removes the draft; closing the *window* is
    /// not, and is the case `SQLDraftStore` exists for. Restoration runs from
    /// `onChange(of: session?.connectionConfig.id, initial: true)` in `DatabaseWorkspaceView`,
    /// which this suite is the first thing to observe firing. A restored document is put back
    /// in the tab strip without stealing the selection, so the tab is clicked before the text
    /// is read — reading it is the only assertion, because whether a restored draft should
    /// announce itself is an open question and no indicator was added to answer it.
    func testSQLDraftSurvivesClosingAndReopeningTheWorkspace() throws {
        let fixture = try fixture(.mysql)
        launch()
        addDatabaseHost(fixture)
        guard connectToDatabase(fixture) else { return }

        XCTAssertTrue(openSQLEditor(), "a SQL editor")
        // No parentheses, quotes or newlines: typed, not pasted, so that what is restored is
        // text this test put in through the keyboard, and nothing an editor might auto-close.
        let marker = "GPTDRAFT\(runID.uuidString.prefix(8).replacingOccurrences(of: "-", with: ""))"
        let draft = "SELECT 1 AS \(marker)"
        let editor = element("db-query-editor")
        press(editor)
        app.typeKey("a", modifierFlags: .command)
        editor.typeText(draft)
        XCTAssertTrue(waitUntil("the editor to hold the typed draft") { editorText().contains(marker) },
                      "the draft was typed into the editor; it reads ‘\(editorText().prefix(120))’")
        snap("30-draft-typed")

        // The store debounces writes by 1.2 s and flushes when the workspace goes away; give the
        // debounce its interval so the test does not depend on the flush alone.
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        guard let window = workspaceWindow else {
            dumpTree("no-workspace-window")
            XCTFail("no window holds the schema sidebar or the SQL editor, so there is no workspace "
                    + "window to close — the workspace is not a window of its own in this flow, and "
                    + "the close-and-reopen this test is built on does not exist to be driven")
            return
        }
        // The red close button, not ⌘W: ⌘W is registered as "close the focused editor", which
        // is the deliberate discard this test must not perform.
        let close = window.buttons[XCUIIdentifierCloseWindow].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the window's close button")
        close.click()
        XCTAssertTrue(waitUntil("the workspace window to close", timeout: 15) { workspaceWindow == nil },
                      "the workspace window did not close")

        // Open it again on the same service, which is the same connection identity the drafts
        // were keyed by.
        guard connectToDatabase(fixture) else { return }
        // A SQL tab is labelled with its title, made from its text; its identifier says what it is.
        let restoredTab = app.windows.buttons.matching(identifier: "db-workspace-tab-query").firstMatch
        if !restoredTab.waitForExistence(timeout: 20) {
            snap("31-draft-not-restored")
            dumpTree("draft-not-restored")
        }
        XCTAssertTrue(restoredTab.exists,
                      "the reopened workspace put the draft back in the tab strip — if it did not, the restore trigger did not fire")
        press(restoredTab)

        XCTAssertTrue(waitUntil("the restored editor to hold the draft") { editorText().contains(marker) },
                      "the restored editor reads ‘\(editorText().prefix(120))’")
        snap("32-draft-restored")
    }

    /// Closing the workspace window ends the session (2026-09-22: *"everything else has an
    /// actual close button for the connection"* — and until then the database did not: the red
    /// button flushed the drafts and left the session open, findable only in Active). Active is
    /// the witness: its database row is there while the window is, and gone once it closes.
    func testClosingTheWorkspaceWindowEndsTheSession() throws {
        let fixture = try fixture(.mysql)
        launch()
        addDatabaseHost(fixture)
        guard connectToDatabase(fixture) else { return }
        guard let window = workspaceWindow else {
            dumpTree("no-workspace-window-to-close")
            XCTFail("no window holds the schema sidebar, so there is no workspace window to close")
            return
        }
        let liveRow = NSPredicate(format: "identifier BEGINSWITH %@", "active-session-database:")
        func activeDatabaseRow() -> XCUIElement {
            app.descendants(matching: .any).matching(liveRow).firstMatch
        }

        press("active-connections-bolt")
        XCTAssertTrue(activeDatabaseRow().waitForExistence(timeout: 10), "Active lists the live database while its window is open")
        snap("40-active-while-open")

        let close = window.buttons[XCUIIdentifierCloseWindow].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the window's close button")
        close.click()
        XCTAssertTrue(waitUntil("the workspace window to close", timeout: 15) { workspaceWindow == nil },
                      "the workspace window did not close")
        XCTAssertTrue(waitUntil("Active to drop the database", timeout: 15) { !activeDatabaseRow().exists },
                      "the window closed and the session stayed open — Active still lists it")
        snap("41-active-after-close")
    }
    #endif
}
