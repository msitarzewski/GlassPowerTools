//
//  LiveRemoteEditingTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  The editor's remote half against a real SSH server.
//
//  Everything else about reading and writing another machine's files is tested against a fake that
//  answers whatever the test wants. That proves the editor's half of the conversation and none of
//  the server's: whether a real `SFTP` server returns the attributes the conflict check compares,
//  whether the verified commit lands, and whether an executable file is still executable
//  afterwards are not things a fake can answer.
//
//  Gated on the same environment the other live tests use, and **not skipped silently**: an
//  unconfigured run prints NOT RUN, because a test that passes by not running is worse than no
//  test (rule 25 and the verification-scope lesson).
//
//      GPT_SSH_TEST_HOST=192.0.2.6 GPT_SSH_TEST_USER=casey \
//      GPT_SSH_TEST_KEY_PATH=$HOME/.ssh/<test VM key> swift test --filter LiveRemoteEditing
//
//  Writes only inside a directory it creates under /tmp and removes afterwards.
//

import Foundation
import Testing
import GlasSecretStore
import GlassEditorCore
import GlassSSHTransport
import GlassShell
@testable import GlassTerminal

nonisolated enum LiveRemoteEnvironment {
    static var host: String? { ProcessInfo.processInfo.environment["GPT_SSH_TEST_HOST"] }
    static var user: String? { ProcessInfo.processInfo.environment["GPT_SSH_TEST_USER"] }
    static var port: Int { Int(ProcessInfo.processInfo.environment["GPT_SSH_TEST_PORT"] ?? "") ?? 22 }
    static var keyPath: String? { ProcessInfo.processInfo.environment["GPT_SSH_TEST_KEY_PATH"] }
    static var password: String? { ProcessInfo.processInfo.environment["GPT_SSH_TEST_PASSWORD"] }
    static var isConfigured: Bool { host != nil && user != nil && (keyPath != nil || password != nil) }
}

struct LiveCredentialResolver: SSHCredentialResolver {
    func resolve(_ reference: SSHCredentialReference,
                 for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential {
        if let keyPath = LiveRemoteEnvironment.keyPath {
            return .privateKey(SSHKeyMaterial(
                privateKey: SecureBytes(try Data(contentsOf: URL(fileURLWithPath: keyPath))),
                passphrase: nil
            ))
        }
        if let password = LiveRemoteEnvironment.password {
            return .password(SecureBytes(Data(password.utf8)))
        }
        throw SSHTransportError.credentialUnavailable("no test credential")
    }
}

struct TrustThisRun: SSHHostTrustDecider {
    func decide(_ challenge: SSHHostTrustChallenge) async -> SSHHostTrustDecision { .trust(remember: false) }
}

@Suite("The editor against a real server (gated)", .serialized)
struct LiveRemoteEditingTests {

    /// A connected lister over a real SFTP session, plus a directory to work in.
    private func connect() async throws -> (lister: GlassTerminalDirectoryLister, root: String,
                                            transport: SSHTransport, owner: UUID)? {
        guard LiveRemoteEnvironment.isConfigured else {
            print("NOT RUN: set GPT_SSH_TEST_HOST, GPT_SSH_TEST_USER and GPT_SSH_TEST_KEY_PATH")
            return nil
        }
        let endpoint = SSHEndpoint(host: LiveRemoteEnvironment.host!,
                                   port: LiveRemoteEnvironment.port,
                                   username: LiveRemoteEnvironment.user!)
        let hop = SSHHop(displayName: "live editor test", endpoint: endpoint,
                         credential: .custom("integration"),
                         options: SSHConnectionOptions(keepAliveInterval: 15))
        let transport = SSHTransport(route: SSHRoute(target: hop),
                                     credentials: LiveCredentialResolver(),
                                     trustStore: InMemoryHostTrustStore(),
                                     trustDecider: TrustThisRun())
        let owner = UUID()
        _ = await transport.acquire(owner: owner)
        try await transport.connect()

        let root = "/tmp/glass-editor-live-\(UUID().uuidString.prefix(8))"
        _ = try await transport.execute("mkdir -p \(root)")

        let sftp = try await transport.openSFTP()
        let lister = GlassTerminalDirectoryLister(
            sftp: sftp,
            client: SFTPClient(session: sftp, extensions: await sftp.serverExtensions),
            transport: nil,
            owner: owner,
            serverID: UUID()
        )
        return (lister, root, transport, owner)
    }

    private func tearDown(_ context: (lister: GlassTerminalDirectoryLister, root: String,
                                      transport: SSHTransport, owner: UUID)) async {
        await context.lister.close()
        _ = try? await context.transport.execute("rm -rf \(context.root)")
        await context.transport.release(owner: context.owner)
    }

    /// Connects, runs the body, and tears down **whether or not the body threw**.
    ///
    /// Not `defer`: `defer` cannot await, and a `Task` inside one is cleanup that races the end of
    /// the test and loses — the first run of these tests left a directory on the VM, which is the
    /// same "tests using the real machine as scratch space" this project has already had to clean
    /// up once.
    private func withLiveServer(
        _ body: (GlassTerminalDirectoryLister, String, SSHTransport) async throws -> Void
    ) async throws {
        guard let context = try await connect() else { return }
        do {
            try await body(context.lister, context.root, context.transport)
        } catch {
            await tearDown(context)
            throw error
        }
        await tearDown(context)
    }

