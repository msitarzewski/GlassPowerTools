//
//  TerminalDropTypingTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A file dropped on a terminal has its path typed, and says so when it can't be (the owner,
//  2026-10-16: a screenshot dragged into a terminal "just disappears" — the file had arrived, and
//  nothing was typed). A paste still waiting for review — never answered, as no sheet can be while
//  a drop lands — gives way to the newer one instead of turning it away.
//

#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import GlassTerminalEmulator

@Suite("A dropped file's path is typed", .serialized)
@MainActor
struct TerminalDropTypingTests {
    /// A terminal in a window, keeping what it sends.
    @MainActor
    final class Hosted {
        let model = SwiftTermHostModel()
        private let window = NSWindow()
        private(set) var sent = Data()

        init() async {
            let hosting = NSHostingView(rootView: SwiftTermHostView(
                model: model,
                theme: SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 1), cursor: (1, 1, 1)),
                runtimeSettings: SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 100),
                allowsFocusOwnership: false,
                onSendData: { [weak self] data in self?.sent.append(data) },
                onResize: { _, _ in }
            ))
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 600, height: 300))
            hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            for _ in 0..<20 { await Task.yield() }
        }

        var sentText: String { String(decoding: sent, as: UTF8.self) }
    }

    @Test("a dropped path is typed, and says it was")
    func typed() async {
        let host = await Hosted()
        #expect(host.model.insertDroppedText("/tmp/Screenshot\\ 1.png ") == .typed)
        #expect(host.sentText.contains("/tmp/Screenshot\\ 1.png "), "\(host.sentText)")
    }

    @Test("a review left waiting gives way to a newer drop, which is typed")
    func reviewLeftWaiting() async {
        let host = await Hosted()
        #expect(host.model.insertDroppedText("one\ntwo\n") == .awaitingReview)
        #expect(host.model.pendingPasteReview != nil)

        #expect(host.model.insertDroppedText("/tmp/shot.png ") == .typed, "a newer drop is turned away by an old review")
        #expect(host.sentText.contains("/tmp/shot.png "), "\(host.sentText)")
        #expect(host.model.pendingPasteReview == nil, "the review that never showed is gone")
        #expect(!host.sentText.contains("two"), "and what it held was never typed")
    }

    @Test("with no terminal to type into, a drop says so")
    func noTerminal() {
        #expect(SwiftTermHostModel().insertDroppedText("/tmp/a ") == .noTerminal)
    }
}
#endif
