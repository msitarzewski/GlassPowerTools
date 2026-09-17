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
        GlassEditorWorkspace(defaults: UserDefaults(suiteName: "editor.tests.\(UUID().uuidString)")!)
    }

    private func write(_ text: String, named name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    // MARK: Opening and saving

    @Test func openingAFileReadsItAndNamesIt() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("SELECT 1;\n", named: "query.sql", in: root)
        let workspace = makeWorkspace()

        let document = try #require(workspace.open(url))
        #expect(document.model.text == "SELECT 1;\n")
        #expect(document.displayName == "query.sql")
        // The grammar comes from the extension, which is what makes the text coloured on open.
        #expect(document.model.language == .sql)
        #expect(!document.isDirty)
    }

    /// A file opened and saved with no edit must come back byte-identical. An editor that
    /// re-encodes or re-terminates on save turns a one-character change into a whole-file diff.
    @Test func savingAnUneditedFileChangesNothing() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        // CRLF on purpose: the platform default is LF, so a naive save would rewrite every line.
        let original = "alpha\r\nbeta\r\n"
        let url = try write(original, named: "windows.txt", in: root)
        let workspace = makeWorkspace()

        let document = try #require(workspace.open(url))
        try document.save()

        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after == original, "the file was rewritten: \(after.debugDescription)")
    }

    @Test func editingThenSavingWritesTheNewText() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("one\n", named: "notes.txt", in: root)
        let workspace = makeWorkspace()

        let document = try #require(workspace.open(url))
        try document.model.replaceAllContent(with: "two\n")
        #expect(document.isDirty)
        workspace.save(document.id)

        #expect(try String(contentsOf: url, encoding: .utf8) == "two\n")
        #expect(!document.isDirty, "saving did not mark the document clean")
        #expect(workspace.message == nil)
    }

    /// Opening the same file twice must select the one already open. Two editors over one file is
    /// how an editor loses work.
    @Test func openingAFileTwiceSelectsTheOpenOne() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("x", named: "same.txt", in: root)
        let workspace = makeWorkspace()

        let first = try #require(workspace.open(url))
        let second = try #require(workspace.open(url))
        #expect(first.id == second.id)
        #expect(workspace.documents.count == 1)
    }

    @Test func aFolderIsNotAFile() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = makeWorkspace()
        #expect(workspace.open(root) == nil)
        #expect(workspace.message?.contains("folder") == true)
    }

    // MARK: Closing

    @Test func closingRefusesWhileThereAreUnsavedChanges() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("keep me", named: "precious.txt", in: root)
        let workspace = makeWorkspace()
        let document = try #require(workspace.open(url))
        try document.model.replaceAllContent(with: "changed")

        #expect(workspace.close(document.id) == false, "an unsaved document was closed silently")
        #expect(workspace.documents.count == 1)
        #expect(workspace.close(document.id, force: true))
        #expect(workspace.documents.isEmpty)
    }

    /// Closing a tab should leave you looking at its neighbour, not jump you to the first one.
    @Test func closingSelectsTheNeighbour() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = makeWorkspace()
        let a = try #require(workspace.open(try write("a", named: "a.txt", in: root)))
        let b = try #require(workspace.open(try write("b", named: "b.txt", in: root)))
        let c = try #require(workspace.open(try write("c", named: "c.txt", in: root)))

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

    @Test func anUnsavedDocumentSaysItHasNowhereToGo() {
        let workspace = makeWorkspace()
        let document = workspace.newDocument()
        #expect(document.hasNeverBeenSaved)
        #expect(throws: GlassEditorWorkspaceError.needsLocation) { try document.save() }
    }

    @Test func savingToANewLocationAdoptsItAndItsLanguage() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = makeWorkspace()
        let document = workspace.newDocument()
        try document.model.replaceAllContent(with: "key: value\n")

        let destination = root.appendingPathComponent("config.yaml")
        workspace.save(document.id, to: destination)

        #expect(document.url == destination)
        #expect(document.displayName == "config.yaml")
        #expect(document.model.language == .yaml, "the language did not follow the chosen name")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "key: value\n")
    }

    // MARK: Find

    @Test func findAndReplaceRunThroughTheDocument() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = try write("red green red blue red", named: "colours.txt", in: root)
        let workspace = makeWorkspace()
        let document = try #require(workspace.open(url))

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

    @Test func recentsAreNewestFirstDedupedAndBounded() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = makeWorkspace()
        for index in 0..<(GlassEditorWorkspace.recentsLimit + 5) {
            workspace.open(try write("x", named: "file\(index).txt", in: root))
        }
        #expect(workspace.recents.count == GlassEditorWorkspace.recentsLimit,
                "the recents list is unbounded")
        #expect(workspace.recents.first?.lastPathComponent == "file24.txt", "recents are not newest first")

        // Re-opening an old one moves it to the front rather than adding a second entry.
        let again = try write("x", named: "file24.txt", in: root)
        workspace.open(again)
        #expect(workspace.recents.filter { $0.lastPathComponent == "file24.txt" }.count == 1)
    }
}
