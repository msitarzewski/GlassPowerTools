import Foundation
@preconcurrency import Citadel
import Logging
import NIOCore

/// File attributes without Citadel types, so the editor and the browser share one model.
public struct SFTPAttributes: Sendable, Hashable {
    public var size: UInt64?
    public var permissions: UInt32?
    public var userID: UInt32?
    public var groupID: UInt32?
    public var accessTime: Date?
    public var modificationTime: Date?

    public init(size: UInt64? = nil, permissions: UInt32? = nil, userID: UInt32? = nil, groupID: UInt32? = nil, accessTime: Date? = nil, modificationTime: Date? = nil) {
        self.size = size
        self.permissions = permissions
        self.userID = userID
        self.groupID = groupID
        self.accessTime = accessTime
        self.modificationTime = modificationTime
    }

    /// POSIX file type bits (S_IFMT).
    public var typeBits: UInt32? { permissions.map { $0 & 0o170000 } }
    public var isDirectory: Bool { typeBits == 0o040000 }
    public var isSymbolicLink: Bool { typeBits == 0o120000 }
    public var isRegularFile: Bool { typeBits == 0o100000 }
    public var mode: UInt32? { permissions.map { $0 & 0o7777 } }

    init(_ attributes: SFTPFileAttributes) {
        size = attributes.size
        permissions = attributes.permissions
        userID = attributes.uidgid?.userId
        groupID = attributes.uidgid?.groupId
        accessTime = attributes.accessModificationTime?.accessTime
        modificationTime = attributes.accessModificationTime?.modificationTime
    }
}

public struct SFTPEntry: Sendable, Hashable, Identifiable {
    public var name: String
    /// The directory the entry was listed from, joined with its name.
    public var path: String
    /// The server's `ls -l`-style line, when it sends one.
    public var longName: String
    public var attributes: SFTPAttributes
    public var id: String { path }

    /// Server-supplied names are untrusted (security review S5). A name is safe to use as a
    /// local file name or to join onto a directory only when it is a single path component:
    /// non-empty, not `.` or `..`, and free of `/` and NUL. Consumers must check this before
    /// writing locally or building paths from `name`; `path` is computed regardless so the
    /// entry can still be shown and deleted.
    public var hasSafeName: Bool { SFTPEntry.isSafeName(name) }

    public static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !isSelfOrParent(name) && !name.contains("/") && !name.contains("\0")
    }

    /// OpenSSH's `sftp-server` lists `.` and `..` like `ls -a`; they are never entries a consumer
    /// wants (verified against OpenSSH 10.2 on 2026-09-11), so `list` omits them at the engine
    /// boundary rather than in every browser and editor.
    public static func isSelfOrParent(_ name: String) -> Bool {
        name == "." || name == ".."
    }

    public init(name: String, path: String, longName: String = "", attributes: SFTPAttributes) {
        self.name = name
        self.path = path
        self.longName = longName
        self.attributes = attributes
    }
}

/// The extensions the server advertised at SFTP init (name → version), with the three OpenSSH
/// extensions consumers decide on. Pure data so consumers and tests can reason about it.
public struct SFTPServerExtensions: Sendable, Hashable {
    public static let posixRename = "posix-rename@openssh.com"
    public static let hardLink = "hardlink@openssh.com"
    public static let fsync = "fsync@openssh.com"

    public let raw: [String: String]
    public init(_ raw: [String: String] = [:]) { self.raw = raw }

    public func version(of name: String) -> String? { raw[name] }
    /// True when the server advertises `name`; with `version`, only that exact version.
    public func supports(_ name: String, version: String? = nil) -> Bool {
        guard let advertised = raw[name] else { return false }
        guard let version else { return true }
        return advertised == version
    }
    public var supportsPOSIXRename: Bool { supports(Self.posixRename, version: "1") }
    public var supportsHardLink: Bool { supports(Self.hardLink, version: "1") }
    public var supportsFSync: Bool { supports(Self.fsync, version: "1") }
}

