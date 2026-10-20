import Foundation
import SwiftTerm
import Testing
@testable import GlassTerminalEmulator

/// A terminal's last lines, read from its end (2026-10-19): the lines the engines read from the
/// whole buffer before, for the screen reader and the error explainer, at the cost of those lines.
@MainActor
@Suite("A terminal's last lines")
struct TerminalBufferTextTests {
    private final class Delegate: TerminalDelegate { func send(source: Terminal, data: ArraySlice<UInt8>) {} }
    private let delegate = Delegate()

    private func terminal(scrollback: Int = 100) -> Terminal {
        Terminal(delegate: delegate, options: TerminalOptions(cols: 20, rows: 5, scrollback: scrollback))
    }

    private func feed(_ terminal: Terminal, _ text: String) {
        terminal.feed(byteArray: Array(text.utf8))
    }

    /// What the engines read before: the whole buffer as text, its last lines with anything in them.
    private func whole(_ terminal: Terminal, _ count: Int) -> [String] {
        let lines = (String(data: terminal.getBufferAsData(), encoding: .utf8) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Array(lines.suffix(max(0, count)))
    }

    private func expectSame(_ terminal: Terminal, counts: [Int], _ comment: Comment) {
        for count in counts {
            #expect(SwiftTermBufferText.lastLines(count, of: terminal) == whole(terminal, count), comment)
        }
    }

    @Test("a screen not yet full")
    func shortScreen() {
        let terminal = terminal()
        feed(terminal, "one\r\ntwo")
        expectSame(terminal, counts: [0, 1, 2, 5], "two lines on a screen of five")
        #expect(SwiftTermBufferText.lastLines(5, of: terminal) == ["one", "two"])
    }

    @Test("history with blank lines among it, and a cleared screen below")
    func history() {
        let terminal = terminal()
        for i in 1...40 { feed(terminal, i % 3 == 0 ? "\r\n" : "line \(i)\r\n") }
        feed(terminal, "\u{1B}[2J\u{1B}[H$ ")
        expectSame(terminal, counts: [1, 3, 10, 40, 100], "history behind a cleared screen")
        // The cleared screen's lines are gone (xterm keeps no copy); the history's last is 35.
        #expect(SwiftTermBufferText.lastLines(2, of: terminal) == ["line 35", "$ "])
    }

    @Test("scrolled back: still the buffer's last lines")
    func scrolledBack() {
        let terminal = terminal()
        for i in 1...40 { feed(terminal, "line \(i)\r\n") }
        terminal.buffer.yDisp = 2
        expectSame(terminal, counts: [1, 6, 50], "the view scrolled back to the top")
        #expect(SwiftTermBufferText.lastLines(1, of: terminal) == ["line 40"])
    }

    @Test("history past the scrollback, trimmed from the top")
    func trimmed() {
        let terminal = terminal(scrollback: 10)
        for i in 1...200 { feed(terminal, "row \(i)\r\n") }
        #expect(terminal.buffer.totalLinesTrimmed > 0)
        expectSame(terminal, counts: [1, 5, 15, 50], "after lines were trimmed")
    }

    @Test("the alternate screen: its own lines")
    func alternate() {
        let terminal = terminal()
        for i in 1...30 { feed(terminal, "shell \(i)\r\n") }
        feed(terminal, "\u{1B}[?1049h\u{1B}[Hprogram\r\n\r\nstatus")
        #expect(terminal.isCurrentBufferAlternate)
        expectSame(terminal, counts: [1, 2, 10], "a full-screen program")
        #expect(SwiftTermBufferText.lastLines(10, of: terminal) == ["program", "status"])
    }
}
