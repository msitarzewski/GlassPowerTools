//
//  SiteShotsUITests.swift
//  GlassPowerToolsUITests
//
//  The website's iPad picture, in landscape (the owner, 2026-10-30, of the portrait one with its
//  lower half empty: "Use a landscape iPad image to show the same screen, just more full"). A
//  simulator turns only when something turns it: iPadOS 26 ignores the app's own request
//  (`--demo-landscape`), and the Simulator app's rotate menu would open a window on the Mac's
//  screen. A UI test turns it without one (`XCUIDevice.orientation`).
//  Tools/Screenshots/device_shots.sh runs this with GPT_SHOTS_DIR and the demo's machines in
//  GPT_DEMO_HOSTS; without them it is skipped.
//

import XCTest

#if os(iOS)
import UIKit

@MainActor
final class SiteShotsUITests: XCTestCase {

    override func tearDown() async throws {
        await MainActor.run {
            XCUIApplication().terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testIPadLibraryInLandscape() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["GPT_SHOTS_DIR"], let hosts = environment["GPT_DEMO_HOSTS"] else {
            throw XCTSkip("a picture for the website, taken when Tools/Screenshots/device_shots.sh asks for it")
        }
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad's picture")
        // No picture from a failed check: one was written after "no Most used" (2026-10-30).
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", UUID().uuidString, "--ui-testing-seed-hosts", hosts,
                                "--demo-open", "library-history"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your Library"].waitForExistence(timeout: 30), "the library's overview did not open")
        // Most used comes with the demo's month of use, after the overview's title.
        XCTAssertTrue(app.staticTexts["Most used"].waitForExistence(timeout: 30), "the overview has no Most used")
        XCTAssertEqual(XCUIDevice.shared.orientation, .landscapeLeft, "the iPad did not turn")
        Thread.sleep(forTimeInterval: 3)
        let url = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("ipad-landscape.png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
#endif