/// Attributes to change with one SETSTAT. Only non-nil fields are sent. SFTP v3 carries access
/// and modification time together (`acmodtime`), so both must be given to change either; use
/// `setTimes(at:accessed:modified:)` to fill the other side from the file's current value.
public struct SFTPAttributeChanges: Sendable, Hashable {
    public var permissions: UInt32?
    public var size: UInt64?
    public var accessed: Date?
    public var modified: Date?
    public init(permissions: UInt32? = nil, size: UInt64? = nil, accessed: Date? = nil, modified: Date? = nil) {
        self.permissions = permissions
        self.size = size
        self.accessed = accessed
        self.modified = modified
    }
    public var isEmpty: Bool { permissions == nil && size == nil && accessed == nil && modified == nil }
    public var hasPartialTimes: Bool { (accessed == nil) != (modified == nil) }

    var citadelAttributes: SFTPFileAttributes {
        var attributes = SFTPFileAttributes.none
        attributes.permissions = permissions
        attributes.size = size
        if let accessed, let modified {
            attributes.accessModificationTime = .init(accessTime: accessed, modificationTime: modified)
        }
        return attributes
    }
}

public struct SFTPOpenMode: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let read = SFTPOpenMode(rawValue: 1 << 0)
    public static let write = SFTPOpenMode(rawValue: 1 << 1)
    public static let append = SFTPOpenMode(rawValue: 1 << 2)
    public static let create = SFTPOpenMode(rawValue: 1 << 3)
    public static let truncate = SFTPOpenMode(rawValue: 1 << 4)
    /// Fail if the file exists (create must also be set).
    public static let exclusive = SFTPOpenMode(rawValue: 1 << 5)

    var citadelFlags: SFTPOpenFileFlags {
        var flags: SFTPOpenFileFlags = []
        if contains(.read) { flags.insert(.read) }
        if contains(.write) { flags.insert(.write) }
        if contains(.append) { flags.insert(.append) }
        if contains(.create) { flags.insert(.create) }
        if contains(.truncate) { flags.insert(.truncate) }
        if contains(.exclusive) { flags.insert(.forceCreate) }
        return flags
    }
}

/// An open remote file. Offsets are absolute; reads return fewer bytes at end of file and
/// empty data at or past it.
public protocol SFTPFileHandle: Sendable {
    func read(from offset: UInt64, length: UInt32) async throws -> Data
    func write(_ data: Data, at offset: UInt64) async throws
    func attributes() async throws -> SFTPAttributes
    /// Flushes the file to stable storage (`fsync@openssh.com`); throws
    /// `SFTPSessionError.extensionUnsupported` when the server lacks it.
    func synchronize() async throws
    func close() async throws
}

/// The SFTP surface every consumer uses: glas.sh's browser today, the editor in Stage 5.
/// All operations honour task cancellation.
public protocol SFTPSession: Sendable {
    /// The directory's entries without the server's `.` and `..` references.
    func list(_ path: String) async throws -> [SFTPEntry]
    func attributes(at path: String, followSymlinks: Bool) async throws -> SFTPAttributes
    func realPath(_ path: String) async throws -> String
    func open(_ path: String, mode: SFTPOpenMode, permissions: UInt32?) async throws -> any SFTPFileHandle
    func createDirectory(_ path: String) async throws
    func removeFile(_ path: String) async throws
    func removeDirectory(_ path: String) async throws
    func rename(_ path: String, to newPath: String) async throws
    /// Atomic rename that replaces an existing destination (`posix-rename@openssh.com`).
    func posixRename(_ path: String, to newPath: String) async throws
    /// `hardlink@openssh.com`.
    func hardLink(_ path: String, to newPath: String) async throws
    func setAttributes(_ changes: SFTPAttributeChanges, at path: String) async throws
    /// What the server advertised at init; decides which of the above are available.
    var serverExtensions: SFTPServerExtensions { get async }
    var isActive: Bool { get async }
    func close() async throws
}

