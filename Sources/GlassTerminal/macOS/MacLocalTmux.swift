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
import AppKit
import Foundation
import GlassTerminalEmulator
import os

enum MacLocalTmux {
    private nonisolated static let logger = Logger(subsystem: "sh.glas", category: "local-tmux")

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
        /// A session's history and screen as `capture-pane` prints them, for Select All; nil when
        /// it could not be read (`TerminalTmux.historyArguments`).
        var history: @Sendable (_ name: String, _ tmux: String) -> String? = { _, _ in nil }
        /// Makes a session under the first free name of `candidates`, as the pane would have:
        /// the answer `TerminalTmux.parseClaim` reads, as `TerminalTmux.claimScript` prints it;
        /// nil when no session was made. Stand-ins that leave it out could not run it.
        var claim: @Sendable (_ candidates: [String], _ launch: Launch, _ tmux: String) -> String? = { _, _, _ in nil }
        /// Gives a session the name its tab was given, or takes it away with nil (W6).
        var setGivenName: @Sendable (_ session: String, _ name: String?, _ tmux: String) -> Void = { _, _, _ in }
        /// What every session's active pane shows, by session, in one run of tmux
        /// (`MacLocalTmux.contexts`, W19); nil when it could not be read.
        var contexts: @Sendable (_ tmux: String) -> [String: MacWorkspacePaneContext]? = { _ in nil }
        /// Keeps on a session the repository and branch its tab found, or takes them away (W11).
        var setRepository: @Sendable (_ session: String, _ repository: TerminalRepository?, _ tmux: String) -> Void = { _, _, _ in }
        /// The repository a session's folder is in, read from the files (W11). Stand-ins that
        /// leave it out read none, so a listing's folders on the test machine change nothing.
        var readRepository: @Sendable (_ folder: String, _ home: String?) -> TerminalRepository? = { _, _ in nil }
        /// Has the server run where no app's Force Quit can end it (`MacTmuxService`) before a pane
        /// attaches. Stand-ins leave it out: a test never starts, stops or asks this Mac's server.
        var ensureRunning: @Sendable (_ tmux: String, _ environment: [String: String]) -> Void = { _, _ in }
        /// Ends the server and every session in it (Settings ▸ Terminal). Stand-ins: nothing.
        var endServer: @Sendable (_ tmux: String) -> Void = { _ in }

