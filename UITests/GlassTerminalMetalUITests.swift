//
//  GlassTerminalMetalUITests.swift
//  GlassPowerToolsUITests
//
//  Vision Pro draws terminals with Metal (D101), at the headset's own scale. SwiftTerm 1.20 as
//  released drew there at 1 pixel a point, half the headset's 2, and the picture was scaled up:
//  "like a jpg vs png" (the owner, 2026-10-29). Our copy draws at the window's scale
//  (Packages/SwiftTerm, S1). The runner can't see how sharp text is, so under
//  `--ui-testing-mark-metal` the app puts the scale Metal drew its last frame at beside the terminal
//  (`terminal-drawing-metal-<scale>`).
//  Driven from `--demo-open terminal`, which connects to nothing.
//

#if os(visionOS)
import XCTest

@MainActor
final class GlassTerminalMetalUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
    }

    func testTheTerminalDrawsWithMetalAtTheHeadsetsScale() {
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString,
                                "--ui-testing-seed-hosts", "alpha@192.0.2.10:ssh",
                                "--demo-open", "terminal", "--ui-testing-mark-metal"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let terminal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Terminal")).firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 40), "no terminal")
        let drawn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "terminal-drawing-metal-")).firstMatch
        XCTAssertTrue(drawn.waitForExistence(timeout: 20), "Metal drew no frame of the terminal")
        XCTAssertEqual(drawn.identifier, "terminal-drawing-metal-2.0",
                       "Metal drew the terminal at another scale than the headset's 2 pixels a point")
    }
}
#endif
