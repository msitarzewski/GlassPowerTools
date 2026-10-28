//
//  DatabaseRecordsFromElsewhereTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  A save on this device writes what this device changed, and nothing it merely still holds
//  (2026-10-22). A machine's MySQL lost its Database address: the service was saved with it, and later
//  stood without it, though the owner never cleared it. Every save here wrote the whole list it
//  held, so a copy from before the address — an older list on one device, or a build that predates
//  the field — went back over the newer one the next time that device stamped "last connected" on
//  another database.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassShell
@testable import GlassDatabase

@MainActor
@Suite("Database records changed elsewhere survive a save here")
struct DatabaseRecordsFromElsewhereTests {

    private func stored(_ store: GlassInMemoryServiceStore, _ id: UUID) throws -> DatabaseConnectionConfig? {
        try store.configuration(for: EndpointID(rawValue: id)).map { try JSONDecoder().decode(DatabaseConnectionConfig.self, from: $0) }
    }

    private func put(_ config: DatabaseConnectionConfig, in store: GlassInMemoryServiceStore) throws {
        store.setConfiguration(try JSONEncoder().encode(config), kind: .database, for: EndpointID(rawValue: config.id))
    }

    @Test("A newer copy from another device is not overwritten by saving another database")
    func newerCopySurvives() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .database)
        let web = DatabaseConnectionConfig(name: "MySQL on Web", engine: .mysql, host: "203.0.113.5", port: 13306,
                                           username: "reader", usesHostTunnel: true)
        let staging = DatabaseConnectionConfig(name: "MySQL on Staging", engine: .mysql, host: "203.0.113.6",
                                               port: 13306, username: "reader", usesHostTunnel: true)
        try put(web, in: store)
        try put(staging, in: store)
        let manager = ConnectionManager(loadImmediately: false, persistenceStore: .catalog(store))
        manager.load()

        // Another device gives Web its address; it arrives here through sync.
        var addressed = web
        addressed.tunnelTargetHost = "198.51.100.7"
        try put(addressed, in: store)

        await manager.updateLastConnected(staging.id)

        #expect(try stored(store, web.id)?.tunnelTargetHost == "198.51.100.7", "an older copy went back over the newer one")
        #expect(try stored(store, staging.id)?.lastConnected != nil)
    }

    @Test("A field this build does not know is kept on records it did not change")
    func unknownFieldSurvives() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .database)
        let web = DatabaseConnectionConfig(name: "MySQL on Web", engine: .mysql, host: "203.0.113.5", port: 13306,
                                           username: "reader", usesHostTunnel: true)
        let staging = DatabaseConnectionConfig(name: "MySQL on Staging", engine: .mysql, host: "203.0.113.6",
                                               port: 13306, username: "reader")
        // Written by a newer build, with a field this one has never heard of.
        var newer = try JSONSerialization.jsonObject(with: JSONEncoder().encode(web)) as! [String: Any]
        newer["fieldFromTheFuture"] = "kept"
        store.setConfiguration(try JSONSerialization.data(withJSONObject: newer), kind: .database,
                               for: EndpointID(rawValue: web.id))
        try put(staging, in: store)
        let manager = ConnectionManager(loadImmediately: false, persistenceStore: .catalog(store))
        manager.load()

        await manager.updateLastConnected(staging.id)

        let raw = try #require(store.configuration(for: EndpointID(rawValue: web.id)))
        let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        #expect(object?["fieldFromTheFuture"] as? String == "kept", "a save of another record dropped it")
    }

    @Test("A database added on another device after this list was read is not deleted by a save here")
    func arrivalSurvives() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .database)
        let staging = DatabaseConnectionConfig(name: "MySQL on Staging", engine: .mysql, host: "203.0.113.6",
                                               port: 13306, username: "reader")
        try put(staging, in: store)
        let manager = ConnectionManager(loadImmediately: false, persistenceStore: .catalog(store))
        manager.load()

        let arrived = DatabaseConnectionConfig(name: "Orders", engine: .postgresql, host: "203.0.113.7",
                                               port: 5432, username: "reader")
        try put(arrived, in: store)

        await manager.updateLastConnected(staging.id)

        #expect(try stored(store, arrived.id) != nil, "a save made from an older list deleted it")
    }
}
