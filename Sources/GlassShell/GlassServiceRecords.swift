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
        store.configurations(Record.self, ofKind: kind)
    }

    /// Whether anything of this kind is stored at all. Distinct from "the list is empty after
    /// decoding": a record that fails to decode still counts as something being there.
    public var isStoreEmpty: Bool { store.configurations(ofKind: kind).isEmpty }

    /// Makes the stored set match `records`.
    ///
    /// Three rules, in this order and for reasons:
    ///
    /// - **Removals first.** A configuration left behind for a record that is gone is the orphan
    ///   D25 exists to prevent, and writing the survivors first would widen the window in which
    ///   both exist.
    /// - **Unchanged records are skipped, not rewritten.** Every write publishes, so rewriting a
    ///   record nobody edited churns the catalog for every other device on the account.
    /// - **Encode once per record**, compared as bytes against what is stored, so "changed" means
    ///   the stored bytes differ rather than some type's idea of equality.
    public func replaceAll(with records: [Record]) async throws {
        let wanted = Dictionary(records.map { (identify($0), $0) }, uniquingKeysWith: { first, _ in first })
        let current = store.configurations(ofKind: kind)

        for endpointID in current.keys where wanted[endpointID] == nil {
            try await store.setConfiguration(nil, for: endpointID)
        }
        for (endpointID, record) in wanted {
            let encoded = try JSONEncoder().encode(record)
            guard current[endpointID] != encoded else { continue }
            try await store.setConfiguration(encoded, for: endpointID)
        }
    }
}
