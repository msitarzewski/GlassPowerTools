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

    /// The owner's iPhone, 2026-10-12: "tapping a workgroup in iphone is a dead end". On a
    /// phone the library pushes a panel's detail when the panel reports a selection, and pops
    /// back by clearing it; Workgroups reported none.
    @Test("a tapped workgroup is the panel's selection, so a phone shows its detail; going back clears it")
    func selectionReachesTheLibrary() throws {
        let (model, runtime, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        let panel = try #require(model.registry.libraryPanels.first { $0.id == GlassTerminalRuntime.workgroupsPanelID })
        #expect(panel.selectedItem == nil)
        let id = UUID()
        runtime.workgroupsModel.selection = .preset(id)
        #expect(panel.selectedItem == AnyHashable(ConnectionWorkgroupSelection.preset(id)))
        runtime.workgroupsModel.selection = .live(id)
        #expect(panel.selectedItem == AnyHashable(ConnectionWorkgroupSelection.live(id)), "another row is another push")
        panel.clearSelection()
        #expect(runtime.workgroupsModel.selection == nil && panel.selectedItem == nil)
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
