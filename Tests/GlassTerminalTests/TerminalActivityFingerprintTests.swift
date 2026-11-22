import Foundation
import Testing
import SwiftTerm
@testable import GlassTerminalEmulator

/// Whether output did anything (2026-11-22, the owner: "the Antigravity icon continues to pulse though the terminal
/// session seems idle"). An idle Antigravity CLI blinks its cursor by drawing the cell under it reversed and back about
/// twice a second; a tab's mark pulsed for any output. Now only changed or scrolled text counts. A headless SwiftTerm
/// terminal, fed as such a program would.
@MainActor
@Suite("A terminal works when its text changes, not when its cursor blinks")
struct TerminalActivityFingerprintTests {
    nonisolated final class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    private let delegate = Delegate()

    private func terminal(rows: Int = 6) -> Terminal {
        Terminal(delegate: delegate, options: TerminalOptions(cols: 30, rows: rows, scrollback: 100))
    }

    private func feed(_ terminal: Terminal, _ text: String) {
        terminal.feed(byteArray: Array(text.utf8))
    }

    private func print(_ terminal: Terminal) -> Int { SwiftTermBufferText.activityFingerprint(of: terminal) }

    @Test("a cursor drawn reversed and back, hidden and shown, or moved, is the same screen")
    func blinkingIsTheSameScreen() {
        let terminal = terminal()
        // An input box at rest, as a Bubble Tea program draws it: a prompt, and its cursor as a reversed cell.
        feed(terminal, "\u{1B}[2J\u{1B}[H> ask anything\u{1B}[3;3H\u{1B}[7m \u{1B}[m")
        let atRest = print(terminal)
        // The blink: the same cell redrawn plain, then reversed again; the real cursor hidden and shown, and moved.
        feed(terminal, "\u{1B}[3;3H \u{1B}[?25l")
        #expect(print(terminal) == atRest, "drawn plain")
        feed(terminal, "\u{1B}[3;3H\u{1B}[7m \u{1B}[m\u{1B}[?25h\u{1B}[1;1H")
        #expect(print(terminal) == atRest, "and reversed again, the cursor elsewhere")
        // A colour change alone: the same characters.
        feed(terminal, "\u{1B}[1;1H\u{1B}[32m> ask anything\u{1B}[m")
        #expect(print(terminal) == atRest, "coloured differently")
    }

    @Test("new text, a spinner's next frame, text scrolled, or the other screen is work")
    func changedTextIsWork() {
        let terminal = terminal()
        feed(terminal, "> ")
        let before = print(terminal)
        feed(terminal, "h")
        #expect(print(terminal) != before, "a character typed or printed")

        feed(terminal, "\u{1B}[2;1H⠋ Working")
        let frame = print(terminal)
        feed(terminal, "\u{1B}[2;1H⠙ Working")
        #expect(print(terminal) != frame, "a spinner's next frame")

        // A screen of one line again and again: the same text on screen, but it scrolled.
        let same = Terminal(delegate: delegate, options: TerminalOptions(cols: 30, rows: 3, scrollback: 100))
        feed(same, "y\r\ny\r\ny")
        let full = print(same)
        feed(same, "\r\ny")
        #expect(print(same) != full, "the same lines, scrolled up")

        let screen = print(terminal)
        feed(terminal, "\u{1B}[?1049h")
        #expect(print(terminal) != screen, "into the alternate screen")
    }

    @Test("the gate: a screen like the last isn't work; a different one is; none to look at counts, as before")
    func gate() {
        var gate = SwiftTermActivityGate()
        let answers = [gate.changed(7), gate.changed(7), gate.changed(8), gate.changed(nil), gate.changed(8)]
        #expect(answers == [true, false, true, true, false],
                "first seen; the same; different; no screen yet, counted; and the last screen still stands")
    }
}
