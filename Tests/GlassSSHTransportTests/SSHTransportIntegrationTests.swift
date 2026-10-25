import Foundation
import Testing
import GlasSecretStore
import NIOCore
@testable import GlassSSHTransport

/// Real-host tests, gated on the environment the coordinator provides:
/// `GPT_SSH_TEST_HOST`, `GPT_SSH_TEST_USER`, and `GPT_SSH_TEST_PASSWORD` or `GPT_SSH_TEST_KEY_PATH`.
/// Read-only apart from a temporary directory the tests create and remove under /tmp.
enum IntegrationEnvironment {
    static var host: String? { ProcessInfo.processInfo.environment["GPT_SSH_TEST_HOST"] }
    static var user: String? { ProcessInfo.processInfo.environment["GPT_SSH_TEST_USER"] }
    static var port: Int { Int(ProcessInfo.processInfo.environment["GPT_SSH_TEST_PORT"] ?? "") ?? 22 }
    static var password: String? { ProcessInfo.processInfo.environment["GPT_SSH_TEST_PASSWORD"] }
    static var keyPath: String? { ProcessInfo.processInfo.environment["GPT_SSH_TEST_KEY_PATH"] }
    static var isConfigured: Bool { host != nil && user != nil && (password != nil || keyPath != nil) }
    /// The host's own address and SSH port as it sees itself, for a tunnel that ends at a network
    /// address on the far side: not `host` and `port` when those are this Mac's end of a tunnel to
    /// the test VM (BUILDING.md). The same when unset.
    static var farHost: String? { ProcessInfo.processInfo.environment["GPT_SSH_TEST_FAR_HOST"] ?? host }
    static var farPort: Int { Int(ProcessInfo.processInfo.environment["GPT_SSH_TEST_FAR_PORT"] ?? "") ?? port }

    /// Why the gated suites are skipped, as the run reports it. They were reported as passed, having
    /// returned early, until 2026-10-24.
    static let notConfigured: Comment = "no host configured: set GPT_SSH_TEST_HOST, GPT_SSH_TEST_USER and GPT_SSH_TEST_PASSWORD or GPT_SSH_TEST_KEY_PATH"
}

/// Resolves the test credential from the environment: a key file read into secure memory, or a
/// password. The engine never sees a path or string beyond this resolver.
struct EnvironmentCredentialResolver: SSHCredentialResolver {
    func resolve(_ reference: SSHCredentialReference, for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential {
        if let keyPath = IntegrationEnvironment.keyPath {
            let data = try Data(contentsOf: URL(fileURLWithPath: keyPath))
            return .privateKey(SSHKeyMaterial(privateKey: SecureBytes(data), passphrase: nil))
        }
        if let password = IntegrationEnvironment.password {
            return .password(SecureBytes(Data(password.utf8)))
        }
        throw SSHTransportError.credentialUnavailable("no test credential")
    }
}

struct TrustEverythingThisRun: SSHHostTrustDecider {
    func decide(_ challenge: SSHHostTrustChallenge) async -> SSHHostTrustDecision { .trust(remember: false) }
}

enum IntegrationTransport {
    static func make() -> SSHTransport {
        let endpoint = SSHEndpoint(host: IntegrationEnvironment.host!, port: IntegrationEnvironment.port, username: IntegrationEnvironment.user!)
        let hop = SSHHop(displayName: "test host", endpoint: endpoint, credential: .custom("integration"), options: SSHConnectionOptions(keepAliveInterval: 15))
        return SSHTransport(route: SSHRoute(target: hop), credentials: EnvironmentCredentialResolver(), trustStore: InMemoryHostTrustStore(), trustDecider: TrustEverythingThisRun())
    }
}

@Suite("Real host (gated)", .serialized, .enabled(if: IntegrationEnvironment.isConfigured, IntegrationEnvironment.notConfigured))
struct SSHTransportIntegrationTests {
    @Test func connectsAndRunsACommand() async throws {
        let transport = IntegrationTransport.make()
        let owner = UUID()
        #expect(await transport.acquire(owner: owner))
        try await transport.connect()
        #expect(await transport.isConnected)
        let output = try await transport.execute("echo ok")
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "ok")
        try await transport.connect() // idempotent
        await transport.release(owner: owner)
        #expect(!(await transport.isConnected))
    }

    @Test func interactiveShellRoundTripsAndReportsCleanExit() async throws {
        let transport = IntegrationTransport.make()
        try await transport.connect()
        let shell = try await transport.openShell(pty: SSHPTYRequest(columns: 100, rows: 30))
        #expect(await shell.isOpen)
        try await shell.sendCommand("echo shell-ok-$((6*7))")
        try await shell.resize(columns: 120, rows: 40)
        try await shell.sendCommand("exit")
        var collected = Data()
        for await chunk in shell.output {
            if case .stdout(let data) = chunk { collected.append(data) }
            if case .stderr(let data) = chunk { collected.append(data) }
        }
        #expect(String(decoding: collected, as: UTF8.self).contains("shell-ok-42"))
        #expect(await shell.exit == .remoteClosed)
        await transport.close()
    }

