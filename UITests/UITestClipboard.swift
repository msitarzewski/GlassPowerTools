//
//  UITestClipboard.swift
//  GlassPowerToolsUITests
//
//  A test that pastes goes through the general pasteboard: on the Mac that is the owner's own
//  clipboard, and a simulator's is synced with it. Tests overwrote it and left it empty or holding
//  test text (2026-10-24, the test audit). What was there is now put back when the test is done.
//

import XCTest
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the clipboard held, every item in every type, so a test can put it back.
@MainActor
struct UITestClipboard {
    #if os(macOS)
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init() throws {
        items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { saved in
            let item = NSPasteboardItem()
            for (type, data) in saved { item.setData(data, forType: type) }
            return item
        })
    }
    #else
    private let items: [[String: Any]]

    /// Text the runner did not put there asks first. Xcode copies the Mac's clipboard into every
    /// booted simulator (`dtpasteboardd`), and iOS answers the runner's read of it with "Allow
    /// Paste" over the home screen, which waits for a person: five database tests failed in Set Up
    /// on the iPhone after the owner copied something on the Mac mid-run, and an earlier read held
    /// a test for 11 minutes (2026-10-25). The prompt is answered as a person answers it; the text
    /// is read only to be put back.
    ///
    /// A refused read is not an error: once Don't Allow Paste has been tapped for the text (XCUITest's
    /// own alert handler tapped it on prompts left from timed-out reads), iOS answers later reads
    /// with the right number of items and nothing in them, and putting that back emptied the
    /// clipboard after each terminal test ("Paste denied silently", the 2026-10-25 iPhone run; a
    /// probe read one item with nothing in it). The kinds of data on the pasteboard are not refused,
    /// and they tell a refusal from an item that holds nothing. A new copy is asked about again.
    init() throws {
        let read = PasteboardRead()
        DispatchQueue.global().async { read.finish(UIPasteboard.general.items) }
        var items = read.wait(seconds: 2)
        if items == nil {
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
            items = read.wait(seconds: 10)
        }
        guard let items else { throw Unanswered() }
        if items.allSatisfy(\.isEmpty), !UIPasteboard.general.types.isEmpty { throw Refused() }
        self.items = items
    }

    func restore() { UIPasteboard.general.items = items }

    struct Refused: LocalizedError {
        var errorDescription: String? {
            "iOS refused the test runner the simulator's clipboard (Don't Allow Paste was tapped for what it holds), so it could not be put back after the test. Copy something new on the Mac, or in the simulator, and run again."
        }
    }

    struct Unanswered: LocalizedError {
        var errorDescription: String? {
            "The simulator's pasteboard did not answer, and no Allow Paste prompt came. If the simulator logs \"Unable to connect to device pasteboard\", shut it down and boot it again (xcrun simctl shutdown <id>; xcrun simctl boot <id>)."
        }
    }
    #endif
}

#if !os(macOS)
/// One pasteboard read handed from the thread that waits on the service to the one that gives up.
private final class PasteboardRead: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private var items: [[String: Any]] = []

    func finish(_ items: [[String: Any]]) {
        self.items = items
        done.signal()
    }

    func wait(seconds: Double) -> [[String: Any]]? {
        done.wait(timeout: .now() + seconds) == .success ? items : nil
    }
}
#endif
