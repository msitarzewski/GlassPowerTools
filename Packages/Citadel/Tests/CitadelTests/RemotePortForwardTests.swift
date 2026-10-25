@testable import Citadel
import Crypto
import NIO
import NIOSSH
import XCTest

final class RemotePortForwardTests: XCTestCase {
    /// The forwards the server opened. Counted, because a check inside the callback alone passes when
    /// the callback never runs.
    private final class Opened: @unchecked Sendable {
        private let lock = NSLock()
        private var forwards: [SSHRemotePortForward] = []
        func add(_ forward: SSHRemotePortForward) { lock.withLock { forwards.append(forward) } }
        var all: [SSHRemotePortForward] { lock.withLock { forwards } }
    }

    /// Waits up to 30 seconds for `count` forwards to open.
    private func wait(for count: Int, in opened: Opened) async throws {
        let deadline = Date().addingTimeInterval(30)
        while opened.all.count < count, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Test that remote port forward request is sent correctly
    func testRemotePortForwardRequest() async throws {
        // This test requires an SSH server that supports remote port forwarding
        // Check if we have the environment variables set for SSH testing
        guard let host = ProcessInfo.processInfo.environment["SSH_HOST"],
              let portString = ProcessInfo.processInfo.environment["SSH_PORT"],
              let port = Int(portString),
              let username = ProcessInfo.processInfo.environment["SSH_USERNAME"],
              let password = ProcessInfo.processInfo.environment["SSH_PASSWORD"] else {
            throw XCTSkip("SSH environment variables not set (SSH_HOST, SSH_PORT, SSH_USERNAME, SSH_PASSWORD)")
        }

        print("Connecting to SSH server at \(host):\(port)...")

        // Connect to SSH server
        let client = try await SSHClient.connect(
            host: host,
            port: port,
            authenticationMethod: .passwordBased(username: username, password: password),
            hostKeyValidator: .acceptAnything(),
            reconnect: .never
        )

        defer {
            Task {
                try? await client.close()
            }
        }

        print("Connected. Requesting remote port forward...")

        // Request remote port forward on a random high port
        // Use port 0 to let the server choose
        let opened = Opened()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await client.withRemotePortForward(
                    host: "127.0.0.1",
                    port: 0 // Let server choose port
                ) { forward in
                    opened.add(forward)
                } handleChannel: { channel, forwardedInfo in
                    print("Received forwarded connection from \(forwardedInfo.originatorAddress)")

                    // Just close the channel for this test
                    return channel.close()
                }
            }

            try await self.wait(for: 1, in: opened)
            group.cancelAll()
        }
        XCTAssertEqual(opened.all.count, 1, "the forward opened")
        XCTAssertGreaterThan(opened.all.first?.boundPort ?? 0, 0, "Server should have bound to a port")
        XCTAssertEqual(opened.all.first?.host, "127.0.0.1")
    }

    /// Test that we can create and cancel multiple forwards
    func testMultipleRemotePortForwards() async throws {
        guard let host = ProcessInfo.processInfo.environment["SSH_HOST"],
              let portString = ProcessInfo.processInfo.environment["SSH_PORT"],
              let port = Int(portString),
              let username = ProcessInfo.processInfo.environment["SSH_USERNAME"],
              let password = ProcessInfo.processInfo.environment["SSH_PASSWORD"] else {
            throw XCTSkip("SSH environment variables not set")
        }

        let client = try await SSHClient.connect(
            host: host,
            port: port,
            authenticationMethod: .passwordBased(username: username, password: password),
            hostKeyValidator: .acceptAnything(),
            reconnect: .never
        )

        defer {
            Task {
                try? await client.close()
            }
        }

        let opened = Opened()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    try await client.withRemotePortForward(
                        host: "127.0.0.1",
                        port: 0
                    ) { forward in
                        opened.add(forward)
                    } handleChannel: { channel, forwardedInfo in
                        print("Received forwarded connection from \(forwardedInfo.originatorAddress)")

                        // Just close the channel for this test
                        return channel.close()
                    }
                }
            }

            try await self.wait(for: 3, in: opened)
            group.cancelAll()
        }
        XCTAssertEqual(opened.all.count, 3, "all three forwards opened")
        XCTAssertTrue(opened.all.allSatisfy { $0.boundPort > 0 && $0.host == "127.0.0.1" })
        XCTAssertEqual(Set(opened.all.map(\.boundPort)).count, 3, "each on a port of its own")
    }
}
