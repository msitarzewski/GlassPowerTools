#if os(macOS)
import Foundation
import Testing
import GlassLayers
@testable import GlassTerminal

/// The terminal's Command Palette commands work from any window (2026-10-14): they were the
/// Connections window's own, missing whenever a terminal window was in front.
@MainActor
@Suite("The terminal's Command Palette commands")
struct GlassTerminalCommandCenterTests {
    private final class Recorder {
        var connectionsOpen = false
        var openedConnections = 0
        var workspaces: [MacWorkspaceLaunchRequest] = []
        var workgroups = 0
    }

    private func entries(_ runtime: GlassTerminalRuntime, _ recorder: Recorder) -> [MacCommandCenterEntry] {
        GlassTerminalCommandCenter.entries(runtime: runtime, windows: .init(
            connectionsOpen: { recorder.connectionsOpen },
            openConnections: { recorder.openedConnections += 1 },
            openWorkspace: { recorder.workspaces.append($0) },
            showWorkgroups: { recorder.workgroups += 1 },
            openTailscale: {}))
    }

    @Test("a machine's terminal is the library's entry; the terminal adds its own windows and panels")
    func titles() {
        let titles = entries(GlassTerminalRuntime(layers: GlassLayerStore.forTest()), Recorder()).map(\.title)
        #expect(Array(titles.prefix(4)) == ["New Connection", "Open Local Terminal", "Open Basic Local Terminal", "Workgroups"])
        #expect(!titles.contains { $0.hasPrefix("Connect to ") && !$0.hasSuffix(" without tmux") })
    }

    @Test("New Connection opens Connections when none is open, and leaves it the request to carry out")
    func newConnectionFromATerminalWindow() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let recorder = Recorder()
        try #require(entries(runtime, recorder).first { $0.title == "New Connection" }).action()
        #expect(recorder.openedConnections == 1)
        guard case .addServer = try #require(runtime.takeRequests().first) else {
            Issue.record("New Connection asks for the Add Connection sheet")
            return
        }
        recorder.connectionsOpen = true
        try #require(entries(runtime, recorder).first { $0.title == "New Connection" }).action()
        #expect(recorder.openedConnections == 1, "one already open is used")
    }

    @Test("the local terminals open their own windows, with no Connections window")
    func localTerminals() throws {
        let recorder = Recorder()
        let list = entries(GlassTerminalRuntime(layers: GlassLayerStore.forTest()), recorder)
        try #require(list.first { $0.title == "Open Local Terminal" }).action()
        try #require(list.first { $0.title == "Open Basic Local Terminal" }).action()
        #expect(recorder.openedConnections == 0)
        #expect(recorder.workspaces.map(\.initialPaneIntent?.withoutTmux) == [nil, true])
    }
}
#endif
