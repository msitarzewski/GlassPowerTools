//
//  CommandSpecs.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06), source 6, "Common tools": what the word being typed at a shell prompt can be,
//  from the subcommands, options and argument kinds of about sixty common command-line tools.
//  `tasks/2026-11/2026-11-06_type-ahead.md`.
//
//  The data is `Resources/CommandSpecs.json`, written for this app from each tool's own manual, `--help` output or
//  official documentation; no other project's completion data. Its shape:
//
//  - A tool (and each subcommand, recursively): `name`, `aliases`, `description`, `args` (positional arguments by
//    kind; the last one repeats, so `["remote", "branch"]` reads `git push origin main next`), `afterDashDash`
//    (the kind of every word after `--`), `options` and `subcommands`.
//  - An argument: a kind's name, or `{"kind", "values", "description"}` when it is one of a fixed list
//    (`kubectl get pods`).
//  - An option: `names` (`["-b", "--branch"]`, the short one first), `description`, `takes` (the kind of its
//    value, absent for a flag), `values` (a fixed list), `optionalValue` (the value only ever comes as
//    `--name=value`, so the next word is not it), `persistent` (it holds in every subcommand below too, as
//    `kubectl -n`).
//
//  The reader splits the line as a POSIX shell would (quotes, backslashes, `;` `&&` `||` `|` `&`, redirections,
//  `$(…)`, backquotes and subshells), takes the last simple command, steps over assignments, reserved words and
//  command runners (`sudo`, `env`, `time`, `xargs`, `nohup`, `watch`, `ssh host …`, `find -exec`), and walks that
//  command's spec word by word.
//

import Foundation
import os

/// What an argument is, for the sources that know such things (the folder, the library, history) to fill.
nonisolated enum CommandArgumentKind: String, Codable, Sendable {
    case branch, remote, tag, file, folder, host, user, script, target, container, image, service, process,
         package, command, url, value, none
}

/// A whole word the spec knows (a subcommand, an option or one of a fixed list of values) and what it does.
nonisolated struct CommandSpecCandidate: Equatable, Sendable {
    let word: String
    let description: String
}

/// What the word being typed can be.
nonisolated struct CommandSpecCompletion: Equatable, Sendable {
    /// The word being typed, as the shell will read it so far: quotes and backslashes removed, empty right after a
    /// space. For `--name=val` it is the part after `=`, which is what the candidates complete.
    let wordPrefix: String
    /// Whole words the spec knows that start with it (subcommands, options or fixed values), most common first, with
    /// descriptions.
    let candidates: [CommandSpecCandidate]
    /// When the word is an argument, its kind, for other sources to fill: `.command` where the rest of the line is a
    /// command of its own (`sudo `), `.none` where the spec says nothing goes here. `nil` where only a subcommand or
    /// an option can.
    let argumentKind: CommandArgumentKind?
}

/// The common tools' data and the reading of a typed line against it.
nonisolated enum CommandSpecs {
    /// The tools described, by name and alias.
    static var commandNames: Set<String> { library.names }

    /// What the last word of `line` can be; `nil` when the line's command isn't described, when the word being typed
    /// is the command's own name, or inside a comment. Handles quotes, `sudo`/`env`/`time` prefixes, `;` `&&` `||`
    /// `|` (only the last command counts), options that take values, and nested subcommands.
    static func completion(forLine line: String) -> CommandSpecCompletion? {
        library.completion(forLine: line)
    }

    /// The bundled data file.
    static var resourceURL: URL? { Bundle.module.url(forResource: "CommandSpecs", withExtension: "json") }

    /// Read once, on first use, by whichever thread gets there first (a `static let` is initialized exactly once).
    static let loaded: Result<CommandSpecLibrary, any Error> = {
        let result = Result { () throws -> CommandSpecLibrary in
            guard let url = resourceURL else { throw CommandSpecLibrary.LoadError.missingResource }
            return try CommandSpecLibrary(data: Data(contentsOf: url))
        }
        if case .failure(let error) = result {
            // A build defect, not a user's problem: the terminal still works, without this source's suggestions.
            logger.fault("Common tools' data didn't load: \(String(describing: error), privacy: .public)")
        }
        return result
    }()

    static var library: CommandSpecLibrary { (try? loaded.get()) ?? CommandSpecLibrary(commands: []) }

    private static let logger = Logger(subsystem: "sh.glas", category: "type-ahead")
}

