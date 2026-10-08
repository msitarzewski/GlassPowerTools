//
//  TerminalTmux.swift
//  Glass Power Tools — GlassTerminal
//
//  D44 (2026-10-01): a terminal that outlives the device. With the server's tmux setting on, each
//  terminal is its own tmux session — `glass-1`, `glass-2` — so a suspended app, a dropped network
//  or a closed lid leaves the work running on the host, and any device can attach to it again.
//
//  Everything here is text: the commands Glass sends and the parsing of what tmux answers. The
//  terminal still opens the ordinary PTY shell; the attach line is typed into it, the way a
//  workgroup's startup command is, because the PTY channel only ever asks for a shell.
//
//  **Every command goes through `sh -c`.** An exec channel runs the user's login shell, and fish
//  does not read `{ …; }` or `2>/dev/null ||` chains the way sh does. The typed attach line is the
//  one exception — it is typed into whatever shell the host gives — so it sticks to syntax bash,
//  zsh and fish all share: `command -v`, `&&`, `exec`, single quotes.
//
//  **Every tmux runs with `-u`.** Without a UTF-8 locale tmux prints the tabs in its `-F` answers
//  as `_`, and an SSH command on a Mac has no locale: every listing read as "no sessions", so a
//  new terminal took `glass-1` and joined the one running there (2026-10-08 — the iPhone and the
//  Vision Pro, connecting to a Mac). `-u` says the terminal is UTF-8 whatever the locale.
//

import Foundation

enum TerminalTmux {
    /// The prefix of the sessions Glass names. Sessions with other names are the user's own.
    nonisolated static let namePrefix = "glass-"

    /// One tmux session on a host.
    struct Session: Equatable, Sendable, Identifiable {
        var name: String
        /// Clients attached right now, on any device.
        var attachedClients: Int
        var windows: Int
        var lastActivity: Date?
        /// The tmux server running it: the same for every session of one listing (W6).
        var server: Server? = nil
        /// The name a tab gave it (`@glass-name`), held to what a tab can show.
        var givenName: String? = nil
        /// What its active pane shows: the title a program set (never tmux's default, the host
        /// name), the folder it is in, and the program in front.
        var title: String? = nil
        var directory: String? = nil
        var command: String? = nil
        /// The home folder of the account that listed it, so a folder is named as a tab names it.
        var home: String? = nil
        var id: String { name }
        var isGlass: Bool { TerminalTmux.glassNumber(name) != nil }

        /// What Active and a tab showing it call it (`TerminalSessionNaming`).
        var displayName: String {
            TerminalSessionNaming.name(given: givenName, title: title, directory: directory, home: home, session: name)
        }
    }

    /// One tmux server, told apart from every other by its process, when it started and its
    /// socket. Two listings naming the same server list the same sessions however they were
    /// reached — this Mac's own, and this Mac reached over SSH as a host in the library (W6).
    struct Server: Equatable, Hashable, Sendable {
        var pid: Int
        var startTime: Int
        var socketPath: String
    }

    enum Listing: Equatable, Sendable {
        /// tmux is not installed on the host.
        case unavailable
        /// tmux is there; an empty list when no server is running.
        case sessions([Session])
        /// tmux answered with something other than a list — an error, or lines that do not read as
        /// sessions. Never "no sessions": a name chosen from it could be one already running.
        case failed
    }

    private nonisolated static let missingMarker = "__glass_no_tmux__"
    private nonisolated static let failedMarker = "__glass_tmux_failed__"
    /// Starts the line after a listing that says whose home the listing ran in: `sh` knows it, and
    /// tmux formats cannot read the environment.
    private nonisolated static let homeMarker = "__glass_home__"

    /// The user option a session's given name is kept in (W6): set when its tab is renamed, read
    /// by every device's Active and by a tab attaching to it.
    nonisolated static let givenNameOption = "@glass-name"

    /// What `list-sessions` prints for each session, read by `parse`: name, attached clients,
    /// windows, last activity; then (W6) the server's pid, start time and socket, the active pane's
    /// program, the host's names (tmux's default pane title), the session's given name, the
    /// pane's folder, and last its title. Pane variables in a session's line are its active pane's.
    /// The title is last so that it may hold anything: `parse` splits a bounded number of times.
    nonisolated static let listFormat = "#{session_name}\t#{session_attached}\t#{session_windows}\t#{session_activity}"
        + "\t#{pid}\t#{start_time}\t#{socket_path}\t#{pane_current_command}\t#{host}\t#{host_short}"
        + "\t#{\(givenNameOption)}\t#{pane_current_path}\t#{pane_title}"
    private nonisolated static let listFieldCount = 13

