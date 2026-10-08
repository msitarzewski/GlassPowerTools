import Testing
import Foundation
import GlassLayers
@testable import GlassShell

/// Something outside the library asking for one of its panels: the ⚡ for Active, and since
/// 2026-10-08 Window ▸ Workgroups for Workgroups, which no longer has a window of its own.
@Suite("Asking the library for a panel")
@MainActor
struct GlassShellPanelRouteTests {
    private func makeShell() throws -> (GlassShellModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanelRoute-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        return (model, root)
    }

    @Test("A panel asked for is the one the library is told to open, and can be asked for again")
    func showPanelRequestsThatPanel() throws {
        let (model, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.panelToShow == nil, "nothing is requested until something asks")

        model.showPanel("workgroups")
        #expect(model.panelToShow == "workgroups")

        // What the library does once the panel is open: the same panel asked for again is then a
        // change the view can see.
        model.panelToShow = nil
        model.showPanel("workgroups")
        #expect(model.panelToShow == "workgroups", "the same panel can be asked for twice")
    }

    @Test("The bolt goes through the same request")
    func boltAsksForActive() throws {
        let (model, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        model.showActiveConnections()
        #expect(model.panelToShow == GlassShellModel.activePanelID)
    }
}
