import XCTest

/// Stage 1 library lifecycle, run against an isolated store (`--ui-testing <uuid>`), never the
/// real App Group. Screenshots go to `$GPT_SHOTS_DIR` when the runner sets it.
@MainActor
final class GlassShellLibraryUITests: XCTestCase {
    private var app: XCUIApplication!
    private var runID = UUID()

    // XCTest calls the synchronous setUp/tearDown off the main actor; the async forms let a
    // @MainActor test case hop over explicitly instead of sending `self` across.
    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            runID = UUID()
            app = launch()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            app.terminate()
            #if os(macOS)
            // F9: the runner can reach the app's sandbox on macOS; remove this run's isolated store.
            let container = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.glasspowertools/Data/Library/Application Support/GlassPowerTools-Tests/\(runID.uuidString)")
            try? FileManager.default.removeItem(at: container)
            #endif
        }
    }

    // MARK: Helpers

    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", runID.uuidString] + extraArguments
        #if os(macOS)
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        #if os(macOS)
        // Synthesized clicks go to the frontmost app; a Simulator launching alongside can take
        // activation between launch and the first tap.
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        #endif
        return app
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// `tap()` compiles on macOS but does not drive SwiftUI buttons there; `click()` does.
    private func press(_ e: XCUIElement) {
        #if os(macOS)
        e.click()
        #else
        e.tap()
        #endif
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let e = element(identifier)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(identifier)", file: file, line: line)
        press(e)
    }

    /// Our own window only (project rule 11); see `UITestCapture.swift`.
    private func snap(_ name: String) {
        let sheet = app.sheets.firstMatch
        let subject = sheet.exists ? sheet : app.windows.firstMatch
        captureOwnWindow(subject, app: app, name: name)
    }

    /// The kit's sidebar list carries `glass-library-scope-<id>`; on visionOS the library is a
    /// TabView whose tabs are titled All / Favorites / Recent / Collections instead.
    private func scopeElement(_ id: String, title: String) -> XCUIElement {
        #if os(visionOS)
        let byTitle = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", title, XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.tab.rawValue)).firstMatch
        return byTitle
        #else
        return element("glass-library-scope-\(id)")
        #endif
    }

    /// iPhone shows scopes first; everything else shows results beside them.
    private func enterAllConnections() {
        let scope = scopeElement("all-connections", title: "All")
        if scope.waitForExistence(timeout: 5) { press(scope) }
    }

    /// Adds a host through the one setup sheet: name and address are the machine's, entered
    /// once. With `terminalUser` the Terminal tab is enabled and its required fields filled, so
    /// the host and its terminal are created together (password auth; nothing connects).
    private func addHost(named name: String, address: String = "10.9.8.7", terminalUser: String? = nil) {
        let empty = element("connection-library-add-host-empty")
        if empty.waitForExistence(timeout: 3) { press(empty) } else { tap("connection-library-add-host") }
        let field = element("host-editor-name")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        press(field); field.typeText(name)
        let addressField = element("host-editor-address")
        XCTAssertTrue(addressField.waitForExistence(timeout: 5), "the sheet asks for the machine's address")
        press(addressField); addressField.typeText(address)
        if let terminalUser {
            enableTerminalTab()
            let user = element("add-server-username")
            XCTAssertTrue(user.waitForExistence(timeout: 10), "the Terminal tab's required fields appear once enabled")
            press(user); user.typeText(terminalUser)
            let password = reveal("add-server-password")
            XCTAssertTrue(password.exists, "password is the default method's required field")
            press(password); password.typeText("not-a-real-password")
        }
        tap("host-editor-save")
        dismissSystemPasswordPrompt()
        XCTAssertTrue(element("host-editor-save").waitForNonExistence(timeout: 15), "the sheet closes after Save")
    }

    /// visionOS offers to save a typed password in iCloud Keychain after the sheet commits; the
    /// alert covers the app and every later assertion fails. The app keeps credentials in its own
    /// store, so the answer is always "Not Now" (observed on the visionOS simulator, 2026-09-11).
    private func dismissSystemPasswordPrompt() {
        var targets = [XCUIApplication(bundleIdentifier: "com.apple.springboard")]
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

    /// The Terminal tab is selected by default; its toggle turns the service on.
    private func enableTerminalTab() {
        let toggle = element("setup-enable-ssh")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Terminal tab toggle")
        #if os(macOS)
        press(toggle)
        #elseif os(iOS)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        #else
        toggle.tap()
        #endif
    }

    /// After saving, the shell selects the new host; on iPhone that pushes to detail directly.
    private func openDetail(of name: String) {
        if element("host-add-service").waitForExistence(timeout: 5) { return }
        enterAllConnections()
        tap("host-row-\(name)")
        XCTAssertTrue(element("host-add-service").waitForExistence(timeout: 10))
    }

    private func openSettings() {
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        tap("connection-library-settings")
        #endif
        XCTAssertTrue(element("settings-sections").waitForExistence(timeout: 10))
    }

    private func closeSettings() {
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        tap("settings-done")
        #endif
    }

    private func selectSettingsPage(_ title: String) {
        let picker = element("settings-sections")
        #if os(visionOS)
        // The sections are a TabView there; visionOS renders its tabs as the leading ornament,
        // which XCUITest exposes as a tab bar rather than as children of the TabView element.
        let candidates = [app.tabBars.buttons[title], picker.buttons[title], app.buttons[title].firstMatch]
        let button = candidates.first(where: { $0.waitForExistence(timeout: 2) }) ?? candidates[0]
        #else
        let button = picker.buttons[title].exists ? picker.buttons[title] : picker.radioButtons[title]
        #endif
        if !button.waitForExistence(timeout: 5) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "accessibility-tree-settings-\(title)"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(button.exists, "settings page \(title)")
        press(button)
    }

    // MARK: Tests

    /// One sheet: the host and its terminal are created together, complete; Connect then goes
    /// straight to the terminal (a failed attempt is fine — no setup form may appear). A kind
    /// no capability owns is a disabled tab, never a saved-but-empty service.
    func testAddHostWithTerminalInOneSheetThenConnect() {
        snap("01-empty-library")
        let empty = element("connection-library-add-host-empty")
        if empty.waitForExistence(timeout: 3) { press(empty) } else { tap("connection-library-add-host") }
        XCTAssertTrue(element("host-editor-name").waitForExistence(timeout: 10))
        XCTAssertTrue(element("setup-sections").waitForExistence(timeout: 5), "service tabs under the machine fields")
        let databaseToggle = element("setup-enable-database")
        // The Database tab exists but is disabled: nothing arrives before Stage 3.
        let sections = element("setup-sections")
        let databaseTab = sections.buttons["Database"].exists ? sections.buttons["Database"] : sections.radioButtons["Database"]
        if databaseTab.waitForExistence(timeout: 3) {
            press(databaseTab)
            XCTAssertTrue(databaseToggle.waitForExistence(timeout: 5))
            XCTAssertFalse(databaseToggle.isEnabled, "no capability: the tab's toggle is disabled")
            snap("02-database-tab-disabled")
            let terminalTab = sections.buttons["Terminal"].exists ? sections.buttons["Terminal"] : sections.radioButtons["Terminal"]
            press(terminalTab)
        }
        tap("host-editor-cancel")
        XCTAssertTrue(element("host-editor-name").waitForNonExistence(timeout: 10))

        addHost(named: "Probe Host", terminalUser: "probe")
        openDetail(of: "Probe Host")
        let detailConnect = reveal("host-service-connect-ssh")
        XCTAssertTrue(detailConnect.exists || element("host-service-ssh").exists,
                      "the terminal exists on the host right after the one save")
        XCTAssertFalse(app.buttons["Set Up…"].exists, "no pending state anywhere")
        snap("03-host-with-terminal")

        // Connect: the saved terminal connects (and fails, there is no such machine); what must
        // not happen is any setup form.
        tap("host-service-connect-ssh")
        XCTAssertFalse(element("add-server-username").waitForExistence(timeout: 5), "Connect never opens a setup form")
        let failure = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Connection Failed' OR value CONTAINS[c] 'Connection Failed' OR label CONTAINS[c] 'Connecting' OR value CONTAINS[c] 'Connecting'")).firstMatch
        _ = failure.waitForExistence(timeout: 20)
        snap("04-connect-attempt")
    }

    func testFavoriteAppearsInFavoritesScope() {
        addHost(named: "Fav Host")
        openDetail(of: "Fav Host")
        tap("host-favorite")
        XCTAssertTrue(element("host-favorite").label.contains("Remove"), "favorite toggled on")
        snap("05-favorited")

        #if os(iOS)
        press(app.navigationBars.buttons.element(boundBy: 0))   // back to results
        press(app.navigationBars.buttons.element(boundBy: 0))   // back to scopes
        #endif
        let favorites = scopeElement("favorites", title: "Favorites")
        XCTAssertTrue(favorites.waitForExistence(timeout: 10), "favorites scope")
        press(favorites)
        XCTAssertTrue(element("host-row-Fav Host").waitForExistence(timeout: 10))
        snap("06-favorites-scope")
    }

    func testSearchFiltersRows() throws {
        addHost(named: "Searchable Host")
        #if os(iOS)
        if element("host-add-service").waitForExistence(timeout: 5) {
            press(app.navigationBars.buttons.element(boundBy: 0))   // detail → results
        }
        #endif
        enterAllConnections()
        XCTAssertTrue(element("host-row-Searchable Host").waitForExistence(timeout: 10))
        var search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 5) {
            search = app.descendants(matching: .any).matching(NSPredicate(
                format: "placeholderValue == %@ OR label == %@ OR value == %@",
                "Search connections...", "Search connections...", "Search connections...")).firstMatch
        }
        #if os(visionOS)
        if !search.waitForExistence(timeout: 5) {
            throw XCTSkip("visionOS exposes no search field element for the kit's .searchable; verified on iOS and macOS")
        }
        #endif
        XCTAssertTrue(search.waitForExistence(timeout: 10), "kit search field")
        press(search); search.typeText("zzz-no-match")
        XCTAssertFalse(element("host-row-Searchable Host").waitForExistence(timeout: 3))
        snap("07-search-no-match")
        #if os(macOS)
        search.typeKey("a", modifierFlags: .command); search.typeText(XCUIKeyboardKey.delete.rawValue)
        #else
        if app.buttons["Clear text"].exists { press(app.buttons["Clear text"]) } else { search.doubleTap(); search.typeText(XCUIKeyboardKey.delete.rawValue) }
        #endif
        XCTAssertTrue(element("host-row-Searchable Host").waitForExistence(timeout: 10))
    }

    func testAppearanceOpacityPersistsAcrossRelaunch() {
        openSettings()
        selectSettingsPage("Appearance")
        // Toggle is a Switch on touch platforms and a CheckBox on macOS; `.any` can match the
        // enclosing row, so prefer the control itself.
        let anyPaints = element("layers-paints-theme")
        XCTAssertTrue(anyPaints.waitForExistence(timeout: 10))
        let control = app.switches.matching(identifier: "layers-paints-theme").firstMatch
        let box = app.checkBoxes.matching(identifier: "layers-paints-theme").firstMatch
        let paints = control.exists ? control : (box.exists ? box : anyPaints)
        let paintsBefore = "\(paints.value ?? "")"
        // D2 default is off, so this turns it on. On touch platforms the Switch element spans the
        // whole Form row and only the trailing knob toggles, so press near the trailing edge.
        #if os(macOS)
        press(paints)                                   // CheckBox: centre click
        #elseif os(iOS)
        paints.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()   // row-wide Switch: knob is trailing
        #else
        paints.tap()                                    // visionOS: the centre tap toggles; edge taps miss
        #endif
        // The value updates asynchronously after the gesture; never read it synchronously.
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in "\(paints.value ?? "")" != paintsBefore }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 5), .completed, "theme toggle value changed")
        let paintsAfter = "\(paints.value ?? "")"
        XCTAssertNotEqual(paintsBefore, paintsAfter, "theme toggle changed")
        var sliderValue: String?
        #if os(iOS)
        // Slider drags synthesize on iOS only (visionOS simulator and macOS refuse); the toggle
        // is the persisted change elsewhere.
        let slider = element("layers-opacity")
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.6)
        sliderValue = slider.value as? String
        XCTAssertNotNil(sliderValue)
        #endif
        snap("08-appearance-opacity")
        closeSettings()

        app.terminate()
        app = launch()
        openSettings()
        selectSettingsPage("Appearance")
        let paintsAgain = element("layers-paints-theme")
        XCTAssertTrue(paintsAgain.waitForExistence(timeout: 10))
        XCTAssertEqual("\(paintsAgain.value ?? "")", paintsAfter, "theme toggle persisted across relaunch")
        if let sliderValue {
            let again = element("layers-opacity")
            XCTAssertTrue(again.waitForExistence(timeout: 10))
            XCTAssertEqual(again.value as? String, sliderValue, "opacity persisted across relaunch")
        }
        tap("layers-reset")   // leave the app's own defaults at D2
        closeSettings()
    }

    /// Records from different family apps for the same machine are one row with one icon per
    /// service. Seeded through `--ui-testing-seed-hosts` (DEBUG, isolated catalog only).
    func testSameMachineRecordsAreOneRowWithAllServiceIcons() {
        app.terminate()
        runID = UUID()
        app = launch(extraArguments: ["--ui-testing-seed-hosts", "juliet:ssh|juliet:rdp|oscar:rdp+ssh"])
        enterAllConnections()
        let rows = app.descendants(matching: .any).matching(identifier: "host-row-juliet")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "juliet row")
        XCTAssertEqual(rows.count, 1, "one row per machine")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "host-row-oscar").count, 1)
        // Icons for both kinds, on both hosts: two of each across the two rows.
        #if os(macOS)
        // The kit row combines its children into one element and macOS folds the icons'
        // identifiers into the row's; the icons are evidenced by their labels in the row's label.
        for name in ["juliet", "oscar"] {
            let label = element("host-row-\(name)").label
            XCTAssertTrue(label.contains("Terminal"), "\(name) row lists the terminal icon: \(label)")
            XCTAssertTrue(label.contains("Desktop"), "\(name) row lists the desktop icon: \(label)")
        }
        #else
        XCTAssertTrue(element("host-service-ssh").waitForExistence(timeout: 5))
        XCTAssertTrue(element("host-service-rdp").waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "host-service-ssh").count, 2)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "host-service-rdp").count, 2)
        #endif
        snap("09-consolidated-hosts")
    }
}
