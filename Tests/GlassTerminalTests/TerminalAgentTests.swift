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

    /// The owner, 2026-10-14: "the logo for codex appears to be incorrect". It was Lobe Icons'
    /// mark, but CoreSVG — what `NSImage` reads SVG with — misread one run of its compact arcs
    /// ("A/a command was given the wrong number of floats") and drew a lump with a bite out of
    /// its side. Each mark must draw the same as its path written out number by number.
    @Test("every logo draws its whole path, as the path written out in full draws")
    @MainActor func logosDrawTheirWholePath() throws {
        let pathData = try Regex(#"d="([^"]*)""#)
        for agent in TerminalAgent.allCases {
            let shipped = try Self.coverage(agent.logoSVG)
            let spaced = try Self.coverage(agent.logoSVG.replacing(pathData) { match in
                "d=\"\(Self.writtenOut(match.output[1].substring.map(String.init) ?? ""))\""
            })
            #expect(shipped.contains { $0 > 128 }, "\(agent) drew nothing")
            let differing = zip(shipped, spaced).filter { abs(Int($0) - Int($1)) > 8 }.count
            #expect(differing == 0, "\(agent): \(differing) of \(shipped.count) pixels differ from its path in full")
        }
    }

    /// The iPhone, iPad and Vision Pro draw the marks from the asset catalog (All Windows,
    /// 2026-10-14); the Mac from `logoSVG`. One drawing: each asset is that SVG, byte for byte,
    /// and each is in the compiled catalog under the name the code asks for.
    @Test("every mark is in the asset catalog, the same SVG the Mac draws")
    @MainActor func marksInTheAssetCatalog() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GlassTerminal/Resources/AgentMarks.xcassets")
        for agent in TerminalAgent.allCases {
            let file = catalog.appendingPathComponent("\(agent.markName).imageset/\(agent.markName).svg")
            #expect(try String(contentsOf: file, encoding: .utf8) == agent.logoSVG, "\(agent): the asset differs from logoSVG")
            #expect(TerminalAgent.markBundle.image(forResource: agent.markName) != nil, "\(agent): not in the compiled catalog")
        }
    }

    /// The alpha of `svg` drawn 96 points square.
    @MainActor private static func coverage(_ svg: String) throws -> [UInt8] {
        let image = try #require(NSImage(data: Data(svg.utf8)))
        let side = 96
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let bytes = try #require(bitmap.bitmapData)
        return (0..<side * side).map { bytes[$0 * 4 + 3] }
    }

    /// SVG path data with every command written out and every number on its own (SVG 1.1 §8.3.9),
    /// so nothing is left to a reader's handling of `0 01.5` or of a command's repeats.
    private static func writtenOut(_ path: String) -> String {
        let arguments: [Character: Int] = ["m": 2, "l": 2, "h": 1, "v": 1, "c": 6, "s": 4, "q": 4, "t": 2, "a": 7]
        let number = try! Regex(#"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?"#)
        var tokens: [String] = []
        var rest = Substring(path)
        while let first = rest.first {
            if first == " " || first == "," || first.isNewline { rest = rest.dropFirst(); continue }
            if first.isLetter { tokens.append(String(first)); rest = rest.dropFirst(); continue }
            guard let match = try? number.prefixMatch(in: rest) else { return path }
            tokens.append(String(match.output[0].substring ?? ""))
            rest = rest[match.range.upperBound...]
        }
        var out = "", command: Character = "M", index = 0
        while index < tokens.count {
            if let letter = tokens[index].first, letter.isLetter {
                command = letter
                index += 1
                if letter == "z" || letter == "Z" { out.append(letter); continue }
            }
            guard let count = arguments[Character(command.lowercased())] else { return path }
            var values: [String] = []
            while values.count < count, index < tokens.count {
                if command.lowercased() == "a", values.count == 3 || values.count == 4 {
                    // An arc's flag is one character, and may run into the number after it.
                    values.append(String(tokens[index].prefix(1)))
                    if tokens[index].count > 1 { tokens[index].removeFirst() } else { index += 1 }
                } else {
                    values.append(tokens[index])
                    index += 1
                }
            }
            out += "\(command)" + values.joined(separator: " ")
            if command == "m" { command = "l" } else if command == "M" { command = "L" }
        }
        return out
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
