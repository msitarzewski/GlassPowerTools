import Foundation
import Testing
import SwiftTerm
@testable import GlassTerminalEmulator

/// The control-mode client, step by step (D83, 2026-10-19): what tmux sends in, what the client draws
/// and what it sends back. tmux's side is written out as tmux writes it — `%begin`/`%end` guards,
/// `\r\n` line ends, octal escapes — so each step is the exchange a real attach has, without tmux.
@Suite("tmux control mode, step by step")
struct TmuxControlClientTests {
    private struct Exchange {
        var client = TmuxControlClient(columns: 80, rows: 24, historyLines: 500)
        var drawn = Data()
        var sent = ""
        var live = 0
        var exited: String??

        mutating func receive(_ text: String) { apply(client.receive(Data(text.utf8))) }
        mutating func type(_ text: String) { apply(client.input(Data(text.utf8))) }

        mutating func apply(_ actions: [TmuxControlAction]) {
            for action in actions {
                switch action {
                case .terminal(let data): drawn += data
                case .transport(let data): sent += String(decoding: data, as: UTF8.self)
                case .live: live += 1
                case .exited(let reason): exited = .some(reason)
                }
            }
        }

        /// What was sent since last asked, a command line each.
        mutating func takeSent() -> [String] {
            defer { sent = "" }
            return sent.split(separator: "\n").map(String.init)
        }

        mutating func takeDrawn() -> String {
            defer { drawn = Data() }
            return String(decoding: drawn, as: UTF8.self)
        }
    }

    private var counter = 100
    /// A reply as tmux writes it, `lines` between its guards.
    private func reply(_ number: Int, _ lines: [String] = [], error: Bool = false) -> String {
        (["%begin 1700000000 \(number) 1"] + lines + ["\(error ? "%error" : "%end") 1700000000 \(number) 1"])
            .map { $0 + "\r\n" }.joined()
    }

    /// Attached and drawn: tmux started, the pane asked for and read.
    private func attached(screen: [String] = ["$ "], state: String = "0,0,0,2,0,0,23,1,0,0,0,1,0,0,0,0,0,0,80,24,0")
    -> Exchange {
        var exchange = Exchange()
        exchange.receive("Last login: today\r\n\u{1B}P1000p%begin 1 1 0\r\n%end 1 1 0\r\n%session-changed $1 alpha\r\n")
        _ = exchange.takeSent()
        exchange.receive(reply(1) + reply(2) + reply(3, ["%3 @1"]))
        _ = exchange.takeSent()
        exchange.receive(reply(4) + reply(5, screen) + reply(6, screen) + reply(7) + reply(8, [state]) + reply(9))
        return exchange
    }

