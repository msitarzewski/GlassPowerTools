#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GlassTerminal
@testable import GlassTerminalEmulator

/// Which agent a local terminal outside tmux runs, read the way the app reads it: its own zsh in a PTY, a program in
/// front of it, and the process table's answer (2026-11-12). A home folder of the test's own; the "agent" is `sleep`
/// under the agent's name, so nothing is installed or run.
extension LocalTmuxServerSuites {
@MainActor
@Suite("A local terminal's agent, from this Mac's process table (live)", .serialized)
struct LiveLocalAgentTests {
    private let settings = SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 1_000)
    private let theme = SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 1), cursor: (1, 1, 1))

    private func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// Runs zsh with this Mac's integration in a home of its own, checks the idle shell is no agent, then types
    /// `command(root)` and waits for the program in front to be Claude Code. `program` is where, under the test's
    /// root, `sleep` is linked in as the agent.
    private func claudeCode(program: String, command: (URL) -> String) async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agent-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let link = root.appendingPathComponent(program)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/bin/sleep")
        try Data("PROMPT='%% '\n".utf8).write(to: home.appendingPathComponent(".zshrc"))

        let previousBase = TerminalLocalShellIntegration.baseFolder
        TerminalLocalShellIntegration.baseFolder = root.appendingPathComponent("support")
        defer { TerminalLocalShellIntegration.baseFolder = previousBase }
        let bin = root.appendingPathComponent("bin")
        let base = ["HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin", "TERM": "xterm-256color",
                    "LANG": "en_US.UTF-8", "USER": NSUserName(), "SHELL": "/bin/zsh"]
        let environment = TerminalLocalShellIntegration.environment(base, shellPath: "/bin/zsh")
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: "/bin/zsh", arguments: ["-l"],
            environment: environment.map { "\($0.key)=\($0.value)" }, currentDirectory: home.path)
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: configuration, theme: theme, runtimeSettings: settings)

        #expect(await waitFor(seconds: 20) { runtime.model.hasShellIntegration },
                "zsh never marked a prompt: \(runtime.model.getVisibleText(lastNLines: 6))")
        let idle = runtime.foregroundCommandLine
        #expect(idle != nil, "the idle shell's command line")
        #expect(TerminalAgent.identify(program: nil, arguments: idle.flatMap(TerminalAgent.identifyingWords)) == nil,
                "the idle shell is no agent: \(idle ?? "nil")")

        #expect(runtime.processState.sendCommand(command(root)))
        let told = await waitFor(seconds: 10) {
            TerminalAgent.identify(program: nil,
                                   arguments: runtime.foregroundCommandLine.flatMap(TerminalAgent.identifyingWords)) == .claudeCode
        }
        #expect(told, "in front: \(runtime.foregroundCommandLine ?? "nil"); screen: \(runtime.model.getVisibleText(lastNLines: 4))")
    }

    @Test("zsh with this Mac's integration: the program in front is read, and `claude` is Claude Code")
    func claudeInFront() async throws {
        try await claudeCode(program: "bin/claude") { _ in "claude 30" }
    }

    /// Claude Code installed through npm runs as the package's `bin/claude.exe`, by its whole path (2026-11-12).
    @Test("Claude Code from npm, run by its path as `…/@anthropic-ai/claude-code/bin/claude.exe`, is Claude Code")
    func npmClaudeInFront() async throws {
        let program = "lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
        try await claudeCode(program: program) { root in "'\(root.appendingPathComponent(program).path)' 30" }
    }
}
}
#endif
