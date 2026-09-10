import Foundation
import Testing
import GlasSecretStore
import os
@testable import GlassSSHTransport

/// Regression tests for the Stage 2 engine security review (S1–S5, S8–S10).
@Suite("Security review fixes")
struct SecurityReviewFixTests {
    private func route(host: String = "127.0.0.1", port: Int = 1) -> SSHRoute {
        SSHRoute(target: SSHHop(endpoint: SSHEndpoint(host: host, port: port, username: "me"), credential: .custom("none")))
    }

    private struct NoCredentials: SSHCredentialResolver {
        func resolve(_ reference: SSHCredentialReference, for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential {
            .password(SecureBytes(Data("x".utf8)))
        }
    }

    private func makeTransport(_ route: SSHRoute) -> SSHTransport {
        SSHTransport(route: route, credentials: NoCredentials(), trustStore: InMemoryHostTrustStore())
    }

    // S1
    @Test func executeOutputIsBoundedByDefault() {
        #expect(SSHTransport.defaultMaximumResponseBytes == 8 * 1024 * 1024)
    }

    // S2
    @Test func concurrentFirstRequestsShareOneTransport() async {
        let counter = OSAllocatedUnfairLock(initialState: 0)
        let pool = SSHTransportPool { route in
            counter.withLock { $0 += 1 }
            return SSHTransport(route: route, credentials: NoCredentials(), trustStore: InMemoryHostTrustStore())
        }
        let route = self.route()
        let transports = await withTaskGroup(of: SSHTransport.self, returning: [SSHTransport].self) { group in
            for _ in 0..<16 { group.addTask { await pool.transport(for: route, owner: UUID()) } }
            var out: [SSHTransport] = []
            for await t in group { out.append(t) }
            return out
        }
        #expect(counter.withLock { $0 } == 1, "one transport per identity even under concurrency")
        #expect(transports.allSatisfy { $0 === transports[0] })
        #expect(await transports[0].ownership.owners.count == 16)
    }

    @Test func aClosingTransportIsReplacedNotReused() async {
        let pool = SSHTransportPool { self.makeTransport($0) }
        let route = self.route()
        let a = UUID()
        let first = await pool.transport(for: route, owner: a)
        await pool.release(first, owner: a)             // last owner → closing
        #expect(await first.isClosing)
        let second = await pool.transport(for: route, owner: UUID())
        #expect(second !== first)
        #expect(!(await second.isClosing))
    }

    // S3
    @Test func concurrentConnectsJoinTheInFlightAttempt() async {
        let transport = makeTransport(route(port: 1))   // 127.0.0.1:1 refuses quickly
        let errors = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for _ in 0..<3 {
                group.addTask {
                    do { try await transport.connect(); return "connected" }
                    catch let error as SSHTransportError { return "transport:\(error)" }
                    catch { return "other" }
                }
            }
            var out: [String] = []
            for await e in group { out.append(e) }
            return out
        }
        #expect(errors.count == 3)
        #expect(!errors.contains("transport:connectionFailed"), "no caller is rejected merely for arriving during an in-flight connect")
        #expect(!(await transport.isConnected))
    }

    // S4
    @Test func legacyOptionRegistersNoHostKeyAlgorithms() {
        _ = SSHEngineAlgorithms.registerHostKeyAlgorithmsOnce
        _ = SSHEngineAlgorithms.registerHostKeyAlgorithmsOnce   // idempotent
        #expect(SSHEngineAlgorithms.legacySetRegistersNoPublicKeyAlgorithms)
        #expect(SSHConnectionOptions().allowLegacyAlgorithms == false, "off by default, per hop")
    }

    // S5
    @Test func serverSuppliedNamesAreClassifiedBeforeLocalUse() {
        #expect(SFTPEntry.isSafeName("report.txt"))
        #expect(SFTPEntry.isSafeName(".hidden"))
        #expect(!SFTPEntry.isSafeName(".."))
        #expect(!SFTPEntry.isSafeName("."))
        #expect(!SFTPEntry.isSafeName(""))
        #expect(!SFTPEntry.isSafeName("a/b"))
        #expect(!SFTPEntry.isSafeName("evil\0"))
        let entry = SFTPEntry(name: "../etc", path: "/srv/../etc", attributes: SFTPAttributes())
        #expect(!entry.hasSafeName)
    }

    // S8
    @Test func closingTwiceEmitsOneClosedEventAndNoLost() async {
        let transport = makeTransport(route())
        await transport.close()
        await transport.close()
        var events: [SSHTransportEvent] = []
        for await event in transport.events { events.append(event) }
        #expect(events == [.closed])
    }

    // S9
    @Test func remoteForwardReportsClosureExactlyOnce() async throws {
        let forward = SSHRemoteForward(remoteHost: "0.0.0.0", requestedRemotePort: 0, localHost: "127.0.0.1", localPort: 1) { onOpen in
            onOpen(1_234)
            try await Task.sleep(for: .seconds(10))
        }
        let closures = OSAllocatedUnfairLock(initialState: 0)
        forward.onClosed = { _ in closures.withLock { $0 += 1 } }
        #expect(await forward.boundPort() == 1_234)
        await forward.close()
        await forward.close()
        #expect(forward.isClosed)
        #expect(closures.withLock { $0 } == 1)
    }

    // S10
    @Test func undecodableHostKeyBlobIsNamedAsSuch() {
        let store = InMemoryHostTrustStore()
        let secretStore = SecretStoreHostTrustStore(configuration: SecretStoreConfiguration(serviceNamePrefix: "com.glasspowertools.review-tests", accessGroup: nil, useDataProtectionKeychain: true))
        let bad = SSHHostTrustChallenge(host: "h", port: 22, algorithm: "a", fingerprintSHA256: "f", keyDataBase64: "%%% not base64 %%%", reason: .unknown)
        #expect(throws: SSHTransportError.invalidHostKey) { try secretStore.pin(bad) }
        #expect(throws: Never.self) { try store.pin(bad) }   // the in-memory store keeps the raw string
        #expect(SSHTransportError.invalidHostKey.errorDescription == "The server's host key could not be decoded")
    }
}
