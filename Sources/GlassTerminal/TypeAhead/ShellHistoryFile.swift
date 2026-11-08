//
//  ShellHistoryFile.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06): the commands a machine's shell remembers, read from its own
//  history file, so a terminal can offer what someone ran there before the app was watching.
//  `tasks/2026-11/2026-11-06_type-ahead.md`.
//
//  Each reader follows the shell's own reader, not a description of the format, because the
//  formats have corners only the source shows:
//
//  - **zsh** (`Src/hist.c`, `readhistline` and `readhistfile`). The file is *metafied*: zsh keeps
//    bytes 0x83–0xA2 and NUL as byte 0x83 followed by the byte XOR 0x20 (`Src/zsh.h`, "Meta"),
//    and writes its history in that form, so 日 (E6 97 A5) is stored as E6 83 B7 A5. Read without
//    undoing it, every non-ASCII command comes out corrupt. A newline inside a command is written
//    as a backslash ending the line; a command that itself ends in a backslash gets a space after
//    it so it isn't read as going on, and the reader takes that space off again. EXTENDED_HISTORY
//    lines are `: <start>:<elapsed>;<command>`, and without it a command starting with `:` is
//    written `\:`.
//  - **bash** (readline's `read_history_range`). With HISTTIMEFORMAT set, a `#<epoch>` line comes
//    before each command. A file that starts with one was written that way, and there a line with
//    no timestamp before it continues the command above: that is how a multi-line command saved
//    with `lithist` comes back whole (bash 5.3 on the Linux test server, 2026-11-06, does exactly this).
//  - **fish** (`src/history/yaml_backend.rs`). A YAML-like list: `- cmd: <command>` starts each
//    item and indented lines (`when:`, `paths:`) belong to it. In the command `\\` is a backslash
//    and `\n` a newline. A last line with no newline is a write still in progress and is skipped,
//    as fish skips it.
//
//  One unreadable entry never costs the rest: invalid UTF-8 drops that entry alone. Files can run
//  to tens of megabytes, so lines are found with `memchr` and each entry is decoded once.
//

import Foundation

/// One command from a shell's history file.
nonisolated struct ShellHistoryEntry: Equatable, Sendable {
    let command: String
    /// When it ran, where the file keeps a time: zsh's EXTENDED_HISTORY start, bash's `#<epoch>`
    /// line, fish's `when`. Nil where it keeps none.
    let date: Date?
}

