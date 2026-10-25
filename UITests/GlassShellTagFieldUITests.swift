import XCTest

/// The host editor's alias and collection fields are token editors backed by the kit's
/// `GlassTagField`: chips, Return/comma commits, Backspace removes, and suggestions drawn from
/// the library's system-wide tag vocabulary. Runs against an isolated store.
@MainActor
final class GlassShellTagFieldUITests: XCTestCase {
    private var app: XCUIApplication!
    private var runID = UUID()

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            runID = UUID()
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
            self.app = app
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            app.terminate()
            #if os(macOS)
            let container = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.glasspowertools/Data/Library/Application Support/GlassPowerTools-Tests/\(runID.uuidString)")
            try? FileManager.default.removeItem(at: container)
            #endif
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

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

    /// The hierarchy at the moment of a failure, attached to the result bundle. Guessing at what
    /// the tree contained cost four re-runs the last time this suite broke; this costs one.
    ///
    /// **One snapshot of one element, never an enumeration.** The first version of this helper
    /// inventoried `app.staticTexts.allElementsBoundByIndex` the way `GlassTerminalUITests` does,
    /// and each of those collection reads takes its own snapshot — so with the UI still settling it
    /// raised "Failed to get matching snapshot: No matches found for Element at index 34" and, with
    /// `continueAfterFailure = false`, failed the test *from inside the diagnostic*, hiding the
    /// failure it was added to explain. `debugDescription` on a single window or sheet element
    /// prints the whole subtree from one snapshot and cannot race with itself.
    private func dumpTree(_ name: String) {
        let sheet = app.sheets.firstMatch
        let root = sheet.exists ? sheet : app.windows.firstMatch
        let subtree = XCTAttachment(string: root.exists ? root.debugDescription : app.debugDescription)
        subtree.name = "tag-tree-\(name)"
        subtree.lifetime = .keepAlways
        add(subtree)
    }

    private func snap(_ name: String) {
        let sheet = app.sheets.firstMatch
        captureOwnWindow(sheet.exists ? sheet : app.windows.firstMatch, app: app, name: name)
    }

    private func openHostEditor(named name: String) {
        let empty = element("connection-library-add-host-empty")
        if empty.waitForExistence(timeout: 3) { press(empty) } else { tap("connection-library-add-host") }
        let field = element("host-editor-name")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        press(field); field.typeText(name)
        // The machine's address is required to save a host.
        let address = element("host-editor-address")
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        press(address); address.typeText("\(name).example")
        fillTerminalService(user: "probe")
    }

    /// The add-host sheet arrives with the Terminal service already selected — *"adding a machine
    /// without a service doesn't make sense"* — so its required fields have to be filled or Save is
    /// **correctly refused** and the sheet stays open.
    ///
    /// This test asserted nothing about services and so never filled them, which is why it read as
    /// a tag-field failure for a week. The tree at the failure said
    /// `add-server-username-validation = "Error: Enter the SSH username"`; nothing was wrong with
    /// the chips at all. Same stale-test class as the four `GlassShellLibraryUITests` cases the
    /// same product decision invalidated — this suite was simply missed when those were repaired.
    private func fillTerminalService(user: String) {
        let username = element("add-server-username")
        XCTAssertTrue(username.waitForExistence(timeout: 10), "the Terminal tab's username field")
        press(username); username.typeText(user)
        let password = element("add-server-password")
        XCTAssertTrue(password.waitForExistence(timeout: 5), "the default method's password field")
        #if os(macOS)
        // Tab from the username rather than clicking the password: clicking a `SecureField` on a
        // freshly laid-out sheet does not reliably take first responder, and the next `typeText`
        // fails with "Neither element nor any descendant has keyboard focus". The username is
        // already focused, so Tab moves focus with no hit-testing and no race. Established in
        // `GlassShellLibraryUITests` after four attempts at fixing the click.
        app.typeKey(.tab, modifierFlags: [])
        password.typeText("not-a-real-password")
        #else
        press(password); password.typeText("not-a-real-password")
        #endif
    }

    /// visionOS offers to save a typed password to iCloud Keychain once the sheet commits, and the
    /// alert covers the app so every later assertion fails. The app stores credentials itself.
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

    /// Types a token and commits it with Return.
    private func addTag(_ tag: String, to fieldID: String) {
        let input = element("\(fieldID).input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "missing \(fieldID).input")
        press(input)
        input.typeText(tag + "\n")
    }

    /// Aliases and collections sit under "Also known as & Collections", collapsed by default.
    private func expandOrganize() {
        if element("host-editor-tags.input").waitForExistence(timeout: 2) { return }
        let triangle = element("host-editor-organize")
        XCTAssertTrue(triangle.waitForExistence(timeout: 5), "organise disclosure")
        expandDisclosure(triangle)
        if !element("host-editor-tags.input").waitForExistence(timeout: 5) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "tree-organize"; tree.lifetime = .keepAlways; add(tree)
            XCTFail("could not expand Also known as & Collections")
        }
    }

