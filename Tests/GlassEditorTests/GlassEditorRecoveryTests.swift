//
//  GlassEditorRecoveryTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  Autosave and recovery (2026-11-22, the owner's word after the editor's gaps were surveyed). Unsaved text is kept on
//  this device while it is unsaved, and a launch after a crash puts it back; saving, closing without saving and Quit
//  Without Saving let it go.
//

import Foundation
import Testing
import GlassEditorCore
@testable import GlassEditor

@MainActor
@Suite("Unsaved text kept and recovered", .serialized)
struct GlassEditorRecoveryTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func runtime(keepingIn directory: URL) -> GlassEditorRuntime {
        GlassEditorRuntime(defaults: UserDefaults.forTest(suiteName: "editor.recovery.\(UUID().uuidString)")!,
                           recoveryDirectory: directory)
    }

    private func type(_ text: String, into document: GlassEditorDocument) throws {
        let end = document.model.utf16Length
        try document.model.apply(TextEdit(replacementRange: end..<end, text: text), intent: .typing)
    }

    @Test("a document is kept while it is unsaved, its copy follows the text, and goes when it is saved or closed")
    func keptWhileUnsaved() async throws {
        let store = try folder(); defer { try? FileManager.default.removeItem(at: store) }
        let files = try folder(); defer { try? FileManager.default.removeItem(at: files) }
        let editor = runtime(keepingIn: store)
        let workspace = editor.workspace(for: UUID())

        let untitled = workspace.newDocument()
        editor.keepUnsavedTextNow()
        #expect(editor.recovery.records().isEmpty, "nothing typed, nothing kept")
        try type("draft", into: untitled)
        editor.keepUnsavedTextNow()
        #expect(editor.recovery.records().map(\.text) == ["draft"])
        try type(" two", into: untitled)
        editor.keepUnsavedTextNow()
        #expect(editor.recovery.records().map(\.text) == ["draft two"])
        #expect(workspace.close(untitled.id, force: true))
        #expect(editor.recovery.records().isEmpty, "closed without saving: let go")

        let url = files.appendingPathComponent("notes.txt")
        try Data("saved\n".utf8).write(to: url)
        let file = try #require(await workspace.open(url))
        try type("more", into: file)
        editor.keepUnsavedTextNow()
        #expect(editor.recovery.records().first?.path == url.standardizedFileURL.path(percentEncoded: false))
        await workspace.save(file.id)
        #expect(!file.isDirty)
        editor.keepUnsavedTextNow()
        #expect(editor.recovery.records().isEmpty, "saved: nothing to recover")
    }

    @Test("after a crash the next launch puts the documents back, in their windows, unsaved, and says so")
    func recoveredAfterACrash() async throws {
        let store = try folder(); defer { try? FileManager.default.removeItem(at: store) }
        let files = try folder(); defer { try? FileManager.default.removeItem(at: files) }
        let url = files.appendingPathComponent("config.yaml")
        try Data("a: 1\n".utf8).write(to: url)

        // The run that crashed: a file and an untitled document in one window, another document in a second.
        let crashed = runtime(keepingIn: store)
        let first = crashed.workspace(for: UUID())
        let file = try #require(await first.open(url))
        try type("b: 2\n", into: file)
        try type("scratch", into: first.newDocument())
        try type("other", into: crashed.workspace(for: UUID()).newDocument())
        crashed.keepUnsavedTextNow()
        #expect(crashed.recovery.records().count == 3)
        let crashedCopies = Set(crashed.recovery.records().map(\.documentID))

        // The next launch.
        let relaunched = runtime(keepingIn: store)
        let windows = await relaunched.recoverUnsavedDocuments()
        #expect(windows.count == 2, "documents that shared a window share one again")
        let back = try #require(windows.map { relaunched.workspace(for: $0) }
                                    .first { $0.documents.contains { $0.url != nil } })
        #expect(back.documents.count == 2)
        let recoveredFile = try #require(back.documents.first { $0.url != nil })
        #expect(recoveredFile.model.text == "a: 1\nb: 2\n")
        #expect(recoveredFile.isDirty, "unsaved, so it is saved or asked about like any other")
        #expect(recoveredFile.model.undo())
        #expect(recoveredFile.model.text == "a: 1\n", "Undo goes back to the file")
        #expect(back.documents.contains { $0.url == nil && $0.model.text == "scratch" })
        // Said once the window is on screen: an alert asked for before then is never shown.
        #expect(back.message == nil)
        #expect(back.noticeOnAppear?.hasPrefix("Recovered unsaved changes to config.yaml and Untitled") == true,
                "\(back.noticeOnAppear ?? "")")
        await back.sayNoticeOnAppear()
        #expect(back.message?.hasPrefix("Recovered unsaved changes to config.yaml and Untitled") == true)
        #expect(back.noticeOnAppear == nil, "once")
        #expect(await relaunched.recoverUnsavedDocuments().isEmpty, "once per launch")

        // The old copies went; the recovered documents were kept again at once, as themselves, against a second crash.
        #expect(Set(relaunched.recovery.records().map(\.documentID)).isDisjoint(with: crashedCopies))
        relaunched.keepUnsavedTextNow()
        #expect(relaunched.recovery.records().count == 2, "the file was undone to what is saved; two still unsaved")
    }

    @Test("a file that is gone, or was on another machine, comes back as an untitled copy that says where it was from")
    func unreachableFilesComeBackUntitled() async throws {
        let store = try folder(); defer { try? FileManager.default.removeItem(at: store) }
        let window = UUID()
        for record in [
            GlassEditorRecovery.Record(documentID: UUID(), windowID: window, name: ".env", path: "/srv/app/.env",
                                       machine: "alpha", language: "bash", text: "KEY=1\n", keptAt: Date()),
            GlassEditorRecovery.Record(documentID: UUID(), windowID: window, name: "gone.md",
                                       path: "/nonexistent-\(UUID().uuidString)/gone.md", machine: nil,
                                       language: "markdown", text: "# gone", keptAt: Date().addingTimeInterval(1)),
        ] {
            try JSONEncoder().encode(record).write(to: store.appendingPathComponent("\(record.documentID).json"))
        }
        // And a file that is not a copy at all.
        try Data("not json".utf8).write(to: store.appendingPathComponent("\(UUID()).json"))

        let editor = runtime(keepingIn: store)
        let windows = await editor.recoverUnsavedDocuments()
        let workspace = editor.workspace(for: try #require(windows.first))
        #expect(workspace.documents.map(\.displayName) == [".env", "gone.md"])
        #expect(workspace.documents.allSatisfy { $0.url == nil && $0.isDirty })
        #expect(workspace.documents.map(\.model.language) == [.bash, .markdown])
        #expect(workspace.noticeOnAppear?.contains(".env (from alpha)") == true, "\(workspace.noticeOnAppear ?? "")")
    }

    @Test("Quit Without Saving lets every copy go, and a file already as the copy says is not reopened")
    func discardedAndUnchanged() async throws {
        let store = try folder(); defer { try? FileManager.default.removeItem(at: store) }
        let files = try folder(); defer { try? FileManager.default.removeItem(at: files) }
        let editor = runtime(keepingIn: store)
        try type("x", into: editor.workspace(for: UUID()).newDocument())
        editor.keepUnsavedTextNow()
        #expect(editor.recovery.records().count == 1)
        editor.discardUnsavedText()
        #expect(editor.recovery.records().isEmpty)
        // The app going inactive on its way out keeps nothing again (found in the macOS VM: it did, and the document
        // let go came back at the next launch).
        editor.keepUnsavedTextNow()
        #expect(editor.recovery.records().isEmpty)

        let url = files.appendingPathComponent("same.txt")
        try Data("same".utf8).write(to: url)
        let record = GlassEditorRecovery.Record(documentID: UUID(), windowID: UUID(), name: "same.txt",
                                                path: url.path(percentEncoded: false), machine: nil,
                                                language: "plaintext", text: "same", keptAt: Date())
        try JSONEncoder().encode(record).write(to: store.appendingPathComponent("\(record.documentID).json"))
        let relaunched = runtime(keepingIn: store)
        #expect(await relaunched.recoverUnsavedDocuments().isEmpty, "the file says what the copy says")
        #expect(relaunched.recovery.records().isEmpty)
    }

    @Test("this run's own copies are never taken for an earlier run's, and an earlier run's wait for recovery")
    func earlierRunsOnly() async throws {
        let store = try folder(); defer { try? FileManager.default.removeItem(at: store) }
        let earlier = GlassEditorRecovery.Record(documentID: UUID(), windowID: UUID(), name: "Untitled 3", path: nil,
                                                 machine: nil, language: "plaintext", text: "earlier", keptAt: Date())
        try JSONEncoder().encode(earlier).write(to: store.appendingPathComponent("\(earlier.documentID).json"))

        let editor = runtime(keepingIn: store)
        let open = editor.workspace(for: UUID()).newDocument()
        try type("now", into: open)
        editor.keepUnsavedTextNow()
        #expect(editor.recovery.records().count == 2, "a sweep leaves the earlier run's copy alone")
        let windows = await editor.recoverUnsavedDocuments()
        #expect(windows.count == 1)
        let recovered = editor.workspace(for: try #require(windows.first)).documents
        #expect(recovered.map(\.model.text) == ["earlier"], "not a second copy of the document open now")
    }
}
