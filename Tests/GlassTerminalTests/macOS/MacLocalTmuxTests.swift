#if os(macOS)
import AppKit
import Foundation
import Testing
import GlassTerminalEmulator
@testable import GlassTerminal

/// D47: local terminals kept in this Mac's tmux. A tab gets its own `glass-N` session and keeps it
/// across a relaunch. Closing the tab or quitting detaches: the session keeps running, and Active
/// lists it under This Mac to open again, take over or end.
@MainActor
@Suite("Local terminals in tmux", .serialized)
struct MacLocalTmuxTests {
    /// A tmux that answers from memory, so the workspace's choices can be checked without one.
    nonisolated final class FakeServer: @unchecked Sendable {
        private let lock = NSLock()
        private var _running: Set<String> = []
        private var _killed: [String] = []
        private var _detached: [String] = []
        private var _scrolled: [(String, Int)] = []
        private var _claims: [(candidates: [String], launch: MacLocalTmux.Launch)] = []
        private var _takesFirstOffered = false
        var scrolled: [(String, Int)] { lock.withLock { _scrolled } }
        var running: Set<String> {
            get { lock.withLock { _running } }
            set { lock.withLock { _running = newValue } }
        }
        var killed: [String] { lock.withLock { _killed } }
        var detached: [String] { lock.withLock { _detached } }
        var claims: [(candidates: [String], launch: MacLocalTmux.Launch)] { lock.withLock { _claims } }
        /// Someone else makes the first name a claim offers just before it runs: after the list.
        var takesFirstOffered: Bool {
            get { lock.withLock { _takesFirstOffered } }
            set { lock.withLock { _takesFirstOffered = newValue } }
        }

        var server: MacLocalTmux.Server {
            MacLocalTmux.Server(
                executablePath: { "/opt/homebrew/bin/tmux" },
                listSessions: { _ in
                    self.running.sorted().map { "\($0)\t0\t1\t1790000000" }.joined(separator: "\n")
                },
                kill: { name, _ in
                    self.lock.withLock {
                        self._killed.append(name)
                        self._running.remove(name)
                    }
                },
                detachClients: { name, _ in self.lock.withLock { self._detached.append(name) } },
                scroll: { name, lines, _ in self.lock.withLock { self._scrolled.append((name, lines)) } },
                // `new-session -d` refuses a running name; the next is tried.
                claim: { candidates, launch, _ in
                    self.lock.withLock {
                        self._claims.append((candidates, launch))
                        if self._takesFirstOffered, let first = candidates.first { self._running.insert(first) }
                        for name in candidates {
                            if !self._running.contains(name) {
                                self._running.insert(name)
                                return "created \(name)\n"
                            }
                            if candidates.count == 1 { return "exists \(name)\n" }
                        }
                        return "__glass_tmux_failed__\n"
                    }
                }
            )
        }
    }

    private func withFake(_ body: (FakeServer, UserDefaults) async throws -> Void) async throws {
        let suite = "MacLocalTmuxTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        let fake = FakeServer()
        MacLocalTmux.server = fake.server
        defer {
            MacLocalTmux.server = .live
            defaults.removePersistentDomain(forName: suite)
        }
        try await body(fake, defaults)
    }

    private func localTab(_ defaults: UserDefaults, id: UUID = UUID()) -> MacWorkspaceController {
        MacWorkspaceController(request: MacWorkspaceTabRequest(workspaceID: id, startsEmpty: false, initialPaneIntent: .local),
                               defaults: defaults)
    }

