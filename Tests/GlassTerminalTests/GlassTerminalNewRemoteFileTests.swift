import Foundation
import Testing
import GlassShell
import Citadel
@testable import GlassSSHTransport
@testable import GlassTerminal

/// The editor saving a file that is not on the server yet — a new document's first save, or New
/// File — through the Files browser's verified commit. The owner, on the headset (2026-10-15): the
/// save said "The operation couldn't be completed. (Citadel.SFTPMessage.Status error 1.)", because
/// the commit read the destination first and a new file has none.
@Suite("The editor creates a file on a server")
struct GlassTerminalNewRemoteFileTests {
    private static let openSSH = SFTPServerExtensions([
        SFTPServerExtensions.hardLink: "1",
        SFTPServerExtensions.posixRename: "1",
        SFTPServerExtensions.fsync: "1",
    ])

    private func lister(_ server: InMemorySFTPServer) -> GlassTerminalDirectoryLister {
        GlassTerminalDirectoryLister(sftp: server, client: SFTPClient(session: server, extensions: Self.openSSH),
                                     transport: nil, owner: UUID(), serverID: UUID())
    }

    @Test("a file that isn't there is created with what was written, and nothing else is left in its folder")
    func createsANewFile() async throws {
        let server = InMemorySFTPServer(directories: ["/project"])
        let written = Data("hello\n".utf8)

        let stamp = try await lister(server).write(written, to: "/project/notes.md", expecting: nil)

        #expect(await server.contents(of: "/project/notes.md") == written)
        #expect(stamp?.size == UInt64(written.count), "the editor is told what landed")
        #expect(await server.names(in: "/project") == ["notes.md"], "no hidden partial left behind")
    }

    @Test("a file the editor saw that has since gone is not made again: it says the file changed")
    func aFileThatWentIsNotRecreated() async throws {
        let server = InMemorySFTPServer(directories: ["/project"])
        await #expect(throws: GlassPortForwardError.self) {
            try await lister(server).write(Data("x".utf8), to: "/project/gone.md",
                                           expecting: GlassHostFileStamp(size: 3, modifiedAt: Date(timeIntervalSince1970: 1)))
        }
        #expect(await server.names(in: "/project").isEmpty)
    }

    @Test("a file that is there is still replaced through the verified commit, as before")
    func anExistingFileIsReplaced() async throws {
        let server = InMemorySFTPServer(directories: ["/project"])
        await server.put(Data("old".utf8), at: "/project/notes.md")

        _ = try await lister(server).write(Data("new".utf8), to: "/project/notes.md", expecting: nil)

        #expect(await server.contents(of: "/project/notes.md") == Data("new".utf8))
        #expect(await server.names(in: "/project") == ["notes.md"])
    }

    @Test("a server's refusal is in words: no library type, no number")
    func refusalsAreInWords() {
        for refusal: SFTPRefusal in [.endOfFile, .noSuchFile, .permissionDenied, .failure, .badMessage,
                                     .noConnection, .connectionLost, .unsupported, .other(9)] {
            let text = SFTPSessionError.refused(refusal, serverMessage: "No such file").localizedDescription
            #expect(!text.contains("Citadel") && !text.contains("error") && !text.isEmpty, "\(refusal): \(text)")
        }
        #expect(SFTPRefusal(SFTPStatusCode.noSuchFile) == .noSuchFile, "Citadel's status, as the session translates it")
        #expect(SFTPSessionError.isMissingPath(SFTPSessionError.refused(.noSuchFile, serverMessage: "")))
        #expect(!SFTPSessionError.isMissingPath(SFTPSessionError.refused(.permissionDenied, serverMessage: "")))
    }
}

