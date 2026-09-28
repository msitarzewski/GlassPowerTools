import Foundation
import Testing
import GlassLayers
import GlassConnectionKit
import GlassShell
@testable import GlassTerminal

/// A live terminal in no workgroup — every terminal Connect opens on a Mac — is a row in Active,
/// on its machine (2026-09-22: the MySQL session on alpha was listed and the terminal beside it
/// was not).
@Suite("Active lists a terminal that is in no workgroup")
@MainActor
struct TerminalActiveListingTests {
    private func session(named name: String) -> TerminalSession {
        TerminalSession(server: ServerConfiguration(name: name, host: "example.invalid", port: 22, username: "casey"))
    }

    @Test("A lone session is one row, on its server's endpoint; grouped, it is the workgroup's row")
    func loneSessionIsListed() {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let session = session(named: "alpha")
        manager.registerSession(session)
        session.state = .connected

        let lone = capability.openSessions()
        #expect(lone.map(\.id) == [GlassTerminalCapability.sessionID(sessionID: session.id)])
        #expect(lone.first?.title == "alpha")
        #expect(lone.first?.endpointIDs == [EndpointID(rawValue: session.server.id)], "on its machine")

        let group = manager.createWorkgroup(name: "alpha", colorTag: .blue)
        #expect(manager.appendSession(session, toWorkgroup: group))
        let grouped = capability.openSessions()
        #expect(grouped.map(\.id) == [GlassTerminalCapability.sessionID(workgroupID: group)], "once, as the workgroup")
        manager.closeWorkgroup(group)
    }

    @Test("Closing a lone session's row ends the session")
    func closeEndsTheSession() {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore())
        let capability = GlassTerminalCapability(runtime: runtime)
        let manager = runtime.sessionManager
        let session = session(named: "alpha")
        manager.registerSession(session)
        capability.openSessions().first?.close()
        #expect(manager.sessions.isEmpty)
    }
}
