import Foundation
import Testing
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
                == " command -v tmux >/dev/null && exec tmux new-session -A -s 'glass-2'")
        #expect(TerminalTmux.attachLine(name: "work", takeOver: true).contains("new-session -A -D -s 'work'"))
        #expect(TerminalTmux.killCommand(name: "work") == "sh -c 'tmux kill-session -t '\\''=work'\\'''")
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
        #expect(writes.lines == [" command -v tmux >/dev/null && exec tmux new-session -A -s 'glass-2'\n", "htop\n"])
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

    @Test("the form explains the setting for each state of the last check")
    func footnotes() {
        #expect(TerminalAdvancedFields.tmuxFootnote(available: nil).contains("Connect to this host once"))
        #expect(TerminalAdvancedFields.tmuxFootnote(available: false).contains("wasn't installed"))
        #expect(TerminalAdvancedFields.tmuxFootnote(available: true).contains("keeps going"))
    }
}
