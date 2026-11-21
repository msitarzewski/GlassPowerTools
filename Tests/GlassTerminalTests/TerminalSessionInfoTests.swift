import Foundation
import Testing
@testable import GlassTerminal

/// Get Info for a terminal (the owner, 2026-11-19: "it looks like we need a right click > Get Info... on the tabs so
/// finding its tmux name is easier"). Stand-in hosts only: nothing here runs tmux.
@MainActor
struct TerminalSessionInfoTests {
    private func terminal(listing: String) -> TerminalSession {
        var server = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")
        server.tmux = true
        let terminal = TerminalSession(server: server, terminalWriteSink: { _ in })
        terminal.tmuxCommandRunner = { command in command == TerminalTmux.listCommand ? listing : "" }
        terminal.tmuxSessionName = "glass-7"
        terminal.tmuxSessionCreated = 1_790_000_000
        return terminal
    }

    /// `glass-7` in the full listing format, made at `created`, with `clients` attached.
    private func listed(clients: Int, created: Int = 1_790_000_000) -> String {
        ["glass-7", String(clients), "1", "", "4242", "1789990000", "/tmp/tmux-501/default", "claude", "alpha.example.com",
         "alpha", "", "/home/ann/src/shop", "", "", "", String(created), "alpha.example.com"].joined(separator: "\t") + "\n"
    }

    @Test("a terminal's info: its session, machine, when the session was made; and how many other places have it open")
    func terminalInfo() async {
        let terminal = terminal(listing: listed(clients: 3))
        let known = terminal.sessionInfo(title: "shop")
        #expect(known.tmuxSession == "glass-7" && known.machine == "alpha" && known.title == "shop")
        #expect(known.created == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(known.otherClients == nil && known.openElsewhere == nil, "only the machine can say who else")

        terminal.state = .connected
        await terminal.waitForTmuxAttach()
        let asked = await terminal.sessionInfoAskingTheMachine(title: "shop")
        #expect(asked.otherClients == 2, "three clients: this terminal and two others")
        #expect(asked.openElsewhere == "Here and in 2 other places")

        // Another session that took its name is not its own: nothing to say about who has it.
        let replaced = self.terminal(listing: listed(clients: 1, created: 1_795_105_500))
        replaced.state = .connected
        await replaced.waitForTmuxAttach()
        #expect(await replaced.sessionInfoAskingTheMachine().otherClients == nil)
        terminal.disconnect()
        replaced.disconnect()
    }

    @Test("what Get Info says: only here, one place or several; a folder under home as ~; outside tmux, nothing to count")
    func wording() {
        var info = TerminalSessionInfo(id: UUID(), title: "t", machine: "This Mac", tmuxSession: "glass-1", created: nil,
                                       folder: nil, running: nil, otherClients: 0)
        #expect(info.openElsewhere == "Only here")
        info.otherClients = 1
        #expect(info.openElsewhere == "Here and in 1 other place")
        info.tmuxSession = nil
        #expect(info.openElsewhere == nil, "not in tmux: nothing else can have it open")
        #expect(TerminalSessionInfo.folder("/Users/ann/src/shop", home: "/Users/ann") == "~/src/shop")
        #expect(TerminalSessionInfo.folder("/Users/annex", home: "/Users/ann") == "/Users/annex")
        #expect(TerminalSessionInfo.otherClients(of: nil, here: 1) == nil)
        let shown = TerminalTmux.Session(name: "glass-1", attachedClients: 2, windows: 1)
        #expect(TerminalSessionInfo.otherClients(of: shown, here: 2) == 0, "both clients are panes here")
    }
}
