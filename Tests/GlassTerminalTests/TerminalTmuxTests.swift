import Foundation
import Testing
import GlassTerminalEmulator
@testable import GlassTerminal

/// D44: terminals kept in tmux sessions (2026-10-01).
@Suite("tmux sessions")
@MainActor
struct TerminalTmuxTests {
    @MainActor private final class Writes {
        var lines: [String] = []
        func receive(_ data: Data) { lines.append(String(decoding: data, as: UTF8.self)) }
    }

    private func server(tmux: Bool?) -> ServerConfiguration {
        var server = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")
        server.tmux = tmux
        return server
    }

    /// A host's tmux, from memory: the list answers `listing`; a claim makes the first name it
    /// offers that is not running — those listed, and any taken after the list was read.
    @MainActor private final class Host {
        var running: Set<String>
        var takenBeforeClaim: Set<String> = []
        private(set) var claims: [[String]] = []
        init(listing: String) {
            if case .sessions(let sessions) = TerminalTmux.parse(listing) { running = Set(sessions.map(\.name)) } else { running = [] }
        }

        /// What the claim's `sh` would print.
        func claim(_ command: String) -> String? {
            guard let offered = TerminalTmuxTests.offered(in: command) else { return nil }
            claims.append(offered)
            running.formUnion(takenBeforeClaim)
            for name in offered {
                if !running.contains(name) {
                    running.insert(name)
                    return "created \(name)\n"
                }
                if offered.count == 1 { return "exists \(name)\n" }
            }
            return "__glass_tmux_failed__\n"
        }
    }

    /// The names a claim command offers, read back out of its script; nil for any other command.
    nonisolated static func offered(in command: String) -> [String]? {
        guard command.hasPrefix("sh -c '"), command.contains("new-session -d") else { return nil }
        let script = String(command.dropFirst("sh -c '".count).dropLast()).replacingOccurrences(of: #"'\''"#, with: "'")
        guard let start = script.range(of: "for c in "),
              let end = script.range(of: "; do ", range: start.upperBound..<script.endIndex) else { return nil }
        return script[start.upperBound..<end.lowerBound].split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
    }

    private func session(_ server: ServerConfiguration, writes: Writes, listing: String,
                         host: Host? = nil, commands: (@MainActor (String) -> Void)? = nil) -> TerminalSession {
        let session = TerminalSession(server: server, terminalWriteSink: { writes.receive($0) })
        let host = host ?? Host(listing: listing)
        session.tmuxCommandRunner = { command in
            commands?(command)
            return host.claim(command) ?? listing
        }
        return session
    }

    @Test("the list command and its answer")
    func parsing() {
        #expect(TerminalTmux.listCommand.hasPrefix("sh -c '"))
        #expect(TerminalTmux.parse("__glass_no_tmux__\n") == .unavailable)
        #expect(TerminalTmux.parse("") == .sessions([]))
        let listing = TerminalTmux.parse("glass-1\t1\t2\t1790000000\nwork\t0\t1\t1790000100\nbroken line\n")
        guard case .sessions(let sessions) = listing else { Issue.record("not a list"); return }
        #expect(sessions.map(\.name) == ["glass-1", "work"])
        #expect(sessions.map(\.attachedClients) == [1, 0])
        #expect(sessions.map(\.isGlass) == [true, false])
        #expect(sessions[1].lastActivity == Date(timeIntervalSince1970: 1_790_000_100))
    }

    @Test("names: the first free glass-N")
    func naming() {
        #expect(TerminalTmux.nextName(avoiding: []) == "glass-1")
        #expect(TerminalTmux.nextName(avoiding: ["glass-1", "glass-3", "work"]) == "glass-2")
        #expect(TerminalTmux.glassNumber("glass-12") == 12)
        #expect(TerminalTmux.glassNumber("glass-0") == nil && TerminalTmux.glassNumber("glassy") == nil)
    }

    @Test("quoting survives a name with a quote in it, and take over adds -D")
    func commands() {
        #expect(TerminalTmux.quoted("it's") == "'it'\\''s'")
        #expect(TerminalTmux.attachLine(name: "glass-2", takeOver: false)
                == " command -v tmux >/dev/null && exec tmux -u new-session -A -s 'glass-2'")
        #expect(TerminalTmux.attachLine(name: "work", takeOver: true).contains("new-session -A -D -s 'work'"))
        #expect(TerminalTmux.killCommand(name: "work")
                == #"sh -c 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; tmux -u kill-session -t '\''=work'\'''"#)
        // D47: every exec-channel command also looks where Homebrew puts tmux on a Mac.
        for command in [TerminalTmux.listCommand, TerminalTmux.currentPathCommand(name: "glass-1")] {
            #expect(command.contains(#"PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; "#))
        }
    }

