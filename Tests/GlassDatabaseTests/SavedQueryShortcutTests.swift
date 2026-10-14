//
//  SavedQueryShortcutTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  D72's B-F48 tail: Siri and Shortcuts open a saved query in a new SQL tab on its database — never
//  run, and never with its SQL handed to the system. What must hold: only queries whose database is
//  still saved are offered; one that cannot be opened says why; a live database's workspace comes
//  forward, else the shell is asked to connect; and a query whose connection never came does not
//  turn up in a workspace opened much later.
//

import Foundation
import Testing
import GlassLayers
@testable import GlassDatabase

@Suite("Saved queries for Shortcuts and Siri")
@MainActor
struct SavedQueryShortcutTests {
    private func runtime() -> (GlassDatabaseRuntime, DatabaseConnectionConfig) {
        let defaults = UserDefaults.forTest(suiteName: "database.saved-queries.\(UUID().uuidString)")!
        let runtime = GlassDatabaseRuntime(layers: GlassLayerStore(defaults: defaults), settingsDefaults: defaults)
        let orders = DatabaseConnectionConfig(name: "Orders")
        runtime.connectionManager.connections = [orders]
        runtime.settingsManager.loadIfNeeded()
        return (runtime, orders)
    }

    @Test("only queries whose database is still saved are offered, by name, without their SQL")
    func entries() {
        let (runtime, orders) = runtime()
        let late = SavedQuery(name: "Late orders", sql: "SELECT * FROM orders WHERE late", connectionID: orders.id)
        runtime.settingsManager.savedQueries = [
            late,
            SavedQuery(name: "Unattached", sql: "SELECT 1"),
            SavedQuery(name: "Gone", sql: "SELECT 2", connectionID: UUID()),
        ]
        #expect(runtime.savedQueryEntries == [GlassDatabaseSavedQueryEntry(id: late.id, name: "Late orders",
                                                                            connectionID: orders.id)])
    }

    @Test("not connected: the shell is asked to connect, and the query waits for the workspace")
    func connectsFirst() {
        let (runtime, orders) = runtime()
        let late = SavedQuery(name: "Late orders", sql: "SELECT * FROM orders WHERE late", connectionID: orders.id)
        runtime.settingsManager.savedQueries = [late]

        #expect(runtime.openSavedQuery(late.id) == orders.id)
        #expect(runtime.takeRequests().isEmpty)
        let waiting = runtime.sessionManager.takePendingQueries(for: orders.id)
        #expect(waiting.map(\.sql) == [late.sql])
        #expect(waiting.map(\.name) == ["Late orders"])
        #expect(runtime.sessionManager.takePendingQueries(for: orders.id).isEmpty, "taken twice")
        #expect(runtime.settingsManager.savedQueries.first?.useCount == 1)
    }

    @Test("connected: the live workspace comes forward with the query; nothing connects twice")
    func liveWorkspace() {
        let (runtime, orders) = runtime()
        let late = SavedQuery(name: "Late orders", sql: "SELECT 1", connectionID: orders.id)
        runtime.settingsManager.savedQueries = [late]
        let sessionID = UUID()
        runtime.sessionManager.sessions[sessionID] = DatabaseSession(connectionConfig: orders)

        #expect(runtime.openSavedQuery(late.id) == nil)
        let requests = runtime.takeRequests()
        #expect(requests.count == 1)
        if case .openQueryEditor(let shown) = requests.first { #expect(shown == sessionID) }
        else { Issue.record("the live workspace was not brought forward") }
        #expect(runtime.sessionManager.takePendingQueries(for: orders.id).count == 1)
    }

    @Test("a query that is gone, or whose database is gone, says so and opens nothing")
    func failures() {
        let (runtime, _) = runtime()
        let orphan = SavedQuery(name: "Gone", sql: "SELECT 2", connectionID: UUID())
        runtime.settingsManager.savedQueries = [orphan]
        for id in [UUID(), orphan.id] {
            #expect(runtime.openSavedQuery(id) == nil)
            let requests = runtime.takeRequests()
            guard case .showFailure(let message) = requests.first else {
                Issue.record("nothing said why"); continue
            }
            #expect(!message.isEmpty)
        }
        #expect(runtime.sessionManager.pendingQueries.isEmpty)
    }

    @Test("a query whose connection never came does not turn up in a workspace opened later")
    func staleQueriesExpire() {
        let manager = DatabaseSessionManager(loadImmediately: false)
        let connection = UUID(), start = Date()
        manager.queueQuery(name: "Old", sql: "SELECT 1", for: connection, at: start)
        manager.queueQuery(name: "New", sql: "SELECT 2", for: connection,
                           at: start.addingTimeInterval(DatabaseSessionManager.PendingQuery.lifetime))
        let taken = manager.takePendingQueries(for: connection,
                                               at: start.addingTimeInterval(DatabaseSessionManager.PendingQuery.lifetime + 1))
        #expect(taken.map(\.name) == ["New"])
        #expect(manager.pendingQueries.isEmpty)
    }
}
