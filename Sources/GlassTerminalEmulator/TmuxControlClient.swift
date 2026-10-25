//
//  TmuxControlClient.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  A terminal kept in tmux as a control-mode client (D83; the owner, 2026-10-19: "I need to be able to
//  drag select through a scroll", then "2." for control mode, then "write up the plan, then build it").
//
//  Attached the ordinary way, tmux draws its own screen on the terminal's alternate screen: the history
//  stays in tmux, a scroll redraws the screen in place, and output faster than tmux draws never reaches
//  the terminal at all (measured: 32 of 60 lines printed at once over SSH). As a control-mode client
//  (`tmux -CC`), tmux instead hands over every byte the pane's program writes, and the terminal draws
//  it as it draws a plain shell: its own history, the program's own alternate screen and mouse, and a
//  session that still outlives the connection. iTerm2 is the only complete client; this follows what
//  its code and Ghostty's (the state machine shape: bytes in, actions out, no I/O) learned the hard way
//  (`memory-bank/tasks/2026-10/2026-10-19_tmux-scrollback.md`).
//
//  One session, one window, one pane: the window's active pane is followed and nothing else is drawn.
//

import Foundation

/// What the client asks of the code around it.
public enum TmuxControlAction: Equatable, Sendable {
    /// Bytes for the terminal emulator to read.
    case terminal(Data)
    /// Bytes for tmux, written to the PTY it runs on.
    case transport(Data)
    /// The pane is drawn and followed; held input has been sent. Once per attach.
    case live
    /// tmux ended the client (`%exit`): detached, or the session ended. What follows on the PTY is
    /// the shell's again, if anything.
    case exited(reason: String?)
    /// The grid for the terminal to show the pane at: tmux's window's while another client has it —
    /// the same session open on another device — so the program's lines break where it broke them,
    /// with the space beyond marked (`own` false); its own again once the window is (2026-10-22).
    /// The terminal's frame stays its own, and its own size still goes to tmux.
    case showGrid(columns: Int, rows: Int, own: Bool)
}

/// The control-mode client: bytes from tmux, keystrokes and sizes in; what to draw and what to send out.
/// No I/O, so its every step can be checked against a recorded exchange.
public struct TmuxControlClient: Sendable {
    public enum Phase: Equatable, Sendable {
        /// Before tmux says it is a control client: the bytes are the shell's.
        case shell
        /// tmux has said so; its first reply or session is awaited, then the pane asked for.
        case starting
        /// The pane is being read; its output waits until it has been.
        case restoring
        /// The pane's output is drawn as it comes.
        case live
        /// tmux has ended the client.
        case exited
    }

    public private(set) var phase: Phase = .shell
    /// The pane drawn, as tmux names it (`%3`), once known.
    public private(set) var pane: String?
    private var window: String?
    private(set) var columns: Int
    private(set) var rows: Int
    /// The most history put above the screen when the pane is read.
    private let historyLines: Int

    private var stream = TmuxControlStream()
    /// Commands sent and not yet answered, oldest first. tmux answers in order; numbers are the
    /// server's, shared with every other client, so they are not used to match.
    private var awaiting: [Awaited] = []
    private var nextLine = 0
    /// The reply being read: its guard's time and number, whether it is ours, and its lines.
    private var block: (time: Substring, number: Substring, ours: Bool, lines: [[UInt8]])?
    private var restore = TmuxPaneRestore.Draft()
    /// Keystrokes from before the pane was known, sent once it is.
    private var heldInput: [UInt8] = []
    private var announcedLive = false
    private var askedAtStart = false
    /// The session attached (`$1`), as tmux last named it.
    private var session: String?
    /// The window's size, as its last layout gave it; nil before one has. tmux gives a window the
    /// size of the client that switched to its session last (`window-size latest`; measured, tmux
    /// 3.8: another client's typing or sizes don't take it back), so with a session open on the Mac
    /// and the headset this is the other's size whenever the other was switched to last.
    private var windowSize: (columns: Int, rows: Int)?
    /// A claim sent and not yet answered by a layout: one is enough.
    private var claimPending = false
    /// The grid last told (`showGrid`); nil until another client has first had the window.
    private var shownGrid: (columns: Int, rows: Int)?
    /// A size sent and tmux's window not yet read back: what was known of the window is from before
    /// it, and a terminal alone on its session would look like another's for that moment.
    private var windowSizePending = false

