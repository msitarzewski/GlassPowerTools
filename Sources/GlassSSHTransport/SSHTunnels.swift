import Foundation
import NIOCore
import NIOPosix
import os

/// Opens a channel to `host:port` on the far side. The transport provides SSH direct-tcpip
/// channels; tests provide plain TCP ones.
public protocol SSHDirectChannelProvider: Sendable {
    func openDirectChannel(toHost host: String, port: Int) async throws -> any Channel
}

/// Tracks accepted local sockets separately from the listening socket. Closing only the
/// listener prevents new accepts but does not terminate clients already blocked in a forwarding
/// pipe. Moved from glas.sh `PortForwardChildChannelRegistry` (PortForwardManager.swift:86).
final class SSHTunnelChildRegistry: Sendable {
    private struct State {
        var channels: [ObjectIdentifier: any Channel] = [:]
        var isClosing = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func insert(_ channel: any Channel) -> Bool {
        state.withLock {
            guard !$0.isClosing else { return false }
            $0.channels[ObjectIdentifier(channel)] = channel
            return true
        }
    }

    func remove(_ channel: any Channel) {
        state.withLock { _ = $0.channels.removeValue(forKey: ObjectIdentifier(channel)) }
    }

    var count: Int { state.withLock { $0.channels.count } }

    func closeAllWithoutWaiting() {
        for channel in removeAll() { channel.close(promise: nil) }
    }

    func closeAllAndWait() async {
        let channels = removeAll()
        await withTaskGroup(of: Void.self) { group in
            for channel in channels {
                group.addTask { try? await channel.close() }
            }
        }
    }

    private func removeAll() -> [any Channel] {
        state.withLock {
            $0.isClosing = true
            let existing = Array($0.channels.values)
            $0.channels.removeAll(keepingCapacity: false)
            return existing
        }
    }
}

/// A local listener whose accepted connections are piped through the SSH transport — either
/// to one fixed remote target (a `-L` forward) or to whatever a SOCKS5 client asks for (`-D`).
/// Closing waits for the listener and every accepted client to shut down.
public final class SSHTunnel: Sendable {
    public enum Kind: Sendable, Equatable {
        case local(remoteHost: String, remotePort: Int)
        case socks5
    }

    public let kind: Kind
    /// The port actually bound on 127.0.0.1 (useful when `0` was requested).
    public let localPort: Int
    private let listener: any Channel
    private let registry: SSHTunnelChildRegistry
    private let task: Task<Void, Never>
    private let closed = OSAllocatedUnfairLock(initialState: false)

    init(kind: Kind, localPort: Int, listener: any Channel, registry: SSHTunnelChildRegistry, task: Task<Void, Never>) {
        self.kind = kind
        self.localPort = localPort
        self.listener = listener
        self.registry = registry
        self.task = task
    }

    public var isClosed: Bool { closed.withLock { $0 } }
    /// Accepted client connections currently open.
    public var activeConnectionCount: Int { registry.count }

    public func close() async {
        let alreadyClosed = closed.withLock { was in
            defer { was = true }
            return was
        }
        guard !alreadyClosed else { return }
        task.cancel()
        try? await listener.close()
        await registry.closeAllAndWait()
        await task.value
    }

    deinit {
        if !closed.withLock({ $0 }) {
            task.cancel()
            listener.close(promise: nil)
            registry.closeAllWithoutWaiting()
        }
    }
}

enum SSHTunnelFactory {
    private static let logger = Logger.sshTransport

    private static func initializeAcceptedClient(
        _ childChannel: any Channel,
        continuation: AsyncStream<NIOAsyncChannel<ByteBuffer, ByteBuffer>>.Continuation,
        registry: SSHTunnelChildRegistry
    ) -> EventLoopFuture<Void> {
        childChannel.eventLoop.makeCompletedFuture {
            let asyncChild = try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: childChannel)
            guard registry.insert(childChannel) else {
                childChannel.close(promise: nil)
                return
            }
            if case .terminated = continuation.yield(asyncChild) {
                registry.remove(childChannel)
                childChannel.close(promise: nil)
            }
        }
    }

