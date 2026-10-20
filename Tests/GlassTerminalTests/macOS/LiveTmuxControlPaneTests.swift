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

    private func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test("typed into before tmux is ready, drawn from tmux, and every row of a burst kept for Find")
    func localPane() async throws {
        guard let tmux = LiveTmuxControlTests.tmux else { print("NOT RUN: no tmux on this Mac"); return }
        let socket = "glass-ccp-\(UUID().uuidString.prefix(8))"
        defer { _ = LiveProcess.run(tmux, ["-L", socket, "kill-session", "-t", "cc"], environment: LiveTmuxControlTests.environment) }
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
        let drawn = await waitFor(seconds: 15) { runtime.model.getVisibleText(lastNLines: 4).contains { $0.hasPrefix("ROW900") } }
        // Under the whole suite's load, SwiftTerm's PTY reader left the burst's last rows in the PTY
        // until tmux wrote again: three runs of eight stalled. tmux on pipes, read here, never does.
        #expect(drawn, "the burst's last row; on screen: \(runtime.model.getVisibleText(lastNLines: 8))")
        // Every row, from the terminal's own history: none skipped as tmux skips what it can't draw.
        #expect(runtime.model.find("ROW", towardOlder: true)?.total == 900)
        runtime.model.clearSearch()
    }

    @Test("a pane with a long history reattaches in moments, its history whole")
    func reattachWithHistory() async throws {
        guard let tmux = LiveTmuxControlTests.tmux else { print("NOT RUN: no tmux on this Mac"); return }
        let environment = LiveTmuxControlTests.environment
        let socket = "glass-ccr-\(UUID().uuidString.prefix(8))"
        defer { _ = LiveProcess.run(tmux, ["-L", socket, "kill-session", "-t", "cc"], environment: environment) }
        _ = LiveProcess.run(tmux, ["-L", socket, "-f", "/dev/null", "new-session", "-d", "-s", "cc", "-x", "80", "-y", "24", "/bin/sh"],
                            environment: environment)
        // 2,000 rows in colour, ahead of the client: the history a tab comes back to after a relaunch.
        _ = LiveProcess.run(tmux, ["-L", socket, "send-keys", "-t", "cc",
                                   "awk 'BEGIN { for (i = 1; i <= 2000; i++) printf \"\\033[3%dmR%cW%d\\033[0m lorem ipsum dolor sit amet\\n\", i % 7 + 1, 79, i }'",
                                   "Enter"], environment: environment)
        let filled = await waitFor(seconds: 15) {
            (Int(LiveProcess.run(tmux, ["-L", socket, "display-message", "-p", "-t", "cc", "#{history_size}"],
                                 environment: environment).output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) >= 1_980
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
        // (2026-10-19, measured); a moment once only the last lines are read, once per chunk.
        #expect(took < .seconds(5), "reattached in \(took)")
        // Find counts to 1,000; the terminal's own lines, all of them.
        let rows = runtime.model.getVisibleText(lastNLines: 2_100).filter { $0.hasPrefix("ROW") }
        #expect(rows.count == 2_000, "every row of the history")
        #expect(rows.first?.hasPrefix("ROW1 ") == true && rows.last?.hasPrefix("ROW2000 ") == true)
    }
}
#endif
