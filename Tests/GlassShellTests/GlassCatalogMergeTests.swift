//
//  GlassCatalogMergeTests.swift
//  Glass Power Tools — GlassShellTests
//
//  D19's rules, tested without a network, an iCloud account or a second device — none of which a
//  unit test has. That is the reason `GlassCatalogSyncBackend` is a protocol and the merge is a
//  free function over values: the part with the arguments in it can be held still and asserted,
//  while the part that talks to CloudKit stays behind a seam.
//
//  What these cannot prove, stated here so nobody mistakes a green suite for a working feature:
//  that CloudKit delivers the records, that a change token resumes correctly, or that two real
//  devices converge. Those need two devices and an iCloud account, and they are on Stage 3.5's
//  device checklist for exactly that reason.
//

import Foundation
import Testing
import GlassConnectionKit
@testable import GlassShell

@Suite("Catalog merge")
struct GlassCatalogMergeTests {
    private let epoch = Date(timeIntervalSince1970: 1_757_000_000)

    private func host(_ name: String, id: HostID = HostID(), updated: TimeInterval,
                      deleted: TimeInterval? = nil) throws -> HostProfile {
        try HostProfile(id: id, displayName: name,
                        createdAt: epoch,
                        updatedAt: epoch.addingTimeInterval(updated),
                        deletedAt: deleted.map { epoch.addingTimeInterval($0) })
    }

    // MARK: - Which version survives

