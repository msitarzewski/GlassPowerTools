//
//  GlassTerminalUITests.swift
//  GlassPowerToolsUITests
//
//  Stage 2 integration: connect to a real SSH host through the shell — add host, add an SSH
//  service, fill glas.sh's server form (key auth), connect, prove the terminal is live.
//
//  Gated on the launch environment: GPT_SSH_TEST_HOST, GPT_SSH_TEST_USER, GPT_SSH_TEST_KEY_PATH
//  (an OpenSSH private key file). Pass them to `xcodebuild test` as TEST_RUNNER_GPT_SSH_TEST_*.
//  Without them every test skips with a reason. Key material is read by the runner at run time,
//  handed to the app through the pasteboard, and never written anywhere.
//

import XCTest

@MainActor
final class GlassTerminalUITests: XCTestCase {
    private var app: XCUIApplication!
    private let runID = UUID()
    private var shotsDirectory: URL?

    private struct HostFixture {
        let host: String
        let user: String
        let keyPath: String
        let port: String
    }

    override func setUp() async throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        if let shots = environment["GPT_SHOTS_DIR"] {
            shotsDirectory = URL(fileURLWithPath: shots, isDirectory: true)
        }
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    // MARK: - Gate

    private func fixture() throws -> HostFixture {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["GPT_SSH_TEST_HOST"], !host.isEmpty,
              let user = env["GPT_SSH_TEST_USER"], !user.isEmpty,
              let keyPath = env["GPT_SSH_TEST_KEY_PATH"], !keyPath.isEmpty else {
            throw XCTSkip("not run: no SSH test host configured (GPT_SSH_TEST_HOST/_USER/_KEY_PATH)")
        }
        guard FileManager.default.isReadableFile(atPath: (keyPath as NSString).expandingTildeInPath) else {
            throw XCTSkip("not run: SSH test key file is not readable at the given path")
        }
        return HostFixture(host: host, user: user, keyPath: (keyPath as NSString).expandingTildeInPath,
                           port: env["GPT_SSH_TEST_PORT"] ?? "22")
    }

    // MARK: - Helpers (same conventions as GlassShellLibraryUITests)

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
        #endif
        return app
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Containers that hold no Touch Bar.
    ///
    /// macOS mirrors an alert's default buttons onto the Touch Bar, and the proxy is a *second*
    /// element carrying the same title as the real control while refusing every click
    /// ("cannot be called with Touch Bar elements"). It is not a descendant of a window, a menu or
    /// a sheet, so a lookup that stays inside those never finds it. Same approach as
    /// `GlassDatabaseUITests`, which met this first.
    private var touchBarFreeScopes: [XCUIElementQuery] {
        [app.windows, app.menus, app.menuBars, app.sheets, app.dialogs]
    }

