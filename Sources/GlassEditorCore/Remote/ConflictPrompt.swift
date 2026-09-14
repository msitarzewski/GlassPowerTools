import Foundation

/// What a user may legally do about a `ConflictState`.
///
/// This is the seam D-006 depends on: `ConflictDetector` produces a state and
/// stops, this type says which choices exist, and a human picks one. Nothing in
/// the package turns a state into an action on its own — there is deliberately
/// no `resolve(_:)` here that returns a chosen `ConflictResolution`.
///
/// ## Ordering
///
/// The returned array order is part of the contract, so consumers render a
/// stable list and tests can assert on it. The rule is **resolving actions
/// before deferring ones**:
///
/// 1. The actions that actually settle the conflict come first, ordered by which
///    side they preserve — keep local (`.overwriteRemote`), take remote
///    (`.discardLocalAndReload`), keep both (`.saveLocalCopy`).
/// 2. `.keepEditing` is always last and never first, because it resolves
///    nothing: the document stays dirty and the conflict stays surfaced.
///
/// This is an ordering, not an endorsement. The list answers "what may I do",
/// not "what should I do" — **the UI decides emphasis**, including which button
/// is default, which is destructive-styled, and which is the escape. A
/// destructive action appearing first must not be rendered as the default
/// action; that choice belongs to `GlassEditorUI` and the consumer app.
///
/// ## Origin
///
/// `.local` and `.remote` documents both have a backing store that can diverge
/// from the buffer, so both get the full state-driven list. (`.overwriteRemote`
/// reads as remote-flavored because the conflict scheme was designed for SFTP;
/// its semantic is the general one — write my buffer over the backing store.)
///
/// `.ephemeral` has no backing store at all: a query tab or scratch buffer has
/// nothing to reload from and nothing to overwrite. It cannot produce a conflict
/// in the first place, and if a caller asks anyway, offering "discard my work
/// and reload" from nowhere would be worse than offering nothing. So it returns
/// an empty list for every state.
public enum ConflictPrompt {

    /// The resolutions a user may choose for this state, safest-to-express order
    /// as documented above.
    ///
    /// Never returns an empty list for `.remoteChangedLocalDirty` or
    /// `.indeterminate` on a document that has a backing store — a dangerous
    /// state with no offered choice would be a dead end for the user, which is
    /// the failure mode D-006 exists to prevent.
    public static func availableResolutions(
        for state: ConflictState,
        origin: DocumentOrigin
    ) -> [ConflictResolution] {
        // No backing store, no conflict to resolve.
        if case .ephemeral = origin { return [] }

        switch state {
        case .noConflict:
            // Nothing to ask. An empty list is how a consumer knows not to
            // prompt at all.
            return []

        case .remoteChangedLocalClean:
            // Nothing local is at risk, so `.overwriteRemote` is not offered:
            // there are no unsaved edits worth pushing, and offering it would
            // invite clobbering a newer remote with a stale buffer for no gain.
            // `.saveLocalCopy` is likewise pointless — the buffer holds exactly
            // what was last saved.
            return [.discardLocalAndReload, .keepEditing]

        case .remoteChangedLocalDirty, .indeterminate:
            // The two dangerous states get every choice, and the same set:
            // `indeterminate` is treated with the caution of a known conflict
            // rather than being quietly downgraded (projectRules.md, Data
            // Safety). Both sides hold work that the other does not, so all four
            // outcomes — keep mine, take theirs, keep both, decide later — are
            // legitimate, and the package refuses to pick among them.
            return [.overwriteRemote, .discardLocalAndReload, .saveLocalCopy, .keepEditing]
        }
    }
}
