import XCTest

/// The device's own host (D8) in the running app: always present, first in the library, with no
/// address to type, no way to delete it, and — on the Mac — its built-in shell.
@MainActor
final class GlassShellLocalHostUITests: XCTestCase {
    private var app: XCUIApplication!
    private var runID = UUID()

    /// What the app calls this device. Mirrors `GlassLocalHost.displayName`.
    private var localName: String {
        #if os(macOS)
        "This Mac"
        #elseif os(visionOS)
        "This Apple Vision Pro"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "This iPad" : "This iPhone"
        #endif
    }

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
            let container = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.glasspowertools/Data/Library/Application Support/GlassPowerTools-Tests/\(runID.uuidString)")
            try? FileManager.default.removeItem(at: container)
            #endif
        }
    }

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
        return app
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

    private func snap(_ name: String) {
        let sheet = app.sheets.firstMatch
        let subject = sheet.exists ? sheet : app.windows.firstMatch
        captureOwnWindow(subject, app: app, name: name)
    }

    private func enterAllConnections() {
        #if os(visionOS)
        let scope = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", "All",
                        XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.tab.rawValue)).firstMatch
        #else
        let scope = element("glass-library-scope-all-connections")
        #endif
        if scope.waitForExistence(timeout: 5) { press(scope) }
    }

    /// It is there on a first launch, with nothing seeded and nothing added.
    func testTheDeviceIsInTheLibraryFromTheFirstLaunch() {
        enterAllConnections()
        let row = element("host-row-\(localName)")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "\(localName) should be in the library")
        snap("30-local-host-row")

        press(row)
        let address = element("host-detail-address")
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        // The host has no address and is never asked for one: the detail says what it is rather
        // than "Not set", which would read as something still to be filled in.
        XCTAssertTrue(address.value as? String == "This device" || address.label.contains("This device"),
                      "address row should say This device, was value=\(String(describing: address.value)) label=\(address.label)")
        snap("31-local-host-detail")
    }

    /// The Mac's shell is a service on it, connectable, with nothing to configure. Off the Mac
    /// there is no local shell and the host says it has no services rather than showing a dead row.
    func testTheBuiltInShellIsThereOnTheMacAndNowhereElse() {
        enterAllConnections()
        let row = element("host-row-\(localName)")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        press(row)

        #if os(macOS)
        let connect = element("host-service-connect-ssh")
        XCTAssertTrue(connect.waitForExistence(timeout: 10), "the built-in Local Shell is a service on this device")
        XCTAssertTrue(app.staticTexts["Local Shell"].waitForExistence(timeout: 5))
        // Nothing is stored for a built-in service, so it has no Edit: a sheet opened on it
        // would have nothing to show and would report the service as broken.
        XCTAssertFalse(element("host-service-edit-ssh").exists, "a built-in service offers no Edit")
        #else
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No services yet")).firstMatch
            .waitForExistence(timeout: 10), "there is no local shell off the Mac, so nothing is offered")
        #endif
        snap("32-local-host-services")
    }

    /// With more than one service its row offers the picker alone: "connect the machine" has no
    /// meaning on the device you are already using, so the play half of the split control is not
    /// drawn at all rather than drawn and refused.
    func testSeveralServicesGiveThePickerAndNoConnectAll() {
        app.terminate()
        runID = UUID()
        app = launch(extraArguments: ["--ui-testing-seed-local-services",
                                      "database:notes.sqlite|database:gpt_test"])
        enterAllConnections()
        let row = element("host-row-\(localName)")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        // macOS folds a row's children into the row element, so its label is where the control's
        // shape is visible: the picker is there and the connect-the-machine half is not.
        XCTAssertTrue(row.label.contains("Choose a service"), "the picker is the control: \(row.label)")
        XCTAssertFalse(row.label.contains("Connect all services"),
                       "there is no connect-the-machine button on this device: \(row.label)")
        snap("34-local-host-picker-only")

        // The row's trailing control is a menu, so the click that selects the host has to land on
        // the name rather than in the middle of the row.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).click()

        // Both databases are separate services on one host — the case the shell had never been
        // exercised with — and each row is addressable on its own.
        XCTAssertTrue(element("host-service-connect-database").waitForExistence(timeout: 10))
        XCTAssertTrue(element("host-service-connect-database-2").exists,
                      "the second service of a kind carries its own identifier")
        XCTAssertTrue(app.staticTexts["notes.sqlite"].exists && app.staticTexts["gpt_test"].exists)
        XCTAssertFalse(element("host-connect").exists,
                       "and the detail's action bar offers the picker too, never connect-all")
        snap("35-local-host-several-services")
    }

    /// Editing the device edits its name and collections; it never offers to delete it, and the
    /// Terminal tab is not one of the kinds it will take (its terminal is the built-in shell).
    func testEditingTheDeviceOffersNoDeleteAndNoTerminalTab() {
        enterAllConnections()
        let row = element("host-row-\(localName)")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        press(row)
        let edit = element("host-edit")
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        press(edit)

        XCTAssertTrue(element("host-editor-name").waitForExistence(timeout: 10), "the sheet opened")
        XCTAssertFalse(element("host-editor-delete").exists, "this device is not a host you can delete")
        snap("33-local-host-edit-sheet")
        press(element("host-editor-cancel"))
    }
}
