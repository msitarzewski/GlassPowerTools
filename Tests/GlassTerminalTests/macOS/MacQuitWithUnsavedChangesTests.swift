#if os(macOS)
import AppKit
import Testing
@testable import GlassTerminal

/// Quitting asks first when the editor has unsaved changes (2026-10-17: a quit threw them away
/// without a word), and says what the terminals lose in the same question.
@MainActor
@Suite("A quit asks about unsaved changes")
struct MacQuitWithUnsavedChangesTests {
    @Test func noUnsavedDocumentsNoQuestion() {
        #expect(MacTerminalAppDelegate.unsavedChangesQuestion(names: [], terminalMessage: nil) == nil)
    }

    @Test func theQuestionNamesTheDocumentsAndCancelComesFirst() throws {
        let alert = try #require(MacTerminalAppDelegate.unsavedChangesQuestion(
            names: ["a.txt", "b.md"], terminalMessage: "Running terminal sessions will be disconnected."))
        #expect(alert.messageText == "Quit without saving?")
        #expect(alert.informativeText
                == "2 documents have changes that haven't been saved: a.txt and b.md. Running terminal sessions will be disconnected.")
        #expect(alert.buttons.map(\.title) == ["Cancel", "Quit Without Saving"])
        #expect(alert.buttons.last?.hasDestructiveAction == true)
    }

    @Test func oneDocumentIsNamed() throws {
        let alert = try #require(MacTerminalAppDelegate.unsavedChangesQuestion(names: ["notes.txt"], terminalMessage: nil))
        #expect(alert.informativeText == "notes.txt has changes that haven't been saved.")
    }
}
#endif
