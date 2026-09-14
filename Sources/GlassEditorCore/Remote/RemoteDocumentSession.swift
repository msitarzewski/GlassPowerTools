import Foundation

/// The identity of a remote document as captured at open, and the baseline every
/// later conflict check compares against.
///
/// Both tiers of the conflict check (INTEGRATION.md B2) need a *baseline*, and
/// both baselines are available at the same moment for free:
///
/// - `openedStat` is what `readAttributes()` returned, modeled on glas.sh's
///   `SFTPLocalFileIdentity` (`SFTPBrowserView.swift:78–94`).
/// - `openedDigest` is the SHA-256 of the bytes we actually opened. Edit-in-place
///   reads the whole file, so the digest costs nothing extra at open — glas.sh
///   already computes exactly this at `SFTPBrowserView.swift:902,916,935`.
///
/// The digest is optional because a consumer may legitimately not have one (a
/// reload path that streams, a transport that hands back a file handle). Absence
/// is represented, never defaulted — `ConflictDetector` degrades to
/// `.indeterminate` rather than guessing (projectRules.md, Data Safety).
///
/// This type holds identity only. It owns no transport, no bytes, and no dirty
/// flag: `localDirty` is passed in at classify time because the buffer's dirty
/// state belongs to the document, not to the remote identity.
public struct RemoteDocumentSession: Sendable, Hashable {
    /// The file this session is editing. Opaque to the package.
    public var ref: RemoteDocumentRef

    /// The cheap identity observed at open — tier 1's baseline.
    public var openedStat: RemoteStat

    /// SHA-256 of the content observed at open — tier 2's baseline.
    /// `nil` means tier 2 is unavailable, not that the content was empty.
    public var openedDigest: ContentDigest?

    public init(
        ref: RemoteDocumentRef,
        openedStat: RemoteStat,
        openedDigest: ContentDigest? = nil
    ) {
        self.ref = ref
        self.openedStat = openedStat
        self.openedDigest = openedDigest
    }

    /// The session that succeeds this one after a successful consumer-side save.
    ///
    /// The package never performs the transfer (projectRules.md, Scope
    /// Discipline: "No SFTP transport"). When glas.sh's verified atomic commit
    /// reports success, it hands back the stat and digest of what it actually
    /// wrote, and *that* becomes the new baseline — otherwise the very next
    /// focus check would compare against the pre-save identity and report our
    /// own write as a remote change.
    ///
    /// Passing `digest: nil` **clears** the previous digest rather than keeping
    /// it. Keeping it would be a lie: the content on the remote is now the
    /// post-save content, and the pre-save digest no longer describes it.
    /// Losing tier 2 costs precision; keeping a stale digest would cost
    /// correctness, and the two are not trade-able in this package.
    public func updatingAfterSave(stat: RemoteStat, digest: ContentDigest?) -> RemoteDocumentSession {
        RemoteDocumentSession(ref: ref, openedStat: stat, openedDigest: digest)
    }
}
