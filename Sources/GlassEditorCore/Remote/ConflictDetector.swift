import Foundation

/// The two-tier conflict check (INTEGRATION.md B2), as pure decision logic.
///
/// Stateless by construction: no stored baseline, no transport, no I/O, no
/// clock. Everything it knows arrives as arguments, which is what makes the
/// dangerous states testable without a network (projectRules.md, Testing:
/// "Conflict resolution is pure logic over `RemoteStat` values and is tested
/// without a transport").
///
/// ## The two tiers
///
/// **Tier 1 — stat.** Cheap enough to run on every window re-focus and before
/// every save. `readAttributes()` gives size and modification time and nothing
/// else. It is false-positive-prone: filesystems with coarse mtime, and `touch`,
/// both report "changed" for content that is byte-identical.
///
/// **Tier 2 — digest.** Definitive, and only consulted when tier 1 says
/// *changed* or cannot tell. Comparing SHA-256 against the digest captured at
/// open is what kills tier 1's false positives, so the user is not prompted on
/// every save of a file nobody else touched.
///
/// ## What this type will never do
///
/// There is no path from `.remoteChangedLocalDirty` or `.indeterminate` to an
/// action. This function returns a *state*; the actions live in
/// `ConflictResolution` and are chosen by a human through `ConflictPrompt`
/// (D-006). `indeterminate` is never coerced into `noConflict` to make a prompt
/// go away.
///
/// ## The asymmetry, stated plainly
///
/// When tier 1 reports change and tier 2 is unavailable (either digest missing),
/// we genuinely cannot distinguish `touch` from a real edit. The answer then
/// depends on what is at risk, because the cost of being wrong is not symmetric:
///
/// - **Local buffer dirty** → `.indeterminate`. Guessing `noConflict` here risks
///   destroying unsaved user work; guessing `remoteChangedLocalDirty` claims a
///   conflict we cannot prove. Both are dishonest, so we say so and let the user
///   decide.
/// - **Local buffer clean** → `.remoteChangedLocalClean`. There is nothing local
///   to lose, so erring toward "reload is available" costs the user at most a
///   redundant reload of identical bytes. The state is offered, not taken:
///   `.discardLocalAndReload` is still a choice, never automatic.
///
/// So the errors this state machine permits itself run in one direction only:
/// toward asking, and away from silently discarding work.
public enum ConflictDetector {

    /// Classify the current remote state against the baseline captured at open.
    ///
    /// - Parameters:
    ///   - session: identity captured at open (or after the last successful save).
    ///   - currentStat: what `readAttributes()` just returned. `nil` means the
    ///     stat call itself failed — not that the file is unchanged.
    ///   - currentDigest: SHA-256 of the remote content as it is *now*, if the
    ///     consumer has re-read it. `nil` means tier 2 is unavailable.
    ///   - localDirty: whether the buffer has unsaved edits.
    public static func classify(
        session: RemoteDocumentSession,
        currentStat: RemoteStat?,
        currentDigest: ContentDigest?,
        localDirty: Bool
    ) -> ConflictState {
        // A failed stat is an absence of observation, not evidence of sameness.
        // It is reported honestly and never coerced (projectRules.md, Data
        // Safety; INTEGRATION.md Part E, glas.sh regression list).
        guard let currentStat else { return .indeterminate }

        switch statVerdict(opened: session.openedStat, current: currentStat) {
        case .unchanged:
            // Tier 1 says same — sufficient on its own for the common case,
            // where no digest was read and stat is the only signal. But a digest
            // is *definitive* and a stat is a heuristic: if both digests are in
            // hand and positively disagree, the remote was edited in a way that
            // left size and mtime unchanged (an equal-length edit, or a
            // mtime-preserving write), and returning `.noConflict` here would
            // silently green-light an overwrite over changed content — the exact
            // trap tier 2 exists to close (pen-suite finding). A definitive
            // disagreement overrules a stat that merely failed to notice.
            if let opened = session.openedDigest,
               let current = currentDigest,
               opened != current {
                return localDirty ? .remoteChangedLocalDirty : .remoteChangedLocalClean
            }
            return .noConflict

        case .changed:
            return resolveWithDigest(
                opened: session.openedDigest,
                current: currentDigest,
                localDirty: localDirty,
                hasStatEvidenceOfChange: true
            )

        case .uncomparable:
            // No usable stat signal on one or both sides. Tier 2 can still
            // settle it outright if both digests exist; otherwise we have no
            // evidence of anything at all, in either direction.
            return resolveWithDigest(
                opened: session.openedDigest,
                current: currentDigest,
                localDirty: localDirty,
                hasStatEvidenceOfChange: false
            )
        }
    }

    // MARK: - Tier 1

    /// What the cheap stat comparison can conclude on its own.
    enum StatVerdict: Sendable, Hashable {
        /// Every field comparable on both sides agrees, and at least one of
        /// those was size or modification time.
        case unchanged
        /// At least one comparable field disagrees. Might still be a `touch`;
        /// tier 2 decides.
        case changed
        /// Too few fields are present on both sides to conclude anything.
        case uncomparable
    }

    /// Compare two stats field by field.
    ///
    /// A field counts only when **both** sides carry it — servers genuinely omit
    /// fields, and comparing a value against a missing value proves nothing.
    /// Modification nanoseconds are compared when available, because two writes
    /// inside the same second are exactly the case a seconds-only comparison
    /// misses, but nanoseconds alone are not a sufficient basis: without size or
    /// seconds to anchor them the verdict is `.uncomparable`.
    static func statVerdict(opened: RemoteStat, current: RemoteStat) -> StatVerdict {
        guard !opened.isEmpty, !current.isEmpty else { return .uncomparable }

        var comparedPrimaryField = false
        var anyFieldDiffers = false

        if let a = opened.size, let b = current.size {
            comparedPrimaryField = true
            if a != b { anyFieldDiffers = true }
        }
        if let a = opened.modificationSeconds, let b = current.modificationSeconds {
            comparedPrimaryField = true
            if a != b { anyFieldDiffers = true }
        }
        if let a = opened.modificationNanoseconds, let b = current.modificationNanoseconds {
            if a != b { anyFieldDiffers = true }
        }

        // Neither side is empty, yet they share no primary field — e.g. one
        // server reported size only and the other reported mtime only. Nothing
        // was actually compared.
        guard comparedPrimaryField else { return .uncomparable }

        return anyFieldDiffers ? .changed : .unchanged
    }

    // MARK: - Tier 2

    /// Settle a tier-1 "changed" or "cannot tell" with the content digest.
    ///
    /// - Parameter hasStatEvidenceOfChange: `true` when tier 1 positively
    ///   observed a difference. When `false`, tier 1 observed *nothing*, so a
    ///   missing digest leaves us with no evidence in either direction and the
    ///   only honest answer is `.indeterminate` — including for a clean buffer,
    ///   which must not be told the remote changed when nothing suggested it.
    static func resolveWithDigest(
        opened: ContentDigest?,
        current: ContentDigest?,
        localDirty: Bool,
        hasStatEvidenceOfChange: Bool
    ) -> ConflictState {
        if let opened, let current {
            // Definitive, and the whole reason tier 2 exists: equal digests mean
            // a metadata-only touch, and the user is not prompted.
            guard opened != current else { return .noConflict }
            return localDirty ? .remoteChangedLocalDirty : .remoteChangedLocalClean
        }

        // No tier 2 available. See the asymmetry note on `ConflictDetector`.
        guard hasStatEvidenceOfChange else { return .indeterminate }
        return localDirty ? .indeterminate : .remoteChangedLocalClean
    }
}
