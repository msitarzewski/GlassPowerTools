//
//  TerminalBellNoticeTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A bell rung out of sight stays with its terminal until the terminal is seen (the owner, 2026-11-03: "We can detect
//  when a terminal sends a bell, right? Let's add an indicator when that happens"). What must hold: a bell out of sight
//  leaves a notice; one in sight leaves none; coming into sight clears it. And the bell gets
//  there from the terminal itself: SwiftTerm reading a BEL in its output, through the host's delegate, with no window.
//

import Foundation
import Testing
@testable import GlassTerminalEmulator
#if os(macOS)
import AppKit
import SwiftTerm
#endif

@MainActor
@Suite("A bell rung out of sight is kept until its terminal is seen")
struct TerminalBellNoticeTests {
    @Test("out of sight: a notice; seen: gone; rung again while seen: none")
    func outOfSightThenSeen() {
        let notice = TerminalBellNotice()
        notice.ring()
        #expect(notice.isUnseen, "rung with nobody looking")
        notice.isInSight = true
        #expect(!notice.isUnseen, "its tab chosen in a window on screen: seen")
        notice.ring()
        #expect(!notice.isUnseen, "rung while in sight: seen as it rings")
        notice.isInSight = false
        #expect(!notice.isUnseen, "leaving sight doesn't bring one back")
        notice.ring()
        #expect(notice.isUnseen)
    }

    /// The owner, 2026-11-15, on the iPhone: Active "doesn't highlight which terminals need attention". The bell is
    /// kept on the terminal's tmux session too, for every device: seen here, that one is cleared; said by the session,
    /// it is unseen here.
    @Test("kept on the session: seen here, cleared there; rung in sight, cleared at once; the session's word is unseen here; cleared once")
    func keptOnTheSession() {
        let notice = TerminalBellNotice()
        var cleared = 0
        var connected = true
        notice.clearsSession = { guard connected else { return false }; cleared += 1; return true }

        notice.isInSight = true
        #expect(cleared == 0, "nothing rang: nothing to clear")
        notice.isInSight = false
        notice.ring()
        #expect(notice.isUnseen && cleared == 0, "out of sight: kept, everywhere")
        notice.isInSight = true
        #expect(!notice.isUnseen && cleared == 1, "seen here: cleared on the session too")
        notice.isInSight = false
        notice.isInSight = true
        #expect(cleared == 1, "once")

        notice.ring()
        #expect(cleared == 2, "rung while in sight: the hook kept it on its way past; cleared at once")

        notice.isInSight = false
        notice.sessionKeepsOne()
        #expect(notice.isUnseen, "the session says a bell rang that no device showed: unseen here")
        connected = false
        notice.isInSight = true
        #expect(!notice.isUnseen && cleared == 2, "seen, but not connected: the session's can't be cleared now")
        connected = true
        notice.isInSight = false
        notice.isInSight = true
        #expect(cleared == 3, "the next time it is seen, it is")

        notice.sessionKeepsOne()
        #expect(!notice.isUnseen && cleared == 4, "the session's word while in sight: seen, and cleared")
    }

    #if os(macOS)
    /// The whole way in, on the Mac's SwiftTerm view: output with a BEL, read by SwiftTerm, told to the host's
    /// delegate, kept on the model — no window, as a terminal whose window is in the dock has none.
    @Test("a BEL in the terminal's output reaches its model's notice")
    func belFromOutput() {
        let model = SwiftTermHostModel()
        var bells = 0
        let coordinator = SwiftTermHostView.Coordinator(model: model, onSendData: { _ in }, onResize: { _, _ in },
                                                         onTitleChanged: { _ in }, onBell: { bells += 1 })
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        view.terminalDelegate = coordinator
        view.feed(text: "build finished\u{07}")
        #expect(bells == 1, "the host's own bell (sound, flash) still rings")
        #expect(model.bellNotice.isUnseen, "and the notice is kept on the model")

        model.bellNotice.isInSight = true
        #expect(!model.bellNotice.isUnseen)
        view.feed(text: "\u{07}")
        #expect(bells == 2)
        #expect(!model.bellNotice.isUnseen, "rung in sight: no notice")

        // An OSC ended by BEL is not a bell: a shell telling its folder (OSC 7) must not light every tab.
        model.bellNotice.isInSight = false
        view.feed(text: "\u{1B}]7;file:///home/ann/shop\u{07}")
        #expect(bells == 2)
        #expect(!model.bellNotice.isUnseen, "OSC's terminator is not a bell")
    }
    #endif
}
