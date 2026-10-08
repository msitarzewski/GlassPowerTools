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

    private func session(_ server: ServerConfiguration, writes: Writes,
                         listing: String, commands: (@MainActor (String) -> Void)? = nil) -> TerminalSession {
        let session = TerminalSession(server: server, terminalWriteSink: { writes.receive($0) })
        session.tmuxCommandRunner = { command in commands?(command); return listing }
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
        func sh(_ command: String) -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            // A private tmux server: TMUX_TMPDIR moves its default socket.
            process.environment = ["TMUX_TMPDIR": folder.path, "PATH": "/usr/bin:/bin"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try? process.run()
            process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        let tmux = TerminalTmuxTests.tmux!
        _ = sh("\(tmux) -f /dev/null new-session -d -s glass-7 -x 80 -y 10 'seq 1 200; sleep 30'")
        // The private server by its socket: named, tmux never falls back to the default one.
        defer { _ = sh("\(tmux) -S \(folder.path)/tmux-\(getuid())/default kill-server") }
        Thread.sleep(forTimeInterval: 0.3)
        _ = sh(TerminalTmux.scrollCommand(name: "glass-7", lines: 5))
        #expect(sh("\(tmux) display-message -p -t '=glass-7:' '#{pane_in_mode} #{scroll_position}'") == "1 5\n")
        _ = sh(TerminalTmux.scrollCommand(name: "glass-7", lines: -9))
        #expect(sh("\(tmux) display-message -p -t '=glass-7:' '#{pane_in_mode}'") == "0\n", "past the bottom: out of copy mode")
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
                        TerminalTmux.killCommand(name: "glass-1"), TerminalTmux.attachLine(name: "glass-1", takeOver: true)]
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
        _ = Self.shell("\(tmux) -f /dev/null new-session -d -s glass-1 -x 80 -y 10 'sleep 30'", environment)
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
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
        #expect(asked == 1)
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
}