    @Test("a server saved before tmux reads as off")
    func oldRecords() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(server(tmux: true))) as! [String: Any]
        json.removeValue(forKey: "tmux")
        let decoded = try JSONDecoder().decode(ServerConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.tmux == nil && !decoded.keepsSessionsInTmux)
    }

    @Test("connecting picks a free name, attaches, then runs the startup command inside it")
    func firstConnect() async {
        let writes = Writes()
        let session = session(server(tmux: true), writes: writes, listing: "glass-1\t1\t1\t0\n")
        _ = session.installStartupCommand("htop")
        session.state = .connected
        await session.waitForTmuxAttach()
        await session.waitUntilTerminalWritesComplete()
        #expect(session.tmuxSessionName == "glass-2")
        #expect(writes.lines == [" command -v tmux >/dev/null && exec tmux -u new-session -A -s 'glass-2'\n", "htop\n"])
    }

    @Test("scrolling a terminal in tmux scrolls tmux's history on the host, one command at a time")
    func scrolling() async {
        #expect(TerminalTmux.scrollCommand(name: "glass-2", lines: 3) == #"sh -c 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; tmux -u copy-mode -e -t '\''=glass-2:'\'' '\'';'\'' send-keys -t '\''=glass-2:'\'' -X -N 3 scroll-up'"#)
        var asked: [String] = []
        let session = session(server(tmux: true), writes: Writes(), listing: "", commands: { asked.append($0) })
        let scroll = session.terminalHostModel.onAlternateScreenScroll
        #expect(scroll?(32, true) == false, "not attached to tmux yet: the terminal keeps the scroll")
        session.state = .connected
        await session.waitForTmuxAttach()
        asked.removeAll()
        #expect(scroll?(40, true) == true && scroll?(30, true) == true)
        for _ in 0..<50 where asked.count < 2 { try? await Task.sleep(for: .milliseconds(10)) }
        // 40 pt is 2.5 lines: 2 go at once. The half left and 30 pt more (1.875) make 2.375 while
        // the first travels: 2 follow, and 0.375 waits for the next scroll.
        #expect(asked == [TerminalTmux.scrollCommand(name: "glass-1", lines: 2), TerminalTmux.scrollCommand(name: "glass-1", lines: 2)],
                "the first lines go at once; what gathers while they travel follows")
    }

    /// The command as the host's `sh` runs it: tmux's history moves, and leaves at the bottom.
    @Test("the scroll command works through sh against a real tmux", .enabled(if: TerminalTmuxTests.tmux != nil))
    func scrollingLive() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tmux-scroll-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // A private tmux server: TMUX_TMPDIR moves its default socket.
        func sh(_ command: String) -> String { Self.shell(command, ["TMUX_TMPDIR": folder.path, "PATH": "/usr/bin:/bin"]) }
        let tmux = TerminalTmuxTests.tmux!
        _ = sh("\(tmux) -f /dev/null new-session -d -s glass-7 -x 80 -y 10 'seq 1 200; sleep 600'")
        // The private server by its socket: named, tmux never falls back to the default one.
        defer { _ = sh("\(tmux) -S \(folder.path)/tmux-\(getuid())/default kill-server") }
        Thread.sleep(forTimeInterval: 0.3)
        _ = sh(TerminalTmux.scrollCommand(name: "glass-7", lines: 5))
        #expect(sh("\(tmux) display-message -p -t '=glass-7:' '#{pane_in_mode} #{scroll_position}'") == "1 5\n")
        _ = sh(TerminalTmux.scrollCommand(name: "glass-7", lines: -9))
        #expect(sh("\(tmux) display-message -p -t '=glass-7:' '#{pane_in_mode}'") == "0\n", "past the bottom: out of copy mode")
    }

    /// The owner (2026-10-11): "I can't drag select past the current screen buffer so I can't copy
    /// all of the output." Select All in a tmux tab takes tmux's history.
    @Test("tmux's history reads as text: each line's trailing blanks and the empty rows below dropped")
    func historyText() {
        #expect(TerminalTmux.historyText("one  \ntwo\t\n\n  three\n\n\n") == "one\ntwo\n\n  three")
        #expect(TerminalTmux.historyText("\n\n") == "")
        #expect(TerminalTmux.historyCommand(name: "glass-2").hasPrefix(#"sh -c 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; tmux '\''-u'\'' '\''capture-pane'\''"#))
    }

    @Test("Select All in a tab in tmux reads the session's whole history over the connection")
    func historyOverTheConnection() async {
        var asked: [String] = []
        let session = session(server(tmux: true), writes: Writes(), listing: "", commands: { asked.append($0) })
        let read = session.terminalHostModel.onFullHistory
        #expect(await read?() == nil, "not attached to tmux yet: nothing beyond the screen")
        session.state = .connected
        await session.waitForTmuxAttach()
        asked.removeAll()
        _ = await read?()
        #expect(asked == [TerminalTmux.historyCommand(name: "glass-1")])
    }

    /// The command as the host's `sh` runs it, against a private tmux: every line, history first.
    @Test("the history command reads every line of a real tmux session, wrapped lines joined",
          .enabled(if: TerminalTmuxTests.tmux != nil))
    func historyLive() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tmux-history-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func sh(_ command: String) -> String { Self.shell(command, ["TMUX_TMPDIR": folder.path, "PATH": "/usr/bin:/bin"]) }
        let tmux = TerminalTmuxTests.tmux!
        let long = String(repeating: "x", count: 100)
        _ = sh("\(tmux) -f /dev/null new-session -d -s glass-8 -x 40 -y 10 'seq 1 300; echo \(long); sleep 600'")
        defer { _ = sh("\(tmux) -S \(folder.path)/tmux-\(getuid())/default kill-server") }
        Thread.sleep(forTimeInterval: 0.3)
        let lines = TerminalTmux.historyText(sh(TerminalTmux.historyCommand(name: "glass-8"))).split(separator: "\n").map(String.init)
        #expect(Array(lines.prefix(300)) == (1...300).map(String.init), "the history before the screen, from the first line")
        #expect(lines.dropFirst(300).first == long, "a line wider than the pane, joined")
    }

    nonisolated static let tmux: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    // MARK: tmux in UTF-8 (2026-10-08)
    //
    // An SSH command on a Mac host has no locale, and tmux without one prints the tabs in its
    // answers as `_`: every listing read as "no sessions", and a new terminal joined `glass-1`.

    @Test("an answer tmux mangled, or an error, is a failure: never \"no sessions\"")
    func unreadable() {
        #expect(TerminalTmux.parse("glass-1_1_1_1700000000\n") == .failed)
        #expect(TerminalTmux.parse("__glass_tmux_failed__\n") == .failed)
        #expect(TerminalTmux.parse("\n") == .sessions([]), "nothing printed: no sessions")
    }

    @Test("a new terminal never takes a name from an answer it could not read")
    func unreadableConnect() async {
        let session = session(server(tmux: true), writes: Writes(), listing: "glass-1_1_1_1700000000\n")
        session.state = .connected
        await session.waitForTmuxAttach()
        let name = session.tmuxSessionName
        #expect(name.flatMap(TerminalTmux.glassNumber).map { $0 >= 100 } == true, "not glass-1: \(name ?? "none")")
    }

    @Test("every tmux run on a host is told the terminal is UTF-8")
    func utf8() throws {
        let commands = [TerminalTmux.listCommand, TerminalTmux.currentPathCommand(name: "glass-1"),
                        TerminalTmux.scrollCommand(name: "glass-1", lines: 2), TerminalTmux.scrollCommand(name: "glass-1", lines: -2),
                        TerminalTmux.killCommand(name: "glass-1"), TerminalTmux.attachLine(name: "glass-1", takeOver: true),
                        TerminalTmux.claimCommand(candidates: ["glass-1", "glass-2"])]
        let withoutU = try NSRegularExpression(pattern: #"\btmux (?!-u )"#)
        for command in commands {
            let runs = command.replacingOccurrences(of: "command -v tmux", with: "")
            #expect(withoutU.numberOfMatches(in: runs, range: NSRange(runs.startIndex..., in: runs)) == 0, "\(command)")
        }
    }

    /// The list command as a Mac host runs it over SSH: `sh`, the system PATH, and no locale.
    @Test("the list command reads a real tmux with no locale; no server is no sessions; an error is a failure",
          .enabled(if: TerminalTmuxTests.tmux != nil))
    func listingLive() throws {
        // Short: a socket path has a length limit, and some temporary folders are long.
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let environment = ["TMUX_TMPDIR": folder.path, "PATH": "/usr/bin:/bin"]
        let tmux = TerminalTmuxTests.tmux!
        #expect(TerminalTmux.parse(Self.shell(TerminalTmux.listCommand, environment)) == .sessions([]),
                "no server running: nothing runs, which is not a failure")
        _ = Self.shell("\(tmux) -f /dev/null new-session -d -s glass-1 -x 80 -y 10 'sleep 600'", environment)
        defer { _ = Self.shell("\(tmux) -S \(folder.path)/tmux-\(getuid())/default kill-server", environment) }
        guard case .sessions(let sessions) = TerminalTmux.parse(Self.shell(TerminalTmux.listCommand, environment)) else {
            Issue.record("not read as a list")
            return
        }
        #expect(sessions.map(\.name) == ["glass-1"])
    }

    /// A tmux that fails in some way other than "no server running" — never a real one: given a
    /// folder it cannot use, tmux falls back to the default server.
    @Test("a tmux that fails for any other reason is a failure, not an empty host")
    func listingFailure() throws {
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tmux = folder.appendingPathComponent("tmux")
        try Data("#!/bin/sh\necho 'server exited unexpectedly' >&2\nexit 1\n".utf8).write(to: tmux)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmux.path)
        let environment = ["PATH": "\(folder.path):/usr/bin:/bin"]
        #expect(TerminalTmux.parse(Self.shell(TerminalTmux.listCommand, environment)) == .failed)
    }

    nonisolated static func shell(_ command: String, _ environment: [String: String]) -> String {
        LiveProcess.run("/bin/sh", ["-c", command], environment: environment, includingErrors: true).output
    }

    @Test("when the host's sessions cannot be listed, a new terminal never takes glass-1")
    func unlisted() async {
        var sequence = [512, 512, 4_000].makeIterator()
        #expect(TerminalTmux.unlistedName(avoiding: ["glass-512"], random: { sequence.next()! }) == "glass-4000")

        let writes = Writes()
        let session = TerminalSession(server: server(tmux: true), terminalWriteSink: { writes.receive($0) })
        var asked = 0
        session.tmuxCommandRunner = { _ in asked += 1; throw SSHError.notConnected }
        session.state = .connected
        await session.waitForTmuxAttach()
        await session.waitUntilTerminalWritesComplete()
        #expect(asked == 2, "asked again once")
        let name = try? #require(session.tmuxSessionName)
        #expect(name.map { (TerminalTmux.glassNumber($0) ?? 0) >= 100 } == true, "not glass-1: \(name ?? "none")")
    }

    @Test("a reconnect attaches to the same session without asking the host again")
    func reconnect() async {
        let writes = Writes()
        var asked = 0
        let session = session(server(tmux: true), writes: writes, listing: "", commands: { _ in asked += 1 })
        session.state = .connected
        await session.waitForTmuxAttach()
        session.state = .reconnecting
        session.state = .connected
        await session.waitForTmuxAttach()
        await session.waitUntilTerminalWritesComplete()
        #expect(asked == 2, "the list and the claim, once")
        #expect(writes.lines.count == 2 && writes.lines[0] == writes.lines[1])
        #expect(writes.lines[0].contains("-s 'glass-1'"))
    }

    @Test("without tmux on the host: an ordinary shell, and the startup command still runs")
    func unavailable() async {
        let writes = Writes()
        let session = session(server(tmux: true), writes: writes, listing: "__glass_no_tmux__\n")
        _ = session.installStartupCommand("uptime")
        session.state = .connected
        await session.waitForTmuxAttach()
        await session.waitUntilTerminalWritesComplete()
        #expect(session.tmuxUnavailable && !session.usesTmux)
        #expect(writes.lines == ["uptime\n"])
    }

    @Test("attaching from Active uses the given name and takes over once")
    func attachGiven() async {
        let writes = Writes()
        let session = session(server(tmux: nil), writes: writes, listing: "")
        session.tmuxSessionName = "work"
        session.tmuxTakesOver = true
        session.state = .connected
        await session.waitForTmuxAttach()
        session.state = .reconnecting
        session.state = .connected
        await session.waitForTmuxAttach()
        await session.waitUntilTerminalWritesComplete()
        #expect(writes.lines.map { $0.contains(" -D ") } == [true, false])
    }

    @Test("with the setting off nothing is typed, but the host is checked for tmux")
    func off() async {
        for (listing, expected) in [("", true), ("__glass_no_tmux__\n", false)] {
            let writes = Writes()
            var observed: [Bool] = []
            let session = session(server(tmux: false), writes: writes, listing: listing)
            session.tmuxAvailabilityObserved = { observed.append($0) }
            session.state = .connected
            await session.waitForTmuxAttach()
            await session.waitUntilTerminalWritesComplete()
            #expect(writes.lines.isEmpty && session.tmuxSessionName == nil)
            #expect(observed == [expected])
        }
    }

    @Test("with the setting on, the attach reports what it found too")
    func onReports() async {
        for (listing, expected) in [("", true), ("__glass_no_tmux__\n", false)] {
            var observed: [Bool] = []
            let session = session(server(tmux: true), writes: Writes(), listing: listing)
            session.tmuxAvailabilityObserved = { observed.append($0) }
            session.state = .connected
            await session.waitForTmuxAttach()
            #expect(observed == [expected])
        }
    }

    @Test("closing asks only when something would stop: a terminal in tmux keeps running")
    func closeRule() async {
        let inTmux = session(server(tmux: true), writes: Writes(), listing: "")
        #expect(!inTmux.closeStopsWork, "not connected yet")
        inTmux.state = .connected
        await inTmux.waitForTmuxAttach()
        #expect(inTmux.survivesClose && !inTmux.closeStopsWork)

        let plain = session(server(tmux: false), writes: Writes(), listing: "")
        plain.state = .connected
        #expect(!plain.survivesClose && plain.closeStopsWork)

        let missing = session(server(tmux: true), writes: Writes(), listing: "__glass_no_tmux__\n")
        missing.state = .connected
        await missing.waitForTmuxAttach()
        #expect(missing.closeStopsWork, "the setting is on but the host has no tmux")
        missing.state = .disconnected
        #expect(!missing.closeStopsWork)
    }

    @Test("Active says when a terminal is in tmux, and calls ending it Detach only when all are")
    func activeWording() async {
        let inTmux = session(server(tmux: true), writes: Writes(), listing: "glass-1\t1\t1\t0\n")
        inTmux.state = .connected
        await inTmux.waitForTmuxAttach()
        let plain = session(server(tmux: false), writes: Writes(), listing: "")
        plain.state = .connected

        #expect(GlassTerminalCapability.subtitle(for: [inTmux]) == "Connected · in tmux (Terminal 2)")
        #expect(GlassTerminalCapability.closeTitle(for: [inTmux]) == "Detach")
        #expect(GlassTerminalCapability.closeSymbolName(for: [inTmux]) == "eject")
        #expect(GlassTerminalCapability.subtitle(for: [plain]) == "Connected")
        #expect(GlassTerminalCapability.closeTitle(for: [plain]) == "Close")
        #expect(GlassTerminalCapability.subtitle(for: [inTmux, plain]) == "2 terminals, 1 in tmux")
        #expect(GlassTerminalCapability.closeTitle(for: [inTmux, plain]) == "Close", "closing stops the plain one")
        #expect(GlassTerminalCapability.subtitle(for: [inTmux, inTmux]) == "2 terminals in tmux")
    }

    @Test("in tmux the working directory comes from tmux, never the stale report")
    func workingDirectory() async {
        var asked: [String] = []
        let inTmux = session(server(tmux: true), writes: Writes(), listing: "", commands: { asked.append($0) })
        inTmux.state = .connected
        await inTmux.waitForTmuxAttach()
        inTmux.tmuxCommandRunner = { asked.append($0); return "/srv/app\n" }
        #expect(await inTmux.workingDirectory(reported: "/home/ann") == "/srv/app")
        #expect(asked.last == TerminalTmux.currentPathCommand(name: "glass-1"))
        inTmux.tmuxCommandRunner = { _ in "no server running" }
        #expect(await inTmux.workingDirectory(reported: "/home/ann") == nil, "unknown, not stale")

        let plain = session(server(tmux: false), writes: Writes(), listing: "")
        plain.state = .connected
        #expect(await plain.workingDirectory(reported: "/home/ann") == "/home/ann")
    }

    @Test("the form explains the setting for each state of the last check")
    func footnotes() {
        #expect(TerminalAdvancedFields.tmuxFootnote(available: nil).contains("Connect to this host once"))
        #expect(TerminalAdvancedFields.tmuxFootnote(available: false).contains("wasn't installed"))
        #expect(TerminalAdvancedFields.tmuxFootnote(available: true).contains("keeps going"))
    }

    // MARK: Claiming a name (2026-10-08)
    //
    // A name chosen from a list and attached with `new-session -A` joined whatever took that name
    // in between: two devices connecting together landed in one session. The claim makes the
    // session with `new-session -d`, which refuses a running name, and tries the next.

    @Test("the claim script and what it answers")
    func claimScript() {
        #expect(TerminalTmux.claimScript(candidates: ["glass-2", "glass-3"], tmux: "tmux")
                == #"command -v tmux >/dev/null 2>&1 || { echo __glass_no_tmux__; exit 0; }; "#
                + #"for c in 'glass-2' 'glass-3'; do tmux -u new-session -d -s "$c" </dev/null >/dev/null 2>&1 && { echo "created $c"; exit 0; }; "#
                + #"tmux -u has-session -t "=$c" >/dev/null 2>&1 || { echo __glass_tmux_failed__; exit 0; }; continue; done; "#
                + "echo __glass_tmux_failed__; exit 0")
        let mac = TerminalTmux.claimScript(candidates: ["glass-1"], directory: "/Users/ann/it's", command: ["/bin/zsh", "-l"],
                                           tmux: "'/opt/homebrew/bin/tmux'")
        #expect(mac.contains(#"'/opt/homebrew/bin/tmux' -u new-session -d -s "$c" -c '/Users/ann/it'\''s' '/bin/zsh' '-l' </dev/null"#))
        #expect(mac.contains(#"echo "exists $c"; exit 0; done"#), "one name asked for: running is an answer, not a reason to go on")
        #expect(TerminalTmux.claimScript(candidates: (1...40).map { "glass-\($0)" }, tmux: "tmux").contains("'glass-32';"),
                "at most 32 names")
        #expect(!TerminalTmux.claimScript(candidates: (1...40).map { "glass-\($0)" }, tmux: "tmux").contains("'glass-33'"))
        #expect(TerminalTmux.claimCommand(candidates: ["glass-1"]).hasPrefix(#"sh -c 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; "#))

        let offered = ["glass-2", "glass-3"]
        #expect(TerminalTmux.parseClaim("created glass-3\n", candidates: offered) == .created("glass-3"))
        #expect(TerminalTmux.parseClaim("Welcome!\ncreated glass-2\n", candidates: offered) == .created("glass-2"), "a login script's chatter is skipped")
        #expect(TerminalTmux.parseClaim("created glass-9\n", candidates: offered) == .failed, "a name not offered is no answer")
        #expect(TerminalTmux.parseClaim("exists glass-2\n", candidates: offered) == .failed, "with several names, running is not an answer")
        #expect(TerminalTmux.parseClaim("exists work\n", candidates: ["work"]) == .exists("work"))
        #expect(TerminalTmux.parseClaim("__glass_tmux_failed__\n", candidates: offered) == .failed)
        #expect(TerminalTmux.parseClaim("__glass_no_tmux__\n", candidates: offered) == .unavailable)
        #expect(TerminalTmux.claimCandidates(avoiding: ["glass-1", "glass-3", "work"], count: 3) == ["glass-2", "glass-4", "glass-5"])
        var sequence = [512, 512, 4_000].makeIterator()
        #expect(TerminalTmux.unlistedCandidates(avoiding: [], count: 2, random: { sequence.next()! }) == ["glass-512", "glass-4000"])
    }

    @Test("a name taken between the list and the claim is skipped, never joined")
    func takenMidClaim() async throws {
        let writes = Writes()
        let host = Host(listing: "glass-1\t1\t1\t0\n")
        host.takenBeforeClaim = ["glass-2"]
        let session = session(server(tmux: true), writes: writes, listing: "glass-1\t1\t1\t0\n", host: host)
        _ = session.installStartupCommand("htop")
        session.state = .connected
        await session.waitForTmuxAttach()
        await session.waitUntilTerminalWritesComplete()
        #expect(host.claims.first?.first == "glass-2", "the claim starts from the list")
        #expect(session.tmuxSessionName == "glass-3", "glass-2 went to someone else in between")
        #expect(writes.lines == [" command -v tmux >/dev/null && exec tmux -u new-session -A -s 'glass-3'\n", "htop\n"],
                "made for this terminal: the startup command follows")
    }

    @Test("a session this terminal joins never has the startup command typed into it")
    func startupOnlyWhenCreated() async {
        let attach = " command -v tmux >/dev/null && exec tmux -u new-session -A -s 'work'\n"

        // Active: joined on purpose, and not claimed.
        var asked: [String] = []
        let writes = Writes()
        let active = session(server(tmux: true), writes: writes, listing: "work\t1\t1\t0\n", commands: { asked.append($0) })
        active.tmuxSessionName = "work"
        _ = active.installStartupCommand("htop")
        active.state = .connected
        await active.waitForTmuxAttach()
        active.state = .reconnecting
        active.state = .connected
        await active.waitForTmuxAttach()
        await active.waitUntilTerminalWritesComplete()
        #expect(asked.isEmpty, "Active's choice is not claimed")
        #expect(writes.lines == [attach, attach], "the attach line alone, then again on reconnecting")
        #expect(!active.hasPendingStartupCommand)

        // A name kept from before: claimed. Running, it is joined; ended, it is made again.
        for (running, expected) in [(true, [attach]), (false, [attach, "htop\n"])] {
            let writes = Writes()
            let host = Host(listing: running ? "work\t0\t1\t0\n" : "")
            let kept = session(server(tmux: true), writes: writes, listing: "", host: host)
            kept.tmuxSessionName = "work"
            kept.tmuxClaimsGivenName = true
            _ = kept.installStartupCommand("htop")
            kept.state = .connected
            await kept.waitForTmuxAttach()
            await kept.waitUntilTerminalWritesComplete()
            #expect(host.claims == [["work"]])
            #expect(writes.lines == expected, running ? "exists: the attach line only" : "created: the attach line, then the command")
        }
    }

    /// Eight claims at once through `sh` against a private tmux server — named by its socket in
    /// every call, and started with no configuration, so neither the real server nor the owner's
    /// `~/.tmux.conf` is ever touched.
    @Test("eight claims at once take eight names; a claim for one running name answers exists",
          .enabled(if: TerminalTmuxTests.tmux != nil))
    func claimingLive() async throws {
        let tmux = try #require(TerminalTmuxTests.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let socket = folder.appendingPathComponent("s").path
        let server = ["-S", socket, "-f", "/dev/null"]
        let environment = ["PATH": "/usr/bin:/bin", "TMUX_TMPDIR": folder.path]
        defer { _ = Self.shell("\(TerminalTmux.quoted(tmux)) -S \(TerminalTmux.quoted(socket)) kill-server", environment) }

        // Each session runs `sleep`, not the login shell and its dotfiles — long enough to outlast a
        // slow, busy test run; the teardown ends the server.
        let candidates = TerminalTmux.claimCandidates(avoiding: [])
        let script = TerminalTmux.claimScript(candidates: candidates, command: ["/bin/sleep", "600"],
                                              tmux: TerminalTmux.quoted(tmux), serverArguments: server)
        // Real threads, not the task pool: eight blocking waits there queued behind the other live
        // tests for most of a minute, and the sessions' sleeps ran out (2026-10-08).
        nonisolated final class Answers: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [String] = []
            func append(_ value: String) { lock.withLock { values.append(value) } }
            var all: [String] { lock.withLock { values } }
        }
        let answers = await Task.detached {
            let answers = Answers()
            DispatchQueue.concurrentPerform(iterations: 8) { _ in answers.append(Self.shell(script, environment)) }
            return answers.all
        }.value
        let claimed = answers.compactMap { answer -> String? in
            if case .created(let name) = TerminalTmux.parseClaim(answer, candidates: candidates) { return name }
            return nil
        }
        #expect(claimed.count == 8 && Set(claimed).count == 8, "\(answers)")
        #expect(Set(claimed) == Set(candidates.prefix(8)), "the lowest numbers, none skipped")

        let one = TerminalTmux.claimScript(candidates: ["glass-1"], command: ["/bin/sleep", "600"],
                                           tmux: TerminalTmux.quoted(tmux), serverArguments: server)
        #expect(TerminalTmux.parseClaim(Self.shell(one, environment), candidates: ["glass-1"]) == .exists("glass-1"))
        let listed = Self.shell("\(TerminalTmux.quoted(tmux)) -S \(TerminalTmux.quoted(socket)) list-sessions -F '#{session_name}'", environment)
        #expect(listed.split(separator: "\n").count == 8, "exists made nothing")
    }

    // MARK: W6 — the listing says what a session shows, and keeps the name its tab was given

    @Test("W6: the listing reads the active pane's title, folder and program, the given name and the server; a title may hold anything")
    func richListing() throws {
        let server = TerminalTmux.Server(pid: 4242, startTime: 1_789_990_000, socketPath: "/private/tmp/tmux-501/default")
        func line(_ fields: [String]) -> String { fields.joined(separator: "\t") }
        // The repository and branch fields (W11) are empty here; `TerminalRepositoryTests` reads them.
        let titled = line(["glass-3", "1", "2", "1790000000", "4242", "1789990000", server.socketPath, "claude",
                           "alpha.example.com", "alpha", "shop", "/Users/ann/src/shop", "", "", "✳ Claude\tCode: fix: the build"])
        let atHome = line(["glass-4", "0", "1", "1790000200", "4242", "1789990000", server.socketPath, "zsh",
                           "alpha.example.com", "alpha", "", "/Users/ann", "", "", "alpha.example.com"])
        let older = "work\t0\t1\t1790000100"
        let output = [titled, older, atHome, "__glass_home__\t/Users/ann"].joined(separator: "\n") + "\n"
        guard case .sessions(let sessions) = TerminalTmux.parse(output) else {
            Issue.record("not read as a list")
            return
        }
        try #require(sessions.map(\.name) == ["glass-3", "work", "glass-4"])
        #expect(sessions[0].title == "✳ Claude\tCode: fix: the build", "everything after the fourteenth tab is the title")
        #expect(sessions[0].directory == "/Users/ann/src/shop" && sessions[0].command == "claude")
        #expect(sessions[0].givenName == "shop" && sessions[0].displayName == "shop")
        #expect(sessions[0].server == server && sessions[0].home == "/Users/ann")
        #expect(sessions[0].attachedClients == 1 && sessions[0].windows == 2)
        #expect(sessions[2].title == nil, "tmux's default title, the host name, is not a title")
        #expect(sessions[2].givenName == nil && sessions[2].displayName == "Terminal 4", "untitled, at home: its own name")
        #expect(sessions[1] == TerminalTmux.Session(name: "work", attachedClients: 0, windows: 1,
                                                    lastActivity: Date(timeIntervalSince1970: 1_790_000_100)),
                "an older four-field answer still reads")
        #expect(TerminalTmux.parse(older + "\n") == .sessions([sessions[1]]))
        // A title is text a program chose: one that reads like a marker is still a title.
        let mischief = titled.replacingOccurrences(of: "✳ Claude\tCode: fix: the build", with: "__glass_no_tmux__")
        guard case .sessions(let marked) = TerminalTmux.parse(mischief + "\n") else {
            Issue.record("a title that reads like a marker made the listing something else")
            return
        }
        #expect(marked.first?.title == "__glass_no_tmux__")
    }

    @Test("W6: the command naming a session quotes every word, holds the name to one line, escapes a trailing ;, and with no name unsets it")
    func givenNameCommand() {
        let name = "it's \"$HOME\" `id`\nnext;"
        #expect(TerminalTmux.givenNameArguments(session: "glass-1", name: name)
                == ["-u", "set-option", "-t", "=glass-1:", "@glass-name", "it's \"$HOME\" `id` next\\;"])
        #expect(TerminalTmux.givenNameCommand(session: "glass-1", name: name)
                == #"sh -c 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; tmux '\''-u'\'' '\''set-option'\'' '\''-t'\'' '\''=glass-1:'\'' '\''@glass-name'\'' '\''it'\''\'\'''\''s "$HOME" `id` next\;'\'''"#)
        #expect(TerminalTmux.givenNameCommand(session: "glass-1", name: nil)
                == #"sh -c 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; tmux '\''-u'\'' '\''set-option'\'' '\''-u'\'' '\''-t'\'' '\''=glass-1:'\'' '\''@glass-name'\'''"#)
        #expect(TerminalTmux.givenNameArguments(session: "glass-1", name: " \n ")
                == ["-u", "set-option", "-u", "-t", "=glass-1:", "@glass-name"], "a blank name is no name")
        #expect(TerminalTmux.givenNameCommand(session: "a:b", name: "x") == nil, "a session name tmux would misread")
        #expect(TerminalTmux.givenNameArguments(session: "-t", name: "x") == nil)
        #expect(TerminalTmux.givenNameQuery(session: "glass-1")
                == #"sh -c 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; tmux '\''-u'\'' '\''display-message'\'' '\''-p'\'' '\''-t'\'' '\''=glass-1:'\'' '\''#{@glass-name}'\'''"#)
    }

    /// Against a private tmux server: every run names its socket — through `-S`, the listing's
    /// server arguments, or a `tmux` on the PATH that adds it — so the default server, which holds
    /// the owner's sessions, is never reached (rule 63).
    @Test("W6, live: the listing gives the active pane's title and folder and the server; a name set through each builder reads back",
          .enabled(if: TerminalTmuxTests.tmux != nil))
    func namingLive() throws {
        let tmux = try #require(TerminalTmuxTests.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8).lowercased())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let socket = folder.appendingPathComponent("s").path
        let work = folder.appendingPathComponent("shop")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        // Home as the system reports a process's folder: /tmp is a link to /private/tmp.
        // (`realpath`: Foundation's resolving gives /tmp back.)
        let home = try #require(realpath(folder.path, nil).map { resolved in
            defer { free(resolved) }
            return String(cString: resolved)
        })
        let environment = ["PATH": "/usr/bin:/bin", "HOME": home]
        @discardableResult func run(_ arguments: [String]) -> (output: String, status: Int32) {
            LiveProcess.run(tmux, ["-S", socket] + arguments, environment: environment)
        }
        defer { run(["kill-server"]) }
        func listing() -> [TerminalTmux.Session] {
            let script = TerminalTmux.listScript(tmux: TerminalTmux.quoted(tmux), serverArguments: ["-S", socket])
            guard case .sessions(let sessions) = TerminalTmux.parse(LiveProcess.run("/bin/sh", ["-c", script], environment: environment).output)
            else { return [] }
            return sessions
        }

        #expect(run(["-u", "-f", "/dev/null", "new-session", "-d", "-s", "glass-1", "-c", work.path, "-x", "80", "-y", "10",
                     "/bin/sleep", "600"]).status == 0)
        #expect(run(["-u", "new-session", "-d", "-s", "glass-2", "-c", home, "/bin/sleep", "600"]).status == 0)
        // A second window, now the active one: a session's line is its active pane's.
        #expect(run(["-u", "new-window", "-t", "=glass-1:", "-c", "/usr", "/bin/sleep", "600"]).status == 0)
        #expect(run(["-u", "select-pane", "-t", "=glass-1:", "-T", "✳ Claude Code: fix"]).status == 0)

        let sessions = listing()
        let first = try #require(sessions.first { $0.name == "glass-1" })
        #expect(first.title == "✳ Claude Code: fix")
        #expect(first.directory == "/usr", "the active window's pane, not the first one")
        #expect(first.command == "sleep")
        #expect(first.home == home)
        let pid = Int(run(["display-message", "-p", "#{pid}"]).output.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(first.server?.pid == pid && first.server?.socketPath == socket)
        #expect(Set(sessions.compactMap(\.server)).count == 1, "one server, the same on every line")
        let second = try #require(sessions.first { $0.name == "glass-2" })
        #expect(second.title == nil && second.displayName == "Terminal 2", "no program titled it, and it is at home")

        // As a local tab names its session: argv.
        let name = "it's \"$HOME\" `id` build;"
        #expect(run(try #require(TerminalTmux.givenNameArguments(session: "glass-1", name: name))).status == 0)
        #expect(listing().first { $0.name == "glass-1" }?.givenName == name)

        // As an SSH tab does: the exact command, through sh, with a tmux on the PATH that names the socket.
        let bin = folder.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let shim = bin.appendingPathComponent("tmux")
        try Data("#!/bin/sh\nexec \(TerminalTmux.quoted(tmux)) -S \(TerminalTmux.quoted(socket)) \"$@\"\n".utf8).write(to: shim)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let throughShim = ["PATH": "\(bin.path):/usr/bin:/bin", "HOME": home]
        let command = try #require(TerminalTmux.givenNameCommand(session: "glass-2", name: name))
        #expect(LiveProcess.run("/bin/sh", ["-c", command], environment: throughShim).status == 0)
        #expect(listing().first { $0.name == "glass-2" }?.givenName == name)
        let query = try #require(TerminalTmux.givenNameQuery(session: "glass-2"))
        #expect(LiveProcess.run("/bin/sh", ["-c", query], environment: throughShim).output == name + "\n")

        #expect(run(try #require(TerminalTmux.givenNameArguments(session: "glass-1", name: nil))).status == 0)
        #expect(listing().first { $0.name == "glass-1" }?.givenName == nil, "the automatic name takes it away")
    }
}
