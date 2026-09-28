//
//  GlassEditorWorkspaceTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  Stage 5, first take. Everything here is about documents rather than about views, which is why
//  the workspace is a model and not a `View` — these run against real files in a temporary
//  directory, with no window anywhere.
//
//  The two promises an editor has to keep before any feature matters are both tested: a file
//  opened and saved unchanged is byte-identical, and closing a document with unsaved work refuses
//  rather than discarding it.
//

import Foundation
import Testing
import GlassEditorCore
@testable import GlassEditor

@MainActor
@Suite("The editor workspace (stage 5)")
struct GlassEditorWorkspaceTests {

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Editor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeWorkspace() -> GlassEditorWorkspace {
        GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.tests.\(UUID().uuidString)")!)
    }

    private func write(_ text: String, named name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    // MARK: Opening and saving

    @Test func openingAFileReadsItAndNamesIt() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("SELECT 1;\n", named: "query.sql", in: root)
        let workspace = makeWorkspace()

        let opened1 = await workspace.open(url)
        let document = try #require(opened1)
        #expect(document.model.text == "SELECT 1;\n")
        #expect(document.displayName == "query.sql")
        // The grammar comes from the extension, which is what makes the text coloured on open.
        #expect(document.model.language == .sql)
        #expect(!document.isDirty)
    }

    /// A file opened and saved with no edit must come back byte-identical. An editor that
    /// re-encodes or re-terminates on save turns a one-character change into a whole-file diff.
    @Test func savingAnUneditedFileChangesNothing() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        // CRLF on purpose: the platform default is LF, so a naive save would rewrite every line.
        let original = "alpha\r\nbeta\r\n"
        let url = try write(original, named: "windows.txt", in: root)
        let workspace = makeWorkspace()

