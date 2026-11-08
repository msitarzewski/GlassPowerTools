#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GlassTerminal
@testable import GlassTerminalEmulator

/// Type-ahead end to end on this Mac (D102, 2026-11-06): the app's own pane running zsh with this Mac's shell
/// integration, in a window. A command run is kept; typing its start again offers the rest, drawn in grey after
/// the cursor. A home folder of the test's own; nothing of the person's is read or written.
///
/// With the tmux suites (`LocalTmuxServerSuites`): these swap `TerminalLocalShellIntegration.baseFolder`, which every
/// local launch reads, and a launch test beside them took the swapped folder into its tmux arguments (2026-11-06).
extension LocalTmuxServerSuites {
@MainActor
@Suite("Type-ahead in a real local terminal (live)", .serialized)
struct LiveTypeAheadTests {
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

    private func ghost(in view: NSView) -> TerminalTypeAheadGhostView? {
        if let ghost = view as? TerminalTypeAheadGhostView { return ghost }
        for subview in view.subviews { if let found = ghost(in: subview) { return found } }
        return nil
    }

    @Test("zsh with this Mac's integration: a command run is kept, and typing its start offers the rest in grey")
    func endToEnd() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("typeahead-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        // The person's own start-up file: it still runs, and its prompt is theirs.
        try Data("PROMPT='%% '\nexport TYPEAHEAD_OWN_RC=ran\n".utf8).write(to: home.appendingPathComponent(".zshrc"))

        let previousBase = TerminalLocalShellIntegration.baseFolder
        TerminalLocalShellIntegration.baseFolder = root.appendingPathComponent("support")
        defer { TerminalLocalShellIntegration.baseFolder = previousBase }
        let base = ["HOME": home.path, "PATH": "/usr/bin:/bin", "TERM": "xterm-256color", "LANG": "en_US.UTF-8",
                    "USER": NSUserName(), "SHELL": "/bin/zsh"]
        let environment = TerminalLocalShellIntegration.environment(base, shellPath: "/bin/zsh")
        #expect(environment["ZDOTDIR"]?.hasPrefix(root.path) == true, "zsh starts from the integration's folder")

        let configuration = SwiftTermLocalProcessConfiguration(
            executable: "/bin/zsh", arguments: ["-l"],
            environment: environment.map { "\($0.key)=\($0.value)" }, currentDirectory: home.path)
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: configuration, theme: theme, runtimeSettings: settings)
        let hosting = NSHostingView(rootView: SwiftTermLocalProcessHostView(
            runtime: runtime, configuration: configuration, theme: theme, runtimeSettings: settings))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 500))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()

        let history = TerminalCommandHistory(folder: root.appendingPathComponent("history"))
        let defaults = try #require(UserDefaults(suiteName: "typeahead-live-\(UUID().uuidString)"))
        TerminalTypeAheadController.attach(to: runtime.model, machine: "live", folder: { nil }, snippets: { [] },
                                           history: history, defaults: defaults)

        #expect(await waitFor(seconds: 20) { runtime.model.hasShellIntegration },
                "zsh never marked a prompt: \(runtime.model.getVisibleText(lastNLines: 6))")
        #expect(runtime.processState.sendCommand("echo \"own rc: $TYPEAHEAD_OWN_RC\"; echo hello-typeahead"))
        #expect(await waitFor(seconds: 10) { history.records(for: "live").contains { $0.command.hasSuffix("echo hello-typeahead") } },
                "never kept: \(history.records(for: "live").map(\.command)); screen: \(runtime.model.getVisibleText(lastNLines: 6))")
        // The shell marks a command run (C) before its output: wait for the output itself.
        #expect(await waitFor(seconds: 10) { runtime.model.getVisibleText(lastNLines: 10).joined(separator: "\n").contains("own rc: ran") },
                "the person's .zshrc ran: \(runtime.model.getVisibleText(lastNLines: 6))")
        let kept = history.records(for: "live").map(\.command)
        #expect(kept == ["echo \"own rc: $TYPEAHEAD_OWN_RC\"; echo hello-typeahead"], "the exact command line, as typed")
        #expect(await waitFor(seconds: 5) { history.records(for: "live").first?.lastStatus == 0 }, "its exit status, from D")
        #expect(history.records(for: "live").first?.count == 1, "kept once for one run")

        // While a command runs there is no line being typed, so nothing is offered over its output.
        #expect(runtime.processState.sendCommand("sleep 2; false"))
        try await Task.sleep(for: .milliseconds(600))
        #expect(runtime.model.typeAheadLine == nil, "a line while a command runs: \(String(describing: runtime.model.typeAheadLine))")
        #expect(await waitFor(seconds: 10) { history.records(for: "live").first { $0.command == "sleep 2; false" }?.lastStatus == 1 },
                "the failing command's status: \(history.records(for: "live").map { ($0.command, $0.count, $0.lastStatus) })")
        #expect(history.records(for: "live").first { $0.command == "sleep 2; false" }?.count == 1)

        // A command typed after a space is kept out, as zsh and bash keep it out of their own history. zsh's preexec
        // names it all the same (the integration's report, 2026-11-06), so the app has to leave it out itself.
        #expect(runtime.processState.sendCommand(" echo hidden-by-its-space"))
        #expect(runtime.processState.sendCommand("echo after-the-hidden-one"))
        #expect(await waitFor(seconds: 10) { history.records(for: "live").contains { $0.command == "echo after-the-hidden-one" } })
        #expect(!history.records(for: "live").contains { $0.command.contains("hidden-by-its-space") },
                "kept: \(history.records(for: "live").map(\.command))")

        // Its start typed again: the rest offered, and drawn after the cursor.
        runtime.model.insertDroppedText("echo \"own")
        #expect(await waitFor(seconds: 10) { runtime.model.typeAheadSuggestion?.command == kept.first },
                "suggested \(String(describing: runtime.model.typeAheadSuggestion)); line \(String(describing: runtime.model.typeAheadLine))")
        #expect(runtime.model.typeAheadSuggestion?.suffix == " rc: $TYPEAHEAD_OWN_RC\"; echo hello-typeahead")
        hosting.layoutSubtreeIfNeeded()
        let drawn = ghost(in: hosting)
        #expect(drawn?.text.hasPrefix(" rc: $TYPEAHEAD") == true, "the grey text: \(drawn?.text ?? "none")")
    }

    /// A tab in tmux, as the owner's are (2026-11-06: "I'm not seeing any auto complete at all"). tmux gives a new
    /// session's shell its server's environment, not its client's, so the integration handed to the client reached no
    /// shell in tmux, and his server had run since before the integration existed. Here the server is the test's own,
    /// started without it, as his was; the session is made by the app's claim, and the tab is a control-mode client on
    /// pipes, as a local tab in tmux is.
    @Test("a tab in tmux on a server started without the integration: its session's zsh marks its prompt, and the rest is offered",
          .enabled(if: LiveTmuxControlTests.tmux != nil))
    func inTmux() async throws {
        let tmux = try #require(LiveTmuxControlTests.tmux)
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("typeahead-tmux-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("PROMPT='%% '\n".utf8).write(to: home.appendingPathComponent(".zshrc"))
        let previousBase = TerminalLocalShellIntegration.baseFolder
        TerminalLocalShellIntegration.baseFolder = root.appendingPathComponent("support")
        defer { TerminalLocalShellIntegration.baseFolder = previousBase }
        let folder = try #require(TerminalLocalShellIntegration.startupFolder()).path

        let base = ["HOME": home.path, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "TERM": "xterm-256color",
                    "LANG": "en_US.UTF-8", "USER": NSUserName(), "SHELL": "/bin/zsh"]
        let socket = "glass-cct-\(UUID().uuidString.prefix(8))"
        defer {
            _ = LiveProcess.run(tmux, ["-L", socket, "kill-server"], environment: base)
            unlink(LiveTmuxControlTests.socketPath(socket))
        }
        // The server first, with no integration in its environment.
        _ = LiveProcess.run(tmux, ["-L", socket, "-f", "/dev/null", "new-session", "-d", "-s", "already", "/bin/sh"],
                            environment: base)
        #expect(LiveProcess.run(tmux, ["-L", socket, "has-session", "-t", "=already"], environment: base).status == 0)

        // The launch as a pane's (`tmuxLaunch`, from this environment rather than the test runner's), and the claim.
        let split = TerminalLocalShellIntegration.tmuxEnvironment(MacLocalTerminalConfiguration.environment(from: base, shell: "/bin/zsh"))
        #expect(split.session.contains("ZDOTDIR=\(folder)"), "the session's own: \(split.session)")
        #expect(!split.rest.contains { $0.hasPrefix("ZDOTDIR=") || $0.hasPrefix("GLASS_USER_ZDOTDIR=") },
                "the server's and clients' environment keeps the integration out: \(split.rest)")
        let launch = MacLocalTmux.Launch(directory: home.path, command: ["/bin/zsh", "-l"], environment: split.rest,
                                         sessionEnvironment: split.session)
        let claim = MacLocalTmux.claim(["cc"], launch: launch, tmux: tmux, serverArguments: ["-L", socket])
        #expect(claim == "created cc\n", "the claim: \(String(describing: claim))")
        let inSession = LiveProcess.run(tmux, ["-L", socket, "show-environment", "-t", "cc", "ZDOTDIR"], environment: base)
        #expect(inSession.output.trimmingCharacters(in: .whitespacesAndNewlines) == "ZDOTDIR=\(folder)", "the session's: \(inSession.output)")
        let global = LiveProcess.run(tmux, ["-L", socket, "show-environment", "-g", "ZDOTDIR"], environment: base)
        #expect(global.status != 0, "the server's own environment has none: \(global.output)")

        let configuration = SwiftTermLocalProcessConfiguration(
            executable: tmux,
            arguments: ["-L", socket] + MacLocalTmux.arguments(session: "cc", directory: home.path, control: true,
                                                               sessionEnvironment: launch.sessionEnvironment) + launch.command,
            environment: launch.environment, currentDirectory: home.path, tmuxControl: true)
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: configuration, theme: theme, runtimeSettings: settings)
        let hosting = NSHostingView(rootView: SwiftTermLocalProcessHostView(
            runtime: runtime, configuration: configuration, theme: theme, runtimeSettings: settings))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 500))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        let history = TerminalCommandHistory(folder: root.appendingPathComponent("history"))
        let defaults = try #require(UserDefaults(suiteName: "typeahead-tmux-\(UUID().uuidString)"))
        TerminalTypeAheadController.attach(to: runtime.model, machine: "live", folder: { nil }, snippets: { [] },
                                           history: history, defaults: defaults)

        #expect(await waitFor(seconds: 10) { runtime.model.isTmuxControlClient }, "never started tmux on pipes")
        let model = runtime.model
        #expect(await waitFor(seconds: 20) { model.getVisibleText(lastNLines: 3).joined(separator: "\n").contains("%") },
                "no prompt: \(model.getVisibleText(lastNLines: 6))")

        // Typed at once, as in a new tab: zsh's first prompt and its marks came before the tab attached, and the pane
        // re-read has none, so the line is followed from the keys, the pane's shell being what reads them.
        model.typeText("echo hello-in-tmux")
        #expect(await waitFor(seconds: 5) { model.typeAheadLine?.text == "echo hello-in-tmux" },
                "line \(String(describing: model.typeAheadLine)); screen \(model.getVisibleText(lastNLines: 3))")
        model.typeText("\r")
        #expect(await waitFor(seconds: 10) { history.records(for: "live").contains { $0.command == "echo hello-in-tmux" } },
                "never kept: \(history.records(for: "live").map(\.command)); screen: \(model.getVisibleText(lastNLines: 6))")
        #expect(await waitFor(seconds: 10) { model.getVisibleText(lastNLines: 10).joined(separator: "\n").contains("\nhello-in-tmux") },
                "its output: \(model.getVisibleText(lastNLines: 6))")
        // From the next prompt the session's zsh marks its own (the integration, from `new-session -e`).
        #expect(await waitFor(seconds: 10) { model.hasShellIntegration },
                "zsh in tmux never marked a prompt: \(model.getVisibleText(lastNLines: 6))")
        #expect(await waitFor(seconds: 5) { history.records(for: "live").first { $0.command == "echo hello-in-tmux" }?.lastStatus == 0 },
                "its status, from the integration's D")
        #expect(history.records(for: "live").first { $0.command == "echo hello-in-tmux" }?.count == 1, "kept once for one run")

        model.insertDroppedText("echo hel")
        #expect(await waitFor(seconds: 10) { model.typeAheadSuggestion?.command == "echo hello-in-tmux" },
                "suggested \(String(describing: model.typeAheadSuggestion)); line \(String(describing: model.typeAheadLine))")
        hosting.layoutSubtreeIfNeeded()
        #expect(ghost(in: hosting)?.text == "lo-in-tmux", "the grey text: \(ghost(in: hosting)?.text ?? "none")")
    }

    /// The owner's tabs in tmux were open before any of this (2026-11-06), their shells started with no integration
    /// and none to come. The pane's shell is a process of this Mac's, so its tab asks the system whether the shell is
    /// what reads the keys, as a tab not in tmux does: the shell's lines are offered and kept; a program's aren't.
    @Test("a tab in tmux whose shell marks nothing: its lines are offered and kept; a program it runs is left alone",
          .enabled(if: LiveTmuxControlTests.tmux != nil))
    func inTmuxWithoutIntegration() async throws {
        let tmux = try #require(LiveTmuxControlTests.tmux)
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("typeahead-tmux-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data("PROMPT='%% '\n".utf8).write(to: home.appendingPathComponent(".zshrc"))
        let base = ["HOME": home.path, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "TERM": "xterm-256color",
                    "LANG": "en_US.UTF-8", "USER": NSUserName(), "SHELL": "/bin/zsh"]
        let socket = "glass-ccp-\(UUID().uuidString.prefix(8))"
        defer {
            _ = LiveProcess.run(tmux, ["-L", socket, "kill-server"], environment: base)
            unlink(LiveTmuxControlTests.socketPath(socket))
        }
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: tmux,
            arguments: ["-L", socket, "-f", "/dev/null"] + MacLocalTmux.arguments(session: "cc", directory: home.path, control: true)
                + ["/bin/zsh", "-l"],
            environment: base.map { "\($0.key)=\($0.value)" }, currentDirectory: home.path, tmuxControl: true)
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: configuration, theme: theme, runtimeSettings: settings)
        let hosting = NSHostingView(rootView: SwiftTermLocalProcessHostView(
            runtime: runtime, configuration: configuration, theme: theme, runtimeSettings: settings))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 500))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        let history = TerminalCommandHistory(folder: home.appendingPathComponent("history"))
        let defaults = try #require(UserDefaults(suiteName: "typeahead-tmux-plain-\(UUID().uuidString)"))
        TerminalTypeAheadController.attach(to: runtime.model, machine: "live", folder: { nil }, snippets: { [] },
                                           history: history, defaults: defaults)
        func type(_ text: String) { runtime.model.typeText(text) }
        let model = runtime.model
        #expect(await waitFor(seconds: 10) { model.isTmuxControlClient }, "never started tmux on pipes")
        #expect(await waitFor(seconds: 20) { model.getVisibleText(lastNLines: 3).joined(separator: "\n").contains("%") },
                "no prompt: \(model.getVisibleText(lastNLines: 6))")

        type("echo kept-in-tmux")
        #expect(await waitFor(seconds: 5) { model.typeAheadLine?.text == "echo kept-in-tmux" },
                "line \(String(describing: model.typeAheadLine)); screen \(model.getVisibleText(lastNLines: 3))")
        type("\r")
        #expect(await waitFor(seconds: 5) { history.records(for: "live").contains { $0.command == "echo kept-in-tmux" } })
        #expect(!model.hasShellIntegration, "this zsh marks nothing")

        try await Task.sleep(for: .milliseconds(300))
        type("cat")
        #expect(await waitFor(seconds: 5) { model.typeAheadLine?.text == "cat" })
        type("\r")
        try await Task.sleep(for: .milliseconds(800))
        type("explain this repo")
        #expect(await waitFor(seconds: 3) { model.getVisibleText(lastNLines: 3).joined(separator: "\n").contains("explain this repo") })
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.typeAheadLine == nil, "offered over cat's input: \(String(describing: model.typeAheadLine))")
        type("\r")
        try await Task.sleep(for: .milliseconds(500))
        type("\u{04}")
        try await Task.sleep(for: .milliseconds(500))
        let kept = history.records(for: "live").map(\.command)
        #expect(!kept.contains { $0.contains("explain this repo") }, "cat's input kept as a command: \(kept)")
        #expect(kept.contains("cat"), "the shell's own command, cat, is kept: \(kept)")

        // Back at the prompt: offered again, from the next line (a ⌃ key, ⌃D here, stops the keys saying what the line
        // holds until Enter, in any tab whose shell marks nothing).
        type("\r")
        try await Task.sleep(for: .milliseconds(300))
        type("echo kep")
        #expect(await waitFor(seconds: 5) { model.typeAheadSuggestion?.command == "echo kept-in-tmux" },
                "suggested \(String(describing: model.typeAheadSuggestion)); line \(String(describing: model.typeAheadLine))")
    }

    /// A window opened on a terminal already typed into (and the demo, whose transcript is read before its window's
    /// sources are added): what's on the line is offered for at once, not at the next key (2026-11-06).
    @Test("a line typed before type-ahead is attached is offered for once its sources are added")
    func lineAlreadyTyped() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("typeahead-typed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data("PROMPT='%% '\n".utf8).write(to: home.appendingPathComponent(".zshrc"))
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: "/bin/zsh", arguments: ["-l"],
            environment: ["HOME=\(home.path)", "PATH=/usr/bin:/bin", "TERM=xterm-256color", "LANG=en_US.UTF-8",
                          "USER=\(NSUserName())", "SHELL=/bin/zsh"],
            currentDirectory: home.path)
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: configuration, theme: theme, runtimeSettings: settings)
        let hosting = NSHostingView(rootView: SwiftTermLocalProcessHostView(
            runtime: runtime, configuration: configuration, theme: theme, runtimeSettings: settings))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 500))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        let model = runtime.model
        #expect(await waitFor(seconds: 20) { model.getVisibleText(lastNLines: 3).joined(separator: "\n").contains("%") })

        model.typeText("echo kept")
        #expect(await waitFor(seconds: 5) { model.typeAheadLine?.text == "echo kept" }, "the line, before anything offers")
        let history = TerminalCommandHistory(folder: nil)
        history.record("echo kept-from-before", machine: "live", folder: nil)
        let defaults = try #require(UserDefaults(suiteName: "typeahead-typed-\(UUID().uuidString)"))
        let controller = TerminalTypeAheadController.attach(to: model, machine: "live", folder: { nil }, snippets: { [] },
                                                            history: history, defaults: defaults)
        controller.offerForCurrentLine()
        #expect(model.typeAheadSuggestion?.command == "echo kept-from-before",
                "offered: \(String(describing: model.typeAheadSuggestion))")
    }

    /// "No surprises for users" (the owner, 2026-11-06). Where the shell marks nothing, a line typed into a program
    /// it runs (Claude Code, Python, mysql; `cat` here) is echoed just as one typed at the prompt. This Mac's own
    /// terminal asks the system which program reads its keys; only the shell's lines are offered and kept.
    @Test("zsh marking nothing: a line typed into a program it runs is neither offered suggestions nor kept")
    func otherProgramsInput() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("typeahead-fg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data("PROMPT='%% '\n".utf8).write(to: home.appendingPathComponent(".zshrc"))
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: "/bin/zsh", arguments: ["-l"],
            environment: ["HOME=\(home.path)", "PATH=/usr/bin:/bin", "TERM=xterm-256color", "LANG=en_US.UTF-8",
                          "USER=\(NSUserName())", "SHELL=/bin/zsh"],
            currentDirectory: home.path)
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: configuration, theme: theme, runtimeSettings: settings)
        let hosting = NSHostingView(rootView: SwiftTermLocalProcessHostView(
            runtime: runtime, configuration: configuration, theme: theme, runtimeSettings: settings))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 500))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()

        let history = TerminalCommandHistory(folder: home.appendingPathComponent("history"))
        let defaults = try #require(UserDefaults(suiteName: "typeahead-fg-\(UUID().uuidString)"))
        TerminalTypeAheadController.attach(to: runtime.model, machine: "live", folder: { nil }, snippets: { [] },
                                           history: history, defaults: defaults)
        func type(_ text: String) { runtime.model.typeText(text) }
        let model = runtime.model
        #expect(await waitFor(seconds: 20) { model.getVisibleText(lastNLines: 3).joined(separator: "\n").contains("%") }, "no prompt: \(model.getVisibleText(lastNLines: 6)) running \(runtime.processState.isRunning)")
        #expect(!model.hasShellIntegration, "this zsh marks nothing")

        // At the prompt: the shell reads the keys, so the line is followed.
        type("echo kept-at-the-prompt")
        #expect(await waitFor(seconds: 5) { model.typeAheadLine?.text == "echo kept-at-the-prompt" },
                "line \(String(describing: model.typeAheadLine)); screen \(model.getVisibleText(lastNLines: 3))")
        type("\r")
        #expect(await waitFor(seconds: 5) { history.records(for: "live").contains { $0.command == "echo kept-at-the-prompt" } })

        // In cat: the same echo, but cat reads the keys.
        try await Task.sleep(for: .milliseconds(300))
        type("cat")
        #expect(await waitFor(seconds: 5) { model.typeAheadLine?.text == "cat" })
        type("\r")
        try await Task.sleep(for: .milliseconds(800))
        type("explain this repo")
        #expect(await waitFor(seconds: 3) { model.getVisibleText(lastNLines: 3).joined(separator: "\n").contains("explain this repo") })
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.typeAheadLine == nil, "offered over cat's input: \(String(describing: model.typeAheadLine))")
        type("\r")
        try await Task.sleep(for: .milliseconds(500))
        type("\u{04}")
        try await Task.sleep(for: .milliseconds(500))
        let kept = history.records(for: "live").map(\.command)
        #expect(!kept.contains { $0.contains("explain this repo") }, "cat's input kept as a command: \(kept)")
        #expect(kept.contains("cat"), "the shell's own command, cat, is kept: \(kept)")
    }
}
}
#endif
