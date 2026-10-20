#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GlassTerminalEmulator

/// A local tmux tab's size reaching tmux (2026-10-20, a new tab: "New terminals open with the input on
/// the wrong line"): tmux sized the pane by a size the tab no longer had. A new font size changes the
/// grid without a new frame, and only a new frame reached tmux. On a tmux server of the test's own.
@MainActor
@Suite("A local tmux tab's size reaching tmux (live)", .serialized)
struct LiveTmuxControlResizeTests {
    private let settings = SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 1_000)

    private func theme(_ size: CGFloat) -> SwiftTermTheme {
        SwiftTermTheme(fontSize: size, foreground: (1, 1, 1), background: (0, 0, 0, 1), cursor: (1, 1, 1))
    }

    private func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test("a bigger font makes tmux's window narrower, as the tab's grid is")
    func fontSizeReachesTmux() async throws {
        guard let tmux = LiveTmuxControlTests.tmux else { print("NOT RUN: no tmux on this Mac"); return }
        let environment = LiveTmuxControlTests.environment
        let socket = "glass-ccz-\(UUID().uuidString.prefix(8))"
        defer { _ = LiveProcess.run(tmux, ["-L", socket, "kill-server"], environment: environment) }
        func width() -> Int? {
            let answer = LiveProcess.run(tmux, ["-L", socket, "display-message", "-p", "-t", "cc", "#{window_width}"],
                                         environment: environment)
            return Int(answer.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: tmux,
            arguments: ["-L", socket, "-f", "/dev/null", "-u", "-C", "new-session", "-A", "-s", "cc", "/bin/sh"],
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: NSTemporaryDirectory(),
            tmuxControl: true)
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: configuration, theme: theme(13), runtimeSettings: settings)
        #expect(runtime.processState.launchError == nil)
        func view(_ size: CGFloat) -> SwiftTermLocalProcessHostView {
            SwiftTermLocalProcessHostView(runtime: runtime, configuration: configuration, theme: theme(size),
                                          runtimeSettings: settings)
        }
        let hosting = NSHostingView(rootView: view(13))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 500))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()

        #expect(runtime.processState.sendCommand("PS1='$ '; echo READY"))
        #expect(await waitFor(seconds: 15) { runtime.model.getVisibleText(lastNLines: 6).contains { $0.hasPrefix("READY") } },
                "tmux never drew: \(runtime.model.getVisibleText(lastNLines: 6))")
        let before = try #require(width())

        hosting.rootView = view(26)
        hosting.layoutSubtreeIfNeeded()
        let narrower = await waitFor(seconds: 5) { (width() ?? before) < before * 2 / 3 }
        #expect(narrower, "tmux still \(width() ?? -1) columns wide, was \(before), after the font doubled")
    }
}
#endif
