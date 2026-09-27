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
    /// The control inventory at a failure, attached to the result bundle.
    ///
    /// Added because every diagnosis in this file's recent history came from the tree and not from
    /// the assertion text: the same `Picker` is a PopUpButton with menu items on macOS and a pushed
    /// list of buttons off it, and "the picker did not change" says nothing about which of those
    /// was on screen.
    /// What the Material picker currently shows.
    ///
    /// macOS exposes the selection as the element's `value`. visionOS exposes **nothing** there and
    /// puts it in the label instead, as `"Material\nMax"` — title and selection together. Reading
    /// only `value` made a working selection look like a picker that refused to change: the test
    /// failed with *"it still reads ''"* while the control on screen already said `Max`.
    private func materialSelection() -> String {
        let picker = element("layers-material")
        let value = "\(picker.value ?? "")"
        return value.isEmpty ? picker.label : value
    }

    private func dumpTree(_ name: String) {
        var lines: [String] = []
        lines.append("buttons: " + app.buttons.allElementsBoundByIndex.prefix(60)
            .map { "'\($0.label)'/'\($0.identifier)'" }.joined(separator: ", "))
        lines.append("staticTexts: " + app.staticTexts.allElementsBoundByIndex.prefix(60)
            .map { "'\($0.label.prefix(40))'/'\($0.identifier)'" }.joined(separator: ", "))
        lines.append("cells: \(app.cells.count)  menuItems: " + app.menuItems.allElementsBoundByIndex
            .prefix(40).map { "'\($0.label)'" }.joined(separator: ", "))
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "shell-tree-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
    /// Adds a host through the setup sheet.
    ///
    /// `terminalUser` defaults to a real value because **Add Host now requires a service**: a
    /// machine with nothing on it is not worth a row, so the sheet pre-selects the first available
    /// tab and its fields are required (`GlassShellSetup.swift:76`). Three tests here passed `nil`,
    /// which produced "Error: Enter the SSH username." and a sheet that correctly refused to close
    /// — reported as *"the sheet closes after Save"*, which reads like a dismissal bug and is the
    /// opposite: validation working. They had been failing on macOS too, unnoticed since the rule
    /// landed, because the suite was not re-run.
    private func addHost(named name: String, address: String = "10.9.8.7", terminalUser: String? = "tester") {
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
            type(terminalUser, into: user)
            let password = reveal("add-server-password")
            XCTAssertTrue(password.exists, "password is the default method's required field")
            #if os(macOS)
            // **Tab from the username rather than clicking the password.**
            //
            // Clicking a `SecureField` in a sheet that has only just re-laid itself out (enabling
            // the Terminal tab inserts these fields) does not reliably make it first responder, and
            // the next `typeText` then fails with "Neither element nor any descendant has keyboard
            // focus". Four attempts at fixing the click — a settle, ⌘A, waiting for `isHittable`,
            // a coordinate click — each changed WHICH test failed rather than whether one did,
            // which is the signature of a race, not a wrong element. The last combination made it
            // worse: four failures instead of one.
            //
            // The username field is already focused, because it was just typed into successfully.
            // Tab moves focus to the next field deterministically, with no hit-testing involved at
            // all — so there is no race left to lose.
            app.typeKey(.tab, modifierFlags: [])
            password.typeText("not-a-real-password")
            #else
            type("not-a-real-password", into: password)
            #endif
        }
        tap("host-editor-save")
        dismissSystemPasswordPrompt()
        XCTAssertTrue(element("host-editor-save").waitForNonExistence(timeout: 15), "the sheet closes after Save")
    }

    /// visionOS offers to save a typed password in iCloud Keychain after the sheet commits; the
    /// alert covers the app and every later assertion fails. The app keeps credentials in its own
    /// store, so the answer is always "Not Now" (observed on the visionOS simulator, 2026-09-11).
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

    /// Types into a field and checks the text actually landed.
    ///
    /// On visionOS a field can report `Keyboard Focused, Focused` and still swallow the first
    /// `typeText` when focus has just moved — which is exactly what happens after
    /// `enableTerminalTab()` switches tab. The symptom is not a typing error but a **save that is
    /// correctly refused**: the host's Name and Address type fine, the Terminal tab's Username
    /// arrives empty, the form shows "Error: Enter the SSH username." and the sheet stays open.
    /// Four visionOS tests failed on `"the sheet closes after Save"` for that reason, which reads
    /// like a dismissal bug and is nothing of the kind — the app was right to refuse.
    ///
    /// A `SecureTextField` reports its value as bullets, so "did it land" is "is the value
    /// non-empty and not the placeholder" rather than an equality check.
    private func type(_ text: String, into e: XCUIElement,
                      file: StaticString = #filePath, line: UInt = #line) {
        // A SecureTextField gets ONE attempt and no verification: its value is bullets or nil, so
        // "did it land" cannot be read, and pressing it again when it is already focused drops
        // focus — the retry then fails with "Neither element nor any descendant has keyboard
        // focus". That is a regression this helper caused on macOS the first time it was written,
        // on a field that had never been the problem: visionOS swallowed the USERNAME, a plain
        // text field, after a tab switch.
        guard e.elementType != .secureTextField else {
            // One press, then a settle, then type — and never a second press.
            //
            // Two distinct faults meet on this field. Re-pressing it once focused DROPS focus, so
            // the verifying loop below must not run here (its value is bullets or nil and can
            // never satisfy `landed()` anyway). And on a COLD launch the first sheet's secure
            // field does not take focus by the time `typeText` dispatches: the one test that
            // drives this helper successfully happens to open and cancel a sheet beforehand, and
            // the three that failed called it as their first action after launch. Same helper,
            // same field, different warmth.
            // Three things, because two were not enough and the failure is intermittent.
            //
            // A plain `press` sometimes does not make the field first responder on a sheet that has
            // only just appeared, and the next `typeText` then fails outright with "Neither element
            // nor any descendant has keyboard focus". A settle alone does not help — a pause does
            // not focus anything. ⌘A alone helped but still failed on roughly one test per run,
            // moving between tests each time, which is the signature of a race rather than a wrong
            // element.
            //
            // So: wait until the field is actually hittable, click its centre COORDINATE (delivered
            // regardless of what scroll-to-visible thinks), then ⌘A, which is both a focus check and
            // the clear-existing-text step `GlassTerminalUITests.setField` uses.
            #if os(macOS)
            _ = e.waitForExistence(timeout: 5)
            let deadline = Date().addingTimeInterval(3)
            while !e.isHittable, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            app.typeKey("a", modifierFlags: .command)
            #else
            press(e)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            #endif
            e.typeText(text)
            return
        }
        func landed() -> Bool {
            guard let value = e.value as? String else { return false }
            return !value.isEmpty && value != (e.placeholderValue ?? "")
        }
        for _ in 0..<3 {
            press(e)
            e.typeText(text)
            if landed() { return }
        }
        XCTAssertTrue(landed(), "‘\(text)’ did not reach \(e.identifier)", file: file, line: line)
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

    /// Choosing the tab is what adds the service — there is no separate toggle.
    private func enableTerminalTab() {
        let sections = element("setup-sections")
        XCTAssertTrue(sections.waitForExistence(timeout: 10), "service tabs")
        let tab = sections.buttons["Terminal"].exists ? sections.buttons["Terminal"] : sections.radioButtons["Terminal"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Terminal tab")
        press(tab)
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
        #if os(macOS)
        // Settings on a Mac is a row of icon tabs in the window's toolbar (2026-09-25).
        XCTAssertTrue(app.toolbars.buttons["General"].firstMatch.waitForExistence(timeout: 10))
        #else
        XCTAssertTrue(element("settings-sections").waitForExistence(timeout: 10))
        #endif
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
        #elseif os(macOS)
        _ = picker
        let button = app.toolbars.buttons[title].firstMatch
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
        // Stage 3 registered the database capability, so the tab that was disabled now offers
        // the real form. Choosing the tab is what adds the service — there is no toggle — and its
        // required fields are engine, database, username and password, deliberately with no
        // address and no SSH section (D7).
        let sections = element("setup-sections")
        let databaseTab = sections.buttons["Database"].exists ? sections.buttons["Database"] : sections.radioButtons["Database"]
        if databaseTab.waitForExistence(timeout: 3) {
            press(databaseTab)
            XCTAssertFalse(element("setup-enable-database").exists, "the tab is the toggle; there is no second one")
            XCTAssertTrue(element("add-database-engine").waitForExistence(timeout: 5), "the engine picker")
            XCTAssertTrue(element("add-database-database").exists, "the database field")
            XCTAssertTrue(element("add-database-username").exists, "the username field")
            XCTAssertTrue(element("add-database-password").exists, "the password field")
            snap("02-database-tab-live")
            // Back to Terminal: choosing another tab replaces the choice, never adds a second.
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

    /// Deleting a machine is deliberate: it is not beside Connect in the detail's action bar, it
    /// is at the bottom of the sheet that edits the host (and in the row's context menu).
    func testDeleteHostLivesInTheEditSheetNotTheActionBar() {
        addHost(named: "Doomed Host")
        openDetail(of: "Doomed Host")
        XCTAssertTrue(element("host-edit").waitForExistence(timeout: 10), "Edit stays in the action bar")
        XCTAssertFalse(element("host-delete").exists, "Delete is not one slip away from Connect")

        tap("host-edit")
        XCTAssertTrue(element("host-editor-name").waitForExistence(timeout: 10), "the edit sheet")
        let delete = reveal("host-editor-delete")
        XCTAssertTrue(delete.exists, "the edit sheet is where a host is removed")
        snap("11-delete-in-edit-sheet")
        press(delete)
        let confirm = element("host-delete-confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "removal is confirmed")
        press(confirm)
        XCTAssertTrue(element("host-row-Doomed Host").waitForNonExistence(timeout: 15), "the host is gone")
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

    /// An Appearance choice survives a relaunch.
    ///
    /// Rewritten 2026-09-13. It used to drive `layers-paints-theme`, which **no longer exists**:
    /// "Paint Theme Color" was removed deliberately — painting the glass is the point of the app,
    /// so it was never optional — and nothing updated the test. It then failed on every platform,
    /// unnoticed, because the macOS suite was not re-run after that change. visionOS surfaced it
    /// only because it could finally run at all.
    ///
    /// Material is the control used now: it is a `Picker` rather than a slider, and slider drags
    /// synthesize on iOS alone (the visionOS simulator and macOS refuse them), so this is the one
    /// appearance control whose change can be driven on all three platforms.
    func testAppearanceOpacityPersistsAcrossRelaunch() {
        openSettings()
        selectSettingsPage("Appearance")

        let material = element("layers-material")
        XCTAssertTrue(material.waitForExistence(timeout: 10), "the Material picker")
        let before = materialSelection()

        // Pick a value that is definitely not the current one. The titles are NOT the case names:
        // `GlassLayerMaterial.title` maps ultraThin/thin/regular/thick to
        // **Light / Medium / Heavy / Max** (`GlassLayerState.swift:13-20`). D2's default is
        // ultraThin, so the picker reads "Light" on a fresh launch.
        let wanted = before.contains("Max") ? "Light" : "Max"
        press(material)
        // The same `Picker` is three different controls. macOS renders a PopUpButton whose options
        // are MENU ITEMS. visionOS and iOS render a navigation-style list inside the Form, so the
        // options are buttons or cells in the view tree and selecting one pops back on its own.
        // Asking only for menu items finds nothing off the Mac; asking `.any` for a label can match
        // the picker's own row, which is already showing that label once selected.
        let byMenuItem = app.menuItems[wanted].firstMatch
        let byButton = app.buttons[wanted].firstMatch
        let byCell = app.cells.containing(.staticText, identifier: wanted).firstMatch
        _ = byMenuItem.waitForExistence(timeout: 3) || byButton.waitForExistence(timeout: 3)
        let option = byMenuItem.exists ? byMenuItem : (byButton.exists ? byButton : byCell)
        guard option.exists else {
            dumpTree("material-options-\(wanted)")
            XCTFail("‘\(wanted)’ is offered; picker read ‘\(before)’", file: #filePath, line: #line)
            return
        }
        press(option)

        // Re-resolved rather than reusing `material`: off the Mac the selection happens on a pushed
        // list and the Form rebuilds when it pops, so the original reference can describe a row that
        // no longer exists.
        let deadline = Date().addingTimeInterval(8)
        var settled = false
        repeat {
            if materialSelection().contains(wanted) { settled = true; break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        if !settled { dumpTree("material-after-select-\(wanted)") }
        XCTAssertTrue(settled, "the picker took the new material; it still reads ‘\(before)’")
        let after = materialSelection()
        snap("08-appearance-material")
        closeSettings()

        app.terminate()
        app = launch()
        openSettings()
        selectSettingsPage("Appearance")
        let again = element("layers-material")
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        XCTAssertEqual(materialSelection(), after, "the material persisted across relaunch")

        tap("layers-reset")   // leave the app's own defaults at D2
        closeSettings()
    }

    /// Records from different family apps for the same machine are one row with one icon per
    /// service. Seeded through `--ui-testing-seed-hosts` (DEBUG, isolated catalog only).
    func testSameMachineRecordsAreOneRowWithAllServiceIcons() {
        app.terminate()
        runID = UUID()
        app = launch(extraArguments: ["--ui-testing-seed-hosts", "bravo:ssh|bravo:rdp|alpha:rdp+ssh"])
        enterAllConnections()
        let rows = app.descendants(matching: .any).matching(identifier: "host-row-bravo")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "bravo row")
        XCTAssertEqual(rows.count, 1, "one row per machine")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "host-row-alpha").count, 1)
        // Icons for both kinds, on both hosts: two of each across the two rows.
        #if os(macOS)
        // The kit row combines its children into one element and macOS folds the icons'
        // identifiers into the row's; the icons are evidenced by their labels in the row's label.
        for name in ["bravo", "alpha"] {
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

    /// The row's control carries no words: a play glyph that opens every service, and its own
    /// chevron that picks one. The chevron is a hit region on every platform, not a long press.
    func testRowConnectControlIsSplitAndCarriesNoLabel() {
        app.terminate()
        runID = UUID()
        app = launch(extraArguments: ["--ui-testing-seed-hosts", "alpha@10.9.8.7:rdp+ssh+database"])
        enterAllConnections()
        let row = element("host-row-alpha")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "alpha row")

        // The row no longer dates the last connection or names/counts the services; the icons do
        // that. "Connect" survives only as the play button's accessibility label, which VoiceOver
        // needs — what must be gone is the visible word.
        for banned in ["Never", "3 services", "Desktop · Terminal"] {
            XCTAssertFalse(row.label.contains(banned), "row still shows \(banned): \(row.label)")
        }
        XCTAssertFalse(app.staticTexts["Connect"].exists, "the control is a glyph, not a word")
        snap("10a-row-icons-and-split-control")

        // The chevron is exercised from the detail: on macOS the kit row combines its children
        // into one element, so controls inside a row are not addressable there.
        press(row)
        let chevron = element("host-connect-menu")
        XCTAssertTrue(chevron.waitForExistence(timeout: 10), "the chevron is its own control")
        XCTAssertTrue(chevron.isHittable, "and a real hit region, not a long press")
        press(chevron)
        let terminalItem = element("host-connect-menu-ssh")
        XCTAssertTrue(terminalItem.waitForExistence(timeout: 10), "the menu lists each service")
        snap("10-row-connect-menu")
        press(terminalItem)
        // The terminal capability owns .ssh, so choosing it opens a terminal rather than the
        // shell's "not part of this build" message that .rdp would raise.
        XCTAssertFalse(app.staticTexts["Desktop is not part of this build yet. Nothing was connected."].exists,
                       "the chosen service connected, not another one")
    }
}
