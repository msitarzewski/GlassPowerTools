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
#if canImport(AppKit)
import AppKit
#endif

nonisolated enum TerminalAgent: String, CaseIterable, Sendable {
    case claudeCode, codex, openCode, geminiCLI, cursor, copilot, qwen, kimi

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
        if let runner = name ?? first, isInterpreter(runner),
           let script = words.dropFirst().first, let agent = agent(forScript: script) {
            return agent
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
        isInterpreter(program) || looksLikeVersion((program as NSString).lastPathComponent)
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
            if next < components.count, components[next].hasPrefix("@") { next += 1 }
            if next < components.count, let agent = byName[components[next]] { return agent }
        }
        return nil
    }

    /// The program, and for an interpreter the script it runs, from a command line — never the
    /// rest, which can hold a password or a token (`mysql -p…`): only an interpreter's next word is
    /// kept, and that is its script. Bounded; nil for nothing.
    static func identifyingWords(_ commandLine: String) -> String? {
        let words = commandLine.split(whereSeparator: \.isWhitespace).prefix(2).map { String($0.prefix(1_024)) }
        guard let program = words.first else { return nil }
        return isInterpreter(program) && words.count > 1 ? program + " " + words[1] : program
    }

    /// Whether `program` runs another program's script: `node`, `bun`, `deno`, a `python`.
    static func isInterpreter(_ program: String) -> Bool {
        let name = (program as NSString).lastPathComponent.lowercased()
        return interpreters.contains(name) || name.hasPrefix("python")
    }

    /// The logo's SVG: Lobe Icons' monochrome mark. Codex's path is written out command by command:
    /// CoreSVG, which `NSImage` reads SVG with, misread a run of its compact arcs and drew a lump
    /// with a bite out of its side (the owner, 2026-10-14: "the logo for codex appears to be incorrect").
    var logoSVG: String {
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
        }
    }

    #if canImport(AppKit)
    /// The logo as a template image, so it takes the colour it is drawn in.
    @MainActor var logo: NSImage? {
        if let cached = Self.logos[self] { return cached }
        guard let image = NSImage(data: Data(logoSVG.utf8)) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 256, height: 256)
        image.accessibilityDescription = displayName
        Self.logos[self] = image
        return image
    }

    @MainActor private static var logos: [TerminalAgent: NSImage] = [:]
    #endif
}
