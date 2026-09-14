import Foundation
import Testing
@testable import GlassEditorCore

/// The two-tier conflict check (INTEGRATION.md B2) as an exhaustive truth table.
///
/// Every case here runs without a transport, a socket, or a filesystem —
/// `ConflictDetector` is pure decision logic, which is precisely what
/// projectRules.md (Testing) requires of it. The forced-conflict and
/// coarse-mtime cases from INTEGRATION.md Part E's glas.sh regression list are
/// named individually below.
@Suite("Remote conflict detection")
struct RemoteConflictTests {

    // MARK: - Fixtures

    static let ref = RemoteDocumentRef(
        connectionID: UUID(uuidString: "6F0C1E2A-9B3D-4A57-8E11-2C4D6F8A0B12")!,
        host: "umbp.tail1234.ts.net",
        path: "/etc/nginx/nginx.conf"
    )

    /// Two distinct, well-formed SHA-256 values. Content is irrelevant; only
    /// equality matters to tier 2.
    static let digestA = ContentDigest(bytes: Array(repeating: 0xAA, count: 32))!
    static let digestB = ContentDigest(bytes: Array(repeating: 0xBB, count: 32))!

    static let openedSeconds: Int64 = 1_770_000_000
    static let openedNanoseconds: Int64 = 250_000_000

    /// A fully-populated stat: the best case a server can give us.
    static let fullStat = RemoteStat(
        size: 4096,
        modificationSeconds: openedSeconds,
        modificationNanoseconds: openedNanoseconds
    )

    // MARK: - Stat axis

    /// Every meaningful shape the tier-1 comparison can be handed.
    enum StatScenario: String, CaseIterable, Sendable {
        /// `readAttributes()` itself failed.
        case currentMissing
        /// Baseline carried no identity signal at all.
        case openedEmpty
        /// Server just returned nothing usable.
        case currentEmpty
        /// Neither side ever had a signal.
        case bothEmpty
        /// Byte-identical stats.
        case equal
        /// Size changed — a real content change, almost always.
        case sizeDiffers
        /// Whole-second mtime moved.
        case secondsDiffer
        /// Same second, different nanoseconds — two writes inside one second.
        case nanosecondsDiffer
        /// One side omits nanoseconds; everything comparable agrees.
        case partiallyComparableEqual
        /// One side omits nanoseconds; a comparable field disagrees.
        case partiallyComparableDifferent
        /// Both sides carry a signal, but not the *same* signal.
        case disjointFields
        /// The only field present on both sides is nanoseconds.
        case nanosecondsOnlyComparable

        var opened: RemoteStat {
            switch self {
            case .currentMissing, .currentEmpty, .equal, .sizeDiffers,
                 .secondsDiffer, .nanosecondsDiffer:
                return fullStat
            case .openedEmpty, .bothEmpty:
                return RemoteStat()
            case .partiallyComparableEqual, .partiallyComparableDifferent:
                return RemoteStat(size: 4096, modificationSeconds: openedSeconds)
            case .disjointFields:
                return RemoteStat(size: 4096)
            case .nanosecondsOnlyComparable:
                return RemoteStat(size: 4096, modificationNanoseconds: openedNanoseconds)
            }
        }

        var current: RemoteStat? {
            switch self {
            case .currentMissing:
                return nil
            case .currentEmpty, .bothEmpty:
                return RemoteStat()
            case .openedEmpty, .equal:
                return fullStat
            case .sizeDiffers:
                return RemoteStat(
                    size: 8192,
                    modificationSeconds: openedSeconds,
                    modificationNanoseconds: openedNanoseconds
                )
            case .secondsDiffer:
                return RemoteStat(
                    size: 4096,
                    modificationSeconds: openedSeconds + 1,
                    modificationNanoseconds: openedNanoseconds
                )
            case .nanosecondsDiffer:
                return RemoteStat(
                    size: 4096,
                    modificationSeconds: openedSeconds,
                    modificationNanoseconds: openedNanoseconds + 1
                )
            case .partiallyComparableEqual:
                return fullStat
            case .partiallyComparableDifferent:
                return RemoteStat(
                    size: 8192,
                    modificationSeconds: openedSeconds,
                    modificationNanoseconds: openedNanoseconds
                )
            case .disjointFields:
                return RemoteStat(modificationSeconds: openedSeconds)
            case .nanosecondsOnlyComparable:
                return RemoteStat(
                    modificationSeconds: openedSeconds,
                    modificationNanoseconds: openedNanoseconds
                )
            }
        }
    }