/// An SFTP server in memory that answers as OpenSSH does where this matters: a missing path is
/// "no such file", an exclusive create of an existing file and a hard link onto an existing name
/// are refused.
actor InMemorySFTPServer: SFTPSession {
    private struct File {
        var data: Data
        var modified: Date
    }

    private var files: [String: File] = [:]
    private var directories: Set<String>
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    init(directories: Set<String>) { self.directories = directories.union(["/"]) }

    func put(_ data: Data, at path: String) { files[path] = File(data: data, modified: tick()) }
    func contents(of path: String) -> Data? { files[path]?.data }
    func names(in folder: String) -> [String] {
        files.keys.filter { ($0 as NSString).deletingLastPathComponent == folder }
            .map { ($0 as NSString).lastPathComponent }.sorted()
    }

    private func tick() -> Date {
        clock = clock.addingTimeInterval(1)
        return clock
    }

    private func missing(_ path: String) -> SFTPSessionError {
        .refused(.noSuchFile, serverMessage: "No such file")
    }

    func list(_ path: String) async throws -> [SFTPEntry] {
        files.keys.filter { ($0 as NSString).deletingLastPathComponent == path }.sorted().map {
            SFTPEntry(name: ($0 as NSString).lastPathComponent, path: $0,
                      attributes: SFTPAttributes(size: UInt64(files[$0]!.data.count), permissions: 0o100644))
        }
    }

    func attributes(at path: String, followSymlinks: Bool) async throws -> SFTPAttributes {
        if directories.contains(path) { return SFTPAttributes(permissions: 0o040755) }
        guard let file = files[path] else { throw missing(path) }
        return SFTPAttributes(size: UInt64(file.data.count), permissions: 0o100644,
                              accessTime: file.modified, modificationTime: file.modified)
    }

    func realPath(_ path: String) async throws -> String { path }

    func open(_ path: String, mode: SFTPOpenMode, permissions: UInt32?) async throws -> any GlassSSHTransport.SFTPFileHandle {
        if files[path] == nil {
            guard mode.contains(.create) else { throw missing(path) }
            files[path] = File(data: Data(), modified: tick())
        } else if mode.contains(.create), mode.contains(.exclusive) {
            throw SFTPSessionError.refused(.failure, serverMessage: "Failure")
        } else if mode.contains(.truncate) {
            files[path]?.data = Data()
        }
        return Handle(server: self, path: path)
    }

    func createDirectory(_ path: String) async throws { directories.insert(path) }
    func removeFile(_ path: String) async throws {
        guard files.removeValue(forKey: path) != nil else { throw missing(path) }
    }
    func removeDirectory(_ path: String) async throws { directories.remove(path) }
    func rename(_ path: String, to newPath: String) async throws {
        guard files[newPath] == nil else { throw SFTPSessionError.refused(.failure, serverMessage: "Failure") }
        guard let file = files.removeValue(forKey: path) else { throw missing(path) }
        files[newPath] = file
    }
    func posixRename(_ path: String, to newPath: String) async throws {
        guard let file = files.removeValue(forKey: path) else { throw missing(path) }
        files[newPath] = file
    }
    func hardLink(_ path: String, to newPath: String) async throws {
        guard files[newPath] == nil else { throw SFTPSessionError.refused(.failure, serverMessage: "Failure") }
        guard let file = files[path] else { throw missing(path) }
        files[newPath] = file
    }
    func setAttributes(_ changes: SFTPAttributeChanges, at path: String) async throws {
        guard files[path] != nil else { throw missing(path) }
    }
    var serverExtensions: SFTPServerExtensions {
        SFTPServerExtensions([SFTPServerExtensions.hardLink: "1", SFTPServerExtensions.posixRename: "1",
                              SFTPServerExtensions.fsync: "1"])
    }
    var isActive: Bool { true }
    func close() async throws {}

    fileprivate func read(_ path: String, offset: UInt64, length: UInt32) throws -> Data {
        guard let data = files[path]?.data else { throw missing(path) }
        guard Int(offset) < data.count else { return Data() }
        return data.subdata(in: Int(offset)..<min(data.count, Int(offset) + Int(length)))
    }

    fileprivate func write(_ path: String, _ data: Data, at offset: UInt64) throws {
        guard var file = files[path] else { throw missing(path) }
        if file.data.count < Int(offset) { file.data.append(Data(count: Int(offset) - file.data.count)) }
        file.data.replaceSubrange(Int(offset)..<min(file.data.count, Int(offset) + data.count), with: data)
        file.modified = tick()
        files[path] = file
    }

    private struct Handle: GlassSSHTransport.SFTPFileHandle {
        let server: InMemorySFTPServer
        let path: String
        func read(from offset: UInt64, length: UInt32) async throws -> Data {
            try await server.read(path, offset: offset, length: length)
        }
        func write(_ data: Data, at offset: UInt64) async throws { try await server.write(path, data, at: offset) }
        func attributes() async throws -> SFTPAttributes { try await server.attributes(at: path, followSymlinks: true) }
        func synchronize() async throws {}
        func close() async throws {}
    }
}
