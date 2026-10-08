#if os(macOS)
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
        var scrolled: [(String, Int)] { lock.withLock { _scrolled } }
        var running: Set<String> {
            get { lock.withLock { _running } }
            set { lock.withLock { _running = newValue } }
        }
        var killed: [String] { lock.withLock { _killed } }
        var detached: [String] { lock.withLock { _detached } }

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
                scroll: { name, lines, _ in self.lock.withLock { self._scrolled.append((name, lines)) } }
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
        #expect(tmux.arguments == ["-T", "sync,RGB", "new-session", "-A", "-s", "glass-3", "-c", "/tmp"],
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

            MacLocalTmux.rememberWindowsToReopen(defaults: defaults)
            #expect(defaults.stringArray(forKey: MacLocalTmux.reopenKey) == [id.uuidString])
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults, open: [id]).isEmpty,
                    "a window still open is not opened twice")

            // The next launch: nothing open yet.
            MacLocalTmux.rememberWindowsToReopen(defaults: defaults)
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
                == ["copy-mode", "-e", "-t", "=glass-2:", ";", "send-keys", "-t", "=glass-2:", "-X", "-N", "3", "scroll-up"])
        #expect(MacLocalTmux.scrollArguments(session: "glass-2", lines: -2)
                == ["send-keys", "-t", "=glass-2:", "-X", "-N", "2", "scroll-down"])
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

    @Test("a tab in tmux says so under its name")
    func subtitle() async throws {
        try await withFake { _, defaults in
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let tab = localTab(defaults)
            #expect(tab.windowIdentity(servers: [], localUsername: "ann", home: "/Users/ann").subtitle
                    == "ann@localhost · in tmux")
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
