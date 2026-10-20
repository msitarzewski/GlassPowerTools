#if os(iOS) || os(visionOS)
import XCTest

/// Xcode's accessibility audit (`performAccessibilityAudit`) over the app's common tasks, for the
/// App Store's Accessibility Nutrition Labels (2026-10-18): the library, adding a host, a host's
/// services, every capability's session and its settings, Active, workgroups and Settings.
///
/// Surfaces open through the demo hooks (`--demo-open`, `App/GlassDemoMode.swift`) on made-up
/// machines, or through the library's own buttons. The audit finds what a machine can find: missing
/// descriptions, hit regions, clipped text, text that does not follow the text size, contrast. It
/// cannot tell whether VoiceOver's reading of a screen makes sense; that takes a person
/// (`memory-bank/tasks/2026-10/2026-10-18_accessibility-audit.md`).
///
/// What fails a test: an element with no description, which VoiceOver reads as nothing — none is
/// left on these screens. Every other issue (contrast, text size, clipping, hit areas) is printed as
/// an `A11Y|…` line and not recorded, while the owner decides the visual proposals in the task note.
///
/// Runner environment (pass as `TEST_RUNNER_<name>` to `xcodebuild test`):
/// - `GPT_A11Y_CONTENT_SIZE`: a text size for the app, such as
///   `UICTContentSizeCategoryAccessibilityXXXL`; the default is the device's.
/// - `GPT_A11Y_INVENTORY=1`: record nothing, only print, to list everything.
/// - `GPT_A11Y_STRICT=1`: record every issue.
///
/// **On iPad, run each test on a fresh install** (`xcrun simctl uninstall` before each
/// `-only-testing:` run). iPadOS restores the windows an earlier test opened — a database's
/// "Connection Closed" — and they stand in front of the surface, which the audit then misses.
///
/// Rule 21: never run alongside another XCUITest target.
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    private static let hosts = "alpha@192.0.2.10:ssh+database|bravo@192.0.2.20:ssh+rdp"

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var inventory: Bool { environment["GPT_A11Y_INVENTORY"] == "1" }
    private var strict: Bool { environment["GPT_A11Y_STRICT"] == "1" }
    private var contentSize: String? { environment["GPT_A11Y_CONTENT_SIZE"].flatMap { $0.isEmpty ? nil : $0 } }

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = true }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    // MARK: - Launch and audit

    private func launch(_ extra: [String] = [], settle: TimeInterval = 10) {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-hosts", Self.hosts] + extra
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        self.app = app
        Thread.sleep(forTimeInterval: settle)
    }

    private func open(_ surface: String, _ extra: [String] = [], settle: TimeInterval = 12) {
        launch(["--demo-open", surface] + extra, settle: settle)
        XCTAssertEqual(app.state, .runningForeground, "the app stopped opening \(surface)")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func tap(_ identifier: String) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 15), "\(identifier) did not appear")
        target.tap()
    }

    private static func name(of type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"), (.trait, "trait"),
        ]
        let found = names.filter { type.contains($0.0) }.map(\.1)
        return found.isEmpty ? "other(\(type.rawValue))" : found.joined(separator: "+")
    }

    /// Audits what is on screen and prints every issue; records the ones that fail (see above).
    private func audit(_ surface: String) throws {
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad"
            : UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "Vision"
        let size = contentSize ?? "default"
        var count = 0
        #if !os(visionOS)
        // The visionOS simulator cannot screenshot through XCUITest (`GlassDemoMode.swift`).
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "a11y-\(device)-\(surface)-\(size)"
        shot.lifetime = .keepAlways
        add(shot)
        #endif
        try app.performAccessibilityAudit(for: .all) { issue in
            count += 1
            let element = issue.element
            let what = element.map { e in
                "\(e.elementType.rawValue)|id=\(e.identifier)|label=\(e.label)|frame=\(NSCoder.string(for: e.frame))"
            } ?? "no element"
            let line = "A11Y|\(device)|\(surface)|\(size)|\(Self.name(of: issue.auditType))|\(issue.compactDescription)|\(what)"
            print(line)
            if self.inventory { return true }
            if self.strict { return false }
            // "No description" with no label at all; the audit's "label not human-readable" also
            // falls under this type, and flags file names such as compose.yaml.
            return !(issue.auditType.contains(.sufficientElementDescription) && (element?.label.isEmpty ?? true))
        }
        print("A11Y-DONE|\(device)|\(surface)|\(size)|\(count) issues")
    }

    // MARK: - The library

    func testLibrary() throws {
        launch()
        try audit("library")
    }

    func testLibraryOverview() throws {
        open("library-history")
        try audit("library-history")
    }

    func testAddHost() throws {
        launch()
        let empty = element("connection-library-add-host-empty")
        if empty.waitForExistence(timeout: 3) { empty.tap() } else { tap("connection-library-add-host") }
        XCTAssertTrue(element("setup-sections").waitForExistence(timeout: 15), "Add Host did not open")
        Thread.sleep(forTimeInterval: 2)
        try audit("add-host")
    }

    func testHostServices() throws {
        open("connections-host")
        try audit("connections-host")
    }

    func testSettings() throws {
        launch()
        tap("connection-library-settings")
        XCTAssertTrue(element("settings-sections").waitForExistence(timeout: 15), "Settings did not open")
        Thread.sleep(forTimeInterval: 2)
        try audit("settings")
    }

    func testActive() throws {
        open("active")
        try audit("active")
    }

    func testWorkgroups() throws {
        open("workgroups")
        try audit("workgroups")
    }

    // MARK: - Sessions

    func testTerminal() throws {
        open("btop")
        try audit("terminal")
    }

    func testTerminalSettings() throws {
        open("terminal-settings")
        try audit("terminal-settings")
    }

    func testFiles() throws {
        open("files")
        try audit("files")
    }

    func testDatabase() throws {
        open("database")
        try audit("database")
    }

    func testDatabaseSettings() throws {
        open("database-settings")
        try audit("database-settings")
    }

    func testDesktop() throws {
        open("desktop")
        try audit("desktop")
    }

    func testDesktopSettings() throws {
        open("desktop-settings")
        try audit("desktop-settings")
    }

    func testDesktopDisconnected() throws {
        open("desktop-disconnected")
        try audit("desktop-disconnected")
    }

    func testEditor() throws {
        open("editor")
        try audit("editor")
    }

    func testEditorSettings() throws {
        open("editor-settings")
        try audit("editor-settings")
    }
}
#endif
