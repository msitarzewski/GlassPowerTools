//
//  TmuxPaneRestore.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  Reading a tmux pane into the terminal as a control-mode client attaches (D83). Output that
//  happened before the client was there arrives as no `%output`: the pane is read — its history, its
//  screen, the primary screen behind a program's alternate one, its cursor and modes, and any escape
//  sequence it is part way through — and the terminal is rebuilt from that, as iTerm2 does
//  (`TmuxWindowOpener.m`, `TmuxStateParser.m`, `VT100ScreenMutableState`'s tmux restore).
//

import Foundation

enum TmuxPaneRestore {
    enum Part: Hashable, Sendable, CaseIterable {
        /// The history above the primary screen, lines tmux wrapped joined so they wrap again here.
        case history
        /// The screen showing now, its lines' trailing spaces left off: the primary's, a shell's.
        case screen
        /// The same with every row's trailing spaces: a full-screen program's, whose coloured
        /// padding is part of what it drew.
        case screenExact
        /// The primary screen while a program has the alternate one; nothing otherwise.
        case primaryBehind
        /// Cursor, scroll region and modes.
        case state
        /// An escape sequence the pane is part way through, so the next output finishes it.
        case pending
    }

    /// The pane's state, comma-separated so a format older tmux doesn't know (empty) keeps its place.
    static let stateFields = [
        "alternate_on", "alternate_saved_x", "alternate_saved_y", "cursor_x", "cursor_y",
        "scroll_region_upper", "scroll_region_lower", "cursor_flag", "insert_flag", "keypad_cursor_flag",
        "keypad_flag", "wrap_flag", "mouse_standard_flag", "mouse_button_flag", "mouse_any_flag",
        "mouse_utf8_flag", "mouse_sgr_flag", "bracket_paste_flag", "pane_width", "pane_height", "history_size",
    ]

    static func commands(pane: String, historyLines: Int) -> [(command: String, part: Part)] {
        let format = stateFields.map { "#{\($0)}" }.joined(separator: ",")
        return [
            ("capture-pane -p -e -q -J -S -\(max(1, historyLines)) -E -1 -t \(pane)", .history),
            ("capture-pane -p -e -q -t \(pane)", .screen),
            ("capture-pane -p -e -q -N -t \(pane)", .screenExact),
            ("capture-pane -p -e -q -a -t \(pane)", .primaryBehind),
            ("display-message -p -t \(pane) '\(format)'", .state),
            ("capture-pane -p -P -C -q -t \(pane)", .pending),
        ]
    }

    /// What has come back so far. A part whose command failed is recorded empty: the rest of the
    /// pane is still drawn.
    struct Draft: Sendable {
        private(set) var parts: [Part: [[UInt8]]] = [:]

        mutating func record(_ part: Part, lines: [[UInt8]]?) { parts[part] = lines ?? [] }

        var isComplete: Bool { Part.allCases.allSatisfy { parts[$0] != nil } }

        func lines(_ part: Part) -> [[UInt8]] { parts[part] ?? [] }

        var state: [String: Int] {
            guard let line = lines(.state).first else { return [:] }
            let values = String(decoding: line, as: UTF8.self).split(separator: ",", omittingEmptySubsequences: false)
            var state: [String: Int] = [:]
            for (field, value) in zip(TmuxPaneRestore.stateFields, values) {
                if let number = Int(value) { state[field] = number }
            }
            return state
        }
    }

    /// The bytes that make the terminal show the pane: the terminal and its history cleared and its
    /// modes reset; the primary screen's history and lines; the alternate screen over them where a
    /// program has it, the primary's cursor saved as it saved it; then the scroll region, the cursor,
    /// the modes a program set, and the part of a sequence the pane is in the middle of.
    static func bytes(for draft: Draft, columns: Int, rows: Int) -> Data {
        let state = draft.state
        func flag(_ name: String) -> Bool { state[name] == 1 }
        let alternate = flag("alternate_on")
        let screen = trimmed(draft.lines(alternate ? .screenExact : .screen), to: state["pane_height"] ?? rows)
        let primaryScreen = alternate ? trimmed(draft.lines(.primaryBehind), to: state["pane_height"] ?? rows) : screen
        // With no history, a capture of "all of it" still prints a line: the screen's first.
        let history = state["history_size"] == 0 ? [] : draft.lines(.history)

        var out: [UInt8] = []
        func add(_ text: String) { out += Array(text.utf8) }
        // Primary screen, modes reset, everything cleared, scrollback too.
        add("\u{1B}[?1049l\u{1B}[!p\u{1B}[?1000l\u{1B}[?1002l\u{1B}[?1003l\u{1B}[?1005l\u{1B}[?1006l")
        add("\u{1B}[?2004l\u{1B}[?1l\u{1B}>\u{1B}[0m\u{1B}[H\u{1B}[2J\u{1B}[3J")

        // The primary's history and screen, a line at a time: the last of them end on the screen.
        let primary = history + primaryScreen
        for (index, line) in primary.enumerated() {
            if index > 0 { add("\r\n") }
            out += line
        }
        add("\u{1B}[0m")

        if alternate {
            // Where the program's switch saved the primary's cursor, then the switch, then its screen.
            add("\u{1B}[\((state["alternate_saved_y"] ?? 0) + 1);\((state["alternate_saved_x"] ?? 0) + 1)H")
            add("\u{1B}[?1049h")
            for (row, line) in screen.enumerated() {
                add("\u{1B}[\(row + 1);1H")
                out += line
                add("\u{1B}[0m")
            }
        }

        let height = state["pane_height"] ?? rows
        if let upper = state["scroll_region_upper"], let lower = state["scroll_region_lower"],
           upper != 0 || lower != height - 1 {
            add("\u{1B}[\(upper + 1);\(lower + 1)r")
        }
        add("\u{1B}[\((state["cursor_y"] ?? 0) + 1);\((state["cursor_x"] ?? 0) + 1)H")
        if state["cursor_flag"] == 0 { add("\u{1B}[?25l") }
        if flag("insert_flag") { add("\u{1B}[4h") }
        if flag("keypad_cursor_flag") { add("\u{1B}[?1h") }
        if flag("keypad_flag") { add("\u{1B}=") }
        if state["wrap_flag"] == 0 { add("\u{1B}[?7l") }
        if flag("mouse_standard_flag") { add("\u{1B}[?1000h") }
        if flag("mouse_button_flag") { add("\u{1B}[?1002h") }
        if flag("mouse_any_flag") { add("\u{1B}[?1003h") }
        if flag("mouse_utf8_flag") { add("\u{1B}[?1005h") }
        if flag("mouse_sgr_flag") { add("\u{1B}[?1006h") }
        if flag("bracket_paste_flag") { add("\u{1B}[?2004h") }
        // `-C` wrote it with tmux's octal escapes.
        for line in draft.lines(.pending) { out += TmuxControlLine.unescaped(line[...]) }
        return Data(out)
    }

    /// A screen's lines, at most its height: `capture-pane` prints one per row.
    private static func trimmed(_ lines: [[UInt8]], to height: Int) -> [[UInt8]] {
        lines.count > height ? Array(lines.prefix(height)) : lines
    }
}
