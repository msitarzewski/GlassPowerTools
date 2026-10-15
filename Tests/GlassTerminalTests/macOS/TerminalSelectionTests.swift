#if os(macOS)
import AppKit
import Foundation
import Testing
import SwiftUI
import SwiftTerm
import GlassTerminalEmulator

/// A selection lasts while output arrives (owner, 2026-10-09: "I can't select text in
/// terminals... it seems to be deselected with a refresh of screen"). SwiftTerm lets go of the
/// selection at every chunk of output while mouse reporting is allowed; it is put back where its
/// text still is. Through the real remote terminal view, fed as a connection feeds it.
@MainActor
@Suite("A terminal's selection lasts through output")
struct TerminalSelectionTests {
    private typealias HostedTerminal = TerminalFindTests.HostedTerminal

    private func terminalView(_ host: HostedTerminal) throws -> TerminalView {
        var views: [NSView] = host.hosting.map { [$0] } ?? []
        while !views.isEmpty {
            let view = views.removeFirst()
            if let terminal = view as? TerminalView { return terminal }
            views += view.subviews
        }
        throw CancellationError()
    }

    /// Selects the word at `column` of the screen's `row`, as a double-click does.
    private func selectWord(_ view: TerminalView, row: Int, column: Int) {
        let buffer = view.getTerminal().buffer
        view.selection.selectWordOrExpression(at: Position(col: column, row: row + buffer.yDisp), in: buffer)
    }

    @Test("output elsewhere, a spinner's frames included, leaves the selection alone")
    func outputElsewhere() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("hello world\r\n")
        let view = try terminalView(host)
        selectWord(view, row: 0, column: 1)
        try #require(view.selection.active && view.selection.getSelectedText() == "hello")

        await host.feed("more output\r\n")
        #expect(view.selection.active && view.selection.getSelectedText() == "hello", "a new line below")
        await host.feed("\u{1B}[?2026h\r\u{1B}[2K⠋ Working\u{1B}[?2026l")
        await host.feed("\u{1B}[?2026h\r\u{1B}[2K⠙ Working\u{1B}[?2026l")
        #expect(view.selection.active && view.selection.getSelectedText() == "hello", "a spinner on another line")
    }

    @Test("output that rewrites the selected text takes the selection with it")
    func rewrittenText() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("hello world\r\n")
        let view = try terminalView(host)
        selectWord(view, row: 0, column: 1)
        try #require(view.selection.active)

        await host.feed("\u{1B}[1;1HHOWDY")
        #expect(!view.selection.active, "what was selected is gone")
    }

    /// A Vision Pro terminal turns mouse reporting off while it has a selection (2026-10-15), so
    /// SwiftTerm leaves the selection in place through output instead of dropping it: it is checked
    /// all the same.
    @Test("with mouse reporting off, output that rewrites the selected text still takes the selection")
    func rewrittenTextWithoutMouseReporting() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("hello world\r\n")
        let view = try terminalView(host)
        view.allowMouseReporting = false
        selectWord(view, row: 0, column: 1)
        try #require(view.selection.active)

        await host.feed("more output\r\n")
        #expect(view.selection.active && view.selection.getSelectedText() == "hello", "a new line below")
        await host.feed("\u{1B}[1;1HHOWDY")
        #expect(!view.selection.active, "what was selected is gone")
    }

    @Test("lines trimmed from the scrollback move the selection with its text, and take it when it goes")
    func trimmedScrollback() async throws {
        let host = await HostedTerminal(scrollback: 20, height: 300)
        defer { host.close() }
        await host.feed("needle here\r\n")
        let view = try terminalView(host)
        selectWord(view, row: 0, column: 1)
        try #require(view.selection.getSelectedText() == "needle")

        await host.feed((1...10).map { "filler \($0)\r\n" }.joined())
        #expect(view.selection.active && view.selection.getSelectedText() == "needle")
        await host.feed((11...200).map { "filler \($0)\r\n" }.joined())
        #expect(!view.selection.active, "trimmed away: no selection left pointing at other text")
    }
}
#endif
