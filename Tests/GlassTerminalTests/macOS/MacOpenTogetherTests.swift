#if os(macOS)
import Foundation
import Testing
import GlassLayers
import GlassConnectionKit
import GlassShell
@testable import GlassTerminal

/// W13 (owner, 2026-10-09): running sessions chosen in Active open as one new Mac window, a tab
/// each, attached to their own tmux sessions, in Active's order — the window W8's Move N Tabs to
/// New Window makes. SSH tabs carry their session as a workgroup's do (W4b), this Mac's as
/// Active's This Mac opens one (D47).
///
/// No tmux runs and nothing connects: hosts answer from memory, and no window opens.
@MainActor
@Suite("A Mac window of running sessions")
struct MacOpenTogetherTests {
    private func server(_ name: String) -> ServerConfiguration {
        var server = ServerConfiguration(name: name, host: "\(name).example.com", username: "ann")
        server.tmux = true
        return server
    }

    private func listed(_ name: String) -> TerminalTmux.Session {
        TerminalTmux.Session(name: name, attachedClients: 0, windows: 1)
    }

    @Test("three running sessions on two machines open as one window: three tabs, the right sessions and machines, in order")
    func threeOnTwoMachines() throws {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassTerminalCapability(runtime: runtime)
        let alpha = server("alpha"), bravo = server("bravo")
        runtime.sessionManager.serverManager.servers = [alpha, bravo]
        let rows = capability.runningReport(local: nil, hosts: [
            (alpha, .sessions([listed("glass-1"), listed("glass-2"), listed("glass-3")])),
            (bravo, .sessions([listed("logs")])),
        ]).sessions
        let chosen = rows.filter { ["glass-1", "glass-3", "logs"].contains($0.attachment?.name) }

        _ = runtime.takeRequests()
        capability.openRunningSessions(chosen.compactMap(\.attachment))
        guard case .openTmuxSessions(let targets)? = runtime.takeRequests().first else {
            Issue.record("Open together asks for the sessions together")
            return
        }
        let plan = TerminalOpenTogether.plan(targets, servers: runtime.sessionManager.serverManager.servers)
        let windows = TerminalOpenTogether.macLaunchRequests(for: plan.opening)
        #expect(windows.count == 1, "one new window")
        let tabs = try #require(windows.first).tabs
        #expect(tabs.count == 3, "a tab each")
        #expect(tabs.map { $0.initialPaneIntent?.kind } == [.ssh, .ssh, .ssh])
        #expect(tabs.map { $0.initialPaneIntent?.serverID } == [alpha.id, alpha.id, bravo.id], "each on its own machine")
        #expect(tabs.map { $0.initialPaneIntent?.sshTmuxSession } == ["glass-1", "glass-3", "logs"],
                "each attached to its own session, in Active's order")
        #expect(tabs.allSatisfy { !$0.startsEmpty && $0.workgroupID == nil && $0.liveSessionTicketID == nil },
                "tabs of their own: no workgroup, nothing connected before the window opens")
        #expect(Set(tabs.map(\.workspaceID)).count == 3)
    }

    @Test("this Mac's own session is a local tab beside a server's, and the window survives being a scene value")
    func localAndRemoteTogether() throws {
        let alpha = server("alpha")
        let targets = [TerminalTmuxTarget(attachment: GlassTerminalCapability.attachment(serverID: nil, name: "w13-build")),
                       TerminalTmuxTarget(attachment: GlassTerminalCapability.attachment(serverID: alpha.id, name: "glass-2"))]
            .compactMap { $0 }
        #expect(targets == [TerminalTmuxTarget(serverID: nil, name: "w13-build"), TerminalTmuxTarget(serverID: alpha.id, name: "glass-2")])
        let plan = TerminalOpenTogether.plan(targets, servers: [alpha])
        #expect(plan.opening == targets && plan.notOpened.isEmpty)

        let window = try #require(TerminalOpenTogether.macLaunchRequests(for: plan.opening).first)
        let decoded = try JSONDecoder().decode(MacWorkspaceLaunchRequest.self, from: JSONEncoder().encode(window))
        #expect(decoded == window)
        #expect(decoded.tabs.map { $0.initialPaneIntent?.kind } == [.local, .ssh])
        try #require(decoded.tabs.count == 2, "one window, a tab each")
        #expect(decoded.tabs[0].initialPaneIntent?.localTmuxSession == "w13-build")
        #expect(decoded.tabs[0].initialPaneIntent?.sshTmuxSession == nil)
        #expect(decoded.tabs[1].initialPaneIntent?.sshTmuxSession == "glass-2")
        #expect(decoded.tabs[1].initialPaneIntent?.localTmuxSession == nil)
    }

    @Test("more than a window holds carry on in another, in order")
    func moreThanAWindow() {
        let alpha = server("alpha")
        let targets = (1...33).map { TerminalTmuxTarget(serverID: alpha.id, name: "glass-\($0)") }
        let windows = TerminalOpenTogether.macLaunchRequests(for: targets)
        #expect(windows.map(\.tabs.count) == [32, 1])
        #expect(windows.flatMap(\.tabs).map { $0.initialPaneIntent?.sshTmuxSession } == targets.map(\.name))
    }
}
#endif
