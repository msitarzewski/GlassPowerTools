import Foundation
import Testing
@testable import GlassEditorCore

/// 3D models (D78): which links are models, and a model given the name RealityKit opens it by.
@Suite("3D model files and links")
struct ModelFileTests {
    @Test("a web address ending in a model's extension is a model's link, whatever follows")
    func links() throws {
        let apple = try #require(URL(string:
            "https://www.apple.com/105/media/us/imac/2024/e1d50c6b-bc34-47bd-850d-379149b71fb8/ar/imac-with-accessories-blue.usdz"))
        #expect(GlassModelFile.isModelLink(apple))
        #expect(GlassModelFile.isModelLink(try #require(URL(string: "http://example.com/Scene.USDA?v=2#top"))))
        #expect(GlassModelFile.isModelLink(try #require(URL(string: "https://example.com/a.reality"))))
        #expect(!GlassModelFile.isModelLink(try #require(URL(string: "https://example.com/archive.zip"))))
        #expect(!GlassModelFile.isModelLink(try #require(URL(string: "https://example.com/models/"))))
        #expect(!GlassModelFile.isModelLink(try #require(URL(string: "ftp://example.com/a.usdz"))), "the web only")
        #expect(!GlassModelFile.isModelLink(URL(fileURLWithPath: "/tmp/a.usdz")), "a file isn't a link")
    }

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ModelFileTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("a model named for what it is opens as itself; one that isn't is given the name its bytes call for")
    func loadableNames() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let named = folder.appendingPathComponent("cube.usda")
        try Data("#usda 1.0\n".utf8).write(to: named)
        #expect(try GlassModelFile.loadableURL(for: named, in: folder) == named)

        let usdz = folder.appendingPathComponent("download")
        try Data([0x50, 0x4B, 0x03, 0x04] + Array(repeating: 0, count: 40)).write(to: usdz)
        let asUSDZ = try GlassModelFile.loadableURL(for: usdz, in: folder)
        #expect(asUSDZ.lastPathComponent == "download.usdz")
        #expect(try Data(contentsOf: asUSDZ) == Data(contentsOf: usdz), "the same bytes")

        let crate = folder.appendingPathComponent("layer.bin")
        try Data("PXR-USDC".utf8 + [0, 0]).write(to: crate)
        #expect(try GlassModelFile.loadableURL(for: crate, in: folder).lastPathComponent == "layer.usdc")
        let text = folder.appendingPathComponent("layer.txt")
        try Data("#usda 1.0\n".utf8).write(to: text)
        #expect(try GlassModelFile.loadableURL(for: text, in: folder).pathExtension == "usda")
    }

    @Test("only a text USD layer can also be opened as text")
    func textLayers() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = folder.appendingPathComponent("a.usda")
        try Data("#usda 1.0\n".utf8).write(to: text)
        let binary = folder.appendingPathComponent("a.usdc")
        try Data("PXR-USDC".utf8).write(to: binary)
        #expect(GlassModelFile.isText(text))
        #expect(!GlassModelFile.isText(binary))
    }
}
