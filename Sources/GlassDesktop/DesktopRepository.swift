//
//  DesktopRepository.swift
//  Glass Power Tools — GlassDesktop
//
//  D26: the catalog is the one store for a connection. Each saved desktop lives on its own service
//  link; `connections.json` is gone, and so is everything that existed to manage it.
//
//  **What this replaced, and why none of it came across.** The previous version was a file-backed
//  actor with `flock`, an atomic rename, a size cap, a schema version — and a publication journal:
//  `pendingHostRemovals` and `pendingHostPublications`, which recorded what still had to be told to
//  a *separate* app's catalog so a crash could not lose it. That machinery exists because glassDT
//  was one of three processes that had to agree about one model. There is one process now, and the
//  catalog it writes to is the model, so there is nothing left to journal. Confirmed before
//  deleting: nothing outside this file ever read those queues.
//
//  The reconcile is `GlassServiceRecords`, shared with the terminal and the database, because
//  "make the stored set match this list" is the same problem for all three.
//

import Foundation
import GlassConnectionKit
import GlassShell

@MainActor
public struct DesktopRepository {
    private let records: GlassServiceRecords<DesktopConnection>

    public init(store: any GlassServiceStore) {
        records = GlassServiceRecords(store: store, kind: .rdp, id: \.id)
    }

    /// Whether the catalog has been read. Until it has, `load()` would answer "no saved desktops"
    /// for a library that is merely not open yet.
    public var isCatalogLoaded: Bool { records.isCatalogLoaded }

    /// Every saved desktop, ordered by name then id so the list is stable across launches — the
    /// catalog keys by endpoint id and has no insertion order to give back.
    ///
    /// `validated()` runs on the way out as well as in: it is what canonicalises a VNC record
    /// (`DesktopConnection.swift:131-137`), and a record written by an older build has to be
    /// brought to the same shape as one written now.
    public func load() throws -> [DesktopConnection] {
        records.all().values
            .compactMap { try? $0.validated() }
            .sorted { ($0.name, $0.id.rawValue.uuidString) < ($1.name, $1.id.rawValue.uuidString) }
    }

    /// One saved desktop, straight out of the catalog.
    ///
    /// The catalog is the record (D26), so this asks it rather than asking whoever happens to have
    /// read it. That is the difference between "this service has nothing behind it" and "nobody has
    /// looked yet", and the second must never be shown as the first — the user acts on what the app
    /// says, and on 2026-09-17 what it said was wrong enough that they deleted a working service.
    public func record(for id: EndpointID) -> DesktopConnection? {
        try? records.all()[id]?.validated()
    }

    public func save(_ connection: DesktopConnection) async throws -> [DesktopConnection] {
        try await persist(connection, expected: nil, compare: false)
    }

    /// Nil expects a new identity; a prior value must still match what is stored, so a concurrent
    /// edit is reported rather than overwritten.
    public func save(_ connection: DesktopConnection,
                     replacing previous: DesktopConnection?) async throws -> [DesktopConnection] {
        try await persist(connection, expected: previous, compare: true)
    }

    private func persist(_ connection: DesktopConnection, expected: DesktopConnection?,
                         compare: Bool) async throws -> [DesktopConnection] {
        let value = try connection.validated()
        var current = try load()
        let index = current.firstIndex { $0.id == value.id }
        if compare, index.map({ current[$0] }) != expected { throw DesktopError.connectionChanged }
        if let index { current[index] = value } else { current.append(value) }
        try await records.replaceAll(with: current)
        return try load()
    }

    public func delete(_ id: EndpointID) async throws -> [DesktopConnection] {
        let remaining = try load().filter { $0.id != id }
        try await records.replaceAll(with: remaining)
        return try load()
    }

    /// Stamps "last connected". `expectedConnection` guards the same way `save(replacing:)` does:
    /// a record edited since the connection began must not have a timestamp written over it.
    public func recordConnection(_ id: EndpointID, at date: Date = Date(),
                                 expectedConnection: DesktopConnection? = nil) async throws -> [DesktopConnection] {
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw DesktopError.invalidDocument }
        let expected = try expectedConnection?.validated()
        var current = try load()
        guard let index = current.firstIndex(where: { $0.id == id }) else {
            throw DesktopError.missingConnection
        }
        let existing = current[index]
        if let expected {
            guard expected.id == id, existing.host == expected.host, existing.port == expected.port,
                  existing.authentication == expected.authentication,
                  existing.certificateSHA256 == expected.certificateSHA256 else {
                throw DesktopError.connectionChanged
            }
        }
        // `max` because a reconnect that finished out of order must not move the stamp backwards.
        current[index].lastConnectedAt = max(existing.lastConnectedAt ?? date, date)
        try await records.replaceAll(with: current)
        return try load()
    }
}