    @Test("finding tmux: the app's PATH first, then the package managers' folders")
    func finding() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tmux-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(MacLocalTmux.executablePath(searching: "/usr/bin:/bin", folders: [folder.path]) == nil)
        let tmux = folder.appendingPathComponent("tmux")
        try Data("#!/bin/sh\n".utf8).write(to: tmux)
        #expect(MacLocalTmux.executablePath(searching: "/usr/bin:/bin", folders: [folder.path]) == nil,
                "a file that is not executable is not tmux")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmux.path)
        #expect(MacLocalTmux.executablePath(searching: "/usr/bin:/bin", folders: [folder.path]) == tmux.path)
        #expect(MacLocalTmux.executablePath(searching: folder.path, folders: []) == tmux.path)
        #expect(MacLocalTmux.packageFolders.first == "/opt/homebrew/bin")
    }

    @Test("which session a pane runs in")
    func choosing() {
        func choose(_ saved: String?, enabled: Bool, running: Set<String>) -> String? {
            MacLocalTmux.session(saved: saved, enabled: enabled, isRunning: running.contains, allocate: { "glass-9" })
        }
        #expect(choose(nil, enabled: true, running: []) == "glass-9")
        #expect(choose("glass-2", enabled: true, running: []) == "glass-2", "on: the saved session, recreated if it ended")
        #expect(choose("glass-2", enabled: false, running: ["glass-2"]) == "glass-2",
                "turning the setting off never strands a terminal that is still running")
        #expect(choose("glass-2", enabled: false, running: []) == nil)
        #expect(choose(nil, enabled: false, running: ["glass-1"]) == nil)
    }

    @Test("the launch: tmux attaches to the session or creates it where the pane opens")
    func launching() {
        let plain = MacLocalTerminalConfiguration.resolve(shell: "/bin/zsh", directory: "/tmp")
        #expect(plain.executable == "/bin/zsh" && plain.arguments == ["-l"])

        let tmux = MacLocalTerminalConfiguration.resolve(shell: nil, directory: "/tmp", tmuxSession: "glass-3",
                                                         tmux: "/opt/homebrew/bin/tmux")
        #expect(tmux.executable == "/opt/homebrew/bin/tmux")
        #expect(tmux.arguments == ["-u", "-T", "sync,RGB", "new-session", "-A", "-s", "glass-3", "-c", "/tmp"],
                "tmux is told this terminal draws synchronized frames and 24-bit colour")
        #expect(tmux.currentDirectory == "/tmp")

        let chosenShell = MacLocalTerminalConfiguration.resolve(shell: "/opt/homebrew/bin/fish", directory: "/tmp",
                                                                tmuxSession: "glass-3", tmux: "/opt/homebrew/bin/tmux")
        #expect(chosenShell.arguments.suffix(2) == ["/opt/homebrew/bin/fish", "-l"],
                "a shell someone chose runs inside the session")
    }

    @Test("a local terminal gets the Mac's environment, with this terminal's identity")
    func environment() {
        let inherited = [
            "HOME": "/Users/ann", "PATH": "/usr/bin:/bin", "SSH_AUTH_SOCK": "/private/tmp/agent.sock",
            "TMPDIR": "/var/folders/xy/T/", "SHELL": "/bin/zsh", "__CFBundleIdentifier": "com.glasspowertools",
            "TERM": "dumb", "TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t0p0", "TMUX": "/tmp/tmux-501/default,1,0",
            "DYLD_INSERT_LIBRARIES": "/usr/lib/libgmalloc.dylib", "XPC_SERVICE_NAME": "application.com.glasspowertools",
        ]
        let environment = MacLocalTerminalConfiguration.environment(from: inherited, version: "0.4.288")
        let names = Set(environment.map { String($0.prefix { $0 != "=" }) })
        for kept in ["HOME=/Users/ann", "SSH_AUTH_SOCK=/private/tmp/agent.sock", "TMPDIR=/var/folders/xy/T/",
                     "PATH=/usr/bin:/bin", "SHELL=/bin/zsh"] {
            #expect(environment.contains(kept), "\(kept) is passed on, as Terminal.app does")
        }
        for set in ["TERM=xterm-256color", "COLORTERM=truecolor", "TERM_PROGRAM=GlassPowerTools",
                    "TERM_PROGRAM_VERSION=0.4.288", "LANG=en_US.UTF-8"] {
            #expect(environment.contains(set))
        }
        #expect(names.isDisjoint(with: ["ITERM_SESSION_ID", "TMUX", "DYLD_INSERT_LIBRARIES", "XPC_SERVICE_NAME"]),
                "another terminal's identity, a loader setting and the app's launchd job stay behind")
        #expect(environment == environment.sorted() && names.count == environment.count)
        #expect(MacLocalTerminalConfiguration.environment(from: ["LANG": "de_DE.UTF-8"], version: nil)
            .contains("LANG=de_DE.UTF-8"), "a language the Mac already set is kept")

        let launch = MacLocalTerminalConfiguration.resolve(shell: "/bin/zsh", directory: "/tmp")
        #expect(launch.environment?.contains("TERM_PROGRAM=GlassPowerTools") == true)
    }

    @Test("what tmux says a pane shows: its host name is not a title")
    func context() {
        #expect(MacLocalTmux.parseContext("/Users/ann/src\talpha.example.com\talpha\talpha.example.com\n")
                == MacWorkspacePaneContext(title: nil, directory: "/Users/ann/src"))
        #expect(MacLocalTmux.parseContext("/Users/ann/src\talpha.example.com\talpha\talpha\n")?.title == nil)
        #expect(MacLocalTmux.parseContext("/Users/ann/src\talpha.example.com\talpha\t✳ Fix the build\tnow\n")
                == MacWorkspacePaneContext(title: "✳ Fix the build\tnow", directory: "/Users/ann/src"))
        #expect(MacLocalTmux.parseContext("relative\th\th\t\n") == MacWorkspacePaneContext(title: nil, directory: nil))
        #expect(MacLocalTmux.parseContext("garbage") == nil)
    }

    @Test("a saved session is a local pane's, with a name tmux and argv can carry safely")
    func restorationRecords() throws {
        var intent = MacWorkspacePaneIntent.local
        intent.localTmuxSession = "glass-4"
        let decoded = try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: JSONEncoder().encode(intent))
        #expect(decoded.localTmuxSession == "glass-4")

        let old = try JSONEncoder().encode(MacWorkspacePaneIntent.local)
        #expect(try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: old).localTmuxSession == nil,
                "a pane saved before tmux reads as a plain shell")

        func decodes(_ mutate: (inout [String: Any]) -> Void, from base: MacWorkspacePaneIntent) throws -> Bool {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
            mutate(&json)
            return (try? JSONDecoder().decode(MacWorkspacePaneIntent.self,
                                              from: JSONSerialization.data(withJSONObject: json))) != nil
        }
        #expect(try decodes({ $0["localTmuxSession"] = "work" }, from: .local), "a session of the user's own, opened from Active")
        for unsafe in ["", "a:b", "a.b", "-t", "bell\u{7}"] {
            #expect(try !decodes({ $0["localTmuxSession"] = unsafe }, from: .local), "\(unsafe.debugDescription) is refused")
        }
        #expect(try !decodes({ $0["localTmuxSession"] = "glass-1" }, from: .ssh(serverID: UUID())),
                "an SSH pane's tmux belongs to its server, not to this Mac")
    }

    @Test("with the setting on, each local pane gets its own session, and keeps it after a relaunch")
    func assigning() async throws {
        try await withFake { fake, defaults in
            fake.running = ["glass-1"]
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let id = UUID()
            let tab = localTab(defaults, id: id)
            let first = try #require(tab.state.root?.panes.first?.intent.localTmuxSession)
            #expect(first != "glass-1", "a name already on the Mac's tmux server is taken")
            #expect(TerminalTmux.glassNumber(first) != nil)

            tab.addPane(intent: .local, axis: .horizontal)
            tab.addPane(intent: .ssh(serverID: UUID()), axis: .vertical)
            let names = tab.state.root?.panes.map(\.intent.localTmuxSession) ?? []
            #expect(names.count == 3 && names[2] == nil, "an SSH pane has no local session")
            #expect(Set(names.compactMap { $0 }).count == 2, "two panes opening together do not share one")

            fake.running.formUnion(names.compactMap { $0 })
            let relaunched = localTab(defaults, id: id)
            #expect(relaunched.state.root?.panes.map(\.intent.localTmuxSession) == names)

            defaults.set(false, forKey: UserDefaultsKeys.localTmux)
            fake.running.remove(first)
            let afterTurningOff = localTab(defaults, id: id)
            let kept = afterTurningOff.state.root?.panes.map(\.intent.localTmuxSession) ?? []
            #expect(kept[0] == nil, "off, and its session has ended: a plain shell next time")
            #expect(kept[1] == names[1], "off, but still running: the pane goes back to it")
        }
    }

    // MARK: tmux in UTF-8 (2026-10-08)
    //
    // launchd starts the app with no locale, and tmux without one prints the tabs in its answers
    // as `_`: the Mac's sessions read as none, a pane's folder as unknown, and a new pane could be
    // given a `glass-N` already running.

    @Test("this Mac's tmux is always asked in UTF-8")
    func utf8() throws {
        #expect(MacLocalTmux.spawnEnvironment(["PATH": "/usr/bin"]).contains("LANG=en_US.UTF-8"))
        #expect(MacLocalTmux.spawnEnvironment(["LANG": "fr_FR.UTF-8"]) == ["LANG=fr_FR.UTF-8"], "a locale already set is kept")
        let scroll = try #require(MacLocalTmux.scrollArguments(session: "glass-1", lines: 1))
        for arguments in [scroll, MacLocalTmux.arguments(session: "glass-1", directory: "/tmp")] {
            #expect(arguments.first == "-u")
        }
    }

    @Test("with the app's environment and no locale, the Mac's sessions and a pane's folder read",
          .enabled(if: TerminalTmuxTests.tmux != nil))
    func utf8Live() throws {
        let tmux = try #require(TerminalTmuxTests.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let environment = ["PATH": "/usr/bin:/bin", "TMUX_TMPDIR": folder.path]
        _ = MacLocalTmux.run(tmux, ["-f", "/dev/null", "new-session", "-d", "-s", "glass-1", "-c", folder.path,
                                    "-x", "80", "-y", "10", "sleep 600"], environment: environment)
        // The private server by its socket: named, tmux never falls back to the default one.
        defer { _ = MacLocalTmux.run(tmux, ["-S", "\(folder.path)/tmux-\(getuid())/default", "kill-server"], environment: environment) }
        let listing = MacLocalTmux.run("/bin/sh", ["-c", TerminalTmux.listScript(tmux: TerminalTmux.quoted(tmux))],
                                       environment: environment)
        guard case .sessions(let sessions)? = listing.map(TerminalTmux.parse) else {
            Issue.record("not read as a list: \(listing ?? "nothing")")
            return
        }
        #expect(sessions.map(\.name) == ["glass-1"])
        let directory = MacLocalTmux.context(session: "glass-1", tmux: tmux, environment: environment)?.directory
        #expect(directory.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == folder.resolvingSymlinksInPath().path)
    }

    @Test("a list it cannot read never gives a new pane glass-1, and never drops a saved session")
    func unreadable() async throws {
        let suite = "MacLocalTmuxTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        MacLocalTmux.server = MacLocalTmux.Server(
            executablePath: { "/opt/homebrew/bin/tmux" },
            listSessions: { _ in "glass-1_1_1_1790000000\n" },
            kill: { _, _ in }, detachClients: { _, _ in }, scroll: { _, _, _ in })
        defer {
            MacLocalTmux.server = .live
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(true, forKey: UserDefaultsKeys.localTmux)
        let id = UUID()
        let name = try #require(localTab(defaults, id: id).state.root?.panes.first?.intent.localTmuxSession)
        #expect((TerminalTmux.glassNumber(name) ?? 0) >= 100, "not glass-1: \(name)")
        defaults.set(false, forKey: UserDefaultsKeys.localTmux)
        #expect(localTab(defaults, id: id).state.root?.panes.first?.intent.localTmuxSession == name,
                "off, and tmux could not say: the saved session is kept, not dropped")
    }

    // MARK: Claiming a name (2026-10-08)
    //
    // A name chosen from the list was started with `new-session -A`, which joins a session that
    // took the name in between — or a running `glass-1` when the list could not be read. The
    // claim makes the session first, and refuses a running name.

    @Test("a name taken after the list was read is skipped, never joined")
    func takenMidClaim() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            fake.running = ["glass-1"]
            fake.takesFirstOffered = true
            let name = try #require(localTab(defaults).state.root?.panes.first?.intent.localTmuxSession)
            let claim = try #require(fake.claims.last, "the name is claimed, not just chosen")
            #expect(!claim.candidates.contains("glass-1"), "the list is read first")
            #expect(name != claim.candidates[0], "\(claim.candidates[0]) went to someone else in between")
            #expect(name == claim.candidates[1])
        }
    }

    @Test("the claim makes the session with the pane's folder, shell and environment")
    func claimLaunch() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let fish = "/opt/homebrew/bin/fish"
            _ = MacWorkspaceController(request: MacWorkspaceTabRequest(workspaceID: UUID(), startsEmpty: false,
                                                                       initialPaneIntent: .local(shell: fish, directory: "/private/tmp")),
                                       defaults: defaults)
            let chosen = try #require(fake.claims.last?.launch)
            #expect(chosen.directory == "/private/tmp" && chosen.command == [fish, "-l"])
            #expect(chosen.environment.contains("TERM_PROGRAM=GlassPowerTools") && chosen.environment.contains("TERM=xterm-256color"),
                    "the pane's environment: a claim that starts tmux's server gives it this")
            #expect(!chosen.environment.contains { $0.hasPrefix("TMUX=") }, "never the app's own terminal's tmux")
            let pane = MacLocalTerminalConfiguration.resolve(shell: fish, directory: "/private/tmp", tmuxSession: "glass-1",
                                                             tmux: "/opt/homebrew/bin/tmux")
            #expect(pane.environment == chosen.environment && pane.currentDirectory == chosen.directory,
                    "the same as the pane's own new-session would have used")

            // No folder or shell of its own: the Settings ones, as the pane resolves them.
            defaults.set("/var/tmp", forKey: UserDefaultsKeys.localWorkingDirectory)
            defaults.set("", forKey: UserDefaultsKeys.localShell)
            _ = localTab(defaults)
            let settings = try #require(fake.claims.last?.launch)
            #expect(settings.directory == "/var/tmp" && settings.command.isEmpty, "tmux runs the login shell")
        }
    }

    @Test("a name restored or opened from Active is never given to another pane, running yet or not")
    func reserving() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let sessionManager = SessionManager(loadImmediately: false)
            // The name the next new pane would take: claimed once, then let go and ended.
            let first = localTab(defaults)
            let pane = try #require(first.focusedPaneID)
            let name = try #require(first.localTmuxSession(for: pane))
            first.removePane(pane, sessionManager: sessionManager)
            fake.running.remove(name)

            var intent = MacWorkspacePaneIntent.local
            intent.localTmuxSession = name
            let restored = MacWorkspaceController(request: MacWorkspaceTabRequest(workspaceID: UUID(), startsEmpty: false,
                                                                                  initialPaneIntent: intent),
                                                  defaults: defaults)
            #expect(restored.state.root?.panes.first?.intent.localTmuxSession == name)
            let next = try #require(localTab(defaults).state.root?.panes.first?.intent.localTmuxSession)
            #expect(next != name, "\(name) belongs to the restored pane, though tmux is not running it yet")
            #expect(fake.claims.last?.candidates.contains(name) == false)
            restored.closeAllSessions(sessionManager: sessionManager)
        }
    }

    @Test("when the claim cannot run, a new pane still never takes a low number")
    func claimUnavailable() async throws {
        let suite = "MacLocalTmuxTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        MacLocalTmux.server = MacLocalTmux.Server(
            executablePath: { "/opt/homebrew/bin/tmux" },
            listSessions: { _ in "" },
            kill: { _, _ in }, detachClients: { _, _ in }, scroll: { _, _, _ in })
        defer {
            MacLocalTmux.server = .live
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(true, forKey: UserDefaultsKeys.localTmux)
        let name = try #require(localTab(defaults).state.root?.panes.first?.intent.localTmuxSession)
        #expect((TerminalTmux.glassNumber(name) ?? 0) >= 100, "the pane's own new-session -A makes it: \(name)")
    }

    /// The claim as the app runs it — `/bin/sh`, the pane's environment — against a private tmux
    /// server, named by its socket in every call and started with no configuration.
    @Test("a claim through sh makes the session in the pane's folder, and gives a new server the pane's environment",
          .enabled(if: TerminalTmuxTests.tmux != nil))
    func claimLive() throws {
        let tmux = try #require(TerminalTmuxTests.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let socket = folder.appendingPathComponent("s").path
        let launch = MacLocalTerminalConfiguration.tmuxLaunch(shell: nil, directory: folder.path)
        var environment = launch.environmentVariables
        environment["TMUX_TMPDIR"] = folder.path
        defer { _ = MacLocalTmux.run(tmux, ["-S", socket, "kill-server"], environment: environment) }
        // `sleep` in place of the login shell, so no dotfiles run.
        func claim(_ candidates: [String]) -> TerminalTmux.Claim {
            let script = TerminalTmux.claimScript(candidates: candidates, directory: launch.directory, command: ["/bin/sleep", "600"],
                                                  tmux: TerminalTmux.quoted(tmux), serverArguments: ["-S", socket, "-f", "/dev/null"])
            return MacLocalTmux.run("/bin/sh", ["-c", script], environment: environment)
                .map { TerminalTmux.parseClaim($0, candidates: candidates) } ?? .failed
        }

        #expect(claim(["glass-1", "glass-2"]) == .created("glass-1"))
        #expect(claim(["glass-1", "glass-2"]) == .created("glass-2"), "glass-1 is running: refused, and the next taken")
        #expect(claim(["glass-1"]) == .exists("glass-1"))
        let path = MacLocalTmux.run(tmux, ["-S", socket, "display-message", "-p", "-t", "=glass-1:", "#{pane_current_path}"],
                                    environment: environment)?.trimmingCharacters(in: .newlines)
        #expect(path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == folder.resolvingSymlinksInPath().path)
        #expect(MacLocalTmux.run(tmux, ["-S", socket, "show-environment", "-g", "TERM_PROGRAM"], environment: environment)
                == "TERM_PROGRAM=GlassPowerTools\n", "the server the claim started has the pane's environment")
    }

    @Test("with the setting off nothing changes")
    func off() async throws {
        try await withFake { _, defaults in
            let tab = localTab(defaults)
            #expect(tab.state.root?.panes.first?.intent.localTmuxSession == nil)
        }
    }

    @Test("closing a pane, a tab or the app detaches: nothing is killed, and Active lists what was shown")
    func closing() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let sessionManager = SessionManager(loadImmediately: false)

            let tab = localTab(defaults)
            tab.addPane(intent: .local, axis: .horizontal)
            let panes = tab.state.root?.panes ?? []
            let names = panes.compactMap(\.intent.localTmuxSession)
            #expect(names.count == 2)
            fake.running = Set(names + ["work"])
            for pane in panes { _ = try #require(tab.localRuntime(for: pane.id)) }

            let shown = MacLocalTmux.listable(MacLocalTmux.sessions(tmux: "tmux")).map(\.name)
            #expect(shown == ["work"], "sessions a tab here shows are not offered again")

            tab.removePane(panes[0].id, sessionManager: sessionManager)
            #expect(MacLocalTmux.listable(MacLocalTmux.sessions(tmux: "tmux")).map(\.name) == [names[0], "work"],
                    "a closed pane's session is listed, Glass's own first")
            tab.closeAllSessions(sessionManager: sessionManager)
            try await Task.sleep(for: .milliseconds(100))
            #expect(fake.killed.isEmpty, "closing never ends a session in tmux")
            #expect(MacLocalTmux.listable(MacLocalTmux.sessions(tmux: "tmux")).map(\.name) == names + ["work"])
        }
    }

    @Test("a window holding local terminals in tmux opens again after a quit, once, unless macOS restores it")
    func reopening() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            var window: MacWorkspaceWindowController? = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(initialPaneIntent: .local), defaults: defaults)
            let id = try #require(window?.windowID)
            try autoreleasepool {
                let tab = try #require(window?.tabs.first)
                let pane = try #require(tab.focusedPaneID)
                fake.running = [try #require(tab.localTmuxSession(for: pane))]
                _ = try #require(tab.localRuntime(for: pane))
            }
            // What is on screen: the registry knows the windows and the controllers they show.
            let registry = MacWorkspacePreviewRegistry()
            let shown = NSWindow()
            shown.isReleasedWhenClosed = false
            registry.register(try #require(window), window: shown)

            MacLocalTmux.rememberWindowsToReopen(defaults: defaults, registry: registry)
            #expect(defaults.stringArray(forKey: MacLocalTmux.reopenKey) == [id.uuidString])
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults, open: [id]).isEmpty,
                    "a window still open is not opened twice")

            // The next launch: nothing open yet.
            MacLocalTmux.rememberWindowsToReopen(defaults: defaults, registry: registry)
            window = nil
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults, open: []) == [id])
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults, open: []).isEmpty, "once")

            defaults.set([id.uuidString, UUID().uuidString], forKey: MacLocalTmux.reopenKey)
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults, open: []) == [id],
                    "a window with nothing saved is skipped")
            defaults.set([id.uuidString], forKey: MacLocalTmux.reopenKey)
            defaults.set(true, forKey: "NSQuitAlwaysKeepsWindows")
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults, open: []).isEmpty, "macOS restores windows itself")
        }
    }

    @Test("scrolling over a local tmux pane scrolls tmux's history, in whole lines a frame at a time")
    func scrolling() async throws {
        #expect(MacLocalTmux.scrollArguments(session: "glass-2", lines: 3)
                == ["-u", "copy-mode", "-e", "-t", "=glass-2:", ";", "send-keys", "-t", "=glass-2:", "-X", "-N", "3", "scroll-up"])
        #expect(MacLocalTmux.scrollArguments(session: "glass-2", lines: -2)
                == ["-u", "send-keys", "-t", "=glass-2:", "-X", "-N", "2", "scroll-down"])
        #expect(MacLocalTmux.scrollArguments(session: "glass-2", lines: 0) == nil)
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let tab = localTab(defaults)
            let pane = try #require(tab.focusedPaneID)
            let session = try #require(tab.localTmuxSession(for: pane))
            let runtime = try #require(tab.localRuntime(for: pane))
            let handler = try #require(runtime.model.onAlternateScreenScroll, "a tmux pane takes the scroll")
            #expect(handler(40, true) && handler(30, true), "70 points of trackpad")
            for _ in 0..<50 where fake.scrolled.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
            #expect(fake.scrolled.map(\.0) == [session] && fake.scrolled.map(\.1) == [4], "4 lines, the rest kept")
            #expect(handler(-3, false))
            for _ in 0..<50 where fake.scrolled.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
            #expect(fake.scrolled.last?.1 == -2, "a wheel reports lines: 6 points left over less 3 lines is −2")

            defaults.set(false, forKey: UserDefaultsKeys.localTmux)
            tab.addPane(intent: .local, axis: .horizontal)
            let plainPane = try #require(tab.focusedPaneID)
            let plain = try #require(tab.localRuntime(for: plainPane))
            #expect(plain.model.onAlternateScreenScroll == nil, "a plain shell keeps the terminal's own behaviour")
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        }
    }

    @Test("a tab in tmux at home is named as Active names its session, and says it is in tmux")
    func naming() async throws {
        try await withFake { _, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let tab = localTab(defaults)
            let pane = try #require(tab.focusedPaneID)
            let session = try #require(tab.localTmuxSession(for: pane))
            tab.paneContextInterval = .zero
            #expect(tab.windowIdentity(servers: [], localUsername: "ann", home: "/Users/ann")
                    == MacWorkspaceWindowIdentity(title: MacWorkspaceTabNaming.tmuxDisplayName(session),
                                                  subtitle: "ann@localhost · in tmux"))
        }
    }

    @Test("closing asks only about what it would stop: a local terminal in tmux keeps running")
    func confirming() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let tab = localTab(defaults)
            let pane = try #require(tab.focusedPaneID)
            fake.running = [try #require(tab.localTmuxSession(for: pane))]
            _ = try #require(tab.localRuntime(for: pane))
            #expect(!tab.closeStopsWork && !tab.focusedPaneCloseStopsWork && tab.closeWarning == nil)
            #expect(tab.hasTerminalsInTmux && tab.hasLocalTerminalsInTmux)

            defaults.set(false, forKey: UserDefaultsKeys.localTmux)
            tab.addPane(intent: .local, axis: .horizontal)
            let second = try #require(tab.focusedPaneID)
            _ = try #require(tab.localRuntime(for: second))
            #expect(tab.localTmuxSession(for: pane) != nil, "turning the setting off leaves a running session alone")
            #expect(tab.closeStopsWork, "a plain shell beside it would stop")
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        }
    }
}
#endif