// MARK: - The data

/// A tool or one of its subcommands.
nonisolated struct CommandSpec: Decodable, Sendable {
    let name: String
    let aliases: [String]
    let description: String
    let args: [CommandArgumentSpec]
    let afterDashDash: CommandArgumentKind?
    let options: [CommandOptionSpec]
    let subcommands: [CommandSpec]

    private enum CodingKeys: String, CodingKey {
        case name, aliases, description, args, afterDashDash, options, subcommands
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        description = try container.decode(String.self, forKey: .description)
        args = try container.decodeIfPresent([CommandArgumentSpec].self, forKey: .args) ?? []
        afterDashDash = try container.decodeIfPresent(CommandArgumentKind.self, forKey: .afterDashDash)
        options = try container.decodeIfPresent([CommandOptionSpec].self, forKey: .options) ?? []
        subcommands = try container.decodeIfPresent([CommandSpec].self, forKey: .subcommands) ?? []
    }

    func subcommand(named word: String) -> CommandSpec? {
        subcommands.first { $0.name == word || $0.aliases.contains(word) }
    }

    /// The positional argument at `index`, counting from 0 after the subcommand; the last declared one repeats.
    func argument(at index: Int, afterDashDash: Bool) -> CommandArgumentSpec? {
        if afterDashDash, let kind = self.afterDashDash { return CommandArgumentSpec(kind: kind) }
        return args.isEmpty ? nil : args[min(index, args.count - 1)]
    }
}

/// A positional argument: its kind, and the words it can be when they are a fixed list.
nonisolated struct CommandArgumentSpec: Decodable, Sendable {
    let kind: CommandArgumentKind
    let values: [String]
    let description: String

    init(kind: CommandArgumentKind, values: [String] = [], description: String = "") {
        self.kind = kind
        self.values = values
        self.description = description
    }

    private enum CodingKeys: String, CodingKey { case kind, values, description }

    /// Either a kind's name (`"branch"`) or `{"kind": "value", "values": […], "description": "…"}`.
    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            guard let kind = CommandArgumentKind(rawValue: name) else {
                throw DecodingError.dataCorruptedError(in: single, debugDescription: "Unknown argument kind \(name)")
            }
            self.init(kind: kind)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try container.decode(CommandArgumentKind.self, forKey: .kind),
                  values: try container.decodeIfPresent([String].self, forKey: .values) ?? [],
                  description: try container.decodeIfPresent(String.self, forKey: .description) ?? "")
    }
}

/// An option, under all its names.
nonisolated struct CommandOptionSpec: Decodable, Sendable {
    let names: [String]
    let description: String
    /// The kind of value it takes; `nil` for a flag.
    let takes: CommandArgumentKind?
    let values: [String]
    /// The value only comes attached (`--color=always`), so the next word is not the option's.
    let optionalValue: Bool
    /// It holds in every subcommand below the one that declares it.
    let persistent: Bool

    private enum CodingKeys: String, CodingKey { case names, description, takes, values, optionalValue, persistent }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        names = try container.decode([String].self, forKey: .names)
        guard !names.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .names, in: container, debugDescription: "An option without a name")
        }
        description = try container.decode(String.self, forKey: .description)
        takes = try container.decodeIfPresent(CommandArgumentKind.self, forKey: .takes)
        values = try container.decodeIfPresent([String].self, forKey: .values) ?? []
        optionalValue = try container.decodeIfPresent(Bool.self, forKey: .optionalValue) ?? false
        persistent = try container.decodeIfPresent(Bool.self, forKey: .persistent) ?? false
    }

    /// Whether the word after it is its value.
    var consumesNextWord: Bool { takes != nil && !optionalValue }
}