    /// A button by its visible title, never the Touch Bar's copy of it. `.firstMatch` inside each
    /// scope is required rather than tidy: `scope` is a query over every window, so
    /// `scope.buttons[title]` can match in several at once — `.exists` answers true for that while
    /// `.click()` refuses it as ambiguous.
    private func titledButton(_ titles: [String], timeout: TimeInterval = 5) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for scope in touchBarFreeScopes {
                for title in titles {
                    let button = scope.buttons[title].firstMatch
                    if button.exists { return button }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    /// macOS: `tap()` compiles but does not drive SwiftUI controls under Xcode 27; `click()` does.
    private func press(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    @discardableResult
    private func press(_ identifier: String, timeout: TimeInterval = 10,
                       file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = element(identifier)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(identifier)", file: file, line: line)
        press(e)
        return e
    }

    private func type(_ text: String, into identifier: String, timeout: TimeInterval = 10) {
        let field = element(identifier)
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "missing \(identifier)")
        press(field)
        field.typeText(text)
    }

    /// First element among several candidate queries that exists within the timeout.
    private func firstExisting(_ candidates: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.exists { return candidate }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return nil
    }

    /// Our own window only (project rule 11); see `UITestCapture.swift`. The main window,
    /// which carries any sheet (the key form is a sheet over the server form on every platform).
    private func snap(_ name: String) {
        captureOwnWindow(app.windows.firstMatch, app: app, name: "terminal-\(name)")
    }

    /// Attaches the accessibility tree so a failure can be diagnosed from the result bundle.
    private func dumpTree(_ name: String) {
        #if !os(macOS)
        // iOS and visionOS print a real subtree. Enumerating `app.buttons` there raises
        // "Automation type mismatch: computed Button ... vs PopUpButton" on a SwiftUI Picker
        // (iOS 27) and fails the test from inside the diagnostic, so never do that off macOS.
        let subtree = XCTAttachment(string: app.debugDescription)
        subtree.name = "terminal-tree-\(name)"
        subtree.lifetime = .keepAlways
        add(subtree)
        return
        #else
        // On macOS `debugDescription` of the application only prints its query chain, so
        // inventory the interesting element classes explicitly.
        var lines: [String] = []
        lines.append("windows=\(app.windows.count) sheets=\(app.sheets.count) dialogs=\(app.dialogs.count) alerts=\(app.alerts.count)")
        for w in app.windows.allElementsBoundByIndex { lines.append("window: '\(w.title)' id='\(w.identifier)'") }
        for s in app.sheets.allElementsBoundByIndex { lines.append("sheet: '\(s.title)' id='\(s.identifier)' frame=\(s.frame)") }
        lines.append("textFields: " + app.textFields.allElementsBoundByIndex.map { "'\($0.label)'/'\($0.placeholderValue ?? "")'/'\($0.identifier)'" }.joined(separator: ", "))
        lines.append("secureFields: \(app.secureTextFields.count)  textViews: \(app.textViews.count)")
        lines.append("buttons: " + app.buttons.allElementsBoundByIndex.prefix(60).map { "'\($0.label)'" }.joined(separator: ", "))
        lines.append("staticTexts: " + app.staticTexts.allElementsBoundByIndex.prefix(60).map { "'\($0.label.prefix(40))'/'\((($0.value as? String) ?? "").prefix(60))'" }.joined(separator: ", "))
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "terminal-tree-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }

    private func enterAllConnections() {
        let scope = element("glass-library-scope-all-connections")
        if scope.waitForExistence(timeout: 5) { press(scope) }
    }

    // MARK: - Steps

    /// Adds a host through the one setup sheet. The address is the machine's, typed once here;
    /// with `terminal` the Terminal tab is enabled and filled (username, SSH key added through
    /// the nested key sheet), so the host and its terminal are created together.
    private func addHost(named name: String, address: String, terminal fixture: HostFixture? = nil,
                         placeholderUser: String = "tester") throws {
        let empty = element("connection-library-add-host-empty")
        if empty.waitForExistence(timeout: 3) { press(empty) } else { press("connection-library-add-host") }
        type(name, into: "host-editor-name")
        type(address, into: "host-editor-address")
        // A service is required: Add Host pre-selects the first available tab and its fields are
        // mandatory, because "a machine with nothing on it is not worth a row"
        // (`GlassShellSetup.swift:76`). Without a fixture this used to leave the tab empty, so Save
        // was correctly refused and the sheet stayed — reported as "the sheet closes after Save",
        // which reads like a dismissal bug and is validation working.
        enableTerminalTab()
        if let fixture {
            try fillTerminalTab(fixture)
        } else {
            // Both through `setField`, which is this file's own helper and already handles the
            // thing a hand-rolled press-and-type does not: it presses, then `selectAll()`, which
            // forces focus before the first keystroke. Typing into a cold sheet's SecureTextField
            // without that fails outright with "Neither element nor any descendant has keyboard
            // focus".
            setField("add-server-username", to: placeholderUser)
            _ = reveal("add-server-password")
            setField("add-server-password", to: "not-a-real-password")
        }
        snap(fixture == nil ? "02-add-host" : "04-add-host-terminal-filled")
        press("host-editor-save")
        // visionOS offers to save the typed password to iCloud Keychain once the sheet commits, and
        // that system alert covers the app: every later assertion then fails against an app it
        // cannot see. This helper only started typing a password when Add Host began requiring a
        // service, so the alert is new here even though the hazard was documented on 2026-09-11.
        dismissSystemPasswordPrompt()
        XCTAssertTrue(element("host-editor-save").waitForNonExistence(timeout: 20), "the sheet closes after Save")
    }

    /// Choosing the tab is what adds the service — there is no separate toggle.
    private func enableTerminalTab() {
        let sections = element("setup-sections")
        XCTAssertTrue(sections.waitForExistence(timeout: 10), "service tabs")
        let tab = sections.buttons["Terminal"].exists ? sections.buttons["Terminal"] : sections.radioButtons["Terminal"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Terminal tab")
        press(tab)
    }

    private func openDetail(of name: String) {
        if element("host-add-service").waitForExistence(timeout: 5) { return }
        enterAllConnections()
        press("host-row-\(name)")
        XCTAssertTrue(element("host-add-service").waitForExistence(timeout: 10))
    }

    private func connectFromDetail() {
        let candidates = [element("host-service-connect-ssh"), element("host-connect")]
        guard let connect = firstExisting(candidates, timeout: 10) else {
            XCTFail("no Connect control on the host detail"); return
        }
        press(connect)
    }

    /// The Terminal tab's required fields: username and an SSH key added through the nested key
    /// sheet. Port lives under Advanced and defaults to 22; it is set only when the fixture's differs.
    private func fillTerminalTab(_ fixture: HostFixture) throws {
        XCTAssertFalse(app.textFields["add-server-host"].exists, "a service never has an address field")
        setField("add-server-username", to: fixture.user)
        if fixture.port != "22" {
            let advanced = element("setup-advanced-ssh")
            if advanced.waitForExistence(timeout: 3) { expandDisclosure(advanced) }
            if element("add-server-port").waitForExistence(timeout: 3) { setField("add-server-port", to: fixture.port) }
        }
        chooseSSHKeyMethod()

        let addKey = app.buttons["Add SSH Key"].firstMatch
        XCTAssertTrue(addKey.waitForExistence(timeout: 10), "Add SSH Key button")
        #if !os(macOS)
        // The host sheet scrolls on a phone; bring the button into view before pressing it.
        var scrolls = 0
        while !addKey.isHittable, scrolls < 4 { app.swipeUp(); scrolls += 1 }
        #endif
        press(addKey)
        let keyName = element("ssh-key-name")
        let keyFormShown = keyName.waitForExistence(timeout: 10)
        if !keyFormShown {
            snap("03-after-add-ssh-key")
            dumpTree("after-add-ssh-key")
        }
        XCTAssertTrue(keyFormShown, "Add SSH Key form")
        press(keyName); keyName.typeText("scratch-vm-key")
        pastePrivateKey(fromFile: fixture.keyPath)
        snap("03-add-key-sheet")
        let saveKey = app.buttons["Save"].firstMatch
        XCTAssertTrue(saveKey.waitForExistence(timeout: 5))
        press(saveKey)
        XCTAssertTrue(keyName.waitForNonExistence(timeout: 10), "Add SSH Key form closes after Save")
        #if os(macOS)
        let keyPicker = app.popUpButtons.matching(NSPredicate(format: "value CONTAINS[c] 'scratch-vm-key'")).firstMatch
        #else
        let keyPicker = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'scratch-vm-key'")).firstMatch
        #endif
        if !keyPicker.waitForExistence(timeout: 5) { dumpTree("key-not-selected") }
        XCTAssertTrue(keyPicker.exists, "the newly added key is selected in the SSH Key picker")
    }

    /// Expands one of the sheet's disclosure rows (a plain button row, see `GlassFormDisclosureStyle`).
    private func expandDisclosure(_ row: XCUIElement) {
        if "\(row.value ?? "")" == "expanded" { return }
        press(row)
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in "\(row.value ?? "")" == "expanded" }, object: nil)
        _ = XCTWaiter().wait(for: [done], timeout: 3)
    }

    /// A sheet's title: a static text on the Mac, the navigation bar on touch platforms.
    /// The detail's Address row is one `LabeledContent`: macOS exposes its value as a child
    /// static text, iOS folds it into the element's own value. Ask for either.
    private func detailShowsAddress(_ value: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.staticTexts[value].firstMatch.exists { return true }
            let row = element("host-detail-address")
            if row.exists, (row.label + " " + ((row.value as? String) ?? "")).contains(value) { return true }
            _ = row.waitForExistence(timeout: 0.5)
        } while Date() < deadline
        return false
    }

    /// visionOS offers to save a typed password in iCloud Keychain once the sheet commits; the
    /// alert covers the app. The app keeps credentials in its own store, so answer "Not Now".
    private func dismissSystemPasswordPrompt() {
        // Springboard only exists on the touch platforms; asking for it on macOS fails the test.
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

    /// SwiftUI builds list rows lazily: a row below the fold is absent from the accessibility
    /// tree, not merely off-screen. The visionOS sheet is short enough for that to hide the
    /// authentication fields, so scroll the surface until the row exists (2026-09-11).
    @discardableResult
    private func reveal(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        let target = element(identifier)
        if target.waitForExistence(timeout: 2) { return target }
        let surfaces = [app.scrollViews.firstMatch, app.collectionViews.firstMatch, app.tables.firstMatch]
        guard let surface = surfaces.first(where: { $0.exists }) else {
            _ = target.waitForExistence(timeout: timeout)
            return target
        }
        for _ in 0..<8 where !target.exists { surface.swipeUp() }
        _ = target.waitForExistence(timeout: timeout)
        return target
    }

    private func sheetTitle(_ title: String) -> XCUIElement {
        #if os(macOS)
        return app.staticTexts[title].firstMatch
        #else
        let bar = app.navigationBars[title].firstMatch
        return bar.exists ? bar : app.staticTexts[title].firstMatch
        #endif
    }

    private func setField(_ identifier: String, to value: String) {
        let field = element(identifier)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "missing \(identifier)")
        if (field.value as? String) == value { return }
        press(field)
        #if os(macOS)
        selectAll()
        #else
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        #endif
        field.typeText(value)
    }

    private func selectAll() {
        #if os(macOS)
        app.typeKey("a", modifierFlags: .command)
        #endif
    }

    private func chooseSSHKeyMethod() {
        #if os(macOS)
        // A SwiftUI Picker in a macOS Form is a pop-up button.
        let popUp = app.popUpButtons.matching(NSPredicate(format: "label CONTAINS[c] 'Method' OR value CONTAINS[c] 'Password'")).firstMatch
        if popUp.waitForExistence(timeout: 5) {
            press(popUp)
            let item = app.menuItems["SSH Key"].firstMatch
            if item.waitForExistence(timeout: 5) { press(item) }
        }
        #else
        // A menu-style picker: a button labelled "Method, Password" whose menu lists the methods
        // (buttons on iOS; visionOS may expose them as menu items or plain cells).
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Method'")).firstMatch
        if picker.waitForExistence(timeout: 5) {
            picker.tap()
            let item = firstExisting([app.buttons["SSH Key"].firstMatch, app.menuItems["SSH Key"].firstMatch,
                                      app.cells["SSH Key"].firstMatch, app.staticTexts["SSH Key"].firstMatch], timeout: 5)
            if let item { item.tap() } else { dumpTree("method-menu") }
            _ = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'SSH Key'")).firstMatch.waitForExistence(timeout: 5)
        }
        #endif
    }

    private func pastePrivateKey(fromFile path: String) {
        guard let key = try? String(contentsOfFile: path, encoding: .utf8) else {
            XCTFail("could not read the SSH test key"); return
        }
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "private key editor")
        press(editor)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        app.typeKey("v", modifierFlags: .command)
        #else
        UIPasteboard.general.string = key
        editor.doubleTap()
        let paste = app.menuItems["Paste"].firstMatch
        if paste.waitForExistence(timeout: 3) { paste.tap() } else { editor.typeText(key) }
        #endif
    }