    /// A session name Glass will pass to tmux: tmux rejects `:` and `.` in names, a leading `-`
    /// would read as an option, and control characters have no business in a tab's record.
    nonisolated static func isValidSessionName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 128 && !name.hasPrefix("-")
            && !name.unicodeScalars.contains { $0 == ":" || $0 == "." || $0.properties.generalCategory == .control }
    }

    /// An exec channel's `sh -c` has the system PATH only, and a Mac's tmux is usually Homebrew's
    /// (D47: a Vision Pro reaching a Mac's local tmux sessions over SSH). Appended, so a tmux
    /// already on the PATH still wins.
    private nonisolated static let searchPath = #"PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; "#

    /// Lists the host's sessions, or says tmux is missing. Exits 0 either way: "no server running"
    /// is an empty list, not a failure.
    static var listCommand: String {
        "sh -c \(quoted(searchPath + listScript(tmux: "tmux")))"
    }

    /// The listing as an `sh` script, for the host's tmux or this Mac's (`tmux` is a word or a
    /// quoted path). Only tmux's own "no server" answers count as an empty list; any other
    /// failure says so, rather than reading as a host with nothing running. After the sessions,
    /// one line says whose home this is (W6).
    /// - Parameter serverArguments: tests only — a private server (`-S socket`), never a real one.
    nonisolated static func listScript(tmux: String, serverArguments: [String] = []) -> String {
        let run = ([tmux, "-u"] + serverArguments.map(quoted)).joined(separator: " ")
        return "command -v \(tmux) >/dev/null 2>&1 || { echo \(missingMarker); exit 0; }; "
            + "out=$(\(run) list-sessions -F '\(listFormat)' 2>/dev/null) && { printf '%s\\n' \"$out\"; "
            + "printf '\(homeMarker)\\t%s\\n' \"$HOME\"; exit 0; }; "
            + "case $(\(run) list-sessions 2>&1) in "
            + "*'no server running'*|*'error connecting to'*'No such file or directory'*|*'error connecting to'*'Connection refused'*) ;; "
            + "*) echo \(failedMarker) ;; esac; exit 0"
    }

    /// Reads a listing. The markers count only as whole lines: a program's title can say anything.
    /// Lines from an older format — four fields — still read, without what came later.
    static func parse(_ output: String) -> Listing {
        var home: String?
        var lines: [Substring] = []
        for line in output.split(whereSeparator: \.isNewline) where !line.allSatisfy(\.isWhitespace) {
            switch line.trimmingCharacters(in: .whitespaces) {
            case missingMarker: return .unavailable
            case failedMarker: return .failed
            default: break
            }
            if line.hasPrefix(homeMarker + "\t") {
                home = String(line.dropFirst(homeMarker.count + 1)).trimmingCharacters(in: .whitespaces)
            } else {
                lines.append(line)
            }
        }
        let sessions = lines.compactMap { session(from: $0, home: home?.hasPrefix("/") == true ? home : nil) }
        // Lines and not one session: tmux's tabs turned to `_`, or an answer from something else.
        return !lines.isEmpty && sessions.isEmpty ? .failed : .sessions(sessions)
    }

    private static func session(from line: Substring, home: String?) -> Session? {
        let fields = line.split(separator: "\t", maxSplits: listFieldCount - 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard fields.count >= 4, !fields[0].isEmpty else { return nil }
        var session = Session(name: fields[0],
                              attachedClients: Int(fields[1]) ?? 0,
                              windows: Int(fields[2]) ?? 1,
                              lastActivity: TimeInterval(fields[3]).map(Date.init(timeIntervalSince1970:)))
        guard fields.count == listFieldCount else { return session }
        if let pid = Int(fields[4]), let started = Int(fields[5]), !fields[6].isEmpty {
            session.server = Server(pid: pid, startTime: started, socketPath: fields[6])
        }
        session.command = fields[7].isEmpty ? nil : fields[7]
        session.givenName = TerminalSessionNaming.displayText(fields[10])
        session.directory = fields[11].hasPrefix("/") ? fields[11] : nil
        session.title = TerminalSessionNaming.programTitle(fields[12], hostNames: [fields[8], fields[9]])
        session.home = home
        return session
    }

    // MARK: A session's given name (W6, 2026-10-08)

    /// tmux's argv for giving a session the name its tab was given, or with nil taking it away:
    /// a session option, so every device's Active and any tab attaching to it see the name. Nil
    /// for a session name tmux could misread. The name is held to one line, as a tab's is; a
    /// trailing `;` is escaped, because tmux reads an argument ending in one as the end of a
    /// command (`build;` was stored as `build`, found live on tmux 3.7c).
    nonisolated static func givenNameArguments(session: String, name: String?) -> [String]? {
        guard isValidSessionName(session) else { return nil }
        let target = "=" + session + ":"
        guard var value = name.flatMap({ TerminalSessionNaming.displayText($0) }) else {
            return ["-u", "set-option", "-u", "-t", target, givenNameOption]
        }
        if value.hasSuffix(";") { value.insert("\\", at: value.index(before: value.endIndex)) }
        return ["-u", "set-option", "-t", target, givenNameOption, value]
    }

    /// The same, for a host: through `sh -c`, every word quoted, as every exec-channel command is.
    nonisolated static func givenNameCommand(session: String, name: String?) -> String? {
        givenNameArguments(session: session, name: name).map { arguments in
            "sh -c \(quoted(searchPath + "tmux " + arguments.map(quoted).joined(separator: " ")))"
        }
    }

    /// Asks a host for the name a session was given: the line it prints, empty when none.
    nonisolated static func givenNameQuery(session: String) -> String? {
        guard isValidSessionName(session) else { return nil }
        let arguments = ["-u", "display-message", "-p", "-t", "=" + session + ":", "#{\(givenNameOption)}"]
        return "sh -c \(quoted(searchPath + "tmux " + arguments.map(quoted).joined(separator: " ")))"
    }

    // MARK: Claiming a name (2026-10-08)
    //
    // A name chosen from a list and then attached with `new-session -A` joins whatever took that
    // name in between: two devices connecting together landed in one session. A claim makes the
    // session with `new-session -d`, which refuses a name already running, and tries the next
    // one; the host's tmux is the only arbiter. Attaching follows, and `-A` then joins the
    // session just made.

    /// What a claim answered.
    enum Claim: Equatable, Sendable {
        /// The session was made for this terminal: a startup command belongs in it.
        case created(String)
        /// The one name asked for is running already. It is joined, and nothing is typed into it.
        case exists(String)
        /// tmux is not installed.
        case unavailable
        /// tmux failed, every name was taken, or the answer did not read.
        case failed
    }

    /// The most names one claim tries: far more than terminals opening together, and a bound on
    /// a host that refuses them all.
    nonisolated static let claimLimit = 32

    /// The names a new session tries, in order: the lowest `glass-N`s not in `taken`.
    static func claimCandidates(avoiding taken: Set<String>, count: Int = claimLimit) -> [String] {
        var names: [String] = []
        var number = 1
        while names.count < count {
            let name = "\(namePrefix)\(number)"
            if !taken.contains(name) { names.append(name) }
            number += 1
        }
        return names
    }

    /// The names to try when the sessions could not be read: numbers far above those in use.
    static func unlistedCandidates(avoiding taken: Set<String>, count: Int = claimLimit,
                                   random: () -> Int = { Int.random(in: 100...9_999) }) -> [String] {
        var names: [String] = []
        while names.count < count { names.append(unlistedName(avoiding: taken.union(names), random: random)) }
        return names
    }

    /// The claim for a host, through `sh -c` like every exec-channel command.
    static func claimCommand(candidates: [String]) -> String {
        "sh -c \(quoted(searchPath + claimScript(candidates: candidates, tmux: "tmux")))"
    }

    /// Makes a session under the first of `candidates` that nothing holds, as an `sh` script.
    /// `new-session -d` fails on a name already running; `has-session` then tells a taken name
    /// (try the next) from tmux failing (stop). Prints `created NAME`, or for a single candidate
    /// already running `exists NAME`; otherwise the failure marker, or the missing-tmux one.
    /// - Parameters:
    ///   - directory: the session's first folder; nil leaves it to tmux — where the claim runs.
    ///   - command: what the session runs in place of the login shell, one word each.
    ///   - tmux: a word or a quoted path, as for `listScript`.
    ///   - serverArguments: tests only — a private server (`-S socket`), never a real one.
    nonisolated static func claimScript(candidates: [String], directory: String? = nil, command: [String] = [],
                                        tmux: String, serverArguments: [String] = []) -> String {
        let run = ([tmux, "-u"] + serverArguments.map(quoted)).joined(separator: " ")
        let creates = (directory.map { ["-c", quoted($0)] } ?? []) + command.map(quoted)
        let onTaken = candidates.count == 1 ? #"echo "exists $c"; exit 0"# : "continue"
        return "command -v \(tmux) >/dev/null 2>&1 || { echo \(missingMarker); exit 0; }; "
            + "for c in \(candidates.prefix(claimLimit).map(quoted).joined(separator: " ")); do "
            + (["\(run) new-session -d -s \"$c\""] + creates).joined(separator: " ")
            + #" </dev/null >/dev/null 2>&1 && { echo "created $c"; exit 0; }; "#
            + "\(run) has-session -t \"=$c\" >/dev/null 2>&1 || { echo \(failedMarker); exit 0; }; "
            + "\(onTaken); done; echo \(failedMarker); exit 0"
    }

    /// Reads a claim's answer. Only a name that was asked for counts: anything else the host
    /// printed — a login script's chatter — is not an answer.
    static func parseClaim(_ output: String, candidates: [String]) -> Claim {
        if output.contains(missingMarker) { return .unavailable }
        for line in output.split(whereSeparator: \.isNewline) {
            let words = line.split(separator: " ", maxSplits: 1)
            guard words.count == 2, candidates.contains(String(words[1])) else { continue }
            switch words[0] {
            case "created": return .created(String(words[1]))
            case "exists" where candidates.count == 1: return .exists(String(words[1]))
            default: continue
            }
        }
        return .failed
    }

    /// The first `glass-N` not in `taken`: the first name a claim tries.
    static func nextName(avoiding taken: Set<String>) -> String {
        claimCandidates(avoiding: taken, count: 1)[0]
    }

    /// A name for when the host's sessions could not be listed: a `glass-N` far above the numbers
    /// in use, so attaching cannot join a session someone already has.
    static func unlistedName(avoiding taken: Set<String>, random: () -> Int = { Int.random(in: 100...9_999) }) -> String {
        var name = namePrefix + String(random())
        while taken.contains(name) { name = namePrefix + String(random()) }
        return name
    }

    nonisolated static func glassNumber(_ name: String) -> Int? {
        guard name.hasPrefix(namePrefix) else { return nil }
        return Int(name.dropFirst(namePrefix.count)).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The line typed into the shell: attach to the session, or create it — a new terminal's
    /// already exists, made by its claim. `exec` replaces the shell, so detaching from tmux ends
    /// the terminal cleanly instead of leaving a bare prompt.
    /// The leading space keeps it out of shell history where `ignorespace` is set. Without tmux
    /// the line does nothing and the shell stays.
    static func attachLine(name: String, takeOver: Bool) -> String {
        " command -v tmux >/dev/null && exec tmux -u new-session -A\(takeOver ? " -D" : "") -s \(quoted(name))"
    }

    /// The directory the session's active pane is in. tmux keeps the shell's OSC 7 reports to
    /// itself, so in tmux this is the only accurate answer to "where is this shell?". The target
    /// is a pane, so the exact session name needs its colon: `=name` alone answers nothing
    /// (found live on the test VM, tmux 3.6).
    static func currentPathCommand(name: String) -> String {
        "sh -c \(quoted(searchPath + "tmux -u display-message -p -t \(quoted("=" + name + ":")) '#{pane_current_path}'"))"
    }

    /// Scrolls the session's history `lines` toward earlier output, or back when negative: up
    /// enters copy mode, which `-e` leaves at the bottom; down outside it is a harmless error.
    /// tmux's `;` is quoted so that `sh` passes it to tmux rather than ending the command.
    static func scrollCommand(name: String, lines: Int) -> String {
        let target = quoted("=" + name + ":")
        let tmux = lines > 0
            ? "tmux -u copy-mode -e -t \(target) ';' send-keys -t \(target) -X -N \(lines) scroll-up"
            : "tmux -u send-keys -t \(target) -X -N \(-lines) scroll-down"
        return "sh -c \(quoted(searchPath + tmux))"
    }

    static func killCommand(name: String) -> String {
        "sh -c \(quoted(searchPath + "tmux -u kill-session -t \(quoted("=" + name))"))"
    }

    /// POSIX single quoting. `'\''` also reads correctly in fish, where `\'` outside quotes is a quote.
    nonisolated static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Open a terminal in a tmux session that is already running — Active's attach and take over.
struct TerminalTmuxAttachment: Equatable, Sendable {
    var name: String
    var takeOver: Bool = false
}

// MARK: Find (2026-10-08)

extension TerminalTmux {
    /// One step of the find bar in tmux's own search, as an exec channel's `sh` runs it: enter copy
    /// mode, search, and print where the search landed — one invocation, so one round trip a step.
    /// `-u` first, as in every tmux command Glass builds. `end` leaves copy mode, so typing reaches
    /// the shell again; outside copy mode it is a harmless error.
    static func findCommand(name: String, request: TerminalTmuxFindRequest) -> String {
        let target = quoted("=" + name + ":")
        let tmux: String
        switch request {
        case .search(let term, let direction):
            tmux = "tmux -u copy-mode -t \(target) ';' send-keys -t \(target) -X "
                + "\(TerminalTmuxFind.searchCommand(direction)) -- \(quoted(TerminalTmuxFind.argument(term))) "
                + "';' display -p -t \(target) \(quoted(TerminalTmuxFind.replyFormat))"
        case .end:
            tmux = "tmux -u send-keys -t \(target) -X cancel"
        }
        return "sh -c \(quoted(searchPath + tmux))"
    }
}
