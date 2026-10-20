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
        let output = try #require(hosted.model.lastActivityAt, "output didn't mark it")
        #expect(output >= before)

        try await Task.sleep(for: .milliseconds(10))
        let view = try #require(terminalView(in: hosted.hosting))
        view.send(txt: "x")
        let input = try #require(hosted.model.lastActivityAt)
        #expect(input > output, "typing didn't mark it")
    }
}
#endif
