//
//  MacLocalTmux.swift
//  Glass Power Tools — GlassTerminal
//
//  Local terminals kept in tmux (D47, 2026-10-07): quitting or updating Glass Power Tools no
//  longer ends what runs in a local tab — a build, a server, an agent session — and the tab
//  reattaches when the app comes back. The sessions are the Mac's own tmux server, the same one
//  an SSH connection to this Mac as the same user reaches, so their names share D44's `glass-N`.
//
//  Closing a tab detaches, as it does for a terminal in tmux on any other machine (D44), and
//  Active lists the Mac's sessions under This Mac to open again, take over or end. Ending one
//  first made closing end its session; the owner: "I can't resume it" (2026-10-07).
//

#if os(macOS)
import Foundation
import os

enum MacLocalTmux {
    /// The tmux the workspace talks to. Tests put a stand-in here.
    struct Server: Sendable {
        var executablePath: @Sendable () -> String?
        /// `TerminalTmux.listScript`'s answer, as printed: sessions in `TerminalTmux.listFormat`,
        /// or its failure marker; nil when it could not be run.
        var listSessions: @Sendable (_ tmux: String) -> String?
        var kill: @Sendable (_ name: String, _ tmux: String) -> Void
        var detachClients: @Sendable (_ name: String, _ tmux: String) -> Void
        /// Scrolls a session's history `lines` toward earlier output, or back when negative.
        var scroll: @Sendable (_ name: String, _ lines: Int, _ tmux: String) -> Void

        nonisolated static let live = Server(
            executablePath: { MacLocalTmux.executablePath() },
            listSessions: { MacLocalTmux.run("/bin/sh", ["-c", TerminalTmux.listScript(tmux: TerminalTmux.quoted($0))]) },
            kill: { MacLocalTmux.kill($0, tmux: $1) },
            detachClients: { MacLocalTmux.detachClients($0, tmux: $1) },
            scroll: { name, lines, tmux in
                guard let arguments = MacLocalTmux.scrollArguments(session: name, lines: lines) else { return }
                // One queue, so a quick up-then-down arrives in that order.
                MacLocalTmux.scrollQueue.async { _ = MacLocalTmux.run(tmux, arguments) }
            }
        )
    }

    @MainActor static var server = Server.live