    // MARK: Reading

    @Test("a real server's listing becomes the editor's tree, folders and files told apart")
    func listingARealDirectory() async throws {
        try await withLiveServer { lister, root, transport in

            _ = try await transport.execute(
                "mkdir -p \(root)/Sources && printf 'hello\\n' > \(root)/README.md"
            )
            let entries = try await lister.list(root)
            let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.isDirectory) })
            #expect(byName["Sources"] == true, "a real directory was not reported as one")
            #expect(byName["README.md"] == false)
        }
    }

    @Test("a real file reads back byte for byte, including one larger than a single SFTP read")
    func readingARealFile() async throws {
        try await withLiveServer { lister, root, transport in

            _ = try await transport.execute("printf 'let x = 1\\n' > \(root)/small.swift")
            #expect(try await lister.read("\(root)/small.swift") == Data("let x = 1\n".utf8))

            // Past the 32 KiB read window, which is where a loop that stops at the first short answer
            // silently truncates.
            _ = try await transport.execute("head -c 200000 /dev/urandom | base64 > \(root)/big.txt")
            let expected = try await transport.execute("cat \(root)/big.txt")
            let actual = try await lister.read("\(root)/big.txt")
            #expect(actual.count == Data(expected.utf8).count, "a large file did not read back whole")
            #expect(actual == Data(expected.utf8))
        }
    }

    @Test("a real server answers with the size and modification time the conflict check needs")
    func statOfARealFile() async throws {
        try await withLiveServer { lister, root, transport in

            _ = try await transport.execute("printf '12345' > \(root)/five.txt")
            let stamp = try await lister.stat("\(root)/five.txt")
            #expect(stamp?.size == 5, "the server did not report a size the check can compare")
            #expect(stamp?.modifiedAt != nil, "the server did not report a modification time")

            // And a file that is not there is an absence, not a zero.
            #expect(try await lister.stat("\(root)/missing.txt") == nil)
        }
    }

    // MARK: Writing

    @Test("a real save lands, and the returned stat describes what landed")
    func writingARealFile() async throws {
        try await withLiveServer { lister, root, transport in

            let path = "\(root)/notes.txt"
            _ = try await transport.execute("printf 'before\\n' > \(path)")
            let before = try await lister.stat(path)

            let committed = try await lister.write(Data("after\n".utf8), to: path, expecting: before)
            let onDisk = try await transport.execute("cat \(path)")
            #expect(onDisk == "after\n", "the save did not reach the machine")
            #expect(committed?.size == 6, "the commit did not describe what it wrote")
        }
    }

    /// The bug the verified commit exists to prevent, and the one my first version had: a save
    /// that replaces the file must not replace its permissions.
    @Test("saving an executable file leaves it executable")
    func modeSurvivesASave() async throws {
        try await withLiveServer { lister, root, transport in

            let path = "\(root)/deploy.sh"
            _ = try await transport.execute("printf '#!/bin/sh\\necho one\\n' > \(path) && chmod 755 \(path)")
            let before = try await transport.execute("stat -c '%a' \(path)")

            let stamp = try await lister.stat(path)
            _ = try await lister.write(Data("#!/bin/sh\necho two\n".utf8), to: path, expecting: stamp)

            let after = try await transport.execute("stat -c '%a' \(path)")
            #expect(after.trimmingCharacters(in: .whitespacesAndNewlines) == "755",
                    "the file's mode changed on save: was \(before.trimmingCharacters(in: .whitespacesAndNewlines)), now \(after.trimmingCharacters(in: .whitespacesAndNewlines))")
            #expect(try await transport.execute("cat \(path)") == "#!/bin/sh\necho two\n")
        }
    }

    /// The window the expectation closes, against a real server rather than a fake that was told
    /// to refuse.
    @Test("a real file changed since the editor looked is not overwritten")
    func aChangedFileIsRefused() async throws {
        try await withLiveServer { lister, root, transport in

            let path = "\(root)/contested.txt"
            _ = try await transport.execute("printf 'original\\n' > \(path)")
            let stale = try await lister.stat(path)

            // Somebody else writes it. A whole second later, so a seconds-resolution mtime moves.
            try await Task.sleep(for: .milliseconds(1_100))
            _ = try await transport.execute("printf 'theirs and longer\\n' > \(path)")

            var thrown: (any Error)?
            do {
                _ = try await lister.write(Data("mine\n".utf8), to: path, expecting: stale)
            } catch { thrown = error }

            #expect(thrown != nil, "the write landed on a version the editor had never seen")
            #expect(try await transport.execute("cat \(path)") == "theirs and longer\n")
        }
    }

    @Test("a save leaves no staging file behind on the machine")
    func noLitterIsLeftBehind() async throws {
        try await withLiveServer { lister, root, transport in

            let path = "\(root)/tidy.txt"
            _ = try await transport.execute("printf 'one\\n' > \(path)")
            let stamp = try await lister.stat(path)
            _ = try await lister.write(Data("two\n".utf8), to: path, expecting: stamp)

            let listing = try await transport.execute("ls -A \(root)")
            let names = listing.split(separator: "\n").map(String.init)
            #expect(names == ["tidy.txt"], "the save left something behind: \(names)")
        }
    }
}