        nonisolated static let live = Server(
            executablePath: { MacLocalTmux.executablePath() },
            listSessions: { MacLocalTmux.run("/bin/sh", ["-c", TerminalTmux.listScript(tmux: TerminalTmux.quoted($0))]) },
            kill: { MacLocalTmux.kill($0, tmux: $1) },
            detachClients: { MacLocalTmux.detachClients($0, tmux: $1) },
            scroll: { name, lines, tmux in
                guard let arguments = MacLocalTmux.scrollArguments(session: name, lines: lines) else { return }
                // One queue, so a quick up-then-down arrives in that order.
                MacLocalTmux.scrollQueue.async { _ = MacLocalTmux.run(tmux, arguments) }
            },
            history: { name, tmux in MacLocalTmux.run(tmux, TerminalTmux.historyArguments(session: name)) },
            claim: { candidates, launch, tmux in
                // The server under launchd, so no app's Force Quit can end it (`MacTmuxService`).
                MacTmuxService.ensureDefaultServer(tmux: tmux, environment: launch.environmentVariables)
                return MacLocalTmux.claim(candidates, launch: launch, tmux: tmux)
            },
            setGivenName: { session, name, tmux in
                guard let arguments = TerminalTmux.givenNameArguments(session: session, name: name) else { return }
                // Argv, never a shell: the name is whatever someone typed.
                if MacLocalTmux.run(tmux, arguments) == nil {
                    MacLocalTmux.logger.notice("tmux would not keep the name given to session \(session, privacy: .public)")
                }
            },
            contexts: { MacLocalTmux.contexts(tmux: $0) },
            setRepository: { session, repository, tmux in
                guard let arguments = TerminalTmux.repositoryArguments(session: session, repository: repository) else { return }
                // Argv, never a shell: a folder's name can be anything.
                if MacLocalTmux.run(tmux, arguments) == nil {
                    MacLocalTmux.logger.notice("tmux would not keep the repository of session \(session, privacy: .public)")
                }
            },
            readRepository: { TerminalRepository.read(folder: $0, home: $1) },
            ensureRunning: { MacTmuxService.ensureDefaultServer(tmux: $0, environment: $1) },
            endServer: { MacTmuxService.stopDefaultServer(tmux: $0) }
        )
    }

    /// What a local pane's session starts with: its folder, the shell someone chose (tmux runs the
    /// login shell otherwise) and the pane's environment (`MacLocalTerminalConfiguration`). The
    /// claim that makes the session needs all three: the pane's own `new-session -A` ignores them
    /// for a session that exists, and a claim that starts the tmux server gives it its environment.
    nonisolated struct Launch: Equatable, Sendable {
        var directory: String
        var command: [String]
        /// `NAME=value`, as a process is given them.
        var environment: [String]

        nonisolated var environmentVariables: [String: String] {
            Dictionary(environment.compactMap { entry -> (String, String)? in
                guard let equals = entry.firstIndex(of: "=") else { return nil }
                return (String(entry[..<equals]), String(entry[entry.index(after: equals)...]))
            }, uniquingKeysWith: { _, last in last })
        }
    }

    @MainActor static var server = Server.live

    /// The reads that tell every local tab in tmux what its sessions show (W19). Tests put their
    /// own here, with no interval.
    @MainActor static var contextReads = MacLocalTmuxContextReads()

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

    /// Names a pane in this process holds — claimed, restored from a saved tab, or opened from
    /// Active — so another pane is never given one, though it may not be running yet.
    @MainActor private static var reserved: Set<String> = []

    /// A pane keeps `name`: no other pane here is given it.
    @MainActor static func reserve(_ name: String) {
        reserved.insert(name)
    }

    /// A new session on this Mac's tmux server, made by a claim (`TerminalTmux.claimScript`)
    /// with the pane's folder, shell and environment. The lowest free `glass-N` when the
    /// sessions read, numbers far above those in use when they do not; a name taken after the
    /// list was read is skipped, never joined. When the claim cannot run, a number nothing is
    /// likely to hold, which the pane's `new-session -A` makes.
    /// - Parameter held: names to leave alone though nothing runs them — W4b: workgroups'.
    @MainActor static func allocateName(tmux: String, launch: Launch, avoiding held: Set<String> = []) -> String {
        let taken = reserved.union(held)
        let candidates = listing(tmux: tmux).map { TerminalTmux.claimCandidates(avoiding: taken.union($0.map(\.name))) }
            ?? TerminalTmux.unlistedCandidates(avoiding: taken)
        let name: String
        if case .created(let created)? = server.claim(candidates, launch, tmux)
            .map({ TerminalTmux.parseClaim($0, candidates: candidates) }) {
            name = created
        } else {
            logger.error("This Mac's tmux would not make a session; the pane will start one itself")
            name = TerminalTmux.unlistedName(avoiding: taken.union(candidates))
        }
        reserved.insert(name)
        return name
    }

    /// A claim on this Mac (`TerminalTmux.claimScript`'s, which a host runs through `sh`), as
    /// argv: no shell stands between Glass and this Mac's tmux, so the pane's folder — whatever
    /// folder a terminal was in, by whatever name (W37) — reaches `new-session -c` exactly as it
    /// is, as one argument. `new-session -d` refuses a name already running; `has-session` then
    /// tells a taken name (try the next) from tmux failing (stop). Answers as the script prints:
    /// `created NAME`, or `exists NAME` for one candidate already running; nil when no session
    /// was made.
    /// - Parameters:
    ///   - serverArguments: tests only — a private server (`-S socket`), never a real one.
    ///   - run: tests only — what runs tmux, and with which environment.
    nonisolated static func claim(
        _ candidates: [String], launch: Launch, tmux: String, serverArguments: [String] = [],
        run: (_ executable: String, _ arguments: [String], _ environment: [String: String]) -> String?
            = { MacLocalTmux.run($0, $1, environment: $2) }
    ) -> String? {
        let tmuxArguments = ["-u"] + serverArguments
        let environment = launch.environmentVariables
        for name in candidates.prefix(TerminalTmux.claimLimit) {
            let create = tmuxArguments + ["new-session", "-d", "-s", name, "-c", launch.directory] + launch.command
            if run(tmux, create, environment) != nil { return "created \(name)\n" }
            guard run(tmux, tmuxArguments + ["has-session", "-t", "=" + name], environment) != nil else {
                logger.error("This Mac's tmux would not make session \(name, privacy: .public), and has none by that name")
                return nil
            }
            if candidates.count == 1 { return "exists \(name)\n" }
        }
        return nil
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

    /// What Active lists under This Mac: every session, Glass's own first by number, as for any
    /// other machine. Those a tab here shows are listed too, as open here, and Open brings that
    /// tab forward (W6): left out, fourteen running tabs made an empty This Mac, and the same
    /// sessions reached over SSH read "Open elsewhere" (2026-10-08).
    @MainActor static func listable(_ sessions: [TerminalTmux.Session]) -> [TerminalTmux.Session] {
        sessions.sorted { (TerminalTmux.glassNumber($0.name) ?? .max, $0.name) < (TerminalTmux.glassNumber($1.name) ?? .max, $1.name) }
    }

    /// How many panes here show `name`: open here when one does.
    @MainActor static func shownCount(_ name: String) -> Int { shownHere[name, default: 0] }

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

    /// What the session's active pane shows: the directory its shell is in, and the title a
    /// program set. tmux keeps both from the terminal outside it, so a tab in tmux asks. Also the
    /// name a tab gave the session (W6), which a tab attaching to it takes.
    nonisolated static func context(session: String, tmux: String,
                                    environment: [String: String] = ProcessInfo.processInfo.environment) -> MacWorkspacePaneContext? {
        run(tmux, ["-u", "display-message", "-p", "-t", "=" + session + ":", contextFormat],
            environment: environment).flatMap(parseContext)
    }

    /// What every session's active pane shows, by session name, from one run of tmux (W19): each
    /// session's name, then what `context` asks one session for. One run answers every tab of
    /// every window; asking per session ran tmux once for each pane. Nil when tmux could not be
    /// asked — no server running included.
    nonisolated static func contexts(tmux: String,
                                     environment: [String: String] = ProcessInfo.processInfo.environment)
        -> [String: MacWorkspacePaneContext]? {
        run(tmux, ["-u", "list-sessions", "-F", contextsFormat], environment: environment).map(parseContexts)
    }

    /// A session's name, then `contextFormat`: pane variables in a session's line are its active
    /// pane's, as `display-message -t =name:` answers them.
    nonisolated static let contextsFormat = "#{session_name}\t" + contextFormat

    /// Reads `contextsFormat` lines. A line that does not read is left out.
    nonisolated static func parseContexts(_ output: String) -> [String: MacWorkspacePaneContext] {
        var contexts: [String: MacWorkspacePaneContext] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, !fields[0].isEmpty, contexts[String(fields[0])] == nil,
                  let context = parseContext(String(fields[1])) else { continue }
            contexts[String(fields[0])] = context
        }
        return contexts
    }

    /// The title last, so that it may hold anything. The same a terminal on any device asks a
    /// host with (`TerminalTmux.paneStateCommand`, W11).
    nonisolated static let contextFormat = TerminalTmux.contextFormat

    /// tmux titles a pane with the host name until a program sets one; that is not a title.
    nonisolated static func parseContext(_ output: String) -> MacWorkspacePaneContext? {
        TerminalTmux.parseContext(output).map {
            MacWorkspacePaneContext(title: $0.title, directory: $0.directory, givenName: $0.givenName,
                                    program: $0.program,
                                    programArguments: foregroundArguments(program: $0.program, shell: $0.shellProcessID))
        }
    }

    /// For a program tmux names too plainly — an interpreter (`node`), or a file named for its
    /// version (Claude Code's `2.1.296`) — how it was run, from this Mac's process table. Not read
    /// for any other program, nor kept beyond the words that say which
    /// (`TerminalAgent.identifyingWords`).
    nonisolated static func foregroundArguments(program: String?, shell: Int32?) -> String? {
        guard let program, TerminalAgent.needsCommandLine(program),
              let shell, let group = TerminalProcessTable.foregroundGroup(ofShell: shell),
              let commandLine = TerminalProcessTable.commandLine(of: group) else { return nil }
        return TerminalAgent.identifyingWords(commandLine)
    }

    /// Gives a session the name its tab was given, or takes it away (W6). Off the main thread,
    /// on one queue, so a rename and its undo arrive in that order.
    @MainActor static func shareGivenName(_ name: String?, session: String) {
        let server = server
        guard let tmux = server.executablePath() else { return }
        nameQueue.async { server.setGivenName(session, name, tmux) }
    }

    nonisolated static let nameQueue = DispatchQueue(label: "GlassPowerTools.local-tmux-name", qos: .utility)

    /// Keeps on a session the repository and branch its tab found (W11), so Active on another
    /// device says them. On the name's queue, so changes arrive in the order they were made.
    @MainActor static func shareRepository(_ repository: TerminalRepository?, session: String) {
        let server = server
        guard let tmux = server.executablePath() else { return }
        nameQueue.async { server.setRepository(session, repository, tmux) }
    }

    /// The sessions with the repository each one's folder is in, read from the files: on this Mac
    /// the folder is the truth, where a session's options say only what a tab last saw (W11).
    /// A session whose folder is not known keeps what its options say. Off the main actor.
    nonisolated static func readingRepositories(_ sessions: [TerminalTmux.Session], home: String?,
                                                read: @Sendable (_ folder: String, _ home: String?) -> TerminalRepository?)
        -> [TerminalTmux.Session] {
        sessions.map { listed in
            guard let directory = listed.directory else { return listed }
            var session = listed
            session.repository = read(directory, home)
            return session
        }
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
    ///
    /// As a control-mode client (`-C` on pipes, D83: `TmuxControlPipe`) tmux hands the pane's every
    /// byte to the terminal, which draws it itself, so the terminal's features don't pass through tmux
    /// and `-T` has nothing to say.
    nonisolated static func arguments(session: String, directory: String, control: Bool = false) -> [String] {
        control ? ["-u", "-C", "new-session", "-A", "-s", session, "-c", directory]
            : ["-u", "-T", "sync,RGB", "new-session", "-A", "-s", session, "-c", directory]
    }

    /// Whether this Mac's tmux can have a control-mode client (3.2 or later): asked once a run, for
    /// each tmux, and only while the setting allows control mode.
    nonisolated static func supportsControlMode(_ tmux: String) -> Bool {
        guard TerminalTmux.controlModeEnabled else { return false }
        return controlModeSupport.withLock { known in
            if let answer = known[tmux] { return answer }
            let answer = TmuxControlClient.supports(version: run(tmux, ["-V"]) ?? "")
            known[tmux] = answer
            return answer
        }
    }

    private nonisolated static let controlModeSupport = OSAllocatedUnfairLock(initialState: [String: Bool]())

    // MARK: Reopening after a quit or a crash

    /// macOS restores none of these windows (D54), so a tab kept in tmux would never come back to
    /// its session without this list: the windows to open again at the next launch (2026-10-07).
    /// SSH terminals in tmux count too (W4b): their panes keep their sessions' names, so a window
    /// of SSH tabs comes back attached to the same sessions rather than not at all. Only the app
    /// writes it, and it keeps it current while it runs (`MacWindowsToReopen`, W12): a list
    /// written from outside raced with the app's own (2026-10-09).
    static let reopenKey = "macLocalTmuxWindowsToReopen"

    /// The windows on screen, as `MacWorkspacePreviewRegistry` knows them — the controller each
    /// one shows, never a copy that no window shows — that hold terminals in tmux; then `opening`,
    /// windows of the last run asked to open and not on screen yet. Written only when it changes;
    /// true when it did.
    @MainActor @discardableResult
    static func rememberWindowsToReopen(defaults: UserDefaults = .standard,
                                        registry: MacWorkspacePreviewRegistry = .shared,
                                        opening: [UUID] = []) -> Bool {
        let shown = registry.shownControllers.filter(reopensOnTmux).map(\.windowID)
        let ids = (shown + opening.filter { !shown.contains($0) }).map(\.uuidString)
        if ids.isEmpty {
            guard defaults.object(forKey: reopenKey) != nil else { return false }
            defaults.removeObject(forKey: reopenKey)
        } else {
            guard defaults.stringArray(forKey: reopenKey) != ids else { return false }
            defaults.set(ids, forKey: reopenKey)
        }
        return true
    }

    /// A window to open again: a tab of it shows a terminal in tmux, or names a tmux session to
    /// attach to. Names count because the list is kept while the app runs (W12): a window is
    /// found before its panes start, and an SSH terminal claims its session after it connects.
    @MainActor static func reopensOnTmux(_ window: MacWorkspaceWindowController) -> Bool {
        window.tabs.contains { tab in
            tab.hasTerminalsInTmux || (tab.state.root?.panes ?? []).contains { tmuxSession(of: $0) != nil }
        }
    }

    /// A tmux session as a pane names it: this Mac's (`serverID` nil), or one on a host.
    struct TmuxSessionKey: Hashable {
        let serverID: UUID?
        let name: String
    }

    static func tmuxSession(of pane: MacWorkspacePane) -> TmuxSessionKey? {
        if let name = pane.intent.localTmuxSession { return TmuxSessionKey(serverID: nil, name: name) }
        if let name = pane.intent.sshTmuxSession { return TmuxSessionKey(serverID: pane.intent.serverID, name: name) }
        return nil
    }

    /// The tmux sessions panes here show or are about to: every pane of every terminal window on
    /// screen or opening, and every session a local pane is attached to.
    @MainActor static func sessionsShown(registry: MacWorkspacePreviewRegistry) -> Set<TmuxSessionKey> {
        let windows = registry.shownControllers + registry.openWindowIDs.flatMap { registry.controllers(windowID: $0) }
        let named = windows.flatMap(\.tabs).flatMap { $0.state.root?.panes ?? [] }.compactMap(tmuxSession(of:))
        return Set(named).union(shownHere.keys.map { TmuxSessionKey(serverID: nil, name: $0) })
    }

    /// Of `windows`, in order, those that bring something of their own: never a window whose
    /// every tab holds only tmux sessions that panes here already show, or that a window before
    /// it in the list brings. Opened, such a window was a window of panes refused as already open
    /// (`claimShown`) — many empty windows, from a list left behind (2026-10-09).
    @MainActor static func withoutDuplicates(_ windows: [UUID], shown: Set<TmuxSessionKey>,
                                             defaults: UserDefaults) -> [UUID] {
        var claimed = shown
        return windows.filter { windowID in
            guard case .restored(let saved) = MacWorkspaceWindowController.load(windowID: windowID, defaults: defaults) else {
                return true
            }
            // Per tab, the sessions it holds; nil when it shows anything else — a plain shell, an
            // empty tab, or a layout that can't be read, which says so.
            let tabs = saved.tabs.map { tab -> Set<TmuxSessionKey>? in
                guard let panes = MacWorkspaceController.savedPanes(workspaceID: tab.id, defaults: defaults),
                      !panes.isEmpty else { return nil }
                let sessions = panes.compactMap(tmuxSession(of:))
                return sessions.count == panes.count ? Set(sessions) : nil
            }
            let duplicate = tabs.allSatisfy { $0.map { $0.isSubset(of: claimed) } ?? false }
            if !duplicate { for case let sessions? in tabs { claimed.formUnion(sessions) } }
            return !duplicate
        }
    }

    /// The windows to open again, taken from the list: none already open, and none whose tabs are
    /// no longer saved. "Already open" includes a window whose controller is made but whose
    /// window is not yet found, so a window is never opened a second time with the same id.
    /// `MacWindowsToReopen.takeOnce` is the one caller in the app, once per launch.
    @MainActor static func takeWindowsToReopen(defaults: UserDefaults = .standard,
                                               open openWindowIDs: Set<UUID>? = nil) -> [UUID] {
        guard let ids = defaults.stringArray(forKey: reopenKey) else {
            logger.notice("Reopen: no windows listed")
            return []
        }
        defaults.removeObject(forKey: reopenKey)
        let open = openWindowIDs ?? MacWorkspacePreviewRegistry.shared.openWindowIDs
        let listed = ids.compactMap(UUID.init(uuidString:))
        let alreadyOpen = listed.filter(open.contains)
        let unsaved = listed.filter { !open.contains($0) && !MacWorkspaceWindowController.hasSavedState(windowID: $0, defaults: defaults) }
        let reopening = listed.filter { !open.contains($0) && !unsaved.contains($0) }
        logger.notice("Reopen: \(listed.count) listed, \(alreadyOpen.count) already open, \(unsaved.count) not saved, \(reopening.count) reopening")
        return reopening
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
        // Nothing else of the app's: a claim can start the tmux server, which keeps whatever its
        // first client inherited for as long as it runs — another run's pipe, or a pane's terminal,
        // or the signals the calling thread blocks (`GlassSpawn`). Reads and End run off the main thread.
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        GlassSpawn.prepare(&attributes)
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let envp = spawnEnvironment(environment).map { strdup($0) } + [nil]
        defer { envp.forEach { free($0) } }
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
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

// MARK: What every local tab shows, read together (W19)

/// A local tab in tmux learns what its sessions show — the title a program set, the folder, the
/// name a tab on any device gave the session — by asking this Mac's tmux, since tmux keeps all
/// three from the terminal outside it. A tab asks when output in it comes to rest, which is also
/// just after it attaches. Each read answers every tab that has asked, in one run of tmux
/// (`MacLocalTmux.Server.contexts`): fifteen tabs settling together are one read, not fifteen,
/// and a tab with nothing printing still hears of a name given on another device when any other
/// tab's output settles. At most one read an interval; asked within it, one more at its end.
/// Nothing is read while every terminal is quiet. On the names' queue, so a name given here
/// reaches tmux before the next read asks for it.
@MainActor
final class MacLocalTmuxContextReads {
    /// The least time between two reads.
    let interval: Duration
    /// How many reads ran, for tests.
    private(set) var reads = 0
    /// How many reads' answers have been handed to their tabs, for tests: a test that a stale read
    /// is not taken over a newer name waits for this rather than for a guess at how long it takes.
    private(set) var applied = 0

    private final class Asker {
        weak var tab: MacWorkspaceController?
        init(_ tab: MacWorkspaceController) { self.tab = tab }
    }
    /// The tabs answered by every read: those that have asked, held weakly, until they close.
    private var askers: [ObjectIdentifier: Asker] = [:]
    private var wanted = false
    private var running: Task<Void, Never>?
    private var lastReadAt: ContinuousClock.Instant?

    init(interval: Duration = .seconds(2)) {
        self.interval = interval
    }

    /// `tab` wants to know what its sessions show: read now, or at the end of the interval.
    func ask(_ tab: MacWorkspaceController) {
        askers[ObjectIdentifier(tab)] = Asker(tab)
        wanted = true
        guard running == nil else { return }
        running = Task { [weak self] in await self?.readWhileWanted() }
    }

    private func readWhileWanted() async {
        defer { running = nil }
        while wanted {
            if let last = lastReadAt, ContinuousClock.now < last + interval {
                try? await Task.sleep(until: last + interval, clock: .continuous)
            }
            // This read answers every ask so far; one after it starts asks again.
            wanted = false
            askers = askers.filter { $0.value.tab.map { !$0.isClosed } ?? false }
            let tabs = askers.values.compactMap(\.tab)
            let server = MacLocalTmux.server
            guard !tabs.isEmpty, let tmux = server.executablePath() else { continue }
            // A name given in a tab after this point is not taken back from this read.
            let generations = tabs.map(\.givenNameGeneration)
            lastReadAt = .now
            reads += 1
            let contexts = await withCheckedContinuation { continuation in
                MacLocalTmux.nameQueue.async { continuation.resume(returning: server.contexts(tmux)) }
            }
            guard let contexts else { continue }
            for (tab, generation) in zip(tabs, generations) {
                tab.applyLocalTmuxContexts(contexts, askedAt: generation)
            }
            applied += 1
        }
    }
}

// MARK: The list, for the whole run (W12)

/// The windows to open at the next launch (D47), owned for the whole run. The first window of a
/// launch — Connections or a terminal window, whichever appears first — takes the last run's
/// list, once per process: the Connections window's own task ran each time its content appeared
/// and applied whatever list it found (2026-10-09). From then on the list is kept current as
/// windows open and close and their tabs are saved, so a crash or a forced quit brings back the
/// same windows. Quitting writes it once more, and the windows closing for the quit leave it alone.
final class MacWindowsToReopen: NSObject {
    static let shared = MacWindowsToReopen()
    private nonisolated static let logger = Logger(subsystem: "sh.glas", category: "local-tmux")

    private let defaults: UserDefaults
    private let registry: MacWorkspacePreviewRegistry
    /// This run has taken the last run's list: from then on, this run's windows are the list.
    private(set) var hasTaken = false
    /// Windows of the last run asked to open and not on screen yet, kept in the list until they
    /// are, so a crash before they appear loses none.
    private var opening: [UUID] = []
    /// Set as the app quits. Windows closing after it are closing for the quit, not by hand.
    private(set) var isQuitting = false

    init(defaults: UserDefaults = .standard, registry: MacWorkspacePreviewRegistry = .shared) {
        self.defaults = defaults
        self.registry = registry
        super.init()
        registry.windowsChanged = { [weak self] in self?.update() }
        NotificationCenter.default.addObserver(self, selector: #selector(recordSaved(_:)),
                                               name: .macWorkspaceRecordSaved, object: defaults)
    }

    /// The windows the last run left, for whichever window of this launch asks first; nil for
    /// every other. None already open, none whose tabs are no longer saved, and none whose every
    /// tab holds only sessions already shown.
    func takeOnce(askedBy asker: String) -> [UUID]? {
        guard !hasTaken else {
            Self.logger.notice("Reopen: asked by \(asker, privacy: .public), already taken at this launch")
            return nil
        }
        hasTaken = true
        Self.logger.notice("Reopen: asked by \(asker, privacy: .public)")
        let candidates = MacLocalTmux.takeWindowsToReopen(defaults: defaults, open: registry.openWindowIDs)
        let reopening = MacLocalTmux.withoutDuplicates(candidates, shown: MacLocalTmux.sessionsShown(registry: registry),
                                                       defaults: defaults)
        if reopening.count < candidates.count {
            Self.logger.notice("Reopen: \(candidates.count - reopening.count) left closed, every tab's sessions already shown")
        }
        opening = reopening
        write()
        return reopening
    }

    /// A window opened or closed, or a tab or window record was saved: the list as it is now.
    /// Nothing before the last run's list is taken — it is still that run's — and nothing while
    /// quitting.
    func update() {
        guard hasTaken, !isQuitting else { return }
        write()
    }

    /// Quitting, before the windows let go of their terminals: where each window is, and which to
    /// open again. Closing them for the quit then changes neither. When no window appeared in this
    /// run, nothing took the last run's list, and it stands.
    func prepareForQuit(displayOf: @MainActor (NSWindow) -> MacWorkspaceDisplay? = MacWorkspaceDisplay.of) {
        MacWorkspaceWindowPlacement.saveAll(registry: registry, displayOf: displayOf)
        if hasTaken { write() }
        isQuitting = true
        let listed = defaults.stringArray(forKey: MacLocalTmux.reopenKey)?.count ?? 0
        Self.logger.notice("Reopen: quitting with \(listed) windows listed")
    }

    @objc private func recordSaved(_ notification: Notification) {
        update()
    }

    private func write() {
        opening.removeAll { registry.shownController(windowID: $0) != nil }
        if MacLocalTmux.rememberWindowsToReopen(defaults: defaults, registry: registry, opening: opening) {
            let listed = defaults.stringArray(forKey: MacLocalTmux.reopenKey)?.count ?? 0
            Self.logger.notice("Reopen: \(listed) windows listed now")
        }
    }
}

// MARK: Find (2026-10-08)

extension MacLocalTmux {
    /// One step of the find bar in tmux's own search, as argv: enter copy mode, search, and print
    /// where the search landed, in one run. `-u` first, as in every tmux command Glass builds.
    /// `end` leaves copy mode, so typing reaches the shell again.
    nonisolated static func findArguments(session: String, request: TerminalTmuxFindRequest) -> [String] {
        let target = "=" + session + ":"
        switch request {
        case .search(let term, let direction):
            return ["-u", "copy-mode", "-t", target, ";",
                    "send-keys", "-t", target, "-X", TerminalTmuxFind.searchCommand(direction),
                    "--", TerminalTmuxFind.argument(term), ";",
                    "display", "-p", "-t", target, TerminalTmuxFind.replyFormat]
        case .end:
            return ["-u", "send-keys", "-t", target, "-X", "cancel"]
        }
    }
}
#endif
