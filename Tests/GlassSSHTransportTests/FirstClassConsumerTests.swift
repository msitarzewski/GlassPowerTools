import Foundation
import Testing
@testable import GlassSSHTransport

// The proof that the engine is first-class: these consumers depend on GlassSSHTransport's
// public API only — never on GlassTerminal — and are exercised both against fakes here and
// against the real transport in SSHTransportIntegrationTests.

/// What a database capability needs: a local port that reaches the database through SSH.
protocol TunnelProviding: Sendable {
    func forward(localPort: Int, toHost host: String, port: Int) async throws -> SSHTunnel
}
extension SSHTransport: TunnelProviding {}

struct DatabaseTunnelConsumer {
    let transport: any TunnelProviding
    /// Returns the local endpoint a database driver would connect to.
    func localEndpoint(forDatabaseAt host: String, port: Int) async throws -> (host: String, port: Int, tunnel: SSHTunnel) {
        let tunnel = try await transport.forward(localPort: 0, toHost: host, port: port)
        return ("127.0.0.1", tunnel.localPort, tunnel)
    }
}

/// What the editor needs: open a remote document, edit it, save it back.
struct EditorSFTPConsumer {
    let session: any SFTPSession
    func openDocument(at path: String) async throws -> String {
        String(decoding: try await session.readFile(at: path, maxBytes: 8 * 1024 * 1024), as: UTF8.self)
    }
    func saveDocument(_ text: String, to path: String) async throws {
        try await session.writeFile(Data(text.utf8), to: path)
    }
}

/// An in-memory SFTP server for the editor consumer.
actor FakeSFTPSession: SFTPSession {
    var files: [String: Data] = [:]
    var directories: Set<String> = ["/"]
    var closed = false
    var permissions: [String: UInt32] = [:]
    var times: [String: (accessed: Date, modified: Date)] = [:]
    var extensions: SFTPServerExtensions
    var posixRenames = 0
    var hardLinks = 0

    init(extensions: SFTPServerExtensions = SFTPServerExtensions()) { self.extensions = extensions }

    func list(_ path: String) async throws -> [SFTPEntry] {
        let base = path.hasSuffix("/") ? path : path + "/"
        return files.keys.filter { $0.hasPrefix(base) && !$0.dropFirst(base.count).contains("/") }.sorted().map {
            SFTPEntry(name: String($0.dropFirst(base.count)), path: $0, attributes: SFTPAttributes(size: UInt64(files[$0]!.count), permissions: 0o100644))
        }
    }
    func attributes(at path: String, followSymlinks: Bool) async throws -> SFTPAttributes {
        if directories.contains(path) { return SFTPAttributes(permissions: 0o040755) }
        guard let data = files[path] else { throw SFTPSessionError.closed }
        return SFTPAttributes(size: UInt64(data.count), permissions: permissions[path] ?? 0o100644,
                              accessTime: times[path]?.accessed, modificationTime: times[path]?.modified)
    }
    func realPath(_ path: String) async throws -> String { path }
    func open(_ path: String, mode: SFTPOpenMode, permissions: UInt32?) async throws -> any SFTPFileHandle {
        if mode.contains(.create), files[path] == nil { files[path] = Data() }
        if mode.contains(.truncate) { files[path] = Data() }
        guard files[path] != nil else { throw SFTPSessionError.closed }
        return FakeHandle(session: self, path: path)
    }
    func createDirectory(_ path: String) async throws { directories.insert(path) }
    func removeFile(_ path: String) async throws { files.removeValue(forKey: path) }
    func removeDirectory(_ path: String) async throws { directories.remove(path) }
    func rename(_ path: String, to newPath: String) async throws {
        guard files[newPath] == nil else { throw SFTPSessionError.closed }   // plain rename refuses to overwrite
        files[newPath] = files.removeValue(forKey: path)
    }
    func posixRename(_ path: String, to newPath: String) async throws {
        guard extensions.supportsPOSIXRename else { throw SFTPSessionError.extensionUnsupported(SFTPServerExtensions.posixRename) }
        posixRenames += 1
        files[newPath] = files.removeValue(forKey: path)
    }
    func hardLink(_ path: String, to newPath: String) async throws {
        guard extensions.supportsHardLink else { throw SFTPSessionError.extensionUnsupported(SFTPServerExtensions.hardLink) }
        hardLinks += 1
        files[newPath] = files[path]
    }
    func setAttributes(_ changes: SFTPAttributeChanges, at path: String) async throws {
        guard !changes.hasPartialTimes else { throw SFTPSessionError.partialTimes }
        guard files[path] != nil || directories.contains(path) else { throw SFTPSessionError.closed }
        if let p = changes.permissions { permissions[path] = p }
        if let a = changes.accessed, let m = changes.modified { times[path] = (a, m) }
    }
    var serverExtensions: SFTPServerExtensions { extensions }
    var isActive: Bool { !closed }
    func close() async throws { closed = true }

    func read(_ path: String, offset: UInt64, length: UInt32) -> Data {
        guard let data = files[path], Int(offset) < data.count else { return Data() }
        return data.subdata(in: Int(offset)..<min(data.count, Int(offset) + Int(length)))
    }
    func write(_ path: String, data: Data, offset: UInt64) {
        var existing = files[path] ?? Data()
        if existing.count < Int(offset) { existing.append(Data(count: Int(offset) - existing.count)) }
        existing.replaceSubrange(Int(offset)..<min(existing.count, Int(offset) + data.count), with: data)
        files[path] = existing
    }

    struct FakeHandle: SFTPFileHandle {
        let session: FakeSFTPSession
        let path: String
        func read(from offset: UInt64, length: UInt32) async throws -> Data { await session.read(path, offset: offset, length: length) }
        func write(_ data: Data, at offset: UInt64) async throws { await session.write(path, data: data, offset: offset) }
        func attributes() async throws -> SFTPAttributes { try await session.attributes(at: path, followSymlinks: true) }
        func synchronize() async throws {
            guard await session.serverExtensions.supportsFSync else { throw SFTPSessionError.extensionUnsupported(SFTPServerExtensions.fsync) }
        }
        func close() async throws {}
    }
}

