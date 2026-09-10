import XCTest

/// Stage 1 library lifecycle, run against an isolated store (`--ui-testing <uuid>`), never the
/// real App Group. Screenshots go to `$GPT_SHOTS_DIR` when the runner sets it.
@MainActor
final class GlassShellLibraryUITests: XCTestCase {
    private var app: XCUIApplication!
    private var runID = UUID()

    #if os(iOS)
    private let platform = "ios"
    #elseif os(visionOS)
    private let platform = "vision"
    #else
    private let platform = "mac"
    #endif

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

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", runID.uuidString]
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

    private func tap(_ identifier: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let e = element(identifier)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing \(identifier)", file: file, line: line)
        e.tap()
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["GPT_SHOTS_DIR"] else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(platform)-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(platform)-\(name)"; attachment.lifetime = .keepAlways
        add(attachment)
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
        if scope.waitForExistence(timeout: 5) { scope.tap() }
    }

    private func addHost(named name: String) {
        let empty = element("connection-library-add-host-empty")
        if empty.waitForExistence(timeout: 3) { empty.tap() } else { tap("connection-library-add-host") }
        let field = element("host-editor-name")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText(name)
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
        let button = picker.buttons[title].exists ? picker.buttons[title] : picker.radioButtons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "settings page \(title)")
        button.tap()
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

        tap("host-connect")
        let placeholder = element("placeholder-session")
        XCTAssertTrue(placeholder.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'not part of this build'")).firstMatch.exists,
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
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to results
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to scopes
        #endif
        let favorites = scopeElement("favorites", title: "Favorites")
        XCTAssertTrue(favorites.waitForExistence(timeout: 10), "favorites scope")
        favorites.tap()
        XCTAssertTrue(element("host-row-Fav Host").waitForExistence(timeout: 10))
        snap("06-favorites-scope")
    }

    func testSearchFiltersRows() throws {
        addHost(named: "Searchable Host")
        #if os(iOS)
        if element("host-add-service").waitForExistence(timeout: 5) {
            app.navigationBars.buttons.element(boundBy: 0).tap()   // detail → results
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
        search.tap(); search.typeText("zzz-no-match")
        XCTAssertFalse(element("host-row-Searchable Host").waitForExistence(timeout: 3))
        snap("07-search-no-match")
        #if os(macOS)
        search.typeKey("a", modifierFlags: .command); search.typeText(XCUIKeyboardKey.delete.rawValue)
        #else
        if app.buttons["Clear text"].exists { app.buttons["Clear text"].tap() } else { search.doubleTap(); search.typeText(XCUIKeyboardKey.delete.rawValue) }
        #endif
        XCTAssertTrue(element("host-row-Searchable Host").waitForExistence(timeout: 10))
    }

    func testAppearanceOpacityPersistsAcrossRelaunch() {
        openSettings()
        selectSettingsPage("Appearance")
        let paints = element("layers-paints-theme")
        XCTAssertTrue(paints.waitForExistence(timeout: 10))
        let paintsBefore = "\(paints.value ?? "")"
        paints.tap()                                   // D2 default is off, so this turns it on
        let paintsAfter = "\(paints.value ?? "")"
        XCTAssertNotEqual(paintsBefore, paintsAfter, "theme toggle changed")
        var sliderValue: String?
        #if !os(visionOS)
        // Slider drags cannot be synthesized on the visionOS simulator; the toggle is the
        // persisted change there.
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
}
