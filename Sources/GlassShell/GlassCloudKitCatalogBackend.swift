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
import GlassConnectionKit
import os

#if canImport(CloudKit)
import CloudKit

/// The user's private CloudKit database, as the catalog sync sees it.
public struct GlassCloudKitCatalogBackend: GlassCatalogSyncBackend {
    public static let containerIdentifier = "iCloud.com.glasspowertools"
    static let recordType = "Host"
    /// The encoded `HostProfile`.
    static let payloadKey = "profile"
    /// Mirrored out of the payload so the merge can order records without decoding them.
    static let updatedAtKey = "updatedAt"

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

        let previous: CKServerChangeToken? = token.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: previous)

        var profiles: [HostProfile] = []
        for modification in result.modificationResultsByID.values {
            guard let record = try? modification.get().record,
                  let data = record[Self.payloadKey] as? Data else { continue }
            // A record this build cannot decode is skipped, not fatal: a newer device may have
            // written a schema this one does not know, and stalling the whole sync over one host
            // would be worse than carrying on without it.
            guard let profile = try? JSONDecoder().decode(HostProfile.self, from: data) else {
                Logger.catalogSync.error("Skipped a host record this build could not decode")
                continue
            }
            profiles.append(profile)
        }

        let nextToken = try? NSKeyedArchiver.archivedData(withRootObject: result.changeToken,
                                                          requiringSecureCoding: true)
        return (profiles, nextToken)
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
        _ = try await database.modifyRecords(saving: records, deleting: [],
                                             savePolicy: .changedKeys, atomically: false)
    }
}

private extension Logger {
    static let catalogSync = Logger(subsystem: "com.glasspowertools", category: "catalog-sync")
}
#endif