@Suite("First-class consumers")
struct FirstClassConsumerTests {
    @Test func editorOpensEditsAndSavesThroughTheSFTPSessionAPIOnly() async throws {
        let session = FakeSFTPSession()
        let editor = EditorSFTPConsumer(session: session)
        try await editor.saveDocument("SELECT 1;\n", to: "/query.sql")
        #expect(try await editor.openDocument(at: "/query.sql") == "SELECT 1;\n")
        try await editor.saveDocument("SELECT 2;\n", to: "/query.sql")
        #expect(try await editor.openDocument(at: "/query.sql") == "SELECT 2;\n", "truncate-on-save replaces the content")
        let listed = try await session.list("/")
        #expect(listed.map(\.name) == ["query.sql"])
        #expect(listed.first?.attributes.isRegularFile == true)
    }

    @Test func readFileHonoursTheSizeLimitAndChunking() async throws {
        let session = FakeSFTPSession()
        let big = Data(repeating: 0x41, count: Int(FakeSFTPSession.defaultChunkLength) * 2 + 17)
        try await session.writeFile(big, to: "/big.bin")
        #expect(try await session.readFile(at: "/big.bin") == big)
        await #expect(throws: SFTPSessionError.fileTooLarge(limit: 10)) {
            _ = try await session.readFile(at: "/big.bin", maxBytes: 10)
        }
    }

    @Test func attributesExposePOSIXTypeBits() {
        #expect(SFTPAttributes(permissions: 0o040755).isDirectory)
        #expect(SFTPAttributes(permissions: 0o120777).isSymbolicLink)
        #expect(SFTPAttributes(permissions: 0o100644).isRegularFile)
        #expect(SFTPAttributes(permissions: 0o100644).mode == 0o644)
        #expect(!SFTPAttributes().isDirectory)
    }

    @Test func databaseConsumerUsesTheTunnelAPIOverATCPProvider() async throws {
        struct ProviderBackedTunnels: TunnelProviding {
            func forward(localPort: Int, toHost host: String, port: Int) async throws -> SSHTunnel {
                try await SSHTunnelFactory.localForward(localPort: localPort, remoteHost: host, remotePort: port, provider: TCPDirectChannelProvider())
            }
        }
        let echo = try await EchoServer.start()
        defer { echo.channel.close(promise: nil) }
        let consumer = DatabaseTunnelConsumer(transport: ProviderBackedTunnels())
        let endpoint = try await consumer.localEndpoint(forDatabaseAt: "127.0.0.1", port: echo.port)
        #expect(endpoint.host == "127.0.0.1")
        let client = try await TCPClient.connect(port: endpoint.port)
        #expect(try await TCPClient.exchange(client, send: [9, 9, 9], expect: 3) == [9, 9, 9])
        await endpoint.tunnel.close()
    }
}
