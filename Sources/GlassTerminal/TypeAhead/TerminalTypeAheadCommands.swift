//
//  TerminalTypeAheadCommands.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102): the commands a machine has, for the word in a command's place (2026-11-06, the owner: "Yes,
//  add PATH", asked whether the first word should also come from every program on the system's PATH). The programs
//  in the usual PATH folders, those `/etc/paths` and `/etc/paths.d` add (macOS's `path_helper` reads the same), and
//  the shell's own commands. Read once per machine for the run, through the terminal's reader (this Mac's files, or
//  a server's over the terminal's SFTP), and ranked below anything run or saved. `tasks/2026-11/2026-11-06_type-ahead.md`.
//
//  The folders are the usual ones, not the shell's own PATH: a shell's PATH is what its start-up files make it, which
//  nothing outside the shell can read without running them. A program in a folder of someone's own comes from their
//  history once run.
//

import Foundation

@MainActor
final class TerminalTypeAheadCommands {
    /// Where programs usually are: Homebrew's (Apple silicon, then Intel), MacPorts', the system's, snaps'; relative
    /// ones are in the home folder (`home`).
    nonisolated static let folders = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin",
                                      "/opt/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", "/snap/bin"]
    nonisolated static let homeFolders = [".local/bin", "bin", ".cargo/bin"]

    /// The shell's own commands, which no folder holds.
    nonisolated static let builtins = ["alias", "autoload", "bg", "bindkey", "builtin", "cd", "command", "dirs",
                                       "disown", "eval", "exec", "exit", "export", "fc", "fg", "hash", "history", "jobs",
                                       "popd", "pushd", "rehash", "setopt", "source", "trap", "type", "typeset",
                                       "ulimit", "umask", "unalias", "unset", "unsetopt", "wait", "whence"]

    /// What may stand before a command and leave the next word a command: `sudo make`, `time swift build`.
    nonisolated static let commandPrefixes: Set<String> = ["sudo", "doas", "time", "nohup", "exec", "command",
                                                           "builtin", "nice", "env", "watch", "xargs"]

    /// Below a tool the app knows (`CommandSpecs`), and both below anything run or saved.
    nonisolated static let score = 0.5
    nonisolated static let knownToolScore = 0.6

    /// Each machine's commands, read once a run.
    private static var known: [String: [String]] = [:]
    private static var loading: Set<String> = []
    private static var waiting: [String: [TerminalTypeAheadCommands]] = [:]

    private let machine: String
    private let reader: any TerminalFolderReader
    private let home: String
    var onLoaded: (() -> Void)?

    /// - Parameter home: what the home folder's own folders are relative to: this Mac's home, or "" on a server,
    ///   whose SFTP paths start there.
    init(machine: String, reader: any TerminalFolderReader, home: String) {
        self.machine = machine
        self.reader = reader
        self.home = home
    }

    /// The commands for the word being typed, when it is in a command's place; read first if not yet.
    func words(line: String) -> [(word: String, score: Double)] {
        let (base, word) = TerminalTypeAheadEngine.currentWord(of: line)
        // Something typed: an empty word would be every program the machine has.
        guard !word.isEmpty, Self.isCommandPlace(base) else { return [] }
        guard let names = Self.known[machine] else {
            load()
            return []
        }
        let tools = CommandSpecs.commandNames
        return names.compactMap { name in
            name.hasPrefix(word) ? (name, tools.contains(name) ? Self.knownToolScore : Self.score) : nil
        }
    }

    /// Whether the word after `base` (the line up to it) is a command: the line's first, or after `|`, `;`, `&&`,
    /// `||`, `(`, a variable set for the command (`FOO=1 make`) or a command that runs the next (`sudo`).
    nonisolated static func isCommandPlace(_ base: String) -> Bool {
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        if "|;&(".contains(last) { return true }
        // From the last separator on, every word sets a variable or runs the next.
        let clause = trimmed.split(whereSeparator: { "|;&(".contains($0) }).last.map(String.init) ?? trimmed
        return clause.split(separator: " ").allSatisfy { word in
            commandPrefixes.contains(String(word)) || isAssignment(word)
        }
    }

    private nonisolated static func isAssignment(_ word: Substring) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        let name = word[..<equals]
        return name.first.map { $0.isLetter || $0 == "_" } == true && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private func load() {
        Self.waiting[machine, default: []].append(self)
        guard !Self.loading.contains(machine) else { return }
        Self.loading.insert(machine)
        let machine = machine, reader = reader, home = home
        Task {
            let names = await Self.read(with: reader, home: home)
            Self.known[machine] = names
            Self.loading.remove(machine)
            for source in Self.waiting.removeValue(forKey: machine) ?? [] { source.onLoaded?() }
        }
    }

    /// Forgets what was read, for tests.
    static func forgetAll() {
        known = [:]
        loading = []
        waiting = [:]
    }

    /// The names in the folders, and the shell's own, sorted, each once. A folder that isn't there adds nothing.
    nonisolated static func read(with reader: any TerminalFolderReader, home: String) async -> [String] {
        var folders = Self.folders
        // macOS's `path_helper` folders: one per line in `/etc/paths` and each file in `/etc/paths.d`.
        var listings: [Data] = []
        if let paths = await reader.read("/etc/paths", maxBytes: 16_384) { listings.append(paths) }
        for entry in await reader.list("/etc/paths.d", limit: 64) ?? [] where !entry.isFolder {
            if let data = await reader.read("/etc/paths.d/" + entry.name, maxBytes: 16_384) { listings.append(data) }
        }
        for data in listings {
            for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                let folder = line.trimmingCharacters(in: .whitespaces)
                if folder.hasPrefix("/"), !folders.contains(folder) { folders.append(folder) }
            }
        }
        folders += homeFolders.map { home.isEmpty ? $0 : (home as NSString).appendingPathComponent($0) }

        var names = Set(builtins)
        for folder in folders {
            for entry in await reader.list(folder, limit: 8_000) ?? []
            where !entry.isFolder && !entry.name.hasPrefix(".") && !entry.name.contains(where: \.isWhitespace) {
                names.insert(entry.name)
            }
        }
        return names.sorted()
    }
}
