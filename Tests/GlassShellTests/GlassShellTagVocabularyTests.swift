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
                                    layers: GlassLayerStore())
        return (model, root)
    }

    @Test("The vocabulary is the union of every host's tags, deduped case-insensitively and sorted")
    func vocabularyUnionsHosts() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.tagVocabulary.isEmpty)
        _ = try await model.addHost(displayName: "oscar", aliases: [], tags: ["Clients", "lab", "prod"])
        _ = try await model.addHost(displayName: "juliet", aliases: ["beast"], tags: ["Prod", "Home", " clients "])
        let vocabulary = model.tagVocabulary
        #expect(vocabulary.map { $0.lowercased() } == ["clients", "home", "lab", "prod"],
                "one entry per tag regardless of case or whitespace, sorted case-insensitively; got \(vocabulary)")
        #expect(Set(vocabulary.map { $0.lowercased() }).count == vocabulary.count)
    }

    @Test("Pure vocabulary keeps the first spelling and ignores blanks")
    func pureVocabulary() {
        #expect(GlassShellTagVocabulary.tags(in: []).isEmpty)
    }
}
