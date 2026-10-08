import Foundation
import Testing
import GlassLayers
import GlassShell
import GlassConnectionUI
@testable import GlassTerminal

/// Workgroups is a panel in the Connections window's sidebar, and nothing else (2026-10-08).
///
/// It had a window of its own as well, which Window ▸ Workgroups opened; resizing that window
/// crashed the app four times in four minutes, and the owner asked why it existed at all. The
/// menu items now ask the library for its Workgroups panel.
@Suite("Workgroups opens in the library")
@MainActor
struct WorkgroupsInLibraryTests {
    private func makeShell() throws -> (GlassShellModel, GlassTerminalRuntime, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkgroupsPanel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore())
        model.registry.register(GlassTerminalCapability(runtime: runtime))
        // As the composition root wires it.
        runtime.showLibraryPanel = { [weak model] panelID in model?.showPanel(panelID) }
        return (model, runtime, root)
    }

    @Test("Asking for Workgroups asks the library for the panel it actually has")
    func asksForTheLibrarysOwnPanel() throws {
        let (model, runtime, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.panelToShow == nil)

        runtime.showWorkgroupsPanel()

        let requested = try #require(model.panelToShow, "nothing asked the library for a panel")
        let panel = try #require(model.registry.libraryPanels.first { $0.id == requested },
                                 "the library has no panel called \(requested), so the request would open nothing")
        #expect(panel.title == "Workgroups")
    }

    @Test("Asking twice opens it twice")
    func askingAgainIsAChange() throws {
        let (model, runtime, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        runtime.showWorkgroupsPanel()
        // What the library does once it has opened the panel.
        model.panelToShow = nil
        runtime.showWorkgroupsPanel()
        #expect(model.panelToShow == GlassTerminalRuntime.workgroupsPanelID)
    }
}
