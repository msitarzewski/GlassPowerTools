#if os(macOS)
import Darwin
import Foundation
import Testing
import GlassTerminalEmulator
@testable import GlassTerminal

/// W37 (the owner, 2026-10-11): "we need to make new local terminals pwd to the pwd in use in the
/// current terminal." A new local terminal opened from a local one — ⌘T, ⇧⌘T, ⌘N, a split — starts
/// in the folder that terminal is in now: tmux's `pane_current_path` for one kept in tmux, the
/// shell's own folder otherwise. From anywhere else, and when that folder is gone, it starts where
/// it always did.
///
/// tmux here is `MacLocalTmuxTests.FakeServer`, or a private server named by its socket on every
/// call (rule 63). The only other processes started are `/bin/sh` and `/bin/sleep`.
extension LocalTmuxServerSuites {
@MainActor
@Suite("New local terminals start in the folder of the one in front", .serialized)
struct MacLocalTerminalStartTests {
    /// A folder name a shell string would break on: spaces, both quotes, `$`, a backquote, a
    /// precomposed and a decomposed accent, another script, and a space at the end.
    static let awkwardName = "it's \"odd\" $HOME `x` caf\u{E9} cafe\u{301} 文件夹 "

    typealias Asked = MacLocalShellFolderTests.Asked

    /// A tmux that says `answer` for every session, on the real disk.
    private func lookups(tmux answer: String?, asked: Asked = Asked()) -> MacLocalShellFolder.Lookups {
        MacLocalShellFolder.Lookups(tmuxDirectory: { session in
            asked.record(session)
            return answer
        }, isFolder: MacLocalShellFolder.Lookups.live.isFolder)
    }

    /// Lookups that fail the test if tmux is asked at all.
    private let tmuxNeverAsked = MacLocalShellFolder.Lookups(
        tmuxDirectory: { session in
            Issue.record("tmux was asked about \(session)")
            return nil
        },
        isFolder: MacLocalShellFolder.Lookups.live.isFolder
    )

    /// A folder of the test's own, by its real path (`/var` is `/private/var`), removed afterwards.
    private func scratchFolder(_ name: String = awkwardName) throws -> (base: String, folder: String) {
        let base = try realPath(NSTemporaryDirectory()) + "/MacLocalTerminalStartTests-" + UUID().uuidString
        let folder = base + "/" + name
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return (base, folder)
    }

