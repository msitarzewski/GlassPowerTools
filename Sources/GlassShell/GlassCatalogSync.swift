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
    /// Records changed since `token`, and the token to resume from next time.
    func fetchChanges(since token: Data?) async throws -> (profiles: [HostProfile], token: Data?)
    /// Publishes local records. Implementations are expected to be idempotent.
    func save(_ profiles: [HostProfile]) async throws
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
    public static func winner(local: HostProfile, remote: HostProfile) -> HostProfile {
        if local.updatedAt == remote.updatedAt {
            if remote.deletedAt != nil && local.deletedAt == nil { return remote }
            return local
        }
        return remote.updatedAt > local.updatedAt ? remote : local
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
    /// winner decides, and it is only sent back if this device is the one holding the newer copy,
    /// so an unchanged library settles instead of ping-ponging.
    public static func reconcile(local: [HostProfile], remote: [HostProfile]) -> Outcome {
        var localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            a.updatedAt >= b.updatedAt ? a : b
        })
        var outcome = Outcome(toApplyLocally: [], toPublish: [])

        for incoming in remote {
            guard let mine = localByID[incoming.id] else {
                outcome.toApplyLocally.append(incoming)
                continue
            }
            let winner = self.winner(local: mine, remote: incoming)
            if winner.updatedAt != mine.updatedAt || winner.deletedAt != mine.deletedAt {
                outcome.toApplyLocally.append(winner)
            } else if mine.updatedAt > incoming.updatedAt {
                outcome.toPublish.append(mine)
            }
            localByID.removeValue(forKey: incoming.id)
        }

        // Whatever the remote has never seen.
        outcome.toPublish.append(contentsOf: localByID.values)
        outcome.toPublish.sort { $0.updatedAt < $1.updatedAt }
        outcome.toApplyLocally.sort { $0.updatedAt < $1.updatedAt }
        return outcome
    }
}
