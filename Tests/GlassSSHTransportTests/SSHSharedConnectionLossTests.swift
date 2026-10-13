import Foundation
import Testing
import GlasSecretStore
@testable import GlassSSHTransport

/// B-X5 (2026-10-13): several terminals share one SSH connection (W21). When it went, one terminal
/// heard the connection's `.lost` — the events were one stream, which hands each event to one
/// reader — and the others saw their shell's channel close, took it for an `exit`, and closed.
@Suite("Every terminal on a lost shared connection hears so")
struct SSHSharedConnectionLossTests {
    private struct NoCredentials: SSHCredentialResolver {
        func resolve(_ reference: SSHCredentialReference, for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential {
            .password(SecureBytes(Data("x".utf8)))
        }
    }

    private func collect(_ events: AsyncStream<SSHTransportEvent>) async -> [SSHTransportEvent] {
        var collected: [SSHTransportEvent] = []
        for await event in events { collected.append(event) }
        return collected
    }

    /// The task's result, or nil if it is not done within `limit` — it is then cancelled, which
    /// ends an `AsyncStream` it is reading. A connection nobody declares lost never ends its events.
    private func value<T: Sendable>(of task: Task<T, Never>, within limit: Duration) async -> T? {
        let deadline = Task {
            try? await Task.sleep(for: limit)
            task.cancel()
        }
        defer { deadline.cancel() }
        let result = await task.value
        return Task.isCancelled || task.isCancelled ? nil : result
    }

    @Test("Each reader of a connection's events hears its end, and so does one that reads after it")
    func everyReaderHearsTheEnd() async {
        let route = SSHRoute(target: SSHHop(endpoint: SSHEndpoint(host: "127.0.0.1", port: 1, username: "me"),
                                            credential: .custom("none")))
        let transport = SSHTransport(route: route, credentials: NoCredentials(), trustStore: InMemoryHostTrustStore())
        let first = transport.events, second = transport.events
        await transport.close()
        #expect(await collect(first) == [.closed])
        #expect(await collect(second) == [.closed], "the second terminal on the connection heard nothing")
        #expect(await collect(transport.events) == [.closed])
    }

    /// Against the test host (gated as the other real-host tests), through a relay that cuts the
    /// connection — a server going down, or the network dropping it.
    @Test("Two shells on a connection that drops both end as a loss, not an exit (gated)")
    func bothShellsOnADroppedConnectionReportALoss() async throws {
        do { try IntegrationEnvironment.skipUnlessConfigured() } catch { print("NOT RUN:", error); return }
        let relay = try await SilenceableRelay.start(to: IntegrationEnvironment.host!, port: IntegrationEnvironment.port)
        defer { relay.stop() }
        let endpoint = SSHEndpoint(host: "127.0.0.1", port: relay.port, username: IntegrationEnvironment.user!)
        let hop = SSHHop(displayName: "test host", endpoint: endpoint, credential: .custom("integration"),
                         options: SSHConnectionOptions(keepAliveInterval: 0))
        let transport = SSHTransport(route: SSHRoute(target: hop), credentials: EnvironmentCredentialResolver(),
                                     trustStore: InMemoryHostTrustStore(), trustDecider: TrustEverythingThisRun())
        try await transport.connect()
        let first = try await transport.openShell(pty: SSHPTYRequest())
        let second = try await transport.openShell(pty: SSHPTYRequest())
        let firstEvents = Task { await collect(transport.events) }
        let secondEvents = Task { await collect(transport.events) }
        // Each terminal reads its shell's output until it ends.
        let firstDrained = Task { for await _ in first.output {} }
        let secondDrained = Task { for await _ in second.output {} }

        relay.cut()
        await firstDrained.value
        await secondDrained.value

        for (name, shell) in [("first", first), ("second", second)] {
            let exit = await shell.exit
            guard case .failed(let reason) = exit else {
                Issue.record("the \(name) shell ended as \(String(describing: exit)), read as an exit")
                continue
            }
            #expect(!reason.isEmpty)
        }
        for events in [firstEvents, secondEvents] {
            guard let heard = await value(of: events, within: .seconds(10)) else {
                Issue.record("a terminal on the connection never heard that it was lost")
                continue
            }
            guard case .lost = heard.last else {
                Issue.record("a terminal's events ended with \(String(describing: heard.last)), not the loss")
                continue
            }
        }
        await transport.close()
    }
}
