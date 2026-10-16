#if os(macOS)
import AppKit
import Testing
import Foundation
import GlassEditorCore
@testable import GlassEditor

/// A file previewed over a terminal (2026-10-16): what it is comes from its bytes, not its name
/// ("We should check the .output file type/mime types"), and text shows in the editor's own view,
/// highlighted ("I just previewed a .swift file and it was plain text").
@MainActor
@Suite("A file previewed over a terminal")
struct GlassEditorQuickPreviewTests {
    private func file(_ name: String, _ data: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "QuickPreviewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }

    @Test("text called .output is text, in the editor's view, not Quick Look's blank icon")
    func outputIsText() async throws {
        let url = try file("task.output", Data("build started\nbuild finished\n".utf8))
        guard case .code(let document) = await GlassEditorQuickPreview.decide(url) else {
            Issue.record("not shown as text")
            return
        }
        #expect(document.model.text == "build started\nbuild finished\n")
        #expect(!document.model.configuration.isEditable, "looked at, not changed")
    }

    @Test("Swift is Swift: the editor's view, with its language, so it's highlighted")
    func swiftIsHighlighted() async throws {
        let url = try file("main.swift", Data("let greeting = \"hello\"\n".utf8))
        guard case .code(let document) = await GlassEditorQuickPreview.decide(url) else {
            Issue.record("not shown as code")
            return
        }
        #expect(document.model.language == .swift)
    }

    @Test("Markdown is rendered, as the editor previews it")
    func markdownIsRendered() async throws {
        let url = try file("README.md", Data("# Notes\n".utf8))
        guard case .preview(_, let kind) = await GlassEditorQuickPreview.decide(url) else {
            Issue.record("not the editor's preview")
            return
        }
        #expect(kind == .markdown)
    }

    @Test("a picture called .output is drawn from its bytes")
    func mislabelledPicture() async throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let url = try file("shot.output", png)
        guard case .image = await GlassEditorQuickPreview.decide(url) else {
            Issue.record("not drawn as a picture")
            return
        }
    }

    @Test("binary that's no kind of picture says so, with its size")
    func binary() async throws {
        let url = try file("blob.output", Data([0x00, 0x01, 0x02, 0x00, 0xFF, 0x00, 0x13, 0x37]))
        guard case .nothing(.binary, let size) = await GlassEditorQuickPreview.decide(url) else {
            Issue.record("not 'no preview'")
            return
        }
        #expect(size == 8)
    }
}
#endif
