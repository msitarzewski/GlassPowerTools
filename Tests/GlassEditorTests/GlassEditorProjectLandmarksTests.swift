import Testing
@testable import GlassEditor

@Suite("What a project root says about itself")
@MainActor
struct GlassEditorProjectLandmarksTests {
    private func nodes(_ entries: [(String, Bool)]) -> [GlassEditorProjectNode] {
        entries.map { GlassEditorProjectNode(name: $0.0, path: "/work/thing/\($0.0)", isDirectory: $0.1) }
    }

    @Test func findsAgentFilesBuildFilesAndTheReadme() {
        let found = GlassEditorProjectLandmarks.detect(in: nodes([
            ("AGENTS.md", false), ("CLAUDE.md", false), ("README.md", false),
            ("Package.swift", false), ("Sources", true), ("notes.md", false)
        ]))
        #expect(found.agentFiles == ["AGENTS.md", "CLAUDE.md"], "in the list's order, not the directory's")
        #expect(found.readFirst == ["README.md"])
        #expect(found.build == ["Package.swift"])
        #expect(!found.isGitRepository)
        #expect(!found.isEmpty)
    }

    @Test func matchesCaseInsensitivelyAndKeepsTheRealSpelling() {
        let found = GlassEditorProjectLandmarks.detect(in: nodes([("readme", false), ("Makefile", false)]))
        #expect(found.readFirst == ["readme"], "the name is opened, so it is the name on disk")
        #expect(found.build == ["Makefile"])
    }

    @Test func aDotGitDirectoryIsWhatMakesItARepository() {
        #expect(GlassEditorProjectLandmarks.detect(in: nodes([(".git", true)])).isGitRepository)
        // A *file* called .git is a worktree pointer, and either way a folder of notes with a file
        // of that name is not a repository this can say anything about.
        #expect(!GlassEditorProjectLandmarks.detect(in: nodes([(".git", false)])).isGitRepository)
    }

    @Test func anOrdinaryFolderHasNothingToSay() {
        let found = GlassEditorProjectLandmarks.detect(in: nodes([
            ("3DBenchy.stl", false), ("1-Ender_BIT_enderzi.gcode", false), ("Poppy", true)
        ]))
        #expect(found.isEmpty, "a folder of models is not a repository with no readme")
    }

    @Test func aDirectoryNamedLikeALandmarkIsNotOne() {
        // `docs/README.md` is a file; a *folder* called README is not the thing to open.
        let found = GlassEditorProjectLandmarks.detect(in: nodes([("README.md", true)]))
        #expect(found.readFirst.isEmpty)
    }
}