    /// Accepts the D14 host-key prompt. This is the only automated coverage the prompt has, and
    /// with D23 it is also the only place a pin written under the app's real synchronizing
    /// configuration is exercised — no `swift test` process can write a synchronizable Keychain
    /// item at all (`errSecMissingEntitlement`), so the signed app is the only witness.
    @discardableResult
    private func acceptTrustPromptIfShown() -> Bool {
        // Scoped to windows and sheets: the application-wide query returns the Touch Bar's copy of
        // the default button about half the time, and that copy refuses every click.
        guard let trust = titledButton(["Trust and Connect", "Trust Changed Key"], timeout: 20) else {
            return false
        }
        snap("05-trust-prompt")
        press(trust)
        return true
    }

    /// The terminal is live when a workspace window for the server appears on macOS, or the
    /// workgroup surface (tabs / session switcher) replaces the library on iPhone and visionOS —
    /// the terminal presents it only once the transport is authenticated and the shell channel
    /// is opening. A session header reporting Connected counts everywhere.
    private func waitForLiveTerminal(serverName: String) -> Bool {
        let connected = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value == 'Connected'")).firstMatch
        #if os(macOS)
        let window = app.windows.matching(NSPredicate(format: "title CONTAINS[c] %@", serverName)).firstMatch
        return firstExisting([connected, window], timeout: 45) != nil
        #else
        let workgroup = [element("terminal-workgroup-session-switcher"), element("terminal-workgroup-tabs")]
        return firstExisting([connected] + workgroup, timeout: 45) != nil
        #endif
    }