    @Test("The newer write wins, whichever device made it")
    func newerWriteWins() throws {
        let id = HostID()
        let mine = try host("local", id: id, updated: 10)
        let theirs = try host("remote", id: id, updated: 20)

        // Both orderings, asserted exactly: the newer record is "remote" (updated: 20), so it must
        // win whether it arrives as the remote copy or is already the local one.
        #expect(GlassCatalogMerge.winner(local: mine, remote: theirs).displayName == "remote")
        #expect(GlassCatalogMerge.winner(local: theirs, remote: mine).displayName == "remote",
                "the newer one is kept regardless of which side it arrived from")
    }

    /// The failure people actually notice: delete a host on the Mac, and a stale edit from the
    /// Vision Pro brings it back.
    @Test("A tombstone at the same instant beats an edit")
    func tombstoneWinsATie() throws {
        let id = HostID()
        let edited = try host("edited", id: id, updated: 10)
        let deleted = try host("deleted", id: id, updated: 10, deleted: 10)

        #expect(GlassCatalogMerge.winner(local: edited, remote: deleted).deletedAt != nil,
                "a deletion must not be undone by an edit made at the same moment")
        #expect(GlassCatalogMerge.winner(local: deleted, remote: edited).deletedAt != nil,
                "and the same however the two arrive")
    }

    /// A device echoing back what it just sent must not look like a change, or two devices will
    /// hand the same record to each other indefinitely.
    @Test("An identical timestamp keeps the local copy")
    func identicalTimestampsSettle() throws {
        let id = HostID()
        let mine = try host("mine", id: id, updated: 10)
        let echo = try host("echo", id: id, updated: 10)
        #expect(GlassCatalogMerge.winner(local: mine, remote: echo).displayName == "mine")
    }

    // MARK: - Reconciling whole libraries

    /// The requirement, in one test: *add a DB on Vision Pro, and it is there on the Mac.*
    @Test("A host that exists only remotely is applied locally")
    func remoteOnlyHostArrives() throws {
        let theirs = try host("from the Vision Pro", updated: 5)
        let outcome = GlassCatalogMerge.reconcile(local: [], remote: [theirs])

        #expect(outcome.toApplyLocally.map(\.displayName) == ["from the Vision Pro"])
        #expect(outcome.toPublish.isEmpty, "nothing local to send")
    }

    /// And the reverse, which is what makes the first device's library reach the second at all.
    @Test("A host that exists only locally is published")
    func localOnlyHostIsPublished() throws {
        let mine = try host("from the Mac", updated: 5)
        let outcome = GlassCatalogMerge.reconcile(local: [mine], remote: [])

        #expect(outcome.toPublish.map(\.displayName) == ["from the Mac"])
        #expect(outcome.toApplyLocally.isEmpty)
    }

    /// Two devices editing *different* hosts is the ordinary case, and neither may lose work —
    /// this is precisely what the key-value store could not do, since every write there replaces
    /// the whole value.
    @Test("Edits to different hosts on two devices both survive")
    func concurrentEditsToDifferentHostsBothSurvive() throws {
        let mine = try host("mac host", updated: 30)
        let theirs = try host("vision host", updated: 40)

        let outcome = GlassCatalogMerge.reconcile(local: [mine], remote: [theirs])
        #expect(outcome.toApplyLocally.map(\.displayName) == ["vision host"])
        #expect(outcome.toPublish.map(\.displayName) == ["mac host"])
    }

    /// An unchanged library must produce no work at all, or every sync writes and every write
    /// wakes the other device.
    @Test("An already-converged library produces nothing to do")
    func convergedLibraryIsQuiet() throws {
        let id = HostID()
        let same = try host("same", id: id, updated: 10)
        let outcome = GlassCatalogMerge.reconcile(local: [same], remote: [same])

        #expect(outcome.toApplyLocally.isEmpty)
        #expect(outcome.toPublish.isEmpty, "a settled library must not keep talking")
    }

    /// A remote deletion reaches the local catalog as a tombstone, not as an absence — the record
    /// has to arrive, or the local copy simply stays.
    @Test("A remote deletion is applied locally")
    func remoteDeletionArrives() throws {
        let id = HostID()
        let mine = try host("doomed", id: id, updated: 10)
        let theirs = try host("doomed", id: id, updated: 20, deleted: 20)

        let outcome = GlassCatalogMerge.reconcile(local: [mine], remote: [theirs])
        #expect(outcome.toApplyLocally.count == 1)
        #expect(outcome.toApplyLocally.first?.deletedAt != nil)
    }

    /// Duplicate local records for one id — possible while several processes write the App Group
    /// file — collapse to the newest rather than both being published.
    @Test("Duplicate local records collapse to the newest")
    func duplicateLocalRecordsCollapse() throws {
        let id = HostID()
        let older = try host("older", id: id, updated: 10)
        let newer = try host("newer", id: id, updated: 20)

        let outcome = GlassCatalogMerge.reconcile(local: [older, newer], remote: [])
        #expect(outcome.toPublish.count == 1)
        #expect(outcome.toPublish.first?.displayName == "newer")
    }

    // MARK: - A stale device restamped its old library (2026-09-28)
    //
    // A headset last used months ago ran the new build, whose upgrade re-stamped its old records
    // with the time of the upgrade. Newest-wins then let those copies beat the account's: three
    // machines deleted long before came back alive, and live machines' services arrived with no
    // configuration ("Not set up"). The catalog store has always said tombstones cannot be
    // resurrected; the sync's merge did not.

    @Test("A deletion wins over a later live copy, whichever side holds it")
    func deletionIsFinal() throws {
        let id = HostID()
        let tombstone = try host("gone", id: id, updated: 10, deleted: 10)
        let restamped = try host("gone", id: id, updated: 99)
        #expect(GlassCatalogMerge.winner(local: tombstone, remote: restamped).deletedAt != nil)
        #expect(GlassCatalogMerge.winner(local: restamped, remote: tombstone).deletedAt != nil)
    }

    @Test("A local deletion the account holds alive is sent back")
    func localTombstoneIsRepublished() throws {
        let id = HostID()
        let tombstone = try host("gone", id: id, updated: 10, deleted: 10)
        let resurrected = try host("gone", id: id, updated: 99)
        let outcome = GlassCatalogMerge.reconcile(local: [tombstone], remote: [resurrected])
        #expect(outcome.toPublish.map(\.id) == [id])
        #expect(outcome.toPublish.first?.deletedAt != nil)
        // Stamped past the resurrected copy, so a device still on newest-wins takes it too.
        #expect((outcome.toPublish.first?.updatedAt ?? .distantPast) > resurrected.updatedAt)
    }

    @Test("A newer copy without a service's configuration keeps the configuration the other had")
    func configurationSurvivesAStaleRestamp() throws {
        let id = HostID(), endpoint = EndpointID()
        let setup = Data(#"{"port":22}"#.utf8)
        var configured = try host("alpha", id: id, updated: 10)
        configured.services = [HostServiceLink(endpointID: endpoint, kind: .ssh, displayName: "Terminal", configuration: setup)]
        var bare = try host("alpha", id: id, updated: 99)
        bare.services = [HostServiceLink(endpointID: endpoint, kind: .ssh, displayName: "Terminal")]

        // The configured copy is local, the bare one arrives newer: apply, but keep the setup, and
        // send the repaired record back so the account stops carrying the bare one.
        let incoming = GlassCatalogMerge.reconcile(local: [configured], remote: [bare])
        #expect(incoming.toApplyLocally.first?.services.first?.configuration == setup)
        #expect(incoming.toPublish.first?.services.first?.configuration == setup)

        // The other way round: the bare copy is local and newer; the account's setup is kept.
        let outgoing = GlassCatalogMerge.reconcile(local: [bare], remote: [configured])
        #expect(outgoing.toApplyLocally.first?.services.first?.configuration == setup)
        #expect(outgoing.toPublish.first?.services.first?.configuration == setup)
    }

    /// CloudKit's paged answer can list one record twice. The second copy found this device's
    /// record already matched and treated it as a host this device had never seen, applying it on
    /// every sync (seen 2026-09-28 in a dry run of a settled library).
    @Test("A record the account lists twice is reconciled once")
    func duplicateRemoteRecordsAreReconciledOnce() throws {
        let id = HostID()
        let settled = try host("gone", id: id, updated: 10, deleted: 10)
        let outcome = GlassCatalogMerge.reconcile(local: [settled], remote: [settled, settled])
        #expect(outcome.toApplyLocally.isEmpty)
        #expect(outcome.toPublish.isEmpty)
    }

    /// A date that has been through JSON and CloudKit comes back a rounding error away — seen as
    /// 1.2e-7 s on a corrected record — and "newer by a rounding error" applied it on every sync.
    @Test("Times a rounding error apart are the same moment")
    func roundingErrorsAreNotNewer() throws {
        let id = HostID()
        let mine = try host("gone", id: id, updated: 10, deleted: 10)
        var theirs = mine
        theirs.updatedAt = mine.updatedAt.addingTimeInterval(1.2e-7)
        let outcome = GlassCatalogMerge.reconcile(local: [mine], remote: [theirs])
        #expect(outcome.toApplyLocally.isEmpty)
        #expect(outcome.toPublish.isEmpty)
    }

    private func configured(_ host: HostProfile, endpoint: EndpointID = EndpointID()) -> HostProfile {
        var host = host
        host.services = [HostServiceLink(endpointID: endpoint, kind: .ssh, displayName: "Terminal",
                                         configuration: Data(#"{"port":22}"#.utf8))]
        return host
    }

    @Test("A live copy holding set-ups nothing else holds survives an older deletion")
    func uniqueSetupsSurviveADeletion() throws {
        // 2026-09-21: a phone folded a machine's duplicates into a record whose id the Mac had
        // deleted days earlier. Its services existed nowhere else; losing them lost the machine.
        let id = HostID()
        let tombstone = try host("folded", id: id, updated: 10, deleted: 10)
        let folded = configured(try host("folded", id: id, updated: 20))
        let outcome = GlassCatalogMerge.reconcile(local: [tombstone], remote: [folded])
        #expect(outcome.toApplyLocally.map(\.deletedAt) == [nil])
        #expect(outcome.toPublish.isEmpty)
    }

    @Test("A restamped stale copy newer than a deletion is corrected past both")
    func restampedStaleCopyIsCorrected() throws {
        let id = HostID()
        let stale = try host("old", id: id, updated: 30)
        let tombstone = try host("old", id: id, updated: 20, deleted: 20)
        let outcome = GlassCatalogMerge.reconcile(local: [stale], remote: [tombstone])
        let correction = try #require(outcome.toApplyLocally.first)
        #expect(correction.deletedAt != nil)
        #expect(correction.updatedAt > stale.updatedAt)
        #expect(outcome.toPublish.first?.deletedAt != nil)
    }

    @Test("A deletion stated after a restamp is simply taken")
    func laterDeletionStatementIsTaken() throws {
        let id = HostID()
        let stale = try host("old", id: id, updated: 30)
        let restated = try host("old", id: id, updated: 40, deleted: 10)
        let outcome = GlassCatalogMerge.reconcile(local: [stale], remote: [restated])
        #expect(outcome.toApplyLocally == [restated])
        #expect(outcome.toPublish.isEmpty)
    }

    // MARK: - Two devices folded one machine into different records (2026-09-28)
    //
    // The Mac held the machine as record M. A stale headset held an old record D for the same
    // machine, folded M's set-up service into D and deleted M, and D was itself deleted by the
    // sync: the machine was live nowhere. Whichever device syncs, the service must survive, and
    // both must end on the same record.

    @Test("The device holding the only live copy revives it and sends it")
    func onlyLiveCopyIsRevivedAndSent() throws {
        let m = HostID(), d = HostID(), endpoint = EndpointID()
        let myM = configured(try host("machine", id: m, updated: 10), endpoint: endpoint)
        let myD = try host("machine", id: d, updated: 5, deleted: 5)
        let theirM = try host("machine", id: m, updated: 30, deleted: 30)
        let theirD = try host("machine", id: d, updated: 31, deleted: 5)
        let outcome = GlassCatalogMerge.reconcile(local: [myM, myD], remote: [theirM, theirD])
        let sent = try #require(outcome.toPublish.first { $0.id == m })
        #expect(sent.deletedAt == nil)
        #expect(sent.services.first?.configuration != nil)
        #expect(sent.updatedAt > theirM.updatedAt)
    }

    @Test("The other device adopts the account's live copy and the two converge")
    func otherDeviceAdoptsTheAccountsCopy() throws {
        let m = HostID(), d = HostID(), endpoint = EndpointID()
        // The headset: its old D live with the folded service, M deleted.
        let myD = configured(try host("machine", id: d, updated: 40), endpoint: endpoint)
        let myM = try host("machine", id: m, updated: 30, deleted: 30)
        // The account after the Mac's revival: M live with the service, D deleted.
        let theirM = configured(try host("machine", id: m, updated: 41), endpoint: endpoint)
        let theirD = try host("machine", id: d, updated: 31, deleted: 5)
        let outcome = GlassCatalogMerge.reconcile(local: [myD, myM], remote: [theirM, theirD])
        let applied = Dictionary(outcome.toApplyLocally.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(applied[m]?.deletedAt == nil, "the account's live copy is adopted")
        #expect(applied[d]?.deletedAt != nil, "the old copy stays deleted")
        #expect(!outcome.toPublish.contains { $0.id == m }, "nothing to send for the adopted copy")
    }

    // MARK: - What a person removed stays removed (2026-10-17)
    //
    // The pass above revived every set-up service no live record held, so a machine deleted on
    // purpose came back at the next sync — on the device that deleted it, from the account's
    // older copy — and so did every service removed with Remove Service. `deleteHost` leaves the
    // services on the tombstone and Remove Service leaves the record live, which a fold never does.

    @Test("A set-up machine deleted here stays deleted, and the deletion is sent")
    func deletedSetUpMachineStaysDeleted() throws {
        let id = HostID(), endpoint = EndpointID()
        let tombstone = configured(try host("doomed", id: id, updated: 20, deleted: 20), endpoint: endpoint)
        let accountCopy = configured(try host("doomed", id: id, updated: 10), endpoint: endpoint)
        let outcome = GlassCatalogMerge.reconcile(local: [tombstone], remote: [accountCopy])
        #expect(outcome.toApplyLocally.isEmpty, "the account's older copy came back: \(outcome.toApplyLocally)")
        #expect(outcome.toPublish.map(\.deletedAt) == [tombstone.deletedAt])
    }

    @Test("A set-up machine deleted on another device is deleted here too")
    func deletionOfASetUpMachineArrives() throws {
        let id = HostID(), endpoint = EndpointID()
        let mine = configured(try host("doomed", id: id, updated: 10), endpoint: endpoint)
        let tombstone = configured(try host("doomed", id: id, updated: 20, deleted: 20), endpoint: endpoint)
        let outcome = GlassCatalogMerge.reconcile(local: [mine], remote: [tombstone])
        #expect(outcome.toApplyLocally.map(\.deletedAt) == [tombstone.deletedAt])
        #expect(outcome.toPublish.isEmpty, "sent back alive: \(outcome.toPublish)")
    }

    @Test("A long-deleted set-up machine a stale device restamped stays deleted")
    func restampedSetUpMachineStaysDeleted() throws {
        // 2026-09-28's headset, with the machines' services set up: its upgrade restamped copies
        // the account had held deleted for months.
        let id = HostID(), endpoint = EndpointID()
        let restamped = configured(try host("gone", id: id, updated: 99), endpoint: endpoint)
        let tombstone = configured(try host("gone", id: id, updated: 10, deleted: 10), endpoint: endpoint)
        let outcome = GlassCatalogMerge.reconcile(local: [restamped], remote: [tombstone])
        #expect(outcome.toApplyLocally.allSatisfy { $0.deletedAt != nil })
        #expect(outcome.toPublish.allSatisfy { $0.deletedAt != nil })
    }

    @Test("A service removed here stays removed, and the record is sent without it")
    func removedServiceStaysRemoved() throws {
        let id = HostID(), removed = EndpointID(), kept = EndpointID()
        let accountCopy = withService(configured(try host("alpha", id: id, updated: 10), endpoint: kept), removed)
        let mine = configured(try host("alpha", id: id, updated: 20), endpoint: kept)
        let outcome = GlassCatalogMerge.reconcile(local: [mine], remote: [accountCopy])
        #expect(outcome.toApplyLocally.isEmpty, "the removed service came back: \(outcome.toApplyLocally)")
        #expect(outcome.toPublish.map { $0.services.map(\.endpointID) } == [[kept]])
    }

    @Test("A service removed on another device is removed here too")
    func removalOfAServiceArrives() throws {
        let id = HostID(), removed = EndpointID(), kept = EndpointID()
        let mine = withService(configured(try host("alpha", id: id, updated: 10), endpoint: kept), removed)
        let theirs = configured(try host("alpha", id: id, updated: 20), endpoint: kept)
        let outcome = GlassCatalogMerge.reconcile(local: [mine], remote: [theirs])
        #expect(outcome.toApplyLocally.map { $0.services.map(\.endpointID) } == [[kept]])
        #expect(outcome.toPublish.isEmpty, "sent back with the removed service: \(outcome.toPublish)")
    }

    /// `host` with a second set-up service.
    private func withService(_ host: HostProfile, _ endpoint: EndpointID) -> HostProfile {
        var host = host
        host.services.append(HostServiceLink(endpointID: endpoint, kind: .database, displayName: "Database",
                                             configuration: Data(#"{"port":5432}"#.utf8)))
        return host
    }
}