public extension SFTPSession {
    /// The chunk size glas.sh's browser streamed with (SFTPBrowserView.swift:3939 and siblings).
    static var defaultChunkLength: UInt32 { 262_144 }

    func attributes(at path: String) async throws -> SFTPAttributes {
        try await attributes(at: path, followSymlinks: true)
    }

    func open(_ path: String, mode: SFTPOpenMode) async throws -> any SFTPFileHandle {
        try await open(path, mode: mode, permissions: nil)
    }

    func setPermissions(_ permissions: UInt32, at path: String) async throws {
        try await setAttributes(SFTPAttributeChanges(permissions: permissions), at: path)
    }

    /// Sets either or both times. When only one is given, the other is read from the file first
    /// because the protocol sends them as a pair.
    func setTimes(at path: String, accessed: Date? = nil, modified: Date? = nil) async throws {
        guard accessed != nil || modified != nil else { return }
        var accessed = accessed, modified = modified
        if accessed == nil || modified == nil {
            let current = try await attributes(at: path, followSymlinks: true)
            accessed = accessed ?? current.accessTime ?? current.modificationTime ?? Date()
            modified = modified ?? current.modificationTime ?? current.accessTime ?? Date()
        }
        try await setAttributes(SFTPAttributeChanges(accessed: accessed, modified: modified), at: path)
    }

    /// Replaces `destination` with `path` atomically where the server supports it, otherwise by
    /// removing the destination first and renaming — the choice every consumer used to make
    /// by hand.
    func replace(_ destination: String, with path: String) async throws {
        if await serverExtensions.supportsPOSIXRename {
            try await posixRename(path, to: destination)
        } else {
            try? await removeFile(destination)
            try await rename(path, to: destination)
        }
    }

    /// Reads a whole file in chunks, stopping at `maxBytes` and on cancellation.
    func readFile(at path: String, maxBytes: Int = .max) async throws -> Data {
        let handle = try await open(path, mode: .read)
        do {
            var result = Data()
            var offset: UInt64 = 0
            while true {
                try Task.checkCancellation()
                let chunk = try await handle.read(from: offset, length: Self.defaultChunkLength)
                if chunk.isEmpty { break }
                guard result.count + chunk.count <= maxBytes else { throw SFTPSessionError.fileTooLarge(limit: maxBytes) }
                result.append(chunk)
                offset += UInt64(chunk.count)
                if chunk.count < Int(Self.defaultChunkLength) { break }
            }
            try await handle.close()
            return result
        } catch {
            try? await handle.close()
            throw error
        }
    }

    /// Writes `data` to `path`, creating or truncating it, in chunks.
    func writeFile(_ data: Data, to path: String, permissions: UInt32? = nil) async throws {
        let handle = try await open(path, mode: [.write, .create, .truncate], permissions: permissions)
        do {
            var offset: UInt64 = 0
            var index = data.startIndex
            while index < data.endIndex {
                try Task.checkCancellation()
                let end = data.index(index, offsetBy: Int(Self.defaultChunkLength), limitedBy: data.endIndex) ?? data.endIndex
                let chunk = data[index..<end]
                try await handle.write(Data(chunk), at: offset)
                offset += UInt64(chunk.count)
                index = end
            }
            try await handle.close()
        } catch {
            try? await handle.close()
            throw error
        }
    }
}

public enum SFTPSessionError: Error, Sendable, Equatable {
    case fileTooLarge(limit: Int)
    case closed
    /// The server did not advertise the named extension.
    case extensionUnsupported(String)
    /// `SFTPAttributeChanges` carried one time without the other.
    case partialTimes
    /// The server answered the request with a status other than OK (SSH_FXP_STATUS), and what it
    /// said with it. Citadel throws its own status type, which reached the person as "Citadel.
    /// SFTPMessage.Status error 1" (the owner, 2026-10-15, saving a new file on the headset).
    case refused(SFTPRefusal, serverMessage: String)

