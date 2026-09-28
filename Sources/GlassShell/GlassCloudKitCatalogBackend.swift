//
//  GlassCloudKitCatalogBackend.swift
//  Glass Power Tools — GlassShell
//
//  The CloudKit half of D19. Everything with a rule in it lives in `GlassCatalogSync`; this file
//  only moves records in and out of the user's private database.
//
//  **The whole profile travels as one encoded field**, not as a CloudKit schema mirroring
//  `HostProfile`'s properties. That is deliberate:
//
//  * A CloudKit record type is a **schema commitment** — fields are hard to change once real data
//    exists in a production container. `HostProfile` already versions itself (`schemaVersion`) and
//    already decodes records written by apps that did not know about newer fields, which is how the
//    three source apps shared one catalog file. Mirroring the fields would put a second, weaker
//    versioning scheme next to a working one.
//  * Nothing here is ever queried by field. Sync fetches changes by token and merges by
//    `updatedAt`, both of which are carried alongside.
//
//  `updatedAt` is stored as its own field regardless, because a change token tells you *that* a
//  record changed and the merge needs to know *when* — and reading it without decoding the payload
//  keeps a malformed record from being able to stall a sync.
//

import Foundation
import GlassLayers
import GlassConnectionKit
import os

#if canImport(CloudKit)
import CloudKit

/// The user's private CloudKit database, as the catalog sync sees it.
public struct GlassCloudKitCatalogBackend: GlassCatalogSyncBackend {
    public static let containerIdentifier = GlassAppIdentity.cloudKitContainer
    static let recordType = "Host"
    /// The encoded `HostProfile`.
    static let payloadKey = "profile"
    /// Mirrored out of the payload so the merge can order records without decoding them.
    static let updatedAtKey = "updatedAt"
    /// Stable, so re-registering on every launch replaces rather than accumulates.
    static let subscriptionID = "glass-host-catalog-changes"

    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID

    public init(containerIdentifier: String = GlassCloudKitCatalogBackend.containerIdentifier) {
        let container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        // A named zone rather than the default one: only a custom zone supports fetching changes by
        // token, which is what keeps a sync proportional to what changed rather than to the size of
        // the library.
        zoneID = CKRecordZone.ID(zoneName: "GlassHostCatalog", ownerName: CKCurrentUserDefaultName)
    }

    /// Creates the zone if it is not there. Safe to call repeatedly; an existing zone is not an
    /// error worth surfacing.
    private func ensureZone() async throws {
        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)],
                                                     deleting: [])
        } catch let error as CKError where error.code == .serverRecordChanged
                                        || error.code == .zoneNotFound {
            // `serverRecordChanged` here means someone else created it first, which is fine.
            return
        }
    }

    public func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?) {
        try await ensureZone()

        var cursor: CKServerChangeToken? = token.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        var profiles: [HostProfile] = []
        // **Every page.** CloudKit answers in batches and says `moreComing`; reading only the
        // first returned part of the account, and the merge then published this device's copies
        // of everything missing from that part over the account's own (2026-09-27).
        var pages = 0
        repeat {
            let result: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                         deletions: [CKDatabase.RecordZoneChange.Deletion],
                         changeToken: CKServerChangeToken, moreComing: Bool)
            do {
                result = try await database.recordZoneChanges(inZoneWith: zoneID, since: cursor)
            } catch let error as CKError where error.code == .changeTokenExpired && cursor != nil {
                // An expired token is not a failure: start again from the beginning.
                cursor = nil
                profiles.removeAll()
                continue
            }
            for modification in result.modificationResultsByID.values {
                guard let record = try? modification.get().record,
                      let data = record[Self.payloadKey] as? Data else { continue }
                // A record this build cannot decode is skipped, not fatal: a newer device may have
                // written a schema this one does not know, and stalling the whole sync over one
                // host would be worse than carrying on without it.
                guard let profile = try? JSONDecoder().decode(HostProfile.self, from: data) else {
                    Logger.catalogSync.error("Skipped a host record this build could not decode")
                    continue
                }
                profiles.append(profile)
            }
            cursor = result.changeToken
            pages += 1
            guard result.moreComing, pages < 1_000 else { break }
        } while true

        let nextToken = cursor.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        return (profiles, nextToken)
    }

    /// Registers for silent pushes when anything in the zone changes, so a second device learns
    /// about an edit while it is open rather than at its next foreground.
    ///
    /// `shouldSendContentAvailable` makes it a *silent* push: no alert, no badge, no sound, and no
    /// user permission prompt — the app is woken to sync and nothing is shown. The subscription is
    /// idempotent; a repeated save of the same id is not an error worth surfacing, which is why
    /// `.serverRecordChanged` is swallowed the way `ensureZone` swallows it.
    ///
    /// **Silent push is best-effort by design.** The system may delay or drop it when the device is
    /// busy, low on power, or the app has been backgrounded a long time. That is why this augments
    /// the sync on foreground rather than replacing it: if the push never lands, the next
    /// foreground still reconciles.
    public func subscribeToChanges() async throws {
        try await ensureZone()
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: Self.subscriptionID)
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        do {
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Already registered by an earlier launch.
            return
        }
    }

    public func save(_ profiles: [HostProfile]) async throws {
        guard !profiles.isEmpty else { return }
        try await ensureZone()

        let records: [CKRecord] = try profiles.map { profile in
            let id = CKRecord.ID(recordName: profile.id.rawValue.uuidString.lowercased(), zoneID: zoneID)
            let record = CKRecord(recordType: Self.recordType, recordID: id)
            record[Self.payloadKey] = try JSONEncoder().encode(profile) as CKRecordValue
            record[Self.updatedAtKey] = profile.updatedAt as CKRecordValue
            return record
        }

        // `.changedKeys` rather than `.ifServerRecordUnchanged`: the merge has already decided this
        // device holds the newer version, so a save must not fail merely because the server has a
        // different one. Losing that argument here would mean re-running the merge to reach the
        // same answer.
        let result = try await database.modifyRecords(saving: records, deleting: [],
                                                      savePolicy: .changedKeys, atomically: false)
        // Non-atomic, so each record succeeds or fails on its own — and a failure was thrown
        // away here, leaving the device sure it had published (2026-09-27). One refused record is
        // now a failed sync, said in the status, rather than a silent gap on every other device.
        let refused = result.saveResults.compactMap { _, outcome -> (any Error)? in
            if case .failure(let error) = outcome { return error } else { return nil }
        }
        if let first = refused.first {
            Logger.catalogSync.error(
                "Sync: \(refused.count, privacy: .public) of \(records.count, privacy: .public) record(s) refused: \(String(describing: first), privacy: .public)")
            throw first
        }
    }
}

#endif
