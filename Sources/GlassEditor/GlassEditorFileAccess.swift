//
//  GlassEditorFileAccess.swift
//  Glass Power Tools — GlassEditor
//
//  Everything the editor needs from the machine a project lives on, in one protocol.
//
//  **There is one path, not two.** A document's bytes come from a disk or from an SFTP session,
//  and after that single difference every step is the same one: `EncodingDetector` replays the
//  bytes' encoding at save, `LineEndingDetector` keeps a CRLF file CRLF, the language is guessed
//  from the name and then from the content, and `ConflictDetector` compares what the file looked
//  like when it was opened against what it looks like now. Writing that twice would be writing the
//  second one worse — the remote half would get the conflict check and the local half would not,
//  which is exactly backwards: a checkout, a build or another editor changes a local file just as
//  a colleague changes a remote one.
//
//  So this protocol is the only thing that knows where a project is, and it answers the four
//  questions the editor actually asks: what is in this folder, what is in this file, put this
//  back, and what does this file look like right now.
//
//  `RemoteStat` and `ContentDigest` are used for both machines despite their names. They are
//  already transport-agnostic — `RemoteDocumentSession`'s own documentation says the package never
//  performs the transfer — and a size and a modification time mean the same thing on a disk as
//  they do over SFTP.
//

import Foundation
import CryptoKit
import GlassEditorCore

@MainActor
public protocol GlassEditorFileAccess {
    /// One folder's entries, as tree nodes.
    func contents(ofDirectory path: String) async throws -> [GlassEditorProjectNode]
    /// The whole file. The editor reads documents entire — it is an editor, not a pager — and the
    /// digest that makes conflict detection exact is free once the bytes are in hand.
    func read(_ path: String) async throws -> Data
    /// Writes the file back, **only if it is still what the caller last saw**, and answers with
    /// what was actually committed.
    ///
    /// The expectation is not the same check `ConflictDetector` does before a save, and does not
    /// replace it. That one asks the user a question; this one closes the window between the
    /// question and the write — a file can change while the bytes are still going up, and an
    /// upload that verified nothing would land on top of it. `nil` expects nothing, which is what
    /// a brand-new file is.
    ///
    /// The returned stat is the new baseline. It is the committed file's own, not a hopeful
    /// re-`stat` afterwards, so the next check compares against what was written rather than
    /// against whatever the file became in the meantime. `nil` means the commit landed but could
    /// not be described, which costs precision and is still the truth.
    @discardableResult
    func write(_ data: Data, to path: String, expecting: RemoteStat?) async throws -> RemoteStat?
    /// Size and modification time as they are now, or nil when they could not be read. **Nil means
    /// "not observed", never "unchanged"** — `ConflictDetector` reports `.indeterminate` for it
    /// rather than guessing, and that distinction is the whole reason this returns an optional.
    func stat(_ path: String) async throws -> RemoteStat?
    /// Drops whatever this is holding open. A disk holds nothing; an SFTP session is a connection.
    func close() async
}

public extension GlassEditorFileAccess {
    func close() async {}

    /// SHA-256 of a file's bytes — tier 2 of the conflict check, and the tier that kills the
    /// false positives a coarse modification time produces.
    func digest(of data: Data) -> ContentDigest? {
        ContentDigest(bytes: Array(SHA256.hash(data: data)))
    }
}

/// This device's file system.
@MainActor
public struct GlassEditorLocalFileAccess: GlassEditorFileAccess {
    /// Kept as a spelling of `GlassEditorProject.skippedNames`, which both implementations share.
    public static var skipped: Set<String> { GlassEditorProject.skippedNames }

    public init() {}

