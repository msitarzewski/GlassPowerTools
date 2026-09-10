//
//  SFTPCompatibility.swift
//  Glass Power Tools — GlassTerminal
//
//  The SFTP client surface glas.sh's browser was written against (Citadel's SFTPClient, SFTPFile,
//  SFTPPathComponent, SFTPFileAttributes, SFTPOpenFileFlags, SFTPError), reproduced as terminal-
//  internal types over the shared engine's `SFTPSession` / `SFTPFileHandle`. The browser keeps its
//  code; the engine keeps the protocol. Server extensions (hardlink, posix-rename, fsync), file
//  times and fsync all go through the engine's SFTPSession / SFTPFileHandle API.
//

import Foundation
import GlassSSHTransport
import NIOCore

nonisolated enum SFTPError: Error, Equatable {
    case missingResponse
    case invalidResponse
    case unsupported(String)
}

nonisolated enum SFTPFileType: Equatable, Sendable {
    case regular, directory, symbolicLink, characterDevice, blockDevice, fifo, socket
    case unknown(UInt32)
}

typealias SFTPOpenFileFlags = SFTPOpenMode
nonisolated extension SFTPOpenMode {
    static let forceCreate = SFTPOpenMode.exclusive
}

nonisolated struct SFTPFileAttributes: Sendable, Hashable {
    struct Flags: OptionSet, Hashable, Sendable {
        var rawValue: UInt32
        static let size = Flags(rawValue: 0x1)
        static let uidgid = Flags(rawValue: 0x2)
        static let permissions = Flags(rawValue: 0x4)
        static let acmodtime = Flags(rawValue: 0x8)
    }
    struct UserGroupId: Sendable, Hashable { let userId: UInt32; let groupId: UInt32 }
    struct AccessModificationTime: Sendable, Hashable {
        let accessTime: Date
        let modificationTime: Date
        init(accessTime: Date, modificationTime: Date) { self.accessTime = accessTime; self.modificationTime = modificationTime }
    }

    var size: UInt64?
    var uidgid: UserGroupId?
    var permissions: UInt32?
    var accessModificationTime: AccessModificationTime?

    static let none = SFTPFileAttributes()

    init(size: UInt64? = nil, uidgid: UserGroupId? = nil, permissions: UInt32? = nil,
         accessModificationTime: AccessModificationTime? = nil) {
        self.size = size; self.uidgid = uidgid; self.permissions = permissions
        self.accessModificationTime = accessModificationTime
    }

    init(_ attributes: SFTPAttributes) {
        size = attributes.size
        permissions = attributes.permissions
        if let uid = attributes.userID, let gid = attributes.groupID { uidgid = UserGroupId(userId: uid, groupId: gid) }
        if let access = attributes.accessTime, let modification = attributes.modificationTime {
            accessModificationTime = AccessModificationTime(accessTime: access, modificationTime: modification)
        }
    }

    var flags: Flags {
        var flags: Flags = []
        if size != nil { flags.insert(.size) }
        if uidgid != nil { flags.insert(.uidgid) }
        if permissions != nil { flags.insert(.permissions) }
        if accessModificationTime != nil { flags.insert(.acmodtime) }
        return flags
    }

    var fileType: SFTPFileType? {
        guard let permissions else { return nil }
        switch permissions & 0o170000 {
        case 0o100000: return .regular
        case 0o040000: return .directory
        case 0o120000: return .symbolicLink
        case 0o020000: return .characterDevice
        case 0o060000: return .blockDevice
        case 0o010000: return .fifo
        case 0o140000: return .socket
        case let value: return .unknown(value)
        }
    }
    var isRegularFile: Bool { fileType == .regular }

    /// The engine's change set for `setstat`: permissions and both times, as the browser sets them.
    var changes: SFTPAttributeChanges {
        SFTPAttributeChanges(
            permissions: permissions,
            size: nil,
            accessed: accessModificationTime?.accessTime,
            modified: accessModificationTime?.modificationTime
        )
    }
}

nonisolated struct SFTPPathComponent: Sendable, Hashable {
    let filename: String
    let longname: String
    let attributes: SFTPFileAttributes

    init(_ entry: SFTPEntry) {
        filename = entry.name
        longname = entry.longName
        attributes = SFTPFileAttributes(entry.attributes)
    }
}

/// One listing, as Citadel returned it: the browser flattens `.components`.
nonisolated struct SFTPDirectoryListing: Sendable {
    let components: [SFTPPathComponent]
}

