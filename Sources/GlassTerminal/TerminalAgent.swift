//
//  TerminalAgent.swift
//  Glass Power Tools — GlassTerminal
//
//  Which AI coding agent a terminal is running (the owner, 2026-10-14: "Is there a way to detect
//  when an AI agent is running (like Claude, codex, opencode, etc.) and put a monochrome logo in the
//  center of the window in expose mode?").
//
//  Told by the program in the terminal's foreground, which the app already reads: tmux names it
//  (`#{pane_current_command}`, every tmux terminal on every device, `TerminalTmux.contextFormat`),
//  and a local terminal's process group is this Mac's own. A program run by an interpreter —
//  Codex or Gemini CLI installed with npm show as `node` — is told by the script it runs: its
//  name, or the package folder under `node_modules` it sits in. Claude Code's own title is a last
//  resort where no program is known (a terminal outside tmux on another machine).
//
//  The logos are Lobe Icons' monochrome marks (lobehub/lobe-icons, MIT; THIRD-PARTY-NOTICES), as
//  the Agency Agents app vendors them: one path each, `currentColor`, drawn here as a template so
//  they take the colour they are given. The marks are their owners' trademarks, shown to say which
//  tool is running.
//

import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

nonisolated enum TerminalAgent: String, CaseIterable, Sendable {
    case claudeCode, codex, openCode, geminiCLI, cursor, copilot, qwen, kimi
    // 2026-10-14, the owner: "we need to detect hermes, openclaw, and as many as we can... agency
    // agents installer has a good list" — its tools that run in a terminal, then others well known.
    case openClaw, hermes, mistralVibe, deepSeekHarness, zCode
    case amp, goose, cline, kiloCode, openHands, grok, kiro, trae, qoder
    case aider, crush, droid, auggie, plandex, iFlow

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openCode: "opencode"
        case .geminiCLI: "Gemini CLI"
        case .cursor: "Cursor Agent"
        case .copilot: "GitHub Copilot"
        case .qwen: "Qwen Code"
        case .kimi: "Kimi"
        case .openClaw: "OpenClaw"
        case .hermes: "Hermes Agent"
        case .mistralVibe: "Mistral Vibe"
        case .deepSeekHarness: "DeepSeek Harness"
        case .zCode: "ZCode"
        case .amp: "Amp"
        case .goose: "Goose"
        case .cline: "Cline"
        case .kiloCode: "Kilo Code"
        case .openHands: "OpenHands"
        case .grok: "Grok CLI"
        case .kiro: "Kiro"
        case .trae: "Trae Agent"
        case .qoder: "Qoder"
        case .aider: "Aider"
        case .crush: "Crush"
        case .droid: "Droid"
        case .auggie: "Auggie"
        case .plandex: "Plandex"
        case .iFlow: "iFlow CLI"
        }
    }

    /// The names a program runs as, and the package folders a script sits in.
    private static let byName: [String: TerminalAgent] = [
        "claude": .claudeCode, "claude-code": .claudeCode,
        "codex": .codex,
        "opencode": .openCode, "opencode-ai": .openCode,
        "gemini": .geminiCLI, "gemini-cli": .geminiCLI,
        "cursor-agent": .cursor,
        "copilot": .copilot,
        "qwen": .qwen, "qwen-code": .qwen,
        "kimi": .kimi, "kimi-cli": .kimi,
        "openclaw": .openClaw,
        "hermes": .hermes, "hermes-agent": .hermes, "hermes_cli": .hermes, "hermes_agent": .hermes,
        "vibe": .mistralVibe, "mistral-vibe": .mistralVibe,
        "zcode": .zCode,
        "amp": .amp,
        "goose": .goose,
        "cline": .cline,
        "kilocode": .kiloCode, "kilo": .kiloCode,
        "openhands": .openHands,
        "grok": .grok, "grok-cli": .grok,
        "kiro-cli": .kiro,
        "trae-cli": .trae, "trae-agent": .trae,
        "qodercli": .qoder,
        "aider": .aider, "aider-chat": .aider,
        "crush": .crush,
        "droid": .droid,
        "auggie": .auggie,
        "plandex": .plandex, "pdx": .plandex,
        "iflow": .iFlow,
    ]

    /// Hidden folders an agent installs itself into, so a program run from inside one is that agent
    /// whatever the program is called: Hermes Agent lives in `~/.hermes/hermes-agent` (its
    /// installer's `HERMES_HOME`), and on another machine of the owner's tmux said only `python3`
    /// (2026-10-14). A hidden folder only — a project folder called `hermes` is not Hermes.
    private static let byHome: [String: TerminalAgent] = [
        ".hermes": .hermes,
    ]

    /// Packages known only by their npm name, scope and all: `dsh` alone is also the distributed
    /// shell that runs a command on many machines, so DeepSeek Harness is told by its package.
    private static let byPackage: [String: TerminalAgent] = [
        "@deepseek-ai/dsh": .deepSeekHarness,
        "@kilocode/cli": .kiloCode,
        "@sourcegraph/amp": .amp,
        "@augmentcode/auggie": .auggie,
        "@iflow-ai/iflow-cli": .iFlow,
    ]

    /// Programs that run another program's script.
    private static let interpreters: Set<String> = ["node", "nodejs", "bun", "deno", "python", "python3"]

    /// The agent a terminal is running, or nil. `program` is the foreground program's name,
    /// `arguments` its program and script (`identifyingWords`), `title` the title it set.
    static func identify(program: String?, arguments: String?, title: String? = nil) -> TerminalAgent? {
        let name = program.map { ($0 as NSString).lastPathComponent.lowercased() }
        if let name, let agent = byName[name] { return agent }
        let words = arguments?.split(separator: " ").map(String.init) ?? []
        // The name it was run by: Claude Code's own installer runs it from a file named for its
        // version (`~/.local/share/claude/versions/2.1.296`), so tmux says `2.1.296` and the
        // command line says `claude`.
        let first = words.first.map { ($0 as NSString).lastPathComponent.lowercased() }
        if let first, let agent = byName[first] { return agent }
        if let target = launched(words)?.target, let agent = agent(for: target) { return agent }
        // The program, or the script it runs, inside an agent's own install folder.
        let paths = [words.first] + [launched(words)?.target].map { target -> String? in
            if case .script(let script)? = target { return script }
            return nil
        }
        for path in paths.compactMap({ $0 }) {
            if let agent = path.lowercased().split(separator: "/").lazy.compactMap({ byHome[String($0)] }).first {
                return agent
            }
        }
        // Claude Code names itself in its title; nothing else here does so plainly. Only where the
        // program is not known by a name of its own.
        if name.map(needsCommandLine) ?? true,
           let title, title.localizedCaseInsensitiveContains("Claude Code") {
            return .claudeCode
        }
        return nil
    }

    /// Whether `program` says too little by its name alone: an interpreter, or a file named for its
    /// version. Its command line is read then, and only then.
    static func needsCommandLine(_ program: String) -> Bool {
        let name = (program as NSString).lastPathComponent.lowercased()
        return isInterpreter(program) || shells.contains(name) || runners.contains(name) || looksLikeVersion(name)
    }

    /// `2.1.296`: digits and dots.
    static func looksLikeVersion(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }

    /// A script's agent: by its own name (`codex.js`), or by the package it is in — the folder
    /// after `node_modules`, past a scope (`node_modules/@google/gemini-cli/dist/index.js`). Not
    /// by any folder on its path: a project folder called `codex` is not Codex.
    static func agent(forScript script: String) -> TerminalAgent? {
        let components = script.split(separator: "/").map { $0.lowercased() }
        if let last = components.last {
            let stem = (last as NSString).deletingPathExtension
            if let agent = byName[stem] { return agent }
        }
        for (index, component) in components.enumerated() where component == "node_modules" {
            var next = index + 1
            if next < components.count, components[next].hasPrefix("@") {
                if next + 1 < components.count, let agent = byPackage[components[next] + "/" + components[next + 1]] {
                    return agent
                }
                next += 1
            }
            if next < components.count, let agent = byName[components[next]] { return agent }
        }
        return nil
    }

    /// The program, and for an interpreter the script it runs, from a command line — never the
    /// rest, which can hold a password or a token (`mysql -p…`): only an interpreter's next word is
    /// kept, and that is its script. Bounded; nil for nothing.
    static func identifyingWords(_ commandLine: String) -> String? {
        let words = commandLine.split(whereSeparator: \.isWhitespace).prefix(8).map { String($0.prefix(1_024)) }
        guard let program = words.first else { return nil }
        guard let kept = launched(words)?.kept else { return program }
        return words.prefix(kept).joined(separator: " ")
    }

    /// What a command line launches, as far as an agent can be told by it.
    enum Launched: Equatable {
        /// A script an interpreter or a shell runs: `node /x/codex.js`, `bash ~/.local/bin/hermes`.
        case script(String)
        /// A Python module: `python3 -m hermes_cli.main`.
        case module(String)
        /// A tool a runner fetches or finds: `uvx aider-chat`, `npx -y @deepseek-ai/dsh`, `uv run hermes`.
        case tool(String)
    }

    /// Shells, which run a script as an interpreter does: a launcher is often one
    /// (2026-10-14, Hermes Agent, whose command was not told).
    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "fish"]
    /// Programs that fetch or find a tool and run it.
    private static let runners: Set<String> = ["uv", "uvx", "pipx", "npx", "pnpx", "bunx", "pnpm", "yarn"]

    /// What `words` launch and how many of them say so — the program up to its script, module or
    /// tool, and none after: the rest can hold a secret. Inline code (`-c`, `-e`) is never kept.
    static func launched(_ words: [String]) -> (kept: Int, target: Launched)? {
        guard let program = words.first.map({ ($0 as NSString).lastPathComponent.lowercased() }) else { return nil }
        /// The first word from `start` that is not an option, skipping an option's value where it takes one.
        func operand(from start: Int, valued: Set<String> = [], code: Set<String> = []) -> Int? {
            var index = start
            while index < words.count {
                let word = words[index]
                if code.contains(word) { return nil }
                if valued.contains(word) { index += 2; continue }
                if word.hasPrefix("-") { index += 1; continue }
                return index
            }
            return nil
        }
        if program.hasPrefix("python") {
            var index = 1
            while index < words.count {
                let word = words[index]
                if word == "-m" { return index + 1 < words.count ? (index + 2, .module(words[index + 1])) : nil }
                if word == "-c" { return nil }
                if ["-X", "-W", "-Q"].contains(word) { index += 2; continue }
                if word.hasPrefix("-") { index += 1; continue }
                return (index + 1, .script(word))
            }
            return nil
        }
        if isInterpreter(program) {
            let start = program == "deno" && words.count > 1 && words[1] == "run" ? 2 : 1
            guard let index = operand(from: start, valued: ["-r", "--require", "--import", "--loader"],
                                      code: ["-e", "--eval", "-p", "--print"]) else { return nil }
            return (index + 1, .script(words[index]))
        }
        if shells.contains(program) {
            guard let index = operand(from: 1, code: ["-c"]) else { return nil }
            return (index + 1, .script(words[index]))
        }
        guard runners.contains(program) else { return nil }
        var start = 1
        switch program {
        case "uv":
            if words.count > 2, words[1] == "tool", words[2] == "run" { start = 3 }
            else if words.count > 1, words[1] == "run" { start = 2 }
            else { return nil }
        case "pipx", "pnpm", "yarn":
            guard words.count > 1, ["run", "dlx", "exec"].contains(words[1]) else { return nil }
            start = 2
        default:
            break
        }
        guard let index = operand(from: start, valued: ["--from", "--with", "-p", "--package", "--python"]) else { return nil }
        return (index + 1, .tool(words[index]))
    }

    /// The agent a launched script, module or tool is.
    static func agent(for launched: Launched) -> TerminalAgent? {
        switch launched {
        case .script(let script):
            return agent(forScript: script)
        case .module(let module):
            let root = String(module.lowercased().split(separator: ".").first ?? "")
            return byName[root] ?? byName[root.replacingOccurrences(of: "_", with: "-")]
        case .tool(let spec):
            // `@scope/name@1.2`, `name@1.2`, `name==1.2`: the package, without its version.
            var name = spec.lowercased()
            if let at = name.dropFirst().firstIndex(of: "@") { name = String(name[..<at]) }
            if let pin = name.range(of: "==") { name = String(name[..<pin.lowerBound]) }
            return byPackage[name] ?? byName[(name as NSString).lastPathComponent]
        }
    }

    /// Whether `program` runs another program's script: `node`, `bun`, `deno`, a `python`.
    static func isInterpreter(_ program: String) -> Bool {
        let name = (program as NSString).lastPathComponent.lowercased()
        return interpreters.contains(name) || name.hasPrefix("python")
    }

    /// The logo's SVG: Lobe Icons' monochrome mark, nil for an agent Lobe Icons has none for (it is
    /// marked with `fallbackSymbol`). Codex's path, and every mark added on 2026-10-14 (from Lobe
    /// Icons 1.95.1), is written out command by command:
    /// CoreSVG, which `NSImage` reads SVG with, misread a run of its compact arcs and drew a lump
    /// with a bite out of its side (the owner, 2026-10-14: "the logo for codex appears to be incorrect").
    var logoSVG: String? {
        switch self {
        case .claudeCode:
            #"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path clip-rule="evenodd" d="M20.998 10.949H24v3.102h-3v3.028h-1.487V20H18v-2.921h-1.487V20H15v-2.921H9V20H7.488v-2.921H6V20H4.487v-2.921H3V14.05H0V10.95h3V5h17.998v5.949zM6 10.949h1.488V8.102H6v2.847zm10.51 0H18V8.102h-1.49v2.847z"></path></svg>"#
        case .codex:
            #"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path clip-rule="evenodd" d="M8.086 .457a6.105 6.105 0 0 1 3.046 -.415c1.333 .153 2.521 .72 3.564 1.7a.117 .117 0 0 0 .107 .029c1.408 -.346 2.762 -.224 4.061 .366l.063 .03l.154 .076c1.357 .703 2.33 1.77 2.918 3.198c.278 .679 .418 1.388 .421 2.126a5.655 5.655 0 0 1 -.18 1.631a.167 .167 0 0 0 .04 .155a5.982 5.982 0 0 1 1.578 2.891c.385 1.901 -.01 3.615 -1.183 5.14l-.182 .22a6.063 6.063 0 0 1 -2.934 1.851a.162 .162 0 0 0 -.108 .102c-.255 .736 -.511 1.364 -.987 1.992c-1.199 1.582 -2.962 2.462 -4.948 2.451c-1.583 -.008 -2.986 -.587 -4.21 -1.736a.145 .145 0 0 0 -.14 -.032c-.518 .167 -1.04 .191 -1.604 .185a5.924 5.924 0 0 1 -2.595 -.622a6.058 6.058 0 0 1 -2.146 -1.781c-.203 -.269 -.404 -.522 -.551 -.821a7.74 7.74 0 0 1 -.495 -1.283a6.11 6.11 0 0 1 -.017 -3.064a.166 .166 0 0 0 .008 -.074a.115 .115 0 0 0 -.037 -.064a5.958 5.958 0 0 1 -1.38 -2.202a5.196 5.196 0 0 1 -.333 -1.589a6.915 6.915 0 0 1 .188 -2.132c.45 -1.484 1.309 -2.648 2.577 -3.493c.282 -.188 .55 -.334 .802 -.438c.286 -.12 .573 -.22 .861 -.304a.129 .129 0 0 0 .087 -.087A6.016 6.016 0 0 1 5.635 2.31C6.315 1.464 7.132 .846 8.086 .457zm-.804 7.85a.848 .848 0 0 0 -1.473 .842l1.694 2.965l-1.688 2.848a.849 .849 0 0 0 1.46 .864l1.94 -3.272a.849 .849 0 0 0 .007 -.854l-1.94 -3.393zm5.446 6.24a.849 .849 0 0 0 0 1.695h4.848a.849 .849 0 0 0 0 -1.696h-4.848z"></path></svg>"#
        case .openCode:
            #"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M16 6H8v12h8V6zm4 16H4V2h16v20z"></path></svg>"#
        case .geminiCLI:
            #"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M16.793 10.358v3.867L7.236 18.82v-2.8l7.751-3.728-7.75-3.728V5.763l9.556 4.595z"></path><path clip-rule="evenodd" d="M19.608 0A4.392 4.392 0 0124 4.392v15.216A4.392 4.392 0 0119.608 24H4.392A4.392 4.392 0 010 19.608V4.392A4.392 4.392 0 014.392 0h15.216zM4.26 1.444A2.816 2.816 0 001.444 4.26v15.48a2.816 2.816 0 002.816 2.816h15.48a2.816 2.816 0 002.816-2.816V4.26a2.816 2.816 0 00-2.816-2.816H4.26z"></path></svg>"#
        case .cursor:
            #"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M22.106 5.68L12.5.135a.998.998 0 00-.998 0L1.893 5.68a.84.84 0 00-.419.726v11.186c0 .3.16.577.42.727l9.607 5.547a.999.999 0 00.998 0l9.608-5.547a.84.84 0 00.42-.727V6.407a.84.84 0 00-.42-.726zm-.603 1.176L12.228 22.92c-.063.108-.228.064-.228-.061V12.34a.59.59 0 00-.295-.51l-9.11-5.26c-.107-.062-.063-.228.062-.228h18.55c.264 0 .428.286.296.514z"></path></svg>"#
        case .copilot:
            #"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M19.245 5.364c1.322 1.36 1.877 3.216 2.11 5.817.622 0 1.2.135 1.592.654l.73.964c.21.278.323.61.323.955v2.62c0 .339-.173.669-.453.868C20.239 19.602 16.157 21.5 12 21.5c-4.6 0-9.205-2.583-11.547-4.258-.28-.2-.452-.53-.453-.868v-2.62c0-.345.113-.679.321-.956l.73-.963c.392-.517.974-.654 1.593-.654l.029-.297c.25-2.446.81-4.213 2.082-5.52 2.461-2.54 5.71-2.851 7.146-2.864h.198c1.436.013 4.685.323 7.146 2.864zm-7.244 4.328c-.284 0-.613.016-.962.05-.123.447-.305.85-.57 1.108-1.05 1.023-2.316 1.18-2.994 1.18-.638 0-1.306-.13-1.851-.464-.516.165-1.012.403-1.044.996a65.882 65.882 0 00-.063 2.884l-.002.48c-.002.563-.005 1.126-.013 1.69.002.326.204.63.51.765 2.482 1.102 4.83 1.657 6.99 1.657 2.156 0 4.504-.555 6.985-1.657a.854.854 0 00.51-.766c.03-1.682.006-3.372-.076-5.053-.031-.596-.528-.83-1.046-.996-.546.333-1.212.464-1.85.464-.677 0-1.942-.157-2.993-1.18-.266-.258-.447-.661-.57-1.108-.32-.032-.64-.049-.96-.05zm-2.525 4.013c.539 0 .976.426.976.95v1.753c0 .525-.437.95-.976.95a.964.964 0 01-.976-.95v-1.752c0-.525.437-.951.976-.951zm5 0c.539 0 .976.426.976.95v1.753c0 .525-.437.95-.976.95a.964.964 0 01-.976-.95v-1.752c0-.525.437-.951.976-.951zM7.635 5.087c-1.05.102-1.935.438-2.385.906-.975 1.037-.765 3.668-.21 4.224.405.394 1.17.657 1.995.657h.09c.649-.013 1.785-.176 2.73-1.11.435-.41.705-1.433.675-2.47-.03-.834-.27-1.52-.63-1.813-.39-.336-1.275-.482-2.265-.394zm6.465.394c-.36.292-.6.98-.63 1.813-.03 1.037.24 2.06.675 2.47.968.957 2.136 1.104 2.776 1.11h.044c.825 0 1.59-.263 1.995-.657.555-.556.765-3.187-.21-4.224-.45-.468-1.335-.804-2.385-.906-.99-.088-1.875.058-2.265.394zM12 7.615c-.24 0-.525.015-.84.044.03.16.045.336.06.526l-.001.159a2.94 2.94 0 01-.014.25c.225-.022.425-.027.612-.028h.366c.187 0 .387.006.612.028-.015-.146-.015-.277-.015-.409.015-.19.03-.365.06-.526a9.29 9.29 0 00-.84-.044z"></path></svg>"#
        case .qwen:
            #"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M12.604 1.34c.393.69.784 1.382 1.174 2.075a.18.18 0 00.157.091h5.552c.174 0 .322.11.446.327l1.454 2.57c.19.337.24.478.024.837-.26.43-.513.864-.76 1.3l-.367.658c-.106.196-.223.28-.04.512l2.652 4.637c.172.301.111.494-.043.77-.437.785-.882 1.564-1.335 2.34-.159.272-.352.375-.68.37-.777-.016-1.552-.01-2.327.016a.099.099 0 00-.081.05 575.097 575.097 0 01-2.705 4.74c-.169.293-.38.363-.725.364-.997.003-2.002.004-3.017.002a.537.537 0 01-.465-.271l-1.335-2.323a.09.09 0 00-.083-.049H4.982c-.285.03-.553-.001-.805-.092l-1.603-2.77a.543.543 0 01-.002-.54l1.207-2.12a.198.198 0 000-.197 550.951 550.951 0 01-1.875-3.272l-.79-1.395c-.16-.31-.173-.496.095-.965.465-.813.927-1.625 1.387-2.436.132-.234.304-.334.584-.335a338.3 338.3 0 012.589-.001.124.124 0 00.107-.063l2.806-4.895a.488.488 0 01.422-.246c.524-.001 1.053 0 1.583-.006L11.704 1c.341-.003.724.032.9.34zm-3.432.403a.06.06 0 00-.052.03L6.254 6.788a.157.157 0 01-.135.078H3.253c-.056 0-.07.025-.041.074l5.81 10.156c.025.042.013.062-.034.063l-2.795.015a.218.218 0 00-.2.116l-1.32 2.31c-.044.078-.021.118.068.118l5.716.008c.046 0 .08.02.104.061l1.403 2.454c.046.081.092.082.139 0l5.006-8.76.783-1.382a.055.055 0 01.096 0l1.424 2.53a.122.122 0 00.107.062l2.763-.02a.04.04 0 00.035-.02.041.041 0 000-.04l-2.9-5.086a.108.108 0 010-.113l.293-.507 1.12-1.977c.024-.041.012-.062-.035-.062H9.2c-.059 0-.073-.026-.043-.077l1.434-2.505a.107.107 0 000-.114L9.225 1.774a.06.06 0 00-.053-.031zm6.29 8.02c.046 0 .058.02.034.06l-.832 1.465-2.613 4.585a.056.056 0 01-.05.029.058.058 0 01-.05-.029L8.498 9.841c-.02-.034-.01-.052.028-.054l.216-.012 6.722-.012z"></path></svg>"#
        case .kimi:
            #"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M21.846 0a1.923 1.923 0 110 3.846H20.15a.226.226 0 01-.227-.226V1.923C19.923.861 20.784 0 21.846 0z"></path><path d="M11.065 11.199l7.257-7.2c.137-.136.06-.41-.116-.41H14.3a.164.164 0 00-.117.051l-7.82 7.756c-.122.12-.302.013-.302-.179V3.82c0-.127-.083-.23-.185-.23H3.186c-.103 0-.186.103-.186.23V19.77c0 .128.083.23.186.23h2.69c.103 0 .186-.102.186-.23v-3.25c0-.069.025-.135.069-.178l2.424-2.406a.158.158 0 01.205-.023l6.484 4.772a7.677 7.677 0 003.453 1.283c.108.012.2-.095.2-.23v-3.06c0-.117-.07-.212-.164-.227a5.028 5.028 0 01-2.027-.807l-5.613-4.064c-.117-.078-.132-.279-.028-.381z"></path></svg>"#
        case .openClaw:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#a)"><path d="M9.046 7.104a.527 .527 0 1 1 0 1.055a.527 .527 0 0 1 0 -1.055z"></path><path d="M15.376 7.104a.528 .528 0 1 1 0 1.056a.528 .528 0 0 1 0 -1.056z"></path><path clip-rule="evenodd" d="M16.877 1.912c.58 -.27 1.14 -.323 1.616 -.037a.317 .317 0 0 1 -.326 .542c-.227 -.136 -.547 -.153 -1.022 .068c-.352 .165 -.765 .45 -1.234 .866c2.683 1.17 4.4 3.5 5.148 5.921a6.421 6.421 0 0 0 -.704 .184c-.578 .016 -1.174 .204 -1.502 .735c-.338 .55 -.268 1.276 .072 2.069l.005 .012l.007 .014c.523 1.045 1.318 1.91 2.2 2.284c-.912 3.274 -3.44 6.144 -5.972 6.988v2.109h-2.11v-2.11c-1.043 .417 -2.086 .01 -2.11 0v2.11h-2.11v-2.11c-2.531 -.843 -5.061 -3.713 -5.973 -6.987c.882 -.373 1.678 -1.238 2.2 -2.284l.007 -.014l.006 -.012c.34 -.793 .41 -1.518 .071 -2.069c-.327 -.531 -.923 -.719 -1.503 -.735a6.409 6.409 0 0 0 -.704 -.183c.749 -2.421 2.466 -4.751 5.149 -5.922c-.47 -.416 -.88 -.701 -1.234 -.866c-.474 -.221 -.794 -.204 -1.021 -.068a.318 .318 0 0 1 -.435 -.109a.317 .317 0 0 1 .109 -.433c.476 -.286 1.036 -.233 1.615 .037c.49 .229 1.031 .628 1.621 1.182A9.924 9.924 0 0 1 12 2.568c1.199 0 2.284 .19 3.256 .526c.59 -.554 1.13 -.953 1.62 -1.182zM8.835 6.577a1.266 1.266 0 1 0 0 2.532a1.266 1.266 0 0 0 0 -2.532zm6.33 0a1.267 1.267 0 1 0 0 2.533a1.267 1.267 0 0 0 0 -2.533z"></path><path d="M.395 13.118c-.966 -1.932 -.163 -3.863 2.41 -3.365v-.001l.05 .01c.084 .018 .17 .038 .26 .06c.033 .009 .067 .017 .1 .027c.084 .022 .168 .048 .255 .076l.09 .027c.528 0 .95 .158 1.16 .501c.212 .343 .212 .87 -.105 1.61c-.085 .17 -.178 .333 -.276 .489l-.01 .017a4.967 4.967 0 0 1 -.62 .791l-.019 .02c-1.092 1.117 -2.496 1.336 -3.295 -.262z"></path><path d="M21.193 9.753c2.574 -.5 3.378 1.433 2.411 3.365c-.58 1.159 -1.476 1.361 -2.342 .96l-.011 -.005a2.419 2.419 0 0 1 -.114 -.056l-.019 -.01a2.751 2.751 0 0 1 -.115 -.067l-.023 -.014c-.035 -.022 -.071 -.044 -.106 -.068l-.05 -.035c-.55 -.388 -1.062 -1.007 -1.44 -1.76c-.276 -.647 -.311 -1.132 -.174 -1.472c.176 -.439 .636 -.639 1.23 -.639c.032 -.011 .066 -.02 .099 -.03c.08 -.026 .16 -.05 .238 -.072l.117 -.03a5.502 5.502 0 0 1 .3 -.067z"></path></g><defs><linearGradient gradientUnits="userSpaceOnUse" id="b" x1="-.659" x2="27.023" y1=".458" y2="22.855"><stop stop-color="#FF4D4D"></stop><stop offset="1" stop-color="#991B1B"></stop></linearGradient><linearGradient gradientUnits="userSpaceOnUse" id="c" x1="-.659" x2="27.023" y1=".458" y2="22.855"><stop stop-color="#FF4D4D"></stop><stop offset="1" stop-color="#991B1B"></stop></linearGradient><linearGradient gradientUnits="userSpaceOnUse" id="d" x1="-.659" x2="27.023" y1=".458" y2="22.855"><stop stop-color="#FF4D4D"></stop><stop offset="1" stop-color="#991B1B"></stop></linearGradient><linearGradient gradientUnits="userSpaceOnUse" id="e" x1="-.659" x2="27.023" y1=".458" y2="22.855"><stop stop-color="#FF4D4D"></stop><stop offset="1" stop-color="#991B1B"></stop></linearGradient><linearGradient gradientUnits="userSpaceOnUse" id="f" x1="-.659" x2="27.023" y1=".458" y2="22.855"><stop stop-color="#FF4D4D"></stop><stop offset="1" stop-color="#991B1B"></stop></linearGradient><clipPath id="a"><path d="M0 0h24v24H0z"></path></clipPath></defs></svg>"##
        case .hermes:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M5.938 12.835c.127 -.039 .285 .02 .373 .143c.028 .038 .036 .092 .046 .14c.003 .014 -.02 .033 -.04 .05c-.124 -.098 -.24 -.194 -.354 -.291c-.011 -.01 -.016 -.027 -.025 -.042zM8.396 9.412c.195 -.032 .39 -.06 .588 -.05a.54 .54 0 0 1 .148 .026c.202 .071 .402 .147 .601 .224c.028 .01 .05 .036 .075 .055l-.013 .027a9.203 9.203 0 0 1 -.26 -.089c-.115 -.038 -.213 -.077 -.315 -.098c-.25 -.05 -.25 -.046 -.292 -.014l.574 .144c.275 .139 .55 .276 .823 .417c.042 .022 .09 .057 .107 .098c.026 .06 .063 .076 .117 .072c.066 -.006 .132 -.017 .213 -.027l-.04 .086c.051 .08 .142 .02 .216 .064c-.074 .13 -.247 .09 -.334 .199l.061 .074l-.12 .087c0 .106 -.038 .168 -.306 .243l.026 .085l-.196 .042l.07 .124h-.25l-.007 .137c-.081 -.01 -.161 -.018 -.244 -.027l-.053 .123c-.027 -.008 -.052 -.011 -.073 -.023c-.067 -.038 -.128 -.056 -.195 .006c-.019 .017 -.063 .014 -.093 .008c-.026 -.006 -.05 -.029 -.07 -.042c-.11 .095 -.11 .095 -.208 .003c-.057 .046 -.12 .074 -.186 .011c-.063 .027 -.123 -.02 -.178 -.014c-.07 .007 -.097 -.035 -.133 -.07l-.13 .033c-.013 -.236 -.194 -.19 -.34 -.203c.005 -.072 .05 -.092 .095 -.094a.474 .474 0 0 1 .159 .022c.164 .05 .32 .12 .496 .138c.203 .021 .405 .029 .601 -.015c.265 -.059 .52 -.149 .707 -.365c.049 -.056 .083 -.127 .117 -.195c.019 -.038 .02 -.084 -.02 -.116a1.397 1.397 0 0 0 -.382 -.217c.024 .12 -.031 .182 -.115 .221c0 .014 -.004 .025 0 .03c.08 .115 .084 .16 -.007 .267a1.39 1.39 0 0 1 -.218 .211a.477 .477 0 0 1 -.641 -.05a1.36 1.36 0 0 1 -.133 -.152c-.078 -.107 -.076 -.108 -.033 -.236c-.165 -.08 -.128 -.226 -.104 -.364c.008 -.05 .028 -.096 .049 -.163c-.04 .014 -.067 .017 -.087 .032a.897 .897 0 0 0 -.316 .357c-.007 .016 -.01 .034 -.02 .047c-.012 .015 -.034 .038 -.045 .035c-.02 -.006 -.037 -.027 -.05 -.045c-.008 -.012 -.007 -.032 -.012 -.057h-.126l.053 -.172a14.82 14.82 0 0 0 -.039 -.049l.11 -.284c-.06 .026 -.091 .044 -.124 .051c-.03 .007 -.064 0 -.095 0c0 -.031 -.01 -.07 .004 -.092c.149 -.22 .305 -.428 .593 -.476z"></path><path d="M8.06 10.788c-.003 -.038 -.004 -.075 .037 -.062c.016 .006 .034 .048 .028 .067c-.01 .04 -.038 .032 -.064 -.005z"></path><path clip-rule="evenodd" d="M11.981 .009c.226 -.012 .453 -.011 .679 0c.247 .01 .495 .024 .74 .062c.401 .064 .798 .157 1.19 .273c.463 .138 .92 .299 1.356 .511a7.31 7.31 0 0 1 2.948 2.642c.292 .469 .536 .963 .739 1.479c.219 .556 .446 1.11 .623 1.683c.204 .654 .329 1.326 .458 1.997c.097 .504 .182 1.01 .29 1.511c.156 .722 .329 1.44 .494 2.16c.186 .812 .4 1.615 .63 2.415c.102 .355 .193 .713 .282 1.072c.11 .436 .202 .876 .254 1.323c.031 .278 .066 .557 .073 .837a7.56 7.56 0 0 1 -.017 .88c-.037 .413 -.1 .818 -.226 1.212a5.017 5.017 0 0 1 -.915 1.649l-.13 .156l.018 .023c.043 -.023 .088 -.041 .127 -.068c.2 -.138 .373 -.307 .531 -.49c.4 -.46 .721 -.973 .975 -1.529a3.59 3.59 0 0 0 .325 -1.72c-.024 -.424 -.097 -.834 -.3 -1.213c-.013 -.027 -.015 -.06 -.03 -.121c.05 .035 .082 .048 .101 .072c.107 .13 .22 .258 .315 .398c.33 .494 .46 1.052 .486 1.64a3.75 3.75 0 0 1 -.47 1.97c-.36 .655 -.887 1.14 -1.526 1.506c-.193 .111 -.394 .21 -.595 .308c-.157 .078 -.248 .211 -.318 .365a.522 .522 0 0 0 -.033 .406a.359 .359 0 0 1 .013 .139c-.005 .077 -.077 .155 -.14 .162c-.054 .006 -.125 -.043 -.15 -.116a1.206 1.206 0 0 1 -.06 -.233c-.04 -.314 -.155 -.6 -.308 -.87a3.906 3.906 0 0 0 -.73 -.91a2.129 2.129 0 0 0 -.897 -.524a4.093 4.093 0 0 0 -.692 -.131c-.075 -.008 -.15 -.04 -.22 .01c.18 .06 .363 .11 .538 .18c.434 .173 .82 .43 1.18 .728c.308 .255 .58 .543 .794 .884c.098 .155 .186 .315 .227 .496c.027 .123 .042 .25 .067 .375c.013 .062 -.002 .109 -.053 .144c-.047 .033 -.122 .034 -.163 -.01a.455 .455 0 0 1 -.08 -.14c-.03 -.073 -.038 -.159 -.078 -.225a7.314 7.314 0 0 0 -1.423 -1.664c-.16 -.137 -.329 -.26 -.537 -.323c-.376 -.114 -.753 -.203 -1.15 -.154c-.213 .025 -.427 .032 -.64 .053a1.6 1.6 0 0 0 -.736 .278a5.14 5.14 0 0 0 -.834 .72c-.329 .342 -.642 .699 -.955 1.055c-.136 .155 -.264 .319 -.314 .531a5.227 5.227 0 0 0 -.012 .051a.096 .096 0 0 1 -.09 .076h-.31c-.046 0 -.082 -.048 -.072 -.094c.023 -.108 .045 -.216 .07 -.324c.075 -.325 .19 -.635 .368 -.917c.024 -.039 .04 -.088 .104 -.08l.01 .049l.027 .077c.28 -.435 .571 -.834 .996 -1.135c.283 -.204 .584 -.378 .89 -.55a.196 .196 0 0 0 -.098 -.002c-.162 .043 -.325 .084 -.485 .134c-.402 .124 -.764 .33 -1.11 .566c-.147 .1 -.298 .193 -.414 .333a7.314 7.314 0 0 0 -1.07 1.767a.845 .845 0 0 0 -.04 .12a.075 .075 0 0 1 -.072 .056h-.494c-.04 0 -.062 -.051 -.036 -.082c.123 -.14 .246 -.282 .377 -.415c.275 -.281 .58 -.532 .777 -.884c.027 -.048 .063 -.09 .095 -.135c.238 -.333 .54 -.607 .818 -.902c.082 -.086 .175 -.16 .26 -.24c.029 -.027 .053 -.057 .079 -.085l-.018 -.025l-.135 .041c-.034 .017 -.07 .031 -.102 .05c-.248 .144 -.494 .292 -.743 .433c-.408 .23 -.825 .439 -1.209 .711c-.281 .2 -.591 .358 -.889 .533c-.02 .012 -.044 .015 -.08 .028c-.015 -.135 .143 -.201 .108 -.336c-.033 .014 -.064 .02 -.085 .038c-.111 .096 -.227 .19 -.328 .296c-.148 .157 -.284 .325 -.425 .488c-.125 .143 -.25 .286 -.373 .431A.153 .153 0 0 1 9.89 24H8.762a.316 .316 0 0 0 .016 -.042c.028 -.09 .085 -.172 .083 -.28c-.091 -.018 -.162 .001 -.212 .077a4.45 4.45 0 0 0 -.136 .215c-.01 .016 -.024 .03 -.042 .03h-.093c-.019 0 -.029 -.022 -.017 -.037c.071 -.088 .14 -.178 .209 -.268c.001 -.002 -.006 -.012 -.012 -.024c-.014 .004 -.03 .006 -.045 .013c-.176 .09 -.352 .181 -.527 .274a.363 .363 0 0 1 -.168 .042H5.202c-.026 0 -.039 -.036 -.019 -.053c.21 -.178 .402 -.374 .558 -.605c.335 -.496 .538 -1.047 .667 -1.629c.004 -.02 -.003 -.043 -.006 -.091c-.037 .048 -.059 .072 -.076 .1a1.943 1.943 0 0 1 -.334 .415c-.28 .258 -.59 .448 -.983 .464c-.297 .012 -.588 0 -.865 -.127c-.46 -.21 -.722 -.57 -.794 -1.072c-.025 -.17 -.017 -.171 -.182 -.219A3.513 3.513 0 0 1 1.97 20.6a2.286 2.286 0 0 1 -.808 -1.13a3.569 3.569 0 0 1 -.16 -1.245c.002 -.034 .016 -.067 .024 -.1c.032 .023 .046 .043 .05 .066c.033 .153 .059 .308 .096 .46c.086 .355 .257 .664 .516 .92c.258 .256 .571 .419 .91 .532c.358 .118 .717 .138 1.07 -.016a1.89 1.89 0 0 0 .621 -.452c.328 -.348 .533 -.76 .648 -1.223c.009 -.034 .005 -.071 .007 -.11c-.015 .006 -.026 .006 -.03 .011c-.031 .05 -.064 .1 -.093 .152c-.284 .502 -.679 .887 -1.196 1.135c-.351 .17 -.718 .255 -1.11 .159a1.607 1.607 0 0 1 -.971 -.64a2.006 2.006 0 0 1 -.368 -.924a2.903 2.903 0 0 1 .02 -.886c.05 -.439 .466 -1.17 .742 -1.271c-.02 .063 -.035 .112 -.053 .16c-.043 .116 -.097 .227 -.13 .345a1.901 1.901 0 0 0 -.05 .82c.033 .212 .09 .416 .204 .6c.147 .236 .346 .407 .62 .465c.11 .023 .225 .014 .338 .018a.576 .576 0 0 0 .386 -.131c.164 -.128 .282 -.292 .366 -.481c.168 -.375 .24 -.777 .309 -1.179c.05 -.296 .093 -.594 .133 -.893c.039 -.281 .071 -.563 .104 -.845c.026 -.232 .048 -.464 .074 -.696c.024 -.228 .052 -.455 .076 -.683c.024 -.227 .047 -.455 .069 -.683c.013 -.14 .022 -.28 .034 -.42l.037 -.417c.022 -.25 .041 -.5 .065 -.748c.008 -.082 -.02 -.132 -.09 -.177a2.46 2.46 0 0 1 -.492 -.418c-.1 -.109 -.188 -.228 -.282 -.342c-.035 -.042 -.056 -.097 -.116 -.118a2.084 2.084 0 0 0 .275 .597c.06 .092 .131 .176 .196 .265c.063 .086 .182 .115 .234 .226c-.028 .003 -.046 .01 -.06 .006a4.74 4.74 0 0 1 -.22 -.057a2.71 2.71 0 0 1 -1.287 -.819c-.435 -.487 -.656 -1.076 -.71 -1.723a5.206 5.206 0 0 1 .014 -1.06c.072 -.602 .22 -1.186 .45 -1.745c.155 -.376 .338 -.741 .526 -1.102c.205 -.393 .466 -.75 .765 -1.076c.512 -.559 1.104 -1.024 1.726 -1.448c.717 -.49 1.478 -.898 2.277 -1.233C8.244 .828 8.767 .632 9.31 .494c.655 -.166 1.31 -.33 1.982 -.415c.229 -.03 .458 -.058 .688 -.07zm-1.847 22.82c-.07 .06 -.147 .111 -.207 .18c-.238 .27 -.464 .549 -.668 .869l-.044 .108a.177 .177 0 0 0 .093 -.057c.174 -.19 .351 -.378 .519 -.574c.104 -.122 .195 -.255 .288 -.386c.024 -.034 .03 -.08 .046 -.12l-.027 -.02zm1.65 -3.695a5.51 5.51 0 0 0 -.653 .593l-.37 .386a.963 .963 0 0 1 -.377 .25a1.372 1.372 0 0 1 -.467 .09c-.044 0 -.087 .006 -.151 .012c.028 .058 .043 .097 .064 .131c.15 .242 .301 .482 .45 .724c.136 .22 .276 .438 .399 .666c.068 .125 .105 .267 .156 .404c.077 .027 .14 -.018 .202 -.048c.29 -.135 .579 -.274 .867 -.412c.213 -.101 .437 -.186 .636 -.31c.347 -.215 .68 -.455 1.018 -.685c.015 -.01 .026 -.028 .042 -.046c-.023 -.019 -.038 -.037 -.056 -.044c-.287 -.111 -.527 -.3 -.77 -.482a5.319 5.319 0 0 1 -.506 -.42a1.757 1.757 0 0 1 -.41 -.653c-.019 -.049 -.045 -.095 -.075 -.156zm-5.847 .264c-.06 .096 -.097 .194 -.132 .293a3.38 3.38 0 0 1 -.555 1.01c-.2 .25 -.455 .412 -.762 .493c-.23 .06 -.464 .076 -.7 .07c-.048 -.002 -.097 .002 -.158 .005c.016 .04 .021 .066 .035 .085c.1 .145 .23 .246 .4 .295c.157 .046 .316 .034 .498 .023c.181 -.037 .343 -.115 .485 -.234c.238 -.199 .402 -.454 .536 -.732c.175 -.363 .264 -.751 .342 -1.144c.01 -.053 .008 -.11 .011 -.164zm14.945 -4.586c.008 .029 .016 .057 .027 .107c.024 .155 .051 .31 .072 .464c.03 .219 .067 .437 .078 .657c.017 .344 .027 .689 -.014 1.033c-.037 .315 -.063 .633 -.116 .946a6.153 6.153 0 0 1 -.46 1.518c-.008 .018 -.01 .039 -.02 .082c.047 -.03 .077 -.042 .098 -.064c.085 -.083 .17 -.167 .248 -.255c.271 -.305 .458 -.66 .596 -1.043c.18 -.498 .228 -1.011 .145 -1.531c-.103 -.65 -.33 -1.263 -.597 -1.881a9.055 9.055 0 0 0 -.024 -.055l-.033 .022zM5.797 8.29a.26 .26 0 0 0 .018 .153c.124 .251 .25 .501 .379 .75c.025 .049 .066 .09 .03 .163c-.284 .06 -.578 .119 -.88 .255c.059 .038 .097 .06 .132 .087c.042 .032 .112 .058 .09 .12c-.01 .033 -.075 .048 -.117 .072c.017 .01 .043 .021 .067 .036c.166 .102 .33 .207 .447 .368c.138 .192 .229 .404 .188 .644c-.079 .469 -.306 .85 -.69 1.132c-.054 .04 -.106 .083 -.161 .122a.243 .243 0 0 0 -.103 .245a.77 .77 0 0 0 .055 .195c.083 .196 .22 .35 .375 .492c.083 .076 .159 .164 .222 .257a.37 .37 0 0 1 .025 .377c-.023 .05 -.05 .099 -.076 .148c-.03 .06 -.028 .111 .022 .162c.041 .042 .08 .089 .112 .138c.038 .058 .078 .079 .147 .05a.486 .486 0 0 1 .333 -.006c.16 .046 .302 .126 .444 .21c.13 .077 .264 .149 .4 .219c.067 .035 .14 .05 .219 .026c.071 -.022 .124 .01 .145 .076c.02 .064 -.003 .108 -.074 .139c-.07 .03 -.137 .063 -.209 .088c-.1 .035 -.201 .073 -.314 .077c-.013 -.107 .11 -.088 .127 -.159c-.206 -.126 -.643 -.145 -.801 -.034c.063 .112 .035 .21 -.096 .313c-.13 -.1 -.025 -.202 .002 -.3a.209 .209 0 0 0 -.249 .17c-.015 .101 .067 .216 .178 .224c.108 .007 .218 -.005 .326 -.012c.06 -.005 .12 -.027 .199 0c-.103 .123 -.248 .127 -.357 .19c.002 .05 .07 .086 .019 .131c-.053 .048 -.095 -.001 -.132 -.03c-.08 -.063 -.16 -.126 -.231 -.197a.474 .474 0 0 1 -.157 -.311a.52 .52 0 0 0 -.043 -.172c-.032 -.074 -.032 -.137 .033 -.19c-.018 -.03 -.028 -.053 -.045 -.072a1.222 1.222 0 0 1 -.196 -.369c-.053 -.137 -.046 -.264 .048 -.381c.024 -.03 .05 -.06 .064 -.095a.664 .664 0 0 0 .047 -.168c.017 -.165 -.064 -.287 -.182 -.387c-.186 -.156 -.36 -.322 -.46 -.551c-.005 -.011 -.024 -.017 -.037 -.026c-.011 .017 -.024 .027 -.025 .038c-.019 .185 -.045 .37 -.052 .557c-.014 .377 .058 .743 .162 1.104c.118 .41 .289 .798 .488 1.173c.267 .502 .537 1.002 .812 1.5c.055 .098 .13 .189 .208 .27c.198 .202 .452 .272 .724 .273c.202 0 .404 -.006 .605 -.026c.295 -.03 .59 -.073 .884 -.113c.183 -.025 .365 -.057 .548 -.08c.21 -.026 .38 .073 .522 .21c.16 .156 .305 .327 .447 .5c.22 .265 .397 .56 .554 .867c.05 .098 .07 .1 .147 .03c.13 -.121 .26 -.242 .394 -.36c.067 -.059 .088 -.12 .067 -.213a3.535 3.535 0 0 1 -.085 -.796c.002 -.157 .006 -.314 .018 -.471c.015 -.224 .03 -.45 .06 -.672a59.114 59.114 0 0 1 .362 -2.298c.087 -.493 .182 -.984 .268 -1.477c.06 -.347 .118 -.694 .162 -1.043c.034 -.273 .055 -.55 .063 -.825c.011 -.332 .003 -.665 .002 -.998c0 -.077 .004 -.155 -.01 -.23c-.028 -.142 -.01 -.155 -.162 -.19a5.826 5.826 0 0 0 -.607 -.107c-.146 -.018 -.207 -.053 -.221 -.19c-.006 -.049 -.025 -.098 -.041 -.146c-.009 -.025 -.024 -.048 -.046 -.09l-.025 .264c-.009 .096 -.029 .116 -.127 .115c-.055 0 -.11 -.008 -.164 -.008c-.476 0 -.952 -.008 -1.426 .032c-.095 .008 -.173 -.015 -.226 -.103c-.04 -.066 -.088 -.126 -.134 -.186c-.063 -.084 -.086 -.093 -.182 -.06c-.195 .068 -.388 .138 -.582 .21a2.71 2.71 0 0 0 -.675 .394a.986 .986 0 0 1 -.323 .168c-.033 .01 -.07 .008 -.127 .013c.02 -.066 .024 -.114 .047 -.15c.064 -.105 .135 -.205 .205 -.306c.023 -.033 .049 -.063 .073 -.095l-.015 -.023l-.201 .037c-.146 .04 -.296 .07 -.437 .122c-.148 .053 -.266 .023 -.386 -.072a3.623 3.623 0 0 1 -.733 -.786l-.093 -.132zm8.592 8.963l-.147 .09c-.22 .134 -.44 .266 -.659 .402c-.093 .058 -.184 .12 -.27 .188c-.085 .07 -.124 .161 -.072 .272c.047 .1 .093 .2 .147 .294c.047 .08 .124 .138 .213 .147c.11 .01 .228 .012 .336 -.012c.217 -.05 .372 -.205 .528 -.357a.291 .291 0 0 0 .087 -.308c-.046 -.18 -.079 -.365 -.118 -.547c-.011 -.052 -.027 -.103 -.045 -.169zm-.257 -2.409c-.12 .291 -.205 .597 -.325 .91c-.151 .433 -.294 .87 -.435 1.323c.036 -.01 .054 -.01 .067 -.018c.261 -.16 .522 -.324 .785 -.484c.054 -.033 .071 -.078 .065 -.138c-.012 -.13 -.024 -.262 -.034 -.393l-.068 -.886c-.008 -.103 -.02 -.206 -.029 -.31c-.009 0 -.017 -.002 -.026 -.004zm3.081 -8.13l.099 .285c.08 .231 .159 .463 .24 .714l.58 1.952c.187 .63 .372 1.262 .558 1.893c.114 .382 .235 .762 .343 1.146c.072 .257 .126 .519 .186 .799c.044 .206 .087 .413 .127 .64c.034 .106 .023 .226 .077 .325l.025 -.006l-.068 -.362c-.038 -.206 -.077 -.412 -.113 -.638c-.015 -.07 -.029 -.141 -.046 -.211c-.095 -.396 -.177 -.796 -.29 -1.187c-.196 -.685 -.413 -1.364 -.618 -2.046c-.165 -.549 -.322 -1.1 -.488 -1.648c-.069 -.227 -.15 -.45 -.226 -.695l-.117 -.336c-.037 -.107 -.075 -.216 -.115 -.322c-.04 -.106 -.084 -.21 -.127 -.314a7.558 7.558 0 0 1 -.027 .01zM6.225 14.304c-.063 -.001 -.115 .014 -.134 .083a.35 .35 0 0 0 .41 .012a4.533 4.533 0 0 0 -.276 -.095zM5.23 11.98c-.026 -.027 -.057 -.048 -.075 .002c-.012 .032 -.007 .07 -.01 .113c.082 -.037 .082 -.037 .085 -.115zm.062 -1.189a.135 .135 0 0 0 -.088 .056a.197 .197 0 0 0 -.025 .11c.005 .152 .01 .306 .026 .457a.751 .751 0 0 0 .066 .218c.061 .136 .157 .167 .288 .101c.055 -.027 .06 -.054 .025 -.11a4.52 4.52 0 0 1 -.129 -.211c-.015 -.068 -.066 -.131 -.033 -.207c.04 -.09 -.076 -.116 -.074 -.19V10.874c-.003 -.038 -.006 -.087 -.056 -.083zm-.017 -.968a.867 .867 0 0 0 -.467 .127c-.076 .045 -.084 .07 -.05 .158c.034 .087 .07 .173 .115 .254c.064 .117 .09 .125 .21 .077a.657 .657 0 0 1 .336 -.053c.202 .022 .357 .136 .504 .264l.092 .077c.007 -.006 .014 -.013 .022 -.018c-.019 -.105 -.035 -.226 -.149 -.264c-.157 -.053 -.324 -.075 -.508 -.117l-.24 -.005c.24 -.169 .452 -.044 .687 .009c-.063 -.115 -.153 -.147 -.23 -.193c-.082 -.05 -.17 -.092 -.25 -.144c-.06 -.037 -.12 -.08 -.072 -.172zm10.233 .325c-.23 -.01 -.427 .08 -.608 .211c-.034 .026 -.06 .065 -.105 .117c.087 .026 .15 .046 .232 .065c.044 -.015 .088 -.03 .13 -.046c.306 -.114 .61 -.115 .904 .031c.126 .063 .237 .04 .366 -.005c-.02 -.031 -.03 -.054 -.045 -.071a.986 .986 0 0 0 -.448 -.273c-.14 -.044 -.284 -.024 -.426 -.03zM7.99 6.483a.308 .308 0 0 0 .002 .133c.08 .321 .156 .643 .242 .962c.104 .387 .27 .75 .456 1.103c.02 .037 .061 .08 .098 .087a.404 .404 0 0 0 .253 -.051l-.472 -.84c-.23 -.448 -.405 -.92 -.579 -1.394zM10.397 .497c-.2 -.008 -.405 .004 -.603 .034c-.236 .035 -.47 .087 -.7 .152c-.287 .08 -.569 .18 -.852 .273c-.04 .013 -.074 .038 -.11 .058c.028 .014 .05 .018 .07 .014c.287 -.068 .58 -.085 .873 -.09c.134 -.002 .269 .009 .402 .025c.19 .024 .382 .048 .57 .09c.456 .104 .874 .3 1.265 .556c.464 .306 .888 .66 1.257 1.078c.205 .232 .395 .475 .56 .739c.17 .274 .315 .561 .449 .856c.273 .601 .456 1.232 .6 1.876c.04 .173 .07 .348 .1 .524c.017 .104 .065 .167 .17 .19c.122 .028 .2 .105 .22 .251c-.003 .102 -.06 .174 -.129 .24a1.065 1.065 0 0 0 -.268 .358a.164 .164 0 0 0 .083 -.039c.08 -.086 .162 -.172 .235 -.265a.56 .56 0 0 0 .13 -.333c.009 -.05 .022 -.1 .024 -.15c.007 -.124 -.017 -.15 -.143 -.168c-.025 -.004 -.049 -.014 -.073 -.015c-.082 -.007 -.125 -.063 -.137 -.131c-.033 -.198 -.004 -.355 .247 -.408c.086 -.018 .174 -.03 .26 -.042c.158 -.023 .315 -.053 .473 -.067c.14 -.012 .19 .033 .226 .167c.008 .029 .018 .057 .021 .087c.019 .179 -.008 .225 -.141 .288c-.027 .013 -.055 .024 -.078 .042a.148 .148 0 0 0 -.051 .067c-.039 .144 .073 .382 .206 .445l.673 .32c.023 .011 .05 .015 .075 .023l.018 -.026c-.015 -.008 -.032 -.013 -.044 -.024a2.27 2.27 0 0 0 -.544 -.32a4.898 4.898 0 0 0 -.173 -.075a.203 .203 0 0 1 -.126 -.191c-.003 -.085 .045 -.154 .128 -.187l.059 -.025c.099 -.044 .118 -.076 .112 -.187a.384 .384 0 0 0 -.008 -.063c-.067 -.294 -.123 -.59 -.205 -.88a9.478 9.478 0 0 0 -.826 -2.036a7.465 7.465 0 0 0 -1.39 -1.805a4.536 4.536 0 0 0 -1.177 -.824a3.656 3.656 0 0 0 -1.016 -.328a6.155 6.155 0 0 0 -.712 -.074zm6.719 5.955c.01 .014 .018 .028 .038 .034l-.022 -.044l-.016 .01zM4.103 3.917a.062 .062 0 0 1 -.03 .012a.455 .455 0 0 1 -.04 .039c-.01 .01 -.02 .02 -.045 .04l-.363 .354c-.088 .085 -.17 .178 -.266 .253c-.284 .22 -.425 .53 -.544 .855a.132 .132 0 0 0 -.007 .071c.013 .055 .033 .108 .052 .168l.074 .026c-.017 .056 -.03 .105 -.047 .152c-.058 .164 -.118 .327 -.175 .491c-.005 .015 .008 .036 .019 .077c.08 -.175 .158 -.33 .225 -.489c.228 -.544 .484 -1.074 .819 -1.561c.09 -.133 .182 -.266 .283 -.401c.004 -.006 .007 -.013 .022 -.03c.001 -.016 .003 -.032 .015 -.04l.008 -.017zm12.976 2.408a.023 .023 0 0 1 .009 .019a.073 .073 0 0 0 -.006 .01a.188 .188 0 0 0 .007 .02l.018 .022c.002 -.007 .007 -.016 .005 -.021c-.003 -.01 -.012 -.018 -.02 -.038a1.331 1.331 0 0 1 -.013 -.012zM4.199 4.48c-.003 .004 -.008 .008 -.027 .014c-.005 .013 -.011 .025 -.031 .047a2.085 2.085 0 0 1 -.124 .167c-.048 .07 -.116 .055 -.181 .041c-.134 -.028 -.228 .016 -.287 .143c-.089 .187 -.187 .37 -.273 .56c-.049 .108 -.11 .216 -.118 .36c.081 .003 .154 .007 .228 .008h.228a2.563 2.563 0 0 1 -.079 .264c-.01 .052 -.022 .103 -.033 .155l.02 .004c.018 -.046 .037 -.092 .067 -.153c.066 -.142 .13 -.285 .2 -.426c.02 -.04 .034 -.1 .116 -.092c0 .043 .004 .084 0 .124c-.005 .045 -.017 .09 -.028 .143c.141 .043 .086 .174 .115 .269c.102 -.022 .104 -.195 .248 -.144v.205l.017 .002l.439 -1.059c-.13 0 -.246 -.02 -.358 .033c-.024 .011 -.058 -.001 -.108 -.004c.075 -.15 .139 -.278 .211 -.417a.128 .128 0 0 1 .025 -.036c0 -.015 -.001 -.03 .008 -.038l.006 -.02c-.005 .006 -.01 .011 -.028 .017c-.004 .012 -.009 .024 -.026 .045a.085 .085 0 0 1 -.032 .033c-.123 .157 -.09 .164 -.258 .106c-.079 -.027 -.078 -.028 -.047 -.144c.028 -.046 .056 -.093 .098 -.15c0 -.016 -.001 -.032 .007 -.042L4.2 4.48zm2.073 -.67c-.003 .006 -.007 .011 -.027 .016c-.094 .125 -.194 .246 -.28 .377c-.155 .238 -.301 .481 -.451 .723c-.14 .224 -.345 .368 -.575 .481c-.017 .008 -.04 .006 -.079 .011c.012 -.059 .016 -.109 .033 -.153a6.076 6.076 0 0 1 .229 -.518l-.007 -.02a.138 .138 0 0 1 -.035 .025c-.028 .05 -.055 .1 -.093 .164c-.26 .424 -.443 .817 -.442 .95c.024 .004 .048 .011 .073 .013c.177 .013 .188 .007 .26 -.165c.03 -.07 .077 -.12 .147 -.15l.175 -.07c.044 -.018 .085 -.057 .146 -.032c.003 .05 -.01 .11 .014 .145c.042 .062 .044 .125 .047 .193c.002 .049 .017 .098 .026 .147c.029 -.034 .039 -.065 .05 -.097c.142 -.39 .277 -.782 .428 -1.17c.1 -.256 .22 -.504 .33 -.756c.013 -.03 .013 -.067 .03 -.092V3.81zm3.987 -.34c0 .045 .01 .084 .021 .123c.042 .16 .094 .318 .124 .48c.024 .133 .023 .27 .028 .406c0 .033 -.019 .067 -.032 .11c-.094 -.058 -.047 -.158 -.106 -.215h-.125c-.015 .072 -.01 .152 -.046 .2c-.066 .085 -.155 .154 -.236 .227c-.043 .038 -.078 .018 -.103 -.025l-.046 -.087c-.065 .035 -.117 .069 -.172 .093c-.116 .051 -.235 .095 -.35 .147c-.085 .038 -.09 .053 -.07 .147c.014 .075 .034 .148 .047 .223c.013 .072 .05 .109 .123 .124c.233 .05 .462 .115 .657 .265c.058 -.102 .058 -.102 .168 -.151c.03 -.014 .06 -.03 .092 -.042c.08 -.03 .115 -.017 .15 .06c.023 .048 .041 .098 .066 .158c.06 -.14 -.042 -.267 .017 -.416c.157 .18 .24 .39 .375 .567a.235 .235 0 0 0 .022 -.098c.002 -.124 0 -.247 .002 -.371c0 -.034 .013 -.067 .02 -.1l.032 -.003c.11 .155 .13 .354 .226 .52a3.036 3.036 0 0 0 -.01 -.392c-.004 -.045 0 -.074 .05 -.088c.08 .036 .116 .14 .215 .158c-.03 -.275 -.423 -1.137 -.798 -1.635c-.114 -.127 -.2 -.28 -.34 -.386zm-2.667 .696c-.019 .034 -.03 .05 -.037 .067c-.061 .185 -.125 .37 -.18 .556c-.031 .105 -.087 .169 -.195 .19c-.09 .019 -.178 .052 -.268 .073c-.038 .009 -.089 .015 -.118 -.003c-.024 -.016 -.025 -.069 -.036 -.106c-.064 .076 -.082 .087 -.17 .047c-.133 -.062 -.262 -.135 -.393 -.201c-.048 -.025 -.093 -.063 -.17 -.03c-.043 .12 -.091 .25 -.137 .382c-.099 .28 -.087 .242 .095 .453c.046 .048 .102 .03 .154 .023c.054 -.009 .106 -.03 .16 -.036c.13 -.013 .26 -.08 .367 -.015c.204 -.064 .387 -.122 .571 -.178c.05 -.015 .089 .005 .114 .054c.022 .042 .034 .093 .082 .121c.038 -.056 -.013 -.128 .063 -.178l.14 .241l-.042 -1.46zm.278 .358c-.096 -.01 -.107 .01 -.11 .108c-.002 .038 -.003 .078 .002 .115c.03 .2 .099 .386 .174 .57c.002 .006 .012 .01 .022 .015l.078 -.05c.052 .036 .081 .088 .153 .088c.205 -.002 .41 .014 .616 .012c.099 -.001 .158 .042 .205 .12c.018 .03 .024 .077 .088 .066l-.08 -.394c-.05 -.195 -.085 -.395 -.172 -.589c-.057 .057 -.114 .068 -.18 .046a.72 .72 0 0 0 -.135 -.028c-.22 -.028 -.44 -.059 -.66 -.08zm10.254 -1.727c.089 .163 .155 .316 .139 .491c-.016 .168 .026 .342 -.044 .516c-.047 -.033 -.088 -.082 -.112 -.075c-.117 .035 -.164 -.057 -.227 -.115a4.772 4.772 0 0 1 -.286 -.29l-.104 -.113a4.856 4.856 0 0 1 -.023 .019c.035 .046 .07 .093 .11 .156c.04 .064 .084 .127 .122 .193c.034 .058 .065 .118 .031 .205c-.082 -.01 -.164 -.019 -.246 -.032c-.06 -.01 -.101 0 -.124 .07c-.031 .098 -.037 .096 -.15 .09c.02 .042 .036 .08 .057 .116c.041 .074 .03 .138 -.03 .196c-.06 .06 -.118 .122 -.178 .181a.175 .175 0 0 1 -.185 .046c-.222 -.061 -.447 -.113 -.67 -.174c-.032 -.009 -.063 -.04 -.086 -.068c-.03 -.04 -.052 -.087 -.08 -.13c-.044 -.07 -.09 -.138 -.136 -.207a.18 .18 0 0 0 -.014 .105c.012 .127 .03 .253 .035 .38c.005 .1 -.024 .12 -.121 .104c-.104 -.017 -.206 -.04 -.31 -.058c-.064 -.012 -.131 -.028 -.202 .03l.081 .208c.09 0 .166 -.01 .237 .002a.819 .819 0 0 1 .458 .251c.078 .083 .154 .168 .241 .26l.018 -.005c-.004 -.006 -.008 -.013 -.01 -.04c.014 -.056 -.062 -.118 .018 -.178c.031 .03 .064 .057 .088 .09c.058 .078 .111 .159 .169 .257l.089 .141l.024 -.013a2093.819 2093.819 0 0 1 -.427 -.934c.055 .007 .083 .007 .108 .016c.193 .07 .385 .142 .577 .216c.074 .028 .147 .06 .219 .094c.062 .028 .112 .018 .157 -.033c.05 -.056 .102 -.112 .154 -.167c.05 -.051 .095 -.046 .132 .014c.016 .025 .026 .053 .04 .08c.071 .138 .143 .277 .217 .433l.159 .308l.025 -.011c-.044 -.106 -.07 -.218 -.138 -.334c-.057 -.182 -.168 -.346 -.206 -.545c.136 .034 .362 .326 .567 .732l.057 .074l.018 -.011a1.563 1.563 0 0 1 -.052 -.127c-.046 -.145 -.097 -.29 -.136 -.436c-.022 -.083 -.036 -.173 .022 -.26l.109 .058l-.026 -.207l.027 -.016c.022 .02 .05 .036 .065 .06c.073 .108 .143 .22 .215 .33c.01 .016 .029 .029 .043 .043c-.036 -.217 -.2 -.38 -.229 -.626l.155 .112c.014 -.166 .012 -.319 .042 -.465c.032 -.158 -.023 -.297 -.063 -.445c.024 .004 .036 .006 .055 .025c.092 .124 .183 .249 .277 .371c.02 .027 .05 .047 .069 .087l.04 .063l.019 -.015a.293 .293 0 0 1 -.053 -.082a27.922 27.922 0 0 1 -.332 -.49c-.221 -.311 -.363 -.467 -.485 -.521zm-6.57 .327c-.003 .161 .092 .275 .069 .415l-.368 .087c.09 .139 .032 .237 -.052 .331c-.05 .057 -.092 .122 -.143 .178c-.037 .04 -.046 .078 -.018 .126l.16 .275c.029 .048 .072 .066 .128 .064c.076 -.003 .152 0 .228 -.001c.116 -.003 .216 .022 .275 .137c.006 .014 .02 .024 .044 .052c.004 -.059 -.003 -.098 .01 -.13c.016 -.04 .04 -.099 .072 -.108c.084 -.023 .173 -.024 .26 -.03c.013 -.001 .027 .018 .04 .029l.071 .065c.019 -.11 -.082 -.198 -.024 -.31l.126 .04c-.026 -.123 -.07 -.245 -.071 -.366c0 -.123 .051 -.243 .115 -.36c.107 .062 .16 .156 .234 .253c.183 .265 .36 .533 .494 .834c.165 -.078 .27 .068 .407 .088c-.003 -.106 -.133 -.441 -.197 -.492a.142 .142 0 0 0 -.102 -.028c-.06 .011 -.119 .039 -.191 .063c-.025 -.039 -.056 -.078 -.077 -.122a3.936 3.936 0 0 0 -.473 -.783c-.076 -.094 -.16 -.182 -.228 -.26l-.391 .285c-.049 .035 -.094 .03 -.132 -.017l-.169 -.207c-.025 -.03 -.053 -.059 -.097 -.108z"></path></svg>"##
        case .mistralVibe:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path clip-rule="evenodd" d="M3.428 3.4h3.429v3.428h3.429v3.429h-.002h3.431V6.828h3.427V3.4h3.43v13.714H24v3.429H13.714v-3.428h-3.428v-3.429h-3.43v3.428h3.43v3.429H0v-3.429h3.428V3.4zm10.286 13.715h3.428v-3.429h-3.427v3.429z"></path></svg>"##
        case .deepSeekHarness:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M23.748 4.482c-.254 -.124 -.364 .113 -.512 .234c-.051 .039 -.094 .09 -.137 .136c-.372 .397 -.806 .657 -1.373 .626c-.829 -.046 -1.537 .214 -2.163 .848c-.133 -.782 -.575 -1.248 -1.247 -1.548c-.352 -.156 -.708 -.311 -.955 -.65c-.172 -.241 -.219 -.51 -.305 -.774c-.055 -.16 -.11 -.323 -.293 -.35c-.2 -.031 -.278 .136 -.356 .276c-.313 .572 -.434 1.202 -.422 1.84c.027 1.436 .633 2.58 1.838 3.393c.137 .093 .172 .187 .129 .323c-.082 .28 -.18 .552 -.266 .833c-.055 .179 -.137 .217 -.329 .14a5.526 5.526 0 0 1 -1.736 -1.18c-.857 -.828 -1.631 -1.742 -2.597 -2.458a11.365 11.365 0 0 0 -.689 -.471c-.985 -.957 .13 -1.743 .388 -1.836c.27 -.098 .093 -.432 -.779 -.428c-.872 .004 -1.67 .295 -2.687 .684a3.055 3.055 0 0 1 -.465 .137a9.597 9.597 0 0 0 -2.883 -.102c-1.885 .21 -3.39 1.102 -4.497 2.623C.082 8.606 -.231 10.684 .152 12.85c.403 2.284 1.569 4.175 3.36 5.653c1.858 1.533 3.997 2.284 6.438 2.14c1.482 -.085 3.133 -.284 4.994 -1.86c.47 .234 .962 .327 1.78 .397c.63 .059 1.236 -.03 1.705 -.128c.735 -.156 .684 -.837 .419 -.961c-2.155 -1.004 -1.682 -.595 -2.113 -.926c1.096 -1.296 2.746 -2.642 3.392 -7.003c.05 -.347 .007 -.565 0 -.845c-.004 -.17 .035 -.237 .23 -.256a4.173 4.173 0 0 0 1.545 -.475c1.396 -.763 1.96 -2.015 2.093 -3.517c.02 -.23 -.004 -.467 -.247 -.588zM11.581 18c-2.089 -1.642 -3.102 -2.183 -3.52 -2.16c-.392 .024 -.321 .471 -.235 .763c.09 .288 .207 .486 .371 .739c.114 .167 .192 .416 -.113 .603c-.673 .416 -1.842 -.14 -1.897 -.167c-1.361 -.802 -2.5 -1.86 -3.301 -3.307c-.774 -1.393 -1.224 -2.887 -1.298 -4.482c-.02 -.386 .093 -.522 .477 -.592a4.696 4.696 0 0 1 1.529 -.039c2.132 .312 3.946 1.265 5.468 2.774c.868 .86 1.525 1.887 2.202 2.891c.72 1.066 1.494 2.082 2.48 2.914c.348 .292 .625 .514 .891 .677c-.802 .09 -2.14 .11 -3.054 -.614zm1 -6.44a.306 .306 0 0 1 .415 -.287a.302 .302 0 0 1 .2 .288a.306 .306 0 0 1 -.31 .307a.303 .303 0 0 1 -.304 -.308zm3.11 1.596c-.2 .081 -.399 .151 -.59 .16a1.245 1.245 0 0 1 -.798 -.254c-.274 -.23 -.47 -.358 -.552 -.758a1.73 1.73 0 0 1 .016 -.588c.07 -.327 -.008 -.537 -.239 -.727c-.187 -.156 -.426 -.199 -.688 -.199a.559 .559 0 0 1 -.254 -.078c-.11 -.054 -.2 -.19 -.114 -.358c.028 -.054 .16 -.186 .192 -.21c.356 -.202 .767 -.136 1.146 .016c.352 .144 .618 .408 1.001 .782c.391 .451 .462 .576 .685 .914c.176 .265 .336 .537 .445 .848c.067 .195 -.019 .354 -.25 .452z"></path></svg>"##
        case .zCode:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M12.105 2L9.927 4.953H.653L2.83 2h9.276zM23.254 19.048L21.078 22h-9.242l2.174 -2.952h9.244zM24 2L9.264 22H0L14.736 2H24z"></path></svg>"##
        case .amp:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M15.087 23.18L12.03 24l-2.097 -7.823l-5.738 5.738l-2.251 -2.251l5.718 -5.719l-7.769 -2.082l.82 -3.057l11.294 3.08l3.08 11.295z"></path><path d="M19.505 18.762l-3.057 .82l-2.564 -9.573l-9.572 -2.564l.819 -3.057l11.295 3.079l3.08 11.295z"></path><path d="M23.893 14.374l-3.057 .82l-2.565 -9.572L8.7 3.057L9.52 0l11.295 3.08l3.079 11.294z"></path></svg>"##
        case .goose:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M21.595 23.61c1.167 -.254 2.405 -.944 2.405 -.944l-2.167 -1.784a12.124 12.124 0 0 1 -2.695 -3.131a12.127 12.127 0 0 0 -3.97 -4.049l-.794 -.462a1.115 1.115 0 0 1 -.488 -.815a.844 .844 0 0 1 .154 -.575c.413 -.582 2.548 -3.115 2.94 -3.44c.503 -.416 1.065 -.762 1.586 -1.159c.074 -.056 .148 -.112 .221 -.17c.003 -.002 .007 -.004 .009 -.007c.167 -.131 .325 -.272 .45 -.438c.453 -.524 .563 -.988 .59 -1.193c-.061 -.197 -.244 -.639 -.753 -1.148c.319 .02 .705 .272 1.056 .569c.235 -.376 .481 -.773 .727 -1.171c.165 -.266 -.08 -.465 -.086 -.471h-.001V3.22c-.007 -.007 -.206 -.25 -.471 -.086c-.567 .35 -1.134 .702 -1.639 1.021c0 0 -.597 -.012 -1.305 .599a2.464 2.464 0 0 0 -.438 .45l-.007 .009c-.058 .072 -.114 .147 -.17 .221c-.397 .521 -.743 1.083 -1.16 1.587c-.323 .391 -2.857 2.526 -3.44 2.94a.842 .842 0 0 1 -.574 .153a1.115 1.115 0 0 1 -.815 -.488l-.462 -.794a12.123 12.123 0 0 0 -4.049 -3.97a12.133 12.133 0 0 1 -3.13 -2.695L1.332 0S.643 1.238 .39 2.405c.352 .428 1.27 1.49 2.34 2.302C1.58 4.167 .73 3.75 .06 3.4c-.103 .765 -.063 1.92 .043 2.816c.726 .317 1.961 .806 3.219 1.066c-1.006 .236 -2.11 .278 -2.961 .262c.15 .554 .358 1.119 .64 1.688c.119 .263 .25 .52 .39 .77c.452 .125 2.222 .383 3.164 .171l-2.51 .897a27.776 27.776 0 0 0 2.544 2.726c2.031 -1.092 2.494 -1.241 4.018 -2.238c-2.467 2.008 -3.108 2.828 -3.8 3.67l-.483 .678c-.25 .351 -.469 .725 -.65 1.117c-.61 1.31 -1.47 4.1 -1.47 4.1c-.154 .486 .202 .842 .674 .674c0 0 2.79 -.861 4.1 -1.47c.392 -.182 .766 -.4 1.118 -.65l.677 -.483c.227 -.187 .453 -.37 .701 -.586c0 0 1.705 2.02 3.458 3.349l.896 -2.511c-.211 .942 .046 2.712 .17 3.163c.252 .142 .509 .272 .772 .392c.569 .28 1.134 .49 1.688 .64c-.016 -.853 .026 -1.956 .261 -2.962c.26 1.258 .75 2.493 1.067 3.219c.895 .106 2.051 .146 2.816 .043a73.87 73.87 0 0 1 -1.308 -2.67c.811 1.07 1.874 1.988 2.302 2.34h-.001z"></path></svg>"##
        case .cline:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M17.035 3.991c2.75 0 4.98 2.24 4.98 5.003v1.667l1.45 2.896a1.01 1.01 0 0 1 -.002 .909l-1.448 2.864v1.668c0 2.762 -2.23 5.002 -4.98 5.002H7.074c-2.751 0 -4.98 -2.24 -4.98 -5.002V17.33l-1.48 -2.855a1.01 1.01 0 0 1 -.003 -.927l1.482 -2.887V8.994c0 -2.763 2.23 -5.003 4.98 -5.003h9.962zM8.265 9.6a2.274 2.274 0 0 0 -2.274 2.274v4.042a2.274 2.274 0 0 0 4.547 0v-4.042A2.274 2.274 0 0 0 8.265 9.6zm7.326 0a2.274 2.274 0 0 0 -2.274 2.274v4.042a2.274 2.274 0 1 0 4.548 0v-4.042A2.274 2.274 0 0 0 15.59 9.6z"></path><path d="M12.054 5.558a2.779 2.779 0 1 0 0 -5.558a2.779 2.779 0 0 0 0 5.558z"></path></svg>"##
        case .kiloCode:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M0 0v24h24V0H0zm22.222 22.222H1.778V1.778h20.444v20.444zm-7.555 -4.964h2.222v1.778h-2.794L12.89 17.83v-2.794h1.778v2.222zm4 0h-1.778v-2.222h-2.222v-1.778h2.793l1.207 1.207v2.793zm-7.556 -2.591H9.333v-1.778h1.778v1.778zm-5.778 -1.778h1.778v4h4v1.778H6.54L5.333 17.46V12.89zm13.334 -3.556v1.778h-5.778V9.333h1.987V7.111h-1.987V5.333h2.558l1.206 1.207v2.793h2.014zm-11.556 -2h2.222l1.778 1.778v2H9.333v-2H7.111v2H5.333V5.333h1.778v2zm4 0H9.333v-2h1.778v2z"></path></svg>"##
        case .openHands:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path clip-rule="evenodd" d="M4.75 5.937c.212 0 .43 .025 .63 .11c.21 .09 .382 .238 .51 .445c.022 .035 .04 .073 .059 .112c.274 -.243 .611 -.28 .877 -.28c.19 0 .382 .04 .56 .144c.177 .104 .317 .26 .42 .453c.196 .372 .267 .905 .237 1.6c-.038 .869 -.098 1.519 -.155 2.098c-.058 .58 -.112 1.078 -.143 1.66c-.047 .908 -.041 1.513 -.009 1.907c.282 -.572 .807 -1.428 1.51 -1.983c.29 -.23 .58 -.358 .862 -.379c.287 -.022 .532 .07 .716 .217c.178 .141 .296 .33 .357 .51c.054 .158 .093 .403 -.027 .61c-.193 .336 -.96 1.507 -1.314 2.695c-.316 1.06 -1.062 2.137 -1.682 2.641c-.66 .538 -1.715 .797 -2.753 .848c-1.048 .051 -2.168 -.105 -3.003 -.48C.68 18.095 .352 16.39 .232 15.828c-.116 -.544 -.114 -1.102 -.087 -1.573c.014 -.236 .035 -.457 .05 -.644c.018 -.193 .029 -.34 .029 -.452c0 -.558 -.156 -2.288 -.21 -2.902c-.038 -.446 -.004 -.845 .17 -1.148c.193 -.336 .515 -.487 .875 -.51c.184 -.013 .393 .016 .592 .104v-.435c0 -.48 .213 -.83 .485 -1.05A1.352 1.352 0 0 1 3.51 7.01a1.48 1.48 0 0 1 .255 -.591c.216 -.291 .552 -.483 .985 -.483zm2.076 1.141c-.24 0 -.342 .041 -.412 .125c-.091 .11 -.205 .383 -.205 1.05l-.001 .017v.001l-.002 .059c-.006 .28 -.037 .91 -.073 1.613l-.006 .093l-.117 2.555l-.313 .041l-1.796 .24l-.002 -.002l-2.064 .329l-.024 -.415l-.16 -2.704V10.06c0 -.35 -.106 -.516 -.195 -.597a.473 .473 0 0 0 -.347 -.114c-.168 .012 -.23 .065 -.271 .136c-.06 .102 -.108 .312 -.074 .707c.051 .585 .213 2.366 .213 2.967c0 .15 -.015 .331 -.03 .517c-.018 .192 -.037 .4 -.05 .623c-.025 .445 -.023 .924 .072 1.371c.124 .582 .4 1.908 1.742 2.51c.697 .312 1.692 .46 2.658 .413c.976 -.048 1.837 -.291 2.314 -.679c.494 -.402 1.16 -1.347 1.436 -2.273c.37 -1.24 1.147 -2.462 1.356 -2.813c-.002 -.008 -.002 -.02 -.007 -.034a.364 .364 0 0 0 -.113 -.163a.26 .26 0 0 0 -.19 -.056c-.09 .007 -.241 .053 -.452 .219c-.728 .575 -1.268 1.597 -1.442 2.037c-.032 .079 -.111 .23 -.223 .348a.62 .62 0 0 1 -.297 .181a.493 .493 0 0 1 -.481 -.15a.903 .903 0 0 1 -.194 -.383a3.145 3.145 0 0 1 -.088 -.545c-.039 -.444 -.043 -1.096 .006 -2.041c.032 -.604 .088 -1.124 .145 -1.696c.056 -.572 .114 -1.207 .151 -2.056c.029 -.654 -.049 -1.023 -.15 -1.215a.369 .369 0 0 0 -.134 -.155a.348 .348 0 0 0 -.18 -.04zm-3.878 .585a.61 .61 0 0 0 -.337 .139a.562 .562 0 0 0 -.207 .465v1.791l.133 2.267l.937 -.15V8.268c0 -.356 -.112 -.472 -.177 -.52c-.09 -.063 -.219 -.084 -.349 -.084zM4.75 6.69a.437 .437 0 0 0 -.38 .179a.856 .856 0 0 0 -.142 .501v4.698l1.057 -.14c.023 -.561 .055 -1.231 .087 -1.848l.085 -1.843c-.002 -.778 -.09 -1.161 -.207 -1.349a.345 .345 0 0 0 -.165 -.147a.866 .866 0 0 0 -.335 -.05zM19.252 5.937c.431 0 .767 .192 .983 .483c.131 .177 .213 .382 .255 .591a1.354 1.354 0 0 1 1.376 .205c.271 .222 .483 .571 .483 1.051v.435c.199 -.088 .408 -.117 .593 -.105c.36 .024 .68 .175 .874 .511c.174 .303 .209 .702 .17 1.147c-.053 .615 -.21 2.345 -.21 2.903c0 .111 .012 .26 .028 .452c.017 .187 .037 .408 .05 .644c.028 .471 .03 1.029 -.086 1.573c-.12 .562 -.448 2.267 -2.17 3.039c-.835 .374 -1.955 .53 -3.003 .479c-1.038 -.051 -2.093 -.31 -2.753 -.848c-.62 -.504 -1.366 -1.58 -1.682 -2.641c-.354 -1.187 -1.119 -2.358 -1.313 -2.695c-.12 -.207 -.081 -.452 -.027 -.61c.06 -.18 .179 -.369 .357 -.51c.184 -.146 .428 -.239 .716 -.217c.28 .021 .57 .149 .861 .379c.703 .554 1.227 1.41 1.509 1.982c.032 -.394 .039 -.999 -.008 -1.906c-.03 -.582 -.085 -1.08 -.143 -1.66a35.962 35.962 0 0 1 -.154 -2.098c-.03 -.695 .04 -1.228 .237 -1.6c.102 -.193 .242 -.349 .42 -.453c.177 -.103 .37 -.143 .56 -.143c.265 0 .6 .036 .875 .279c.02 -.039 .038 -.077 .06 -.112c.129 -.207 .3 -.355 .51 -.445c.201 -.085 .42 -.11 .631 -.11zm-2.078 1.141a.35 .35 0 0 0 -.18 .04a.37 .37 0 0 0 -.134 .155c-.101 .192 -.179 .561 -.15 1.215c.037 .85 .095 1.484 .151 2.056c.057 .572 .114 1.092 .145 1.696c.05 .945 .045 1.597 .006 2.041a3.15 3.15 0 0 1 -.088 .545a.905 .905 0 0 1 -.192 .384a.494 .494 0 0 1 -.481 .15a.621 .621 0 0 1 -.299 -.182a1.195 1.195 0 0 1 -.223 -.348c-.174 -.44 -.713 -1.462 -1.441 -2.037c-.21 -.166 -.362 -.212 -.452 -.219a.26 .26 0 0 0 -.191 .056a.365 .365 0 0 0 -.112 .163c-.005 .014 -.007 .026 -.009 .034c.21 .35 .988 1.573 1.357 2.813c.276 .926 .942 1.871 1.437 2.273c.476 .388 1.338 .631 2.314 .68c.967 .047 1.961 -.102 2.659 -.414c1.342 -.602 1.616 -1.928 1.74 -2.51c.096 -.447 .097 -.926 .072 -1.371c-.013 -.223 -.032 -.43 -.049 -.623a6.384 6.384 0 0 1 -.03 -.517c0 -.601 .161 -2.382 .212 -2.967c.034 -.395 -.015 -.605 -.073 -.707c-.04 -.07 -.104 -.124 -.272 -.136a.473 .473 0 0 0 -.347 .114c-.078 .07 -.168 .207 -.19 .474l-.005 .122v.022l-.159 2.704l-.024 .415l-2.066 -.329l-2.11 -.28l-.117 -2.554l-.005 -.093a74.933 74.933 0 0 1 -.075 -1.613l-.002 -.059v-.017c0 -.668 -.113 -.94 -.205 -1.05c-.07 -.085 -.172 -.126 -.412 -.126zm3.878 .585c-.13 0 -.258 .021 -.349 .085c-.065 .047 -.177 .163 -.177 .519v3.909l.936 .149l.134 -2.267V8.267a.563 .563 0 0 0 -.205 -.465a.614 .614 0 0 0 -.339 -.139zM19.25 6.69c-.159 0 -.264 .02 -.335 .05a.346 .346 0 0 0 -.165 .148c-.116 .188 -.205 .571 -.206 1.349l.078 1.699c.034 .655 .068 1.387 .092 1.991l1.059 .14V7.37a.857 .857 0 0 0 -.143 -.501a.438 .438 0 0 0 -.38 -.179z"></path><path d="M8.912 3.873a.377 .377 0 0 1 .513 .138l1.151 1.993a.377 .377 0 0 1 -.652 .376l-1.15 -1.993a.377 .377 0 0 1 .138 -.514zM14.555 4.011a.376 .376 0 0 1 .652 .376l-1.15 1.993a.377 .377 0 0 1 -.652 -.376l1.15 -1.993zM11.989 3c.208 0 .376 .169 .376 .377v2.3a.377 .377 0 0 1 -.753 0v-2.3c0 -.208 .169 -.377 .377 -.377z"></path></svg>"##
        case .grok:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M9.27 15.29l7.978 -5.897c.391 -.29 .95 -.177 1.137 .272c.98 2.369 .542 5.215 -1.41 7.169c-1.951 1.954 -4.667 2.382 -7.149 1.406l-2.711 1.257c3.889 2.661 8.611 2.003 11.562 -.953c2.341 -2.344 3.066 -5.539 2.388 -8.42l.006 .007c-.983 -4.232 .242 -5.924 2.75 -9.383c.06 -.082 .12 -.164 .179 -.248l-3.301 3.305v-.01L9.267 15.292M7.623 16.723c-2.792 -2.67 -2.31 -6.801 .071 -9.184c1.761 -1.763 4.647 -2.483 7.166 -1.425l2.705 -1.25a7.808 7.808 0 0 0 -1.829 -1A8.975 8.975 0 0 0 5.984 5.83c-2.533 2.536 -3.33 6.436 -1.962 9.764c1.022 2.487 -.653 4.246 -2.34 6.022c-.599 .63 -1.199 1.259 -1.682 1.925l7.62 -6.815"></path></svg>"##
        case .kiro:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M4.594 6.677C6.67 -2.226 18.746 -2.211 21.16 6.632c.353 1.297 1.725 7.582 -1.673 13.747c-1.545 2.797 -5.841 5.49 -6.99 1.883C8.6 25.477 3.315 24.1 5.789 18.609l-.318 .143c-3.57 1.305 -3.863 -1.208 -3.173 -2.513c.45 -.84 .727 -1.335 .937 -1.897c.353 -.975 .458 -1.568 .593 -2.498c.27 -1.837 .277 -3.607 .765 -5.167zm8.37 .01a.92 .92 0 0 0 -.81 .428c-.217 .323 -.33 .825 -.33 1.462c0 .705 .15 1.89 1.14 1.89h.008c.757 0 1.214 -.705 1.214 -1.89c0 -.622 -.127 -1.125 -.367 -1.455a1.014 1.014 0 0 0 -.855 -.435zm4.08 0a.92 .92 0 0 0 -.81 .428c-.217 .323 -.33 .825 -.33 1.462c0 .705 .15 1.89 1.14 1.89h.008c.757 0 1.215 -.705 1.215 -1.89c0 -.622 -.128 -1.125 -.368 -1.455a1.014 1.014 0 0 0 -.855 -.435z"></path></svg>"##
        case .trae:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M24 20.541H3.428v-3.426H0V3.4h24V20.54zM3.428 17.115h17.144V6.827H3.428v10.288zm8.573 -5.196l-2.425 2.424l-2.424 -2.424l2.424 -2.424l2.425 2.424zm6.857 -.001l-2.424 2.423l-2.425 -2.423l2.425 -2.425l2.424 2.425z"></path></svg>"##
        case .qoder:
            ##"<svg fill="currentColor" fill-rule="evenodd" height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><path d="M23.376 14.458v-4.056c0 -2.304 -1.003 -4.154 -2.748 -5.075L11.612 .574l-.046 .086l-.045 .086c1.68 .886 2.644 2.673 2.644 4.902v4.056a7.928 7.928 0 0 1 -.014 .454l-.005 .061c-.005 .081 -.01 .164 -.018 .245a4.897 4.897 0 0 1 -.011 .1l-.01 .076c-.008 .068 -.015 .135 -.025 .203l-.018 .113l-.01 .058a9.99 9.99 0 0 1 -.098 .513l-.007 .03a7.209 7.209 0 0 1 -.074 .294l-.024 .086c-.027 .099 -.056 .197 -.087 .296l-.027 .085a9.592 9.592 0 0 1 -.111 .323l-.033 .085l-.018 .046c-.032 .082 -.064 .166 -.098 .248c-.019 .048 -.04 .096 -.061 .145l-.007 .017a6 6 0 0 1 -.084 .187c-.024 .056 -.05 .11 -.077 .165c-.03 .061 -.058 .122 -.089 .182a9.423 9.423 0 0 1 -.176 .332c-.03 .056 -.062 .111 -.094 .167c-.031 .053 -.062 .108 -.095 .16c-.033 .055 -.066 .11 -.101 .164c-.033 .053 -.065 .104 -.1 .155c-.034 .055 -.07 .107 -.111 .169l-.099 .144a15.193 15.193 0 0 1 -.34 .457c-.04 .05 -.08 .102 -.121 .151l-.107 .128l-.007 .008a6.987 6.987 0 0 1 -.262 .298l-.149 .16l-.116 .12a9.562 9.562 0 0 1 -.204 .198l-.03 .03l-.072 .069a9.05 9.05 0 0 1 -.263 .235l-.025 .022l-.029 .026l-.042 .035a11.7 11.7 0 0 1 -.22 .18l-.07 .055l-.018 .013a8.904 8.904 0 0 1 -.194 .146c-.029 .02 -.057 .042 -.086 .063a7.7 7.7 0 0 1 -.22 .152l-.057 .04a8.865 8.865 0 0 1 -.293 .185l-.062 .037a10.424 10.424 0 0 1 -.307 .173l-.037 .02l-.196 .103l-.108 .052l-.012 .006a6.196 6.196 0 0 1 -.315 .143c-.065 .028 -.13 .054 -.196 .08l-.035 .014l-.086 .034c-.07 .026 -.143 .05 -.215 .075l-.039 .014l-.064 .023a8.056 8.056 0 0 1 -.323 .097l-.63 .173a7.285 7.285 0 0 1 -.33 .08l-.07 .015c-.053 .012 -.104 .023 -.157 .032l-.065 .011l-.085 .015a2.332 2.332 0 0 1 -.194 .027l-.085 .01a4.715 4.715 0 0 1 -.16 .018l-.034 .003a4.861 4.861 0 0 1 -.246 .016h-.033a2.714 2.714 0 0 1 -.155 .005h-.106a3.384 3.384 0 0 1 -.225 -.007H4.86l-.15 -.012l-.066 -.006a5.586 5.586 0 0 1 -.187 -.02l-.04 -.005a5.14 5.14 0 0 1 -.219 -.035l-.054 -.01a6.943 6.943 0 0 1 -.347 -.082l-.03 -.008l-.038 -.01a5.034 5.034 0 0 1 -.269 -.086l-.063 -.023a4.216 4.216 0 0 1 -.188 -.073l-.071 -.031l-.016 -.007a4.959 4.959 0 0 1 -.16 -.074l-.026 -.013a.164 .164 0 0 0 -.014 -.007l-.671 -.351l.486 .486h.016l8.995 4.742l.093 .048l.03 .014l.02 .01c.056 .026 .111 .052 .169 .076l.016 .008l.073 .032l.195 .076l.022 .008a.718 .718 0 0 1 .03 .012l.014 .004a4.693 4.693 0 0 0 .323 .1l.027 .007c.073 .02 .147 .038 .22 .055l.018 .004l.027 .006l.066 .013l.088 .016c.075 .014 .15 .026 .226 .038l.042 .004c.064 .009 .128 .016 .193 .022l.126 .012l.06 .003l.05 .002l.098 .005c.046 .002 .094 .002 .14 .003h.12c.05 0 .1 -.002 .161 -.005h.033l.07 -.004a6.17 6.17 0 0 0 .184 -.014l.033 -.003a.753 .753 0 0 0 .058 -.005l.108 -.012l.081 -.01l.08 -.01l.129 -.021l.082 -.014l.071 -.012c.054 -.01 .107 -.021 .16 -.033l.066 -.013l.059 -.013c.096 -.022 .192 -.046 .287 -.073l.63 -.172a7.354 7.354 0 0 0 .397 -.122l.04 -.015c.075 -.025 .149 -.051 .222 -.078c.032 -.011 .062 -.024 .093 -.037l.03 -.012c.067 -.027 .135 -.054 .2 -.082l.128 -.056l.195 -.09l.021 -.01l.102 -.05c.068 -.034 .135 -.069 .202 -.105l.037 -.02l.073 -.038c.08 -.044 .16 -.092 .24 -.139l.026 -.015a8.086 8.086 0 0 0 .322 -.2l.065 -.045l1.98 .902a1.748 1.748 0 0 0 2.472 -1.59v-7.33l.004 .004z" opacity=".5"></path><path d="M11.617 .576a3.904 3.904 0 0 0 -.093 -.047c-.016 -.009 -.033 -.016 -.05 -.024a5.854 5.854 0 0 0 -.166 -.077l-.09 -.04a4.094 4.094 0 0 0 -.194 -.074c-.017 -.006 -.035 -.015 -.053 -.02l-.013 -.005a5.18 5.18 0 0 0 -.277 -.088l-.07 -.019a4.034 4.034 0 0 0 -.219 -.053c-.015 -.003 -.03 -.008 -.044 -.012L10.253 .1l-.057 -.011a5.177 5.177 0 0 0 -.225 -.036L9.928 .047a5.972 5.972 0 0 0 -.191 -.022L9.669 .02a1.33 1.33 0 0 0 -.058 -.005L9.515 .009a4.058 4.058 0 0 0 -.111 -.005C9.354 0 9.304 0 9.254 0h-.109c-.052 0 -.106 .004 -.16 .004L8.884 .01A5.32 5.32 0 0 0 8.7 .022l-.083 .006h-.008c-.05 .005 -.1 .013 -.15 .019l-.12 .014c-.056 .008 -.112 .018 -.169 .028c-.037 .006 -.074 .011 -.11 .018a7.054 7.054 0 0 0 -.572 .133l-.63 .172c-.111 .031 -.22 .064 -.33 .1c-.037 .011 -.072 .025 -.108 .037a12.91 12.91 0 0 0 -.345 .126c-.067 .027 -.133 .054 -.2 .083l-.128 .055a11.916 11.916 0 0 0 -.318 .15a7.376 7.376 0 0 0 -.311 .163c-.082 .045 -.16 .092 -.24 .14a9.424 9.424 0 0 0 -.35 .218l-.016 .01l-.06 .04a9.242 9.242 0 0 0 -.51 .37a12.54 12.54 0 0 0 -.315 .254l-.043 .034l-.01 .007l-.045 .041c-.09 .078 -.18 .158 -.268 .24l-.106 .101c-.07 .067 -.139 .135 -.207 .204l-.056 .054l-.063 .067l-.153 .164l-.12 .133l-.148 .17c-.024 .03 -.049 .057 -.073 .086l-.043 .053a5.96 5.96 0 0 0 -.123 .155l-.118 .151c-.04 .053 -.08 .106 -.118 .16l-.075 .101l-.038 .056l-.107 .155l-.11 .164a9.91 9.91 0 0 0 -.168 .265c-.012 .02 -.023 .043 -.037 .063a12.43 12.43 0 0 0 -.192 .335l-.09 .168c-.019 .034 -.04 .07 -.057 .105c-.011 .022 -.02 .043 -.032 .065l-.092 .188l-.08 .167a19.15 19.15 0 0 0 -.083 .192c-.017 .038 -.035 .076 -.05 .115c-.008 .016 -.014 .034 -.021 .051c-.035 .083 -.067 .167 -.1 .253l-.051 .134c-.04 .11 -.077 .22 -.113 .33l-.02 .057c0 .002 0 .005 -.002 .007l-.008 .026c-.032 .1 -.06 .2 -.09 .301l-.023 .089c-.027 .1 -.052 .2 -.075 .301l-.007 .03a7.63 7.63 0 0 0 -.057 .267l-.008 .048c-.015 .074 -.026 .148 -.038 .223L.082 8.4c-.011 .078 -.02 .156 -.029 .234c-.006 .051 -.013 .103 -.017 .154a6.57 6.57 0 0 0 -.02 .26c-.003 .044 -.007 .086 -.009 .13c-.004 .128 -.007 .257 -.007 .386v4.056c0 1.478 .42 2.741 1.138 3.692A4.75 4.75 0 0 0 2.73 18.67l9.015 4.753c-1.656 -.874 -2.728 -2.685 -2.73 -5.051v-4.056c0 -.13 .004 -.26 .01 -.39c.002 -.043 .006 -.085 .01 -.128c.005 -.088 .01 -.174 .019 -.261l.017 -.155c.01 -.077 .018 -.155 .029 -.234l.026 -.164c.013 -.074 .025 -.15 .039 -.223c.02 -.105 .04 -.21 .064 -.313l.008 -.031c.023 -.1 .048 -.201 .075 -.301l.023 -.088c.028 -.1 .058 -.202 .09 -.302l.008 -.025l.021 -.063c.036 -.11 .073 -.22 .113 -.33l.052 -.134c.031 -.085 .065 -.169 .1 -.253c.022 -.056 .047 -.111 .07 -.166a13.856 13.856 0 0 1 .164 -.358c.03 -.063 .06 -.126 .092 -.188l.088 -.172a9.22 9.22 0 0 1 .187 -.338l.096 -.164c.034 -.057 .069 -.112 .104 -.168l.1 -.159a10.49 10.49 0 0 1 .567 -.786l.123 -.155l.116 -.139c.05 -.057 .098 -.115 .148 -.171a14.092 14.092 0 0 1 .272 -.297a9.706 9.706 0 0 1 .432 -.425c.088 -.083 .177 -.163 .268 -.241l.054 -.048a10.08 10.08 0 0 1 .553 -.435l.092 -.068c.075 -.053 .15 -.105 .226 -.156c.019 -.013 .038 -.028 .06 -.04a9.18 9.18 0 0 1 .362 -.227c.08 -.047 .16 -.094 .241 -.139l.11 -.058a7.643 7.643 0 0 1 .521 -.256l.126 -.056a7.509 7.509 0 0 1 .546 -.208l.107 -.037c.11 -.036 .22 -.069 .33 -.1l.63 -.172c.095 -.026 .191 -.05 .287 -.072l.097 -.02c.062 -.014 .125 -.029 .187 -.04l.114 -.018c.055 -.01 .11 -.02 .166 -.028c.04 -.006 .08 -.01 .12 -.014c.053 -.007 .105 -.014 .157 -.019l.083 -.006c.061 -.005 .123 -.01 .184 -.013c.034 -.003 .067 -.003 .101 -.004l.16 -.006h.11a3.187 3.187 0 0 1 .261 .008l.153 .01l.067 .007c.064 .006 .128 .013 .192 .022l.043 .005a5.232 5.232 0 0 1 .281 .047l.141 .03c.073 .016 .146 .035 .218 .053l.07 .019c.094 .026 .187 .055 .278 .087l.067 .025a4.326 4.326 0 0 1 .449 .19l.143 .072L11.617 .576z"></path></svg>"##
        case .aider, .crush, .droid, .auggie, .plandex, .iFlow:
            nil
        }
    }

    /// The mark as SwiftUI draws it on every platform — the iPhone, iPad and Vision Pro cannot read
    /// SVG text as the Mac does — from the module's asset catalog, as a template: the same SVG as
    /// `logoSVG` (`Resources/AgentMarks.xcassets`, held equal to it by a test).
    /// The agent's own colour, as the owner's Agency Agents app gives it (MIT): the Coding Agent
    /// look draws its mark and smoke in it, and can glow the text in it. Nil where the mark is
    /// black (Cursor, Kimi) or no colour is known: the text's colour stands in.
    @MainActor var accent: CodableColor? {
        let hex: UInt32? = switch self {
        case .claudeCode: 0xD97757
        case .codex: 0x10A37F
        case .geminiCLI: 0x4285F4
        case .copilot: 0x6E40C9
        case .qwen: 0x615CED
        case .openCode: 0xFF6B35
        case .aider: 0x8B5CF6
        case .openClaw: 0xE11D48
        case .hermes: 0x7C3AED
        case .mistralVibe: 0xFA520F
        case .zCode: 0x4263EB
        case .deepSeekHarness: 0x4D6BFE
        case .cursor, .kimi, .amp, .goose, .cline, .kiloCode, .openHands, .grok, .kiro, .trae, .qoder, .crush,
             .droid, .auggie, .plandex, .iFlow: nil
        }
        return hex.map {
            CodableColor(sRGBRed: Double($0 >> 16 & 0xFF) / 255, green: Double($0 >> 8 & 0xFF) / 255,
                         blue: Double($0 & 0xFF) / 255)
        }
    }

    var markImage: Image {
        guard logoSVG != nil else { return Image(systemName: Self.fallbackSymbol) }
        return Image(markName, bundle: Self.markBundle).renderingMode(.template)
    }

    /// An agent with no mark of its own is still marked as one: quietly, the same for each.
    static let fallbackSymbol = "sparkles"

    /// The mark's name in the asset catalog, and the bundle that holds it.
    var markName: String { "agent-\(rawValue)" }
    static var markBundle: Bundle { .module }

    #if canImport(AppKit)
    /// The logo as a template image, so it takes the colour it is drawn in.
    @MainActor var logo: NSImage? {
        if let cached = Self.logos[self] { return cached }
        let drawn = logoSVG.map { NSImage(data: Data($0.utf8)) }
            ?? NSImage(systemSymbolName: Self.fallbackSymbol, accessibilityDescription: displayName)
        guard let image = drawn else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 256, height: 256)
        image.accessibilityDescription = displayName
        Self.logos[self] = image
        return image
    }

    @MainActor private static var logos: [TerminalAgent: NSImage] = [:]
    #endif
}
