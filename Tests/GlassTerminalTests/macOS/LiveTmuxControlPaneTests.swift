#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminalEmulator

/// The app's own local pane — `SwiftTermLocalProcessRuntime`, its engine and its view — as tmux's
/// control-mode client (D83, 2026-10-19), on a tmux server of the test's own (`-L`, no configuration).
/// What the pure client's tests leave out: the view reading tmux's bytes, the engine typing through
/// the client, Find over the history it kept. Not run where tmux isn't installed.
@MainActor
@Suite("A local pane as tmux's control-mode client (live)", .serialized)
struct LiveTmuxControlPaneTests {
    private let theme = SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 0), cursor: (1, 1, 1))
    private let runtimeSettings = SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 10_000)

    /// Polls to a deadline; tmux is asked off the main actor (`LiveProcess.runDetached`).
    private func waitFor(seconds: Double, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }

    @Test("typed into before tmux is ready, drawn from tmux, and every row of a burst kept for Find",
          .enabled(if: LiveTmuxControlTests.tmux != nil))
    func localPane() async throws {
        let tmux = try #require(LiveTmuxControlTests.tmux)
        let socket = "glass-ccp-\(UUID().uuidString.prefix(8))"
        defer {
            _ = LiveProcess.run(tmux, ["-L", socket, "kill-session", "-t", "cc"], environment: LiveTmuxControlTests.environment)
            unlink(LiveTmuxControlTests.socketPath(socket))
        }
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: tmux,
            arguments: ["-L", socket, "-f", "/dev/null", "-u", "-C", "new-session", "-A", "-s", "cc", "/bin/sh"],
            environment: LiveTmuxControlTests.environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: NSTemporaryDirectory(),
            tmuxControl: true)
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: configuration, theme: theme, runtimeSettings: runtimeSettings)
        #expect(runtime.processState.launchError == nil)
        #expect(runtime.model.isTmuxControlClient)

        // Sent at once: held until tmux has started and the pane is drawn, then typed into it.
        // "ROW", which the command itself doesn't contain (`%c` of 79 is the O), so every match is a row.
        #expect(runtime.processState.sendCommand("PS1='$ '; awk 'BEGIN { for (i = 1; i <= 900; i++) printf \"R%cW%d\\n\", 79, i }'"))
        // The screen's last lines, cheaply: a Find over the whole history every few milliseconds held
        // the main actor from the suite's timing tests.
        // tmux's bytes reach the pane on the main actor (`TmuxControlPipe` hands each chunk there). In
        // a whole run this missed its 15 s while other tests held the main actor — 14.7 s at a stretch,
        // measured 2026-10-24 — and was put down to SwiftTerm's PTY reader, which a control-mode pane
        // doesn't use. Those tests no longer hold it; the deadline is for a pane that never draws.
        let drawn = await waitFor(seconds: 30) { runtime.model.getVisibleText(lastNLines: 4).contains { $0.hasPrefix("ROW900") } }
        #expect(drawn, "the burst's last row; on screen: \(runtime.model.getVisibleText(lastNLines: 8))")
        // Every row, from the terminal's own history: none skipped as tmux skips what it can't draw.
        #expect(runtime.model.find("ROW", towardOlder: true)?.total == 900)
        runtime.model.clearSearch()
    }

    @Test("a pane with a long history reattaches in moments, its history whole", .enabled(if: LiveTmuxControlTests.tmux != nil))
    func reattachWithHistory() async throws {
        let tmux = try #require(LiveTmuxControlTests.tmux)
        let environment = LiveTmuxControlTests.environment
        let socket = "glass-ccr-\(UUID().uuidString.prefix(8))"
        defer {
            _ = LiveProcess.run(tmux, ["-L", socket, "kill-session", "-t", "cc"], environment: environment)
            unlink(LiveTmuxControlTests.socketPath(socket))
        }
        _ = await LiveProcess.runDetached(tmux, ["-L", socket, "-f", "/dev/null", "new-session", "-d", "-s", "cc", "-x", "80", "-y", "24",
                                                 "/bin/sh"], environment: environment)
        // 2,000 rows in colour, ahead of the client: the history a tab comes back to after a relaunch.
        _ = await LiveProcess.runDetached(tmux, ["-L", socket, "send-keys", "-t", "cc",
                                                 "awk 'BEGIN { for (i = 1; i <= 2000; i++) printf \"\\033[3%dmR%cW%d\\033[0m lorem ipsum dolor sit amet\\n\", i % 7 + 1, 79, i }'",
                                                 "Enter"], environment: environment)
        // Filled once the last row is on the pane. It waited for a history of 1,980 lines, which 2,000
        // rows, the wrapped command and the prompts reach or miss by one (2026-10-24).
        let filled = await waitFor(seconds: 30) {
            let screen = await LiveProcess.runDetached(tmux, ["-L", socket, "capture-pane", "-p", "-t", "cc"], environment: environment)
            return screen.output.split(separator: "\n").contains { $0.hasPrefix("ROW2000 ") }
        }
        #expect(filled, "the pane's history")

        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        let start = ContinuousClock.now
        runtime.start(configuration: SwiftTermLocalProcessConfiguration(
            executable: tmux,
            arguments: ["-L", socket, "-u", "-C", "new-session", "-A", "-s", "cc", "/bin/sh"],
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: NSTemporaryDirectory(),
            tmuxControl: true), theme: theme, runtimeSettings: runtimeSettings)
        // Typed once the pane is restored: its answer is the reattach done.
        #expect(runtime.processState.sendCommand("echo D''ONE"))
        let done = await waitFor(seconds: 30) { runtime.model.getVisibleText(lastNLines: 3).contains("DONE") }
        let took = start.duration(to: .now)
        #expect(done)
        // Each line the history scrolled read the whole buffer for the screen reader: 15 seconds
        // (2026-10-19, measured); a moment once only the last lines are read, once per chunk. 10 s
        // still catches that, with room for a run whose other tests share the main actor.
        #expect(took < .seconds(10), "reattached in \(took)")
        // Find counts to 1,000; the terminal's own lines, all of them.
        let rows = runtime.model.getVisibleText(lastNLines: 2_100).filter { $0.hasPrefix("ROW") }
        #expect(rows.count == 2_000, "every row of the history")
        #expect(rows.first?.hasPrefix("ROW1 ") == true && rows.last?.hasPrefix("ROW2000 ") == true)
    }
}
#endif