    /// Whether `error` is a server saying the path is not there.
    public static func isMissingPath(_ error: any Error) -> Bool {
        if case .refused(.noSuchFile, _)? = error as? SFTPSessionError { return true }
        return false
    }
}

/// Why an SFTP server refused a request: the status codes of SFTP version 3
/// (draft-ietf-secsh-filexfer-02 §7), which OpenSSH speaks.
public enum SFTPRefusal: Sendable, Equatable {
    case endOfFile
    case noSuchFile
    case permissionDenied
    case failure
    case badMessage
    case noConnection
    case connectionLost
    case unsupported
    case other(UInt32)
}

/// In words, and what to do (the owner, 2026-09-16: an error "should suggest that, not be so …
/// technical"). The server's own text goes to the log, not here: OpenSSH says no more than the
/// status does.
extension SFTPSessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let limit):
            "The file is larger than \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)), more than can be opened here."
        case .closed:
            "The connection to the machine has closed. Try again to open a new one."
        case .extensionUnsupported:
            "The machine's SFTP server can't do this. A recent OpenSSH can."
        case .partialTimes:
            "A file's times can only be set together."
        case .refused(let refusal, _):
            switch refusal {
            case .noSuchFile: "That file or folder isn't there. It may have been moved, renamed or deleted."
            case .permissionDenied: "The machine doesn't let this account do that. Check the file's or folder's permissions."
            case .endOfFile: "The file ended sooner than expected. It may be changing; try again."
            case .noConnection, .connectionLost: "The connection to the machine was lost. Try again to open a new one."
            case .unsupported: "The machine's SFTP server can't do this."
            case .failure, .badMessage, .other: "The machine refused without saying why. Check that there is room on its disk and that the folder can be written to."
            }
        }
    }
}

extension SFTPRefusal {
    init(_ code: SFTPStatusCode) {
        switch code {
        case .ok: self = .other(0)
        case .eof: self = .endOfFile
        case .noSuchFile: self = .noSuchFile
        case .permissionDenied: self = .permissionDenied
        case .failure: self = .failure
        case .badMessage: self = .badMessage
        case .noConnection: self = .noConnection
        case .connectionLost: self = .connectionLost
        case .unsupportedOperation: self = .unsupported
        case .unknown(let raw): self = .other(raw)
        }
    }
}

// MARK: - Citadel-backed implementation

/// Wraps Citadel's `SFTPClient`. Its logger is set to `.error` because Citadel's info and
/// debug messages include full remote paths and handles (glas.sh `openSFTPClient`).
final class CitadelSFTPSession: SFTPSession {
    private let client: SFTPClient

    init(client: SFTPClient) { self.client = client }

    static func open(over ssh: SSHClient) async throws -> CitadelSFTPSession {
        var logger = Logging.Logger(label: "com.glasspowertools.sftp.private")
        logger.logLevel = .error
        return CitadelSFTPSession(client: try await ssh.openSFTP(logger: logger))
    }

    var isActive: Bool { get async { client.isActive } }

    func list(_ path: String) async throws -> [SFTPEntry] {
        try Task.checkCancellation()
        let names = try await Self.translatingErrors { try await client.listDirectory(atPath: path) }
        let base = path.hasSuffix("/") ? path : path + "/"
        return names.flatMap(\.components)
            .filter { !SFTPEntry.isSelfOrParent($0.filename) }
            .map { component in
            SFTPEntry(
                name: component.filename,
                path: base + component.filename,
                longName: component.longname,
                attributes: SFTPAttributes(component.attributes)
            )
        }
    }

    func attributes(at path: String, followSymlinks: Bool) async throws -> SFTPAttributes {
        try Task.checkCancellation()
        let attributes = try await Self.translatingErrors {
            if followSymlinks { return try await client.getAttributes(at: path) }
            return try await client.getLinkAttributes(at: path)
        }
        return SFTPAttributes(attributes)
    }

