import Foundation
import Testing
@testable import GlassTerminal

/// W6 (2026-10-08): one rule names a terminal in a Mac's tab and in Active on every device. The
/// owner's tabs read a program's title or a project's folder while Active listed the same
/// sessions as "Terminal 1"…"Terminal 14".
@Suite("One rule names a terminal, in a tab and in Active")
struct TerminalSessionNamingTests {
    private let home = "/Users/ann"

    private func name(given: String? = nil, title: String? = nil, directory: String? = nil,
                      session: String = "glass-3") -> String {
        TerminalSessionNaming.name(given: given, title: title, directory: directory, home: home, session: session)
    }

    @Test("a given name first, then the program's title, then a folder other than home, then the session")
    func order() {
        #expect(name(given: "shop", title: "✳ Claude Code", directory: "/Users/ann/src/app") == "shop")
        #expect(name(title: "✳ Claude Code", directory: "/Users/ann/src/app") == "✳ Claude Code")
        #expect(name(directory: "/Users/ann/src/app") == "app")
        #expect(name(directory: home) == "Terminal 3", "home names nothing")
        #expect(name(directory: "/") == "Terminal 3", "nor does /")
        #expect(name() == "Terminal 3")
        #expect(name(session: "work") == "work", "a session Glass did not name is called by its own name")
        #expect(name(given: "  ", title: "vim") == "vim", "a blank given name is no name")
    }

    @Test("tmux's default title, the host name, is not a program's title")
    func hostNameIsNoTitle() {
        let hosts = ["alpha.example.com", "alpha"]
        #expect(TerminalSessionNaming.programTitle("alpha.example.com", hostNames: hosts) == nil)
        #expect(TerminalSessionNaming.programTitle("alpha", hostNames: hosts) == nil)
        #expect(TerminalSessionNaming.programTitle(" ", hostNames: hosts) == nil)
        #expect(TerminalSessionNaming.programTitle("✳ Claude Code", hostNames: hosts) == "✳ Claude Code")
    }

    @Test("a name read from tmux is held to what a tab shows: one line, no control characters, 80 at most")
    func givenNamesAreCleaned() {
        #expect(TerminalSessionNaming.displayText("build\n\tnow\u{202E}") == "build now")
        #expect(TerminalSessionNaming.displayText(" \n ") == nil)
        #expect(TerminalSessionNaming.displayText(String(repeating: "x", count: 200))?.count == 80)
        #expect(name(given: "line one\nline two") == "line one line two")
    }

    @Test("a folder is written as the tabs write it")
    func abbreviation() {
        #expect(TerminalSessionNaming.abbreviated("/Users/ann/src/app", home: home) == "~/src/app")
        #expect(TerminalSessionNaming.abbreviated(home, home: home) == "~")
        #expect(TerminalSessionNaming.abbreviated("/Users/annie", home: home) == "/Users/annie")
        #expect(TerminalSessionNaming.abbreviated("/etc", home: nil) == "/etc")
    }

    @Test("a Mac tab and Active agree: the tab's automatic name is the shared rule's")
    func tabsAgree() {
        let context = MacWorkspacePaneContext(title: nil, directory: "/Users/ann/src/shop")
        #expect(MacWorkspaceTabNaming.automaticTitle(context, home: home)
                == TerminalSessionNaming.automaticName(title: nil, directory: "/Users/ann/src/shop", home: home))
        #expect(MacWorkspaceTabNaming.tmuxDisplayName("glass-14") == name(session: "glass-14"))
    }
}
