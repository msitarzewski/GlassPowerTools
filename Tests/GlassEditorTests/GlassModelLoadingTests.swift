import Foundation
import RealityKit
import Testing
import GlassEditorCore

/// A 3D model RealityKit opens (D78): a text USD layer saved without its extension is given the one
/// its bytes call for, and RealityKit opens it — the viewer's path on the Mac, iPhone and iPad.
@Suite("A 3D model RealityKit opens")
@MainActor
struct GlassModelLoadingTests {
    /// A tenth of a metre's cube, in USD's text form.
    private let cube = """
    #usda 1.0
    (
        defaultPrim = "Box"
        metersPerUnit = 1
        upAxis = "Y"
    )

    def Cube "Box"
    {
        double size = 0.1
    }
    """

    @Test("a model saved under another name opens once it is named for what it is")
    func misnamedModelOpens() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GlassModelLoadingTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let saved = folder.appendingPathComponent("box.download")
        try Data(cube.utf8).write(to: saved)

        let loadable = try GlassModelFile.loadableURL(for: saved, in: folder)
        #expect(loadable.pathExtension == "usda")
        let entity = try await Entity(contentsOf: loadable)
        let extents = entity.visualBounds(relativeTo: nil).extents
        #expect(abs(extents.x - 0.1) < 0.001 && abs(extents.y - 0.1) < 0.001, "the cube, a tenth of a metre: \(extents)")
    }
}
