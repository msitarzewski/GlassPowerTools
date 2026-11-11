import Foundation
import Testing
import GlasSecretStore
import NIOCore
@testable import GlassSSHTransport

/// A machine that doesn't answer, as the real transport meets it (2026-11-10: a laptop asleep in a bag). The pool
/// and the terminal decide what to do from `SSHTransportError.isMachineNotAnswering`; these check it against the
/// errors the engine really throws, not ones made up for the purpose. The first dials 192.0.2.1, an address set
/// aside for documentation (RFC 5737) that no machine answers: the network drops it, or says there is no route.
@Suite("A machine that doesn't answer, as the real transport meets it")
struct SSHMachineNotAnsweringTests {
    private struct AnyPassword: SSHCredentialResolver {
        func resolve(_ reference: SSHCredentialReference, for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential {
            .password(SecureBytes(Data("unused".utf8)))
        }
    }

    private func transport(host: String, port: Int) -> SSHTransport {
        let hop = SSHHop(displayName: "nobody", endpoint: SSHEndpoint(host: host, port: port, username: "ann"),
                         credential: .custom("test"))
        return SSHTransport(route: SSHRoute(target: hop), credentials: AnyPassword(),
                            trustStore: InMemoryHostTrustStore(), trustDecider: TrustEverythingThisRun())
    }

    @Test("an address nothing answers fails within the connect timeout, as the machine not answering",
          .timeLimit(.minutes(1)))
    func nothingAnswers() async {
        let started = ContinuousClock.now
        do {
            try await transport(host: "192.0.2.1", port: 22).connect()
            Issue.record("connected to an address nothing answers")
        } catch {
            let waited = ContinuousClock.now - started
            #expect(SSHTransportError.isMachineNotAnswering(error), "\(String(reflecting: error))")
            #expect(waited < .seconds(20), "the 15 s timeout, not Citadel's 30: waited \(waited)")
        }
    }

    @Test("a closed port is the machine answering, not the machine missing", .timeLimit(.minutes(1)))
    func closedPortAnswers() async throws {
        // A port bound and closed again on the loopback: nothing listens there now.
        let port = try Self.freshClosedPort()
        do {
            try await transport(host: "127.0.0.1", port: port).connect()
            Issue.record("connected to a closed port")
        } catch {
            #expect(!SSHTransportError.isMachineNotAnswering(error), "\(String(reflecting: error))")
        }
    }

    /// A TCP port on 127.0.0.1 that was free a moment ago and has nothing listening on it.
    private static func freshClosedPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0 }
        }
        guard bound else { throw POSIXError(.EADDRINUSE) }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