nonisolated final class SFTPFile: @unchecked Sendable {
    static let maximumPipelinedReadCount = 8
    struct ReadRequest: Sendable {
        let offset: UInt64
        let length: UInt32
        init(offset: UInt64, length: UInt32) { self.offset = offset; self.length = length }
    }

    private let session: any SFTPSession
    private let handle: any SFTPFileHandle
    let path: String

    init(session: any SFTPSession, handle: any SFTPFileHandle, path: String) {
        self.session = session; self.handle = handle; self.path = path
    }

    func read(from offset: UInt64 = 0, length: UInt32 = .max) async throws -> ByteBuffer {
        ByteBuffer(bytes: try await handle.read(from: offset, length: length))
    }

    /// Ordered results for a batch of reads, issued concurrently as the browser expects.
    func read(_ requests: [ReadRequest]) async throws -> [ByteBuffer] {
        guard requests.count <= Self.maximumPipelinedReadCount else { throw SFTPError.invalidResponse }
        return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask { (index, try await self.handle.read(from: request.offset, length: request.length)) }
            }
            var results = [Data?](repeating: nil, count: requests.count)
            for try await (index, data) in group { results[index] = data }
            return results.map { ByteBuffer(bytes: $0 ?? Data()) }
        }
    }

    func readAll() async throws -> ByteBuffer {
        var result = Data(); var offset: UInt64 = 0
        while true {
            let chunk = try await handle.read(from: offset, length: 262_144)
            if chunk.isEmpty { break }
            result.append(chunk); offset += UInt64(chunk.count)
            if chunk.count < 262_144 { break }
        }
        return ByteBuffer(bytes: result)
    }

    func write(_ data: ByteBuffer, at offset: UInt64 = 0) async throws {
        try await handle.write(Data(data.readableBytesView), at: offset)
    }

    func readAttributes() async throws -> SFTPFileAttributes {
        SFTPFileAttributes(try await handle.attributes())
    }

    func setAttributes(to attributes: SFTPFileAttributes) async throws {
        try await session.setAttributes(attributes.changes, at: path)
    }

    func synchronize() async throws { try await handle.synchronize() }

    func close() async throws { try await handle.close() }
}

nonisolated final class SFTPClient: @unchecked Sendable {
    private let session: any SFTPSession
    private let extensions: SFTPServerExtensions

    /// `extensions` is read once when the client is created: the browser asks synchronously.
    init(session: any SFTPSession, extensions: SFTPServerExtensions) {
        self.session = session
        self.extensions = extensions
    }

    var isActive: Bool { get async { await session.isActive } }

    func supportsExtension(_ name: String, version: String? = nil) -> Bool {
        extensions.supports(name, version: version)
    }

    func listDirectory(atPath path: String) async throws -> [SFTPDirectoryListing] {
        [SFTPDirectoryListing(components: try await session.list(path).map(SFTPPathComponent.init))]
    }

    func getAttributes(at filePath: String) async throws -> SFTPFileAttributes {
        SFTPFileAttributes(try await session.attributes(at: filePath, followSymlinks: true))
    }

    func getLinkAttributes(at filePath: String) async throws -> SFTPFileAttributes {
        SFTPFileAttributes(try await session.attributes(at: filePath, followSymlinks: false))
    }

    func getRealPath(atPath path: String) async throws -> String {
        try await session.realPath(path)
    }

    func openFile(filePath: String, flags: SFTPOpenFileFlags, attributes: SFTPFileAttributes = .none) async throws -> SFTPFile {
        let handle = try await session.open(filePath, mode: flags, permissions: attributes.permissions)
        return SFTPFile(session: session, handle: handle, path: filePath)
    }

    func createDirectory(atPath path: String) async throws { try await session.createDirectory(path) }
    func remove(at path: String) async throws { try await session.removeFile(path) }
    func rmdir(at path: String) async throws { try await session.removeDirectory(path) }
    func rename(at oldPath: String, to newPath: String) async throws { try await session.rename(oldPath, to: newPath) }

    func hardLink(at oldPath: String, to newPath: String) async throws {
        try await session.hardLink(oldPath, to: newPath)
    }

    func posixRename(at oldPath: String, to newPath: String) async throws {
        try await session.posixRename(oldPath, to: newPath)
    }

    func setAttributes(at filePath: String, to attributes: SFTPFileAttributes) async throws {
        try await session.setAttributes(attributes.changes, at: filePath)
    }

    func close() async throws { try await session.close() }
}
