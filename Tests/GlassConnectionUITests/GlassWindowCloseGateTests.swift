#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import GlassConnectionUI

/// A SwiftUI window asks before it closes (2026-10-17: an editor window closed with its unsaved
/// changes and said nothing). The gate stands in for SwiftUI's window delegate and forwards to it.
@MainActor
@Suite("A window asks before it closes", .serialized)
struct GlassWindowCloseGateTests {
    /// SwiftUI's own delegate, as far as the gate can tell.
    private final class OwnDelegate: NSObject, NSWindowDelegate {
        var allowsClose = true
        var resized = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool { allowsClose }
        func windowDidResize(_ notification: Notification) { resized += 1 }
    }

    @MainActor
    private final class Answer {
        var allowsClose = false
        var asked = 0
    }

    private func window(_ own: OwnDelegate, _ answer: Answer) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = own
        window.contentView = NSHostingView(rootView: Color.clear.background {
            GlassWindowCloseGate { answer.asked += 1; return answer.allowsClose }
        })
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    // The window's own delegate is asked, as `performClose` and the close button ask it. Not
    // `performClose` itself: it runs a moment of the main run loop to flash the button, and under
    // the test runner's async main that ended the whole run, silently, with exit 0.

    @Test func theWindowAsksTheGateBeforeItCloses() throws {
        _ = NSApplication.shared
        let own = OwnDelegate(), answer = Answer()
        let window = window(own, answer)
        defer { window.close() }
        let delegate = try #require(window.delegate)
        #expect(delegate !== own, "the gate is not the window's delegate")

        #expect(delegate.windowShouldClose?(window) == false, "the window would close though the gate keeps it")
        #expect(answer.asked == 1, "the gate was not asked")

        answer.allowsClose = true
        #expect(delegate.windowShouldClose?(window) == true, "the window would stay though the gate lets it go")
    }

    @Test func swiftUIsDelegateKeepsEverythingElse() throws {
        _ = NSApplication.shared
        let own = OwnDelegate(), answer = Answer()
        answer.allowsClose = true
        let window = window(own, answer)
        defer { window.close() }

        window.setContentSize(NSSize(width: 420, height: 320))
        #expect(own.resized > 0, "SwiftUI's delegate no longer hears the window")

        // SwiftUI's own refusal still stands, and the gate is not asked past it.
        own.allowsClose = false
        #expect(window.delegate?.windowShouldClose?(window) == false)
        #expect(answer.asked == 0, "asked though SwiftUI had already kept the window")
    }
}
#endif