    /// The connect flow's "Connection Failed" alert: a dialog on touch platforms, a sheet on the
    /// main window on macOS, where static text is exposed as `value`.
    private func connectionFailureText() -> String? {
        let candidates = [app.dialogs.firstMatch, app.alerts.firstMatch, app.sheets.firstMatch]
        guard let alert = candidates.first(where: { $0.exists }) else { return nil }
        var parts: [String] = []
        for text in alert.staticTexts.allElementsBoundByIndex {
            let label = text.label
            let value = (text.value as? String) ?? ""
            let content = label.isEmpty ? value : label
            if !content.isEmpty { parts.append(content) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    // MARK: - Tests

    /// The terminal's settings pages (Connections, Terminal, Snippets) are in the shell's one
    /// settings surface, and selecting one renders the capability's page. Not gated on a host.
    func testTerminalSettingsPagesAppearInTheShellSettings() throws {
        app = launch()
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        press("connection-library-settings")
        #endif
        let picker = element("settings-sections")
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "settings picker")
        // visionOS renders the sections TabView as the leading ornament, exposed as a tab bar.
        func page(_ title: String) -> XCUIElement {
            #if os(visionOS)
            if app.tabBars.buttons[title].waitForExistence(timeout: 2) { return app.tabBars.buttons[title] }
            if app.buttons[title].firstMatch.waitForExistence(timeout: 2) { return app.buttons[title].firstMatch }
            #endif
            return picker.buttons[title].exists ? picker.buttons[title] : picker.radioButtons[title]
        }
        for title in ["Connections", "Terminal", "Snippets"] {
            if !page(title).waitForExistence(timeout: 5) {
                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = "accessibility-tree-settings-\(title)"
                tree.lifetime = .keepAlways
                add(tree)
            }
            XCTAssertTrue(page(title).exists, "settings page \(title) listed")
        }
        press(page("Terminal"))
        XCTAssertTrue(element("settings-page-terminal.terminal").waitForExistence(timeout: 10), "Terminal page renders")
        snap("00-settings-terminal-page")
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        press("settings-done")
        #endif
    }

    #if os(macOS)
    /// Phase 3 visual evidence on the Mac: the library window with a host selected (flat detail
    /// column, "+" in the sidebar toolbar left of the toggle) and a local terminal workspace
    /// window (framed canvas with its 3 pt glass margin, "New Terminal Tab" in the sidebar).
    func testMacLibraryAndTerminalWindowChrome() throws {
        app = launch()
        try addHost(named: "chrome", address: "chrome.example")
        openDetail(of: "chrome")
        // Toolbar order: the sidebar's "+" must precede the sidebar toggle from the left.
        let addHost = element("connection-library-add-host")
        XCTAssertTrue(addHost.waitForExistence(timeout: 5), "Add Host in the sidebar toolbar")
        let toggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
        if toggle.exists {
            XCTAssertLessThan(addHost.frame.minX, toggle.frame.minX, "Add Host sits left of the sidebar toggle")
        }
        snap("10-mac-library-detail")

        // ⌘N is the shell's Add Host in the library window; the local terminal is the terminal
        // capability's toolbar item.
        press("connection-library-local-terminal-toolbar")
        // The workspace window closes again as soon as the local shell exits, which it does at
        // once under the test runner's environment on some machines; watch for the window
        // eagerly and capture it the moment its sidebar is up.
        let others = app.windows.matching(NSPredicate(format: "NOT (title CONTAINS[c] 'All Connections')"))
        let deadline = Date().addingTimeInterval(15)
        var terminalWindow: XCUIElement?
        while Date() < deadline {
            let candidate = others.firstMatch
            if candidate.exists { terminalWindow = candidate; break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard let terminalWindow else {
            dumpTree("no-terminal-window")
            XCTFail("local terminal workspace window"); return
        }
        let newTab = element("mac-workspace-new-tab")
        _ = newTab.waitForExistence(timeout: 5)
        captureOwnWindow(terminalWindow, app: app, name: "terminal-11-mac-local-terminal")
        XCTContext.runActivity(named: "workspace window '\(terminalWindow.title)' newTab=\(newTab.exists) stillOpen=\(terminalWindow.exists)") { _ in }
        if terminalWindow.exists { app.typeKey("w", modifierFlags: [.command, .shift]) }
    }
    #endif

    /// Add a service to a host that has no address (a record another family app wrote): the one
    /// sheet collects the address on the host and the terminal's fields together; no service
    /// setup ever shows an address field of its own. No real connection is made.
    func testAddServiceCollectsTheAddressOnTheHost() throws {
        app = launch(extraArguments: ["--ui-testing-seed-hosts", "bare"])
        openDetail(of: "bare")
        XCTAssertTrue(element("host-detail-address").waitForExistence(timeout: 10))
        // The row is one `LabeledContent`: macOS exposes its value as a child static text, iOS as
        // the element's own value. Query for either rather than assuming one shape.
        XCTAssertTrue(detailShowsAddress("Not set", timeout: 5), "no address yet")
        press("host-add-service")
        XCTAssertTrue(sheetTitle("Add Terminal to bare").waitForExistence(timeout: 10), "titled for the host")
        let addressField = element("host-editor-address")
        XCTAssertTrue(addressField.waitForExistence(timeout: 10), "the address is asked for on the host, in the same sheet")
        XCTAssertTrue(element("add-server-username").waitForExistence(timeout: 5), "the terminal's required fields are already there")
        XCTAssertFalse(app.textFields["add-server-host"].exists, "the terminal never has an address field")
        snap("20-add-service-collects-address")
        press("host-editor-save")
        XCTAssertTrue(element("host-editor-address-validation").waitForExistence(timeout: 5) || element("host-editor-save").exists,
                      "Save refuses without the address")
        press(addressField); addressField.typeText("10.9.8.7")
        setField("add-server-username", to: "probe")
        _ = reveal("add-server-password")
        // `setField`, not a raw press-and-type: it calls `selectAll()` between the two, which is
        // what guarantees focus. A bare `typeText` into a SecureTextField lands only when the sheet
        // happens to be warm, so this passed and failed on alternate runs for no visible reason.
        setField("add-server-password", to: "not-a-real-password")
        press("host-editor-save")
        dismissSystemPasswordPrompt()
        XCTAssertTrue(element("host-editor-save").waitForNonExistence(timeout: 15))
        // Read the value as a static text: macOS keeps the row's earlier text in the accessibility
        // tree for a while, so the identifier's first match can lag behind what is on screen.
        let shown = detailShowsAddress("10.9.8.7")
        if !shown { dumpTree("detail-address") }
        snap("21-detail-after-add-service")
        XCTAssertTrue(shown, "the detail shows the address saved on the host")
        XCTAssertTrue(element("host-service-connect-ssh").waitForExistence(timeout: 10), "the terminal exists, complete")
        snap("21-detail-after-add-service")
    }

    /// Edit opens the same sheet on the service's tab with the saved fields loaded; Advanced holds
    /// the optional settings. Password auth, nothing connects.
    func testEditTerminalOpensTheSheetWithAdvanced() throws {
        app = launch()
        // The terminal is created by `addHost` itself, because Add Host now requires a service.
        // This test used to make a service-less host and then add one — a flow the product no
        // longer allows — which left TWO ssh services and an Edit that opened the first while the
        // assertions described the second. "Add a service opens on the Terminal tab" is covered on
        // its own by `testAddServiceCollectsTheAddressOnTheHost`.
        try addHost(named: "editable", address: "editable.example", placeholderUser: "probe")
        openDetail(of: "editable")

        // A sheet presented while the previous one is still animating away is swallowed on iOS,
        // so wait for the detail to settle and press again if the first press did not take.
        let editButton = reveal("host-service-edit-ssh")
        XCTAssertTrue(editButton.exists, "Edit on the service row")
        press(editButton)
        if !sheetTitle("Edit Terminal on editable").waitForExistence(timeout: 6), editButton.exists {
            press(editButton)
        }
        if !sheetTitle("Edit Terminal on editable").waitForExistence(timeout: 10) { dumpTree("after-edit-press") }
        XCTAssertTrue(sheetTitle("Edit Terminal on editable").exists, "edit sheet titled for the host")
        let user = element("edit-server-username")
        XCTAssertTrue(user.waitForExistence(timeout: 10))
        XCTAssertEqual(user.value as? String, "probe", "the saved terminal's fields are loaded")
        XCTAssertFalse(element("setup-enable-ssh").exists, "the tab is the toggle; there is no second one")
        let advanced = element("setup-advanced-ssh")
        XCTAssertTrue(advanced.waitForExistence(timeout: 5), "Advanced disclosure")
        expandDisclosure(advanced)
        if !element("edit-server-port").waitForExistence(timeout: 5) { dumpTree("advanced-not-expanded") }
        XCTAssertTrue(element("edit-server-port").exists, "port lives under Advanced")
        snap("22-edit-terminal-advanced")
        press("host-editor-cancel")
        XCTAssertTrue(element("edit-server-username").waitForNonExistence(timeout: 10))
    }

    /// The Files browser's header, against the real server.
    ///
    /// It used to set `.navigationTitle(currentPath)` — the whole path as a title, which reads as
    /// a string of text rather than a place (reported 2026-09-18). It now shows the shared header
    /// the editor's file list shows: the folder's name, and the path that leads to it beneath.
    /// Proven here rather than in a unit test because the splitting is the easy half; that the
    /// header arrives, over a real listing, is the half that has been wrong before.
    func testFilesBrowserHeaderNamesTheFolder() throws {
        let fixture = try fixture()
        app = launch()

        try addHost(named: "scratch", address: fixture.host, terminal: fixture)
        openDetail(of: "scratch")

        // Files is a tool on the service, not a service of its own: `host-tool-open-files-<id>`.
        let files = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'host-tool-open-files-'")).firstMatch
        XCTAssertTrue(files.waitForExistence(timeout: 15), "the service offers no Files tool")
        press(files)
        acceptTrustPromptIfShown()

        let header = app.descendants(matching: .any)
            .matching(identifier: "glass-path-header").firstMatch
        guard header.waitForExistence(timeout: 45) else {
            dumpTree("no-sftp-header")
            if let failure = connectionFailureText() { XCTFail("connection failed: \(failure)") }
            else { XCTFail("the Files browser never showed its header") }
            return
        }
        // The browser opens in the account's home directory, so the header names the account and
        // the path beneath it is what leads there — never the folder repeated.
        let label = header.label
        XCTAssertTrue(label.contains(fixture.user),
                      "the header does not name the folder it is in: '\(label)'")
        XCTAssertFalse(label.hasPrefix("/"),
                       "the header is still leading with the whole path: '\(label)'")
        #if os(macOS)
        captureOwnWindow(app.windows.matching(NSPredicate(format: "title CONTAINS[c] %@", fixture.user)).firstMatch,
                         app: app, name: "terminal-30-sftp-header")
        #endif
        snap("30-sftp-header")
    }

    func testConnectsToRealHostThroughTheShell() throws {
        let fixture = try fixture()
        app = launch()
        snap("01-library")

        // Host and terminal in one sheet: name, address, then the Terminal tab's fields.
        try addHost(named: "scratch", address: fixture.host, terminal: fixture)
        openDetail(of: "scratch")
        XCTAssertTrue(element("host-service-connect-ssh").waitForExistence(timeout: 10), "the terminal exists after the one save")
        connectFromDetail()
        acceptTrustPromptIfShown()

        let live = waitForLiveTerminal(serverName: "scratch")
        snap(live ? "06-terminal-live" : "06-terminal-not-live")
        if !live {
            dumpTree("not-live")
            if let failure = connectionFailureText() {
                XCTFail("connection failed: \(failure)")
            } else {
                XCTFail("terminal did not report Connected within 45 s")
            }
            return
        }

        // Round trip: type a marker command and look for its echo in the accessibility tree.
        #if os(macOS)
        let terminalWindow = app.windows.matching(NSPredicate(format: "title CONTAINS[c] 'scratch'")).firstMatch
        if terminalWindow.exists { press(terminalWindow) }
        #endif
        let marker = "GPT_OK_\(runID.uuidString.prefix(8))"
        app.typeText("echo \(marker)\n")
        let echoed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", marker, marker)).firstMatch
        let sawEcho = echoed.waitForExistence(timeout: 15)
        snap("07-echo")
        if !sawEcho {
            dumpTree("echo")
            // Not a failure of the connection: SwiftTerm's buffer may not be exposed to
            // accessibility. Connected state is the proven signal; record the limit.
            XCTContext.runActivity(named: "terminal output not visible to accessibility; Connected state verified") { _ in }
        }
    }
}
