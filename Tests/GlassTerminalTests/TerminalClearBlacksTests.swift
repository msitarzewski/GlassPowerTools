//
//  TerminalClearBlacksTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  Black backgrounds show the glass (the owner, 2026-10-13: "btop's black is black and not
//  transparent … the other colors are fine at 100%"). What must hold: every way a program paints a
//  black background — btop's truecolor, the palette's black, the 256-colour cube's — reaches SwiftTerm
//  as the default background; no other colour does, and no foreground; nothing but SGR is touched;
//  a sequence split across two reads is still found; and under a light theme black stays black.
//

import Foundation
import Testing
import SwiftTerm
@testable import GlassTerminalEmulator

@Suite("Black backgrounds show the glass")
struct TerminalClearBlacksTests {
    /// A dark theme whose own background is not black, so the two rules can be told apart.
    private func darkTheme() -> TerminalClearBlacks {
        var filter = TerminalClearBlacks()
        filter.configure(ansi: [], background: (30 / 255, 30 / 255, 46 / 255))
        return filter
    }

    private func run(_ text: String, through filter: inout TerminalClearBlacks) -> String {
        String(decoding: Array(filter.filter(ArraySlice(Array(text.utf8)))), as: UTF8.self)
    }

    @Test("btop's black, the palette's and the cube's become the default background")
    func blacksClear() {
        var filter = darkTheme()
        #expect(run("\u{1b}[48;2;0;0;0m ", through: &filter) == "\u{1b}[49m ")
        #expect(run("\u{1b}[40mx", through: &filter) == "\u{1b}[49mx")
        #expect(run("\u{1b}[48;5;0m", through: &filter) == "\u{1b}[49m")
        #expect(run("\u{1b}[48;5;16m", through: &filter) == "\u{1b}[49m")
        #expect(run("\u{1b}[48:2::0:0:0m", through: &filter) == "\u{1b}[49m")
        #expect(run("\u{1b}[48:5:16m", through: &filter) == "\u{1b}[49m")
        // In the middle of everything else btop sets at once; the foreground stays black.
        #expect(run("\u{1b}[0;1;38;2;0;0;0;48;2;0;0;0m", through: &filter) == "\u{1b}[0;1;38;2;0;0;0;49m")
        // The theme's own background colour shows the glass too.
        #expect(run("\u{1b}[48;2;30;30;46m", through: &filter) == "\u{1b}[49m")
    }

    @Test("every other colour, every foreground and every other sequence goes through unchanged")
    func othersStay() {
        var filter = darkTheme()
        for text in [
            "\u{1b}[48;2;1;0;0m", "\u{1b}[41m", "\u{1b}[100m", "\u{1b}[48;5;232m", "\u{1b}[48;5;17m",
            "\u{1b}[30m", "\u{1b}[38;2;0;0;0m", "\u{1b}[38;5;0m",
            "\u{1b}[38;5;40m",          // a foreground from the cube, not background 40
            "\u{1b}[58;5;40m",          // an underline colour, likewise
            "\u{1b}[4:3m",              // a curly underline
            "\u{1b}[>4;2m",             // a private sequence that also ends in m
            "\u{1b}[40H",               // not SGR at all
            "\u{1b}]0;40m title\u{07}", // an OSC
            "plain text, no escapes",
        ] {
            #expect(run(text, through: &filter) == text, "\(text.debugDescription) was changed")
        }
    }

    @Test("a sequence cut between two reads is still found, and nothing is lost or repeated")
    func splitAcrossReads() {
        var filter = darkTheme()
        let first = run("ab\u{1b}[48;2;0", through: &filter)
        let second = run(";0;0mcd", through: &filter)
        #expect(first + second == "ab\u{1b}[49mcd")
        #expect(run("\u{1b}", through: &filter) == "")
        #expect(run("[40mz", through: &filter) == "\u{1b}[49mz")
        // A sequence far too long to be SGR is passed on rather than held.
        let long = "\u{1b}[" + String(repeating: "1;", count: 200)
        #expect(run(long, through: &filter) == long)
    }

    @Test("under a light theme black stays black; the theme's own background clears")
    func lightTheme() {
        var filter = TerminalClearBlacks()
        filter.configure(ansi: [], background: (1, 1, 1))
        #expect(run("\u{1b}[48;2;0;0;0m", through: &filter) == "\u{1b}[48;2;0;0;0m")
        #expect(run("\u{1b}[40m", through: &filter) == "\u{1b}[40m")
        #expect(run("\u{1b}[48;2;255;255;255m", through: &filter) == "\u{1b}[49m")
    }

    @Test("a theme whose palette black is not black keeps that colour solid")
    func paletteFollowsTheTheme() {
        var filter = TerminalClearBlacks()
        var ansi = TerminalClearBlacks.xtermPalette.map { (Double($0.red) / 255, Double($0.green) / 255, Double($0.blue) / 255) }
        ansi[0] = (7 / 255, 54 / 255, 66 / 255)   // Solarized's base02
        filter.configure(ansi: ansi, background: (0, 43 / 255, 54 / 255))
        #expect(run("\u{1b}[40m", through: &filter) == "\u{1b}[40m")
        #expect(run("\u{1b}[48;2;0;0;0m", through: &filter) == "\u{1b}[49m")
    }

    /// The whole way: what SwiftTerm stores for a cell btop painted black.
    @Test("SwiftTerm stores btop's black cell with the default background")
    func swiftTermCell() {
        final class Sink: TerminalDelegate {
            lazy var terminal = Terminal(delegate: self, options: TerminalOptions(cols: 20, rows: 2))
            func send(source: Terminal, data: ArraySlice<UInt8>) {}
        }
        var filter = darkTheme()
        let btop = Array("\u{1b}[38;2;200;200;200;48;2;0;0;0mC\u{1b}[48;2;80;0;0mR".utf8)
        let sink = Sink()
        sink.terminal.feed(buffer: filter.filter(ArraySlice(btop)))
        #expect(sink.terminal.getCharData(col: 0, row: 0)?.attribute.bg == .defaultColor)
        #expect(sink.terminal.getCharData(col: 1, row: 0)?.attribute.bg == .trueColor(red: 80, green: 0, blue: 0))

        let unfiltered = Sink()
        unfiltered.terminal.feed(buffer: ArraySlice(btop))
        #expect(unfiltered.terminal.getCharData(col: 0, row: 0)?.attribute.bg != .defaultColor,
                "the cell was clear without the filter, so this test proves nothing")
    }
}