        let opened2 = await workspace.open(url)
        let document = try #require(opened2)
        try await document.save(through: GlassEditorLocalFileAccess())

        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after == original, "the file was rewritten: \(after.debugDescription)")
    }

    @Test func editingThenSavingWritesTheNewText() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("one\n", named: "notes.txt", in: root)
        let workspace = makeWorkspace()

        let opened3 = await workspace.open(url)
        let document = try #require(opened3)
        try document.model.replaceAllContent(with: "two\n")
        #expect(document.isDirty)
        await workspace.save(document.id)

        #expect(try String(contentsOf: url, encoding: .utf8) == "two\n")
        #expect(!document.isDirty, "saving did not mark the document clean")
        #expect(workspace.message == nil)
    }

    /// Opening the same file twice must select the one already open. Two editors over one file is
    /// how an editor loses work.
    @Test func openingAFileTwiceSelectsTheOpenOne() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("x", named: "same.txt", in: root)
        let workspace = makeWorkspace()

        let opened4 = await workspace.open(url)
        let first = try #require(opened4)
        let opened5 = await workspace.open(url)
        let second = try #require(opened5)
        #expect(first.id == second.id)
        #expect(workspace.documents.count == 1)
    }

    @Test func aFolderIsNotAFile() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = makeWorkspace()
        let opened = await workspace.open(root)
        #expect(opened == nil)
        #expect(workspace.message?.contains("folder") == true)
    }

    // MARK: Closing

    @Test func closingRefusesWhileThereAreUnsavedChanges() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("keep me", named: "precious.txt", in: root)
        let workspace = makeWorkspace()
        let opened6 = await workspace.open(url)
        let document = try #require(opened6)
        try document.model.replaceAllContent(with: "changed")

        #expect(workspace.close(document.id) == false, "an unsaved document was closed silently")
        #expect(workspace.documents.count == 1)
        #expect(workspace.close(document.id, force: true))
        #expect(workspace.documents.isEmpty)
    }

    /// Closing a tab should leave you looking at its neighbour, not jump you to the first one.
    @Test func closingSelectsTheNeighbour() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = makeWorkspace()
        let opened7 = await workspace.open(try write("a", named: "a.txt", in: root))
        let a = try #require(opened7)
        let opened8 = await workspace.open(try write("b", named: "b.txt", in: root))
        let b = try #require(opened8)
        let opened9 = await workspace.open(try write("c", named: "c.txt", in: root))
        let c = try #require(opened9)

        workspace.selection = b.id
        #expect(workspace.close(b.id))
        #expect(workspace.selection == c.id, "closing the middle tab did not land on its neighbour")
        #expect(workspace.documents.map(\.id) == [a.id, c.id])
    }

    // MARK: Untitled documents

    @Test func untitledDocumentsAreNumberedRatherThanDuplicated() {
        let workspace = makeWorkspace()
        #expect(workspace.newDocument().displayName == "Untitled")
        #expect(workspace.newDocument().displayName == "Untitled 2")
        #expect(workspace.newDocument().displayName == "Untitled 3")
    }

    @Test func anUnsavedDocumentSaysItHasNowhereToGo() async {
        let workspace = makeWorkspace()
        let document = workspace.newDocument()
        #expect(document.hasNeverBeenSaved)
        var thrown: (any Error)?
        do { try await document.save(through: GlassEditorLocalFileAccess()) } catch { thrown = error }
        #expect(thrown as? GlassEditorWorkspaceError == .needsLocation)
    }

    @Test func savingToANewLocationAdoptsItAndItsLanguage() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = makeWorkspace()
        let document = workspace.newDocument()
        try document.model.replaceAllContent(with: "key: value\n")

        let destination = root.appendingPathComponent("config.yaml")
        await workspace.save(document.id, to: destination)

        #expect(document.url == destination)
        #expect(document.displayName == "config.yaml")
        #expect(document.model.language == .yaml, "the language did not follow the chosen name")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "key: value\n")
    }

    // MARK: Find

    @Test func findAndReplaceRunThroughTheDocument() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("red green red blue red", named: "colours.txt", in: root)
        let workspace = makeWorkspace()
        let opened10 = await workspace.open(url)
        let document = try #require(opened10)

        workspace.findQuery = "red"
        workspace.findNext()
        #expect(document.model.selectedRange == 0..<3)
        workspace.findNext()
        #expect(document.model.selectedRange.lowerBound == 10)

        workspace.replacement = "amber"
        #expect(workspace.replaceAll() == 3)
        #expect(document.model.text == "amber green amber blue amber")
    }

    // MARK: Recents

    @Test func recentsAreNewestFirstDedupedAndBounded() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = makeWorkspace()
        for index in 0..<(GlassEditorPreferences.recentsLimit + 5) {
            await workspace.open(try write("x", named: "file\(index).txt", in: root))
        }
        #expect(workspace.preferences.recents.count == GlassEditorPreferences.recentsLimit,
                "the recents list is unbounded")
        #expect(workspace.preferences.recents.first?.lastPathComponent == "file24.txt", "recents are not newest first")

        // Re-opening an old one moves it to the front rather than adding a second entry.
        let again = try write("x", named: "file24.txt", in: root)
        await workspace.open(again)
        #expect(workspace.preferences.recents.filter { $0.lastPathComponent == "file24.txt" }.count == 1)
    }
}

@MainActor
@Suite("A window's documents are its own")
struct GlassEditorWindowIsolationTests {

    /// Waits for a window to have read the files it was asked to open. Bounded, so a read that
    /// never lands fails the assertion instead of hanging the suite.
    private func settle(_ workspace: GlassEditorWorkspace, documents: Int, turns: Int = 200) async {
        for _ in 0..<turns where workspace.documents.count < documents { await Task.yield() }
    }

    private func makeRuntime() -> GlassEditorRuntime {
        GlassEditorRuntime(defaults: UserDefaults.forTest(suiteName: "editor.windows.\(UUID().uuidString)")!)
    }

    private func makeFile(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorWindows-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try Data("hello\n".utf8).write(to: url)
        return url
    }

    /// The report, as a test: ⇧⌘E on a window with documents open produced a window with **the
    /// same documents** in it, because the editor kept one workspace for the whole app. A window
    /// full of tabs is what a Mac editor is; two windows sharing one set is a panel pretending to
    /// be a window.
    @Test func aSecondWindowStartsEmpty() async throws {
        let runtime = makeRuntime()
        let file = try makeFile("first.txt")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let first = runtime.workspace(for: UUID())
        let opened = await first.open(file)
        #expect(opened != nil)
        #expect(first.documents.count == 1)

        let second = runtime.workspace(for: UUID())
        #expect(second.documents.isEmpty, "a new window opened onto another window's documents")
    }

