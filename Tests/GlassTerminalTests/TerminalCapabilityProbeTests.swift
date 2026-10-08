import Foundation
import Testing
import SwiftTerm

/// What a full-screen program asks the terminal before it decides how to draw, and what the
/// SwiftTerm we ship answers (2026-10-07).
///
/// Claude Code 2.1 asks XTVERSION first and asks about synchronized output (DEC 2026) only if
/// XTVERSION is answered; without synchronized output it also leaves scroll regions off and redraws
/// by moving the cursor, which is what made it scroll in and jump here on SwiftTerm 1.18. These
/// tests pin the answers, so a SwiftTerm update that loses one fails here rather than on screen.
@Suite("Terminal answers the questions TUIs ask")
struct TerminalCapabilityProbeTests {
    /// A terminal with nothing attached, collecting what it sends back to the program.
    final class Probe: TerminalDelegate {
        var replies = Data()
        lazy var terminal = Terminal(delegate: self, options: TerminalOptions(cols: 80, rows: 24))

        func send(source: Terminal, data: ArraySlice<UInt8>) { replies.append(contentsOf: data) }

        /// Feeds `query` and returns what came back, as text with ESC written `^[`.
        func ask(_ query: String) -> String {
            replies.removeAll()
            terminal.feed(text: query)
            return String(decoding: replies, as: UTF8.self).replacingOccurrences(of: "\u{1b}", with: "^[")
        }
    }

    @Test("XTVERSION names the terminal, so the program goes on to ask about the rest")
    func identity() {
        let reply = Probe().ask("\u{1b}[>0q")
        #expect(reply.hasPrefix("^[P>|SwiftTerm") && reply.hasSuffix("^[\\"), "reply was \(reply)")
    }

    @Test("synchronized output (DEC 2026) is reported as supported, and as set while a frame is open")
    func synchronizedOutput() {
        let probe = Probe()
        #expect(probe.ask("\u{1b}[?2026$p") == "^[[?2026;2$y")
        _ = probe.ask("\u{1b}[?2026h")
        #expect(probe.ask("\u{1b}[?2026$p") == "^[[?2026;1$y")
        #expect(probe.terminal.synchronizedOutputActive)
        _ = probe.ask("\u{1b}[?2026l")
        #expect(!probe.terminal.synchronizedOutputActive)
    }

    @Test("bracketed paste and the alternate screen are reported")
    func modes() {
        let probe = Probe()
        #expect(probe.ask("\u{1b}[?2004$p") == "^[[?2004;2$y")
        // SwiftTerm 1.20 reports the alternate screen as mode 47 only; 1049 (the one programs set)
        // answers "unknown". No program we know of asks about 1049 this way.
        #expect(probe.ask("\u{1b}[?47$p") == "^[[?47;2$y")
    }

    @Test("primary device attributes are answered: the probe's end marker")
    func deviceAttributes() {
        let reply = Probe().ask("\u{1b}[c")
        #expect(reply.hasPrefix("^[[?") && reply.hasSuffix("c"), "reply was \(reply)")
    }

    @Test("the kitty keyboard protocol query is answered")
    func kittyKeyboard() {
        let reply = Probe().ask("\u{1b}[?u")
        #expect(reply.hasPrefix("^[[?") && reply.hasSuffix("u"), "reply was \(reply)")
    }
}