    /// - Parameter overPipe: tmux runs as `-C` on pipes rather than `-CC` on a terminal: no start
    ///   marker, its protocol from the first byte.
    public init(columns: Int, rows: Int, historyLines: Int = 10_000, overPipe: Bool = false) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.historyLines = max(0, historyLines)
        if overPipe {
            phase = .starting
            stream = TmuxControlStream(protocolFromStart: true)
        }
    }

    /// True from tmux's start to its `%exit`: input must go through `input`, never straight to the PTY.
    public var isActive: Bool { phase != .shell && phase != .exited }

    // MARK: - Bytes from tmux

    public mutating func receive(_ data: Data) -> [TmuxControlAction] {
        var actions: [TmuxControlAction] = []
        stream.append(Array(data))
        // A piece at a time: `%exit` changes how the bytes after it are read.
        while let piece = stream.next() {
            switch piece {
            case .shell(let bytes):
                actions.append(.terminal(Data(bytes)))
            case .started:
                phase = .starting
                awaiting.removeAll()
                block = nil
                pane = nil
                window = nil
                announcedLive = false
                askedAtStart = false
                session = nil
                windowSize = nil
                claimPending = false
                shownGrid = nil
                windowSizePending = false
            case .line(let line):
                actions += handle(line)
            }
        }
        return Self.coalesced(actions)
    }

    private mutating func handle(_ line: [UInt8]) -> [TmuxControlAction] {
        // Inside a reply every line is the reply's, whatever it says — a captured pane can show
        // control-mode text — until the guard with this reply's own time and number.
        if var open = block {
            if let guardLine = TmuxControlLine.guardLine(line), guardLine.keyword != "%begin",
               guardLine.time == open.time, guardLine.number == open.number {
                block = nil
                // The attach command's own reply: tmux has attached this client.
                guard open.ours else { return startIfDue() }
                return answered(lines: open.lines, error: guardLine.keyword == "%error")
            }
            open.lines.append(line)
            block = open
            return []
        }
        switch TmuxControlLine(line) {
        case .begin(let time, let number, let flags):
            // Flags 0: a command that didn't come from this client, such as the attach itself.
            block = (time, number, flags != "0", [])
            return []
        case .output(let pane, let data):
            guard phase == .live, pane == self.pane else { return [] }
            return [.terminal(Data(data))]
        case .pause(let pane):
            guard pane == self.pane else { return [] }
            // Output older than the client could take was dropped: carry on, and read the pane again.
            return send("refresh-client -A '\(pane):continue'", as: .ignored) + readPane()
        case .sessionChanged(let id):
            // The first is the attach; a later one, the session gone and another in its place — or
            // this client's own switch to the session it is on (`claim`), which changes nothing to
            // read again.
            if phase == .starting {
                session = id
                return startIfDue()
            }
            if let id, id == session { return [] }
            session = id
            return phase == .live || phase == .restoring ? askForPane() : []
        case .layoutChange(let window, let layout):
            guard window == self.window, let size = TmuxLayout.windowSize(layout) else { return [] }
            windowSize = size
            windowSizePending = false
            claimPending = false
            return noteGrid(force: false)
        case .sessionWindowChanged:
            return phase == .live || phase == .restoring ? askForPane() : []
        case .windowPaneChanged(let window, let pane):
            guard window == self.window, pane != self.pane, phase == .live || phase == .restoring else { return [] }
            self.pane = pane
            return readPane()
        case .exit(let reason):
            phase = .exited
            awaiting.removeAll()
            stream.endProtocol()
            return [.exited(reason: reason)]
        case .other:
            return []
        }
    }

    // MARK: - Commands and their replies

    private enum Purpose: Sendable {
        case ignored
        /// `WxH`: the window's size, read back after a size was sent.
        case windowSize
        case paneAndWindow
        case restore(TmuxPaneRestore.Part)
    }

    private struct Awaited: Sendable {
        let line: Int
        let purpose: Purpose
    }

    /// One command on a line of its own.
    private mutating func send(_ command: String, as purpose: Purpose) -> [TmuxControlAction] {
        sendLine([(command, purpose)])
    }

    /// Commands on one line: tmux runs them together, with no pane read in between.
    private mutating func sendLine(_ commands: [(String, Purpose)]) -> [TmuxControlAction] {
        let line = nextLine
        nextLine += 1
        awaiting += commands.map { Awaited(line: line, purpose: $0.1) }
        let text = commands.map(\.0).joined(separator: " ; ") + "\n"
        return [.transport(Data(text.utf8))]
    }

    private mutating func answered(lines: [[UInt8]], error: Bool) -> [TmuxControlAction] {
        guard !awaiting.isEmpty else { return [] }
        let answered = awaiting.removeFirst()
        var actions = finish(answered.purpose, lines: error ? nil : lines)
        if error {
            // After an error tmux runs nothing more of that line, and answers none of it.
            while let next = awaiting.first, next.line == answered.line {
                awaiting.removeFirst()
                actions += finish(next.purpose, lines: nil)
            }
        }
        return actions
    }

    private mutating func finish(_ purpose: Purpose, lines: [[UInt8]]?) -> [TmuxControlAction] {
        switch purpose {
        case .ignored:
            return []
        case .windowSize:
            windowSizePending = false
            if let reply = lines?.first.map({ String(decoding: $0, as: UTF8.self) }) {
                let parts = reply.split(separator: "x")
                if parts.count == 2, let columns = Int(parts[0]), let rows = Int(parts[1]) { windowSize = (columns, rows) }
            }
            return noteGrid(force: isForeign)
        case .paneAndWindow:
            guard let lines, let reply = lines.first.map({ String(decoding: $0, as: UTF8.self) }) else { return [] }
            let parts = reply.split(separator: " ")
            guard let pane = parts.first, pane.hasPrefix("%") else { return [] }
            self.pane = String(pane)
            window = parts.count > 1 ? String(parts[1]) : nil
            return readPane()
        case .restore(let part):
            restore.record(part, lines: lines)
            guard restore.isComplete else { return [] }
            let draft = restore
            restore = TmuxPaneRestore.Draft()
            phase = .live
            var actions: [TmuxControlAction] = [.terminal(TmuxPaneRestore.bytes(for: draft, columns: columns, rows: rows))]
            if !announcedLive {
                announcedLive = true
                actions.append(.live)
            }
            if !heldInput.isEmpty, let pane {
                let held = heldInput
                heldInput.removeAll()
                actions += sendKeys(held, to: pane)
            }
            return actions
        }
    }

    /// Once tmux has attached this client — its first `%session-changed`, or the attach command's
    /// reply, whichever comes first — and only then: nothing is typed at a shell that merely printed
    /// the start marker.
    private mutating func startIfDue() -> [TmuxControlAction] {
        guard phase == .starting, !askedAtStart else { return [] }
        askedAtStart = true
        return askForPane()
    }

    /// Sized to this terminal, never to a placeholder (iTerm2 once shrank people's windows so), told
    /// to pause rather than fall far behind, and asked which pane to draw.
    private mutating func askForPane() -> [TmuxControlAction] {
        var actions: [TmuxControlAction] = []
        if phase == .starting {
            actions += send("refresh-client -C \(columns),\(rows)", as: .ignored)
            actions += send("refresh-client -f pause-after=30", as: .ignored)
        }
        actions += send("display-message -p '#{pane_id} #{window_id}'", as: .paneAndWindow)
        return actions
    }

    /// The pane's history, screen, state and any escape sequence it is in the middle of, on one line,
    /// so no output falls between them; its output is dropped until the last of them is answered.
    private mutating func readPane() -> [TmuxControlAction] {
        guard let pane else { return [] }
        phase = .restoring
        restore = TmuxPaneRestore.Draft()
        return sendLine(TmuxPaneRestore.commands(pane: pane, historyLines: historyLines).map { ($0.command, .restore($0.part)) })
    }

    // MARK: - Keystrokes and sizes

    /// Keystrokes, pasted text and typed commands, as the terminal encoded them.
    public mutating func input(_ data: Data) -> [TmuxControlAction] {
        guard !data.isEmpty else { return [] }
        switch phase {
        case .exited:
            return [.transport(data)]
        case .shell:
            // tmux is on its way: typed at the shell now, tmux would read it as its commands.
            heldInput += Array(data)
            return []
        case .starting, .restoring, .live:
            guard let pane else {
                heldInput += Array(data)
                return []
            }
            return sendKeys(Array(data), to: pane)
        }
    }

    private mutating func sendKeys(_ bytes: [UInt8], to pane: String) -> [TmuxControlAction] {
        var actions: [TmuxControlAction] = []
        for command in TmuxSendKeys.commands(for: bytes, pane: pane) {
            actions += send(command, as: .ignored)
        }
        return Self.coalesced(actions)
    }

    /// **The terminal in front takes its session's window** (the owner, 2026-10-22: "do the focus
    /// claim"): focused, or its window made the key one, while tmux has the window at another
    /// client's size — the same session open on the Mac and the headset — it switches to its own
    /// session, which is what makes tmux size the window to it, and the program redraws for it.
    /// Nothing while the window is this terminal's size already, or a claim is unanswered.
    public mutating func claim() -> [TmuxControlAction] {
        guard phase == .live, let pane, let windowSize, !claimPending,
              windowSize.columns != columns || windowSize.rows != rows else { return [] }
        claimPending = true
        return send("switch-client -t \(pane)", as: .ignored)
    }

    /// tmux never started (the attach failed at the shell): what was held, to be typed there after
    /// all. The client has nothing more to do.
    public mutating func abandon() -> Data {
        let held = heldInput
        heldInput.removeAll()
        phase = .exited
        return Data(held)
    }

    /// The terminal's new size — its own, fitted to its frame — for tmux to size the window to.
    public mutating func resize(columns: Int, rows: Int) -> [TmuxControlAction] {
        let columns = max(1, columns), rows = max(1, rows)
        let changed = columns != self.columns || rows != self.rows
        self.columns = columns
        self.rows = rows
        // Once the start has sent a size, every change goes too: one made while the pane was being
        // asked for was kept here and never reached tmux, and the pane stayed the placeholder's
        // size under a taller terminal (2026-10-20).
        guard phase == .live || phase == .restoring || (phase == .starting && askedAtStart) else { return [] }
        if changed {
            var commands: [(String, Purpose)] = [("refresh-client -C \(columns),\(rows)", .ignored)]
            // What tmux made of it, read back rather than assumed: the window this size, or still
            // another client's. Until then nothing is decided.
            if windowSize != nil {
                windowSizePending = true
                commands.append(("display-message -p '#{window_width}x#{window_height}'", .windowSize))
            }
            return sendLine(commands)
        }
        // The terminal fitted itself to its frame again at the same size: while another client has
        // the window, it goes back to that size.
        return noteGrid(force: isForeign)
    }

    /// Whether tmux has the window at another client's size.
    private var isForeign: Bool {
        guard let windowSize else { return false }
        return windowSize.columns != columns || windowSize.rows != rows
    }

    /// The grid to show, told when it changes (or `force`): tmux's window's while it is another
    /// client's size, the terminal's own otherwise. Nothing until another client has first had it.
    private mutating func noteGrid(force: Bool) -> [TmuxControlAction] {
        guard !windowSizePending else { return [] }
        let grid: (columns: Int, rows: Int) = isForeign ? windowSize! : (columns, rows)
        if let shownGrid {
            guard force || shownGrid != grid else { return [] }
        } else if !isForeign {
            return []
        }
        shownGrid = grid
        return [.showGrid(columns: grid.columns, rows: grid.rows, own: !isForeign)]
    }

    /// Neighbouring sends and draws joined, so a burst is one write and one feed.
    private static func coalesced(_ actions: [TmuxControlAction]) -> [TmuxControlAction] {
        var result: [TmuxControlAction] = []
        for action in actions {
            switch (result.last, action) {
            case (.terminal(let a)?, .terminal(let b)):
                result[result.count - 1] = .terminal(a + b)
            case (.transport(let a)?, .transport(let b)):
                result[result.count - 1] = .transport(a + b)
            default:
                result.append(action)
            }
        }
        return result
    }

    // MARK: - Versions

    /// Whether `tmux -V`'s answer is a tmux with what this client relies on: 3.2, for pausing a
    /// client that falls behind and the `-f` and `-A` it is driven with. `next-3.9` and an OpenBSD
    /// build (`openbsd-7.6`, always current) count; nothing readable does not.
    public static func supports(version: String) -> Bool {
        let text = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.contains("openbsd") { return true }
        guard let start = text.firstIndex(where: \.isNumber) else { return false }
        let numbers = text[start...].prefix { $0.isNumber || $0 == "." }.split(separator: ".").compactMap { Int($0) }
        guard let major = numbers.first else { return false }
        let minor = numbers.count > 1 ? numbers[1] : 0
        return major > 3 || (major == 3 && minor >= 2)
    }
}