    public func contents(ofDirectory path: String) async throws -> [GlassEditorProjectNode] {
        let url = URL(filePath: GlassEditorProject.normalized(path), directoryHint: .isDirectory)
        let entries = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        return GlassEditorProject.nodes(in: path, from: entries.map { entry in
            GlassEditorDirectoryEntry(
                name: entry.lastPathComponent,
                isDirectory: (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            )
        })
    }

    /// The most of a local file the editor reads (2026-10-12), the same as of a file on another
    /// machine (`GlassTerminalDirectoryLister.fileByteCeiling`): documents are read whole, into
    /// memory. A larger media file is shown from the disk without being read
    /// (`GlassEditorDocument.open`).
    public nonisolated static let byteCeiling = 64 * 1024 * 1024

    /// The file's bytes, read off the main actor — **a regular file only, and at most
    /// `byteCeiling`** (2026-10-12). The editor kit checked both (its pen-test finding M-4); this
    /// path, written after it, read any file whole on the main actor: a log or a video of several
    /// gigabytes went into memory while the window waited. A named pipe or a device was refused only
    /// by Foundation, which `Data(contentsOf:)` on macOS 27.2 does at once — as "you don't have
    /// permission", which it is not.
    public func read(_ path: String) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Self.readRegularFile(atPath: path, limit: Self.byteCeiling)
        }.value
    }

    /// A regular file's size and first `length` bytes, without reading the rest; off the main actor.
    public nonisolated static func head(atPath path: String,
                                        length: Int = GlassEditorFileKind.sniffLength) async throws -> (size: UInt64, head: Data) {
        try await Task.detached(priority: .userInitiated) {
            let (handle, size) = try openRegularFile(atPath: path)
            return (size, try handle.read(upToCount: length) ?? Data())
        }.value
    }

    /// Up to `limit` bytes of a regular file, or why not.
    nonisolated static func readRegularFile(atPath path: String, limit: Int) throws -> Data {
        let (handle, size) = try openRegularFile(atPath: path)
        let name = (path as NSString).lastPathComponent
        guard size <= UInt64(limit) else {
            throw GlassEditorReadRefusal.tooLarge(name: name, bytes: size, limit: UInt64(limit))
        }
        // One byte past the limit, so a file still growing cannot carry the read beyond it.
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else {
            throw GlassEditorReadRefusal.tooLarge(name: name, bytes: UInt64(data.count), limit: UInt64(limit))
        }
        return data
    }

    /// The file opened for reading, when it is a regular file. Opened without blocking, so a pipe
    /// with no writer cannot hold the call; then the *open* file is asked what it is, so nothing can
    /// be swapped in between a check and the read. Links are followed, as opening a file does.
    nonisolated static func openRegularFile(atPath path: String) throws -> (FileHandle, UInt64) {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw readError(errno, path: path) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = Darwin.stat()
        guard fstat(descriptor, &info) == 0 else { throw readError(errno, path: path) }
        guard info.st_mode & S_IFMT == S_IFREG else {
            throw GlassEditorReadRefusal.notAFile(name: (path as NSString).lastPathComponent,
                                                  what: GlassEditorReadRefusal.describe(mode: info.st_mode))
        }
        return (handle, UInt64(max(info.st_size, 0)))
    }

    /// The error `Data(contentsOf:)` would have thrown, so a missing or forbidden file reads as before.
    nonisolated static func readError(_ code: Int32, path: String) -> Error {
        let kind: CocoaError.Code = switch code {
        case ENOENT, ENOTDIR: .fileReadNoSuchFile
        case EACCES, EPERM: .fileReadNoPermission
        default: .fileReadUnknown
        }
        return CocoaError(kind, userInfo: [NSFilePathErrorKey: path,
                                           NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)])
    }

    @discardableResult
    public func write(_ data: Data, to path: String, expecting: RemoteStat?) async throws -> RemoteStat? {
        if let expecting, let now = try await stat(path),
           !Self.isStillTheSameFile(expecting: expecting, now: now) {
            throw GlassEditorWriteError.targetChanged((path as NSString).lastPathComponent)
        }
        // Through a temporary file and a rename, so an interrupted save cannot leave a truncated
        // file where a whole one was — and `AtomicSaver` carries the destination's POSIX mode onto
        // the replacement, so saving an executable leaves it executable.
        try AtomicSaver.writeAtomically(data, to: URL(filePath: path))
        return try await stat(path)
    }

    /// Whether two observations describe the same unchanged file.
    ///
    /// `ConflictDetector` rather than a second hand-written comparison: it is the one place that
    /// knows a field counts only when both sides carry it, and that nanoseconds alone prove
    /// nothing. An unreadable *now* is not evidence of change, so it does not block the write —
    /// the question before the save is where an unknown is surfaced to the user.
    static func isStillTheSameFile(expecting: RemoteStat, now: RemoteStat) -> Bool {
        let session = RemoteDocumentSession(ref: RemoteDocumentRef(connectionID: UUID(), host: "",
                                                                   path: ""),
                                            openedStat: expecting)
        return ConflictDetector.classify(session: session, currentStat: now,
                                         currentDigest: nil, localDirty: false) != .remoteChangedLocalClean
    }

    public func stat(_ path: String) async throws -> RemoteStat? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value
        let modified = attributes[.modificationDate] as? Date
        guard size != nil || modified != nil else { return nil }
        let interval = modified?.timeIntervalSince1970
        return RemoteStat(
            size: size,
            modificationSeconds: interval.map { Int64($0.rounded(.down)) },
            // The sub-second part, which is what tells two saves inside the same second apart —
            // the case a seconds-only comparison misses.
            modificationNanoseconds: interval.map { Int64(($0 - $0.rounded(.down)) * 1_000_000_000) }
        )
    }
}

