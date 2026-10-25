//
//  ServerRecordsFromElsewhereTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A save on this device writes what this device changed, and nothing it merely still holds
//  (2026-10-22). The terminal saved its whole list, as the database did when a machine's MySQL lost its
//  Database address: a copy older than another device's edit went back over it, and a server
//  added on another device since this list was read was deleted by the next "last connected".
//

import Foundation
import Testing
import GlassConnectionKit
import GlassShell
import GlasSecretStore
@testable import GlassTerminal

@MainActor
@Suite("Servers changed elsewhere survive a save here")
struct ServerRecordsFromElsewhereTests {

    private func manager(_ store: GlassInMemoryServiceStore) -> ServerManager {
        let manager = ServerManager(loadImmediately: false,
                                    defaults: UserDefaults.forTest(suiteName: "elsewhere.\(UUID().uuidString)")!,
                                    passwordStore: ServerPasswordStore(retrieve: { _ in throw SecretStoreError.notFound },
                                                                       save: { _, _ in }, delete: { _ in }))
        manager.attach(store: .catalog(store))
        manager.reloadFromStore()
        return manager
    }

    private func put(_ server: ServerConfiguration, in store: GlassInMemoryServiceStore) throws {
        store.setConfiguration(try JSONEncoder().encode(server), kind: .ssh, for: EndpointID(rawValue: server.id))
    }

    private func stored(_ store: GlassInMemoryServiceStore, _ id: UUID) throws -> ServerConfiguration? {
        try store.configuration(for: EndpointID(rawValue: id)).map { try JSONDecoder().decode(ServerConfiguration.self, from: $0) }
    }

    @Test("A newer copy from another device is not overwritten by saving another server")
    func newerCopySurvives() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .ssh)
        let web = ServerConfiguration(name: "Web", host: "web.example", username: "casey")
        let staging = ServerConfiguration(name: "Staging", host: "staging.example", username: "casey")
        try put(web, in: store)
        try put(staging, in: store)
        let manager = manager(store)

        var renamed = web
        renamed.username = "deploy"   // edited on another device, delivered by sync
        try put(renamed, in: store)

        await manager.updateLastConnected(staging.id)

        #expect(try stored(store, web.id)?.username == "deploy", "an older copy went back over the newer one")
        #expect(try stored(store, staging.id)?.lastConnected != nil, "the change asked for was saved")
    }

    @Test("A server added on another device after this list was read is not deleted by a save here")
    func arrivalSurvives() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .ssh)
        let staging = ServerConfiguration(name: "Staging", host: "staging.example", username: "casey")
        try put(staging, in: store)
        let manager = manager(store)

        let arrived = ServerConfiguration(name: "Build", host: "build.example", username: "casey")
        try put(arrived, in: store)

        await manager.updateLastConnected(staging.id)

        #expect(try stored(store, arrived.id) != nil, "a save made from an older list deleted it")
        #expect(try stored(store, staging.id)?.lastConnected != nil)
    }

    @Test("Deleting a server here still deletes it")
    func deleteStillDeletes() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .ssh)
        let staging = ServerConfiguration(name: "Staging", host: "staging.example", username: "casey")
        let web = ServerConfiguration(name: "Web", host: "web.example", username: "casey")
        try put(staging, in: store)
        try put(web, in: store)
        let manager = manager(store)

        try await manager.deleteServer(web)

        #expect(try stored(store, web.id) == nil)
        #expect(try stored(store, staging.id) != nil)
    }
}
