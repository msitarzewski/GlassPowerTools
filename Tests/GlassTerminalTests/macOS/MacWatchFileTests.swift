#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// Watch Log File's tab (the owner, 2026-10-14: "opens a new tab in the current window"): on the
/// machine the path was printed on, a plain shell that follows the file, named after it.
@MainActor
@Suite("Watch Log File's tab")
struct MacWatchFileTests {
    private func tab(_ intent: MacWorkspacePaneIntent) throws -> (MacWorkspaceController, UUID) {
        let defaults = try #require(UserDefaults.forTest(suiteName: "MacWatchFileTests.\(UUID())"))
        let controller = MacWorkspaceController(request: MacWorkspaceTabRequest(initialPaneIntent: intent), defaults: defaults)
        return (controller, try #require(controller.state.root?.panes.first?.id))
    }

    @Test("from a local pane: a local tab in the pane's folder, without tmux, following the file")
    func fromALocalPane() async throws {
        let (controller, pane) = try tab(.local(shell: "/bin/zsh", directory: "/srv/app"))
        let broker = MacStartupCommandBroker()
        let request = try #require(await controller.watchFileRequest("logs/a b.log", from: pane, broker: broker))
        #expect(request.initialPaneIntent == MacWorkspacePaneIntent.local(shell: "/bin/zsh", directory: "/srv/app").startingWithoutTmux())
        #expect(request.tabLabel == "a b.log")
        let ticket = try #require(request.startupTicketID)
        #expect(broker.claim(ticket)?.command == #"tail -F /srv/app/logs/a\ b.log"#)
    }

    @Test("from an SSH pane: a tab on the same host, without tmux; a relative path with no folder known is refused")
    func fromAnSSHPane() async throws {
        let server = UUID()
        let (controller, pane) = try tab(.ssh(serverID: server))
        let broker = MacStartupCommandBroker()
        let request = try #require(await controller.watchFileRequest("/var/log/syslog", from: pane, broker: broker))
        #expect(request.initialPaneIntent == MacWorkspacePaneIntent.ssh(serverID: server).startingWithoutTmux())
        #expect(broker.claim(try #require(request.startupTicketID))?.command == "tail -F /var/log/syslog")
        #expect(await controller.watchFileRequest("logs/app.log", from: pane, broker: broker) == nil)
    }
}
#endif
