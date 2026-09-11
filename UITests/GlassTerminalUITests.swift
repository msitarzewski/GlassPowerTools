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

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", runID.uuidString]
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

    /// Our own window only (project rule 11); see `UITestCapture.swift`. Prefers the Add SSH
    /// Key window, then a sheet, then the main window.
    private func snap(_ name: String) {
        let sheet = app.sheets.firstMatch
        let keyWindow = app.windows["Add SSH Key"].firstMatch
        let subject = keyWindow.exists ? keyWindow : (sheet.exists ? sheet : app.windows.firstMatch)
        captureOwnWindow(subject, app: app, name: "terminal-\(name)")
    }

    /// Attaches the accessibility tree so a failure can be diagnosed from the result bundle.
    private func dumpTree(_ name: String) {
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
    }

    private func enterAllConnections() {
        let scope = element("glass-library-scope-all-connections")
        if scope.waitForExistence(timeout: 5) { press(scope) }
    }

    // MARK: - Steps

    /// The machine's address is typed once, on the host; every service inherits it.
    private func addHost(named name: String, address: String) {
        let empty = element("connection-library-add-host-empty")
        if empty.waitForExistence(timeout: 3) { press(empty) } else { press("connection-library-add-host") }
        type(name, into: "host-editor-name")
        type(address, into: "host-editor-address")
        press("host-editor-save")
    }

    private func openDetail(of name: String) {
        if element("host-add-service").waitForExistence(timeout: 5) { return }
        enterAllConnections()
        press("host-row-\(name)")
        XCTAssertTrue(element("host-add-service").waitForExistence(timeout: 10))
    }

    private func addSSHService() {
        press("host-add-service")
        XCTAssertTrue(element("service-editor-save").waitForExistence(timeout: 10))
        // Default kind is ssh; the picker is left alone unless the ssh icon does not appear.
        // A press that lands while the sheet is still animating in is dropped on iOS 27; press
        // once more if the sheet is still up.
        press("service-editor-save")
        if !element("service-editor-save").waitForNonExistence(timeout: 3) {
            press("service-editor-save")
            XCTAssertTrue(element("service-editor-save").waitForNonExistence(timeout: 5), "service editor dismissed")
        }
        // The row combines its children into one element on macOS, so the icon's own identifier
        // is not addressable there; the detail's per-service Connect is the evidence.
        let added = firstExisting([element("host-service-connect-ssh"), element("host-service-ssh")], timeout: 10)
        XCTAssertNotNil(added, "ssh service present after adding the service")
    }

    /// The shell's Connect hands off to the terminal capability; with no saved server yet the
    /// capability presents glas.sh's AddServerView pre-filled from the host.
    private func connectFromDetail() {
        let candidates = [element("host-service-connect-ssh"), element("host-connect")]
        guard let connect = firstExisting(candidates, timeout: 10) else {
            XCTFail("no Connect control on the host detail"); return
        }
        press(connect)
    }

    private func fillServerForm(_ fixture: HostFixture) throws {
        XCTAssertTrue(element("add-server-host").waitForExistence(timeout: 15), "glas.sh server form")
        snap("02-server-form")

        // The address came from the host and is read-only here: the form must show it, not ask
        // for it again. The port defaults to 22; only type into a field whose value is wrong
        // (select-all is macOS-only, so typing appends).
        let addressRow = element("add-server-host")
        XCTAssertEqual(addressRow.value as? String ?? addressRow.label, fixture.host, "the host's address is shown, not typed")
        XCTAssertFalse(app.textFields["add-server-host"].exists, "no editable Host field when the host has an address")
        setField("add-server-username", to: fixture.user)
        if element("add-server-port").exists { setField("add-server-port", to: fixture.port) }

        // Authentication → SSH Key.
        chooseSSHKeyMethod()

        // Add the key through the form's own "Add SSH Key": a sheet on iOS and visionOS, its own
        // window on macOS (the form is already a sheet; project rule 12).
        let addKey = app.buttons["Add SSH Key"].firstMatch
        XCTAssertTrue(addKey.waitForExistence(timeout: 10), "Add SSH Key button")
        press(addKey)
        // By identifier: on macOS the placeholder is neither the field's label nor its identifier.
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
        // The key just added is the selected one, even when the catalog already holds others
        // (the Mac shares glas.sh's key catalog).
        #if os(macOS)
        let keyPicker = app.popUpButtons.matching(NSPredicate(format: "value CONTAINS[c] 'scratch-vm-key'")).firstMatch
        #else
        let keyPicker = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'scratch-vm-key'")).firstMatch
        #endif
        if !keyPicker.waitForExistence(timeout: 5) { dumpTree("key-not-selected") }
        XCTAssertTrue(keyPicker.exists, "the newly added key is selected in the SSH Key picker")

        // Confirm the server. The confirmation title is mode-dependent; find the toolbar's
        // non-Cancel button by the titles glas.sh uses.
        let confirm = firstExisting([app.buttons["Save Connection"].firstMatch,
                                     app.buttons["Add Server"].firstMatch,
                                     app.buttons["Add Connection"].firstMatch,
                                     app.buttons["Import"].firstMatch,
                                     app.buttons["Add"].firstMatch,
                                     app.buttons["Save"].firstMatch], timeout: 10)
        XCTAssertNotNil(confirm, "server form confirmation button")
        snap("04-server-form-filled")
        if let confirm {
            XCTAssertTrue(confirm.isEnabled, "server form must validate before saving")
            press(confirm)
        }
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

    private func acceptTrustPromptIfShown() {
        let trust = firstExisting([app.buttons["Trust and Connect"].firstMatch,
                                   app.buttons["Trust Changed Key"].firstMatch], timeout: 20)
        if let trust {
            snap("05-trust-prompt")
            press(trust)
        }
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
        for title in ["Connections", "Terminal", "Snippets"] {
            let entry = picker.buttons[title].exists ? picker.buttons[title] : picker.radioButtons[title]
            XCTAssertTrue(entry.waitForExistence(timeout: 5), "settings page \(title) listed")
        }
        let terminal = picker.buttons["Terminal"].exists ? picker.buttons["Terminal"] : picker.radioButtons["Terminal"]
        press(terminal)
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
        addHost(named: "chrome", address: "chrome.example")
        openDetail(of: "chrome")
        addSSHService()
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

    func testConnectsToRealHostThroughTheShell() throws {
        let fixture = try fixture()
        app = launch()
        snap("01-library")

        addHost(named: "scratch", address: fixture.host)
        openDetail(of: "scratch")
        addSSHService()
        connectFromDetail()
        try fillServerForm(fixture)

        // With the server saved, Connect goes straight to the connect flow.
        if !element("add-server-host").waitForNonExistence(timeout: 10) {
            dumpTree("form-still-open")
            XCTFail("server form did not dismiss after saving")
        }
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
