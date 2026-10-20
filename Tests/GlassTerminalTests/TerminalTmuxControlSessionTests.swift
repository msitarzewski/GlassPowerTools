import Foundation
import Testing
@testable import GlassTerminal
@testable import GlassTerminalEmulator

/// A terminal session kept in tmux attaches as a control-mode client where the host's tmux can have
/// one (D83, 2026-10-19): its attach line, what tmux sends back, and what it types, through the
/// session's own write queue — the wiring the live tests leave out.
@MainActor
@Suite("A terminal in tmux as a control-mode client")
struct TerminalTmuxControlSessionTests {
    @MainActor private final class Writes {
        var text = ""
        func receive(_ data: Data) { text += String(decoding: data, as: UTF8.self) }
        func take() -> String { defer { text = "" }; return text }
    }

    private func session(version: String, writes: Writes) -> TerminalSession {
        var server = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")
        server.tmux = true
        let session = TerminalSession(server: server, terminalWriteSink: { writes.receive($0) })
        session.tmuxCommandRunner = { command in command == TerminalTmux.versionCommand ? version : "" }
        // A name given, as Active gives one: attached without a claim.
        session.tmuxSessionName = "work"
        return session
    }

    private func reply(_ number: Int, _ lines: [String] = []) -> String {
        (["%begin 1700000000 \(number) 1"] + lines + ["%end 1700000000 \(number) 1"]).map { $0 + "\r\n" }.joined()
    }

    @Test("tmux 3.2 or later: -CC, sized and asked for the pane once tmux starts, keystrokes as send-keys")
    func controlClient() async {
        let writes = Writes()
        let session = session(version: "tmux 3.6\n", writes: writes)
        session.state = .connected
        await session.waitForTmuxAttach()
        await session.waitUntilTerminalWritesComplete()
        #expect(writes.take() == " command -v tmux >/dev/null && exec tmux -u -CC new-session -A -s 'work'\n")
        #expect(session.terminalHostModel.isTmuxControlClient)

        // Typed before tmux has started: held, not typed at the shell tmux replaces.
        session.sendTerminalData(Data("ls\r".utf8))
        await session.waitUntilTerminalWritesComplete()
        #expect(writes.take().isEmpty)

        session.feedTerminalData(Data("\u{1B}P1000p%session-changed $1 work\r\n".utf8))
        await session.waitUntilTerminalWritesComplete()
        #expect(writes.take().hasPrefix("refresh-client -C 120,40\nrefresh-client -f pause-after=30\ndisplay-message -p"), "the session's own size")

        session.feedTerminalData(Data((reply(1) + reply(2) + reply(3, ["%3 @1"])).utf8))
        await session.waitUntilTerminalWritesComplete()
        #expect(writes.take().hasPrefix("capture-pane"))
        session.feedTerminalData(Data((reply(4) + reply(5, ["$ "]) + reply(6, ["$ "]) + reply(7)
                                       + reply(8, ["0,0,0,2,0,0,23,1,0,0,0,1,0,0,0,0,0,0,80,24,0"]) + reply(9)).utf8))
        await session.waitUntilTerminalWritesComplete()
        #expect(writes.take() == "send-keys -l -t %3 -- 'ls'\nsend-keys -H -t %3 0d\n", "what was held, to the pane")

        session.sendTerminalData(Data("q".utf8))
        session.updateTerminalGeometry(rows: 30, columns: 100)
        await session.waitUntilTerminalWritesComplete()
        #expect(writes.take() == "send-keys -l -t %3 -- 'q'\nrefresh-client -C 100,30\n")
        #expect(session.scrollTmux(deltaY: 3, precise: false) == false, "the terminal's own history scrolls")
        #expect(session.tmuxFindTarget == nil, "and is what Find searches")

        session.state = .reconnecting
        #expect(!session.terminalHostModel.isTmuxControlClient, "a connection's client ends with it")
        session.state = .disconnected
    }

    @Test("tmux older than 3.2 attaches the ordinary way")
    func olderTmux() async {
        let writes = Writes()
        let session = session(version: "tmux 3.1c\n", writes: writes)
        session.state = .connected
        await session.waitForTmuxAttach()
        await session.waitUntilTerminalWritesComplete()
        #expect(writes.take() == " command -v tmux >/dev/null && exec tmux -u new-session -A -s 'work'\n")
        #expect(!session.terminalHostModel.isTmuxControlClient)
        session.sendTerminalData(Data("ls\r".utf8))
        await session.waitUntilTerminalWritesComplete()
        #expect(writes.take() == "ls\r", "typed at the terminal as always")
        session.state = .disconnected
    }
}