// MARK: - The byte stream

/// Splits what arrives on the PTY: the shell's bytes until tmux's `ESC P 1000 p`, then protocol lines
/// (`\r\n`, since the PTY keeps output translation on), then, after `%exit` and its ST, the shell's
/// again. A marker or line cut by the end of a read is held for the next.
struct TmuxControlStream: Sendable {
    enum Piece: Equatable { case shell([UInt8]), started, line([UInt8]) }
    private enum Mode { case shell, protocolLines, closing }

    static let start: [UInt8] = [0x1B, 0x50, 0x31, 0x30, 0x30, 0x30, 0x70]  // ESC P 1000 p
    private var mode = Mode.shell
    private var buffer: [UInt8] = []
    private var index = 0

    init(protocolFromStart: Bool = false) {
        mode = protocolFromStart ? .protocolLines : .shell
    }

    mutating func append(_ bytes: [UInt8]) {
        if index > 0 {
            buffer.removeFirst(index)
            index = 0
        }
        buffer += bytes
    }

    /// After `%exit`: an ST, then the shell's bytes.
    mutating func endProtocol() { mode = .closing }

    mutating func next() -> Piece? {
        while index < buffer.count {
            switch mode {
            case .shell:
                if let found = Self.find(Self.start, in: buffer, from: index) {
                    if found > index {
                        let shell = Array(buffer[index..<found])
                        index = found
                        return .shell(shell)
                    }
                    index = found + Self.start.count
                    mode = .protocolLines
                    return .started
                }
                // Hold what could be the start of the marker; the rest is the shell's.
                let keep = Self.partialSuffix(of: Self.start, in: buffer, from: index)
                guard buffer.count - keep > index else { return nil }
                let shell = Array(buffer[index..<(buffer.count - keep)])
                index = buffer.count - keep
                return .shell(shell)
            case .protocolLines:
                guard let newline = buffer[index...].firstIndex(of: 0x0A) else { return nil }
                var line = Array(buffer[index..<newline])
                if line.last == 0x0D { line.removeLast() }
                index = newline + 1
                return .line(line)
            case .closing:
                if buffer[index] == 0x1B {
                    guard index + 1 < buffer.count else { return nil }
                    if buffer[index + 1] == 0x5C { index += 2 }
                }
                mode = .shell
            }
        }
        return nil
    }