    private func realPath(_ path: String) throws -> String {
        try #require(realpath(path, nil).map { resolved in
            defer { free(resolved) }
            return String(cString: resolved)
        })
    }

    /// Local terminals in tmux, the tmux a fake one.
    private func withFakeTmux(_ body: (MacLocalTmuxTests.FakeServer, UserDefaults) async throws -> Void) async throws {
        let suite = "MacLocalTerminalStartTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        let fake = MacLocalTmuxTests.FakeServer()
        let previous = MacLocalTmux.server
        MacLocalTmux.server = fake.server
        defer {
            MacLocalTmux.server = previous
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(true, forKey: UserDefaultsKeys.localTmux)
        try await body(fake, defaults)
    }

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let suite = "MacLocalTerminalStartTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    private func close(_ window: MacWorkspaceWindowController) {
        window.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        MacWorkspacePreviewRegistry.shared.remove(window.windowID)
    }

    private func localWindow(_ defaults: UserDefaults,
                             intent: MacWorkspacePaneIntent = .local) -> MacWorkspaceWindowController {
        MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(initialPaneIntent: intent), defaults: defaults)
    }

    private let theme = SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 0), cursor: (1, 1, 1))
    private let runtimeSettings = SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 100)

    // MARK: The policy

    @Test("tabs, windows and splits all follow the terminal in front, as the owner was told; the choice is one switch")
    func policy() {
        for opening in MacLocalTerminalStart.Opening.allCases {
            #expect(MacLocalTerminalStart.followsTerminalInFront(opening), "\(opening)")
        }
    }

    // MARK: In tmux

    @Test("in tmux, ⌘T's tab starts where tmux says the focused pane is: its claim and its own new-session carry that -c")
    func tabFollowsTmux() async throws {
        let (base, folder) = try scratchFolder()
        defer { try? FileManager.default.removeItem(atPath: base) }
        try await withFakeTmux { fake, defaults in
            let window = localWindow(defaults)
            defer { close(window) }
            let source = try #require(window.selectedTab.focusedPaneID)
            let sourceSession = try #require(window.selectedTab.localTmuxSession(for: source))
            let asked = Asked()

            let tab = try #require(await window.addTabStartingWhereFocusedIs(lookups: lookups(tmux: folder, asked: asked)))
            #expect(asked.sessions == [sourceSession], "tmux is asked about the pane in front, by its session")
            #expect(asked.onMainThread == [false], "and off the main actor")
            #expect(window.tabs.count == 2 && window.selectedTab === tab)
            let pane = try #require(tab.focusedPane)
            #expect(pane.intent.kind == .local && pane.intent.localDirectory == folder)
            #expect(pane.intent.localShell == nil, "the folder only: the shell is the Settings one, as for any new tab")

            // The claim that made the new tab's session was given the folder…
            let session = try #require(tab.localTmuxSession(for: pane.id))
            #expect(session != sourceSession)
            #expect(fake.claims.last?.launch.directory == folder)
            // …and so is the pane's own `new-session -A`, as the one argument after `-c`.
            let launch = MacLocalTerminalConfiguration.resolve(shell: nil, directory: pane.intent.localDirectory,
                                                               tmuxSession: session, tmux: "/opt/homebrew/bin/tmux")
            let c = try #require(launch.arguments.firstIndex(of: "-c"))
            #expect(launch.arguments[c + 1] == folder)
            #expect(launch.currentDirectory == folder)
        }
    }

    @Test("⌘N's window, ⇧⌘T's tab and a split start there too; ⇧⌘T keeps the rest of the pane it repeats")
    func windowRepeatAndSplitFollow() async throws {
        let (base, folder) = try scratchFolder()
        defer { try? FileManager.default.removeItem(atPath: base) }
        try await withFakeTmux { fake, defaults in
            let window = localWindow(defaults, intent: .local(shell: "/bin/zsh", directory: "/usr"))
            defer { close(window) }
            let found = lookups(tmux: folder)

            let request = await window.newWindowRequest(lookups: found)
            #expect(request.initialPaneIntent == .local(shell: nil, directory: folder))
            #expect(!request.startsEmpty && request.tabs.count == 1)

            // ⇧⌘T: the pane's own intent, its tmux session let go, as `MacWorkspaceView` repeats it.
            var repeated = try #require(window.selectedTab.focusedPane?.intent)
            repeated.label = "Build"
            repeated.localTmuxSession = nil
            let tab = try #require(await window.addTabStartingWhereFocusedIs(repeating: repeated, lookups: found))
            let intent = try #require(tab.focusedPane?.intent)
            #expect(intent.localDirectory == folder, "where the terminal is now, not /usr where it opened")
            #expect(intent.localShell == "/bin/zsh" && intent.label == "Build")
            #expect(fake.claims.last?.launch.directory == folder)

            let source = try #require(tab.focusedPaneID)
            await tab.addLocalPane(axis: .vertical, lookups: found)
            let split = try #require(tab.focusedPane)
            #expect(split.id != source && tab.state.root?.panes.count == 2)
            #expect(split.intent.kind == .local && split.intent.localDirectory == folder && split.intent.localShell == nil)
            #expect(fake.claims.last?.launch.directory == folder)
        }
    }

    @Test("a folder gone since, or one tmux cannot say, starts the new terminal at the default, quietly")
    func goneOrUnknown() async throws {
        let (base, folder) = try scratchFolder()
        defer { try? FileManager.default.removeItem(atPath: base) }
        try FileManager.default.removeItem(atPath: folder)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        try await withFakeTmux { fake, defaults in
            let window = localWindow(defaults)
            defer { close(window) }
            for answer in [folder, nil, "", "not/absolute"] as [String?] {
                let said = String(describing: answer)
                let tab = try #require(await window.addTabStartingWhereFocusedIs(lookups: lookups(tmux: answer)))
                #expect(tab.focusedPane?.intent.localDirectory == nil, "tmux said \(said)")
                #expect(fake.claims.last?.launch.directory == home, "tmux said \(said)")
                #expect(await window.newWindowRequest(lookups: lookups(tmux: answer)).initialPaneIntent == nil,
                        "the request New Terminal Window always made; tmux said \(said)")
            }
        }
    }

    @Test("no local terminal in front — an empty tab, an SSH pane — opens at the default, and nothing is asked")
    func noLocalTerminalInFront() async throws {
        try await withFakeTmux { _, defaults in
            let empty = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(startsEmpty: true), defaults: defaults)
            defer { close(empty) }
            #expect(empty.selectedTab.focusedLocalTerminal == nil)
            #expect(await empty.newWindowRequest(lookups: tmuxNeverAsked).initialPaneIntent == nil,
                    "the request New Terminal Window always made")
            let fromEmpty = try #require(await empty.addTabStartingWhereFocusedIs(lookups: tmuxNeverAsked))
            #expect(fromEmpty.focusedPane?.intent.kind == .local)
            #expect(fromEmpty.focusedPane?.intent.localDirectory == nil)

            let serverID = UUID()
            let ssh = localWindow(defaults, intent: .ssh(serverID: serverID))
            defer { close(ssh) }
            #expect(ssh.selectedTab.focusedLocalTerminal == nil)
            let fromSSH = try #require(await ssh.addTabStartingWhereFocusedIs(lookups: tmuxNeverAsked))
            #expect(fromSSH.focusedPane?.intent.kind == .local)
            #expect(fromSSH.focusedPane?.intent.localDirectory == nil)
            // ⇧⌘T on an SSH tab: the same connection, with nothing local asked or changed.
            let again = try #require(await ssh.addTabStartingWhereFocusedIs(repeating: .ssh(serverID: serverID),
                                                                             lookups: tmuxNeverAsked))
            #expect(again.focusedPane?.intent == .ssh(serverID: serverID))
        }
    }

    @Test("a window closed while tmux was asked gets no tab: no session made, no shell started")
    func closedWindowGetsNoTab() async throws {
        try await withFakeTmux { fake, defaults in
            let window = localWindow(defaults)
            defer { MacWorkspacePreviewRegistry.shared.remove(window.windowID) }
            let claimsBefore = fake.claims.count
            let entered = DispatchSemaphore(value: 0)
            let proceed = DispatchSemaphore(value: 0)
            let held = MacLocalShellFolder.Lookups(tmuxDirectory: { _ in
                entered.signal()
                proceed.wait()
                return "/usr"
            }, isFolder: { _ in true })

            let adding = Task { await window.addTabStartingWhereFocusedIs(lookups: held) }
            #expect(await waitFor(seconds: 5) { entered.wait(timeout: .now()) == .success }, "tmux is being asked")
            window.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
            proceed.signal()
            #expect(await adding.value == nil)
            #expect(window.tabs.count == 1)
            #expect(fake.claims.count == claimsBefore, "no session made for a tab no window shows")
        }
    }

    // MARK: A plain shell

    /// The pane's own shell, really running and `cd`'d into the folder: the new tab reads the
    /// process's folder, as Open Folder Here reads it.
    @Test("without tmux, ⌘T's tab starts where the focused shell process is, and the PTY is given that path exactly")
    func tabFollowsPlainShell() async throws {
        let (base, folder) = try scratchFolder()
        defer { try? FileManager.default.removeItem(atPath: base) }
        try await withDefaults { defaults in
            let window = localWindow(defaults)
            defer { close(window) }
            let tab = window.selectedTab
            let paneID = try #require(tab.focusedPaneID)
            #expect(tab.localTmuxSession(for: paneID) == nil)
            let runtime = try #require(tab.localRuntime(for: paneID))
            runtime.start(
                configuration: SwiftTermLocalProcessConfiguration(
                    executable: "/bin/sh",
                    arguments: ["-c", "cd \"$1\" && exec /bin/sleep 600", "sh", folder],
                    executableName: "sh",
                    currentDirectory: base
                ),
                theme: theme,
                runtimeSettings: runtimeSettings
            )
            let arrived = await waitFor(seconds: 5) { runtime.currentWorkingDirectory == folder }
            #expect(arrived, "the shell is in \(String(describing: runtime.currentWorkingDirectory))")

            let new = try #require(await window.addTabStartingWhereFocusedIs(lookups: tmuxNeverAsked))
            let directory = try #require(new.focusedPane?.intent.localDirectory)
            #expect(directory == folder)
            #expect(new.localRuntimesByPaneID.isEmpty, "nothing is started by this test")
            let launch = MacLocalTerminalConfiguration.resolve(shell: "/bin/sh", directory: directory)
            #expect(launch.currentDirectory.map { Array($0.utf8) } == Array(directory.utf8),
                    "the PTY's working directory is the folder's own bytes")
        }
    }

    // MARK: Passed as an argument, exactly

    @Test("this Mac's claim runs tmux with argv: the folder is one argument, whatever it is called; no shell runs")
    func claimIsArgv() {
        let folder = "/tmp/" + Self.awkwardName
        let launch = MacLocalTmux.Launch(directory: folder, command: ["/opt/homebrew/bin/fish", "-l"],
                                         environment: ["TERM=xterm-256color", "LANG=en_US.UTF-8"])
        var runs: [(executable: String, arguments: [String], environment: [String: String])] = []
        var running: Set<String> = ["glass-1"]
        let answer = MacLocalTmux.claim(["glass-1", "glass-2"], launch: launch, tmux: "/opt/homebrew/bin/tmux",
                                        serverArguments: ["-S", "/tmp/gpt-test/s"]) { executable, arguments, environment in
            runs.append((executable, arguments, environment))
            if let s = arguments.firstIndex(of: "-s") {
                return running.insert(arguments[s + 1]).inserted ? "" : nil
            }
            return arguments.last.map { running.contains(String($0.dropFirst())) ? "" : nil } ?? nil
        }
        #expect(answer == "created glass-2\n")
        #expect(TerminalTmux.parseClaim(answer ?? "", candidates: ["glass-1", "glass-2"]) == .created("glass-2"))
        #expect(runs.allSatisfy { $0.executable == "/opt/homebrew/bin/tmux" }, "tmux itself, never /bin/sh")
        #expect(runs.map(\.arguments) == [
            ["-u", "-S", "/tmp/gpt-test/s", "new-session", "-d", "-s", "glass-1", "-c", folder, "/opt/homebrew/bin/fish", "-l"],
            ["-u", "-S", "/tmp/gpt-test/s", "has-session", "-t", "=glass-1"],
            ["-u", "-S", "/tmp/gpt-test/s", "new-session", "-d", "-s", "glass-2", "-c", folder, "/opt/homebrew/bin/fish", "-l"],
        ])
        #expect(runs.allSatisfy { $0.environment == launch.environmentVariables }, "the pane's environment, for a server it starts")

        // One name, already running: joined, and nothing is typed into it. tmux failing: no session.
        #expect(MacLocalTmux.claim(["glass-1"], launch: launch, tmux: "tmux") { _, arguments, _ in
            arguments.contains("new-session") ? nil : ""
        } == "exists glass-1\n")
        #expect(MacLocalTmux.claim(["glass-1", "glass-2"], launch: launch, tmux: "tmux") { _, _, _ in nil } == nil)
    }

    @Test("the launch keeps a folder's exact name: a space at the end, quotes, accents as written; a typed setting's stray spaces still go")
    func exactFolder() throws {
        let (base, folder) = try scratchFolder()
        defer { try? FileManager.default.removeItem(atPath: base) }
        #expect(folder.hasSuffix(" "))

        let plain = MacLocalTerminalConfiguration.resolve(shell: "/bin/sh", directory: folder)
        #expect(plain.currentDirectory.map { Array($0.utf8) } == Array(folder.utf8))
        #expect(plain.fallbackDirectory == FileManager.default.homeDirectoryForCurrentUser.path)
        let tmux = MacLocalTerminalConfiguration.resolve(shell: nil, directory: folder, tmuxSession: "glass-3",
                                                         tmux: "/opt/homebrew/bin/tmux")
        #expect(tmux.arguments == ["-u", "-T", "sync,RGB", "new-session", "-A", "-s", "glass-3", "-c", folder])
        #expect(tmux.fallbackDirectory == FileManager.default.homeDirectoryForCurrentUser.path)
        #expect(MacLocalTerminalConfiguration.tmuxLaunch(shell: nil, directory: folder).directory == folder)

        // A setting typed with spaces round a folder that exists without them, and a `~`.
        #expect(MacLocalTerminalConfiguration.expandedPath("  /usr  ") == "/usr")
        #expect(MacLocalTerminalConfiguration.expandedPath("~")?.hasPrefix("/") == true)
        #expect(MacLocalTerminalConfiguration.expandedPath("   ") == nil)
        let decomposed = "/tmp/cafe\u{301}"
        #expect(MacLocalTerminalConfiguration.expandedPath(decomposed, isFolder: { _ in false }).map { Array($0.utf8) }
                == Array(decomposed.utf8), "never normalized")
    }

    // MARK: Gone by the time it starts

    @Test("a start folder gone by launch time starts the shell at its fallback; without one, the launch says so")
    func fallbackAtLaunch() async throws {
        let (base, folder) = try scratchFolder("gone")
        defer { try? FileManager.default.removeItem(atPath: base) }
        try FileManager.default.removeItem(atPath: folder)

        let requested = SwiftTermLocalProcessConfiguration(executable: "/bin/sh", arguments: ["-c", "exec /bin/sleep 600"],
                                                           currentDirectory: folder, fallbackDirectory: base)
        #expect(requested.startingInAFolderThatExists().currentDirectory == base)
        #expect(requested.startingInAFolderThatExists(isFolder: { _ in true }) == requested)
        var noFallback = requested
        noFallback.fallbackDirectory = nil
        #expect(noFallback.startingInAFolderThatExists() == noFallback)

        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: requested, theme: theme, runtimeSettings: runtimeSettings)
        #expect(runtime.processState.launchError == nil)
        let started = await waitFor(seconds: 5) { runtime.currentWorkingDirectory == base }
        #expect(started, "in \(String(describing: runtime.currentWorkingDirectory))")

        let refused = SwiftTermLocalProcessRuntime()
        defer { refused.terminate() }
        refused.start(configuration: noFallback, theme: theme, runtimeSettings: runtimeSettings)
        #expect(refused.processState.launchError?.contains("does not exist") == true)
    }

    // MARK: Live, on a private tmux server

    /// The whole way through, on a tmux server of the test's own: a window's local pane in tmux,
    /// its shell moved to another folder, then ⌘T. The new session's `pane_current_path` is
    /// checked as tmux reports it. Every tmux call names the socket (rule 63) — the test's own
    /// directly, the app's through a shim — the server starts with no configuration file, and its
    /// panes run `sleep`, so no dotfiles run.
    @Test("live: ⌘T's new tmux session is in the folder the source session's pane is in now",
          .enabled(if: TerminalTmuxTests.tmux != nil))
    func live() async throws {
        let tmux = try #require(TerminalTmuxTests.tmux)
        let root = "/tmp/gpt-\(UUID().uuidString.prefix(8).lowercased())"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let socket = root + "/s"
        let environment = ["PATH": "/usr/bin:/bin", "TMUX_TMPDIR": root]
        @discardableResult func run(_ arguments: [String]) -> (output: String, status: Int32) {
            LiveProcess.run(tmux, ["-S", socket] + arguments, environment: environment)
        }
        defer { run(["kill-server"]) }
        let resolvedRoot = try realPath(root)
        let opened = resolvedRoot + "/opened"
        let moved = resolvedRoot + "/" + Self.awkwardName
        for folder in [opened, moved] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
        }

        let shim = root + "/tmux"
        try Data("#!/bin/sh\nexec \(TerminalTmux.quoted(tmux)) -S \(TerminalTmux.quoted(socket)) -f /dev/null \"$@\"\n".utf8)
            .write(to: URL(fileURLWithPath: shim))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim)
        var server = MacLocalTmux.Server.live
        server.executablePath = { shim }
        server.claim = { candidates, launch, tmux in
            var launch = launch
            launch.command = ["/bin/sleep", "600"]
            return MacLocalTmux.claim(candidates, launch: launch, tmux: tmux)
        }
        let previous = MacLocalTmux.server
        MacLocalTmux.server = server
        defer { MacLocalTmux.server = previous }
        let found = MacLocalShellFolder.Lookups(
            tmuxDirectory: { MacLocalTmux.context(session: $0, tmux: shim)?.directory },
            isFolder: MacLocalShellFolder.Lookups.live.isFolder
        )
        func path(_ session: String) -> String {
            run(["-u", "display-message", "-p", "-t", "=\(session):", "#{pane_current_path}"]).output
                .trimmingCharacters(in: .newlines)
        }

        try await withDefaults { defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let window = localWindow(defaults, intent: .local(shell: nil, directory: opened))
            defer { close(window) }
            let sourcePane = try #require(window.selectedTab.focusedPaneID)
            let source = try #require(window.selectedTab.localTmuxSession(for: sourcePane))
            #expect(path(source) == opened, "the claim made the source session where its pane opened")

            // The source's shell moves: its pane still says `opened`; tmux says `moved`.
            #expect(run(["-u", "respawn-pane", "-k", "-t", "=\(source):", "-c", moved, "/bin/sleep", "600"]).status == 0)
            #expect(path(source) == moved)

            let tab = try #require(await window.addTabStartingWhereFocusedIs(lookups: found))
            let pane = try #require(tab.focusedPane)
            let session = try #require(pane.intent.localTmuxSession)
            #expect(session != source)
            #expect(pane.intent.localDirectory == moved)
            #expect(path(session) == path(source), "the new session's pane_current_path is the source's")
            // Byte for byte: Foundation stored the folder's name decomposed, tmux reported those
            // bytes, and they reached the new session's `-c` unchanged.
            #expect(pane.intent.localDirectory.map { Array($0.utf8) } == Array(path(source).utf8))
            #expect(Array(path(session).utf8) == Array(path(source).utf8))
        }
    }

    private func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
}
#endif
