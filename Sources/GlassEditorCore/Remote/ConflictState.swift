import Foundation

/// The conflict decision for a remote document at save or re-focus time.
///
/// Rules (D-006, projectRules.md Data Safety):
/// - `remoteChangedLocalDirty` always requires an explicit user choice.
///   There is no last-write-wins path anywhere in this package.
/// - `indeterminate` is first-class and surfaced honestly — it is never
///   coerced into `noConflict` because a stat came back empty.
public enum ConflictState: Sendable, Hashable {
    /// Remote matches what we opened; saving is safe.
    case noConflict

    /// Remote changed but the local buffer has no unsaved edits.
    /// Safe to reload; nothing local is lost.
    case remoteChangedLocalClean

    /// Remote changed *and* the local buffer is dirty. The dangerous state.
    /// Resolution is an explicit user choice, made through `ConflictResolution`.
    case remoteChangedLocalDirty

    /// We cannot tell — the stat carried no identity signal, or signals
    /// disagree in a way the two-tier check cannot settle. Treated with the
    /// same caution as a known conflict.
    case indeterminate
}

/// The explicit user choices offered for `remoteChangedLocalDirty` and
/// `indeterminate`. Note there is no `merge` in v1 and no silent default.
public enum ConflictResolution: String, Sendable, Hashable, CaseIterable {
    /// Overwrite the remote with the local buffer. Explicitly chosen, never assumed.
    case overwriteRemote
    /// Discard local edits and reload the remote content.
    case discardLocalAndReload
    /// Save the local buffer somewhere else (consumer supplies the destination).
    case saveLocalCopy
    /// Do nothing; the document stays dirty and the conflict stays surfaced.
    case keepEditing
}
