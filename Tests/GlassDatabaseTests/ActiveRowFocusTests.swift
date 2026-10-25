import Foundation
import Testing
import GlassLayers
@testable import GlassDatabase

/// Active's database row says where the workspace is, not only that it is connected
/// (2026-09-22: Active should say which table the open workspace is on).
@Suite("Active's database row reflects what the workspace is looking at")
@MainActor
struct ActiveRowFocusTests {
    @Test("The focus is the database, the table in its database, or the SQL document; nothing on the overview")
    func focusDescriptions() {
        let title: (UUID) -> String? = { _ in "Untitled SQL 2" }
        #expect(DatabaseWorkspaceView.focus(for: .connection, queryTitle: title) == nil)
        #expect(DatabaseWorkspaceView.focus(for: .database("shop"), queryTitle: title) == "shop")
        #expect(DatabaseWorkspaceView.focus(for: .table(database: "shop", table: "articles"), queryTitle: title)
                == "shop › articles")
        #expect(DatabaseWorkspaceView.focus(for: .query(id: UUID()), queryTitle: title) == "Untitled SQL 2")
        #expect(DatabaseWorkspaceView.focus(for: .query(id: UUID()), queryTitle: { _ in nil }) == "SQL")
    }

    @Test("Connected, the subtitle carries the focus after the engine; other states say the state")
    func subtitles() {
        #expect(GlassDatabaseCapability.subtitle(engine: .mysql, state: .connected, focus: "shop › articles")
                == "MySQL · shop › articles")
        #expect(GlassDatabaseCapability.subtitle(engine: .mysql, state: .connected, focus: nil) == "MySQL")
        #expect(GlassDatabaseCapability.subtitle(engine: .mysql, state: .disconnected, focus: "shop")
                == "MySQL · Disconnected", "a focus means nothing on a session that is not connected")
    }

    @Test("Moving to another table or tab marks the session active, for the library's time in use (2026-10-20)")
    func focusIsActivity() throws {
        let runtime = GlassDatabaseRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassDatabaseCapability(runtime: runtime)
        let session = DatabaseSession(connectionConfig: DatabaseConnectionConfig(name: "MySQL on alpha"))
        runtime.sessionManager.sessions[UUID()] = session
        let row = try #require(capability.openSessions().first)
        #expect(row.lastActivity?() == nil)
        let before = Date()
        session.workspaceFocus = "shop › articles"
        let first = try #require(row.lastActivity?())
        #expect(first >= before)
        session.workspaceFocus = "shop › articles"
        #expect(row.lastActivity?() == first, "the same place again isn't activity")
    }

    @Test("The row Active gets carries the session's focus")
    func rowCarriesFocus() {
        let runtime = GlassDatabaseRuntime(layers: GlassLayerStore.forTest())
        let capability = GlassDatabaseCapability(runtime: runtime)
        let session = DatabaseSession(connectionConfig: DatabaseConnectionConfig(name: "MySQL on alpha"))
        session.state = .connected
        session.workspaceFocus = "shop › articles"
        runtime.sessionManager.sessions[UUID()] = session
        let row = capability.openSessions().first
        #expect(row?.title == "MySQL on alpha")
        #expect(row?.subtitle == "MySQL · shop › articles")
    }
}
