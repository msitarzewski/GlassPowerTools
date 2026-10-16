//
//  GlassTerminalScaleIPadUITests.swift
//  GlassPowerToolsUITests
//
//  D75 on iPad (2026-10-16). Under Scale a terminal keeps its rows and columns and its text follows
//  the window. Font Size ▸ Increase (⌘+) grows the window, as it does on the Mac and Vision Pro.
//  iPadOS has no request that sizes a window; the terminal raises its scene's minimum size for a
//  moment, which a smaller window grows to. Nothing makes one smaller, so Decrease does nothing there.
//
//  Driven from `--demo-open terminal-tabs` on an iPad simulator in Windowed Apps (Settings ▸
//  Multitasking & Gestures); under Full Screen Apps a window can't be resized, and what needs that
//  skips. The runner reads a window's frame in screen points, and iPadOS resizes a window dragged
//  by its corner about its middle (measured, iPadOS 27.2 simulator).
//

#if os(iOS)
import XCTest

@MainActor
final class GlassTerminalScaleIPadUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    private var tools: XCUIElement { app.buttons["Tools"].firstMatch }

    private func launch() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Scale is offered on iPad, not iPhone")
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", "terminal-tabs"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCTAssertTrue(tools.waitForExistence(timeout: 40), "the terminal's Tools menu did not appear")
    }

    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private var windowFrame: CGRect { app.windows.firstMatch.frame }

    /// Polls, since a frame is a struct no predicate reads.
    private func waitForWindow(timeout: TimeInterval = 5, _ condition: (CGRect) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition(windowFrame) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition(windowFrame)
    }

    /// Drags the window's corner, as a person would, toward `size`: the corner moves half the
    /// change, the window being resized about its middle.
    private func dragWindow(toward size: CGSize) {
        let start = windowFrame
        let screen = XCUIApplication(bundleIdentifier: "com.apple.springboard").coordinate(withNormalizedOffset: .zero)
        let corner = CGVector(dx: start.maxX - 8, dy: start.maxY - 8)
        screen.withOffset(corner).press(forDuration: 0.4, thenDragTo: screen.withOffset(
            CGVector(dx: corner.dx + (size.width - start.width) / 2, dy: corner.dy + (size.height - start.height) / 2)))
    }

    /// True when the window could be given about `size`: the simulator is in Windowed Apps.
    private func sizeWindow(_ size: CGSize) -> Bool {
        dragWindow(toward: size)
        return waitForWindow { abs($0.width - size.width) < 60 && abs($0.height - size.height) < 60 }
    }

    private func chooseFromTools(_ path: String...) {
        tools.tap()
        for title in path {
            let item = app.buttons[title].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "no \(title) in the Tools menu")
            item.tap()
        }
    }

    private func toggleScale() {
        tools.tap()
        let scale = app.descendants(matching: .any).matching(identifier: "terminal-scale-text").firstMatch
        XCTAssertTrue(scale.waitForExistence(timeout: 5), "no Scale Text in the Tools menu")
        scale.tap()
    }

    /// Increase under Scale grows the window by a tenth, the text with it, and leaves the person
    /// free to make it smaller again.
    func testIncreaseGrowsTheScaledWindow() throws {
        try launch()
        try XCTSkipUnless(sizeWindow(CGSize(width: 560, height: 800)),
                          "the window could not be resized: the simulator needs Windowed Apps")
        toggleScale()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let before = windowFrame
        chooseFromTools("Font Size", "Increase")
        let grew = waitForWindow(timeout: 8) { $0.width > before.width * 1.05 }
        attachScreen("increased")
        XCTAssertTrue(grew, "Increase did not grow the window: \(before) → \(windowFrame)")
        let grown = windowFrame
        XCTAssertEqual(grown.width / before.width, 1.1, accuracy: 0.03, "\(before) → \(grown)")
        XCTAssertGreaterThan(grown.height, before.height, "\(before) → \(grown)")
        // The minimum raised to grow it was put back.
        dragWindow(toward: before.size)
        XCTAssertTrue(waitForWindow { $0.width < grown.width - 30 }, "the window can't be made smaller again: \(windowFrame)")
    }
}
#endif
