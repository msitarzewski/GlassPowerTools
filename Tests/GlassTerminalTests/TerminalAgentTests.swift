//
//  TerminalAgentTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  Which AI agent a terminal runs (the owner, 2026-10-14: "detect when an AI agent is running
//  (like Claude, codex, opencode, etc.) and put a monochrome logo in the center of the window in
//  expose mode"): by the foreground program, an interpreter's script, or Claude Code's own title.
//

import Foundation
import Testing
@testable import GlassTerminal
#if os(macOS)
import AppKit
import GlassTerminalEmulator
#endif

@Suite("Which AI agent a terminal runs")
struct TerminalAgentTests {
    @Test("by the program's own name, as tmux or the process table says it")
    func byName() {
        let cases: [(String, TerminalAgent)] = [
            ("claude", .claudeCode), ("codex", .codex), ("opencode", .openCode), ("gemini", .geminiCLI),
            ("cursor-agent", .cursor), ("copilot", .copilot), ("qwen", .qwen), ("kimi", .kimi),
        ]
        for (program, agent) in cases {
            #expect(TerminalAgent.identify(program: program, arguments: nil) == agent, "\(program)")
        }
        #expect(TerminalAgent.identify(program: nil, arguments: "/Users/ann/.local/bin/claude --resume") == .claudeCode)
        // Claude Code's installer runs it from a file named for its version: tmux says that, and
        // the command line says `claude` (seen on the owner's Mac, 2026-10-14).
        #expect(TerminalAgent.identify(program: "2.1.296", arguments: TerminalAgent.identifyingWords("claude -c")) == .claudeCode)
        #expect(TerminalAgent.identify(program: "2.1.296", arguments: nil, title: "✳ Claude Code") == .claudeCode)
        #expect(TerminalAgent.identify(program: "2.1.296", arguments: nil) == nil)
        #expect(TerminalAgent.needsCommandLine("2.1.296") && TerminalAgent.needsCommandLine("node"))
        #expect(!TerminalAgent.needsCommandLine("vim") && !TerminalAgent.needsCommandLine("1password"))
        for program in ["zsh", "-zsh", "vim", "htop", "ssh", "tmux"] {
            #expect(TerminalAgent.identify(program: program, arguments: nil) == nil, "\(program)")
        }
    }

    @Test("a script run by node is told by its name or its package, never by a project folder's name")
    func byScript() {
        #expect(TerminalAgent.identify(program: "node", arguments: "node /opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js") == .codex)
        #expect(TerminalAgent.identify(program: "node", arguments: "node /usr/local/lib/node_modules/@google/gemini-cli/dist/index.js") == .geminiCLI)
        #expect(TerminalAgent.identify(program: "node", arguments: "node /home/ann/.npm/_npx/1a/node_modules/@qwen-code/qwen-code/cli.js") == .qwen)
        #expect(TerminalAgent.identify(program: "bun", arguments: "bun /home/ann/.bun/install/global/node_modules/opencode-ai/bin/opencode") == .openCode)
        #expect(TerminalAgent.identify(program: "node", arguments: "node /home/ann/src/codex/server.js") == nil,
                "a project called codex is not Codex")
        #expect(TerminalAgent.identify(program: "node", arguments: "node server.js") == nil)
    }

    @Test("Claude Code's own title answers only where no other program is known")
    func byTitle() {
        #expect(TerminalAgent.identify(program: nil, arguments: nil, title: "✳ Claude Code") == .claudeCode)
        #expect(TerminalAgent.identify(program: "vim", arguments: nil, title: "notes about Claude Code") == nil,
                "vim editing a file that names it is vim")
        #expect(TerminalAgent.identify(program: nil, arguments: nil, title: "build") == nil)
    }

    @Test("only an interpreter's script is kept from a command line: a program's arguments can hold a secret")
    func identifyingWords() {
        #expect(TerminalAgent.identifyingWords("node /x/codex.js --api-key sk-1") == "node /x/codex.js")
        #expect(TerminalAgent.identifyingWords("mysql -psecret db") == "mysql")
        #expect(TerminalAgent.identifyingWords("   ") == nil)
    }

    #if os(macOS)
    @Test("every logo draws, as a template that takes the colour it is given")
    @MainActor func logos() throws {
        for agent in TerminalAgent.allCases {
            let logo = try #require(agent.logo, "\(agent) did not draw")
            #expect(logo.isTemplate)
            #expect(logo.representations.contains { String(describing: type(of: $0)).contains("SVG") })
        }
    }

    @Test("this Mac's process table gives a process's command line")
    func processTable() throws {
        let line = try #require(TerminalProcessTable.commandLine(of: getpid()))
        #expect(line.contains(ProcessInfo.processInfo.arguments[0]))
        #expect(TerminalProcessTable.commandLine(of: 0) == nil)
    }

    @Test("Show All Windows marks a tmux session no window shows with its agent")
    @MainActor func exposeTile() throws {
        let sessions = [TerminalTmux.Session(name: "glass-3", attachedClients: 0, windows: 1, lastActivity: nil, command: "claude"),
                        TerminalTmux.Session(name: "glass-4", attachedClients: 0, windows: 1, lastActivity: nil, command: "zsh")]
        let group = try #require(MacTerminalExposeModel.notInAWindowGroup(sessions))
        #expect(group.tiles.map(\.agent) == [.claudeCode, nil])
    }
    #endif
}
