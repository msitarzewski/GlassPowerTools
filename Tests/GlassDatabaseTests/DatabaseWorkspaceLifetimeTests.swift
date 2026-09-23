import Foundation
import Testing
@testable import GlassDatabase

/// Closing the last workspace window on a session ends the session; a second window closing
/// leaves it alone (2026-09-22: the database was the one capability whose red close button did
/// not end the connection).
@Suite("The last workspace window takes its session with it")
@MainActor
struct DatabaseWorkspaceLifetimeTests {
    private func manager(with sessionID: UUID) -> DatabaseSessionManager {
        let manager = DatabaseSessionManager(loadImmediately: false)
        manager.sessions[sessionID] = DatabaseSession(connectionConfig: DatabaseConnectionConfig(name: "oscar"))
        manager.sessions[sessionID]?.state = .connected
        return manager
    }

    @Test("One window: closing it ends the session")
    func lastWindowEndsTheSession() async throws {
        let sessionID = UUID()
        let manager = manager(with: sessionID)
        let window = manager.registerWorkspace(.primary(sessionID: sessionID))
        #expect(manager.sessions[sessionID] != nil)
        await manager.releaseWorkspace(window)?.value
        #expect(manager.sessions[sessionID] == nil, "the session ended with its only window")
    }

    @Test("Two windows on one session: the first closing leaves the session; the second ends it")
    func secondWindowKeepsTheSession() async throws {
        let sessionID = UUID()
        let manager = manager(with: sessionID)
        let first = manager.registerWorkspace(.primary(sessionID: sessionID))
        let second = manager.registerWorkspace(.additional(sessionID: sessionID))
        let ended = manager.releaseWorkspace(first)
        #expect(ended == nil, "another window still shows this session")
        #expect(manager.sessions[sessionID] != nil)
        await manager.releaseWorkspace(second)?.value
        #expect(manager.sessions[sessionID] == nil)
    }

    @Test("A window nobody registered releases nothing and ends nothing")
    func unknownWindowIsInert() async throws {
        let sessionID = UUID()
        let manager = manager(with: sessionID)
        #expect(manager.releaseWorkspace(UUID()) == nil)
        #expect(manager.sessions[sessionID] != nil)
    }
}
