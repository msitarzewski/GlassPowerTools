import Testing
import Foundation
@testable import GlassEditor

@Suite("A folder open in a window, and the list that outlives it")
@MainActor
struct GlassEditorProjectKeepingTests {
    private func scratch() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glass-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("# hello\n".utf8).write(to: url.appendingPathComponent("README.md"))
        return url
    }

    private func runtime() -> GlassEditorRuntime {
        let defaults = UserDefaults.forTest(suiteName: "glass-editor-keeping-\(UUID().uuidString)")!
        return GlassEditorRuntime(defaults: defaults)
    }

    @Test func openProjectInAWindowLeavesItOutOfTheList() throws {
        // `Open Project…` in an editor window opens the folder straight into the workspace. It is
        // a project you can work in and cannot find again — which is what the suggestion in the
        // toolbar is for (reported 2026-09-18).
        let runtime = runtime()
        let workspace = runtime.workspace(for: UUID())
        let url = try scratch()
        let project = try #require(workspace.openProject(url))

        #expect(!runtime.isRemembered(project), "the window has it; the list does not")
        #expect(runtime.projects.projects.isEmpty)

        runtime.remember(project)
        #expect(runtime.isRemembered(project), "and accepting the offer is what puts it there")
        #expect(runtime.projects.projects.count == 1)
    }

    @Test func openingThroughTheRuntimeRemembersItWithoutAsking() throws {
        // The routes that already mean "this is a project" — the library, and Open in Editor on a
        // folder in the Files browser — do not need to ask.
        let runtime = runtime()
        let url = try scratch()
        _ = runtime.openProject(url)
        #expect(runtime.projects.projects.count == 1)
    }

    @Test func renamingReachesTheListAndNotJustTheWindow() throws {
        let runtime = runtime()
        let workspace = runtime.workspace(for: UUID())
        let url = try scratch()
        let opened = try #require(workspace.openProject(url))
        let project = runtime.remember(opened)

        runtime.rename(project.id, to: "Sensor Rig", in: workspace)
        #expect(workspace.projects.first?.displayName == "Sensor Rig")
        #expect(runtime.projects.projects.first?.displayName == "Sensor Rig",
                "a name only the window knows is gone at the next launch")
    }

    @Test func aProjectsTextOverridesReachTheListAndTheOpenDocuments() async throws {
        let runtime = runtime()
        let workspace = runtime.workspace(for: UUID())
        let url = try scratch()
        let opened = try #require(workspace.openProject(url))
        let project = runtime.remember(opened)
        let document = try #require(await workspace.open(url.appendingPathComponent("README.md")))

        runtime.setTextOverrides(GlassEditorTextOverrides(fontSize: 19), forProject: project.id,
                                 in: workspace)
        #expect(runtime.projects.projects.first?.textOverrides?.fontSize == 19,
                "the project keeps it, and it travels")
        #expect(document.model.configuration.fontSize == 19,
                "and the document already open follows it without being reopened")

        // A file may disagree with its own project, and does so only while it is open.
        workspace.setTextOverrides(GlassEditorTextOverrides(fontSize: 24), for: document)
        #expect(document.model.configuration.fontSize == 24)
        #expect(runtime.projects.projects.first?.textOverrides?.fontSize == 19,
                "a file's disagreement is not the project's")

        // Clearing the file's falls back to the project's rather than to today's number.
        workspace.setTextOverrides(GlassEditorTextOverrides(), for: document)
        #expect(document.model.configuration.fontSize == 19)
    }
}
