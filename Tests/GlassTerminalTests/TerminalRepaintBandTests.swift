//
//  TerminalRepaintBandTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A Vision Pro terminal repaints the rows that changed, not the whole terminal (the owner,
//  2026-10-29: the screen refreshed at every typed key). What must hold: the band covers the
//  changed rows and a row each way, in the scroll view's own space, measured from where SwiftTerm
//  draws the screen's first row — the view's top only while the terminal's rows fill the view
//  (2026-11-03: with fewer, the band named rows above the changed ones); a change on the last two rows
//  reaches the foot; rows off the screen give nothing, so the whole terminal is repainted as before.
//

import CoreGraphics
import Testing
import SwiftTerm
@testable import GlassTerminalEmulator

@Suite("A terminal repaints the rows that changed")
struct TerminalRepaintBandTests {
    private let cell: CGFloat = 20
    /// 24 rows, scrolled 1,000 rows down its scrollback.
    private let bounds = CGRect(x: 0, y: 20_000, width: 800, height: 480)

    @Test("One row typed on: that row and one each side, where the scroll view shows it")
    func oneRow() throws {
        let band = try #require(TerminalRepaintBand.rect(rows: (5, 5), screenRows: 24, cellHeight: cell, screenTop: bounds.minY, bounds: bounds))
        #expect(band == CGRect(x: 0, y: 20_000 + 4 * cell, width: 800, height: 3 * cell))
    }

    @Test("The top row: no row above it to take")
    func topRow() throws {
        let band = try #require(TerminalRepaintBand.rect(rows: (0, 1), screenRows: 24, cellHeight: cell, screenTop: bounds.minY, bounds: bounds))
        #expect(band == CGRect(x: 0, y: 20_000, width: 800, height: 3 * cell))
    }

    @Test("A change near the foot reaches the foot, as SwiftTerm's Mac repaint does")
    func footRows() throws {
        let band = try #require(TerminalRepaintBand.rect(rows: (22, 22), screenRows: 24, cellHeight: cell, screenTop: bounds.minY, bounds: bounds))
        #expect(band.minY == 20_000 + 21 * cell)
        #expect(band.maxY == bounds.maxY)
        let whole = try #require(TerminalRepaintBand.rect(rows: (0, 23), screenRows: 24, cellHeight: cell, screenTop: bounds.minY, bounds: bounds))
        #expect(whole == bounds, "every row changed: the whole terminal, which is repainted as before")
    }

    /// The visionOS simulator's numbers (2026-11-03, `--demo-foreign-grid 12`): a view 697 points
    /// high, cells 17, the terminal held at tmux's 12 rows. SwiftTerm kept its last line at the
    /// view's foot, its first shown line 9 (`yDisp`), the scroll view's top at 0: the screen's first
    /// row is drawn at 153, not at the view's top. A row typed on mid-screen is repainted where it is.
    @Test("The terminal has fewer rows than the view: the band is where SwiftTerm draws the rows")
    func screenLowerThanTheView() throws {
        let view = CGRect(x: 0, y: 0, width: 1108, height: 697)
        let cell: CGFloat = 17
        let screenTop = 9 * cell
        let band = try #require(TerminalRepaintBand.rect(rows: (5, 5), screenRows: 12, cellHeight: cell,
                                                         screenTop: screenTop, bounds: view))
        let typedRow = CGRect(x: 0, y: screenTop + 5 * cell, width: 1108, height: cell)
        #expect(band.contains(typedRow), "the row typed on, drawn at \(typedRow.minY), is inside the band \(band)")
        #expect(band == CGRect(x: 0, y: screenTop + 4 * cell, width: 1108, height: 3 * cell))
    }

    @Test("A band reaching past the view is cut to it; one wholly out of sight gives nothing")
    func outOfSight() throws {
        let view = CGRect(x: 0, y: 0, width: 800, height: 200)
        // The terminal taller than the view: rows past its foot are not seen.
        let cut = try #require(TerminalRepaintBand.rect(rows: (8, 9), screenRows: 30, cellHeight: 20, screenTop: 0, bounds: view))
        #expect(cut == CGRect(x: 0, y: 140, width: 800, height: 60))
        #expect(TerminalRepaintBand.rect(rows: (20, 20), screenRows: 30, cellHeight: 20, screenTop: 0, bounds: view) == nil)
    }

    @Test("Rows not on the screen, or no rows, give nothing: the whole terminal is repainted")
    func outside() {
        #expect(TerminalRepaintBand.rect(rows: (0, 24), screenRows: 24, cellHeight: cell, screenTop: bounds.minY, bounds: bounds) == nil)
        #expect(TerminalRepaintBand.rect(rows: (-1, 2), screenRows: 24, cellHeight: cell, screenTop: bounds.minY, bounds: bounds) == nil)
        #expect(TerminalRepaintBand.rect(rows: (6, 5), screenRows: 24, cellHeight: cell, screenTop: bounds.minY, bounds: bounds) == nil)
        #expect(TerminalRepaintBand.rect(rows: (1, 1), screenRows: 0, cellHeight: cell, screenTop: bounds.minY, bounds: bounds) == nil)
        #expect(TerminalRepaintBand.rect(rows: (1, 1), screenRows: 24, cellHeight: 0, screenTop: bounds.minY, bounds: bounds) == nil)
    }
}

