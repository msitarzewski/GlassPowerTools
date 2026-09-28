//
//  GlassCatalogSync.swift
//  Glass Power Tools — GlassShell
//
//  Stage 3.5 (D19): the host library on every device the user owns.
//
//  D18 made the *credentials* travel, which is half of the promise — a password that syncs is no
//  use while the record naming the machine stays on this device's App Group. This is the other
//  half: hosts and their services, in CloudKit's private database.
//
//  **Why CloudKit and not the key-value store.** `GlassShellSettingsSync` already syncs terminal
//  themes through `NSUbiquitousKeyValueStore`, and reusing it here was the obvious move and the
//  wrong one: KVS is 1 MB total across 1024 keys, every write replaces the whole value for its key,
//  and there is no partial update. Apple's own line decides it — if you would call it *a value*,
//  use KVS; if you would call it *records* or *a list*, use CloudKit. A host library is records, it
//  grows with use, and two devices editing different hosts must not overwrite each other.
//
//  **`HostProfile` was already shaped for this**, which is why the merge below is short:
//  `updatedAt` orders writes, `deletedAt` is a tombstone rather than an absence, and `lastWriterID`
//  names the device. Nothing here had to be added to the record; the catalog has modelled
//  convergence since it was written for three apps sharing one file.
//

import Foundation
import GlassConnectionKit

/// What the sync needs from a remote store. A protocol so the merge — the part with the rules in
/// it — is testable without a network, an iCloud account or a second device, none of which a unit
/// test has.
public protocol GlassCatalogSyncBackend: Sendable {
    /// Records changed since `token`, and the token to resume from next time. With a nil token,
    /// **every** record in the account, across however many pages the store answers in: the sync
    /// asks with nil, and its merge is only correct against a complete answer.
    func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?)
    /// Publishes local records. Implementations are expected to be idempotent.
    func save(_ profiles: [HostProfile]) async throws
    /// Asks the backend to notify this device when the library changes elsewhere. Optional: a
    /// backend with no notion of push does nothing, and the sync on foreground still reconciles.
    func subscribeToChanges() async throws
}

public extension GlassCatalogSyncBackend {
    func subscribeToChanges() async throws {}
}

/// What one completed sync did, in counts a person can check against another device.
public struct GlassCatalogSyncSummary: Equatable, Sendable {
    /// Records the account holds, tombstones included.
    public let inAccount: Int
    /// Records this device took from the account.
    public let received: Int
    /// Records this device sent to the account.
    public let sent: Int
}

public enum GlassCatalogSyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case synced(Date)
    /// iCloud is signed out, restricted, or the container is unavailable. Not an error the user
    /// caused, and not something retrying will fix on its own.
    case unavailable(String)
    case failed(String)
}

/// Merges a remote host library with the local one.
///
/// Deliberately a free function over values rather than a method on the store: every rule worth
/// arguing about is here, it touches no file and no network, and a test can put two versions of the
/// same host side by side and assert which one survives.
public enum GlassCatalogMerge {
    /// The winner between two versions of one host.
    ///
    /// **Last write wins, by `updatedAt`.** Per-field merging would be better for two people
    /// editing one host at the same moment, and is not worth its cost here: the library is edited
    /// rarely, by one person, usually on one device at a time. The rule is stated plainly so the
    /// trade is visible rather than discovered.
    ///
    /// **A tombstone at the same instant wins**, because deleting and then having a stale edit
    /// resurrect the host is the failure people notice and swear at. Equal timestamps otherwise
    /// keep the local copy, so a device that is merely echoing back what it sent does not churn.
    ///
    /// **A deletion is final** (2026-09-28). If either copy is a tombstone the tombstone wins,
    /// whatever the times — the catalog store's own rule ("tombstones cannot be resurrected by an
    /// offline writer"), which this merge had not followed. A headset last used months earlier
    /// re-stamped its old records during an upgrade and brought three long-deleted machines back.
    public static func winner(local: HostProfile, remote: HostProfile) -> HostProfile {
        switch (local.deletedAt != nil, remote.deletedAt != nil) {
        case (true, false): return local
        case (false, true): return remote
        default: break
        }
        if sameInstant(local.updatedAt, remote.updatedAt) {
            if remote.deletedAt != nil && local.deletedAt == nil { return remote }
            return local
        }
        return remote.updatedAt > local.updatedAt ? remote : local
    }

