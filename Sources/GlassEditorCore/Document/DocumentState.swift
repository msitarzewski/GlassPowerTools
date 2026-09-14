import Foundation

/// Everything the engine needs at open, and everything save has to consult to
/// stay honest.
///
/// This is the value handed across the open boundary. It is deliberately a
/// plain struct with no behavior: the facts established while reading the file
/// — what encoding the bytes were, what terminators they used, what the remote
/// looked like at that instant — must travel with the content, because by save
/// time the file on the other end may have changed and the only defense is
/// having recorded what was true when we opened it.
public struct DocumentSnapshot: Sendable, Hashable {
    /// Text exactly as decoded. Line terminators are **not** normalized; a BOM
    /// is **not** included (it lives in `encoding`).
    public var content: String

    /// The encoding the bytes actually were, replayed verbatim at save.
    public var encoding: DetectedEncoding

    /// The terminator style observed at open. Governs what a newly typed line
    /// break inserts; existing terminators in `content` are untouched.
    public var lineEndings: LineEndingStyle

    /// Where the content came from, and therefore who owns saving it.
    public var origin: DocumentOrigin

    /// SHA-256 of the bytes as opened, when the consumer computed one.
    ///
    /// `nil` for `.local` origins in v1 — tier 2 of conflict detection exists to
    /// kill coarse-mtime false positives on remote files (INTEGRATION.md B2),
    /// and glas.sh already computes the digest during transfer for free. Hashing
    /// every local open would be a cost paid for a problem local files don't have.
    public var openedDigest: ContentDigest?

    /// The remote's stat at the moment we opened it. `nil` for local and
    /// ephemeral origins. Absent fields inside a present stat are meaningful —
    /// see `RemoteStat.isEmpty`.
    public var openedStat: RemoteStat?

    public init(
        content: String,
        encoding: DetectedEncoding,
        lineEndings: LineEndingStyle,
        origin: DocumentOrigin,
        openedDigest: ContentDigest? = nil,
        openedStat: RemoteStat? = nil
    ) {
        self.content = content
        self.encoding = encoding
        self.lineEndings = lineEndings
        self.origin = origin
        self.openedDigest = openedDigest
        self.openedStat = openedStat
    }

    /// Whether this package owns writing this document back.
    ///
    /// `.remote` is false on purpose: glas.sh's transfer layer already does
    /// SHA-256 verification, mid-transfer change detection, and atomic commit,
    /// more rigorously than a reimplementation would (INTEGRATION.md B1). The
    /// package owns the conflict *decision*, never the transfer.
    public var isPackageSaveable: Bool {
        if case .local = origin { return true }
        return false
    }
}

/// Stateless document loading (projectRules.md, Naming).
///
/// Three entry points for three real situations: a local file the package
/// reads itself, bytes the consumer already holds (a completed SFTP download),
/// and text with no bytes behind it at all (a glassdb query tab).
public enum DocumentLoader: Sendable {

    /// Read and decode a local file.
    ///
    /// The size ceiling is checked against the filesystem's reported size
    /// **before** the bytes are read, not after. Reading first and measuring
    /// second would mean a multi-gigabyte file gets fully resident in memory
    /// precisely in the case the ceiling exists to prevent.
    ///
    /// - Throws: `EditorError.fileTooLarge` above `configuration.largeFileByteCeiling`,
    ///   `EditorError.unreadableData` if the file cannot be read, and whatever
    ///   `EncodingDetector.decode(_:)` throws.
    public static func load(
        from url: URL,
        configuration: GlassEditorConfiguration
    ) throws -> DocumentSnapshot {
        // `resourceValues` follows symlinks; `attributesOfItem(atPath:)` does
        // not, and would report the link's own few bytes for a symlink pointing
        // at a 4 GB file — waving it straight past the ceiling.
        let reportedSize: UInt64
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            // Require a regular file (pen finding M-4). `.fileSizeKey` is nil for
            // FIFOs, character devices, and directories, so `?? 0` would sail a
            // named pipe or `/dev/zero` past the ceiling and into an unbounded /
            // blocking `Data(contentsOf:)`. `resourceValues` follows symlinks, so
            // this reflects the target.
            guard values.isRegularFile == true else {
                throw EditorError.unreadableData(reason: "\(url.lastPathComponent): not a regular file")
            }
            reportedSize = UInt64(values.fileSize ?? 0)
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError.unreadableData(reason: "\(url.lastPathComponent): \(error.localizedDescription)")
        }
        guard reportedSize <= configuration.largeFileByteCeiling else {
            throw EditorError.fileTooLarge(bytes: reportedSize, ceiling: configuration.largeFileByteCeiling)
        }

        // Read, don't memory-map: a mapped file that is truncated underneath us
        // faults the whole process, and everything here is under the ceiling.
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EditorError.unreadableData(reason: "\(url.lastPathComponent): \(error.localizedDescription)")
        }

        return try load(fromData: data, origin: .local(url), configuration: configuration)
    }

    /// Decode bytes the consumer already holds.
    ///
    /// The shared path — `load(from:configuration:)` funnels into it — so a
    /// remote file opened over SFTP gets byte-identical detection to a local
    /// one. The ceiling is re-checked here because the caller may not have
    /// checked it, and because this is the only gate on the remote path.
    public static func load(
        fromData data: Data,
        origin: DocumentOrigin,
        configuration: GlassEditorConfiguration,
        openedDigest: ContentDigest? = nil,
        openedStat: RemoteStat? = nil
    ) throws -> DocumentSnapshot {
        let byteCount = UInt64(data.count)
        guard byteCount <= configuration.largeFileByteCeiling else {
            throw EditorError.fileTooLarge(bytes: byteCount, ceiling: configuration.largeFileByteCeiling)
        }

        let (content, encoding) = try EncodingDetector.decode(data)
        return DocumentSnapshot(
            content: content,
            encoding: encoding,
            lineEndings: LineEndingDetector.detect(in: content),
            origin: origin,
            openedDigest: openedDigest,
            openedStat: openedStat
        )
    }

    /// Wrap text that has no bytes behind it — a glassdb query tab, a scratch
    /// buffer, or content the consumer decoded itself.
    ///
    /// Encoding is `.utf8(hadBOM: false)` because that is what the text *is*
    /// once it is a Swift `String`; nothing is being claimed about a file. Line
    /// endings are still detected from the content, so pasting CRLF text into a
    /// scratch buffer keeps typing CRLF.
    public static func make(
        content: String,
        origin: DocumentOrigin,
        openedDigest: ContentDigest? = nil,
        openedStat: RemoteStat? = nil
    ) -> DocumentSnapshot {
        DocumentSnapshot(
            content: content,
            encoding: .utf8(hadBOM: false),
            lineEndings: LineEndingDetector.detect(in: content),
            origin: origin,
            openedDigest: openedDigest,
            openedStat: openedStat
        )
    }
}
