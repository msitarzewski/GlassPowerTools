//
//  GlassServiceRecordsUnreadableTests.swift
//  Glass Power Tools — GlassShellTests
//
//  A record this build cannot read is not a record the user deleted.
//
//  Found 2026-09-27 comparing glassDT with the merged desktop: `replaceAll(with:)` made the stored
//  set match the list it was given, and every caller built that list from `all()`, which skips what
//  it cannot decode. So any save, favorite, "last connected" stamp or delete — in the terminal, the
//  database and the desktop alike — deleted every record written by a newer build (a new field, a
//  new enum case), and the deletion synced to every other device. glassDT refused to write instead.
//

import Foundation
import Testing
import GlassConnectionKit
@testable import GlassShell

@MainActor
@Suite("Records this build cannot read survive a write")
struct GlassServiceRecordsUnreadableTests {

    private struct Record: Codable, Equatable {
        var id: UUID
        var name: String
    }

    private func records(_ store: GlassInMemoryServiceStore) -> GlassServiceRecords<Record> {
        GlassServiceRecords(store: store, kind: .rdp) { EndpointID(rawValue: $0.id) }
    }

    @Test func anUnreadableRecordIsNotDeletedBySavingAnother() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .rdp)
        let newer = EndpointID()
        // Written by a build that knows a shape this one does not.
        store.setConfiguration(Data(#"{"future":true}"#.utf8), kind: .rdp, for: newer)
        let mine = Record(id: UUID(), name: "alpha")

        try await records(store).replaceAll(with: records(store).all().values + [mine])

        #expect(store.configuration(for: newer) == Data(#"{"future":true}"#.utf8))
        #expect(records(store).all()[EndpointID(rawValue: mine.id)] == mine)
    }

    /// B-X14: the terminal and the database write from a list read earlier. A record another
    /// device added after that read must survive a save made from it.
    @Test func aRecordArrivingAfterTheLastReadIsNotDeletedByAStaleList() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .rdp)
        let records = records(store)
        let mine = Record(id: UUID(), name: "alpha")
        try await records.replaceAll(with: [mine])
        let list = Array(records.all().values)       // what this device's list was built from

        let theirs = Record(id: UUID(), name: "bravo") // arrives through sync, not yet re-read
        store.setConfiguration(try JSONEncoder().encode(theirs), kind: .rdp, for: EndpointID(rawValue: theirs.id))

        var edited = list[0]
        edited.name = "alpha, renamed"
        try await records.replaceAll(with: [edited])

        #expect(records.all()[EndpointID(rawValue: theirs.id)] == theirs, "a stale list deleted a record it never showed")
        #expect(records.all()[EndpointID(rawValue: mine.id)] == edited)

        // Once read, it is the caller's to delete.
        try await records.replaceAll(with: [edited])
        #expect(records.all()[EndpointID(rawValue: theirs.id)] == nil)
    }

    @Test func deletingARecordStillDeletesIt() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .rdp)
        let gone = Record(id: UUID(), name: "bravo")
        try await records(store).replaceAll(with: [gone])

        try await records(store).replaceAll(with: [])

        #expect(store.configuration(for: EndpointID(rawValue: gone.id)) == nil)
    }

    /// Same value, different key order: not a change, so not a write, so not a publish.
    @Test func anUnchangedRecordInAnotherKeyOrderIsNotRewritten() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .rdp)
        let id = UUID()
        let reordered = Data(#"{"name":"alpha","id":"\#(id.uuidString)"}"#.utf8)
        store.setConfiguration(reordered, kind: .rdp, for: EndpointID(rawValue: id))

        try await records(store).replaceAll(with: [Record(id: id, name: "alpha")])

        #expect(store.configuration(for: EndpointID(rawValue: id)) == reordered)
    }
}
