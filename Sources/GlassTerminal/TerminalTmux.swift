//
//  TerminalTmux.swift
//  Glass Power Tools — GlassTerminal
//
//  D44 (2026-10-01): a terminal that outlives the device. With the server's tmux setting on, each
//  terminal is its own tmux session — `glass-1`, `glass-2` — so a suspended app, a dropped network
//  or a closed lid leaves the work running on the host, and any device can attach to it again.
//
//  Everything here is text: the commands Glass sends and the parsing of what tmux answers. The
//  terminal still opens the ordinary PTY shell; the attach line is typed into it, the way a
//  workgroup's startup command is, because the PTY channel only ever asks for a shell.
//
//  **Every command goes through `sh -c`.** An exec channel runs the user's login shell, and fish
//  does not read `{ …; }` or `2>/dev/null ||` chains the way sh does. The typed attach line is the
//  one exception — it is typed into whatever shell the host gives — so it sticks to syntax bash,
//  zsh and fish all share: `command -v`, `&&`, `exec`, single quotes.
//

import Foundation

enum TerminalTmux {
    /// The prefix of the sessions Glass names. Sessions with other names are the user's own.
    static let namePrefix = "glass-"

    /// One tmux session on a host.
    struct Session: Equatable, Sendable, Identifiable {
        var name: String
        /// Clients attached right now, on any device.
        var attachedClients: Int
        var windows: Int
        var lastActivity: Date?
        var id: String { name }
        var isGlass: Bool { TerminalTmux.glassNumber(name) != nil }
    }

    enum Listing: Equatable, Sendable {
        /// tmux is not installed on the host.
        case unavailable
        /// tmux is there; an empty list when no server is running.
        case sessions([Session])
    }

    private static let missingMarker = "__glass_no_tmux__"

    /// Lists the host's sessions, or says tmux is missing. Exits 0 either way: "no server running"
    /// is an empty list, not a failure.
    static var listCommand: String {
        let script = "command -v tmux >/dev/null 2>&1 || { echo \(missingMarker); exit 0; }; "
            + "tmux list-sessions -F '#{session_name}\t#{session_attached}\t#{session_windows}\t#{session_activity}' "
            + "2>/dev/null; exit 0"
        return "sh -c \(quoted(script))"
    }

    static func parse(_ output: String) -> Listing {
        if output.contains(missingMarker) { return .unavailable }
        let sessions = output.split(whereSeparator: \.isNewline).compactMap { line -> Session? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 4, !fields[0].isEmpty else { return nil }
            return Session(name: String(fields[0]),
                           attachedClients: Int(fields[1]) ?? 0,
                           windows: Int(fields[2]) ?? 1,
                           lastActivity: TimeInterval(fields[3]).map(Date.init(timeIntervalSince1970:)))
        }
        return .sessions(sessions)
    }

    /// The first `glass-N` that neither the host nor this device is using.
    static func nextName(avoiding taken: Set<String>) -> String {
        var number = 1
        while taken.contains("\(namePrefix)\(number)") { number += 1 }
        return "\(namePrefix)\(number)"
    }

    static func glassNumber(_ name: String) -> Int? {
        guard name.hasPrefix(namePrefix) else { return nil }
        return Int(name.dropFirst(namePrefix.count)).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The line typed into the shell: attach to the session, or create it. `exec` replaces the
    /// shell, so detaching from tmux ends the terminal cleanly instead of leaving a bare prompt.
    /// The leading space keeps it out of shell history where `ignorespace` is set. Without tmux
    /// the line does nothing and the shell stays.
    static func attachLine(name: String, takeOver: Bool) -> String {
        " command -v tmux >/dev/null && exec tmux new-session -A\(takeOver ? " -D" : "") -s \(quoted(name))"
    }

    /// The directory the session's active pane is in. tmux keeps the shell's OSC 7 reports to
    /// itself, so in tmux this is the only accurate answer to "where is this shell?". The target
    /// is a pane, so the exact session name needs its colon: `=name` alone answers nothing
    /// (found live on the test VM, tmux 3.6).
    static func currentPathCommand(name: String) -> String {
        "sh -c \(quoted("tmux display-message -p -t \(quoted("=" + name + ":")) '#{pane_current_path}'"))"
    }

    static func killCommand(name: String) -> String {
        "sh -c \(quoted("tmux kill-session -t \(quoted("=" + name))"))"
    }

    /// POSIX single quoting. `'\''` also reads correctly in fish, where `\'` outside quotes is a quote.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Open a terminal in a tmux session that is already running — Active's attach and take over.
struct TerminalTmuxAttachment: Equatable, Sendable {
    var name: String
    var takeOver: Bool = false
}