    func realPath(_ path: String) async throws -> String {
        try Task.checkCancellation()
        return try await Self.translatingErrors { try await client.getRealPath(atPath: path) }
    }

    func open(_ path: String, mode: SFTPOpenMode, permissions: UInt32?) async throws -> any SFTPFileHandle {
        try Task.checkCancellation()
        var attributes = SFTPFileAttributes.none
        if let permissions { attributes.permissions = permissions }
        let file = try await Self.translatingErrors {
            try await client.openFile(filePath: path, flags: mode.citadelFlags, attributes: attributes)
        }
        return CitadelSFTPFileHandle(file: file)
    }

    func createDirectory(_ path: String) async throws {
        try Task.checkCancellation()
        try await Self.translatingErrors { try await client.createDirectory(atPath: path) }
    }

    func removeFile(_ path: String) async throws {
        try Task.checkCancellation()
        try await Self.translatingErrors { try await client.remove(at: path) }
    }

    func removeDirectory(_ path: String) async throws {
        try Task.checkCancellation()
        try await Self.translatingErrors { try await client.rmdir(at: path) }
    }

    func rename(_ path: String, to newPath: String) async throws {
        try Task.checkCancellation()
        try await Self.translatingErrors { try await client.rename(at: path, to: newPath) }
    }

    func posixRename(_ path: String, to newPath: String) async throws {
        try Task.checkCancellation()
        try await Self.translatingErrors { try await client.posixRename(at: path, to: newPath) }
    }

    func hardLink(_ path: String, to newPath: String) async throws {
        try Task.checkCancellation()
        try await Self.translatingErrors { try await client.hardLink(at: path, to: newPath) }
    }

    func setAttributes(_ changes: SFTPAttributeChanges, at path: String) async throws {
        try Task.checkCancellation()
        guard !changes.hasPartialTimes else { throw SFTPSessionError.partialTimes }
        guard !changes.isEmpty else { return }
        try await Self.translatingErrors { try await client.setAttributes(at: path, to: changes.citadelAttributes) }
    }

    var serverExtensions: SFTPServerExtensions {
        get async { SFTPServerExtensions(client.serverExtensions) }
    }

    func close() async throws {
        try await client.close()
    }

    /// Citadel's errors as this module's: a missing extension, and a server's refusal with its
    /// status, so nothing above sees a Citadel type and every refusal has words.
    static func translatingErrors<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() }
        catch SFTPError.unsupportedExtension(let name) { throw SFTPSessionError.extensionUnsupported(name) }
        catch let status as SFTPMessage.Status {
            throw SFTPSessionError.refused(SFTPRefusal(status.errorCode), serverMessage: status.message)
        }
    }
}

/// `SFTPFile` is not `Sendable`; every call on it hops to Citadel's event loop, and one handle is
/// used by one task at a time (as glas.sh did).
final class CitadelSFTPFileHandle: SFTPFileHandle, @unchecked Sendable {
    private let file: SFTPFile
    init(file: SFTPFile) { self.file = file }

    func read(from offset: UInt64, length: UInt32) async throws -> Data {
        try Task.checkCancellation()
        let buffer = try await CitadelSFTPSession.translatingErrors { try await file.read(from: offset, length: length) }
        return Data(buffer.readableBytesView)
    }

    func write(_ data: Data, at offset: UInt64) async throws {
        try Task.checkCancellation()
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        try await CitadelSFTPSession.translatingErrors { try await file.write(buffer, at: offset) }
    }

    func attributes() async throws -> SFTPAttributes {
        SFTPAttributes(try await CitadelSFTPSession.translatingErrors { try await file.readAttributes() })
    }

    func synchronize() async throws {
        try Task.checkCancellation()
        try await CitadelSFTPSession.translatingErrors { try await file.synchronize() }
    }

    func close() async throws {
        try await file.close()
    }
}
