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

    private func addHost(named name: String) {
        let empty = element("connection-library-add-host-empty")
        if empty.waitForExistence(timeout: 3) { press(empty) } else { tap("connection-library-add-host") }
        let field = element("host-editor-name")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        press(field); field.typeText(name)
        tap("host-editor-save")
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

    func testAddHostAddServiceConnectPlaceholder() {
        snap("01-empty-library")
        addHost(named: "Probe Host")
        openDetail(of: "Probe Host")
        snap("02-host-detail-no-services")

        tap("host-add-service")
        XCTAssertTrue(element("service-editor-save").waitForExistence(timeout: 10))
        tap("service-editor-save")
        let rowIcon = element("host-service-ssh"), detailConnect = element("host-service-connect-ssh")
        XCTAssertTrue(detailConnect.waitForExistence(timeout: 10) || rowIcon.waitForExistence(timeout: 5),
                      "ssh service after adding the default service (detail Connect or row icon)")
        snap("03-host-with-ssh-service")

        // SSH is a live capability since Stage 2, so Connect on it opens the terminal. The
        // placeholder is the contract for kinds no capability owns yet: use a seeded database
        // service for that assertion.
        app.terminate()
        runID = UUID()   // a fresh isolated store: the seeder only fills an empty catalog
        app = launch(extraArguments: ["--ui-testing-seed-hosts", "dbhost:database"])
        openDetail(of: "dbhost")
        tap("host-connect")
        let placeholder = element("placeholder-session")
        XCTAssertTrue(placeholder.waitForExistence(timeout: 10))
        // macOS exposes static text as `value`, touch platforms as `label`.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'not part of this build' OR value CONTAINS 'not part of this build'")).firstMatch.exists,
                      "placeholder must say the capability is absent")
        snap("04-connect-placeholder")
        tap("placeholder-done")
        XCTAssertFalse(placeholder.waitForExistence(timeout: 3))
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
