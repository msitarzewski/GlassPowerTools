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
}
