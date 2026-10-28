//
//  GlassServiceRecordsChangedFromTests.swift
//  Glass Power Tools — GlassShellTests
//
//  Given the list it started from, a save writes only what the caller changed (2026-10-22). The
//  whole-list save put back every copy the caller held: older than another device's edit, without
//  a field a newer build added, or missing a record that arrived since. a machine's MySQL lost its
//  Database address to it.
//

import Foundation
import Testing
import GlassConnectionKit
@testable import GlassShell

@MainActor
@Suite("A save writes only what the caller changed")
struct GlassServiceRecordsChangedFromTests {

    private struct Record: Codable, Equatable {
        var id: UUID
        var name: String
    }

    private func records(_ store: GlassInMemoryServiceStore) -> GlassServiceRecords<Record> {
        GlassServiceRecords(store: store, kind: .rdp) { EndpointID(rawValue: $0.id) }
    }

    private func put(_ json: String, _ id: UUID, in store: GlassInMemoryServiceStore) {
        store.setConfiguration(Data(json.utf8), kind: .rdp, for: EndpointID(rawValue: id))
    }

    private func object(_ store: GlassInMemoryServiceStore, _ id: UUID) -> [String: String]? {
        store.configuration(for: EndpointID(rawValue: id))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
    }

    @Test func aRecordNotChangedKeepsAFieldThisBuildDoesNotKnow() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .rdp)
        let kept = UUID(), edited = UUID()
        put(#"{"id":"\#(kept.uuidString)","name":"alpha","address":"198.51.100.7"}"#, kept, in: store)
        put(#"{"id":"\#(edited.uuidString)","name":"bravo"}"#, edited, in: store)
        let base = Array(records(store).all().values)

        let changed = base.map { $0.id == edited ? Record(id: edited, name: "bravo, renamed") : $0 }
        try await records(store).replaceAll(with: changed, changedFrom: base)

        #expect(object(store, kept)?["address"] == "198.51.100.7", "re-encoded by a build without the field, and written")
        #expect(object(store, edited)?["name"] == "bravo, renamed")
    }

    @Test func aNewerStoredCopyOfARecordNotChangedIsKept() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .rdp)
        let alpha = Record(id: UUID(), name: "alpha"), bravo = Record(id: UUID(), name: "bravo")
        try await records(store).replaceAll(with: [alpha, bravo])
        let base = [alpha, bravo]
        put(#"{"id":"\#(alpha.id.uuidString)","name":"alpha, edited elsewhere"}"#, alpha.id, in: store)

        try await records(store).replaceAll(with: [alpha, Record(id: bravo.id, name: "bravo, renamed")], changedFrom: base)

        #expect(object(store, alpha.id)?["name"] == "alpha, edited elsewhere")
        #expect(object(store, bravo.id)?["name"] == "bravo, renamed")
    }

    @Test func aRecordArrivingSinceIsKeptAndOneRemovedHereIsRemoved() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .rdp)
        let alpha = Record(id: UUID(), name: "alpha"), bravo = Record(id: UUID(), name: "bravo")
        try await records(store).replaceAll(with: [alpha, bravo])
        let base = [alpha, bravo]
        let arrived = UUID()
        put(#"{"id":"\#(arrived.uuidString)","name":"charlie"}"#, arrived, in: store)

        try await records(store).replaceAll(with: [alpha], changedFrom: base)

        #expect(object(store, arrived)?["name"] == "charlie", "never shown here, so not deleted here")
        #expect(object(store, bravo.id) == nil, "removed here, so removed")
        #expect(object(store, alpha.id)?["name"] == "alpha")
    }
}
