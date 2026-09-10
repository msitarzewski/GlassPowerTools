import Foundation
import Citadel
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

    public init(name: String, path: String, longName: String = "", attributes: SFTPAttributes) {
        self.name = name
        self.path = path
        self.longName = longName
        self.attributes = attributes
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
    func close() async throws
}

/// The SFTP surface every consumer uses: glas.sh's browser today, the editor in Stage 5.
/// All operations honour task cancellation.
public protocol SFTPSession: Sendable {
    func list(_ path: String) async throws -> [SFTPEntry]
    func attributes(at path: String, followSymlinks: Bool) async throws -> SFTPAttributes
    func realPath(_ path: String) async throws -> String
    func open(_ path: String, mode: SFTPOpenMode, permissions: UInt32?) async throws -> any SFTPFileHandle
    func createDirectory(_ path: String) async throws
    func removeFile(_ path: String) async throws
    func removeDirectory(_ path: String) async throws
    func rename(_ path: String, to newPath: String) async throws
    func setPermissions(_ permissions: UInt32, at path: String) async throws
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
        let names = try await client.listDirectory(atPath: path)
        let base = path.hasSuffix("/") ? path : path + "/"
        return names.flatMap(\.components).map { component in
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
        let attributes = followSymlinks
            ? try await client.getAttributes(at: path)
            : try await client.getLinkAttributes(at: path)
        return SFTPAttributes(attributes)
    }

    func realPath(_ path: String) async throws -> String {
        try Task.checkCancellation()
        return try await client.getRealPath(atPath: path)
    }

    func open(_ path: String, mode: SFTPOpenMode, permissions: UInt32?) async throws -> any SFTPFileHandle {
        try Task.checkCancellation()
        var attributes = SFTPFileAttributes.none
        if let permissions { attributes.permissions = permissions }
        let file = try await client.openFile(filePath: path, flags: mode.citadelFlags, attributes: attributes)
        return CitadelSFTPFileHandle(file: file)
    }

    func createDirectory(_ path: String) async throws {
        try Task.checkCancellation()
        try await client.createDirectory(atPath: path)
    }

    func removeFile(_ path: String) async throws {
        try Task.checkCancellation()
        try await client.remove(at: path)
    }

    func removeDirectory(_ path: String) async throws {
        try Task.checkCancellation()
        try await client.rmdir(at: path)
    }

    func rename(_ path: String, to newPath: String) async throws {
        try Task.checkCancellation()
        try await client.rename(at: path, to: newPath)
    }

    func setPermissions(_ permissions: UInt32, at path: String) async throws {
        try Task.checkCancellation()
        var attributes = SFTPFileAttributes.none
        attributes.permissions = permissions
        try await client.setAttributes(at: path, to: attributes)
    }

    func close() async throws {
        try await client.close()
    }
}

/// `SFTPFile` is not `Sendable`; every call on it hops to Citadel's event loop, and one handle is
/// used by one task at a time (as glas.sh did).
final class CitadelSFTPFileHandle: SFTPFileHandle, @unchecked Sendable {
    private let file: SFTPFile
    init(file: SFTPFile) { self.file = file }

    func read(from offset: UInt64, length: UInt32) async throws -> Data {
        try Task.checkCancellation()
        let buffer = try await file.read(from: offset, length: length)
        return Data(buffer.readableBytesView)
    }

    func write(_ data: Data, at offset: UInt64) async throws {
        try Task.checkCancellation()
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        try await file.write(buffer, at: offset)
    }

    func attributes() async throws -> SFTPAttributes {
        SFTPAttributes(try await file.readAttributes())
    }

    func close() async throws {
        try await file.close()
    }
}
