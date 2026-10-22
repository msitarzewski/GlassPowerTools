//
//  GlassTerminalToolsIPhoneUITests.swift
//  GlassPowerToolsUITests
//
//  A terminal's Tools menu on iPhone (the owner, 2026-10-21: "the folder icon in the tools on iphone
//  in terminal [has no] label. i dont see a settings option in terminal there either"). Every row
//  says what it does, and Settings is reached from it.
//
//  Driven from `--demo-open terminal-tabs`, whose shell reports its folder, so Open Folder Here is
//  offered. Run on the iOS the owner's phone runs (27.2): menus there are drawn by the system.
//

#if os(iOS)
import XCTest

@MainActor
final class GlassTerminalToolsIPhoneUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func attachScreen(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tools-\(name).png"))
    }

    func testToolsRowsSayWhatTheyDoAndReachSettings() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone's Tools menu")
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", "terminal-tabs"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let tools = app.buttons["Tools"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 40), "the terminal's Tools menu did not appear")
        attachScreen("terminal")
        tools.tap()

        // A menu row is one button to XCUITest, its drawn words not exposed apart from its spoken
        // label, so whether the folder's row has words is seen in the "menu" picture.
        let folder = app.buttons["Open Folder Here"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5), "no Open Folder Here in the Tools menu")
        attachScreen("menu")

        // Settings in Tools itself, not inside Session, where it was the last row of a second menu.
        XCTAssertTrue(app.buttons["Session"].exists, "no Session in the Tools menu")
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.exists, "no Settings in the Tools menu itself")
        settings.tap()
        XCTAssertTrue(app.buttons["terminal-settings-done"].waitForExistence(timeout: 10),
                      "Settings didn't open Terminal Settings")
        attachScreen("settings")
    }

    /// A Mermaid diagram a program printed as text has a mark beside it, which shows it drawn
    /// (2026-10-21: "an inline diagram icon would be amazing").
    func testADiagramHasAMarkThatShowsIt() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone's terminal")
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", "terminal-diagram"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let mark = app.buttons["terminal-diagram-mark"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 40), "no mark beside the diagram")
        XCTAssertEqual(app.buttons.matching(identifier: "terminal-diagram-mark").count, 1, "one diagram, one mark")
        attachScreen("diagram-mark")
        mark.tap()
        let drawn = app.descendants(matching: .any).matching(identifier: "terminal-diagram").firstMatch
        XCTAssertTrue(drawn.waitForExistence(timeout: 10), "the mark didn't show the diagram")
        // A moment for Mermaid to draw it, for the picture.
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        attachScreen("diagram")
    }

    /// Tools ▸ Session ▸ Open Folder in Editor shows the editor over the terminal, and its back button
    /// returns to the terminal (the owner, 2026-10-21: "Open Folder in Editor doesn't [work]"). The
    /// terminal had taken the library's place, and the editor's presenter with it.
    func testOpenFolderInEditorShowsTheEditor() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone's Tools menu")
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", "terminal-tabs"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let tools = app.buttons["Tools"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 40), "the terminal's Tools menu did not appear")
        // A tap while the demo terminal is still being laid out can open nothing: tap again.
        let session = app.buttons["Session"].firstMatch
        for _ in 0..<3 where !session.exists {
            tools.tap()
            _ = session.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(session.exists, "no Session in the Tools menu")
        session.tap()
        let open = app.buttons["Open Folder in Editor"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "no Open Folder in Editor under Session")
        open.tap()

        let editorSettings = app.buttons["editor-settings"].firstMatch
        XCTAssertTrue(editorSettings.waitForExistence(timeout: 10), "the editor never appeared")
        attachScreen("editor")
        let back = app.buttons["Terminal"].firstMatch
        XCTAssertTrue(back.exists, "the editor's back button doesn't say it returns to the terminal")
        back.tap()
        XCTAssertTrue(tools.waitForExistence(timeout: 10), "back didn't return to the terminal")
    }
}
#endif
