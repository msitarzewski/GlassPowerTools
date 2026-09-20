import Testing
import Foundation
@testable import GlassEditor

@Suite("The provisional tab: one click shows, commitment keeps")
@MainActor
struct GlassEditorPreviewTabTests {
    private func folder(_ names: [String]) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glass-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for name in names {
            try Data("\(name)\n".utf8).write(to: url.appendingPathComponent(name))
        }
        return url
    }

    private func workspace() -> GlassEditorWorkspace {
        GlassEditorWorkspace(defaults: UserDefaults(suiteName: "glass-preview-\(UUID().uuidString)")!)
    }

    @Test func oneClickAfterAnotherReusesTheSameTab() async throws {
        let workspace = workspace()
        let root = try folder(["a.txt", "b.txt", "c.txt"])

        let a = try #require(await workspace.open(root.appendingPathComponent("a.txt"), asPreview: true))
        #expect(workspace.documents.count == 1)
        #expect(workspace.isPreview(a.id))

        let b = try #require(await workspace.open(root.appendingPathComponent("b.txt"), asPreview: true))
        #expect(workspace.documents.count == 1, "reading down a folder must not leave a tab per file")
        #expect(workspace.documents.first?.id == b.id)
        #expect(workspace.isPreview(b.id))
        #expect(workspace.selection == b.id)

        _ = await workspace.open(root.appendingPathComponent("c.txt"), asPreview: true)
        #expect(workspace.documents.count == 1)
    }

    @Test func aDoubleClickKeepsTheFile() async throws {
        let workspace = workspace()
        let root = try folder(["a.txt", "b.txt"])

        let a = try #require(await workspace.open(root.appendingPathComponent("a.txt"), asPreview: true))
        // The second open of the same file is the double click's second half.
        _ = await workspace.open(root.appendingPathComponent("a.txt"))
        #expect(!workspace.isPreview(a.id), "opening it deliberately is what keeps it")

        _ = await workspace.open(root.appendingPathComponent("b.txt"), asPreview: true)
        #expect(workspace.documents.count == 2, "the kept file is still there beside the new preview")
    }

    @Test func aPreviewTakesThePlaceOfTheOneItReplaces() async throws {
        // The tab must not jump to the end of the strip while someone is clicking down a list.
        let workspace = workspace()
        let root = try folder(["kept.txt", "one.txt", "two.txt"])

        _ = await workspace.open(root.appendingPathComponent("kept.txt"))
        let one = try #require(await workspace.open(root.appendingPathComponent("one.txt"), asPreview: true))
        #expect(workspace.documents.map(\.id).firstIndex(of: one.id) == 1)

        let two = try #require(await workspace.open(root.appendingPathComponent("two.txt"), asPreview: true))
        #expect(workspace.documents.count == 2)
        #expect(workspace.documents.map(\.id).firstIndex(of: two.id) == 1, "it took the same slot")
    }

    @Test func anEditedPreviewIsKeptRatherThanReplaced() async throws {
        let workspace = workspace()
        let root = try folder(["draft.txt", "next.txt"])

        let draft = try #require(await workspace.open(root.appendingPathComponent("draft.txt"), asPreview: true))
        try draft.model.replaceAllContent(with: "something worth losing\n")
        #expect(draft.isDirty)

        _ = await workspace.open(root.appendingPathComponent("next.txt"), asPreview: true)
        #expect(workspace.documents.count == 2, "a file with unsaved changes is never evicted by a click")
        #expect(workspace.documents.contains { $0.id == draft.id })
        #expect(!workspace.isPreview(draft.id), "and it stops being provisional")
    }

    @Test func savingKeepsIt() async throws {
        let workspace = workspace()
        let root = try folder(["a.txt"])
        let a = try #require(await workspace.open(root.appendingPathComponent("a.txt"), asPreview: true))
        try a.model.replaceAllContent(with: "edited\n")
        await workspace.save(a.id)
        #expect(!workspace.isPreview(a.id))
    }

    @Test func closingThePreviewEmptiesTheSlot() async throws {
        let workspace = workspace()
        let root = try folder(["a.txt", "b.txt"])
        let a = try #require(await workspace.open(root.appendingPathComponent("a.txt"), asPreview: true))
        #expect(workspace.close(a.id))
        #expect(workspace.previewDocumentID == nil, "a slot pointing at a closed document is a leak")

        let b = try #require(await workspace.open(root.appendingPathComponent("b.txt"), asPreview: true))
        #expect(workspace.isPreview(b.id))
        #expect(workspace.documents.count == 1)
    }

    @Test func openingDeliberatelyNeverMakesAPreview() async throws {
        let workspace = workspace()
        let root = try folder(["a.txt", "b.txt"])
        _ = await workspace.open(root.appendingPathComponent("a.txt"))
        _ = await workspace.open(root.appendingPathComponent("b.txt"))
        #expect(workspace.previewDocumentID == nil)
        #expect(workspace.documents.count == 2)
    }
}