/// The tools, found by name or alias.
nonisolated struct CommandSpecLibrary: Sendable {
    enum LoadError: Error { case missingResource }

    let commands: [CommandSpec]
    let names: Set<String>
    private let byName: [String: Int]

    init(commands: [CommandSpec]) {
        self.commands = commands
        var byName: [String: Int] = [:]
        for (index, command) in commands.enumerated() {
            for name in [command.name] + command.aliases where byName[name] == nil { byName[name] = index }
        }
        self.byName = byName
        names = Set(byName.keys)
    }

    init(data: Data) throws {
        struct File: Decodable { let commands: [CommandSpec] }
        try self.init(commands: JSONDecoder().decode(File.self, from: data).commands)
    }

    func command(named name: String) -> CommandSpec? { byName[name].map { commands[$0] } }
}

// MARK: - Reading a line against the data

nonisolated extension CommandSpecLibrary {
    func completion(forLine line: String) -> CommandSpecCompletion? {
        guard let typed = CommandSpecLineReader.lastCommand(in: line),
              !typed.current.unicodeScalars.contains(CommandSpecLineReader.substitution) else { return nil }
        return completion(words: typed.words[...], current: typed.current,
                          currentIsRedirectTarget: typed.currentIsRedirectTarget)
    }

    /// Words that begin where a command can: assignments, reserved words and the command's name come first.
    private func completion(words: ArraySlice<String>, current: String,
                            currentIsRedirectTarget: Bool) -> CommandSpecCompletion? {
        var start = words.startIndex
        while start < words.endIndex, Self.leadsCommand(words[start]) { start += 1 }
        guard start < words.endIndex else { return nil }  // the word being typed is the command's name
        let name = words[start].split(separator: "/").last.map(String.init) ?? words[start]
        guard let spec = command(named: name) else { return nil }
        if currentIsRedirectTarget { return CommandSpecCompletion(wordPrefix: current, candidates: [], argumentKind: .file) }
        return walk(spec, words: words[(start + 1)...], current: current)
    }

    /// Follows `words` through the spec's subcommands and options, then says what `current` can be.
    private func walk(_ spec: CommandSpec, words: ArraySlice<String>, current: String) -> CommandSpecCompletion? {
        var node = spec
        var inherited: [CommandOptionSpec] = []
        var positional = 0
        var afterDashDash = false
        var awaitingValue: CommandOptionSpec?
        var usedFlags = Set<String>()

        var index = words.startIndex
        while index < words.endIndex {
            let word = words[index]
            index += 1
            if let option = awaitingValue {
                awaitingValue = nil
                // `find -exec grep …`: the option's value is a command, and so is everything after it.
                if option.takes == .command { return completion(words: words[(index - 1)...], current: current, currentIsRedirectTarget: false) }
                continue
            }
            if !afterDashDash {
                if word == "--" {
                    afterDashDash = true
                    if node.afterDashDash == .command { return completion(words: words[index...], current: current, currentIsRedirectTarget: false) }
                    continue
                }
                let options = Self.activeOptions(node, inherited)
                if let given = Self.readOption(word, among: options) {
                    usedFlags.formUnion(given.flags)
                    awaitingValue = given.awaitingValue
                    continue
                }
            }
            if positional == 0, !afterDashDash, let subcommand = node.subcommand(named: word) {
                inherited += node.options.filter(\.persistent)
                node = subcommand
                continue
            }
            if node.argument(at: positional, afterDashDash: afterDashDash)?.kind == .command {
                return completion(words: words[(index - 1)...], current: current, currentIsRedirectTarget: false)
            }
            positional += 1
        }

        if let option = awaitingValue {
            if option.takes == .command { return commandNameCompletion(current) }
            return CommandSpecCompletion(wordPrefix: current, candidates: Self.values(of: option, startingWith: current),
                                         argumentKind: option.takes)
        }

        let options = Self.activeOptions(node, inherited)
        if !afterDashDash, Self.isOptionWord(current, among: options, typing: true) {
            if let equals = current.firstIndex(of: "="),
               let option = Self.option(named: String(current[..<equals]), among: options), option.takes != nil {
                let value = String(current[current.index(after: equals)...])
                return CommandSpecCompletion(wordPrefix: value, candidates: Self.values(of: option, startingWith: value),
                                             argumentKind: option.takes)
            }
            let candidates = options.compactMap { option -> CommandSpecCandidate? in
                guard option.takes != nil || !usedFlags.contains(option.names[0]),
                      let name = option.names.first(where: { $0.hasPrefix(current) }) else { return nil }
                return CommandSpecCandidate(word: name, description: option.description)
            }
            return CommandSpecCompletion(wordPrefix: current, candidates: candidates, argumentKind: nil)
        }

        let argument = node.argument(at: positional, afterDashDash: afterDashDash)
        if argument?.kind == .command { return commandNameCompletion(current) }
        var candidates: [CommandSpecCandidate] = []
        if positional == 0, !afterDashDash {
            candidates = node.subcommands.filter { $0.name.hasPrefix(current) }
                .map { CommandSpecCandidate(word: $0.name, description: $0.description) }
        }
        if let argument {
            candidates += argument.values.filter { $0.hasPrefix(current) }
                .map { CommandSpecCandidate(word: $0, description: argument.description) }
        }
        // No declared argument: where a subcommand can go, only a subcommand can; anywhere else, nothing can.
        let subcommandOnly = positional == 0 && !afterDashDash && !node.subcommands.isEmpty
        let kind = argument?.kind ?? (subcommandOnly ? nil : CommandArgumentKind.none)
        return CommandSpecCompletion(wordPrefix: current, candidates: candidates, argumentKind: kind)
    }

    /// The word being typed names a command (`sudo sys`): the described tools that start with it.
    private func commandNameCompletion(_ current: String) -> CommandSpecCompletion {
        let candidates = commands.flatMap { command in
            ([command.name] + command.aliases).filter { $0.hasPrefix(current) }
                .map { CommandSpecCandidate(word: $0, description: command.description) }
        }
        return CommandSpecCompletion(wordPrefix: current, candidates: candidates, argumentKind: .command)
    }

    /// The node's own options, then those its ancestors pass down that it doesn't declare itself.
    private static func activeOptions(_ node: CommandSpec, _ inherited: [CommandOptionSpec]) -> [CommandOptionSpec] {
        guard !inherited.isEmpty else { return node.options }
        let own = Set(node.options.flatMap(\.names))
        return node.options + inherited.filter { !$0.names.contains(where: own.contains) }
    }

    private static func option(named name: String, among options: [CommandOptionSpec]) -> CommandOptionSpec? {
        options.first { $0.names.contains(name) }
    }

    private static func values(of option: CommandOptionSpec, startingWith prefix: String) -> [CommandSpecCandidate] {
        option.values.filter { $0.hasPrefix(prefix) }.map { CommandSpecCandidate(word: $0, description: option.description) }
    }

    /// Options start with `-` (a lone `-` is a file name, standard input, unless it is being typed); `+` too for the
    /// few tools that have such options (`dig +short`, `less +F`).
    private static func isOptionWord(_ word: String, among options: [CommandOptionSpec], typing: Bool) -> Bool {
        if word.hasPrefix("-") { return typing || word.count > 1 }
        guard word.hasPrefix("+") else { return false }
        return options.contains { $0.names.contains { $0.hasPrefix("+") } }
    }

    /// A finished option word: the flags it sets and the option whose value comes next, if any. `nil` when it isn't
    /// an option word. An unknown option is still one; it is taken to have no value of its own.
    private static func readOption(_ word: String,
                                   among options: [CommandOptionSpec]) -> (flags: [String], awaitingValue: CommandOptionSpec?)? {
        guard isOptionWord(word, among: options, typing: false) else { return nil }
        if let option = option(named: word, among: options) {
            return option.consumesNextWord ? ([], option) : (option.takes == nil ? [option.names[0]] : [], nil)
        }
        if let equals = word.firstIndex(of: "="), option(named: String(word[..<equals]), among: options) != nil {
            return ([], nil)  // `--output=json`, `-count=1`: the value is attached
        }
        // Bundled short options: `-xzf archive`, `-n5`. Each letter must be a known one-letter option; the first that
        // takes a value takes the rest of the word, or the next word when it is the last letter.
        guard word.hasPrefix("-"), !word.hasPrefix("--"), word.count > 2 else { return ([], nil) }
        var flags: [String] = []
        let letters = Array(word.dropFirst())
        for (position, letter) in letters.enumerated() {
            guard let option = option(named: "-\(letter)", among: options) else { return ([], nil) }
            if option.takes != nil {
                return (flags, position == letters.count - 1 && option.consumesNextWord ? option : nil)
            }
            flags.append(option.names[0])
        }
        return (flags, nil)
    }

    /// Words that may come before a command's name without being it.
    private static func leadsCommand(_ word: String) -> Bool {
        if reservedWords.contains(word) { return true }
        // An assignment: `NAME=value` or `NAME+=value`.
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        var name = word[..<equals]
        if name.hasSuffix("+") { name = name.dropLast() }
        func isLetter(_ s: Unicode.Scalar) -> Bool { s == "_" || ("a"..."z").contains(s) || ("A"..."Z").contains(s) }
        guard let first = name.unicodeScalars.first, isLetter(first) else { return false }
        return name.unicodeScalars.allSatisfy { isLetter($0) || ("0"..."9").contains($0) }
    }

    private static let reservedWords: Set<String> = [
        "!", "{", "if", "then", "else", "elif", "do", "while", "until", "command", "builtin", "exec", "nocorrect", "noglob",
    ]
}

