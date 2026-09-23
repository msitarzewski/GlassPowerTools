import Foundation
import Testing
import GlassLayers
@testable import GlassDatabase

/// Active's database row says where the workspace is, not only that it is connected
/// (2026-09-22: *"I have the DB open, but I'm in common-vision.articles"*).
@Suite("Active's database row reflects what the workspace is looking at")
@MainActor
struct ActiveRowFocusTests {
    @Test("The focus is the database, the table in its database, or the SQL document; nothing on the overview")
    func focusDescriptions() {
        let title: (UUID) -> String? = { _ in "Untitled SQL 2" }
        #expect(DatabaseWorkspaceView.focus(for: .connection, queryTitle: title) == nil)
        #expect(DatabaseWorkspaceView.focus(for: .database("common_vision"), queryTitle: title) == "common_vision")
        #expect(DatabaseWorkspaceView.focus(for: .table(database: "common_vision", table: "articles"), queryTitle: title)
                == "common_vision › articles")
        #expect(DatabaseWorkspaceView.focus(for: .query(id: UUID()), queryTitle: title) == "Untitled SQL 2")
        #expect(DatabaseWorkspaceView.focus(for: .query(id: UUID()), queryTitle: { _ in nil }) == "SQL")
    }

    @Test("Connected, the subtitle carries the focus after the engine; other states say the state")
    func subtitles() {
        #expect(GlassDatabaseCapability.subtitle(engine: .mysql, state: .connected, focus: "common_vision › articles")
                == "MySQL · common_vision › articles")
        #expect(GlassDatabaseCapability.subtitle(engine: .mysql, state: .connected, focus: nil) == "MySQL")
        #expect(GlassDatabaseCapability.subtitle(engine: .mysql, state: .disconnected, focus: "common_vision")
                == "MySQL · Disconnected", "a focus means nothing on a session that is not connected")
    }

    @Test("The row Active gets carries the session's focus")
    func rowCarriesFocus() {
        let runtime = GlassDatabaseRuntime(layers: GlassLayerStore())
        let capability = GlassDatabaseCapability(runtime: runtime)
        let session = DatabaseSession(connectionConfig: DatabaseConnectionConfig(name: "MySQL on oscar"))
        session.state = .connected
        session.workspaceFocus = "common_vision › articles"
        runtime.sessionManager.sessions[UUID()] = session
        let row = capability.openSessions().first
        #expect(row?.title == "MySQL on oscar")
        #expect(row?.subtitle == "MySQL · common_vision › articles")
    }
}
