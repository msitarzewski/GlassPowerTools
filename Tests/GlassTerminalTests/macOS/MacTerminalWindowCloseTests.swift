#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import GlassTerminal

/// A terminal window that has closed stays closed (2026-10-09). After `exit` ended the last tab's
/// tmux session over SSH, the window closed, then SwiftUI's next update of its views found the
/// window again: it went back into the app's list of windows with a coordinator as its delegate
/// and SwiftUI's own delegate gone. Show All Terminals offered it as "New Terminal" with an empty
/// tab; choosing it brought the torn-down window forward, invisible, and the app crashed.
@MainActor
@Suite("Closed terminal windows stay closed")
struct MacTerminalWindowCloseTests {
    private final class SwiftUIDelegate: NSObject, NSWindowDelegate {}

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "MacTerminalWindowCloseTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test("after it closes, the window is neither configured again nor offered by the list of windows")
    func closedWindowStaysClosed() throws {
        try withDefaults { defaults in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            let swiftUIDelegate = SwiftUIDelegate()
            window.delegate = swiftUIDelegate
            let controller = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(), defaults: defaults)
            let registry = MacWorkspacePreviewRegistry()

            // The window is found: its reader takes the close gate, and the list shows it.
            let reader = MacTerminalWindowReader.Coordinator()
            var closes = 0
            reader.observeWindowClose(window) { closes += 1 }
            reader.interceptWindowClose(window) { _ in nil }
            registry.register(controller, window: window)
            #expect(window.delegate === reader)
            #expect(registry.shownWindows.map(\.window) == [window])

            // It closes: the view's close action takes it off the list, and SwiftUI dismantles the reader.
            window.close()
            #expect(closes == 1)
            registry.remove(controller.windowID)
            MacTerminalWindowReader.dismantleNSView(NSView(), coordinator: reader)
            #expect(window.delegate === swiftUIDelegate)

            // SwiftUI's next update of the closing window's views finds the window again.
            let again = MacTerminalWindowReader.Coordinator()
            again.observeWindowClose(window) { closes += 1 }
            again.interceptWindowClose(window) { _ in nil }
            registry.register(controller, window: window)

            #expect(window.delegate === swiftUIDelegate, "a closed window's delegate is left to SwiftUI")
            #expect(registry.shownWindows.isEmpty, "Show All Terminals never offers a closed window")
            #expect(registry.shownController(windowID: controller.windowID) == nil)
            #expect(registry.shownControllers.isEmpty, "nor is it kept in the reopen list")
        }
    }

    @Test("a window still listed when it closes is dropped from the list at once")
    func listedWindowDropsOnClose() throws {
        try withDefaults { defaults in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            let controller = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(), defaults: defaults)
            let registry = MacWorkspacePreviewRegistry()
            let reader = MacTerminalWindowReader.Coordinator()
            reader.observeWindowClose(window) {}
            registry.register(controller, window: window)

            window.close()
            #expect(registry.shownWindows.isEmpty, "closed, even before anything removes it")
            reader.stopObservingWindowClose()
        }
    }
}
#endif