/// A machine reached over its own SSH service.
///
/// **The transport is supplied, not performed here.** SFTP belongs to the capability that owns the
/// connection, the trust prompt and the session; the editor does not import it and must not learn
/// to. That is also what makes a remote project testable without a server.
@MainActor
public struct GlassEditorRemoteFileAccess: GlassEditorFileAccess {
    public typealias Listing = @MainActor (String) async throws -> [GlassEditorDirectoryEntry]
    public typealias Read = @MainActor (String) async throws -> Data
    public typealias Write = @MainActor (Data, String, RemoteStat?) async throws -> RemoteStat?
    public typealias Stat = @MainActor (String) async throws -> RemoteStat?

    private let listing: Listing
    private let reader: Read
    private let writer: Write
    private let stater: Stat
    private let onClose: @MainActor () async -> Void

    public init(listing: @escaping Listing,
                read: @escaping Read,
                write: @escaping Write,
                stat: @escaping Stat,
                onClose: @escaping @MainActor () async -> Void = {}) {
        self.listing = listing
        self.reader = read
        self.writer = write
        self.stater = stat
        self.onClose = onClose
    }

    public func contents(ofDirectory path: String) async throws -> [GlassEditorProjectNode] {
        let base = GlassEditorProject.normalized(path)
        return GlassEditorProject.nodes(in: base, from: try await listing(base))
    }

    public func read(_ path: String) async throws -> Data { try await reader(path) }
    @discardableResult
    public func write(_ data: Data, to path: String, expecting: RemoteStat?) async throws -> RemoteStat? {
        try await writer(data, path, expecting)
    }
    public func stat(_ path: String) async throws -> RemoteStat? { try await stater(path) }
    public func close() async { await onClose() }
}

/// What can go wrong on the way to the file, in words rather than errno.
public enum GlassEditorWriteError: LocalizedError, Equatable {
    /// The file changed between the check and the commit. Nothing was written.
    case targetChanged(String)
    /// The write was sent and the connection did not say whether it landed. **The file may or may
    /// not have been replaced**, which is the one outcome that must never be reported as either.
    case commitOutcomeUnknown(String)

    public var errorDescription: String? {
        switch self {
        case .targetChanged(let name):
            "\(name) changed while it was being saved, so nothing was written. Save again to see what it looks like now."
        case .commitOutcomeUnknown(let name):
            "The connection dropped while \(name) was being saved, and the machine did not say whether it landed. Re-open it to see which version is there."
        }
    }
}

/// What a check before saving concluded, and what the file looked like while it concluded it.
public struct GlassEditorSaveCheck: Sendable {
    public let state: ConflictState
    /// The observation the decision was made against — what the write then expects to replace.
    public let observed: RemoteStat?

    public init(state: ConflictState, observed: RemoteStat?) {
        self.state = state
        self.observed = observed
    }
}

/// A save that stopped to ask. Carries what the window needs to say and nothing else.
public struct GlassEditorConflict: Identifiable, Sendable {
    public let id = UUID()
    public let documentID: UUID
    public let name: String
    /// The machine, when it is not this one — the difference between "somebody edited this" and
    /// "something on your Mac edited this".
    public let machine: String?
    public let state: ConflictState
    /// What the file was when the question was asked. Answering "save anyway" authorises replacing
    /// *that* — if it changes again while the question is on screen, the write refuses rather than
    /// silently landing on a third version.
    public let observed: RemoteStat?

    public init(documentID: UUID, name: String, machine: String?, state: ConflictState,
                observed: RemoteStat?) {
        self.documentID = documentID
        self.name = name
        self.machine = machine
        self.state = state
        self.observed = observed
    }

    /// What happened, in the words a person would use.
    public var explanation: String {
        let where_ = machine.map { "on \($0)" } ?? GlassEditorPlace.thisDevice
        switch state {
        case .remoteChangedLocalDirty:
            return "\(name) has changed \(where_) since you opened it, and you have unsaved edits. Saving replaces what is there now."
        case .remoteChangedLocalClean:
            return "\(name) has changed \(where_) since you opened it."
        case .indeterminate:
            return "\(name) could not be checked \(where_) — it may have changed since you opened it. Saving replaces whatever is there now."
        case .noConflict:
            return "\(name) is unchanged \(where_)."
        }
    }
}

/// How the device the editor runs on is named in text: "this Mac" was said on every platform.
enum GlassEditorPlace {
    static var thisDevice: String {
        #if os(macOS)
        "on this Mac"
        #else
        "on this device"
        #endif
    }
}

extension String {
    /// "on this Mac" → "On this Mac".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Why a project on another machine cannot be opened. The editor reaches another machine only
/// through its Terminal service; the message used to be the port-forwarding one.
public enum GlassEditorRemoteAccessError: LocalizedError, Equatable {
    case machineNotInLibrary
    case noTerminalService

    public var errorDescription: String? {
        switch self {
        case .machineNotInLibrary:
            "The machine this project is on is no longer in your library. Add it again, or remove the project."
        case .noTerminalService:
            "Files on another machine are reached through its Terminal service, and this machine has none. Add a Terminal service to it in the library, then open the project again."
        }
    }
}