    private static func find(_ needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
        guard haystack.count - start >= needle.count else { return nil }
        var index = start
        while index <= haystack.count - needle.count {
            if haystack[index] == needle[0], Array(haystack[index..<(index + needle.count)]) == needle { return index }
            index += 1
        }
        return nil
    }

    /// How many of the last bytes are the beginning of `needle`.
    private static func partialSuffix(of needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int {
        let available = haystack.count - start
        for length in stride(from: min(needle.count - 1, available), to: 0, by: -1)
        where Array(haystack[(haystack.count - length)...]) == Array(needle[..<length]) {
            return length
        }
        return 0
    }
}

// MARK: - Lines

enum TmuxControlLine: Equatable {
    case begin(time: Substring, number: Substring, flags: Substring)
    case output(pane: String, data: [UInt8])
    case pause(pane: String)
    /// `%session-changed $1 name`: the session attached, by its id.
    case sessionChanged(id: String?)
    case sessionWindowChanged
    case windowPaneChanged(window: String, pane: String)
    /// `%layout-change @window layout visible-layout flags`: the window's size and its panes'.
    case layoutChange(window: String, layout: String)
    case exit(reason: String?)
    case other

    init(_ line: [UInt8]) {
        if line.starts(with: Array("%output ".utf8)) || line.starts(with: Array("%extended-output ".utf8)) {
            self = Self.output(line)
            return
        }
        let text = String(decoding: line, as: UTF8.self)
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        switch words.first {
        case "%begin":
            guard let guardLine = Self.guardLine(line) else { self = .other; return }
            self = .begin(time: guardLine.time, number: guardLine.number, flags: guardLine.flags)
        case "%pause" where words.count >= 2:
            self = .pause(pane: String(words[1]))
        case "%session-changed":
            self = .sessionChanged(id: words.count > 1 ? String(words[1]) : nil)
        case "%session-window-changed":
            self = .sessionWindowChanged
        case "%window-pane-changed" where words.count >= 3:
            self = .windowPaneChanged(window: String(words[1]), pane: String(words[2]))
        case "%layout-change" where words.count >= 3:
            self = .layoutChange(window: String(words[1]), layout: String(words[2]))
        case "%exit":
            let reason = words.dropFirst().joined(separator: " ")
            self = .exit(reason: reason.isEmpty ? nil : reason)
        default:
            self = .other
        }
    }

