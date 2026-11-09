//
//  TerminalScrollCoastTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A flick that coasts stays where it stopped while output arrives (2026-11-08). The owner on the headset: "I can't
//  scroll to the latest lines... it jumps and stutters", in a tab where Codex was working. SwiftTerm's UIKit view
//  takes its row from the scroll position only while a finger or hand is down; through the coast after it lets go,
//  the row stayed where the hand had let go, and the next output put the view back there. With output all the time,
//  every flick that stopped short of the bottom was undone. The Mac's view scrolls another way.
//
//  UIKit's tracking and coasting can't be made in a unit test, so the view reports them as the test says.
//

#if canImport(UIKit)
import Foundation
import SwiftTerm
import Testing
import UIKit

@Suite("A terminal scrolled by a flick")
@MainActor
struct TerminalScrollCoastTests {
    /// SwiftTerm's view, with UIKit's `isTracking` and `isDecelerating` set by the test.
    private final class FlickedTerminalView: TerminalView {
        var handDown = false
        var coasts = false
        override var isTracking: Bool { handDown }
        override var isDecelerating: Bool { coasts }

        /// The furthest down the view scrolls: the last line at the bottom.
        var bottom: CGFloat { max(0, contentSize.height - bounds.height + adjustedContentInset.bottom) }
    }

    private func terminalWithHistory() throws -> (view: FlickedTerminalView, rowHeight: CGFloat) {
        let view = FlickedTerminalView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        view.layoutIfNeeded()
        view.feed(text: (1...300).map { "line \($0)" }.joined(separator: "\r\n") + "\r\n")
        let terminal = view.getTerminal()
        // Following the output, the view shows the last screen: every line is the history above it and the screen.
        let rowHeight = view.contentSize.height / CGFloat(terminal.buffer.yDisp + terminal.rows)
        try #require(rowHeight > 0 && terminal.buffer.yDisp > 100, "the terminal has no history to scroll")
        try #require(abs(view.contentOffset.y - view.bottom) < rowHeight, "the terminal isn't at its last line")
        return (view, rowHeight)
    }

    @Test("a coast that stops short of the bottom keeps its place when output arrives")
    func coastKeepsItsPlace() throws {
        let (view, rowHeight) = try terminalWithHistory()
        let bottom = view.bottom

        // The hand drags 100 rows up and lets go; the coast carries the view 60 rows back down.
        view.handDown = true
        view.contentOffset.y = bottom - 100 * rowHeight
        view.handDown = false
        view.coasts = true
        view.contentOffset.y = bottom - 40 * rowHeight
        view.coasts = false
        let stopped = view.contentOffset.y

        view.feed(text: "more output\r\n")

        let moved = abs(view.contentOffset.y - stopped) / rowHeight
        #expect(moved < 1, "the view moved \(moved) rows from where the coast stopped")
    }

    @Test("a coast while the view follows the output doesn't stop it following")
    func coastWhileFollowingKeepsFollowing() throws {
        let (view, rowHeight) = try terminalWithHistory()

        // Output grows the content under a coast from a flick down to the bottom.
        view.coasts = true
        view.contentOffset.y -= 3 * rowHeight
        view.coasts = false
        view.feed(text: "more output\r\n")

        #expect(abs(view.contentOffset.y - view.bottom) < rowHeight, "the view stopped following the output")
    }

    @Test("a coast that reaches the bottom follows the output again")
    func coastToTheBottomFollows() throws {
        let (view, rowHeight) = try terminalWithHistory()

        view.handDown = true
        view.contentOffset.y = view.bottom - 50 * rowHeight
        view.handDown = false
        view.coasts = true
        view.contentOffset.y = view.bottom
        view.coasts = false
        view.feed(text: "more output\r\n")

        #expect(abs(view.contentOffset.y - view.bottom) < rowHeight, "the view didn't follow the output again")
    }
}
#endif