    // MARK: - Digest axis

    enum DigestScenario: String, CaseIterable, Sendable {
        /// Tier 2 available and says: identical content.
        case bothEqual
        /// Tier 2 available and says: genuinely different content.
        case bothDifferent
        /// Captured at open, but the current content was not re-read.
        case openedOnly
        /// Current content re-read, but no baseline was captured at open.
        case currentOnly
        /// Tier 2 unavailable entirely.
        case neither

        var opened: ContentDigest? {
            switch self {
            case .bothEqual, .bothDifferent, .openedOnly: return digestA
            case .currentOnly, .neither: return nil
            }
        }

        var current: ContentDigest? {
            switch self {
            case .bothEqual: return digestA
            case .bothDifferent: return digestB
            case .currentOnly: return digestA
            case .openedOnly, .neither: return nil
            }
        }
    }

    // MARK: - The truth table

    /// Expected state for a dirty buffer and for a clean one.
    struct Expectation: Sendable {
        var whenDirty: ConflictState
        var whenClean: ConflictState

        init(dirty: ConflictState, clean: ConflictState) {
            self.whenDirty = dirty
            self.whenClean = clean
        }
    }

    /// Tier 1 concluded "no observable difference". Tier 2 is consulted only when
    /// a digest pair is actually in hand — the cost saving tier 1 buys is that a
    /// caller with no current digest is not forced to read the whole file — but a
    /// digest that *is* present and positively disagrees overrules the stat: a
    /// definitive signal beats a heuristic one, and a same-size, same-mtime
    /// content swap must not be silently green-lit (pen-suite finding closing the
    /// blind spot this row once documented).
    static let unchangedRow: [DigestScenario: Expectation] = [
        // Stat agrees; digests agreeing too changes nothing.
        .bothEqual: Expectation(dirty: .noConflict, clean: .noConflict),
        // Stat agrees, but the digests are both present and differ — real content
        // change. The dangerous cell: dirty must demand a human choice, never
        // noConflict (D-006).
        .bothDifferent: Expectation(dirty: .remoteChangedLocalDirty, clean: .remoteChangedLocalClean),
        // Only one digest, so tier 2 cannot compare; tier 1's "unchanged" stands.
        .openedOnly: Expectation(dirty: .noConflict, clean: .noConflict),
        .currentOnly: Expectation(dirty: .noConflict, clean: .noConflict),
        .neither: Expectation(dirty: .noConflict, clean: .noConflict),
    ]

    /// Tier 1 positively observed a difference. Tier 2 now decides whether that
    /// difference is real content or a bare `touch`.
    static let changedRow: [DigestScenario: Expectation] = [
        // The headline B2 case: coarse mtime / `touch` false positive, killed by
        // tier 2 without prompting the user.
        .bothEqual: Expectation(dirty: .noConflict, clean: .noConflict),
        // Definitive change. Dirty is the dangerous state; clean is safe to reload.
        .bothDifferent: Expectation(dirty: .remoteChangedLocalDirty, clean: .remoteChangedLocalClean),
        // No tier 2: cannot tell touch from edit. Dirty → say so; clean → reload
        // is offered because nothing local is at risk. (The documented asymmetry.)
        .openedOnly: Expectation(dirty: .indeterminate, clean: .remoteChangedLocalClean),
        .currentOnly: Expectation(dirty: .indeterminate, clean: .remoteChangedLocalClean),
        .neither: Expectation(dirty: .indeterminate, clean: .remoteChangedLocalClean),
    ]

    /// Tier 1 could not compare anything. There is no evidence of change *or* of
    /// sameness, so a missing digest yields `.indeterminate` on both sides — a
    /// clean buffer must not be told the remote changed when nothing said so.
    static let uncomparableRow: [DigestScenario: Expectation] = [
        // Tier 2 settles it outright, no stat needed.
        .bothEqual: Expectation(dirty: .noConflict, clean: .noConflict),
        .bothDifferent: Expectation(dirty: .remoteChangedLocalDirty, clean: .remoteChangedLocalClean),
        // No stat signal and no digest pair: nothing is known in either direction.
        .openedOnly: Expectation(dirty: .indeterminate, clean: .indeterminate),
        .currentOnly: Expectation(dirty: .indeterminate, clean: .indeterminate),
        .neither: Expectation(dirty: .indeterminate, clean: .indeterminate),
    ]

