#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GlassTerminal
@testable import GlassTerminalEmulator

/// Type-ahead in a terminal drawn by the engine every SSH terminal uses (iPhone, iPad and Vision Pro's, and a Mac's
/// SSH pane's): the host's output read with the shell's marks, kept, and offered back (D102). Wired only into the
/// Mac's own shell at first, so no SSH terminal ever offered anything; found in the Vision Pro simulator's demo,
/// 2026-11-06. A connectionless terminal fed as the host would feed it.
@MainActor
@Suite("Type-ahead in an SSH terminal")
struct TypeAheadSSHTerminalTests {
    private func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test("the host's marked prompts: each command run is kept, and a start typed again offers them back")
    func offered() async throws {
        let model = SwiftTermHostModel()
        let hosting = NSHostingView(rootView: SwiftTermHostView(
            model: model,
            theme: SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 1), cursor: (1, 1, 1)),
            runtimeSettings: SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 100),
            allowsFocusOwnership: false,
            onSendData: { _ in },
            onResize: { _, _ in }))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 700, height: 300))
        hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 300)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()

        // As the terminal's window does when it appears, before the host has said anything.
        let history = TerminalCommandHistory(folder: nil)
        let defaults = try #require(UserDefaults(suiteName: "typeahead-ssh-\(UUID().uuidString)"))
        let controller = TerminalTypeAheadController.attach(to: model, machine: "alpha", folder: { nil }, snippets: { [] },
                                                            history: history, defaults: defaults)
        controller.offerForCurrentLine()

        func ran(_ command: String, _ output: String) -> String {
            "\u{1B}]133;A\u{07}~/shop $ \u{1B}]133;B\u{07}\(command)\r\n\u{1B}]633;E;\(command)\u{07}"
                + "\u{1B}]133;C\u{07}\(output)\r\n\u{1B}]133;D;0\u{07}"
        }
        let transcript = ran("git status", "On branch main") + ran("git stash list", "stash@{0}: WIP on main")
            + "\u{1B}]133;A\u{07}~/shop $ \u{1B}]133;B\u{07}git st"
        model.ingest(data: Data(transcript.utf8), nonce: 1)

        #expect(await waitFor(seconds: 5) { history.records(for: "alpha").count == 2 },
                "kept: \(history.records(for: "alpha").map(\.command))")
        #expect(await waitFor(seconds: 5) { model.typeAheadChoices.contains("git status") && model.typeAheadChoices.contains("git stash list") },
                "offered: \(model.typeAheadChoices); line: \(String(describing: model.typeAheadLine))")
        #expect(model.typeAheadSuggestion?.command.hasPrefix("git st") == true)
    }
}
#endif