// MARK: - Splitting a line as a shell would

/// The last simple command of a typed line: its finished words and the word being typed, with quoting removed.
nonisolated enum CommandSpecLineReader {
    struct TypedCommand: Equatable {
        var words: [String]
        var current: String
        /// The word being typed follows `>`, `<` or another redirection, so it names a file.
        var currentIsRedirectTarget: Bool
    }

    /// Stands in for the output of a `$(…)`, backquoted or parenthesized part in the word around it.
    static let substitution: Unicode.Scalar = "\u{FFFC}"

    private enum Quote { case none, single, double, dollarSingle }
    private enum Closer { case end, parenthesis, backquote }

    /// One level of nesting: the line itself, or an open `$(`, `(`, `<(` or backquote.
    private struct Frame {
        let closer: Closer
        var quote = Quote.none
        var words: [String] = []
        var word: String.UnicodeScalarView?
        var wordIsRedirectTarget = false
        var nextIsRedirectTarget = false

        init(closer: Closer) { self.closer = closer }

        mutating func beginWord() {
            guard word == nil else { return }
            word = String.UnicodeScalarView()
            wordIsRedirectTarget = nextIsRedirectTarget
            nextIsRedirectTarget = false
        }

        mutating func append(_ scalar: Unicode.Scalar) {
            beginWord()
            word?.append(scalar)
        }

        mutating func endWord() {
            guard let finished = word else { return }
            if !wordIsRedirectTarget { words.append(String(finished)) }
            word = nil
            wordIsRedirectTarget = false
        }

        mutating func endCommand() {
            endWord()
            words.removeAll()
            nextIsRedirectTarget = false
        }
    }

    /// `nil` when the line ends inside a comment.
    static func lastCommand(in line: String) -> TypedCommand? {
        let scalars = Array(line.unicodeScalars)
        var stack = [Frame(closer: .end)]
        var i = 0
        func next(_ offset: Int = 1) -> Unicode.Scalar? { i + offset < scalars.count ? scalars[i + offset] : nil }
        func open(_ closer: Closer) {
            stack[stack.count - 1].beginWord()
            stack.append(Frame(closer: closer))
        }
        func close() {
            stack.removeLast()
            stack[stack.count - 1].append(substitution)
        }

        while i < scalars.count {
            let c = scalars[i]
            let top = stack.count - 1
            switch stack[top].quote {
            case .single:
                if c == "'" { stack[top].quote = .none } else { stack[top].append(c) }
                i += 1
            case .dollarSingle:
                if c == "'" {
                    stack[top].quote = .none
                    i += 1
                } else if c == "\\", let escaped = next() {
                    stack[top].append(escaped)
                    i += 2
                } else {
                    stack[top].append(c)
                    i += 1
                }
            case .double:
                if c == "\"" {
                    stack[top].quote = .none
                    i += 1
                } else if c == "\\", let escaped = next() {
                    if "$`\"\\".unicodeScalars.contains(escaped) {
                        stack[top].append(escaped)
                    } else if escaped != "\n" {
                        stack[top].append(c)
                        stack[top].append(escaped)
                    }
                    i += 2
                } else if c == "$", next() == "(" {
                    open(.parenthesis)
                    i += 2
                } else if c == "`" {
                    if stack[top].closer == .backquote { close() } else { open(.backquote) }
                    i += 1
                } else {
                    stack[top].append(c)
                    i += 1
                }
            case .none:
                switch c {
                case " ", "\t":
                    stack[top].endWord()
                    i += 1
                case "\n", ";":
                    stack[top].endCommand()
                    i += 1
                case "&":
                    if next() == ">" {  // `&>file`, `&>>file`
                        stack[top].endWord()
                        i += 2
                        if i < scalars.count, scalars[i] == ">" { i += 1 }
                        stack[top].nextIsRedirectTarget = true
                    } else {
                        stack[top].endCommand()
                        i += next() == "&" ? 2 : 1
                    }
                case "|":
                    stack[top].endCommand()
                    i += next() == "|" || next() == "&" ? 2 : 1
                case "<", ">":
                    if next() == "(" {  // process substitution
                        open(.parenthesis)
                        i += 2
                        break
                    }
                    // `2>`: a descriptor number written right before belongs to the redirection.
                    if let word = stack[top].word, !word.isEmpty, word.allSatisfy({ ("0"..."9").contains($0) }) {
                        stack[top].word = nil
                        stack[top].wordIsRedirectTarget = false
                    } else {
                        stack[top].endWord()
                    }
                    i += 1
                    while i < scalars.count, "<>&|-".unicodeScalars.contains(scalars[i]) { i += 1 }
                    stack[top].nextIsRedirectTarget = true
                case "\\":
                    if let escaped = next() {
                        if escaped != "\n" { stack[top].append(escaped) }
                        i += 2
                    } else {
                        stack[top].beginWord()
                        i += 1
                    }
                case "'":
                    stack[top].beginWord()
                    stack[top].quote = .single
                    i += 1
                case "\"":
                    stack[top].beginWord()
                    stack[top].quote = .double
                    i += 1
                case "$" where next() == "'":
                    stack[top].beginWord()
                    stack[top].quote = .dollarSingle
                    i += 2
                case "$" where next() == "(":
                    open(.parenthesis)
                    i += 2
                case "`":
                    if stack[top].closer == .backquote { close() } else { open(.backquote) }
                    i += 1
                case "(":
                    open(.parenthesis)
                    i += 1
                case ")":
                    if stack[top].closer == .parenthesis { close() } else { stack[top].endCommand() }
                    i += 1
                case "#" where stack[top].word == nil:
                    // A comment, to the end of the line (bash's default; zsh's with INTERACTIVE_COMMENTS).
                    guard let newline = scalars[i...].firstIndex(of: "\n") else { return nil }
                    i = newline
                default:
                    stack[top].append(c)
                    i += 1
                }
            }
        }

        let last = stack[stack.count - 1]
        return TypedCommand(words: last.words, current: last.word.map(String.init) ?? "",
                            currentIsRedirectTarget: last.word == nil ? last.nextIsRedirectTarget : last.wordIsRedirectTarget)
    }
}