    /// The stat call failed. That is an absence of observation, not evidence,
    /// and it is surfaced honestly rather than coerced (D-006; INTEGRATION.md
    /// Part E: "`readAttributes()` returning no usable stat → `indeterminate`").
    static let currentMissingRow: [DigestScenario: Expectation] = [
        .bothEqual: Expectation(dirty: .indeterminate, clean: .indeterminate),
        .bothDifferent: Expectation(dirty: .indeterminate, clean: .indeterminate),
        .openedOnly: Expectation(dirty: .indeterminate, clean: .indeterminate),
        .currentOnly: Expectation(dirty: .indeterminate, clean: .indeterminate),
        .neither: Expectation(dirty: .indeterminate, clean: .indeterminate),
    ]

    static let matrix: [StatScenario: [DigestScenario: Expectation]] = [
        // A failed stat short-circuits before tier 1 runs at all.
        .currentMissing: currentMissingRow,
        // `isEmpty` on either side means no field can be compared.
        .openedEmpty: uncomparableRow,
        .currentEmpty: uncomparableRow,
        .bothEmpty: uncomparableRow,
        // Every field matches on both sides.
        .equal: unchangedRow,
        // Size is the strongest cheap signal of a content change.
        .sizeDiffers: changedRow,
        // Whole-second mtime movement.
        .secondsDiffer: changedRow,
        // Same second, different nanoseconds — the sub-second write.
        .nanosecondsDiffer: changedRow,
        // Nanoseconds present on one side only; size and seconds both agree, so
        // all comparable fields agree.
        .partiallyComparableEqual: unchangedRow,
        // Nanoseconds present on one side only; size disagrees, which is enough.
        .partiallyComparableDifferent: changedRow,
        // Size on one side, mtime on the other: nothing was actually compared.
        .disjointFields: uncomparableRow,
        // Nanoseconds alone are not an anchor — without size or seconds they
        // cannot establish sameness.
        .nanosecondsOnlyComparable: uncomparableRow,
    ]

    // MARK: - The exhaustive matrix test