    @Test func sftpListsAndRoundTripsInATemporaryDirectory() async throws {
        let transport = IntegrationTransport.make()
        try await transport.connect()
        let sftp = try await transport.openSFTP()
        #expect(await sftp.isActive)
        _ = try await sftp.list(".")   // read-only listing succeeds

        let directory = "/tmp/glasspowertools-transport-\(UUID().uuidString)"
        try await sftp.createDirectory(directory)
        #expect(try await sftp.attributes(at: directory).isDirectory)
        let file = directory + "/roundtrip.txt"
        let editor = EditorSFTPConsumer(session: sftp)      // the Stage 5 consumer, on the real engine
        try await editor.saveDocument("round trip\n", to: file)
        #expect(try await editor.openDocument(at: file) == "round trip\n")
        #expect(try await sftp.list(directory).map(\.name) == ["roundtrip.txt"])

        // Extensions and times on a real OpenSSH sftp-server.
        let extensions = await sftp.serverExtensions
        #expect(!extensions.raw.isEmpty, "OpenSSH advertises extensions at init")
        let accessed = Date(timeIntervalSince1970: 1_600_000_000), modified = Date(timeIntervalSince1970: 1_600_000_100)
        try await sftp.setTimes(at: file, accessed: accessed, modified: modified)
        let stamped = try await sftp.attributes(at: file)
        #expect(stamped.modificationTime == modified && stamped.accessTime == accessed)
        try await sftp.setPermissions(0o600, at: file)
        #expect(try await sftp.attributes(at: file).mode == 0o600)
        if extensions.supportsPOSIXRename {
            try await editor.saveDocument("replacement\n", to: file + ".tmp")
            try await sftp.replace(file, with: file + ".tmp")
            #expect(try await editor.openDocument(at: file) == "replacement\n")
        }
        if extensions.supportsFSync {
            let handle = try await sftp.open(file, mode: [.write])
            try await handle.synchronize()
            try await handle.close()
        }
        try await sftp.rename(file, to: file + ".renamed")
        #expect(try await sftp.list(directory).map(\.name) == ["roundtrip.txt.renamed"])
        try await sftp.removeFile(file + ".renamed")
        try await sftp.removeDirectory(directory)
        await #expect(throws: (any Error).self, "the directory is gone") { _ = try await sftp.attributes(at: directory) }
        try await sftp.close()
        await transport.close()
    }

    @Test func tunnelReachesTheHostsOwnSSHPort() async throws {
        let transport = IntegrationTransport.make()
        try await transport.connect()
        let consumer = DatabaseTunnelConsumer(transport: transport)   // the Stage 3 consumer, on the real engine
        let endpoint = try await consumer.localEndpoint(forDatabaseAt: "localhost", port: 22)
        let client = try await TCPClient.connect(port: endpoint.port)
        let banner = try await client.executeThenClose { inbound, _ in
            var received = Data()
            for try await chunk in inbound {
                received.append(contentsOf: chunk.readableBytesView)
                if received.count >= 8 { break }
            }
            return String(decoding: received.prefix(8), as: UTF8.self)
        }
        #expect(banner.hasPrefix("SSH-2.0"), "the tunnelled connection reached sshd on the host")
        await endpoint.tunnel.close()
        await transport.close()
    }

    /// A database behind another machine (2026-10-05): the tunnel ends at a network address as the
    /// SSH machine sees it, not at its loopback. The test host's own address stands in for the
    /// private database server, so nothing about the network is written here.
    @Test func tunnelReachesANetworkAddressNotOnlyLoopback() async throws {
        let transport = IntegrationTransport.make()
        try await transport.connect()
        let consumer = DatabaseTunnelConsumer(transport: transport)
        let endpoint = try await consumer.localEndpoint(forDatabaseAt: IntegrationEnvironment.farHost!,
                                                        port: IntegrationEnvironment.farPort)
        let client = try await TCPClient.connect(port: endpoint.port)
        let banner = try await client.executeThenClose { inbound, _ in
            var received = Data()
            for try await chunk in inbound {
                received.append(contentsOf: chunk.readableBytesView)
                if received.count >= 8 { break }
            }
            return String(decoding: received.prefix(8), as: UTF8.self)
        }
        #expect(banner.hasPrefix("SSH-2.0"), "the tunnel reached a service at a network address from the far side")
        await endpoint.tunnel.close()
        await transport.close()
    }

    @Test func poolSharesOneConnectedTransportPerRoute() async throws {
        let pool = SSHTransportPool { _ in IntegrationTransport.make() }
        let route = IntegrationTransport.make().route
        let a = UUID(), b = UUID()
        let first = await pool.transport(for: route, owner: a)
        try await first.connect()
        let second = await pool.transport(for: route, owner: b)
        #expect(first === second)
        #expect(await pool.connectedTransportCount() == 1)
        await pool.release(first, owner: a)
        #expect(await first.isConnected, "still owned by b")
        await pool.release(second, owner: b)
        #expect(!(await first.isConnected))
        #expect(await pool.connectedTransportCount() == 0)
    }
}