    /// Within half a millisecond. A date that has been through JSON and CloudKit comes back a
    /// rounding error away (1.2e-7 s, seen 2026-09-28), and a rounding error is not a newer write.
    static func sameInstant(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSinceReferenceDate - b.timeIntervalSinceReferenceDate) < 0.0005
    }

    /// The result of reconciling a remote set against the local one.
    public struct Outcome: Equatable, Sendable {
        /// Records to write into the local catalog.
        public var toApplyLocally: [HostProfile]
        /// Records to publish, because this device holds the newer version.
        public var toPublish: [HostProfile]
    }

    /// Reconciles both directions in one pass.
    ///
    /// A host present only remotely is applied locally — that is a host added on another device,
    /// which is the entire point. A host present only locally is published. Where both have it, the
    /// winner decides, a service's configuration is never lost to a copy without one, and the
    /// result is applied here if it differs from this device's copy and sent if it differs from the
    /// account's — so an unchanged library settles instead of ping-ponging.
    public static func reconcile(local: [HostProfile], remote: [HostProfile]) -> Outcome {
        var localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            a.updatedAt >= b.updatedAt ? a : b
        })
        var outcome = Outcome(toApplyLocally: [], toPublish: [])
        // One copy per record, the newest. CloudKit's paged answer can list a record twice, and
        // the second copy, finding this device's record already matched, read as a host this
        // device had never seen and was applied on every sync.
        let remote = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            winner(local: a, remote: b)
        }).values.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }

        for incoming in remote {
            guard let mine = localByID[incoming.id] else {
                outcome.toApplyLocally.append(incoming)
                continue
            }
            localByID.removeValue(forKey: incoming.id)
            let mineWins = winner(local: mine, remote: incoming) == mine
            let first = mineWins ? mine : incoming
            var merged = keepingConfigurations(first, from: mineWins ? incoming : mine)
            let restoredSetup = merged != first
            // This device's deletion overriding a live copy the account holds.
            let deletionOverrides = mineWins && mine.deletedAt != nil && incoming.deletedAt == nil
            if restoredSetup || deletionOverrides {
                // A correction the account does not hold. It must read as newer than both copies,
                // or a device still on the old newest-wins rule keeps the copy being corrected.
                merged.updatedAt = max(mine.updatedAt, incoming.updatedAt).addingTimeInterval(0.001)
                outcome.toApplyLocally.append(merged)
                outcome.toPublish.append(merged)
            } else if !mineWins {
                if incoming != mine { outcome.toApplyLocally.append(incoming) }
            } else if mine.updatedAt > incoming.updatedAt, !sameInstant(mine.updatedAt, incoming.updatedAt) {
                outcome.toPublish.append(mine)
            }
        }

        // Whatever the remote has never seen.
        outcome.toPublish.append(contentsOf: localByID.values)
        outcome.toPublish.sort { $0.updatedAt < $1.updatedAt }
        outcome.toApplyLocally.sort { $0.updatedAt < $1.updatedAt }
        return outcome
    }

    /// `winner` with any service configuration it lacks taken from `other`'s copy of the same
    /// service. **A configuration is never lost to a copy without one** (2026-09-28): the
    /// restamped headset's services had none, arrived newest, and every one showed "Not set up".
    /// A deliberate un-setup is not a thing the app can do — removing a service removes its link.
    static func keepingConfigurations(_ winner: HostProfile, from other: HostProfile) -> HostProfile {
        guard winner.deletedAt == nil else { return winner }
        let others = Dictionary(other.services.map { ($0.endpointID, $0) }, uniquingKeysWith: { a, _ in a })
        var result = winner
        for index in result.services.indices where result.services[index].configuration == nil {
            if let setup = others[result.services[index].endpointID]?.configuration,
               others[result.services[index].endpointID]?.kind == result.services[index].kind {
                result.services[index].configuration = setup
            }
        }
        return result
    }
}