    /// Expands one of the sheet's disclosure rows (a plain button row, see `GlassFormDisclosureStyle`).
    private func expandDisclosure(_ row: XCUIElement) {
        if "\(row.value ?? "")" == "expanded" { return }
        press(row)
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in "\(row.value ?? "")" == "expanded" }, object: nil)
        _ = XCTWaiter().wait(for: [done], timeout: 3)
    }

    func testCollectionsAreChipsAndFeedTheSystemWideVocabulary() throws {
        // First host: two collections typed as tokens.
        openHostEditor(named: "alpha")
        expandOrganize()
        addTag("Clients", to: "host-editor-tags")
        addTag("Lab", to: "host-editor-tags")
        XCTAssertTrue(element("host-editor-tags.tag.0").waitForExistence(timeout: 5), "first chip")
        XCTAssertTrue(element("host-editor-tags.tag.1").waitForExistence(timeout: 5), "second chip")
        XCTAssertEqual(element("host-editor-tags.tag.0").label, "Clients, tag")
        snap("tag-field-two-chips")
        #if os(iOS)
        // The input's accessibility frame is its own box, not the row. VoiceOver outlines the
        // field by it and activates it at its centre; when it was the whole row, the outline took
        // in the chips and the centre fell on Lab's remove button (2026-10-25, real VoiceOver on
        // the iOS 27.1 simulator). Measured on iOS only.
        let inputFrame = element("host-editor-tags.input").frame
        for chip in ["host-editor-tags.tag.0", "host-editor-tags.tag.1"] {
            XCTAssertFalse(inputFrame.intersects(element(chip).frame),
                           "the input's frame \(inputFrame) covers \(chip) \(element(chip).frame)")
        }
        #endif

        // Comma commits too, and duplicates (any case) are dropped.
        addTag("clients,", to: "host-editor-tags")
        XCTAssertFalse(element("host-editor-tags.tag.2").waitForExistence(timeout: 2), "a case-insensitive duplicate is not a third chip")
        // And Lab is still there: a tap at the input's centre once landed on Lab's remove button
        // and deleted it, and the third-chip check above passed regardless (2026-10-25, Duo).
        XCTAssertEqual(element("host-editor-tags.tag.1").label, "Lab, tag", "the chips are still Clients and Lab")

        #if os(macOS)
        // Backspace on the empty input removes the last chip; the alias field is independent.
        let input = element("host-editor-tags.input")
        press(input); input.typeKey(.delete, modifierFlags: [])
        XCTAssertFalse(element("host-editor-tags.tag.1").waitForExistence(timeout: 2), "Backspace removed Lab")
        addTag("Lab", to: "host-editor-tags")
        #endif
        addTag("Foxtrot", to: "host-editor-aliases")
        XCTAssertTrue(element("host-editor-aliases.tag.0").waitForExistence(timeout: 5), "alias chip")
        #if os(iOS)
        app.tapUntilSheetCloses("host-editor-save")
        #else
        tap("host-editor-save")
        #endif
        dismissSystemPasswordPrompt()
        if !(element("host-add-service").waitForExistence(timeout: 15) || element("host-row-alpha").waitForExistence(timeout: 15)) {
            snap("save-did-not-settle")
            dumpTree("save-did-not-settle")
            // The sheet staying open means the save was refused, and the form says why. Read it
            // out rather than reporting "the sheet did not close", which describes a symptom and
            // has misled this project before.
            // The sheet reports per-field validation, not one `host-editor-error` banner — reading
            // only the banner is how this failure stayed anonymous.
            let banner = element("host-editor-error")
            let field = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier ENDSWITH '-validation'")).firstMatch
            let reason = banner.exists ? banner.label
                : (field.exists ? "\(field.identifier): \((field.value as? String) ?? "")" : "")
            XCTFail("after Save neither the detail nor the row appeared\(reason.isEmpty ? "" : "; form error: \(reason)")")
        }

        // Second host: the vocabulary offers the first host's collections before anything is typed.
        openHostEditor(named: "beta")
        expandOrganize()
        let input2 = element("host-editor-tags.input")
        XCTAssertTrue(input2.waitForExistence(timeout: 10))
        press(input2)
        let suggestion = element("host-editor-tags.suggestion.0")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "system-wide suggestions appear on focus")
        XCTAssertEqual(suggestion.label, "Add Clients")
        snap("tag-field-suggestions")
        press(suggestion)
        XCTAssertTrue(element("host-editor-tags.tag.0").waitForExistence(timeout: 5), "picking a suggestion adds a chip")
        XCTAssertEqual(element("host-editor-tags.tag.0").label, "Clients, tag")
        // A chosen tag is no longer offered; "Lab" remains.
        XCTAssertTrue(element("host-editor-tags.suggestion.0").waitForExistence(timeout: 5))
        XCTAssertEqual(element("host-editor-tags.suggestion.0").label, "Add Lab")
        #if os(iOS)
        app.tapUntilSheetCloses("host-editor-save")
        #else
        tap("host-editor-save")
        #endif
        dismissSystemPasswordPrompt()

        #if !os(visionOS)
        // The sidebar's Collections scope lists the shared tag. iPhone pushed to the new host's
        // detail; pop back to the scopes list first.
        #if os(iOS)
        if element("host-add-service").waitForExistence(timeout: 10) {
            press(app.backButton)   // detail → results
            press(app.backButton)   // results → scopes
        }
        #endif
        // Matched by identifier, not by label. A Mac sidebar scope row publishes its text as the
        // element's **value** and leaves `label` empty, so the previous
        // `label CONTAINS[c] 'Clients'` predicate could never match however right the app was —
        // the tree at the failure showed `glass-library-scope-collection-clients` sitting there
        // with `value: Clients` and a count of 1. On iOS the row's title text carries it as its
        // label (`libraryScope`). The identifier carries the collection's slug, which is the tag
        // lowercased, so it says the same thing without depending on where the text surfaces.
        let collection = app.libraryScope("collection-clients")
        if !collection.waitForExistence(timeout: 10) {
            snap("no-collection-scope")
            dumpTree("no-collection-scope")
            XCTFail("the Clients collection does not appear in the sidebar")
        }
        XCTAssertEqual(collection.shownText, "Clients",
                       "the scope row names the collection the first host introduced")
        #endif
    }
}