    @Test("the shell's bytes are drawn until tmux starts; then it is sized, told to pause, and asked for the pane")
    func start() {
        var exchange = Exchange()
        exchange.receive("Last login: today\r\n$ exec tmux -CC new-session\r\n\u{1B}P10")
        #expect(exchange.takeDrawn() == "Last login: today\r\n$ exec tmux -CC new-session\r\n", "the marker, cut, is held")
        exchange.receive("00p%begin 1700000000 278 0\r\n%end 1700000000 278 0\r\n")
        #expect(exchange.client.phase == .starting)
        #expect(exchange.takeSent() == ["refresh-client -C 80,24", "refresh-client -f pause-after=30",
                                        "display-message -p '#{pane_id} #{window_id}'"],
                "once the attach is answered, and nothing typed before it")
        exchange.receive("%session-changed $1 alpha\r\n")
        #expect(exchange.takeSent().isEmpty, "asked once")
    }

    @Test("the pane is read on one line, its output dropped until the last answer, then drawn as it comes")
    func restore() {
        var exchange = Exchange()
        exchange.receive("\u{1B}P1000p%session-changed $1 alpha\r\n")
        _ = exchange.takeSent()
        exchange.receive(reply(1) + reply(2) + reply(3, ["%3 @1"]))
        let restore = exchange.takeSent()
        #expect(restore.count == 1, "one line, so no output falls between its commands")
        #expect(restore.first?.hasPrefix("capture-pane -p -e -q -J -S -500 -E -1 -t %3 ; ") == true)
        #expect(restore.first?.contains("display-message -p -t %3 '#{alternate_on},") == true)
        #expect(exchange.client.phase == .restoring)

        // Output already in the capture, queued before it: dropped.
        exchange.receive("%output %3 old\\015\\012\r\n")
        exchange.receive(reply(4, ["one", "two"]) + reply(5, ["$ ls"]) + reply(6, ["$ ls"]) + reply(7))
        #expect(exchange.takeDrawn().isEmpty, "nothing until the last answer")
        exchange.receive(reply(8, ["0,0,0,4,1,0,23,1,0,0,0,1,0,0,0,0,0,1,80,24,2"]) + reply(9))
        let drawn = exchange.takeDrawn()
        #expect(drawn.contains("one\r\ntwo\r\n$ ls"), "the history, then the screen")
        #expect(drawn.contains("\u{1B}[2;5H"), "the cursor where tmux has it")
        #expect(drawn.contains("\u{1B}[?2004h"), "bracketed paste, as the program asked")
        #expect(!drawn.contains("old"))
        #expect(exchange.live == 1 && exchange.client.phase == .live)

        exchange.receive("%output %3 new\\015\\012\r\n%output %4 another-pane\r\n")
        #expect(exchange.takeDrawn() == "new\r\n", "this pane's output, escapes undone; no other pane's")
    }

    @Test("with no history, the capture's one line isn't drawn twice")
    func noHistory() {
        var exchange = Exchange()
        exchange.receive("\u{1B}P1000p%session-changed $1 alpha\r\n" + reply(1) + reply(2) + reply(3, ["%3 @1"]))
        exchange.receive(reply(4, ["$ "]) + reply(5, ["$ "]) + reply(6, ["$ "]) + reply(7)
                         + reply(8, ["0,0,0,2,0,0,23,1,0,0,0,1,0,0,0,0,0,0,80,24,0"]) + reply(9))
        #expect(exchange.takeDrawn().components(separatedBy: "$ ").count == 2)
    }

    @Test("inside a reply every line is the reply's, even one reading %exit or another reply's %end")
    func replyLinesAreData() {
        var exchange = attached()
        _ = exchange.takeDrawn()
        exchange.type("x")
        _ = exchange.takeSent()
        exchange.receive("%begin 1700000000 50 1\r\n%exit\r\n%end 1700000000 49 1\r\n%end 1700000000 50 1\r\n")
        #expect(exchange.exited == nil && exchange.client.phase == .live)
        exchange.receive("%output %3 still\r\n")
        #expect(exchange.takeDrawn() == "still")
    }

    @Test("an error part-way along a line: the rest of it never answers, and the pane is drawn with what came")
    func errorMidLine() {
        var exchange = Exchange()
        exchange.receive("\u{1B}P1000p%session-changed $1 alpha\r\n" + reply(1) + reply(2) + reply(3, ["%3 @1"]))
        // The history capture fails: tmux runs nothing more of that line.
        exchange.receive(reply(4, ["parse error"], error: true))
        #expect(exchange.client.phase == .live, "drawn with what there was")
        #expect(exchange.live == 1)
        exchange.receive("%output %3 after\r\n")
        #expect(exchange.takeDrawn().hasSuffix("after"))
    }

    @Test("keystrokes before the pane is known are held, then sent to it")
    func heldInput() {
        var exchange = Exchange()
        exchange.type("ls\r")
        #expect(exchange.takeSent().isEmpty, "not typed at the shell tmux is replacing")
        exchange.receive("\u{1B}P1000p%session-changed $1 alpha\r\n" + reply(1) + reply(2) + reply(3, ["%3 @1"]))
        _ = exchange.takeSent()
        exchange.receive(reply(4) + reply(5, ["$ "]) + reply(6, ["$ "]) + reply(7)
                         + reply(8, ["0,0,0,2,0,0,23,1,0,0,0,1,0,0,0,0,0,0,80,24,0"]) + reply(9))
        #expect(exchange.takeSent() == ["send-keys -l -t %3 -- 'ls'", "send-keys -H -t %3 0d"])
    }

    @Test("what is typed reaches the program exactly: quotes, backslashes, semicolons, UTF-8, escapes")
    func encoding() {
        let pane = "%3"
        #expect(TmuxSendKeys.commands(for: Array("echo 'hi'; ~\\".utf8), pane: pane)
                == ["send-keys -l -t %3 -- 'echo '", "send-keys -H -t %3 27", "send-keys -l -t %3 -- 'hi'",
                    "send-keys -H -t %3 27", "send-keys -l -t %3 -- '; ~\\'"])
        #expect(TmuxSendKeys.commands(for: Array("é\u{1B}[A".utf8), pane: pane)
                == ["send-keys -H -t %3 c3 a9 1b", "send-keys -l -t %3 -- '[A'"])
        let long = Array(String(repeating: "a", count: 2_500).utf8)
        let commands = TmuxSendKeys.commands(for: long, pane: pane)
        #expect(commands.allSatisfy { $0.count <= TmuxSendKeys.commandLimit })
        #expect(commands.map { $0.split(separator: "'")[1].count }.reduce(0, +) == 2_500, "all of it, in pieces")
        let binary = Array(repeating: UInt8(0x01), count: 700)
        #expect(TmuxSendKeys.commands(for: binary, pane: pane).allSatisfy { $0.count <= TmuxSendKeys.commandLimit })
    }

    @Test("tmux's escapes are undone: control bytes and the backslash")
    func unescaping() {
        #expect(TmuxControlLine.unescaped(Array("a\\033[1mb\\134c\\015\\012".utf8)[...])
                == Array("a\u{1B}[1mb\\c\r\n".utf8))
        // A backslash without three octal digits is itself.
        #expect(TmuxControlLine.unescaped(Array("a\\9z".utf8)[...]) == Array("a\\9z".utf8))
    }

    @Test("a character cut between two output lines reaches the terminal whole")
    func splitCharacter() {
        var exchange = attached()
        _ = exchange.takeDrawn()
        // tmux writes bytes above 0x7F as they are, wherever its chunk ends: here, mid-character.
        let bytes = Array("é".utf8)
        exchange.apply(exchange.client.receive(Data("%output %3 ".utf8) + Data([bytes[0]]) + Data("\r\n".utf8)))
        exchange.apply(exchange.client.receive(Data("%output %3 ".utf8) + Data([bytes[1]]) + Data("\r\n".utf8)))
        #expect(exchange.drawn == Data(bytes))
    }

    @Test("paused for falling behind: carried on, and the pane read again")
    func pause() {
        var exchange = attached()
        _ = exchange.takeSent()
        exchange.receive("%pause %3\r\n")
        let sent = exchange.takeSent()
        #expect(sent.first == "refresh-client -A '%3:continue'")
        #expect(sent.count == 2 && sent[1].hasPrefix("capture-pane"))
        #expect(exchange.client.phase == .restoring)
    }

    @Test("the window's active pane changing: followed, and read")
    func paneChange() {
        var exchange = attached()
        _ = exchange.takeSent()
        exchange.receive("%window-pane-changed @2 %9\r\n")
        #expect(exchange.takeSent().isEmpty, "another window's")
        exchange.receive("%window-pane-changed @1 %9\r\n")
        #expect(exchange.client.pane == "%9")
        #expect(exchange.takeSent().first?.contains("-t %9") == true)
    }

    @Test("%exit: the client ends, the ST is passed over, and what follows is the shell's")
    func exit() {
        var exchange = attached()
        _ = exchange.takeDrawn()
        exchange.receive("%exit detached\r\n\u{1B}\\$ ")
        #expect(exchange.exited == .some("detached"))
        #expect(exchange.takeDrawn() == "$ ")
        exchange.type("ls")
        #expect(exchange.takeSent() == ["ls"], "the shell's again")
    }

    @Test("sizes go to tmux only when they change, and only once the pane is followed")
    func resize() {
        var exchange = Exchange()
        exchange.apply(exchange.client.resize(columns: 100, rows: 30))
        #expect(exchange.takeSent().isEmpty, "not yet attached; the start sends the size")
        var live = attached()
        _ = live.takeSent()
        live.apply(live.client.resize(columns: 100, rows: 30))
        live.apply(live.client.resize(columns: 100, rows: 30))
        #expect(live.takeSent() == ["refresh-client -C 100,30"])
    }

    @Test("tmux 3.2 and later, as tmux -V says it")
    func versions() {
        #expect(TmuxControlClient.supports(version: "tmux 3.6\n"))
        #expect(TmuxControlClient.supports(version: "tmux 3.2a"))
        #expect(TmuxControlClient.supports(version: "tmux next-3.9"))
        #expect(TmuxControlClient.supports(version: "tmux openbsd-7.6"))
        #expect(!TmuxControlClient.supports(version: "tmux 3.1c"))
        #expect(!TmuxControlClient.supports(version: "tmux 2.9"))
        #expect(!TmuxControlClient.supports(version: ""))
        #expect(!TmuxControlClient.supports(version: "sh: tmux: not found"))
    }

    @Test("a program's alternate screen comes back over the primary, its cursor saved where it saved it")
    func alternateRestore() throws {
        var draft = TmuxPaneRestore.Draft()
        draft.record(.history, lines: [Array("earlier".utf8)])
        draft.record(.screen, lines: [Array("trimmed".utf8)])
        draft.record(.screenExact, lines: [Array("PROGRAM".utf8), Array("status".utf8)])
        draft.record(.primaryBehind, lines: [Array("$ vim".utf8), []])
        draft.record(.state, lines: [Array("1,5,0,3,1,0,1,1,0,1,0,1,0,0,0,0,0,0,20,2,1".utf8)])
        draft.record(.pending, lines: [])
        let bytes = TmuxPaneRestore.bytes(for: draft, columns: 20, rows: 2)

        final class Delegate: TerminalDelegate { func send(source: Terminal, data: ArraySlice<UInt8>) {} }
        let delegate = Delegate()
        let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: 20, rows: 2, scrollback: 100))
        terminal.feed(byteArray: Array(bytes))
        #expect(terminal.isCurrentBufferAlternate)
        #expect(terminal.getLine(row: 0)?.translateToString(trimRight: true) == "PROGRAM")
        #expect(terminal.getLine(row: 1)?.translateToString(trimRight: true) == "status")
        #expect(terminal.buffer.x == 3 && terminal.buffer.y == 1, "the cursor where the program has it")
        #expect(terminal.applicationCursor, "the program's cursor keys")
        terminal.feed(byteArray: Array("\u{1B}[?1049l".utf8))
        let primary = (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
        #expect(primary.first == "$ vim", "the shell behind it")
    }
}
