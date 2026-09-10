import Foundation
import Testing
import NIOCore
import NIOPosix
@testable import GlassSSHTransport

/// A plain TCP "remote side" so the tunnel machinery is exercised without an SSH server.
struct TCPDirectChannelProvider: SSHDirectChannelProvider {
    func openDirectChannel(toHost host: String, port: Int) async throws -> any Channel {
        try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton).connect(host: host, port: port).get()
    }
}

/// Fails every channel request — the tunnel must reply cleanly and close the client.
struct RefusingDirectChannelProvider: SSHDirectChannelProvider {
    func openDirectChannel(toHost host: String, port: Int) async throws -> any Channel {
        throw SSHTransportError.notConnected
    }
}

final class EchoHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(data, promise: nil)
    }
}

enum EchoServer {
    static func start() async throws -> (channel: any Channel, port: Int) {
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { $0.pipeline.addHandler(EchoHandler()) }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        return (channel, channel.localAddress!.port!)
    }
}

enum TCPClient {
    static func connect(port: Int) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton).connect(host: "127.0.0.1", port: port) { channel in
            channel.eventLoop.makeCompletedFuture { try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel) }
        }
    }

    /// Writes `bytes`, then reads until `expected` bytes have arrived or the peer closes.
    static func exchange(_ client: NIOAsyncChannel<ByteBuffer, ByteBuffer>, send bytes: [UInt8], expect expected: Int) async throws -> [UInt8] {
        try await client.executeThenClose { inbound, outbound in
            try await outbound.write(ByteBuffer(bytes: bytes))
            var received: [UInt8] = []
            for try await chunk in inbound {
                received.append(contentsOf: chunk.readableBytesView)
                if received.count >= expected { break }
            }
            return received
        }
    }
}

@Suite("Tunnels", .serialized)
struct SSHTunnelTests {
    @Test func localForwardPipesBothWaysAndCloseWaitsForClients() async throws {
        let echo = try await EchoServer.start()
        defer { echo.channel.close(promise: nil) }
        let tunnel = try await SSHTunnelFactory.localForward(localPort: 0, remoteHost: "127.0.0.1", remotePort: echo.port, provider: TCPDirectChannelProvider())
        #expect(tunnel.localPort > 0)
        #expect(tunnel.kind == .local(remoteHost: "127.0.0.1", remotePort: echo.port))

        let client = try await TCPClient.connect(port: tunnel.localPort)
        let echoed = try await TCPClient.exchange(client, send: Array("hello through the tunnel".utf8), expect: 24)
        #expect(String(decoding: echoed, as: UTF8.self) == "hello through the tunnel")

        await tunnel.close()
        #expect(tunnel.isClosed)
        #expect(tunnel.activeConnectionCount == 0)
        await #expect(throws: (any Error).self, "the listener is gone after close") {
            _ = try await TCPClient.connect(port: tunnel.localPort)
        }
    }

    @Test func bindingAnOccupiedPortFailsWithTheGlasSHMessage() async throws {
        let echo = try await EchoServer.start()
        defer { echo.channel.close(promise: nil) }
        let first = try await SSHTunnelFactory.localForward(localPort: 0, remoteHost: "127.0.0.1", remotePort: echo.port, provider: TCPDirectChannelProvider())
        defer { Task { await first.close() } }
        do {
            _ = try await SSHTunnelFactory.localForward(localPort: first.localPort, remoteHost: "127.0.0.1", remotePort: echo.port, provider: TCPDirectChannelProvider())
            Issue.record("second bind on the same port should fail")
        } catch let error as SSHTransportError {
            guard case .tunnelBindFailed(let port, let reason) = error else { Issue.record("unexpected \(error)"); return }
            #expect(port == first.localPort)
            #expect(reason == "Port \(first.localPort) is already in use.")
        }
        await first.close()
    }

    @Test func refusedRemoteChannelClosesTheLocalClientCleanly() async throws {
        let tunnel = try await SSHTunnelFactory.localForward(localPort: 0, remoteHost: "127.0.0.1", remotePort: 1, provider: RefusingDirectChannelProvider())
        let client = try await TCPClient.connect(port: tunnel.localPort)
        // The tunnel closes the local socket without ever writing to it; depending on timing the
        // client sees EOF (empty read) or a reset (unread bytes were pending). Both mean "closed".
        do {
            let received = try await TCPClient.exchange(client, send: [1, 2, 3], expect: 1)
            #expect(received.isEmpty, "nothing comes back; the peer closes")
        } catch let error as IOError where error.errnoCode == ECONNRESET {
            // closed by reset — acceptable
        }
        await tunnel.close()
    }

    @Test func socks5ProxyAuthenticatesConnectsAndPipes() async throws {
        let echo = try await EchoServer.start()
        defer { echo.channel.close(promise: nil) }
        let credentials = try #require(SOCKS5Credentials(username: "user", password: "secret"))
        let tunnel = try await SSHTunnelFactory.socks5(localPort: 0, credentials: credentials, provider: TCPDirectChannelProvider())
        #expect(tunnel.kind == .socks5)

        let client = try await TCPClient.connect(port: tunnel.localPort)
        let payload = Array("proxied".utf8)
        var request: [UInt8] = [0x05, 0x01, 0x02]                                   // greeting: username/password
        request += [0x01, 0x04] + Array("user".utf8) + [0x06] + Array("secret".utf8) // RFC 1929
        request += [0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, UInt8(echo.port >> 8), UInt8(echo.port & 0xFF)] // CONNECT 127.0.0.1:port
        request += payload
        let expectedReplies = 2 + 2 + 10
        let received = try await TCPClient.exchange(client, send: request, expect: expectedReplies + payload.count)
        #expect(Array(received.prefix(2)) == [0x05, 0x02])
        #expect(Array(received[2..<4]) == [0x01, 0x00])
        #expect(Array(received[4..<6]) == [0x05, 0x00])
        #expect(Array(received.suffix(payload.count)) == payload, "data after the handshake reaches the target and echoes back")
        await tunnel.close()
    }

    @Test func socks5ProxyRejectsWrongPassword() async throws {
        let credentials = try #require(SOCKS5Credentials(username: "user", password: "secret"))
        let tunnel = try await SSHTunnelFactory.socks5(localPort: 0, credentials: credentials, provider: RefusingDirectChannelProvider())
        let client = try await TCPClient.connect(port: tunnel.localPort)
        var request: [UInt8] = [0x05, 0x01, 0x02]
        request += [0x01, 0x04] + Array("user".utf8) + [0x05] + Array("wrong".utf8)
        let received = try await TCPClient.exchange(client, send: request, expect: 4)
        #expect(Array(received.prefix(2)) == [0x05, 0x02])
        #expect(Array(received[2..<4]) == [0x01, 0x01], "authentication failure reply, then close")
        await tunnel.close()
    }

    @Test func remoteForwardHandleReportsBoundPortAndFailure() async throws {
        let forward = SSHRemoteForward(remoteHost: "0.0.0.0", requestedRemotePort: 0, localHost: "127.0.0.1", localPort: 1) { onOpen in
            onOpen(45_000)
            try await Task.sleep(for: .seconds(5))
        }
        #expect(await forward.boundPort() == 45_000)
        await forward.close()

        let failing = SSHRemoteForward(remoteHost: "0.0.0.0", requestedRemotePort: 0, localHost: "127.0.0.1", localPort: 1) { _ in
            throw SSHTransportError.notConnected
        }
        #expect(await failing.boundPort() == nil)
        await #expect(throws: SSHTransportError.notConnected) { try await failing.waitUntilClosed() }
    }
}
