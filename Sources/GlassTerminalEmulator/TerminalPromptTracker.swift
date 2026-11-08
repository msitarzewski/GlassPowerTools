//
//  TerminalPromptTracker.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  Type-ahead (D102, 2026-11-06; `tasks/2026-11/2026-11-06_type-ahead.md`). The shell owns the line being edited:
//  the terminal sees only the keys it sends and the screen that comes back. This follows the prompt two ways.
//
//  1. Where the shell marks it (shell integration: OSC 133 as iTerm2, Ghostty, kitty and WezTerm send it, VS Code's
//     OSC 633), typing begins where `B` says, the command that runs is `633;E`'s text or the input cells at `C`,
//     and `D` gives its exit status. SwiftTerm still gets every 133 mark (and 633's as 133) for its own cell
//     tagging: its handler is public for this (patch S3).
//  2. Elsewhere, the keys typed since the last Enter count, while they are plain characters and backspace, and
//     only when the screen shows exactly them just before the cursor. Anything typed with echo off (a password)
//     never shows, so it is never taken for a command. And only where the shell is known to be the program
//     reading the keys (`shellIsInForeground`: a terminal on this Mac asks the system). Where nothing says so (an
//     SSH terminal whose shell marks nothing), a line typed into Claude Code, Python or mysql looks just like one
//     typed at a prompt: nothing is offered over it and nothing is kept (2026-11-06, "no surprises for users").
//     VS Code's terminal suggestions likewise need shell integration.
//
//  Shells differ in the order they send marks (the shell integration's report, 2026-11-06): fish 4 sends its own
//  `C` (with `cmdline_url`) before the app's `633;E`, and its own `A` and `B` around a `read` prompt inside a
//  running command. A prompt while a command runs is that program's, never the shell's.
//

import Foundation
import SwiftTerm

/// The line typed at a shell prompt, as the terminal shows it now.
public struct TerminalTypedLine: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// The shell marks its prompt: typing began where it said.
        case shellIntegration
        /// The keys sent since the last Enter, matched against the screen.
        case typedKeys
    }

    /// What has been typed before the cursor.
    public let text: String
    /// Nothing typed after the cursor, so a suggestion can follow it.
    public let cursorAtEnd: Bool
    /// Text after the cursor drawn faint or grey: the shell's own suggestion (zsh-autosuggestions, fish).
    public let othersSuggestion: Bool
    public let source: Source
    /// Columns from the cursor to the end of its row.
    public let columnsLeft: Int

    public init(text: String, cursorAtEnd: Bool, othersSuggestion: Bool, source: Source, columnsLeft: Int) {
        self.text = text
        self.cursorAtEnd = cursorAtEnd
        self.othersSuggestion = othersSuggestion
        self.source = source
        self.columnsLeft = columnsLeft
    }
}

/// A command the shell ran, as it was typed.
public struct TerminalRanCommand: Equatable, Sendable {
    public let command: String
    public let source: TerminalTypedLine.Source

    public init(command: String, source: TerminalTypedLine.Source) {
        self.command = command
        self.source = source
    }
}

@MainActor
public final class TerminalPromptTracker {
    public enum Phase: Equatable, Sendable {
        /// No mark seen yet, or the shell doesn't send them.
        case unknown
        /// A prompt is being drawn (`A`).
        case prompt
        /// Typing (`B` until `C`).
        case typing
        /// A command runs (`C` until `D`).
        case running
    }

    /// The shell marks its prompts. Set on the first mark and kept: a shell that sent one sends them all.
    public private(set) var hasShellIntegration = false
    public private(set) var phase: Phase = .unknown
    /// A command the shell ran: the integration's `C`, or Enter on a line the screen confirmed.
    public var onCommandRun: ((TerminalRanCommand) -> Void)?
    /// The last command's exit status (`D`); nil when the shell didn't give one.
    public var onCommandFinished: ((Int?) -> Void)?
    /// Where the shell marks nothing: whether it is the program reading the keys now. Nil, or false, and the keys
    /// typed are neither offered suggestions nor kept: a line typed into another program can't be told from one
    /// typed at a prompt.
    public var shellIsInForeground: (() -> Bool)?

