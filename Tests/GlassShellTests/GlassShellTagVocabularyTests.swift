import Foundation
import Testing
import GlassLayers
import GlassConnectionKit
@testable import GlassShell

@Suite("Shell tag vocabulary", .serialized)
@MainActor
struct GlassShellTagVocabularyTests {
    private func makeModel() throws -> (GlassShellModel, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassShellTagTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                    layers: GlassLayerStore.forTest())
        return (model, root)
    }

    @Test("The vocabulary is the union of every host's tags, deduped case-insensitively and sorted")
    func vocabularyUnionsHosts() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.tagVocabulary.isEmpty)
        _ = try await model.addHost(displayName: "alpha", aliases: [], tags: ["Clients", "lab", "prod"])
        _ = try await model.addHost(displayName: "bravo", aliases: ["foxtrot"], tags: ["Prod", "Home", " clients "])
        let vocabulary = model.tagVocabulary
        // Spelled as each was first written — alpha's "Clients" and "prod", not bravo's " clients " or
        // "Prod" — one entry per tag, sorted case-insensitively. (Compared lowercased until 2026-10-24,
        // which no spelling could fail.)
        #expect(vocabulary == ["Clients", "Home", "lab", "prod"], "got \(vocabulary)")
    }

}
