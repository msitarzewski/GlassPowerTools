#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// A tab row's tooltip (the owner, 2026-10-20: "Since we got rid of the bottom status for tmux,
/// let's add an Apple way to see the session info"): which tmux session, where, and what runs.
@Suite("A tab's session, in its tooltip")
struct MacWorkspaceSessionHelpTests {
    private typealias Pane = MacWorkspaceSessionHelp.Pane

    @Test("a local terminal in tmux: its session, then what runs and in which folder")
    func local() {
        let text = MacWorkspaceSessionHelp.text(
            [Pane(tmuxSession: "glass-24", program: "Codex", directory: "/Users/ann/src/shop")], home: "/Users/ann")
        #expect(text == "tmux session glass-24 on this Mac\nCodex in ~/src/shop")
    }

    @Test("an SSH terminal: the session on its machine, and how it is reached")
    func remote() {
        let text = MacWorkspaceSessionHelp.text(
            [Pane(tmuxSession: "work", machine: "alpha", connection: "ann@192.0.2.10", program: "vim", directory: nil)],
            home: "/Users/ann")
        #expect(text == "tmux session work on alpha\nann@192.0.2.10\nvim")
    }

    @Test("not in tmux says so; a split tab says each of its terminals")
    func notInTmuxAndSplit() {
        let text = MacWorkspaceSessionHelp.text(
            [Pane(tmuxSession: nil, program: nil, directory: "/Users/ann"),
             Pane(tmuxSession: "glass-3", program: "Claude Code", directory: "/opt/www")], home: "/Users/ann")
        #expect(text == "On this Mac, not in tmux\n~\n\ntmux session glass-3 on this Mac\nClaude Code in /opt/www")
        #expect(MacWorkspaceSessionHelp.text([], home: nil) == nil)
        #expect(MacWorkspaceSessionHelp.abbreviated("/Users/annabel/x", home: "/Users/ann") == "/Users/annabel/x",
                "a folder beside home is not in it")
    }
}
#endif