    private weak var terminal: Terminal?
    /// Where typing began (`B`), rows as `getScrollInvariantLine(row:)` counts them.
    private var inputStart: (row: Int, column: Int)?
    /// `633;E`'s command line, until its `C`.
    private var pendingCommandLine: String?
    /// The keys typed since the last Enter; nil once something was sent the tracker can't follow (an arrow, Tab,
    /// a ⌃ key), until the next Enter, ⌃C or ⌃U starts the line afresh.
    private var typed: String? = ""
    /// A command counted at Enter before the shell had marked anything: the `C` of that same run, when the
    /// integration turns out to be there (a reattached screen, or zsh loading it at its first prompt), isn't
    /// another run. Seen in the macOS VM, 2026-11-06: each terminal's first command was kept twice.
    private var countedAtEnter: String?
    /// A `C` that said nothing of its command, and no cells to read it from: the `633;E` that follows it (fish
    /// sends its own `C` first) names it.
    private var awaitingCommandLine = false

    public init(terminal: Terminal) {
        self.terminal = terminal
        // The app's handlers are consulted before SwiftTerm's own codes (`EscapeSequenceParser.dispatchOsc`).
        // The parser calls them as it reads output, which the terminal's view does on the main actor.
        terminal.parser.oscHandlers[133] = { [weak self, weak terminal] data in
            MainActor.assumeIsolated {
                terminal?.oscSemanticPrompt(data)
                self?.mark(data)
            }
        }
        terminal.parser.oscHandlers[633] = { [weak self, weak terminal] data in
            MainActor.assumeIsolated {
                guard let first = data.first else { return }
                switch first {
                case UInt8(ascii: "A"), UInt8(ascii: "B"), UInt8(ascii: "C"), UInt8(ascii: "D"):
                    // VS Code's marks are 133's: SwiftTerm tags the cells by them too.
                    terminal?.oscSemanticPrompt(data)
                    self?.mark(data)
                case UInt8(ascii: "E"):
                    self?.commandLine(data)
                default:
                    break
                }
            }
        }
    }

    // MARK: - Marks

    private func mark(_ data: ArraySlice<UInt8>) {
        guard let terminal, !terminal.isCurrentBufferAlternate,
              let text = String(bytes: data, encoding: .utf8),
              let action = text.first else { return }
        hasShellIntegration = true
        let fields = text.split(separator: ";", omittingEmptySubsequences: false)
        switch action {
        case "A":
            // A prompt drawn while a command runs is that command's (fish marks `read`'s): typing there isn't at
            // the shell's prompt, and the command's `D` is still to come.
            guard phase != .running else { return }
            phase = .prompt
            inputStart = nil
            countedAtEnter = nil
            pendingCommandLine = nil
        case "B":
            guard phase != .running else { return }
            phase = .typing
            inputStart = (terminal.scrollInvariantCursorRow, terminal.getCursorLocation().x)
            typed = ""
        case "C":
            let command = pendingCommandLine ?? Self.commandLineParameter(fields) ?? submittedInput()
            pendingCommandLine = nil
            phase = .running
            inputStart = nil
            guard let command else {
                awaitingCommandLine = true
                return
            }
            let counted = countedAtEnter
            countedAtEnter = nil
            ran(command, countedAtEnter: counted)
        case "D":
            let ran = phase == .running
            phase = .prompt
            inputStart = nil
            pendingCommandLine = nil
            awaitingCommandLine = false
            countedAtEnter = nil
            if ran { onCommandFinished?(fields.count > 1 ? Int(fields[1]) : nil) }
        default:
            break
        }
    }

