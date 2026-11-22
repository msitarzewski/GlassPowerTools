//
//  GlassCloudKitLayoutBackend.swift
//  Glass Power Tools — GlassShell
//
//  The CloudKit half of the shared layout (`GlassLayout`), beside the library's (`GlassCloudKitCatalogBackend`) in
//  the same private database: a zone of its own, `GlassLayout`, and one record type, `LayoutItem`, carrying the
//  encoded window or tab and its `updatedAt`, as `Host` carries an encoded profile. One record type for both kinds,
//  so the production schema is one type to deploy, and the record's own schema versions it (D19's reasoning).
//
//  **The zone is read whole each time**, as the library's is: the merge publishes what the account lacks, and only a
//  complete read says what that is. A layout is tens of records.
//

import Foundation
import os

/// What the layout's sync needs from a remote store. A protocol so the rules are testable without iCloud.
public protocol GlassLayoutSyncBackend: Sendable {
    /// Every record in the account, every page of it. A record this build can't read is left out.
    func fetchAll() async throws -> [GlassLayoutItem]
    /// Saves records, replacing what the account holds under their names.
    func save(_ items: [GlassLayoutItem]) async throws
    /// Removes records from the account for good: tombstones every device has long since heard.
    func remove(_ items: [GlassLayoutItem]) async throws
    /// Asks to be told when the layout changes on another device. Optional.
    func subscribeToChanges() async throws
}

public extension GlassLayoutSyncBackend {
    func subscribeToChanges() async throws {}
}

#if canImport(CloudKit)
import CloudKit

public struct GlassCloudKitLayoutBackend: GlassLayoutSyncBackend {
    static let recordType = "LayoutItem"
    /// The encoded `GlassLayoutItem`.
    static let itemKey = "item"
    static let updatedAtKey = "updatedAt"
    static let subscriptionID = "glass-layout-changes"
    static let zoneName = "GlassLayout"

    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID

    public init(containerIdentifier: String = GlassCloudKitCatalogBackend.containerIdentifier) {
        database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private func ensureZone() async throws {
        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        } catch let error as CKError where error.code == .serverRecordChanged || error.code == .zoneNotFound {
            return
        }
    }

    public func fetchAll() async throws -> [GlassLayoutItem] {
        try await ensureZone()
        var cursor: CKServerChangeToken?
        var items: [GlassLayoutItem] = []
        var pages = 0
        repeat {
            let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: cursor)
            for modification in result.modificationResultsByID.values {
                guard let record = try? modification.get().record,
                      let data = record[Self.itemKey] as? Data else { continue }
                guard let item = try? Self.decoder.decode(GlassLayoutItem.self, from: data), item.isReadable else {
                    Logger.layoutSync.notice("Skipped a layout record this build can't read")
                    continue
                }
                items.append(item)
            }
            cursor = result.changeToken
            pages += 1
            guard result.moreComing, pages < 1_000 else { break }
        } while true
        return items
    }

    public func save(_ items: [GlassLayoutItem]) async throws {
        guard !items.isEmpty else { return }
        try await ensureZone()
        let records: [CKRecord] = try items.map { item in
            let record = CKRecord(recordType: Self.recordType,
                                  recordID: CKRecord.ID(recordName: item.recordName, zoneID: zoneID))
            record[Self.itemKey] = try Self.encoder.encode(item) as CKRecordValue
            record[Self.updatedAtKey] = item.updatedAt as CKRecordValue
            return record
        }
        // `.changedKeys`: the merge has already decided these stand, as the library's save does.
        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys,
                                                      atomically: false)
        let refused = result.saveResults.compactMap { _, outcome -> (any Error)? in
            if case .failure(let error) = outcome { return error } else { return nil }
        }
        if let first = refused.first {
            Logger.layoutSync.error(
                "Layout: \(refused.count, privacy: .public) of \(records.count, privacy: .public) record(s) refused: \(String(describing: first), privacy: .public)")
            throw first
        }
    }

    public func remove(_ items: [GlassLayoutItem]) async throws {
        guard !items.isEmpty else { return }
        let ids = items.map { CKRecord.ID(recordName: $0.recordName, zoneID: zoneID) }
        _ = try await database.modifyRecords(saving: [], deleting: ids, savePolicy: .changedKeys, atomically: false)
    }

    public func subscribeToChanges() async throws {
        try await ensureZone()
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: Self.subscriptionID)
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        do {
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        } catch let error as CKError where error.code == .serverRecordChanged {
            return
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
#endif

extension Logger {
    static let layoutSync = Logger(subsystem: "com.glasspowertools", category: "layout-sync")
}