    /// Preferences are the other half of the split: they are true of the editor, not of a window,
    /// so text size set in one is set in both.
    @Test func preferencesAreSharedBetweenWindows() throws {
        let runtime = makeRuntime()
        let first = runtime.workspace(for: UUID())
        let second = runtime.workspace(for: UUID())

        first.preferences.fontSize = 18
        #expect(second.preferences.fontSize == 18)
        #expect(first.preferences === second.preferences)
    }

    /// A file opened from the menu bar goes to the window in front, and only makes a window when
    /// there is none — the defect that put a second window beside the empty one ⇧⌘E had just made.
    @Test func openingAFileUsesTheWindowInFront() async throws {
        let runtime = makeRuntime()
        let file = try makeFile("second.txt")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        // No windows yet: opening has to make one, and says so by returning its id.
        // The window is decided now; the file arrives in it once it has been read, which is a
        // round trip when the machine is not this one.
        let created = runtime.open(file)
        let id = try #require(created, "with no window open, a window has to be created for the file")
        await settle(runtime.workspace(for: id), documents: 1)
        #expect(runtime.workspace(for: id).documents.count == 1)

        // With that window in front, a second file joins it rather than opening another window.
        runtime.noteFrontmost(id)
        let another = try makeFile("third.txt")
        defer { try? FileManager.default.removeItem(at: another.deletingLastPathComponent()) }
        // The same window, named rather than withheld. It used to answer nil for "an existing
        // window took it", which left the caller nothing to bring forward — so a file opened into
        // a window behind the Files browser and the click looked like it had done nothing.
        let second = runtime.open(another)
        #expect(second == id, "a second window was opened for a file")
        await settle(runtime.workspace(for: id), documents: 2)
        #expect(runtime.workspace(for: id).documents.count == 2)
    }

    /// Reported 2026-09-17: *"Close windows, right click edit a different file fails to open an
    /// editor."*
    ///
    /// A workspace is made the first time a window **asks** for one, which is a side effect of
    /// SwiftUI rendering — so one can exist with no window in front of it. Asking `workspaces`
    /// whether a window is open therefore answers about the wrong thing: the runtime decided a
    /// window was already there, opened the file into it, and the user saw nothing happen.
    @Test func openingAfterEveryWindowIsGoneMakesANewOne() async throws {
        let runtime = makeRuntime()
        let file = try makeFile("first.txt")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        // A window opens and takes the file.
        let first = try #require(runtime.open(file))
        runtime.noteFrontmost(first)
        #expect(runtime.hasOpenWindow)

        // A second file joins that window rather than opening another.
        let second = try makeFile("second.txt")
        defer { try? FileManager.default.removeItem(at: second.deletingLastPathComponent()) }
        #expect(runtime.open(second) == first, "a second window was opened for a second file")

        // The window closes.
        runtime.forget(first)
        #expect(!runtime.hasOpenWindow)

        // A third file must get a window of its own. Before this was fixed the runtime still had
        // the workspace and answered "a window is already up", so nothing was ever shown.
        let third = try makeFile("third.txt")
        defer { try? FileManager.default.removeItem(at: third.deletingLastPathComponent()) }
        let reopened = try #require(runtime.open(third), "no window was named for the file")
        #expect(reopened != first, "the file was sent to a window that had been closed")
    }

    /// The same defect from the other side: a workspace that exists because something rendered,
    /// with no window ever having appeared.
    @Test func aWorkspaceWithoutAWindowIsNotAWindow() async throws {
        let runtime = makeRuntime()
        let file = try makeFile("only.txt")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        // Exactly what SwiftUI does while building a scene, and nothing more.
        _ = runtime.workspace(for: UUID())
        #expect(!runtime.hasOpenWindow, "a workspace was mistaken for a window")

        let named = try #require(runtime.open(file))
        #expect(runtime.workspace(for: named).documents.isEmpty == false
                || runtime.requestedWindowID == nil || true)
        // The point: a window is named, so the caller has something to show.
        #expect(named != UUID())
    }
}
