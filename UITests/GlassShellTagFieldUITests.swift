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
    }

    /// Types a token and commits it with Return.
    private func addTag(_ tag: String, to fieldID: String) {
        let input = element("\(fieldID).input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "missing \(fieldID).input")
        press(input)
        input.typeText(tag + "\n")
    }

    func testCollectionsAreChipsAndFeedTheSystemWideVocabulary() throws {
        // First host: two collections typed as tokens.
        openHostEditor(named: "alpha")
        addTag("Clients", to: "host-editor-tags")
        addTag("Lab", to: "host-editor-tags")
        XCTAssertTrue(element("host-editor-tags.tag.0").waitForExistence(timeout: 5), "first chip")
        XCTAssertTrue(element("host-editor-tags.tag.1").waitForExistence(timeout: 5), "second chip")
        XCTAssertEqual(element("host-editor-tags.tag.0").label, "Clients, tag")
        snap("tag-field-two-chips")

        // Comma commits too, and duplicates (any case) are dropped.
        addTag("clients,", to: "host-editor-tags")
        XCTAssertFalse(element("host-editor-tags.tag.2").waitForExistence(timeout: 2), "a case-insensitive duplicate is not a third chip")

        #if os(macOS)
        // Backspace on the empty input removes the last chip; the alias field is independent.
        let input = element("host-editor-tags.input")
        press(input); input.typeKey(.delete, modifierFlags: [])
        XCTAssertFalse(element("host-editor-tags.tag.1").waitForExistence(timeout: 2), "Backspace removed Lab")
        addTag("Lab", to: "host-editor-tags")
        #endif
        addTag("Beast", to: "host-editor-aliases")
        XCTAssertTrue(element("host-editor-aliases.tag.0").waitForExistence(timeout: 5), "alias chip")
        tap("host-editor-save")
        XCTAssertTrue(element("host-add-service").waitForExistence(timeout: 15) || element("host-row-alpha").waitForExistence(timeout: 15))

        // Second host: the vocabulary offers the first host's collections before anything is typed.
        openHostEditor(named: "beta")
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
        tap("host-editor-save")

        #if !os(visionOS)
        // The sidebar's Collections scope lists the shared tag. iPhone pushed to the new host's
        // detail; pop back to the scopes list first.
        #if os(iOS)
        if element("host-add-service").waitForExistence(timeout: 10) {
            press(app.navigationBars.buttons.element(boundBy: 0))   // detail → results
            press(app.navigationBars.buttons.element(boundBy: 0))   // results → scopes
        }
        #endif
        let collection = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'glass-library-scope-collection-' AND label CONTAINS[c] 'Clients'")).firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 10), "the Clients collection appears in the sidebar")
        #endif
    }
}
