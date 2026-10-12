#if os(macOS)
import AppKit
import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlassShell
import GlassTerminalEmulator
@testable import GlassTerminal

/// D47: local terminals kept in this Mac's tmux. A tab gets its own `glass-N` session and keeps it
/// across a relaunch. Closing the tab or quitting detaches: the session keeps running, and Active
/// lists it under This Mac to open again, take over or end.
extension LocalTmuxServerSuites {
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
        private var _listing: String?
        private var _givenNames: [(session: String, name: String?)] = []
        private var _contexts: [String: MacWorkspacePaneContext] = [:]
        private var _contextReads = 0
        private var _contextReadDelay: TimeInterval = 0
        private var _repositories: [(session: String, repository: TerminalRepository?)] = []
        private var _readsRepositories = false
        /// What each session was told about its repository (W11).
        var repositories: [(session: String, repository: TerminalRepository?)] { lock.withLock { _repositories } }
        /// Reads a listed folder's repository from the disk, as this Mac does; off, a listing's
        /// folders on the test machine change nothing.
        var readsRepositories: Bool {
            get { lock.withLock { _readsRepositories } }
            set { lock.withLock { _readsRepositories = newValue } }
        }
        /// What the list answers in place of the running names, in the full format (W6).
        var listing: String? {
            get { lock.withLock { _listing } }
            set { lock.withLock { _listing = newValue } }
        }
        var givenNames: [(session: String, name: String?)] { lock.withLock { _givenNames } }
        /// What each session's active pane shows. A name given to a session shows here, as tmux's does.
        var contexts: [String: MacWorkspacePaneContext] {
            get { lock.withLock { _contexts } }
            set { lock.withLock { _contexts = newValue } }
        }
        /// How many times every session's context was read (W19).
        var contextReads: Int { lock.withLock { _contextReads } }
        /// How long a read of every session's context takes.
        var contextReadDelay: TimeInterval {
            get { lock.withLock { _contextReadDelay } }
            set { lock.withLock { _contextReadDelay = newValue } }
        }
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
                    self.listing ?? self.running.sorted().map { "\($0)\t0\t1\t1790000000" }.joined(separator: "\n")
                },
                kill: { name, _ in
                    self.lock.withLock {
                        self._killed.append(name)
                        self._running.remove(name)
                    }
                },
                detachClients: { name, _ in self.lock.withLock { self._detached.append(name) } },
                scroll: { name, lines, _ in self.lock.withLock { self._scrolled.append((name, lines)) } },
                history: { name, _ in "history of \(name)  \n\n" },
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
                },
                setGivenName: { session, name, _ in
                    self.lock.withLock {
                        self._givenNames.append((session, name))
                        self._contexts[session, default: MacWorkspacePaneContext()].givenName = name
                    }
                },
                contexts: { _ in
                    let (answer, delay) = self.lock.withLock { () -> ([String: MacWorkspacePaneContext], TimeInterval) in
                        self._contextReads += 1
                        return (self._contexts, self._contextReadDelay)
                    }
                    if delay > 0 { Thread.sleep(forTimeInterval: delay) }
                    return answer
                },
                setRepository: { session, repository, _ in self.lock.withLock { self._repositories.append((session, repository)) } },
                readRepository: { folder, home in
                    self.readsRepositories ? TerminalRepository.read(folder: folder, home: home) : nil
                }
            )
        }
    }

    private func withFake(_ body: (FakeServer, UserDefaults) async throws -> Void) async throws {
        let suite = "MacLocalTmuxTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        let fake = FakeServer()
        MacLocalTmux.server = fake.server
        // Every ask read at once, so a test need not wait out the interval (W19).
        MacLocalTmux.contextReads = MacLocalTmuxContextReads(interval: .zero)
        defer {
            MacLocalTmux.server = .live
            MacLocalTmux.contextReads = MacLocalTmuxContextReads()
            defaults.removePersistentDomain(forName: suite)
        }
        try await body(fake, defaults)
    }

    /// A tab its window shows, so saved as the window opens; init itself writes nothing (W7b).
    private func localTab(_ defaults: UserDefaults, id: UUID = UUID()) -> MacWorkspaceController {
        let tab = MacWorkspaceController(request: MacWorkspaceTabRequest(workspaceID: id, startsEmpty: false, initialPaneIntent: .local),
                                         defaults: defaults)
        tab.saveIfUnsaved()
        return tab
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

    @Test("what tmux says a pane shows: its host name is not a title; the name a tab gave the session comes too")
    func context() {
        #expect(MacLocalTmux.parseContext("/Users/ann/src\talpha.example.com\talpha\t\talpha.example.com\n")
                == MacWorkspacePaneContext(title: nil, directory: "/Users/ann/src"))
        #expect(MacLocalTmux.parseContext("/Users/ann/src\talpha.example.com\talpha\t\talpha\n")?.title == nil)
        #expect(MacLocalTmux.parseContext("/Users/ann/src\talpha.example.com\talpha\tbuild\t✳ Fix the build\tnow\n")
                == MacWorkspacePaneContext(title: "✳ Fix the build\tnow", directory: "/Users/ann/src", givenName: "build"))
        #expect(MacLocalTmux.parseContext("relative\th\th\t\t\n") == MacWorkspacePaneContext(title: nil, directory: nil))
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

    /// Against a private tmux server: the test's own runs name its socket with `-S`, and the app's
    /// run goes through a `tmux` that adds it, so the default server is never reached (rule 63).
    @Test("W19, live: one run of tmux says every session's title, folder and given name",
          .enabled(if: TerminalTmuxTests.tmux != nil))
    func contextsLive() throws {
        let tmux = try #require(TerminalTmuxTests.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8).lowercased())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let socket = folder.appendingPathComponent("s").path
        let environment = ["PATH": "/usr/bin:/bin"]
        @discardableResult func run(_ arguments: [String]) -> Int32 {
            LiveProcess.run(tmux, ["-S", socket] + arguments, environment: environment).status
        }
        defer { run(["kill-server"]) }
        let work = try #require(realpath(folder.path, nil).map { resolved in
            defer { free(resolved) }
            return String(cString: resolved)
        }) + "/shop"
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        #expect(run(["-u", "-f", "/dev/null", "new-session", "-d", "-s", "glass-1", "-c", work, "-x", "80", "-y", "10",
                     "/bin/sleep", "600"]) == 0)
        #expect(run(["-u", "new-session", "-d", "-s", "glass-2", "-c", "/usr", "/bin/sleep", "600"]) == 0)
        #expect(run(["-u", "select-pane", "-t", "=glass-1:", "-T", "✳ Claude Code: fix"]) == 0)
        #expect(run(try #require(TerminalTmux.givenNameArguments(session: "glass-2", name: "deploys; \"$HOME\""))) == 0)

        let shim = folder.appendingPathComponent("tmux")
        try Data("#!/bin/sh\nexec \(TerminalTmux.quoted(tmux)) -S \(TerminalTmux.quoted(socket)) \"$@\"\n".utf8).write(to: shim)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let contexts = try #require(MacLocalTmux.contexts(tmux: shim.path, environment: environment))
        #expect(contexts.keys.sorted() == ["glass-1", "glass-2"])
        #expect(contexts["glass-1"] == MacWorkspacePaneContext(title: "✳ Claude Code: fix", directory: work))
        #expect(contexts["glass-2"] == MacWorkspacePaneContext(title: nil, directory: "/usr", givenName: "deploys; \"$HOME\""),
                "tmux's own title, the host's name, is no title")
        #expect(run(["kill-server"]) == 0)
        #expect(MacLocalTmux.contexts(tmux: shim.path, environment: environment) == nil, "no server: nothing read")
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

    /// The claim as the app runs it — tmux's own argv, no shell, the pane's environment (W37) —
    /// against a private tmux server, named by its socket in every call and started with no
    /// configuration.
    @Test("a claim makes the session in the pane's folder, and gives a new server the pane's environment",
          .enabled(if: TerminalTmuxTests.tmux != nil))
    func claimLive() throws {
        let tmux = try #require(TerminalTmuxTests.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let socket = folder.appendingPathComponent("s").path
        var launch = MacLocalTerminalConfiguration.tmuxLaunch(shell: nil, directory: folder.path)
        // `sleep` in place of the login shell, so no dotfiles run.
        launch.command = ["/bin/sleep", "600"]
        launch.environment.append("TMUX_TMPDIR=\(folder.path)")
        let environment = launch.environmentVariables
        defer { _ = MacLocalTmux.run(tmux, ["-S", socket, "kill-server"], environment: environment) }
        func claim(_ candidates: [String]) -> TerminalTmux.Claim {
            MacLocalTmux.claim(candidates, launch: launch, tmux: tmux, serverArguments: ["-S", socket, "-f", "/dev/null"])
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

            // W6: every session is listed, Glass's own first; those a tab here shows are open here.
            #expect(MacLocalTmux.listable(MacLocalTmux.sessions(tmux: "tmux")).map(\.name) == names + ["work"])
            #expect(names.map(MacLocalTmux.shownCount) == [1, 1] && MacLocalTmux.shownCount("work") == 0)

            tab.removePane(panes[0].id, sessionManager: sessionManager)
            #expect(names.map(MacLocalTmux.shownCount) == [0, 1], "a closed pane's session is no longer open here")
            tab.closeAllSessions(sessionManager: sessionManager)
            try await Task.sleep(for: .milliseconds(100))
            #expect(fake.killed.isEmpty, "closing never ends a session in tmux")
            #expect(MacLocalTmux.listable(MacLocalTmux.sessions(tmux: "tmux")).map(\.name) == names + ["work"])
            #expect(names.map(MacLocalTmux.shownCount) == [0, 0])
        }
    }

    @Test("a window holding local terminals in tmux opens again after a quit, once, unless macOS restores it")
    func reopening() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            var window: MacWorkspaceWindowController? = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(initialPaneIntent: .local), defaults: defaults)
            // On screen, so saved; init itself writes nothing (W7b).
            window?.windowDidOpen()
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
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults, open: [id]).isEmpty,
                    "macOS restored it: not opened a second time")
            defaults.set([id.uuidString], forKey: MacLocalTmux.reopenKey)
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults, open: []) == [id],
                    "restoration on, but macOS brought nothing back: it opens all the same (2026-10-09)")
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

    @Test("Select All over a local tmux pane reads its session's history; a plain shell has none to read")
    func history() async throws {
        #expect(TerminalTmux.historyArguments(session: "glass-2") == ["-u", "capture-pane", "-p", "-J", "-S", "-", "-E", "-", "-t", "=glass-2:"])
        try await withFake { _, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let tab = localTab(defaults)
            let pane = try #require(tab.focusedPaneID)
            let session = try #require(tab.localTmuxSession(for: pane))
            let runtime = try #require(tab.localRuntime(for: pane))
            let read = try #require(runtime.model.onFullHistory, "a tmux pane reads tmux's history")
            #expect(await read() == "history of \(session)", "trailing blanks and empty rows dropped")

            defaults.set(false, forKey: UserDefaultsKeys.localTmux)
            tab.addPane(intent: .local, axis: .horizontal)
            let plainPane = try #require(tab.focusedPaneID)
            let plain = try #require(tab.localRuntime(for: plainPane))
            #expect(plain.model.onFullHistory == nil, "a plain shell's scrollback is the terminal's own")
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

    @Test("a pane in tmux closes when its session ends, not when its client is detached")
    func detachedPaneStays() {
        let runs: (String) -> Bool? = { _ in true }
        let ended: (String) -> Bool? = { _ in false }
        let unknown: (String) -> Bool? = { _ in nil }
        #expect(!MacLocalTerminalExitPolicy.shouldClose(exitCode: 0, tmuxSession: "glass-3", sessionRuns: runs),
                "detached from elsewhere: the session runs on, and so does the pane")
        #expect(MacLocalTerminalExitPolicy.shouldClose(exitCode: 0, tmuxSession: "glass-3", sessionRuns: ended),
                "the session ended: the pane goes with it")
        #expect(!MacLocalTerminalExitPolicy.shouldClose(exitCode: 0, tmuxSession: "glass-3", sessionRuns: unknown),
                "tmux could not say: the pane stays")
        #expect(MacLocalTerminalExitPolicy.shouldClose(exitCode: 0, tmuxSession: nil, sessionRuns: runs),
                "not in tmux: a shell that exits closes its pane, as before")
        #expect(!MacLocalTerminalExitPolicy.shouldClose(exitCode: nil, tmuxSession: "glass-3", sessionRuns: ended),
                "a process killed by a signal never closes its pane")
    }

    // MARK: W6 — Active names sessions as the tabs do, and knows this Mac (2026-10-08)

    /// One session's line in the listing's full format (`TerminalTmux.listFormat`), with no
    /// activity time, so a row's second line reads the same whenever the test runs.
    private static func line(_ name: String, attached: Int = 0, server: TerminalTmux.Server, directory: String,
                                         title: String = "alpha.example.com", given: String = "", command: String = "zsh",
                                         repository: String = "", branch: String = "") -> String {
        [name, String(attached), "1", "", String(server.pid), String(server.startTime), server.socketPath, command,
         "alpha.example.com", "alpha", given, directory, repository, branch, title].joined(separator: "\t")
    }

    /// Waits up to two seconds for `condition`.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @MainActor private final class Commands {
        var all: [String] = []
    }

    @Test("W6: a host whose sessions come from this Mac's own tmux is this Mac: listed once, under This Mac, named as the tabs are; one a tab here shows is open here, and Open brings that tab forward")
    func thisMacIsRecognised() async throws {
        try await withFake { fake, _ in
            let home = NSHomeDirectory()
            let thisMac = TerminalTmux.Server(pid: 4242, startTime: 1_790_000_000, socketPath: "/private/tmp/tmux-501/default")
            // Another Mac, same account and even the same pid: told apart by when its server started.
            let other = TerminalTmux.Server(pid: 4242, startTime: 1_780_000_000, socketPath: "/private/tmp/tmux-501/default")
            let listing = [
                Self.line("glass-1", attached: 1, server: thisMac, directory: home + "/src/shop", title: "✳ Claude Code", command: "claude"),
                Self.line("glass-2", attached: 1, server: thisMac, directory: home + "/src/notes"),
                Self.line("glass-3", server: thisMac, directory: home + "/src/shop-task-2"),
                Self.line("glass-4", server: thisMac, directory: home, given: "build"),
            ].joined(separator: "\n") + "\n"
            fake.listing = listing
            // A tab here shows glass-1.
            MacLocalTmux.noteShown("glass-1")
            defer { MacLocalTmux.noteHidden("glass-1") }

            let runtime = GlassTerminalRuntime(layers: GlassLayerStore())
            let capability = GlassTerminalCapability(runtime: runtime)
            var alpha = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")
            alpha.tmux = true
            var bravo = ServerConfiguration(name: "bravo", host: "bravo.example.com", username: "ann")
            bravo.tmux = true
            runtime.sessionManager.serverManager.servers = [alpha, bravo]

            // This Mac reached over SSH as the host alpha: an SSH tab here shows glass-2 that way.
            let overSSH = TerminalSession(server: alpha, terminalWriteSink: { _ in })
            overSSH.tmuxSessionName = "glass-2"
            overSSH.tmuxCommandRunner = { _ in listing }
            runtime.sessionManager.registerSession(overSSH)
            overSSH.state = .connected
            await overSSH.waitForTmuxAttach()
            // bravo answers over a terminal open to it, which shows none of its sessions.
            var bravoCopy = bravo
            bravoCopy.tmux = false
            let toBravo = TerminalSession(server: bravoCopy, terminalWriteSink: { _ in })
            let bravoListing = Self.line("glass-1", attached: 1, server: other, directory: "/home/ann/src/app")
                + "\n__glass_home__\t/home/ann\n"
            toBravo.tmuxCommandRunner = { _ in bravoListing }
            runtime.sessionManager.registerSession(toBravo)
            toBravo.state = .connected

            let revealed = Commands()
            let reveal = GlassTerminalCapability.revealLocalTmuxSession
            GlassTerminalCapability.revealLocalTmuxSession = { revealed.all.append($0); return true }
            defer { GlassTerminalCapability.revealLocalTmuxSession = reveal }

            let rows = await capability.runningReport().sessions
            let alphaEndpoint = EndpointID(rawValue: alpha.id), bravoEndpoint = EndpointID(rawValue: bravo.id)
            let underAlpha = rows.filter { $0.endpointID == alphaEndpoint }
            #expect(underAlpha.isEmpty, "alpha is this Mac: nothing listed twice")
            let local = rows.filter { $0.endpointID == GlassTerminalCapability.localShellEndpointID }
            #expect(local.map(\.id) == ["terminal-tmux:local:glass-1", "terminal-tmux:local:glass-3", "terminal-tmux:local:glass-4"],
                    "glass-2 is open here over SSH, a row of its own under alpha")
            #expect(local.map(\.title) == ["✳ Claude Code", "shop-task-2", "build"], "named as the tabs name them")
            #expect(local.map(\.subtitle) == ["~/src/shop · Open here", "~/src/shop-task-2 · Detached", "~ · Detached"])
            #expect(local.map(\.isOpenHere) == [true, false, false])
            #expect(local.map(\.isAttachedElsewhere) == [false, false, false], "the client attached is this app's tab")

            let onBravo = rows.filter { $0.endpointID == bravoEndpoint }
            #expect(onBravo.map(\.title) == ["app"] && onBravo.map(\.subtitle) == ["~/src/app · Open elsewhere"],
                    "another machine's sessions stay under it, named from its own home")

            _ = runtime.takeRequests()
            try #require(local.count == 3)
            local[0].open()
            #expect(revealed.all == ["glass-1"], "Open brings forward the tab showing it")
            #expect(runtime.takeRequests().isEmpty, "and never attaches a second client")
            local[1].open()
            guard case .localTerminal(let opened)? = runtime.takeRequests().first else {
                Issue.record("a detached session opens in a new tab")
                return
            }
            #expect(opened == "glass-3")
            runtime.sessionManager.closeSession(overSSH)
            runtime.sessionManager.closeSession(toBravo)
        }
    }

    @Test("W6: Open for a session open here brings forward the tab showing it, on its pane")
    func revealsTheTabShowingIt() async throws {
        try await withFake { _, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let window = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(), defaults: defaults)
            let shownTab = try #require(window.tabs.first)
            let pane = try #require(shownTab.focusedPaneID)
            let session = try #require(shownTab.localTmuxSession(for: pane))
            _ = try #require(shownTab.localRuntime(for: pane))
            shownTab.addPane(intent: .local, axis: .horizontal)
            #expect(shownTab.focusedPaneID != pane)
            _ = try #require(window.addTab())
            #expect(window.selectedTabID != shownTab.workspaceID)

            let registry = MacWorkspacePreviewRegistry()
            let onScreen = NSWindow()
            onScreen.isReleasedWhenClosed = false
            registry.register(window, window: onScreen)
            var presented: [NSWindow] = []
            #expect(registry.reveal(localTmuxSession: session, present: { presented.append($0) }))
            #expect(window.selectedTabID == shownTab.workspaceID, "its tab is selected")
            #expect(shownTab.focusedPaneID == pane, "on the pane showing it")
            #expect(presented.count == 1 && presented.first === onScreen, "and its window comes forward")
            #expect(!registry.reveal(localTmuxSession: "glass-999", present: { _ in Issue.record("no tab shows it") }))
            for tab in window.tabs { tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
        }
    }

    @Test("W6: naming a tab names its tmux session; going back to the automatic name takes it away")
    func renamingNamesTheSession() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let tab = localTab(defaults)
            let session = try #require(tab.focusedPaneID.flatMap(tab.localTmuxSession(for:)))
            tab.rename(to: "shop; \"$HOME\" `id`")
            tab.rename(to: nil)
            MacLocalTmux.nameQueue.sync {}
            #expect(fake.givenNames.map(\.session) == [session, session])
            #expect(fake.givenNames.map(\.name) == ["shop; \"$HOME\" `id`", nil])
        }
    }

    @Test("W6: a tab attaching to a session another tab named takes that name, once; naming it here wins")
    func attachingTakesTheGivenName() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let tab = localTab(defaults)
            let pane = try #require(tab.focusedPaneID)
            let session = try #require(tab.localTmuxSession(for: pane))
            _ = try #require(tab.localRuntime(for: pane))
            tab.paneContextInterval = .zero
            fake.contexts = [session: MacWorkspacePaneContext(title: nil, directory: NSHomeDirectory(), givenName: "shop")]
            tab.refreshLocalTmuxContext()
            #expect(await eventually { tab.windowIdentity(servers: []).title == "shop" })

            tab.rename(to: nil)
            tab.refreshLocalTmuxContext()
            try await Task.sleep(for: .milliseconds(200))
            #expect(tab.windowIdentity(servers: []).title == MacWorkspaceTabNaming.tmuxDisplayName(session),
                    "the automatic name, chosen here, is not replaced by the session's old one")
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))

            // Chosen before tmux was first asked: the old name, read after, is not taken either.
            let other = localTab(defaults)
            let otherPane = try #require(other.focusedPaneID)
            let otherSession = try #require(other.localTmuxSession(for: otherPane))
            _ = try #require(other.localRuntime(for: otherPane))
            other.paneContextInterval = .zero
            fake.contexts[otherSession] = MacWorkspacePaneContext(title: nil, directory: NSHomeDirectory(), givenName: "shop")
            other.rename(to: nil)
            other.refreshLocalTmuxContext()
            #expect(await eventually { other.paneContextByPaneID[otherPane] != nil }, "tmux was asked")
            #expect(other.windowIdentity(servers: []).title == MacWorkspaceTabNaming.tmuxDisplayName(otherSession))
            other.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        }
    }

    @Test("W6: an SSH tab in tmux takes the name its host's session was given, and naming it names the session there")
    func sshTabsNameTheirSessions() async throws {
        try await withFake { _, defaults in
            let host = HostSession()
            host.given = "shop"
            let (window, tab, session) = await sshTab(host, defaults)
            #expect(tab.focusedPaneID.flatMap(tab.session(for:)) === session)

            // W19: the session's own read, once the tab has it, rather than a query of its own.
            #expect(await eventually { tab.windowIdentity(servers: [host.server]).title == "shop" })
            tab.rename(to: "build")
            tab.rename(to: nil)
            let named = try #require(TerminalTmux.givenNameCommand(session: "glass-5", name: "build"))
            let unnamed = try #require(TerminalTmux.givenNameCommand(session: "glass-5", name: nil))
            #expect(await eventually { host.commands.contains(named) && host.commands.contains(unnamed) })
            _ = window
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        }
    }

    // MARK: W19 — open Mac tabs keep up with names given elsewhere; SSH tabs in tmux show what runs (2026-10-10)

    /// A host's tmux session `glass-5` on `alpha`, from memory: what a read of it answers, every
    /// command it was sent, and the names a tab here may give it, which then show in its reads.
    @MainActor private final class HostSession {
        let server: ServerConfiguration = {
            var server = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")
            server.tmux = true
            return server
        }()
        var commands: [String] = []
        var readTimes: [ContinuousClock.Instant] = []
        var given = ""
        var title = "✳ Claude Code"
        var directory = "/home/ann/src/app/Sources"
        var repository: (top: String, branch: String)? = ("/home/ann/src/app", "main")
        /// How long a read takes on the host.
        var delay: Duration = .zero
        /// Names a tab here may give the session: one sent shows in the reads after it.
        var nameable: [String?] = [nil]
        let read = TerminalTmux.paneStateCommand(session: "glass-5")!

        func run(_ command: String) async throws -> String {
            commands.append(command)
            if let name = nameable.first(where: { TerminalTmux.givenNameCommand(session: "glass-5", name: $0) == command }) {
                given = name ?? ""
                return ""
            }
            guard command == read else { return "" }
            readTimes.append(.now)
            let pane = [TerminalTmux.paneMarker, "/home/ann", directory, "alpha.example.com", "alpha", given, title]
                .joined(separator: "\t")
            let answer = pane + "\n" + (repository.map {
                [TerminalRepository.remoteMarker, $0.top, "../.git", $0.branch, "/home/ann"].joined(separator: "\n") + "\n"
            } ?? "")
            if delay > .zero { try await Task.sleep(for: delay) }
            return answer
        }
    }

    /// A Mac window whose one tab shows a terminal in `host`'s session, as Connect hands it a
    /// connected terminal; `label` is the tab's own name, as a saved tab has one.
    private func sshTab(_ host: HostSession, _ defaults: UserDefaults, label: String? = nil, connected: Bool = true)
        async -> (MacWorkspaceWindowController, MacWorkspaceController, TerminalSession) {
        let session = TerminalSession(server: host.server, terminalWriteSink: { _ in })
        session.tmuxSessionName = "glass-5"
        session.tmuxPaneReadInterval = .zero
        session.outputSettleDelay = .milliseconds(30)
        session.tmuxCommandRunner = { try await host.run($0) }
        if connected {
            session.state = .connected
            await session.waitForTmuxAttach()
        }
        let broker = MacLiveSessionBroker()
        let ticket = broker.issue(session: session) {}
        let request = MacWorkspaceLaunchRequest(tabs: [MacWorkspaceTabRequest(initialPaneIntent: .ssh(serverID: host.server.id),
                                                                            tabLabel: label, liveSessionTicketID: ticket)])
        let window = MacWorkspaceWindowController(request: request, liveSessionBroker: broker, defaults: defaults)
        let tab = window.tabs[0]
        tab.paneContextInterval = .zero
        return (window, tab, session)
    }

    /// Output in the terminal that comes to rest.
    private func settle(_ session: TerminalSession) async {
        let before = session.outputSettledNonce
        session.feedTerminalData(Data("output\r\n".utf8))
        _ = await eventually { session.outputSettledNonce > before }
    }

    /// The name the window's record keeps for its first tab; nil when nothing is saved.
    private func savedLabel(_ window: MacWorkspaceWindowController, _ defaults: UserDefaults) -> String?? {
        guard case .restored(let saved) = MacWorkspaceWindowController.load(windowID: window.windowID, defaults: defaults)
        else { return nil }
        return .some(saved.tabs.first?.tabLabel)
    }

    @Test("W19: an open local tab follows its session's name — given on another device, given again, taken away there — and its window saves it")
    func localTabFollowsItsSessionsName() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let window = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(), defaults: defaults)
            let tab = try #require(window.tabs.first)
            let pane = try #require(tab.focusedPaneID)
            let session = try #require(tab.localTmuxSession(for: pane))
            _ = try #require(tab.localRuntime(for: pane))
            tab.paneContextInterval = .zero
            // At home, with no program's title: Active and the tab call it by its session.
            let automatic = MacWorkspaceTabNaming.tmuxDisplayName(session)
            fake.contexts = [session: MacWorkspacePaneContext(title: nil, directory: NSHomeDirectory())]
            tab.refreshLocalTmuxContext()
            #expect(await eventually { fake.contextReads == 1 })
            #expect(tab.windowIdentity(servers: []).title == automatic)

            fake.contexts[session]?.givenName = "deploys"
            tab.refreshLocalTmuxContext()
            #expect(await eventually { tab.windowIdentity(servers: []).title == "deploys" },
                    "named on the iPhone while the tab is open: before W19 only a tab attaching took it")
            #expect(savedLabel(window, defaults) == .some("deploys"), "the window saves it, as Rename does")

            fake.contexts[session]?.givenName = "deploys 2"
            tab.refreshLocalTmuxContext()
            #expect(await eventually { tab.windowIdentity(servers: []).title == "deploys 2" }, "and again: not once only")

            fake.contexts[session]?.givenName = nil
            tab.refreshLocalTmuxContext()
            #expect(await eventually { tab.tabLabel == nil }, "Use Automatic Name there")
            #expect(tab.windowIdentity(servers: []).title == automatic)
            #expect(savedLabel(window, defaults) == .some(nil))
            #expect(fake.givenNames.isEmpty, "a name taken from the session is never written back to it")
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        }
    }

    @Test("W19: a local tab named here keeps the name though a read of its session begun before says the old one")
    func localRenameWinsOverAnOlderRead() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let tab = localTab(defaults)
            let pane = try #require(tab.focusedPaneID)
            let session = try #require(tab.localTmuxSession(for: pane))
            _ = try #require(tab.localRuntime(for: pane))
            tab.paneContextInterval = .zero
            fake.contexts = [session: MacWorkspacePaneContext(title: nil, directory: NSHomeDirectory(), givenName: "old")]
            tab.refreshLocalTmuxContext()
            #expect(await eventually { tab.tabLabel == "old" }, "attaching, the tab takes the session's name")

            fake.contextReadDelay = 0.3
            tab.refreshLocalTmuxContext()
            #expect(await eventually { fake.contextReads == 2 }, "a read is on its way, and will say \"old\"")
            tab.rename(to: "new")
            try await Task.sleep(for: .milliseconds(600))
            #expect(tab.tabLabel == "new", "the read begun before the rename is not taken over it")
            #expect(fake.givenNames.map(\.name) == ["new"] && fake.contexts[session]?.givenName == "new")

            fake.contextReadDelay = 0
            tab.refreshLocalTmuxContext()
            #expect(await eventually { fake.contextReads == 3 })
            try await Task.sleep(for: .milliseconds(100))
            #expect(tab.tabLabel == "new", "the next read finds it on the session")
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        }
    }

    @Test("W19: a local tab meeting its session takes the session's name, or gives the session its own when it has none")
    func localTabMeetsItsSession() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            @MainActor func namedTab(_ label: String) throws -> (MacWorkspaceController, String) {
                let tab = MacWorkspaceController(request: MacWorkspaceTabRequest(initialPaneIntent: .local, tabLabel: label),
                                                 defaults: defaults)
                tab.saveIfUnsaved()
                let pane = try #require(tab.focusedPaneID)
                _ = try #require(tab.localRuntime(for: pane))
                tab.paneContextInterval = .zero
                return (tab, try #require(tab.localTmuxSession(for: pane)))
            }
            // Renamed on the iPhone while this tab was closed: the session's name is the newer.
            let (renamedElsewhere, first) = try namedTab("build")
            fake.contexts[first] = MacWorkspacePaneContext(title: nil, directory: NSHomeDirectory(), givenName: "deploys")
            renamedElsewhere.refreshLocalTmuxContext()
            #expect(await eventually { renamedElsewhere.tabLabel == "deploys" })
            #expect(fake.givenNames.isEmpty)

            // Named before names were kept on sessions (W6): the session is given the tab's name,
            // so Active and every other device say it too.
            let (namedBefore, second) = try namedTab("api")
            fake.contexts[second] = MacWorkspacePaneContext(title: nil, directory: NSHomeDirectory())
            namedBefore.refreshLocalTmuxContext()
            #expect(await eventually { fake.givenNames.map(\.session) == [second] })
            #expect(fake.givenNames.map(\.name) == ["api"] && namedBefore.tabLabel == "api")
            for tab in [renamedElsewhere, namedBefore] { tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
        }
    }

    @Test("W19: one read of this Mac's tmux answers every local tab, at most one an interval, none while quiet; a quiet tab hears of a name given elsewhere")
    func oneReadForEveryLocalTab() async throws {
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let interval = Duration.milliseconds(400)
            MacLocalTmux.contextReads = MacLocalTmuxContextReads(interval: interval)
            var tabs: [MacWorkspaceController] = []
            var sessions: [String] = []
            for _ in 0..<3 {
                let tab = localTab(defaults)
                let pane = try #require(tab.focusedPaneID)
                sessions.append(try #require(tab.localTmuxSession(for: pane)))
                _ = try #require(tab.localRuntime(for: pane))
                tab.paneContextInterval = .zero
                tabs.append(tab)
            }
            for (index, session) in sessions.enumerated() {
                fake.contexts[session] = MacWorkspacePaneContext(title: "job \(index)", directory: NSHomeDirectory())
            }
            @MainActor func titles() -> [String] { tabs.map { $0.windowIdentity(servers: []).title } }

            for tab in tabs { tab.refreshLocalTmuxContext() }
            #expect(await eventually { titles() == ["job 0", "job 1", "job 2"] })
            #expect(fake.contextReads == 1, "three tabs settling together are one run of tmux")

            let first = ContinuousClock.now
            tabs[0].refreshLocalTmuxContext()
            tabs[1].refreshLocalTmuxContext()
            #expect(await eventually { fake.contextReads == 2 }, "asked within the interval: one more read, at its end")
            #expect(ContinuousClock.now - first >= interval - .milliseconds(150), "not before the interval is out")
            try await Task.sleep(for: interval * 2)
            #expect(fake.contextReads == 2, "every tab quiet: nothing more is read")

            fake.contexts[sessions[2]]?.givenName = "deploys"
            tabs[0].refreshLocalTmuxContext()
            #expect(await eventually { tabs[2].tabLabel == "deploys" }, "the quiet tab hears of it from another tab's read")
            #expect(fake.contextReads == 3)
            for tab in tabs { tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
        }
    }

    @Test("W19: an SSH tab in tmux is named by what runs in its session, as Active and every other device name it; its own reports stop at tmux")
    func sshTabShowsWhatRuns() async throws {
        try await withFake { _, defaults in
            let host = HostSession()
            let (window, tab, session) = await sshTab(host, defaults)
            let pane = try #require(tab.focusedPaneID)
            #expect(await eventually { tab.windowIdentity(servers: [host.server]).title == "✳ Claude Code" })
            #expect(tab.windowIdentity(servers: [host.server]).subtitle == "app · main · ann@alpha.example.com:22")
            let tile = MacTerminalExposeModel.tile(for: tab, servers: [host.server])
            #expect(tile.title == "✳ Claude Code" && tile.folder == "~/src/app/Sources" && tile.repository == "app · main",
                    "Show All Terminals says the same")

            // The terminal's own title report is tmux's, or a shell's from before tmux: not the session's.
            tab.updatePaneContext(title: "ann@alpha: ~", directory: "/home/ann", for: pane)
            #expect(tab.windowIdentity(servers: [host.server]).title == "✳ Claude Code")

            // The program ends, at home and outside a repository: nothing names it, so the server does.
            host.title = "alpha.example.com"
            host.directory = "/home/ann"
            host.repository = nil
            await settle(session)
            #expect(await eventually { tab.windowIdentity(servers: [host.server]).title == "alpha" })
            #expect(tab.windowIdentity(servers: [host.server]).subtitle == "ann@alpha.example.com:22")
            // Besides its reads, only W11's note of the repository on the session, once per change.
            let kept = try #require(TerminalTmux.repositoryCommand(session: "glass-5",
                                                                   repository: TerminalRepository(name: "app", branch: "main")))
            let none = try #require(TerminalTmux.repositoryCommand(session: "glass-5", repository: nil))
            #expect(host.commands.filter { $0 != host.read } == [kept, none],
                    "the read says the folder and repository too: no lookup or name query of its own: \(host.commands)")
            _ = window
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        }
    }

    @Test("W19: an open SSH tab in tmux follows its session's name, the window saves it, and a name given here wins over a read begun before it")
    func sshTabFollowsItsSessionsName() async throws {
        try await withFake { _, defaults in
            let host = HostSession()
            host.nameable = ["build", nil]
            let (window, tab, session) = await sshTab(host, defaults)
            #expect(await eventually { tab.windowIdentity(servers: [host.server]).title == "✳ Claude Code" })

            host.given = "deploys"
            await settle(session)
            #expect(await eventually { tab.windowIdentity(servers: [host.server]).title == "deploys" })
            #expect(savedLabel(window, defaults) == .some("deploys"))
            host.given = ""
            await settle(session)
            #expect(await eventually { tab.tabLabel == nil }, "Use Automatic Name there")
            #expect(tab.windowIdentity(servers: [host.server]).title == "✳ Claude Code")
            #expect(savedLabel(window, defaults) == .some(nil))

            host.given = "old"
            host.delay = .milliseconds(300)
            let reads = host.readTimes.count
            await settle(session)
            #expect(await eventually { host.readTimes.count == reads + 1 }, "a read is on its way, and will say \"old\"")
            window.renameTab(tab.workspaceID, to: "build")
            let named = try #require(TerminalTmux.givenNameCommand(session: "glass-5", name: "build"))
            #expect(await eventually { host.commands.contains(named) })
            try await Task.sleep(for: .milliseconds(500))
            #expect(tab.tabLabel == "build" && host.given == "build", "the read begun before the rename is not taken over it")
            host.delay = .zero
            await settle(session)
            try await Task.sleep(for: .milliseconds(100))
            #expect(tab.tabLabel == "build" && savedLabel(window, defaults) == .some("build"))
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        }
    }

    @Test("W19: an SSH tab named while its terminal was not connected tells the session once it is, and a session made again under the same name is given the tab's name rather than taking it away")
    func sshTabTellsItsSession() async throws {
        try await withFake { _, defaults in
            let host = HostSession()
            host.nameable = ["build"]
            let named = try #require(TerminalTmux.givenNameCommand(session: "glass-5", name: "build"))

            // Named before its terminal connected: the session, still called "old", is told.
            host.given = "old"
            let (window, tab, session) = await sshTab(host, defaults, connected: false)
            window.renameTab(tab.workspaceID, to: "build")
            #expect(!host.commands.contains(named), "not connected: nothing reached the host")
            session.state = .connected
            #expect(await eventually { host.commands.contains(named) })
            #expect(tab.tabLabel == "build" && host.given == "build")

            // The host restarted, and reconnecting made glass-5 again: a session with no name.
            let told = host.commands.filter { $0 == named }.count
            session.state = .disconnected
            host.given = ""
            session.state = .connected
            #expect(await eventually { host.commands.filter { $0 == named }.count == told + 1 })
            #expect(tab.tabLabel == "build", "the tab keeps its name, and the new session is given it")
            _ = window
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        }
    }

    @Test("W19: Active's row for an SSH terminal open in a Mac tab is called what the tab is called")
    func activeNamesAnOpenSSHTerminalAsItsTab() async throws {
        try await withFake { _, defaults in
            let host = HostSession()
            let (window, tab, session) = await sshTab(host, defaults)
            #expect(await eventually { tab.windowIdentity(servers: [host.server]).title == "✳ Claude Code" })
            let runtime = GlassTerminalRuntime(layers: GlassLayerStore())
            runtime.sessionManager.serverManager.servers = [host.server]
            runtime.sessionManager.registerSession(session)
            let capability = GlassTerminalCapability(runtime: runtime)
            let rowID = GlassTerminalCapability.sessionID(sessionID: session.id)
            #expect(capability.openSessions().first { $0.id == rowID }?.title == "✳ Claude Code",
                    "the terminal reads its session, so it names itself as its tab does")
            _ = window
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
            runtime.sessionManager.closeSession(session)

            // Not in tmux, the title its program set is the tab's alone: Active asks the tab.
            var plainServer = host.server
            plainServer.tmux = false
            let plain = TerminalSession(server: plainServer, terminalWriteSink: { _ in })
            plain.state = .connected
            let broker = MacLiveSessionBroker()
            let ticket = broker.issue(session: plain) {}
            let plainWindow = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(tabs: [MacWorkspaceTabRequest(initialPaneIntent: .ssh(serverID: plainServer.id),
                                                                                 liveSessionTicketID: ticket)]),
                liveSessionBroker: broker, defaults: defaults)
            let plainTab = plainWindow.tabs[0]
            plainTab.paneContextInterval = .zero
            plainTab.updatePaneContext(title: "vim notes.md", directory: nil, for: try #require(plainTab.focusedPaneID))
            #expect(plainTab.windowIdentity(servers: [plainServer]).title == "vim notes.md")
            runtime.sessionManager.registerSession(plain)
            let plainRowID = GlassTerminalCapability.sessionID(sessionID: plain.id)
            let onScreen = NSWindow()
            onScreen.isReleasedWhenClosed = false
            MacWorkspacePreviewRegistry.shared.register(plainWindow, window: onScreen)
            let title = capability.openSessions().first { $0.id == plainRowID }?.title
            MacWorkspacePreviewRegistry.shared.remove(plainWindow.windowID)
            #expect(title == "vim notes.md", "the tab's name, where Active said the server's")
            plainTab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
            runtime.sessionManager.closeSession(plain)
        }
    }

    // MARK: W11 — the repository and branch a session is in (2026-10-09)

    /// A repository as far as the reader looks — a `.git` folder and its HEAD — in a folder of
    /// the test's own, outside any home and any repository. Returns that folder, to remove.
    private static func scratchRepository(branch: String = "main") throws -> (root: String, app: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gpt-repo-\(UUID().uuidString.prefix(8))").path
        let app = root + "/app"
        try FileManager.default.createDirectory(atPath: app + "/.git", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: app + "/Sources", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: root + "/notes", withIntermediateDirectories: true)
        try Data("ref: refs/heads/\(branch)\n".utf8).write(to: URL(fileURLWithPath: app + "/.git/HEAD"))
        return (root, app)
    }

    @Test("W11: a local tab in tmux keeps the repository and branch it is in on its session — a change only — and leaving it takes them away")
    func repositoryKeptOnTheSession() async throws {
        let (root, app) = try Self.scratchRepository()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await withFake { fake, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let tab = localTab(defaults)
            let pane = try #require(tab.focusedPaneID)
            let session = try #require(tab.localTmuxSession(for: pane))
            _ = try #require(tab.localRuntime(for: pane))
            tab.paneContextInterval = .zero
            tab.localRepositoryInterval = .zero
            tab.repositoryCache = TerminalRepositoryCache()
            fake.contexts = [session: MacWorkspacePaneContext(title: nil, directory: app + "/Sources")]
            tab.refreshLocalTmuxContext()
            #expect(await eventually {
                tab.windowIdentity(servers: [], localUsername: "ann", home: "/Users/ann")
                    == MacWorkspaceWindowIdentity(title: "app", subtitle: "app · main · Sources · in tmux")
            })
            let kept = TerminalRepository(name: "app", branch: "main")
            #expect(await eventually { fake.repositories.map(\.repository) == [kept] })
            #expect(fake.repositories.map(\.session) == [session])

            tab.refreshRepositories()
            #expect(await eventually { tab.repositoryByPaneID[pane] == TerminalRepository(name: "app", branch: "main", root: app) })
            fake.contexts = [session: MacWorkspacePaneContext(title: nil, directory: root + "/notes")]
            tab.refreshLocalTmuxContext()
            #expect(await eventually { fake.repositories.map(\.repository) == [kept, nil] },
                    "told once while unchanged, then told it is in none")
            tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
        }
    }

    @Test("W11: Active says each of this Mac's sessions' repository and branch, read from its folder; a host's, from what its tab kept there")
    func activeSaysTheRepository() async throws {
        let (root, app) = try Self.scratchRepository()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await withFake { fake, _ in
            fake.readsRepositories = true
            let thisMac = TerminalTmux.Server(pid: 4242, startTime: 1_790_000_000, socketPath: "/private/tmp/tmux-501/default")
            fake.listing = [
                // What a tab kept on it before a checkout: this Mac reads the folder instead.
                Self.line("glass-1", server: thisMac, directory: app + "/Sources", repository: "app", branch: "old"),
                Self.line("glass-2", server: thisMac, directory: root + "/notes"),
            ].joined(separator: "\n") + "\n"

            let runtime = GlassTerminalRuntime(layers: GlassLayerStore())
            let capability = GlassTerminalCapability(runtime: runtime)
            var bravo = ServerConfiguration(name: "bravo", host: "bravo.example.com", username: "ann")
            bravo.tmux = true
            runtime.sessionManager.serverManager.servers = [bravo]
            var bravoCopy = bravo
            bravoCopy.tmux = false
            let toBravo = TerminalSession(server: bravoCopy, terminalWriteSink: { _ in })
            let other = TerminalTmux.Server(pid: 4242, startTime: 1_780_000_000, socketPath: "/private/tmp/tmux-501/default")
            let bravoListing = Self.line("glass-1", attached: 1, server: other, directory: "/home/ann/src/shop",
                                         repository: "shop", branch: "fix/login") + "\n__glass_home__\t/home/ann\n"
            toBravo.tmuxCommandRunner = { _ in bravoListing }
            runtime.sessionManager.registerSession(toBravo)
            toBravo.state = .connected

            let rows = await capability.runningReport().sessions
            let local = rows.filter { $0.endpointID == GlassTerminalCapability.localShellEndpointID }
            #expect(local.map(\.title) == ["app", "notes"])
            #expect(local.map(\.subtitle) == ["app · main · Sources · Detached", root + "/notes · Detached"])
            let onBravo = rows.filter { $0.endpointID == EndpointID(rawValue: bravo.id) }
            #expect(onBravo.map(\.title) == ["shop"] && onBravo.map(\.subtitle) == ["shop · fix/login · Open elsewhere"])
            runtime.sessionManager.closeSession(toBravo)
        }
    }
}
}
#endif