/// Of the rows SwiftTerm names, the ones that really changed (the owner, 2026-10-29: "Every letter
/// affects the screen"). SwiftTerm names every row when a synchronized update ends, and Claude Code
/// sends each frame as one: the headset counted each typed key a whole repaint, "every line".
@Suite("A terminal repaints only the rows whose look changed")
struct TerminalRowFingerprintsTests {
    @Test("nothing drawn yet: every row named; drawn and unchanged: none; one changed: that one")
    func rows() {
        var screen = ["$ ls", "a b c", "$ "]
        var prints = TerminalRowFingerprints()
        let look: (Int) -> Int = { screen[$0].hashValue }
        #expect(prints.changed(in: 0...2, fingerprint: look) == 0...2)
        #expect(prints.changed(in: 0...2, fingerprint: look) == nil, "the same again repaints nothing")
        screen[2] = "$ g"
        #expect(prints.changed(in: 0...2, fingerprint: look) == 2...2)
        screen[0] = "$ ls -l"
        screen[2] = "$ gi"
        #expect(prints.changed(in: 0...2, fingerprint: look) == 0...2, "the range holding both")
        prints.forget()
        #expect(prints.changed(in: 1...1, fingerprint: look) == 1...1, "forgotten: as if nothing were drawn")
    }

    /// The headset's case, in SwiftTerm itself: a frame wrapped in a synchronized update, as Claude
    /// Code sends one per key, rewriting the screen with one letter more.
    @MainActor
    @Test("a synchronized frame that adds one letter: SwiftTerm names every row, one row changed")
    func synchronizedFrame() throws {
        let terminal = Terminal(delegate: SilentTerminal(), options: TerminalOptions(cols: 40, rows: 8))
        func frame(_ input: String) -> String {
            "\u{1B}[?2026h\u{1B}[H\u{1B}[2J" + "Claude Code\r\n\r\n> \(input)\r\n\r\n? for shortcuts" + "\u{1B}[?2026l"
        }
        terminal.feed(text: frame("hel"))
        terminal.clearUpdateRange()
        var prints = TerminalRowFingerprints()
        let look: (Int) -> Int = { TerminalRowFingerprint.of(terminal.getLine(row: $0), columns: terminal.cols) }
        prints.record(0...7, fingerprint: look)

        terminal.feed(text: frame("hell"))
        let named = try #require(terminal.getUpdateRange())
        #expect(named.startY == 0 && named.endY == 7, "SwiftTerm names every row")
        #expect(prints.changed(in: named.startY...named.endY, fingerprint: look) == 2...2, "the prompt's row alone")

        terminal.clearUpdateRange()
        terminal.feed(text: frame("hell"))
        #expect(prints.changed(in: 0...7, fingerprint: look) == nil, "the same frame again: nothing to repaint")
    }

    @MainActor
    @Test("a row's colour is in its fingerprint, not only its letters")
    func colour() {
        let terminal = Terminal(delegate: SilentTerminal(), options: TerminalOptions(cols: 20, rows: 3))
        terminal.feed(text: "ready")
        let plain = TerminalRowFingerprint.of(terminal.getLine(row: 0), columns: terminal.cols)
        terminal.feed(text: "\r\u{1B}[31mready\u{1B}[0m")
        #expect(TerminalRowFingerprint.of(terminal.getLine(row: 0), columns: terminal.cols) != plain)
    }
}

private final class SilentTerminal: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

