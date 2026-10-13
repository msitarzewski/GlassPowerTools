import Foundation
import Testing
import NIOCore
import NIOPosix
import os
@testable import GlassSSHTransport

/// B-X25 (2026-10-12): a connection that went silent while the device slept is found when it is
/// asked to answer, and shown lost. Against the test host (gated as the other real-host tests),
/// through a relay that can go silent — it stops passing bytes without closing anything, which is
/// what a connection looks like after a laptop lid has been shut for a while.
@Suite("A silent connection is found after a wake (gated)", .serialized)
struct SSHWakeLivenessTests {
    @Test func aConnectionThatWentSilentIsFoundLost() async throws {
        do { try IntegrationEnvironment.skipUnlessConfigured() } catch { print("NOT RUN:", error); return }
        let relay = try await SilenceableRelay.start(to: IntegrationEnvironment.host!, port: IntegrationEnvironment.port)
        defer { relay.stop() }
        let endpoint = SSHEndpoint(host: "127.0.0.1", port: relay.port, username: IntegrationEnvironment.user!)
        let hop = SSHHop(displayName: "test host", endpoint: endpoint, credential: .custom("integration"),
                         options: SSHConnectionOptions(keepAliveInterval: 0))
        let transport = SSHTransport(route: SSHRoute(target: hop), credentials: EnvironmentCredentialResolver(),
                                     trustStore: InMemoryHostTrustStore(), trustDecider: TrustEverythingThisRun())
        try await transport.connect()

        await SSHLiveTransports.shared.checkAllAlive(timeout: .seconds(3))
        #expect(await transport.isConnected, "a connection that answers was ended")

        relay.silence()
        let started = ContinuousClock.now
        await SSHLiveTransports.shared.checkAllAlive(timeout: .seconds(3))
        #expect(ContinuousClock.now - started < .seconds(6))
        #expect(!(await transport.isConnected), "a connection that no longer answers was taken as alive")
        #expect(!(await SSHLiveTransports.shared.contains(transport)), "a lost transport stayed on the list")
        await transport.close()
    }
}

/// A TCP relay to the test host that can be made to swallow everything, in both directions,
/// while every socket stays open — or to cut every connection through it (`cut`).
final class SilenceableRelay: Sendable {
    private let group: MultiThreadedEventLoopGroup
    private let listener: any Channel
    private let silenced: OSAllocatedUnfairLock<Bool>
    private let connections: OSAllocatedUnfairLock<[any Channel]>
    let port: Int

    private init(group: MultiThreadedEventLoopGroup, listener: any Channel, silenced: OSAllocatedUnfairLock<Bool>,
                 connections: OSAllocatedUnfairLock<[any Channel]>) {
        self.group = group
        self.listener = listener
        self.silenced = silenced
        self.connections = connections
        self.port = listener.localAddress?.port ?? 0
    }

    static func start(to host: String, port: Int) async throws -> SilenceableRelay {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let silenced = OSAllocatedUnfairLock(initialState: false)
        let connections = OSAllocatedUnfairLock<[any Channel]>(initialState: [])
        let listener = try await ServerBootstrap(group: group)
            .childChannelOption(.autoRead, value: false)
            .childChannelInitializer { inbound in
                ClientBootstrap(group: group).connect(host: host, port: port).flatMap { outbound in
                    connections.withLock { $0 += [inbound, outbound] }
                    return inbound.pipeline.addHandler(Pass(to: outbound, silenced: silenced)).flatMap {
                        outbound.pipeline.addHandler(Pass(to: inbound, silenced: silenced))
                    }.flatMap { inbound.setOption(ChannelOptions.autoRead, value: true) }
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        return SilenceableRelay(group: group, listener: listener, silenced: silenced, connections: connections)
    }

    func silence() { silenced.withLock { $0 = true } }

    /// Closes every connection through the relay, both sides: what the client sees when the
    /// server goes down or the network drops it.
    func cut() {
        for channel in connections.withLock({ $0 }) { channel.close(promise: nil) }
    }

    func stop() {
        listener.close(promise: nil)
        try? group.syncShutdownGracefully()
    }

    private final class Pass: ChannelInboundHandler, Sendable {
        typealias InboundIn = ByteBuffer
        private let peer: any Channel
        private let silenced: OSAllocatedUnfairLock<Bool>

        init(to peer: any Channel, silenced: OSAllocatedUnfairLock<Bool>) {
            self.peer = peer
            self.silenced = silenced
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            guard !silenced.withLock({ $0 }) else { return }
            peer.writeAndFlush(unwrapInboundIn(data), promise: nil)
        }

        func channelInactive(context: ChannelHandlerContext) {
            peer.close(promise: nil)
        }
    }
}
