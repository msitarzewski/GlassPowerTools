//
//  TerminalConnectionLostUITests.swift
//  Glass Power Tools — UI tests
//
//  A terminal that loses its connection says so in the middle of its window, over its dimmed text, with Reconnect and
//  Close Terminal (the owner, 2026-11-10: "a disconnected terminal shows a red text under the name in the tab, but the
//  window itself still shows what looks like a connected window"). The demo window's first terminal loses its
//  connection a few seconds after it opens (`--demo-connection-lost`), with the words a real one uses when it stops
//  answering; its Reconnect comes back connected, as a demo has no server.
//
//  iPhone and Vision Pro simulators. On the Mac, the same demo is driven in the macOS VM, never on the owner's screen.
//

#if os(iOS) || os(visionOS)
import XCTest

@MainActor
final class TerminalConnectionLostUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private func launch(_ more: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                // A blinking caret never lets the app go still, and XCUITest waits for that.
                                "-blinkingCursor", "NO",
                                "--demo-open", "terminal-tabs", "--demo-connection-lost", "8"] + more
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func attachTree(_ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Nothing over the terminal while it's connected; once its connection drops, the panel in its middle.
    private func waitForTheLostPanel() -> XCUIElement {
        let reconnect = element("terminal-connection-reconnect")
        // The window's bar: Vision Pro's new-tab button; an iPhone's Tools (Vision Pro has no "Tools" button, and
        // waiting for one outlasted the demo's drop, 2026-11-10).
        #if os(visionOS)
        let opened = element("terminal-footer-new-tab")
        #else
        let opened = app.buttons["Tools"].firstMatch
        #endif
        XCTAssertTrue(opened.waitForExistence(timeout: 40), "the demo terminal's window did not open")
        XCTAssertFalse(element("terminal-connection-panel").exists, "the panel showed over a connected terminal")
        attachScreen("connected")
        if !reconnect.waitForExistence(timeout: 30) { attachTree("no-panel") }
        XCTAssertTrue(reconnect.exists, "no Reconnect over the terminal once its connection dropped")
        // The picture once the panel and the dimming have faded in (it is there to be looked at).
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        attachScreen("connection-lost")
        return reconnect
    }

    func testALostConnectionSaysSoInTheWindowAndReconnects() {
        launch()
        let reconnect = waitForTheLostPanel()
        let title = element("terminal-connection-title")
        XCTAssertEqual(title.label, "Connection Lost")
        XCTAssertTrue(element("terminal-connection-message").label.contains("stopped answering"),
                      "the panel doesn't say why: \(element("terminal-connection-message").label)")
        XCTAssertTrue(element("terminal-connection-close").exists, "no Close Terminal beside Reconnect")

        reconnect.tap()
        // The demo's reconnect takes 1.5 s: a spinner in the panel, then nothing over the terminal.
        if !waitUntilGone(element("terminal-connection-panel"), timeout: 20) { attachTree("still-shown") }
        XCTAssertFalse(element("terminal-connection-panel").exists, "the panel stayed after reconnecting")
        attachScreen("reconnected")
    }

    /// A machine on a tailnet, with Tailscale off on this device (2026-11-10): the panel says to turn it on.
    func testTailscaleOffSaysToTurnItOn() {
        launch(["--demo-needs-tailscale"])
        _ = waitForTheLostPanel()
        XCTAssertEqual(element("terminal-connection-title").label, "Tailscale Is Off")
        let message = element("terminal-connection-message").label
        XCTAssertTrue(message.contains("is on your tailnet (100.92.10.12), and Tailscale is off on this"), message)
        XCTAssertTrue(message.hasSuffix("Turn it on, then try again."), message)
        XCTAssertTrue(element("terminal-connection-reconnect").exists, "Reconnect, for once it's on")
    }

    func testCloseTerminalClosesOnlyTheTerminalThatLostItsConnection() {
        launch()
        _ = waitForTheLostPanel()
        #if os(visionOS)
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'vision-terminal-sidebar-row-'"))
        XCTAssertEqual(rows.count, 2, "the window's two terminals before the close")
        #endif
        element("terminal-connection-close").tap()

        if !waitUntilGone(element("terminal-connection-panel"), timeout: 15) { attachTree("after-close") }
        XCTAssertFalse(element("terminal-connection-panel").exists, "the panel stayed after Close Terminal")
        #if os(visionOS)
        // One terminal left: the window's sidebar goes (help: "When the window is back to one terminal, the sidebar
        // goes"), and the window stays, showing bravo.
        let none = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [none], timeout: 15), .completed,
                       "the window still has two terminals after Close Terminal")
        XCTAssertTrue(element("terminal-footer-new-tab").exists, "Close Terminal closed the whole window")
        let bravo = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'bravo'")).firstMatch
        XCTAssertTrue(bravo.exists, "the window doesn't show the other terminal, bravo")
        #else
        XCTAssertTrue(app.buttons["Tools"].firstMatch.waitForExistence(timeout: 15),
                      "the window's other terminal isn't there after the close")
        #endif
        attachTree("closed")
        attachScreen("closed")
    }
}
#endif