/// Reading the history files zsh, bash and fish keep, the way each shell reads its own.
nonisolated enum ShellHistoryFile {
    /// Where each shell keeps its history, relative to the home folder, most likely first.
    ///
    /// The defaults only: someone who sets `$HISTFILE` (or fish's `fish_history` session name)
    /// keeps it elsewhere, and asking the shell for that comes first where the caller can.
    /// zsh has three in common use: `.zsh_history` (macOS's `/etc/zshrc`, oh-my-zsh, grml),
    /// `.zhistory` (prezto's older default) and `.histfile` (zsh's own new-user setup, as on
    /// Debian and Arch).
    static func relativePaths(for shell: TerminalShellKind) -> [String] {
        switch shell {
        case .zsh: [".zsh_history", ".zhistory", ".histfile"]
        case .bash: [".bash_history"]
        case .fish: [".local/share/fish/fish_history"]
        }
    }

    /// The entries in file order, oldest first.
    ///
    /// Empty and whitespace-only commands are dropped, and so is any entry that isn't valid
    /// UTF-8 once the shell's own encoding is undone.
    static func parse(_ data: Data, shell: TerminalShellKind) -> [ShellHistoryEntry] {
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            switch shell {
            case .zsh: return parseZsh(bytes)
            case .bash: return parseBash(bytes)
            case .fish: return parseFish(bytes)
            }
        }
    }

    /// Each command once, at its last use, newest first, at most `limit`.
    ///
    /// "Last" is the file's order, not the times in it: the shells append as commands finish and
    /// recall in file order, and several shells sharing one file write times out of order.
    /// Commands match exactly; the entry kept is the last one, with that use's date.
    static func distinctRecent(_ entries: [ShellHistoryEntry], limit: Int) -> [ShellHistoryEntry] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var recent: [ShellHistoryEntry] = []
        recent.reserveCapacity(Swift.min(limit, entries.count))
        for entry in entries.reversed() where seen.insert(entry.command).inserted {
            recent.append(entry)
            if recent.count == limit { break }
        }
        return recent
    }

    // MARK: - zsh

    private static func parseZsh(_ bytes: UnsafeBufferPointer<UInt8>) -> [ShellHistoryEntry] {
        var entries: [ShellHistoryEntry] = []
        var entry: [UInt8] = []
        var continuing = false
        var lines = LineReader(bytes)
        while let line = lines.next() {
            let range = line.range
            // A backslash ending the line stands for a newline in the command, and the command
            // goes on. zsh's writer never leaves a real trailing backslash there: it adds a space.
            if line.terminated, !range.isEmpty, bytes[range.upperBound - 1] == ASCII.backslash {
                entry.append(contentsOf: bytes[range.lowerBound ..< range.upperBound - 1])
                entry.append(ASCII.newline)
                continuing = true
                continue
            }
            entry.append(contentsOf: bytes[range])
            if let parsed = zshEntry(entry, terminated: line.terminated) { entries.append(parsed) }
            entry.removeAll(keepingCapacity: true)
            continuing = false
        }
        // The file ended inside a command that said it went on.
        if continuing {
            entry.removeLast()
            if let parsed = zshEntry(entry, terminated: false) { entries.append(parsed) }
        }
        return entries
    }

    /// One whole entry, its continuation lines already joined, still metafied.
    private static func zshEntry(_ entry: [UInt8], terminated: Bool) -> ShellHistoryEntry? {
        var end = entry.count
        // `echo trailing\` is written `echo trailing\ `: take that one space off again.
        if terminated {
            var index = end - 1
            while index >= 0, entry[index] == ASCII.space { index -= 1 }
            if index != end - 1, index >= 0, entry[index] == ASCII.backslash { end -= 1 }
        }
        var start = 0
        var date: Date?
        if end > 0, entry[0] == ASCII.colon {
            // `: <start>:<elapsed>;<command>`, read as zsh reads it: the start time after the
            // first colon, then on to the next colon, then past the semicolon.
            date = epochDate(entry, from: 1, to: end)
            var index = 1
            while index < end, entry[index] != ASCII.colon { index += 1 }
            if index < end {
                index += 1
                while index < end, entry[index] != ASCII.semicolon { index += 1 }
                if index < end { index += 1 }
            }
            start = index
        } else if end > 1, entry[0] == ASCII.backslash, entry[1] == ASCII.colon {
            start = 1
        }
        guard let command = decode(unmetafied(entry[start ..< end])) else { return nil }
        return ShellHistoryEntry(command: command, date: date)
    }

    /// Undo zsh's metafication: byte 0x83 says the next byte was XORed with 0x20 (`unmetafy`).
    private static func unmetafied(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        guard bytes.contains(ASCII.zshMeta) else { return bytes }
        var plain: [UInt8] = []
        plain.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == ASCII.zshMeta, index + 1 < bytes.endIndex {
                plain.append(bytes[index + 1] ^ 0x20)
                index += 2
            } else {
                plain.append(byte)
                index += 1
            }
        }
        return plain[...]
    }

    // MARK: - bash

    private static func parseBash(_ bytes: UnsafeBufferPointer<UInt8>) -> [ShellHistoryEntry] {
        var entries: [ShellHistoryEntry] = []
        var lines = LineReader(bytes)
        var entry: [UInt8] = []
        var entryDate: Date?
        var hasEntry = false
        var stamped = false
        var stamp: Date?
        var multiline: Bool?
        while let line = lines.next() {
            var range = line.range
            // readline accepts Windows line ends.
            if !range.isEmpty, bytes[range.upperBound - 1] == ASCII.carriageReturn {
                range = range.lowerBound ..< range.upperBound - 1
            }
            guard !range.isEmpty else { continue }
            let isStamp = isBashTimestamp(bytes, range)
            // readline decides once, from the file's first line.
            if multiline == nil { multiline = isStamp }
            if isStamp {
                stamped = true
                stamp = epochDate(bytes, from: range.lowerBound + 1, to: range.upperBound)
                continue
            }
            if multiline == true, !stamped, hasEntry {
                entry.append(ASCII.newline)
                entry.append(contentsOf: bytes[range])
            } else {
                if hasEntry, let command = decode(entry[...]) {
                    entries.append(ShellHistoryEntry(command: command, date: entryDate))
                }
                entry.removeAll(keepingCapacity: true)
                entry.append(contentsOf: bytes[range])
                entryDate = stamped ? stamp : nil
                hasEntry = true
            }
            stamped = false
            stamp = nil
        }
        if hasEntry, let command = decode(entry[...]) {
            entries.append(ShellHistoryEntry(command: command, date: entryDate))
        }
        return entries
    }

    /// `#` and digits alone. readline itself takes any `#` and a digit for a timestamp, and so
    /// loses a command like `#1 todo`; this keeps it as the command it was.
    private static func isBashTimestamp(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Bool {
        guard range.count > 1, bytes[range.lowerBound] == ASCII.hash else { return false }
        return bytes[range.lowerBound + 1 ..< range.upperBound].allSatisfy(ASCII.isDigit)
    }

    // MARK: - fish

    private static func parseFish(_ bytes: UnsafeBufferPointer<UInt8>) -> [ShellHistoryEntry] {
        var entries: [ShellHistoryEntry] = []
        var command: ArraySlice<UInt8>?
        var date: Date?
        func finish() {
            if let pending = command, let text = decode(fishUnescaped(pending)) {
                entries.append(ShellHistoryEntry(command: text, date: date))
            }
            command = nil
            date = nil
        }
        var lines = LineReader(bytes)
        while let line = lines.next() {
            // A last line with no newline is a write in progress: fish skips it.
            guard line.terminated else { break }
            let range = line.range
            if starts(bytes, range, with: ASCII.fishCommand) {
                finish()
                var start = range.lowerBound + ASCII.fishCommand.count
                while start < range.upperBound, ASCII.isWhitespace(bytes[start]) { start += 1 }
                command = ArraySlice(bytes[start ..< range.upperBound])
            } else if !range.isEmpty, bytes[range.lowerBound] == ASCII.space {
                // An item's own lines: `when:` is its last use; `added_when:` and `paths:` aren't needed.
                var start = range.lowerBound
                while start < range.upperBound, bytes[start] == ASCII.space { start += 1 }
                if command != nil, starts(bytes, start ..< range.upperBound, with: ASCII.fishWhen) {
                    date = epochDate(bytes, from: start + ASCII.fishWhen.count, to: range.upperBound)
                }
            } else {
                // A YAML marker (`---`, `...`, `%`) or a damaged line: it ends the item, as in fish.
                finish()
            }
        }
        finish()
        return entries
    }

    /// fish's escaping: `\\` is a backslash and `\n` a newline. fish writes nothing else after a
    /// backslash; anything else is kept as it stands, as fish 2's reader kept it.
    private static func fishUnescaped(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        guard bytes.contains(ASCII.backslash) else { return bytes }
        var plain: [UInt8] = []
        plain.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == ASCII.backslash, index + 1 < bytes.endIndex {
                switch bytes[index + 1] {
                case ASCII.backslash: plain.append(ASCII.backslash); index += 2; continue
                case ASCII.letterN: plain.append(ASCII.newline); index += 2; continue
                default: break
                }
            }
            plain.append(byte)
            index += 1
        }
        return plain[...]
    }

    // MARK: - Shared

    /// The command as text, or nil when it is empty, only whitespace, or not UTF-8.
    private static func decode(_ bytes: ArraySlice<UInt8>) -> String? {
        guard !bytes.allSatisfy(ASCII.isWhitespace) else { return nil }
        return bytes.withUnsafeBufferPointer { String(validating: $0, as: UTF8.self) }
    }

    /// A decimal count of seconds since 1970, after any blanks; nil for none, zero, or one too
    /// long to be a time.
    private static func epochDate<Bytes: RandomAccessCollection<UInt8>>(
        _ bytes: Bytes, from start: Bytes.Index, to end: Bytes.Index
    ) -> Date? where Bytes.Index == Int {
        var index = start
        while index < end, bytes[index] == ASCII.space || bytes[index] == ASCII.tab { index += 1 }
        var seconds = 0
        var digits = 0
        while index < end, ASCII.isDigit(bytes[index]) {
            guard digits < 15 else { return nil }
            seconds = seconds * 10 + Int(bytes[index] - ASCII.zero)
            digits += 1
            index += 1
        }
        return seconds > 0 ? Date(timeIntervalSince1970: TimeInterval(seconds)) : nil
    }

    private static func starts(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>, with prefix: [UInt8]) -> Bool {
        guard range.count >= prefix.count else { return false }
        for (offset, byte) in prefix.enumerated() where bytes[range.lowerBound + offset] != byte { return false }
        return true
    }

    /// The lines of a file, found with `memchr`, each with whether a newline ended it.
    nonisolated private struct LineReader {
        let bytes: UnsafeBufferPointer<UInt8>
        var position = 0

        init(_ bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

        mutating func next() -> (range: Range<Int>, terminated: Bool)? {
            guard position < bytes.count, let base = bytes.baseAddress else { return nil }
            let start = position
            if let found = memchr(base + start, Int32(ASCII.newline), bytes.count - start) {
                let end = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(found))
                position = end + 1
                return (start ..< end, true)
            }
            position = bytes.count
            return (start ..< bytes.count, false)
        }
    }

    nonisolated private enum ASCII {
        static let tab: UInt8 = 0x09
        static let newline: UInt8 = 0x0A
        static let carriageReturn: UInt8 = 0x0D
        static let space: UInt8 = 0x20
        static let hash: UInt8 = 0x23
        static let zero: UInt8 = 0x30
        static let colon: UInt8 = 0x3A
        static let semicolon: UInt8 = 0x3B
        static let backslash: UInt8 = 0x5C
        static let letterN: UInt8 = 0x6E
        /// zsh's `Meta` (`Src/zsh.h`).
        static let zshMeta: UInt8 = 0x83
        static let fishCommand = Array("- cmd:".utf8)
        static let fishWhen = Array("when:".utf8)

        static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
        /// Rust's `is_ascii_whitespace`, which fish trims with: space, tab, LF, FF, CR.
        static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
        }
    }
}