    /// Binds 127.0.0.1:`localPort` (0 for any) and serves accepted clients with `handle`.
    static func bind(
        kind: SSHTunnel.Kind,
        localPort: Int,
        handle: @escaping @Sendable (NIOAsyncChannel<ByteBuffer, ByteBuffer>) async -> Void
    ) async throws -> SSHTunnel {
        let registry = SSHTunnelChildRegistry()
        let (acceptedClients, continuation) = AsyncStream<NIOAsyncChannel<ByteBuffer, ByteBuffer>>.makeStream()
        let listener: any Channel
        do {
            listener = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { childChannel in
                    initializeAcceptedClient(childChannel, continuation: continuation, registry: registry)
                }
                .bind(host: "127.0.0.1", port: localPort)
                .get()
        } catch {
            continuation.finish()
            throw SSHTransportError.tunnelBindFailed(port: localPort, reason: SSHTransportError.bindFailureReason(error, port: localPort))
        }
        let boundPort = listener.localAddress?.port ?? localPort

        let task = Task<Void, Never> {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    // When the listener closes, finish the stream so the accept loop ends.
                    try? await listener.closeFuture.get()
                    continuation.finish()
                }
                group.addTask {
                    await withDiscardingTaskGroup { connections in
                        for await client in acceptedClients {
                            connections.addTask {
                                defer { registry.remove(client.channel) }
                                await handle(client)
                            }
                        }
                    }
                }
                await group.next()
                continuation.finish()
                group.cancelAll()
            }
        }
        return SSHTunnel(kind: kind, localPort: boundPort, listener: listener, registry: registry, task: task)
    }

    /// `NIOAsyncChannel` must be created on the channel's own event loop (NIOCore
    /// asserts it); provider channels arrive on arbitrary tasks, so hop there first.
    static func wrap(_ channel: any Channel) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        try await channel.eventLoop.submit {
            try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
        }.get()
    }

    /// Establish a channel to the remote target and pipe data bidirectionally with the local
    /// socket. Moved from glas.sh `handleLocalConnection` (PortForwardManager.swift:445).
    static func pipe(
        localClient: NIOAsyncChannel<ByteBuffer, ByteBuffer>,
        remoteHost: String,
        remotePort: Int,
        provider: any SSHDirectChannelProvider
    ) async {
        do {
            let remoteChannel = try await provider.openDirectChannel(toHost: remoteHost, port: remotePort)
            let remote = try await wrap(remoteChannel)
            try await localClient.executeThenClose { localInbound, localOutbound in
                try await remote.executeThenClose { remoteInbound, remoteOutbound in
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for try await data in localInbound { try await remoteOutbound.write(data) }
                        }
                        group.addTask {
                            for try await data in remoteInbound { try await localOutbound.write(data) }
                        }
                        defer { group.cancelAll() }
                        try await group.next()
                    }
                }
            }
        } catch {
            logger.debug("Port forward connection ended")
            try? await localClient.channel.close()
        }
    }

    /// Perform a SOCKS5 handshake on a local client, then tunnel to the requested target.
    /// Moved from glas.sh `handleSOCKS5Connection` (PortForwardManager.swift:965).
    static func serveSOCKS5(
        localClient: NIOAsyncChannel<ByteBuffer, ByteBuffer>,
        provider: any SSHDirectChannelProvider,
        credentials: SOCKS5CredentialBytes,
        handshakePermit: SOCKS5ConnectionPermit
    ) async {
        let handshakeTimeoutTask = Task {
            do {
                try await Task.sleep(for: SOCKS5Protocol.handshakeTimeout)
                try Task.checkCancellation()
                try? await localClient.channel.close()
            } catch {
                // Cancellation means the complete handshake beat the deadline.
            }
        }
        defer { handshakeTimeoutTask.cancel() }
        do {
            try await localClient.executeThenClose { localInbound, localOutbound in
                var buffered = ByteBuffer()
                var iterator = localInbound.makeAsyncIterator()

                var greeting = SOCKS5Protocol.parseGreeting(from: &buffered)
                while case .incomplete = greeting {
                    guard buffered.readableBytes < SOCKS5Protocol.maximumGreetingBytes,
                          var chunk = try await iterator.next() else { return }
                    guard SOCKS5Protocol.appendHandshakeBytes(&chunk, to: &buffered) else { return }
                    greeting = SOCKS5Protocol.parseGreeting(from: &buffered)
                }
                switch greeting {
                case .selectUsernamePassword:
                    try await localOutbound.write(ByteBuffer(bytes: [0x05, 0x02]))
                case .rejectAuthenticationMethods:
                    try await localOutbound.write(ByteBuffer(bytes: [0x05, 0xFF]))
                    return
                case .invalidVersion, .incomplete:
                    return
                }

                var authentication = SOCKS5Protocol.parseAuthentication(from: &buffered)
                while case .incomplete = authentication {
                    guard buffered.readableBytes < SOCKS5Protocol.maximumAuthenticationBytes,
                          var chunk = try await iterator.next() else { return }
                    guard SOCKS5Protocol.appendHandshakeBytes(&chunk, to: &buffered) else { return }
                    authentication = SOCKS5Protocol.parseAuthentication(from: &buffered)
                }
                let authenticated: Bool
                switch authentication {
                case .authenticate(let presented):
                    authenticated = SOCKS5Protocol.authenticate(presented: presented, expected: credentials)
                case .invalidVersion, .invalidCredentials, .incomplete:
                    authenticated = false
                }
                try await localOutbound.write(ByteBuffer(bytes: [0x01, authenticated ? 0x00 : 0x01]))
                guard authenticated else { return }

                var request = SOCKS5Protocol.parseConnectRequest(from: &buffered)
                while case .incomplete = request {
                    guard buffered.readableBytes < SOCKS5Protocol.maximumConnectRequestBytes,
                          var chunk = try await iterator.next() else { return }
                    guard SOCKS5Protocol.appendHandshakeBytes(&chunk, to: &buffered) else { return }
                    request = SOCKS5Protocol.parseConnectRequest(from: &buffered)
                }
                let target: SOCKS5Target
                switch request {
                case .connect(let parsed): target = parsed
                case .unsupportedCommand: try await localOutbound.write(SOCKS5Protocol.reply(code: 0x07)); return
                case .unsupportedAddressType: try await localOutbound.write(SOCKS5Protocol.reply(code: 0x08)); return
                case .invalidReservedByte, .invalidAddress: try await localOutbound.write(SOCKS5Protocol.reply(code: 0x01)); return
                case .invalidVersion, .incomplete: return
                }

                let remoteChannel: any Channel
                do {
                    remoteChannel = try await provider.openDirectChannel(toHost: target.host, port: target.port)
                } catch {
                    try await localOutbound.write(SOCKS5Protocol.reply(code: 0x01))
                    return
                }
                handshakeTimeoutTask.cancel()
                await handshakePermit.release()

                let remote = try await wrap(remoteChannel)
                try await localOutbound.write(SOCKS5Protocol.reply(code: 0x00))

                let pending = buffered
                try await remote.executeThenClose { remoteInbound, remoteOutbound in
                    let remoteToLocal = Task {
                        defer { localClient.channel.close(promise: nil) }
                        for try await data in remoteInbound { try await localOutbound.write(data) }
                    }
                    do {
                        if pending.readableBytes > 0 { try await remoteOutbound.write(pending) }
                        while let data = try await iterator.next() { try await remoteOutbound.write(data) }
                    } catch {
                        remoteToLocal.cancel()
                        _ = try? await remoteToLocal.value
                        throw error
                    }
                    remoteToLocal.cancel()
                    do { try await remoteToLocal.value } catch is CancellationError {}
                }
            }
        } catch {
            logger.debug("SOCKS5 connection ended")
            try? await localClient.channel.close()
        }
    }

    // MARK: Public constructors used by SSHTransport and by tests

    static func localForward(localPort: Int, remoteHost: String, remotePort: Int, provider: any SSHDirectChannelProvider) async throws -> SSHTunnel {
        try await bind(kind: .local(remoteHost: remoteHost, remotePort: remotePort), localPort: localPort) { client in
            await pipe(localClient: client, remoteHost: remoteHost, remotePort: remotePort, provider: provider)
        }
    }

    static func socks5(localPort: Int, credentials: SOCKS5Credentials, provider: any SSHDirectChannelProvider) async throws -> SSHTunnel {
        let limiter = SOCKS5ConnectionLimiter(maximumConnections: SOCKS5Protocol.maximumConcurrentConnections)
        let bytes = credentials.bytes
        return try await bind(kind: .socks5, localPort: localPort) { client in
            guard await limiter.acquire() else {
                try? await client.channel.close()
                return
            }
            let permit = SOCKS5ConnectionPermit(limiter: limiter)
            await serveSOCKS5(localClient: client, provider: provider, credentials: bytes, handshakePermit: permit)
            await permit.release()
        }
    }
}

