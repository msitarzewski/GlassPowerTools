import Testing
import Foundation
@testable import GlassEditor

/// Leaving the editor on a phone is "go back", not "close".
///
/// `GlassEditorWorkspaceView.onDisappear` calls `forget`, which discarded the workspace — right
/// for a window, wrong for a full-screen cover, because a phone dismisses that cover every time
/// the user taps Connections. The documents went with it, unsaved edits included, and nothing
/// said so. These tests are the phone, which the suite's own machine can never be.
@Suite("An editor left on a phone is still there")
@MainActor
struct GlassEditorSessionLifetimeTests {
    private func runtime(phone: Bool) -> GlassEditorRuntime {
        let runtime = GlassEditorRuntime(
            defaults: UserDefaults.forTest(suiteName: "glass-editor-lifetime-\(UUID().uuidString)")!)
        runtime.closesWorkspaceWithItsWindow = !phone
        return runtime
    }

    private func file(_ name: String, _ contents: String = "text\n") throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glass-lifetime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(name)
        try Data(contents.utf8).write(to: file)
        return file
    }

    @Test func leavingTheScreenOnAPhoneKeepsTheDocuments() async throws {
        let runtime = runtime(phone: true)
        let id = UUID()
        let workspace = runtime.workspace(for: id)
        _ = await workspace.open(try file("notes.txt"))
        #expect(workspace.documents.count == 1)

        runtime.noteFrontmost(id)
        runtime.forget(id)

        #expect(runtime.workspace(for: id) === workspace, "the same workspace, not a fresh one")
        #expect(runtime.workspace(for: id).documents.count == 1)
    }

    @Test func anUnsavedEditSurvivesTappingConnections() async throws {
        // The damage the old behaviour actually did, stated as its own test.
        let runtime = runtime(phone: true)
        let id = UUID()
        let workspace = runtime.workspace(for: id)
        let document = try #require(await workspace.open(try file("draft.txt")))
        try document.model.replaceAllContent(with: "something worth losing\n")
        #expect(document.isDirty)

        runtime.forget(id)

        let after = runtime.workspace(for: id)
        #expect(after.documents.contains { $0.id == document.id })
        #expect(after.documents.first?.isDirty == true)
    }

    @Test func closingAWorkspaceOnPurposeStillEndsIt() async throws {
        // Otherwise a phone would accumulate editors with no way to be rid of one — which is
        // the switcher's swipe, and the reason `closeWorkspace` exists beside `forget`.
        let runtime = runtime(phone: true)
        let id = UUID()
        let workspace = runtime.workspace(for: id)
        _ = await workspace.open(try file("gone.txt"))

        runtime.closeWorkspace(id)

        #expect(runtime.workspace(for: id) !== workspace)
        #expect(runtime.workspace(for: id).documents.isEmpty)
    }

    @Test func aMacStillClosesTheEditorWithItsWindow() async throws {
        // The behaviour being preserved, not replaced. A window full of tabs is what a Mac
        // editor is, and closing it closes them.
        let runtime = runtime(phone: false)
        let id = UUID()
        let workspace = runtime.workspace(for: id)
        _ = await workspace.open(try file("closed.txt"))

        runtime.forget(id)

        #expect(runtime.workspace(for: id) !== workspace)
        #expect(runtime.workspace(for: id).documents.isEmpty)
    }

    @Test func aWorkspaceLeftOnAPhoneIsOfferedInTheSwitcher() async throws {
        let runtime = runtime(phone: true)
        let id = UUID()
        let workspace = runtime.workspace(for: id)
        _ = await workspace.open(try file("README.md"))
        runtime.forget(id)

        let sessions = runtime.openSessions()
        #expect(sessions.map(\.id) == [GlassEditorRuntime.sessionID(windowID: id)])
        #expect(sessions.first?.title == "README.md")
        #expect(sessions.first?.subtitle == "1 file")
    }

    @Test func aProjectSurvivesLeavingTheScreenOnAPhone() throws {
        // The other half of the same defect, and the one that actually emptied the switcher:
        // `GlassEditorWorkspaceView.onDisappear` called `closeAllProjects()`, so the workspace
        // was kept and arrived back with nothing in it.
        let runtime = runtime(phone: true)
        let id = UUID()
        let workspace = runtime.workspace(for: id)
        let folder = try file("README.md").deletingLastPathComponent()
        #expect(workspace.openProject(folder) != nil)
        #expect(workspace.projects.count == 1)

        // What the view does on the way out, with the same condition it now applies.
        if runtime.closesWorkspaceWithItsWindow { workspace.closeAllProjects() }
        runtime.forget(id)

        #expect(runtime.workspace(for: id).projects.count == 1,
                "the project left the workspace the user is coming back to")
        #expect(runtime.openSessions().count == 1)
    }

    @Test func closingTheWorkspaceReleasesItsProjects() throws {
        let runtime = runtime(phone: true)
        let id = UUID()
        let workspace = runtime.workspace(for: id)
        let folder = try file("README.md").deletingLastPathComponent()
        #expect(workspace.openProject(folder) != nil)

        runtime.closeWorkspace(id)

        #expect(workspace.projects.isEmpty, "closing on purpose must release the project's reader")
        #expect(runtime.openSessions().isEmpty)
    }

    @Test func anEmptyWorkspaceIsNotASession() {
        // One is made the first time a window *asks* for a workspace, which is a side effect of
        // drawing. Listing those would offer rows for windows that never held anything.
        let runtime = runtime(phone: true)
        _ = runtime.workspace(for: UUID())
        #expect(runtime.openSessions().isEmpty)
    }

    @Test func theRowSaysWhenSomethingWouldBeLost() async throws {
        let runtime = runtime(phone: true)
        let workspace = runtime.workspace(for: UUID())
        let document = try #require(await workspace.open(try file("a.txt")))
        _ = await workspace.open(try file("b.txt"))
        try document.model.replaceAllContent(with: "edited\n")

        #expect(runtime.openSessions().first?.subtitle == "2 files · 1 unsaved")
    }

    @Test func closingFromTheSwitcherEndsIt() async throws {
        let runtime = runtime(phone: true)
        let id = UUID()
        _ = await runtime.workspace(for: id).open(try file("bye.txt"))

        let row = try #require(runtime.openSessions().first)
        row.close()

        #expect(runtime.openSessions().isEmpty)
    }

    // MARK: - Unsaved changes are never dropped silently (2026-10-17)
    //
    // Closing an editor window, quitting, or closing it in Active discarded unsaved changes
    // without a word; only closing a document asked. An iPad's or Vision Pro's window can be
    // dismissed with no chance to ask, so its workspace is kept for the changes.

    @Test func aWindowClosedWithUnsavedChangesKeepsThemInActive() async throws {
        let runtime = runtime(phone: false)
        let id = UUID()
        let workspace = runtime.workspace(for: id)
        let document = try #require(await workspace.open(try file("draft.txt")))
        try document.model.replaceAllContent(with: "not yet saved\n")

        runtime.forget(id)

        #expect(runtime.workspace(for: id) === workspace, "the window's unsaved changes went with it")
        let session = try #require(runtime.openSessions().first)
        #expect(session.subtitle == "1 file · 1 unsaved")
        #expect(session.unsavedChanges?() == "draft.txt has changes that haven't been saved.")
    }

    @Test func whatClosingWouldLoseIsSaid() async throws {
        let runtime = runtime(phone: false)
        let workspace = runtime.workspace(for: UUID())
        let first = try #require(await workspace.open(try file("a.txt")))
        let second = try #require(await workspace.open(try file("b.md")))
        #expect(runtime.openSessions().first?.unsavedChanges?() == nil, "nothing is unsaved yet")
        #expect(runtime.unsavedDocumentNames.isEmpty)

        try first.model.replaceAllContent(with: "one\n")
        try second.model.replaceAllContent(with: "two\n")

        #expect(runtime.openSessions().first?.unsavedChanges?()
                == "2 documents have changes that haven't been saved: a.txt and b.md.")
        #expect(Set(runtime.unsavedDocumentNames) == ["a.txt", "b.md"])
    }
}
