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

    /// Polls to a deadline. Asking tmux is done off the main actor (`LiveProcess.runDetached`): this
    /// suite is on it, and so is every other test in the run waiting its turn.
    private func waitFor(seconds: Double, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }

    @Test("a bigger font makes tmux's window narrower, as the tab's grid is", .enabled(if: LiveTmuxControlTests.tmux != nil))
    func fontSizeReachesTmux() async throws {
        let tmux = try #require(LiveTmuxControlTests.tmux)
        let environment = LiveTmuxControlTests.environment
        let socket = "glass-ccz-\(UUID().uuidString.prefix(8))"
        defer {
            _ = LiveProcess.run(tmux, ["-L", socket, "kill-server"], environment: environment)
            unlink(LiveTmuxControlTests.socketPath(socket))
        }
        func width() async -> Int? {
            let answer = await LiveProcess.runDetached(tmux, ["-L", socket, "display-message", "-p", "-t", "cc", "#{window_width}"],
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
        #expect(await waitFor(seconds: 30) { runtime.model.getVisibleText(lastNLines: 6).contains { $0.hasPrefix("READY") } },
                "tmux never drew: \(runtime.model.getVisibleText(lastNLines: 6))")
        // tmux as wide as the tab before anything changes, so the change measured is the font's.
        let grid = try #require(runtime.model.rendererGrid)
        let matched = await waitFor(seconds: 15) { await width() == grid.columns }
        let start = await width()
        #expect(matched, "tmux \(start ?? -1), the tab \(grid.columns)")

        hosting.rootView = view(26)
        hosting.layoutSubtreeIfNeeded()
        let narrower = try #require(runtime.model.rendererGrid?.columns)
        #expect(narrower < grid.columns * 2 / 3, "the tab's grid, \(narrower) columns, after the font doubled")
        let followed = await waitFor(seconds: 15) { await width() == narrower }
        let now = await width()
        #expect(followed, "tmux still \(now ?? -1) columns wide, the tab \(narrower), after the font doubled")
    }

    /// Someone dragged a local tmux tab's window edge (2026-11-06) and each step of the drag left another
    /// copy of zsh's prompt above the cursor, until the screen was full of them.
    ///
    /// zsh redraws its prompt on a resize; on the screen's top row the redraw's clear is the whole
    /// screen, which tmux scrolled into the session's history first. The tab showed one prompt; the
    /// copies came into its history when the pane was read again (a relaunch, a reattach), and a window
    /// growing then brought them down onto the screen a row at a time (seen in the macOS 26 VM; this
    /// harness's tab doesn't bring history down, so tmux's copy is what is counted).
    @Test("dragging the window's edge leaves zsh's prompt once, in the tab and in tmux's history",
          .enabled(if: LiveTmuxControlTests.tmux != nil))
    func dragLeavesOnePrompt() async throws {
        let tmux = try #require(LiveTmuxControlTests.tmux)
        let environment = LiveTmuxControlTests.environment
        let socket = "glass-ccd-\(UUID().uuidString.prefix(8))"
        defer {
            _ = LiveProcess.run(tmux, ["-L", socket, "kill-server"], environment: environment)
            unlink(LiveTmuxControlTests.socketPath(socket))
        }
        /// The prompts in tmux's own copy of the pane, history and screen: what a reattach draws.
        func promptsInTmux() async -> [String] {
            let capture = await LiveProcess.runDetached(tmux, ["-L", socket, "capture-pane", "-p", "-S", "-", "-t", "cc"],
                                                        environment: environment)
            return capture.output.split(separator: "\n").map(String.init).filter { $0.hasPrefix("MARK ") }
        }
        // `-f`: no start-up files, so the prompt is the one set here wherever the test runs.
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: tmux,
            arguments: ["-L", socket, "-f", "/dev/null", "-u", "-C", "new-session", "-A", "-s", "cc", "/bin/zsh -f"],
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: NSTemporaryDirectory(),
            tmuxControl: true)
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: configuration, theme: theme(13), runtimeSettings: settings)
        let hosting = NSHostingView(rootView: SwiftTermLocalProcessHostView(
            runtime: runtime, configuration: configuration, theme: theme(13), runtimeSettings: settings))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 500))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()

        // The prompt on the top row, as in a new tab: `clear` leaves it there.
        #expect(runtime.processState.sendCommand("PROMPT='MARK %# '; clear"))
        let shown = { runtime.model.getVisibleText(lastNLines: 200).filter { $0.hasPrefix("MARK ") } }
        #expect(await waitFor(seconds: 30) { shown().count == 1 && !runtime.model.getVisibleText(lastNLines: 200).contains { $0.contains("clear") } },
                "zsh never drew a cleared screen: \(runtime.model.getVisibleText(lastNLines: 6))")
        let settled = await waitFor(seconds: 10) { await promptsInTmux().count == 1 }
        let before = await promptsInTmux()
        #expect(settled, "tmux before the drag: \(before)")

        // A drag's steps, each long enough for tmux to pass the size on and zsh to redraw.
        var width: CGFloat = 900, height: CGFloat = 500
        for step in 0..<12 {
            width += step < 6 ? -24 : 24
            height += step < 6 ? -16 : 16
            window.setContentSize(NSSize(width: width, height: height))
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        try await Task.sleep(for: .milliseconds(500))
        let inTmux = await promptsInTmux()
        #expect(inTmux.count == 1, "\(inTmux.count) prompts in tmux's history and screen after the drag")
        #expect(shown().count == 1, "\(shown().count) prompts in the tab after the drag")
    }

    /// Scale Text on a local tab in tmux did nothing (2026-11-06, someone using the Mac release: "Scale acted like
    /// a regular resize, like the button wasn't clicked"). The pane turns Scale on only once its terminal has said
    /// its size (`MacLocalTerminalPaneView.hasMeasuredGrid`), and SwiftTerm's local view says it only while its
    /// own process runs, which tmux on pipes isn't.
    @Test("a tab in tmux tells its pane its size, which Scale Text waits for", .enabled(if: LiveTmuxControlTests.tmux != nil))
    func tellsItsSize() async throws {
        let tmux = try #require(LiveTmuxControlTests.tmux)
        let environment = LiveTmuxControlTests.environment
        let socket = "glass-ccm-\(UUID().uuidString.prefix(8))"
        defer {
            _ = LiveProcess.run(tmux, ["-L", socket, "kill-server"], environment: environment)
            unlink(LiveTmuxControlTests.socketPath(socket))
        }
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: tmux,
            arguments: ["-L", socket, "-f", "/dev/null", "-u", "-C", "new-session", "-A", "-s", "cc", "/bin/sh"],
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: NSTemporaryDirectory(),
            tmuxControl: true)
        // Started by its view, as a window's tab is: laid out first, its process started after.
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        var told: [String] = []
        let hosting = NSHostingView(rootView: SwiftTermLocalProcessHostView(
            runtime: runtime, configuration: configuration, theme: theme(13), runtimeSettings: settings,
            onResize: { told.append("\($0)x\($1)") }))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 500))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        #expect(await waitFor(seconds: 10) { runtime.model.isTmuxControlClient }, "never started tmux on pipes")
        #expect(runtime.processState.sendCommand("echo READY"))
        #expect(await waitFor(seconds: 30) { runtime.model.getVisibleText(lastNLines: 6).contains { $0.hasPrefix("READY") } },
                "tmux never drew: \(runtime.model.getVisibleText(lastNLines: 6))")
        let opened = try #require(runtime.model.rendererGrid)
        #expect(told.last == "\(opened.columns)x\(opened.rows)",
                "before any resize the pane was told \(told), the tab is \(opened.columns)x\(opened.rows)")

        window.setContentSize(NSSize(width: 600, height: 340))
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 340)
        hosting.layoutSubtreeIfNeeded()
        let grid = try #require(runtime.model.rendererGrid)
        #expect(told.last == "\(grid.columns)x\(grid.rows)", "the pane was told \(told), the tab is \(grid.columns)x\(grid.rows)")
    }

    /// Scale Text on a local tmux tab (2026-10-20): the tab keeps its grid as its window shrinks, so
    /// tmux is told nothing and its programs don't redraw.
    @Test("under Scale a smaller window leaves tmux's window as it was", .enabled(if: LiveTmuxControlTests.tmux != nil))
    func scaleKeepsTmuxsSize() async throws {
        let tmux = try #require(LiveTmuxControlTests.tmux)
        let environment = LiveTmuxControlTests.environment
        let socket = "glass-ccs-\(UUID().uuidString.prefix(8))"
        defer {
            _ = LiveProcess.run(tmux, ["-L", socket, "kill-server"], environment: environment)
            unlink(LiveTmuxControlTests.socketPath(socket))
        }
        func size() async -> String? {
            let answer = await LiveProcess.runDetached(tmux, ["-L", socket, "display-message", "-p", "-t", "cc",
                                                              "#{window_width}x#{window_height}"], environment: environment)
            let text = answer.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
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
        let hosting = NSHostingView(rootView: SwiftTermLocalProcessHostView(
            runtime: runtime, configuration: configuration, theme: theme(13), runtimeSettings: settings))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 500))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()

        #expect(runtime.processState.sendCommand("PS1='$ '; echo READY"))
        #expect(await waitFor(seconds: 30) { runtime.model.getVisibleText(lastNLines: 6).contains { $0.hasPrefix("READY") } },
                "tmux never drew: \(runtime.model.getVisibleText(lastNLines: 6))")
        let grid = try #require(runtime.model.rendererGrid)
        let matched = await waitFor(seconds: 15) { await size() == "\(grid.columns)x\(grid.rows)" }
        let start = await size()
        #expect(matched, "tmux has \(start ?? "nothing"), the tab \(grid.columns)x\(grid.rows)")
        let before = try #require(await size())

        runtime.model.setScaling(true)
        try await Task.sleep(for: .milliseconds(300))
        window.setContentSize(NSSize(width: 450, height: 250))
        hosting.frame = NSRect(x: 0, y: 0, width: 450, height: 250)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(1))
        let after = await size()
        #expect(after == before, "tmux went to \(after ?? "nothing") from \(before) under Scale")
        #expect(runtime.model.rendererGrid?.columns == grid.columns && runtime.model.rendererGrid?.rows == grid.rows)
    }
}
#endif