    /// `%begin`, `%end` or `%error` with its three numbers, and nothing else on the line.
    static func guardLine(_ line: [UInt8]) -> (keyword: Substring, time: Substring, number: Substring, flags: Substring)? {
        guard line.first == 0x25 else { return nil }
        let text = String(decoding: line, as: UTF8.self)
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count == 4, ["%begin", "%end", "%error"].contains(words[0]),
              words[1...].allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return (words[0], words[1], words[2], words[3])
    }

    /// `%output %P data` or `%extended-output %P age … : data`, with tmux's octal escapes undone.
    private static func output(_ line: [UInt8]) -> Self {
        let extended = line.starts(with: Array("%extended-output ".utf8))
        var index = extended ? 17 : 8
        guard let paneEnd = line[index...].firstIndex(of: 0x20) else { return .other }
        let pane = String(decoding: line[index..<paneEnd], as: UTF8.self)
        index = paneEnd + 1
        if extended {
            // The arguments end at a lone `:`.
            var found: Int?
            var cursor = index
            while cursor + 1 < line.count {
                if line[cursor] == 0x3A, line[cursor + 1] == 0x20, cursor > 0, line[cursor - 1] == 0x20 {
                    found = cursor + 2
                    break
                }
                cursor += 1
            }
            guard let found else { return .other }
            index = found
        }
        return .output(pane: pane, data: unescaped(line[index...]))
    }

