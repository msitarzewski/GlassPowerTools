//
//  GlassServiceRecords.swift
//  Glass Power Tools — GlassShell
//
//  One capability's records, kept on their service links (D26).
//
//  All three capabilities key a record by the shell's endpoint id — `EndpointID.rawValue` *is* the
//  record's own id, and was before D26 — so "read my whole list" and "write my whole list" is the
//  same code three times over. It is here once.
//
//  This is the only place that knows how to make a stored set match a wanted set. Each capability
//  keeps its own store type around it, because each has its own failure and rollback semantics
//  that are not shared and should not be.
//

import Foundation
import GlassConnectionKit

@MainActor
public struct GlassServiceRecords<Record: Codable> {
    private let store: any GlassServiceStore
    private let kind: HostServiceKind
    private let identify: (Record) -> EndpointID
    /// What this caller has been shown — the records `all()` last returned, and those it wrote
    /// since — or nil before it has read anything. Shared by copies of this value.
    private let shown = Shown()

    private final class Shown {
        var ids: Set<EndpointID>?
    }

    public init(store: any GlassServiceStore, kind: HostServiceKind,
                id identify: @escaping (Record) -> EndpointID) {
        self.store = store
        self.kind = kind
        self.identify = identify
    }

    /// Every readable record, keyed by its endpoint. Records this build cannot decode are skipped
    /// rather than fatal, matching the catalog backend's rule: one unreadable service must not take
    /// a whole library down with it.
    public func all() -> [EndpointID: Record] {
        let records = readable()
        shown.ids = Set(records.keys)
        return records
    }

    private func readable() -> [EndpointID: Record] {
        store.configurations(Record.self, ofKind: kind)
    }

    /// Whether anything of this kind is stored at all. Distinct from "the list is empty after
    /// decoding": a record that fails to decode still counts as something being there.
    public var isStoreEmpty: Bool { store.configurations(ofKind: kind).isEmpty }

    /// Whether the catalog has been read yet. A capability must not mistake "not read" for
    /// "nothing saved" — see `replaceAll(with:)`.
    public var isCatalogLoaded: Bool { store.isCatalogLoaded }

    /// Makes the stored set match `records`, leaving alone any stored record this build cannot read.
    ///
    /// Three rules, in this order and for reasons:
    ///
    /// - **Removals first.** A configuration left behind for a record that is gone is the orphan
    ///   D25 exists to prevent, and writing the survivors first would widen the window in which
    ///   both exist.
    /// - **Unchanged records are skipped, not rewritten.** Every write publishes, so rewriting a
    ///   record nobody edited churns the catalog for every other device on the account.
    /// - **Encode once per record**, compared as JSON values against what is stored, so "changed"
    ///   means the stored value differs rather than some type's idea of equality — or key order.
    /// - **Refused before the catalog has been read.** This reconcile deletes whatever is stored
    ///   and missing from `records`, so running it against a list built from an unread catalog
    ///   deletes everything the user has. It is the one call in D26 that can destroy data by doing
    ///   exactly what it was asked, which is why the guard lives here, at the door all three
    ///   capabilities go through, rather than in each of them.
    ///
    /// - Parameter preserving: stored records the caller could read but will not vouch for — the
    ///   desktop's records that fail its validation — which are neither deleted nor rewritten.
    public func replaceAll(with records: [Record], preserving: Set<EndpointID> = []) async throws {
        guard store.isCatalogLoaded else { throw GlassServiceRecordsError.catalogNotRead }
        let wanted = Dictionary(records.map { (identify($0), $0) }, uniquingKeysWith: { first, _ in first })
        let current = store.configurations(ofKind: kind)
        // **Only what this build can read can have been removed by the caller.** Every caller
        // builds `records` from `all()`, which skips a record it cannot decode — one written by a
        // newer build, with a field or an enum case this one does not know. Absent from the list
        // is not deleted by the user: it was never shown to them. Removing it here made every save,
        // favorite, "last connected" stamp and delete erase the newer build's records, and the
        // erasure synced to every device (2026-09-27). glassDT refused to write instead.
        let readable = Set(readable().keys)
        // **And only what the caller has been shown** (2026-10-12, B-X14). The terminal and the
        // database build `records` from a list read earlier; a record another device added since —
        // arrived through sync, not yet re-read — is missing from that list without anyone having
        // deleted it, and the next save here deleted it everywhere. A caller that has read nothing
        // through this value is taken at its word, as before.
        let known = shown.ids ?? readable

        for endpointID in current.keys
        where wanted[endpointID] == nil && readable.contains(endpointID) && !preserving.contains(endpointID) {
            guard known.contains(endpointID) else {
                GlassServiceStoreLog.logger.notice("Kept a \(kind.rawValue, privacy: .public) record (\(endpointID.rawValue.uuidString, privacy: .public)) that arrived after this device last read its list")
                continue
            }
            try await store.setConfiguration(nil, for: endpointID)
            shown.ids?.remove(endpointID)
        }
        let encoder = JSONEncoder()
        // Sorted, so the same record always encodes to the same bytes.
        encoder.outputFormatting = .sortedKeys
        for (endpointID, record) in wanted where !preserving.contains(endpointID) {
            let encoded = try encoder.encode(record)
            if let stored = current[endpointID], Self.sameJSON(stored, encoded) { continue }
            try await store.setConfiguration(encoded, for: endpointID)
        }
        shown.ids?.formUnion(wanted.keys)
    }

    /// Whether two encodings hold the same value. Bytes alone are not enough: `JSONEncoder` does
    /// not keep key order stable, even within one process, so an unchanged record could compare
    /// as changed, be rewritten and be published to every device for nothing (2026-09-27).
    static func sameJSON(_ lhs: Data, _ rhs: Data) -> Bool {
        if lhs == rhs { return true }
        guard let left = try? JSONSerialization.jsonObject(with: lhs, options: [.fragmentsAllowed]) as? NSObject,
              let right = try? JSONSerialization.jsonObject(with: rhs, options: [.fragmentsAllowed]) as? NSObject
        else { return false }
        return left.isEqual(right)
    }
}

public enum GlassServiceRecordsError: LocalizedError, Equatable {
    /// A write arrived before the catalog was read. Refusing is the point: the alternative is a
    /// reconcile against an empty list, which deletes every saved connection of that kind.
    case catalogNotRead

    public var errorDescription: String? {
        switch self {
        case .catalogNotRead:
            "The connection library has not finished loading. Nothing was changed; try again in a moment."
        }
    }
}
