//
//  ICloudWorkgroupsSync.swift
//  Glass Power Tools — GlassTerminal
//
//  Workgroups on every device (owner, 2026-10-08: "work on getting workgroups to sync on
//  icloud"). They were saved on the device only; now each one travels through the shell's iCloud
//  key-value sync beside the terminal's themes and preferences, under the same switch.
//
//  The newest change per workgroup wins, and a deletion is a change like any other, so removing
//  one on a device removes it everywhere. What stays on the device: when it was last opened (so
//  opening one sends nothing) and its per-device SSH substitutions.
//

import Foundation
import GlassShell

/// Each workgroup travels as its own JSON: the payload is read off the main actor, and a
/// workgroup's coding belongs to the main actor in this module. It is decoded, and checked like
/// any saved workgroup, when it is applied.
nonisolated struct ICloudWorkgroupsPayload: Codable, Equatable, Sendable {
    nonisolated struct Record: Codable, Equatable, Sendable {
        var id: UUID
        /// When the workgroup was last saved or deleted, here or elsewhere — the sync's clock.
        var changedAt: Date
        /// The workgroup as JSON; nil once deleted.
        var preset: Data?
    }

    static let maximumRecords = 512
    static let maximumRecordBytes = 32 * 1024
    var records: [Record]

    init(records: [Record] = []) { self.records = records }

    /// The later change; on a tie, the workgroup over its deletion, then the bytes, so two
    /// devices merging in either order agree.
    static func newer(_ a: Record, _ b: Record) -> Record {
        if a.changedAt != b.changedAt { return a.changedAt > b.changedAt ? a : b }
        if (a.preset == nil) != (b.preset == nil) { return a.preset != nil ? a : b }
        return (a.preset ?? Data()).lexicographicallyPrecedes(b.preset ?? Data()) ? a : b
    }
}

nonisolated extension ICloudWorkgroupsPayload: GlassSettingsSyncPayload {
    func validate() throws {
        guard records.count <= Self.maximumRecords else {
            throw GlassSettingsSyncError.invalidPayload("Too many workgroups to synchronize.")
        }
        var ids = Set<UUID>()
        for record in records {
            guard ids.insert(record.id).inserted else {
                throw GlassSettingsSyncError.invalidPayload("Workgroup identifiers must be unique.")
            }
            guard (record.preset?.count ?? 0) <= Self.maximumRecordBytes else {
                throw GlassSettingsSyncError.invalidPayload("A synchronized workgroup is too large.")
            }
        }
    }

    func converged(with other: ICloudWorkgroupsPayload) -> ICloudWorkgroupsPayload {
        var byID: [UUID: Record] = [:]
        for record in records + other.records {
            byID[record.id] = byID[record.id].map { Self.newer($0, record) } ?? record
        }
        return ICloudWorkgroupsPayload(records: byID.values.sorted { $0.id.uuidString < $1.id.uuidString })
    }
}

extension GlassSettingsSyncService where Payload == ICloudWorkgroupsPayload {
    static var workgroupsStoreKey: String { "terminal-workgroups-envelope-v1" }

    /// Labelled differently from the designated initializer so this forwards to it.
    convenience init(workgroupsStore store: any GlassSettingsKeyValueStore, writerID: UUID = UUID()) {
        self.init(store: store, writerID: writerID, storeKey: Self.workgroupsStoreKey)
    }
}