    /// A command the shell said it ran, unless it is the one already counted at Enter.
    private func ran(_ command: String, countedAtEnter counted: String?) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              counted.map({ Self.droppingTrailingBlanks($0) != Self.droppingTrailingBlanks(command) }) ?? true else { return }
        onCommandRun?(TerminalRanCommand(command: command, source: .shellIntegration))
    }

    /// `C;cmdline_url=<percent-encoded>`, as fish 4.0.1 and later send it (kitty's form).
    nonisolated static func commandLineParameter(_ fields: [Substring]) -> String? {
        for field in fields.dropFirst() where field.hasPrefix("cmdline_url=") {
            return String(field.dropFirst("cmdline_url=".count)).removingPercentEncoding
        }
        return nil
    }

    /// `633;E;<command line>[;<nonce>]`: VS Code's escaping undone (`\\`, `\xNN`).
    private func commandLine(_ data: ArraySlice<UInt8>) {
        hasShellIntegration = true
        guard let text = String(bytes: data, encoding: .utf8) else { return }
        let fields = text.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count > 1 else { return }
        let command = Self.unescapeCommandLine(String(fields[1]))
        // After its `C` (fish sends its own first): it names that command only when the `C` couldn't.
        if phase == .running {
            guard awaitingCommandLine else { return }
            awaitingCommandLine = false
            let counted = countedAtEnter
            countedAtEnter = nil
            ran(command, countedAtEnter: counted)
            return
        }
        pendingCommandLine = command
    }

    /// `\\` is a backslash, `\xNN` a byte (VS Code writes `;` and control characters so).
    nonisolated static func unescapeCommandLine(_ text: String) -> String {
        var bytes: [UInt8] = []
        let source = Array(text.utf8)
        var index = 0
        while index < source.count {
            let byte = source[index]
            if byte == UInt8(ascii: "\\"), index + 1 < source.count {
                let next = source[index + 1]
                if next == UInt8(ascii: "\\") {
                    bytes.append(next)
                    index += 2
                    continue
                }
                if next == UInt8(ascii: "x"), index + 3 < source.count,
                   let value = UInt8(String(decoding: source[(index + 2)...(index + 3)], as: UTF8.self), radix: 16) {
                    bytes.append(value)
                    index += 4
                    continue
                }
            }
            bytes.append(byte)
            index += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// At `C`, the cursor has gone on past the line typed: from where typing began to the end of that line.
    private func submittedInput() -> String? {
        guard let terminal, let start = inputStart else { return nil }
        let cursorRow = terminal.scrollInvariantCursorRow
        let lastRow = cursorRow > start.row ? cursorRow - 1 : cursorRow
        // The end's blanks are the row's; a leading space is the person's (zsh and bash keep such a command out of
        // their history, and so does the app).
        return text(from: start, toRow: lastRow, column: nil).map(Self.droppingTrailingBlanks)
    }

    nonisolated static func droppingTrailingBlanks(_ text: String) -> String {
        var text = text
        while let last = text.last, last == " " || last == "\t" { text.removeLast() }
        return text
    }

    // MARK: - The line now

    /// The line being typed at the prompt, from the screen now; nil on the alternate screen, while a command runs,
    /// or when it can't be read with confidence.
    public func currentLine() -> TerminalTypedLine? {
        guard let terminal, !terminal.isCurrentBufferAlternate else { return nil }
        let cursorRow = terminal.scrollInvariantCursorRow
        let cursorColumn = terminal.getCursorLocation().x
        let columnsLeft = max(0, terminal.cols - cursorColumn)
        let (atEnd, others) = trailing(row: cursorRow, after: cursorColumn)
        if hasShellIntegration {
            guard phase == .typing, let start = inputStart, start.row <= cursorRow,
                  let text = text(from: start, toRow: cursorRow, column: cursorColumn) else { return nil }
            return TerminalTypedLine(text: text, cursorAtEnd: atEnd || others, othersSuggestion: others,
                                     source: .shellIntegration, columnsLeft: columnsLeft)
        }
        guard let typed, !typed.isEmpty, shown(typed, beforeRow: cursorRow, column: cursorColumn),
              shellIsInForeground?() == true else { return nil }
        return TerminalTypedLine(text: typed, cursorAtEnd: atEnd || others, othersSuggestion: others,
                                 source: .typedKeys, columnsLeft: columnsLeft)
    }

    /// The cells from `start` to `column` of `lastRow` (to its end for nil), rows joined across soft wraps only: a
    /// line broken by the shell (a continuation prompt) isn't one command line.
    private func text(from start: (row: Int, column: Int), toRow lastRow: Int, column: Int?) -> String? {
        guard let terminal, lastRow >= start.row, lastRow - start.row < 64 else { return nil }
        var result = ""
        for row in start.row...lastRow {
            guard let line = terminal.getScrollInvariantLine(row: row) else { return nil }
            if row > start.row, !line.isWrapped { return nil }
            let from = row == start.row ? start.column : 0
            let to = row == lastRow ? (column ?? line.count) : line.count
            guard from <= to else { return nil }
            result += Self.cellText(line, from: from, to: to)
        }
        return result
    }

    /// Whether the screen shows `typed` just before the cursor.
    private func shown(_ typed: String, beforeRow cursorRow: Int, column: Int) -> Bool {
        guard let terminal, let cursorLine = terminal.getScrollInvariantLine(row: cursorRow) else { return false }
        var before = Self.cellText(cursorLine, from: 0, to: column)
        var row = cursorRow
        var line = cursorLine
        // A typed line longer than the screen is wide wraps: read back across the soft wraps.
        while before.count < typed.count, line.isWrapped, let previous = terminal.getScrollInvariantLine(row: row - 1) {
            before = Self.cellText(previous, from: 0, to: previous.count) + before
            row -= 1
            line = previous
        }
        return before.hasSuffix(typed)
    }

    /// Whether the rest of the cursor's row is blank, and if not, whether what's there is drawn faint or grey, as
    /// zsh-autosuggestions and fish draw their own suggestions.
    private func trailing(row: Int, after column: Int) -> (blank: Bool, othersSuggestion: Bool) {
        guard let terminal, let line = terminal.getScrollInvariantLine(row: row), column < line.count else { return (true, false) }
        var sawText = false
        var allFaint = true
        for index in column..<line.count {
            let cell = line[index]
            let character = cell.getCharacter()
            guard character != "\u{0}", character != " " else { continue }
            sawText = true
            if !Self.isFaint(cell.attribute) { allFaint = false }
        }
        return sawText ? (false, allFaint) : (true, false)
    }

    /// Faint, or one of the greys suggestions are drawn in: bright black (8) and the 256-colour greys.
    nonisolated static func isFaint(_ attribute: Attribute) -> Bool {
        if attribute.style.contains(.dim) { return true }
        if case .ansi256(let code) = attribute.fg { return code == 8 || (232...250).contains(code) }
        if case .trueColor(let red, let green, let blue) = attribute.fg {
            let spread = max(red, green, blue) - min(red, green, blue)
            return spread < 16 && (60...170).contains(Int(red))
        }
        return false
    }

    /// A row's text in columns `from..<to`, empty cells as spaces.
    nonisolated static func cellText(_ line: BufferLine, from: Int, to: Int) -> String {
        let end = min(to, line.count)
        guard from < end else { return "" }
        return line.translateToString(trimRight: false, startCol: from, endCol: end, skipNullCellsFollowingWide: true)
            .replacingOccurrences(of: "\u{0}", with: " ")
    }

    // MARK: - Keys sent

    /// The bytes about to go to the shell, as typed or pasted. Enter on a line the screen confirms is a command run,
    /// where the shell doesn't mark its own.
    public func noteSent(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        // A bracketed paste of one line joins the typed line; more lines, the line is lost.
        let pasteStart: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]  // ESC [200~
        let pasteEnd: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]    // ESC [201~
        if bytes.starts(with: pasteStart) {
            let inner = bytes.dropFirst(pasteStart.count)
            let body = inner.count >= pasteEnd.count && Array(inner.suffix(pasteEnd.count)) == pasteEnd
                ? Array(inner.dropLast(pasteEnd.count)) : Array(inner)
            if body.contains(0x0A) || body.contains(0x0D) { typed = nil } else { typed? += String(decoding: body, as: UTF8.self) }
            return
        }
        // An escape sequence is an arrow, a function key, ⌥ and a key: the line moved in ways not followed here.
        if bytes.contains(0x1B) {
            typed = nil
            return
        }
        var printable: [UInt8] = []
        func flush() {
            if !printable.isEmpty {
                typed? += String(decoding: printable, as: UTF8.self)
                printable.removeAll()
            }
        }
        for byte in bytes {
            switch byte {
            case 0x0D, 0x0A:
                flush()
                enter()
            case 0x7F, 0x08:
                flush()
                if typed?.isEmpty == false { typed?.removeLast() }
            case 0x03, 0x15:  // ⌃C, ⌃U: the line starts again.
                printable.removeAll()
                typed = ""
            case 0x00..<0x20:
                printable.removeAll()
                typed = nil
            default:
                printable.append(byte)
            }
        }
        flush()
    }

    private func enter() {
        defer { typed = "" }
        guard !hasShellIntegration, let line = currentLine(), line.source == .typedKeys else { return }
        let command = line.text.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        countedAtEnter = line.text
        onCommandRun?(TerminalRanCommand(command: line.text, source: .typedKeys))
    }
}
