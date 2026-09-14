import Foundation
import GlassConnectionKit
import Darwin

public actor DesktopRepository {
    private struct Document: Codable {
        var version = 1
        var connections: [DesktopConnection]
        // Commit removals with profile deletion; acknowledge only after the
        // separate family catalog has removed its service reference.
        var pendingHostRemovals: [EndpointID] = []
        var pendingHostPublications: [EndpointID] = []
        private enum CodingKeys: String, CodingKey { case version, connections, pendingHostRemovals, pendingHostPublications }
        init(connections: [DesktopConnection] = []) { self.connections = connections }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            connections = try values.decode([DesktopConnection].self, forKey: .connections)
            pendingHostRemovals = try values.decodeIfPresent([EndpointID].self, forKey: .pendingHostRemovals) ?? []
            pendingHostPublications = try values.decodeIfPresent([EndpointID].self, forKey: .pendingHostPublications) ?? []
        }
    }
    private let fileURL: URL
    private let writer: @Sendable (Data, URL) throws -> Void
    public static let maximumFileBytes = 8 * 1024 * 1024

    /// The optional writer is an I/O boundary for deterministic failure tests.
    /// Production prepares the full protected file before its atomic rename.
    public init(fileURL: URL, writer: (@Sendable (Data, URL) throws -> Void)? = nil) {
        self.fileURL = fileURL
        self.writer = writer ?? Self.writeAtomically
    }

    public func load() throws -> [DesktopConnection] {
        try transaction(write: false) { $0.connections }
    }

    public func save(_ connection: DesktopConnection) throws -> [DesktopConnection] {
        try persist(connection, expected: nil, compare: false)
    }

    /// Nil expects a new identity; a prior value must still match the stored one.
    public func save(_ connection: DesktopConnection, replacing previous: DesktopConnection?) throws -> [DesktopConnection] {
        try persist(connection, expected: previous, compare: true)
    }

    private func persist(_ connection: DesktopConnection, expected: DesktopConnection?, compare: Bool) throws -> [DesktopConnection] {
        let value = try connection.validated()
        return try transaction { document in
            let index = document.connections.firstIndex(where: { $0.id == value.id })
            if compare, index.map({ document.connections[$0] }) != expected { throw DesktopError.connectionChanged }
            let old = index.map { document.connections[$0] }
            if old.map({ !Self.samePublication($0, value) }) ?? true,
               !document.pendingHostPublications.contains(value.id) {
                document.pendingHostPublications.append(value.id)
            }
            if let index { document.connections[index] = value }
            else { document.connections.append(value) }
            document.pendingHostRemovals.removeAll { $0 == value.id }
            return document.connections
        }
    }

    public func delete(_ id: EndpointID) throws -> [DesktopConnection] {
        try transaction { document in
            document.connections.removeAll { $0.id == id }
            document.pendingHostPublications.removeAll { $0 == id }
            if !document.pendingHostRemovals.contains(id) { document.pendingHostRemovals.append(id) }
            return document.connections
        }
    }

    public func pendingHostRemovals() throws -> [EndpointID] {
        try transaction(write: false) { $0.pendingHostRemovals }
    }

    public func acknowledgeHostRemoval(_ id: EndpointID) throws {
        try transaction { $0.pendingHostRemovals.removeAll { $0 == id } }
    }

    public func pendingHostPublications() throws -> [EndpointID] {
        try transaction(write: false) { $0.pendingHostPublications }
    }

    public func queueHostPublications(_ ids: [EndpointID]) throws {
        try transaction { document in
            let saved = Set(document.connections.map(\.id))
            for id in ids where saved.contains(id) && !document.pendingHostPublications.contains(id) {
                document.pendingHostPublications.append(id)
            }
        }
    }

    /// A concurrent edit must not be acknowledged by an older publication.
    public func acknowledgeHostPublications(_ published: [DesktopConnection]) throws {
        try transaction { document in
            document.pendingHostPublications.removeAll { id in
                guard let current = document.connections.first(where: { $0.id == id }),
                      let sent = published.first(where: { $0.id == id }) else { return false }
                return Self.samePublication(current, sent)
            }
        }
    }

    private static func samePublication(_ a: DesktopConnection, _ b: DesktopConnection) -> Bool {
        a.id == b.id && a.name == b.name && a.host == b.host && a.credentialID == b.credentialID
    }

    public func recordConnection(_ id: EndpointID, at date: Date = Date(),
                                 expectedConnection: DesktopConnection? = nil) throws -> [DesktopConnection] {
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw DesktopError.invalidDocument }
        let expected = try expectedConnection?.validated()
        return try transaction { document in
            try Task.checkCancellation()
            guard let index = document.connections.firstIndex(where: { $0.id == id }) else { throw DesktopError.missingConnection }
            let current = document.connections[index]
            if let expected {
                guard expected.id == id, current.host == expected.host, current.port == expected.port,
                      current.authentication == expected.authentication,
                      current.certificateSHA256 == expected.certificateSHA256 else { throw DesktopError.connectionChanged }
            }
            document.connections[index].lastConnectedAt = max(current.lastConnectedAt ?? date, date)
            return document.connections
        }
    }

    private func read() throws -> Document {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return Document()
        }
        guard let size = attributes[.size] as? NSNumber, size.intValue <= Self.maximumFileBytes else {
            throw DesktopError.storageTooLarge
        }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= Self.maximumFileBytes else { throw DesktopError.storageTooLarge }
        var document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) }
        catch { throw DesktopError.invalidDocument }
        try validate(document)
        document.connections = try document.connections.map { try $0.validated() }
        return document
    }

    private func validate(_ document: Document) throws {
        guard document.version == 1 else { throw DesktopError.unsupportedVersion(document.version) }
        guard document.connections.count <= 10_000, document.pendingHostRemovals.count <= 10_000,
              document.pendingHostPublications.count <= 10_000 else {
            throw DesktopError.storageTooLarge
        }
        guard Set(document.connections.map(\.id)).count == document.connections.count,
              Set(document.pendingHostRemovals).count == document.pendingHostRemovals.count,
              Set(document.pendingHostPublications).count == document.pendingHostPublications.count else {
            throw DesktopError.duplicateConnection
        }
        for connection in document.connections { _ = try connection.validated() }
    }

    private func transaction<T>(write: Bool = true, _ operation: (inout Document) throws -> T) throws -> T {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = open(fileURL.appendingPathExtension("lock").path,
                              O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        defer { flock(descriptor, LOCK_UN) }
        var document = try read()
        let result = try operation(&document)
        if write {
            try validate(document)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(document)
            guard data.count <= Self.maximumFileBytes else { throw DesktopError.storageTooLarge }
            try writer(data, fileURL)
        }
        return result
    }

    private static func writeAtomically(_ data: Data, to fileURL: URL) throws {
        let temporary = fileURL.deletingLastPathComponent().appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID()).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { unlink(temporary.path) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        // Nothing fallible follows commit. A failed save therefore never causes
        // credential cleanup for a profile that was already persisted.
        guard rename(temporary.path, fileURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