    @Test(
        "Conflict matrix: stat state x digest state x dirty",
        arguments: StatScenario.allCases, DigestScenario.allCases
    )
    func conflictMatrix(stat: StatScenario, digests: DigestScenario) throws {
        let row = try #require(Self.matrix[stat], "no row for stat scenario \(stat.rawValue)")
        let expectation = try #require(row[digests], "no cell for digest scenario \(digests.rawValue)")

        let session = RemoteDocumentSession(
            ref: Self.ref,
            openedStat: stat.opened,
            openedDigest: digests.opened
        )

        for localDirty in [true, false] {
            let actual = ConflictDetector.classify(
                session: session,
                currentStat: stat.current,
                currentDigest: digests.current,
                localDirty: localDirty
            )
            let expected = localDirty ? expectation.whenDirty : expectation.whenClean
            #expect(
                actual == expected,
                "stat=\(stat.rawValue) digests=\(digests.rawValue) dirty=\(localDirty): expected \(expected), got \(actual)"
            )
        }
    }

    // MARK: - Invariants that hold across the whole matrix

    @Test("Nothing in the matrix ever auto-resolves a dirty buffer against a differing digest")
    func dirtyDifferingDigestNeverSilent() {
        // D-006 as a sweep: whenever tier 2 is available and says the content
        // really differs, a dirty buffer always lands in the state that demands
        // a human choice — never `.noConflict`.
        for stat in StatScenario.allCases where stat != .currentMissing {
            let session = RemoteDocumentSession(
                ref: Self.ref,
                openedStat: stat.opened,
                openedDigest: Self.digestA
            )
            let state = ConflictDetector.classify(
                session: session,
                currentStat: stat.current,
                currentDigest: Self.digestB,
                localDirty: true
            )
            // No blind spot: with both digests present and differing, a dirty
            // buffer lands in `.remoteChangedLocalDirty` for *every* stat shape —
            // including `.equal`, where the definitive digest overrules a stat
            // that merely failed to notice. This is the pen-suite finding that
            // brought the code in line with this test's own name.
            #expect(
                state == .remoteChangedLocalDirty,
                "\(stat.rawValue) produced \(state)"
            )
        }
    }

    @Test("Indeterminate is never produced when tier 2 can answer")
    func tierTwoAlwaysSettles() {
        // If both digests exist, the answer is definitive for every stat shape
        // except a failed stat call — tier 2 is what removes uncertainty.
        for stat in StatScenario.allCases where stat != .currentMissing {
            for (opened, current) in [(Self.digestA, Self.digestA), (Self.digestA, Self.digestB)] {
                let session = RemoteDocumentSession(ref: Self.ref, openedStat: stat.opened, openedDigest: opened)
                for dirty in [true, false] {
                    let state = ConflictDetector.classify(
                        session: session,
                        currentStat: stat.current,
                        currentDigest: current,
                        localDirty: dirty
                    )
                    #expect(state != .indeterminate, "\(stat.rawValue) dirty=\(dirty) went indeterminate with both digests present")
                }
            }
        }
    }

    // MARK: - Named regression cases (INTEGRATION.md Part E, glas.sh)

    @Test("Forced conflict: a shell edits the file mid-session, buffer is dirty")
    func forcedConflictNeverSilentOverwrite() {
        let session = RemoteDocumentSession(ref: Self.ref, openedStat: Self.fullStat, openedDigest: Self.digestA)
        let state = ConflictDetector.classify(
            session: session,
            currentStat: RemoteStat(size: 5000, modificationSeconds: Self.openedSeconds + 42, modificationNanoseconds: 0),
            currentDigest: Self.digestB,
            localDirty: true
        )
        #expect(state == .remoteChangedLocalDirty)
        // And the state offers choices rather than performing one.
        #expect(!ConflictPrompt.availableResolutions(for: state, origin: .remote(Self.ref)).isEmpty)
    }

    @Test("Coarse-mtime false positive resolves at tier 2 without prompting")
    func touchDoesNotPrompt() {
        // `touch` moved the mtime; content is byte-identical. Tier 1 says
        // changed, tier 2 says no — and the user is never asked.
        let session = RemoteDocumentSession(ref: Self.ref, openedStat: Self.fullStat, openedDigest: Self.digestA)
        let touched = RemoteStat(
            size: 4096,
            modificationSeconds: Self.openedSeconds + 3600,
            modificationNanoseconds: 0
        )
        let state = ConflictDetector.classify(
            session: session,
            currentStat: touched,
            currentDigest: Self.digestA,
            localDirty: true
        )
        #expect(state == .noConflict)
        #expect(ConflictPrompt.availableResolutions(for: state, origin: .remote(Self.ref)).isEmpty)
    }

    @Test("A failed stat is surfaced, never coerced to noConflict")
    func failedStatIsIndeterminate() {
        let session = RemoteDocumentSession(ref: Self.ref, openedStat: Self.fullStat, openedDigest: Self.digestA)
        for dirty in [true, false] {
            let state = ConflictDetector.classify(session: session, currentStat: nil, currentDigest: nil, localDirty: dirty)
            #expect(state == .indeterminate)
        }
    }

    @Test("Nanosecond precision distinguishes two writes inside the same second")
    func nanosecondPrecision() {
        // Seconds-only comparison would call these identical. Carrying seconds
        // and nanoseconds separately — as SFTPLocalFileIdentity does — is what
        // catches it.
        let opened = RemoteStat(size: 4096, modificationSeconds: 1_770_000_000, modificationNanoseconds: 100)
        let rewritten = RemoteStat(size: 4096, modificationSeconds: 1_770_000_000, modificationNanoseconds: 900)

        #expect(ConflictDetector.statVerdict(opened: opened, current: rewritten) == .changed)

        let session = RemoteDocumentSession(ref: Self.ref, openedStat: opened, openedDigest: Self.digestA)
        #expect(
            ConflictDetector.classify(session: session, currentStat: rewritten, currentDigest: Self.digestB, localDirty: true)
                == .remoteChangedLocalDirty
        )
        // Same-second rewrite that happens to produce identical content: still
        // no prompt, because tier 2 has the last word.
        #expect(
            ConflictDetector.classify(session: session, currentStat: rewritten, currentDigest: Self.digestA, localDirty: true)
                == .noConflict
        )
        // A truncating rewrite in the same second, with no digest available at
        // all, is the honest-uncertainty case.
        #expect(
            ConflictDetector.classify(session: session, currentStat: rewritten, currentDigest: nil, localDirty: true)
                == .indeterminate
        )
    }

    // MARK: - Session lifecycle

    @Test("updatingAfterSave makes the post-save identity the new baseline")
    func updatingAfterSaveRebaselines() {
        let session = RemoteDocumentSession(ref: Self.ref, openedStat: Self.fullStat, openedDigest: Self.digestA)
        let postSaveStat = RemoteStat(
            size: 5120,
            modificationSeconds: Self.openedSeconds + 90,
            modificationNanoseconds: 42
        )
        let saved = session.updatingAfterSave(stat: postSaveStat, digest: Self.digestB)

        #expect(saved.ref == session.ref, "the file identity itself does not change on save")
        #expect(saved.openedStat == postSaveStat)
        #expect(saved.openedDigest == Self.digestB)

        // Against the post-save reality, the new session is clean...
        for dirty in [true, false] {
            #expect(
                ConflictDetector.classify(
                    session: saved,
                    currentStat: postSaveStat,
                    currentDigest: Self.digestB,
                    localDirty: dirty
                ) == .noConflict,
                "our own write must not read back as a remote change"
            )
        }

        // ...and the *old* session would have flagged that same write as a
        // conflict, which is exactly why re-baselining is required.
        #expect(
            ConflictDetector.classify(
                session: session,
                currentStat: postSaveStat,
                currentDigest: Self.digestB,
                localDirty: true
            ) == .remoteChangedLocalDirty
        )
    }

    @Test("updatingAfterSave with no digest clears tier 2 rather than keeping a stale one")
    func updatingAfterSaveWithoutDigest() {
        let session = RemoteDocumentSession(ref: Self.ref, openedStat: Self.fullStat, openedDigest: Self.digestA)
        let postSaveStat = RemoteStat(size: 5120, modificationSeconds: Self.openedSeconds + 90)
        let saved = session.updatingAfterSave(stat: postSaveStat, digest: nil)

        #expect(saved.openedDigest == nil, "the pre-save digest no longer describes the remote content")
        // Tier 1 still carries the load; the post-save stat matches.
        #expect(
            ConflictDetector.classify(session: saved, currentStat: postSaveStat, currentDigest: nil, localDirty: false)
                == .noConflict
        )
        // Losing tier 2 costs precision, and that cost is paid as honest
        // uncertainty, not as a false all-clear.
        #expect(
            ConflictDetector.classify(
                session: saved,
                currentStat: RemoteStat(size: 5120, modificationSeconds: Self.openedSeconds + 91),
                currentDigest: nil,
                localDirty: true
            ) == .indeterminate
        )
    }

    @Test("RemoteDocumentSession is a value type with value equality")
    func sessionValueSemantics() {
        let a = RemoteDocumentSession(ref: Self.ref, openedStat: Self.fullStat, openedDigest: Self.digestA)
        let b = RemoteDocumentSession(ref: Self.ref, openedStat: Self.fullStat, openedDigest: Self.digestA)
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
        #expect(a != a.updatingAfterSave(stat: Self.fullStat, digest: nil))
    }

    // MARK: - Prompt

    @Test("noConflict offers nothing to decide")
    func noConflictOffersNothing() {
        #expect(ConflictPrompt.availableResolutions(for: .noConflict, origin: .remote(Self.ref)).isEmpty)
        #expect(ConflictPrompt.availableResolutions(for: .noConflict, origin: .local(URL(filePath: "/tmp/a.sql"))).isEmpty)
    }

    @Test("remoteChangedLocalClean offers reload or carry on, in that order")
    func cleanOffersReloadOrContinue() {
        let resolutions = ConflictPrompt.availableResolutions(for: .remoteChangedLocalClean, origin: .remote(Self.ref))
        #expect(resolutions == [.discardLocalAndReload, .keepEditing])
        // Nothing local is at risk, so pushing a stale buffer is not offered.
        #expect(!resolutions.contains(.overwriteRemote))
        #expect(!resolutions.contains(.saveLocalCopy))
    }

    @Test(
        "The dangerous states always offer every choice",
        arguments: [ConflictState.remoteChangedLocalDirty, .indeterminate]
    )
    func dangerousStatesOfferEverything(state: ConflictState) {
        for origin in [DocumentOrigin.remote(Self.ref), .local(URL(filePath: "/tmp/a.sql"))] {
            let resolutions = ConflictPrompt.availableResolutions(for: state, origin: origin)
            #expect(!resolutions.isEmpty, "a dangerous state with no offered choice is a dead end for the user")
            #expect(resolutions == [.overwriteRemote, .discardLocalAndReload, .saveLocalCopy, .keepEditing])
            #expect(Set(resolutions) == Set(ConflictResolution.allCases), "no resolution is silently withheld")
            #expect(resolutions.last == .keepEditing, "the action that resolves nothing sorts last")
            #expect(resolutions.first != .keepEditing, "the list is 'what you may do'; deferring is never the head of it")
            #expect(Set(resolutions).count == resolutions.count, "no duplicates")
        }
    }

    @Test("indeterminate is offered the same choices as a known conflict")
    func indeterminateIsNotDowngraded() {
        // The rule from projectRules.md (Data Safety) expressed as behavior:
        // uncertainty is treated with the caution of certainty, not with the
        // convenience of `noConflict`.
        #expect(
            ConflictPrompt.availableResolutions(for: .indeterminate, origin: .remote(Self.ref))
                == ConflictPrompt.availableResolutions(for: .remoteChangedLocalDirty, origin: .remote(Self.ref))
        )
    }

    @Test("Ephemeral documents have no backing store to reconcile against")
    func ephemeralOffersNothing() {
        let origin = DocumentOrigin.ephemeral(id: UUID())
        for state in [ConflictState.noConflict, .remoteChangedLocalClean, .remoteChangedLocalDirty, .indeterminate] {
            #expect(
                ConflictPrompt.availableResolutions(for: state, origin: origin).isEmpty,
                "a scratch buffer cannot be reloaded from, nor overwritten onto, anything"
            )
        }
    }

    // MARK: - Tier 1 unit checks

    @Test("statVerdict field-comparability rules")
    func statVerdictRules() {
        typealias Verdict = ConflictDetector.StatVerdict
        let cases: [(RemoteStat, RemoteStat, Verdict, String)] = [
            (RemoteStat(), RemoteStat(), .uncomparable, "no signal on either side"),
            (RemoteStat(), Self.fullStat, .uncomparable, "no baseline to compare against"),
            (Self.fullStat, RemoteStat(), .uncomparable, "server gave nothing usable back"),
            (RemoteStat(size: 10), RemoteStat(size: 10), .unchanged, "size alone is a valid anchor"),
            (RemoteStat(size: 10), RemoteStat(size: 11), .changed, "size alone is a valid anchor"),
            (RemoteStat(modificationSeconds: 5), RemoteStat(modificationSeconds: 5), .unchanged, "mtime alone is a valid anchor"),
            (RemoteStat(modificationSeconds: 5), RemoteStat(modificationSeconds: 6), .changed, "mtime alone is a valid anchor"),
            (RemoteStat(size: 10), RemoteStat(modificationSeconds: 5), .uncomparable, "disjoint fields compare nothing"),
            (
                RemoteStat(size: 10, modificationNanoseconds: 1),
                RemoteStat(modificationSeconds: 5, modificationNanoseconds: 1),
                .uncomparable,
                "nanoseconds alone cannot anchor a sameness claim"
            ),
            (
                RemoteStat(size: 10, modificationSeconds: 5),
                RemoteStat(size: 10, modificationSeconds: 5, modificationNanoseconds: 7),
                .unchanged,
                "a field only one side carries is not evidence of difference"
            ),
            (
                RemoteStat(size: 10, modificationSeconds: 5, modificationNanoseconds: 7),
                RemoteStat(size: 10, modificationSeconds: 5, modificationNanoseconds: 8),
                .changed,
                "nanoseconds do count when both sides carry them"
            ),
        ]
        for (opened, current, expected, rationale) in cases {
            #expect(ConflictDetector.statVerdict(opened: opened, current: current) == expected, "\(rationale)")
        }
    }
}
