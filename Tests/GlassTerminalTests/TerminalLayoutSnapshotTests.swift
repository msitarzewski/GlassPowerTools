import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlassShell
@testable import GlassTerminal

/// What iPhone, iPad and Vision Pro publish to the shared layout (phase 1, 2026-11-22): each workgroup a window, each
/// terminal a tab under the id it keeps across relaunches.
@Suite("The shared layout: the terminals off the Mac")
@MainActor
struct TerminalLayoutSnapshotTests {
    private func server(_ name: String, tmux: Bool) -> ServerConfiguration {
        var server = ServerConfiguration(name: name, host: "\(name).example.com", username: "ann")
        server.tmux = tmux
        return server
    }

    @Test("a terminal in tmux is a tab another device can join; one outside tmux is a shell here; one getting its session waits")
    func tabs() throws {
        let manager = GlassTerminalRuntime(layers: GlassLayerStore.forTest()).sessionManager
        let alpha = server("alpha", tmux: true), bravo = server("bravo", tmux: false)
        let window = manager.createWorkgroup(name: "Work", colorTag: .blue)
        func terminal(_ server: ServerConfiguration, tmux: String?) -> TerminalSession {
            let session = TerminalSession(server: server)
            session.tmuxSessionName = tmux
            manager.registerSession(session)
            _ = manager.appendSession(session, toWorkgroup: window)
            return session
        }
        let inTmux = terminal(alpha, tmux: "glass-3")
        inTmux.tmuxSessionCreated = 1_790_000_000
        let plain = terminal(bravo, tmux: nil)
        _ = terminal(alpha, tmux: nil)  // tmux on its machine, its session not claimed yet

        #expect(TerminalLayoutSnapshot.current(manager, settled: false) == nil,
                "nothing before the last run's windows are back")
        let snapshot = try #require(TerminalLayoutSnapshot.current(manager, settled: true))
        let only = try #require(snapshot.windows.first)
        #expect(snapshot.windows.count == 1 && only.id == window)
        #expect(only.tabs.map(\.id) == [inTmux.layoutTabID, plain.layoutTabID], "the one getting its session isn't listed yet")
        #expect(only.tabs[0] == GlassLayoutSnapshot.Tab(id: inTmux.layoutTabID, title: only.tabs[0].title,
                                                        endpointID: EndpointID(rawValue: alpha.id),
                                                        tmuxSession: "glass-3", tmuxCreated: 1_790_000_000,
                                                        isShellHere: false))
        #expect(only.tabs[1].isShellHere && only.tabs[1].tmuxSession == nil
                && only.tabs[1].endpointID == EndpointID(rawValue: bravo.id))

        let empty = manager.createWorkgroup(name: "Empty", colorTag: .blue)
        #expect(TerminalLayoutSnapshot.current(manager, settled: true)?.windows.map(\.id) == [window],
                "a window with no terminal isn't listed: \(empty)")
    }
}