    /// Homebrew's folders (Apple silicon, then Intel) and MacPorts'. A GUI app's PATH has none.
    nonisolated static let packageFolders = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]

    /// Where tmux is, if anywhere: the app's PATH, then the package managers' folders.
    nonisolated static func executablePath(searching path: String? = ProcessInfo.processInfo.environment["PATH"],
                               folders: [String] = packageFolders,
                               fileManager: FileManager = .default) -> String? {
        let candidates = ((path ?? "").split(separator: ":").map(String.init) + folders).map { $0 + "/tmux" }
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    /// The session a local pane runs in: its saved one while the setting is on or the session is
    /// still running (so turning the setting off never strands a running terminal), a new one when
    /// the setting is on, and none otherwise.
    nonisolated static func session(saved: String?, enabled: Bool,
                        isRunning: (String) -> Bool, allocate: () -> String) -> String? {
        if let saved, enabled || isRunning(saved) { return saved }
        return enabled ? allocate() : nil
    }

    /// Names chosen in this process and not yet started, so panes opening together do not share one.
    @MainActor private static var reserved: Set<String> = []

    /// A free `glass-N` on this Mac's tmux server. When the sessions cannot be read, a number far
    /// above those in use, as for a host (`TerminalTmux.unlistedName`): `glass-1` may be running,
    /// and the pane's `new-session -A` would join it.
    @MainActor static func allocateName(tmux: String) -> String {
        let name = listing(tmux: tmux).map { TerminalTmux.nextName(avoiding: Set($0.map(\.name)).union(reserved)) }
            ?? TerminalTmux.unlistedName(avoiding: reserved)
        reserved.insert(name)
        return name
    }

    /// The Mac's tmux sessions, in the form D44 reads from a host; none when no server runs, and
    /// none when they cannot be read — for a list to show. Choosing a name asks `listing`.
    @MainActor static func sessions(tmux: String) -> [TerminalTmux.Session] {
        sessions(from: server.listSessions(tmux))
    }

    /// The Mac's tmux sessions, or nil when tmux could not be asked or its answer not read.
    @MainActor static func listing(tmux: String) -> [TerminalTmux.Session]? {
        guard let output = server.listSessions(tmux), case .sessions(let sessions) = TerminalTmux.parse(output) else { return nil }
        return sessions
    }

    @MainActor static func sessions(from output: String?) -> [TerminalTmux.Session] {
        guard let output, case .sessions(let sessions) = TerminalTmux.parse(output) else { return [] }
        return sessions
    }

    /// What Active lists under This Mac: every session but those a tab here is showing, Glass's
    /// own first by number, as for any other machine.
    @MainActor static func listable(_ sessions: [TerminalTmux.Session]) -> [TerminalTmux.Session] {
        sessions.filter { shownHere[$0.name, default: 0] == 0 }
            .sorted { (TerminalTmux.glassNumber($0.name) ?? .max, $0.name) < (TerminalTmux.glassNumber($1.name) ?? .max, $1.name) }
    }

    /// Sessions a tab in this app is attached to, by how many panes show each.
    @MainActor private(set) static var shownHere: [String: Int] = [:]
    @MainActor static func noteShown(_ name: String) { shownHere[name, default: 0] += 1 }
    @MainActor static func noteHidden(_ name: String) {
        let count = shownHere[name, default: 0] - 1
        shownHere[name] = count > 0 ? count : nil
    }

    /// A pane is about to attach to `name`: noted, or refused and logged when a tab here already
    /// shows it. A second client would mirror the first window, which is how a dragged tab looked
    /// like a copy of its session (2026-10-08). A view asks on every redraw, so a refusal is
    /// logged once until the session is next claimed.
    @MainActor static func claimShown(_ name: String) -> Bool {
        guard shownHere[name, default: 0] == 0 else {
            if refusalsLogged.insert(name).inserted {
                logger.error("Refused a second client for tmux session \(name, privacy: .public): a tab here already shows it")
            }
            return false
        }
        refusalsLogged.remove(name)
        noteShown(name)
        return true
    }

    @MainActor private static var refusalsLogged: Set<String> = []
    nonisolated private static let logger = Logger(subsystem: "sh.glas", category: "tmux")

    /// What the session's active pane shows: the directory its shell is in, and the title a
    /// program set. tmux keeps both from the terminal outside it, so a tab in tmux asks.
    nonisolated static func context(session: String, tmux: String,
                                    environment: [String: String] = ProcessInfo.processInfo.environment) -> MacWorkspacePaneContext? {
        run(tmux, ["-u", "display-message", "-p", "-t", "=" + session + ":",
                   "#{pane_current_path}\t#{host}\t#{host_short}\t#{pane_title}"], environment: environment).flatMap(parseContext)
    }

    /// tmux titles a pane with the host name until a program sets one; that is not a title.
    nonisolated static func parseContext(_ output: String) -> MacWorkspacePaneContext? {
        let fields = output.trimmingCharacters(in: .newlines)
            .split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4 else { return nil }
        let title = fields[3].trimmingCharacters(in: .whitespaces)
        return MacWorkspacePaneContext(
            title: title.isEmpty || title == fields[1] || title == fields[2] ? nil : title,
            directory: fields[0].hasPrefix("/") ? fields[0] : nil
        )
    }

    /// A pane is done with its name: the session ended, or it runs on without a tab.
    @MainActor static func release(_ name: String) {
        reserved.remove(name)
    }

    /// Ends a session and everything in it — Active's End. A session already gone is not an error.
    nonisolated static func kill(_ name: String, tmux: String) {
        _ = run(tmux, ["-u", "kill-session", "-t", "=" + name])
    }

    /// Scrolling a session's history like a terminal's scrollback (2026-10-08): up enters copy
    /// mode, which `-e` leaves again on reaching the bottom; down outside it is a harmless error.
    nonisolated static func scrollArguments(session: String, lines: Int) -> [String]? {
        guard lines != 0 else { return nil }
        let target = "=" + session + ":"
        return lines > 0
            ? ["-u", "copy-mode", "-e", "-t", target, ";", "send-keys", "-t", target, "-X", "-N", String(lines), "scroll-up"]
            : ["-u", "send-keys", "-t", target, "-X", "-N", String(-lines), "scroll-down"]
    }

    nonisolated static let scrollQueue = DispatchQueue(label: "GlassPowerTools.local-tmux-scroll", qos: .userInteractive)

    /// Detaches everyone else from a session — Active's Take Over, before this Mac attaches.
    nonisolated static func detachClients(_ name: String, tmux: String) {
        _ = run(tmux, ["-u", "detach-client", "-s", "=" + name])
    }

    /// The process a local pane runs when it is kept in tmux: attach to its session, or create it
    /// in the pane's directory. tmux starts the user's login shell inside, so their PATH and
    /// prompt are as they would be in Terminal.app.
    ///
    /// `-T` tells tmux what this terminal can do beyond the xterm its TERM names: synchronized
    /// output (DEC 2026), so tmux sends each redraw as one frame, and 24-bit colour, which tmux
    /// otherwise reduces to the 256-colour palette. SwiftTerm supports both.
    nonisolated static func arguments(session: String, directory: String) -> [String] {
        ["-u", "-T", "sync,RGB", "new-session", "-A", "-s", session, "-c", directory]
    }

    // MARK: Reopening after a quit

    /// macOS restores no windows after a quit while "Close windows when quitting an application"
    /// is on — its default — so a tab kept in tmux would never come back to its session. The app
    /// notes those windows as it quits, and opens them again at the next launch (2026-10-07).
    static let reopenKey = "macLocalTmuxWindowsToReopen"

    /// The windows on screen, as `MacWorkspacePreviewRegistry` knows them: the controller each one
    /// shows, never a copy that no window shows.
    @MainActor static func rememberWindowsToReopen(defaults: UserDefaults = .standard,
                                                   registry: MacWorkspacePreviewRegistry = .shared) {
        let ids = registry.shownControllers
            .filter { $0.tabs.contains(where: \.hasLocalTerminalsInTmux) }
            .map(\.windowID.uuidString)
        if ids.isEmpty { defaults.removeObject(forKey: reopenKey) } else { defaults.set(ids, forKey: reopenKey) }
    }

    /// The windows to open again, once. None when macOS restores windows itself
    /// (`NSQuitAlwaysKeepsWindows`), none already open, and none whose tabs are no longer saved.
    /// "Already open" includes a window whose controller is made but whose window is not yet
    /// found, so a window macOS is restoring is never opened a second time with the same id.
    @MainActor static func takeWindowsToReopen(defaults: UserDefaults = .standard,
                                               open openWindowIDs: Set<UUID>? = nil) -> [UUID] {
        guard let ids = defaults.stringArray(forKey: reopenKey) else { return [] }
        defaults.removeObject(forKey: reopenKey)
        guard !defaults.bool(forKey: "NSQuitAlwaysKeepsWindows") else { return [] }
        let open = openWindowIDs ?? MacWorkspacePreviewRegistry.shared.openWindowIDs
        return ids.compactMap(UUID.init(uuidString:)).filter {
            !open.contains($0) && MacWorkspaceWindowController.hasSavedState(windowID: $0, defaults: defaults)
        }
    }

    /// Runs tmux and returns what it printed, or nil when it failed. `posix_spawn` and `waitpid`
    /// rather than `Process`: `waitUntilExit` spins the caller's run loop, and these queries run
    /// on the main thread while a tab is being set up. tmux answers in milliseconds.
    nonisolated static func run(_ executable: String, _ arguments: [String],
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        var output: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { return nil }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addclose(&actions, output[0])
        posix_spawn_file_actions_addclose(&actions, output[1])
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let envp = spawnEnvironment(environment).map { strdup($0) } + [nil]
        defer { envp.forEach { free($0) } }
        let spawned = posix_spawn(&pid, executable, &actions, nil, argv, envp)
        close(output[1])
        let reader = FileHandle(fileDescriptor: output[0], closeOnDealloc: true)
        guard spawned == 0 else { return nil }
        let data = reader.readDataToEndOfFile()
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        return status == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    /// The app's environment with a UTF-8 locale when it has none — the app is started by launchd,
    /// which sets none, and tmux then answered with `_` for every tab (2026-10-08). The same rule
    /// as a local pane's (`MacLocalTerminalConfiguration.environment`); `-u` covers tmux itself.
    nonisolated static func spawnEnvironment(_ environment: [String: String]) -> [String] {
        var environment = environment
        if environment["LANG"] == nil, environment["LC_ALL"] == nil, environment["LC_CTYPE"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment.map { "\($0.key)=\($0.value)" }.sorted()
    }
}
#endif
