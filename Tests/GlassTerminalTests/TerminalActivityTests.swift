//
//  TerminalActivityTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  When a terminal last had input or output, for the library's time in use (2026-10-20).
//

#if os(macOS)
import AppKit
import Foundation
import SwiftTerm
import Testing
import GlassTerminalEmulator

@Suite("A terminal's activity")
@MainActor
struct TerminalActivityTests {
    private func terminalView(in view: NSView?) -> TerminalView? {
        guard let view else { return nil }
        if let terminal = view as? TerminalView { return terminal }
        for child in view.subviews { if let found = terminalView(in: child) { return found } }
        return nil
    }

    @Test("output and typing each mark the terminal active; nothing does before either")
    func outputAndInput() async throws {
        let hosted = await TerminalFindTests.HostedTerminal()
        defer { hosted.close() }
        #expect(hosted.model.lastActivityAt == nil)
        let before = Date()
        await hosted.feed("hello\r\n")
        // Looked at a moment after it arrives, once it is drawn (2026-11-22).
        let output = try #require(await activity(of: hosted, after: nil), "output didn't mark it")
        #expect(output >= before)

        try await Task.sleep(for: .milliseconds(10))
        let view = try #require(terminalView(in: hosted.hosting))
        view.send(txt: "x")
        let input = try #require(hosted.model.lastActivityAt)
        #expect(input > output, "typing didn't mark it")
    }

    /// The model's activity once it moves past `after`, waiting up to two seconds; nil if it doesn't.
    private func activity(of hosted: TerminalFindTests.HostedTerminal, after: Date?) async -> Date? {
        for _ in 0..<200 {
            if let at = hosted.model.lastActivityAt, after.map({ at > $0 }) ?? true { return at }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    /// The owner, 2026-11-22: "the Antigravity icon continues to pulse though the terminal session seems idle". An idle
    /// Antigravity CLI redraws its cursor cell reversed and back about twice a second.
    @Test("a live terminal: a cursor redrawn blinking is not work, and the mark stops; new text is, and it pulses")
    func blinkingIsNotWork() async throws {
        let hosted = await TerminalFindTests.HostedTerminal()
        defer { hosted.close() }
        await hosted.feed("\u{1B}[2J\u{1B}[H> ask anything\u{1B}[3;3H\u{1B}[7m \u{1B}[m")
        let drawn = try #require(await activity(of: hosted, after: nil), "the prompt drawn is output")

        for reversed in [false, true, false, true] {
            await hosted.feed(reversed ? "\u{1B}[3;3H\u{1B}[7m \u{1B}[m" : "\u{1B}[3;3H \u{1B}[m")
            try await Task.sleep(for: .milliseconds(300))
        }
        #expect(hosted.model.lastActivityAt == drawn, "four blinks, more than a second of them: no work")
        for _ in 0..<200 where hosted.model.outputActivity.isActive { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!hosted.model.outputActivity.isActive, "so the mark stops pulsing")

        await hosted.feed("\u{1B}[4;1HThinking…")
        #expect(await activity(of: hosted, after: drawn) != nil, "a line printed is work")
        #expect(hosted.model.outputActivity.isActive)
    }
}
#endif