/// A remote (`-R`) forward: the server listens and sends connections back through the tunnel.
/// `boundPort` resolves once the server confirms the listener; `close()` cancels it.
public final class SSHRemoteForward: Sendable {
    public let remoteHost: String
    public let requestedRemotePort: Int
    public let localHost: String
    public let localPort: Int
    private let task: Task<Void, Error>
    private let bound: AsyncStream<Int>
    private let boundValue = OSAllocatedUnfairLock<Int?>(initialState: nil)

    init(remoteHost: String, requestedRemotePort: Int, localHost: String, localPort: Int, run: @escaping @Sendable (_ onOpen: @escaping @Sendable (Int) -> Void) async throws -> Void) {
        self.remoteHost = remoteHost
        self.requestedRemotePort = requestedRemotePort
        self.localHost = localHost
        self.localPort = localPort
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        bound = stream
        let boundValue = self.boundValue
        task = Task {
            defer { continuation.finish() }
            try await run { port in
                boundValue.withLock { $0 = port }
                continuation.yield(port)
            }
        }
    }

    /// The port the server actually bound, once known. Returns `nil` if the forward ended first.
    public func boundPort() async -> Int? {
        if let port = boundValue.withLock({ $0 }) { return port }
        for await port in bound { return port }
        return boundValue.withLock { $0 }
    }

    /// Waits for the forward to end; throws the reason if it failed.
    public func waitUntilClosed() async throws {
        try await task.value
    }

    public func close() async {
        task.cancel()
        _ = try? await task.value
    }
}