    /// tmux writes bytes below 0x20 and `\` as `\ooo`; everything else as it is.
    static func unescaped(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == 0x5C, bytes.endIndex - index >= 4, let value = octal(bytes[(index + 1)...(index + 3)]) {
                result.append(value)
                index += 4
            } else {
                result.append(byte)
                index += 1
            }
        }
        return result
    }

    private static func octal(_ digits: ArraySlice<UInt8>) -> UInt8? {
        var value = 0
        for digit in digits {
            guard (0x30...0x37).contains(digit) else { return nil }
            value = value * 8 + Int(digit - 0x30)
        }
        return value <= 255 ? UInt8(value) : nil
    }
}

// MARK: - Keystrokes as commands

/// What the terminal sends, as `send-keys` commands for one pane: runs of plain ASCII literally, every
/// other byte in hex — `-H` passes bytes to the program as they are, so it gets exactly what the
/// terminal encoded for the modes the program asked for. Each command under 1,000 characters (tmux
/// 1.8 crashed past 1,024; iTerm2 has kept to 1,000 since).
enum TmuxSendKeys {
    static let commandLimit = 1_000

    static func commands(for bytes: [UInt8], pane: String) -> [String] {
        var commands: [String] = []
        var index = 0
        while index < bytes.count {
            if isLiteral(bytes[index]) {
                let prefix = "send-keys -l -t \(pane) -- '"
                var end = index
                while end < bytes.count, isLiteral(bytes[end]), end - index < commandLimit - prefix.count - 1 { end += 1 }
                commands.append(prefix + String(decoding: bytes[index..<end], as: UTF8.self) + "'")
                index = end
            } else {
                var command = "send-keys -H -t \(pane)"
                while index < bytes.count, !isLiteral(bytes[index]), command.count + 3 <= commandLimit {
                    command += " " + String(format: "%02x", bytes[index])
                    index += 1
                }
                commands.append(command)
            }
        }
        return commands
    }

    /// Printable ASCII but the quote itself, which single quotes cannot hold.
    private static func isLiteral(_ byte: UInt8) -> Bool {
        (0x20...0x7E).contains(byte) && byte != 0x27
    }
}

// MARK: - Layouts

/// tmux's layout strings: a checksum, then the window's cell, `WxH,X,Y` and its pane or panes.
enum TmuxLayout {
    /// The window's size: the first cell's `WxH`, after the checksum.
    static func windowSize(_ layout: String) -> (columns: Int, rows: Int)? {
        guard let comma = layout.firstIndex(of: ",") else { return nil }
        let cell = layout[layout.index(after: comma)...].prefix { $0 != "," }
        let parts = cell.split(separator: "x")
        guard parts.count == 2, let columns = Int(parts[0]), let rows = Int(parts[1]) else { return nil }
        return (columns, rows)
    }
}
