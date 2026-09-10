import Foundation
import Citadel
import NIOCore
import NIOSSH
import GlasSecretStore
import os

/// Where a connection attempt is. glas.sh drove its progress UI from the same stages
/// (`ConnectionProgressStage`, Models.swift:1155).
public enum SSHConnectionStage: Sendable, Equatable {
    case resolvingHost
    case openingSocket(port: Int)
    case negotiatingSecurity
    case negotiatingCompatibility
    case authenticating
    case connectingJump(index: Int, count: Int, displayName: String)
    case jumpConnected(index: Int, count: Int, displayName: String)
    case tunnelingToTarget(host: String, port: Int)
}

public enum SSHTransportEvent: Sendable, Equatable {
    case stage(SSHConnectionStage)
    case connected
    case keepAliveMissed(count: Int, maximum: Int)
    /// The transport declared itself lost (keep-alives exhausted) and closed.
    case lost(String)
    case closed
}

/// One authenticated SSH connection to a route, shared by every session on that route.
/// Moved from glas.sh `SharedSSHTransport` + the connection half of `SSHConnection`
/// (Models.swift:1909-2320); the terminal-specific half became `SSHShellChannel`.
///
/// Ownership: callers `acquire(owner:)` and `release(owner:)`; the final release closes the
/// connection. `close()` closes regardless. A closing transport refuses new owners.
public actor SSHTransport {
    public nonisolated let route: SSHRoute
    public nonisolated let identity: SSHTransportIdentity
    public nonisolated let events: AsyncStream<SSHTransportEvent>

    private let credentials: any SSHCredentialResolver
    private let trustStore: any SSHHostTrustStore
    private let trustDecider: (any SSHHostTrustDecider)?
    private let eventContinuation: AsyncStream<SSHTransportEvent>.Continuation
    private let challengeBox = SSHHostKeyChallengeBox()

    private var client: SSHClient?
    private var jumpClients: [SSHClient] = []
    private var connecting = false
    private(set) public var ownership = SSHTransportOwnership()
    private var keepAliveTask: Task<Void, Never>?
    private var missedKeepAlives = 0
    /// Keys trusted for this transport's lifetime only (`.trust(remember: false)`), by host:port.
    private var sessionTrustedKeys: [String: Set<String>] = [:]

    public init(
        route: SSHRoute,
        credentials: any SSHCredentialResolver,
        trustStore: any SSHHostTrustStore,
        trustDecider: (any SSHHostTrustDecider)? = nil
    ) {
        self.route = route
        self.identity = route.identity
        self.credentials = credentials
        self.trustStore = trustStore
        self.trustDecider = trustDecider
        let (stream, continuation) = AsyncStream<SSHTransportEvent>.makeStream()
        events = stream
        eventContinuation = continuation
    }

    /// The GlasSecretStore-backed configuration: credentials and pinned host keys from the
    /// family's shared Keychain group.
    public init(
        route: SSHRoute,
        secrets: SecretStoreConfiguration,
        trustDecider: (any SSHHostTrustDecider)? = nil
    ) {
        self.init(
            route: route,
            credentials: SecretStoreCredentialResolver(configuration: secrets),
            trustStore: SecretStoreHostTrustStore(configuration: secrets),
            trustDecider: trustDecider
        )
    }

    public var isConnected: Bool { client?.isConnected == true }
    public var isClosing: Bool { ownership.isClosing }

    // MARK: Ownership

    @discardableResult
    public func acquire(owner: UUID) -> Bool { ownership.acquire(owner) }

    /// Releases one owner; closes the connection when the last owner leaves.
    public func release(owner: UUID) async {
        guard ownership.release(owner) else { return }
        await teardown(reason: .closed)
    }

    /// Closes regardless of owners.
    public func close() async {
        _ = ownership.forceClose()
        await teardown(reason: .closed)
    }

    private func teardown(reason: SSHTransportEvent) async {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        let closing = [client].compactMap { $0 } + jumpClients.reversed()
        client = nil
        jumpClients.removeAll()
        for c in closing {
            do { try await c.close() } catch {
                Logger.sshTransport.error("SSH client close failed; category=\(String(reflecting: type(of: error)), privacy: .public)")
            }
        }
        eventContinuation.yield(reason)
        eventContinuation.finish()
    }

    // MARK: Connect

    /// Connects (idempotent). Host-trust challenges go to the decider; with none, the
    /// challenge is thrown as `SSHHostTrustRequiredError` for the caller to handle and retry.
    public func connect() async throws {
        if isConnected { return }
        guard !ownership.isClosing else { throw SSHTransportError.notConnected }
        guard !connecting else { throw SSHTransportError.connectionFailed }
        connecting = true
        defer { connecting = false }

        while true {
            do {
                try await connectOnce()
                return
            } catch let trust as SSHHostTrustRequiredError {
                let challenge = trust.challenge
                guard route.trustPolicy == .ask, let trustDecider else {
                    throw trust
                }
                switch await trustDecider.decide(challenge) {
                case .trust(let remember):
                    if remember {
                        try trustStore.pin(challenge)
                    } else {
                        sessionTrustedKeys[InMemoryHostTrustStore.key(host: challenge.host, port: challenge.port), default: []].insert(challenge.keyDataBase64)
                    }
                    continue
                case .reject:
                    throw SSHTransportError.hostTrustRejected(challenge)
                }
            }
        }
    }

    private func authorizedKeys(for endpoint: SSHEndpoint) throws -> Set<String> {
        let stored = try trustStore.authorizedKeys(host: endpoint.host, port: endpoint.port)
        let session = sessionTrustedKeys[InMemoryHostTrustStore.key(host: endpoint.host, port: endpoint.port)] ?? []
        return stored.union(session)
    }

    private func validator(for hop: SSHHop) throws -> SSHHostKeyValidator {
        .custom(SSHPromptingHostKeyValidator(
            host: hop.endpoint.host,
            port: hop.endpoint.port,
            trustedKeyBase64Set: try authorizedKeys(for: hop.endpoint),
            challengeBox: challengeBox
        ))
    }

    private func authentication(for hop: SSHHop) async throws -> SSHAuthenticationMethod {
        let resolved = try await credentials.resolve(hop.credential, for: hop.endpoint)
        return try SSHAuthenticationBuilder.method(username: hop.endpoint.username, reference: hop.credential, credential: resolved)
    }

    private func connectOnce() async throws {
        let target = route.target
        try target.endpoint.validate()
        for jump in route.jumps { try jump.endpoint.validate() }
        challengeBox.clear()
        emit(.stage(.resolvingHost))

        let targetAuth = try await authentication(for: target)
        let targetValidator = try validator(for: target)
        emit(.stage(.openingSocket(port: target.endpoint.port)))
        emit(.stage(.negotiatingSecurity))

        var established: [SSHClient] = []
        do {
            if route.jumps.isEmpty {
                client = try await connectWithFallback(hop: target, authentication: targetAuth, validator: targetValidator)
            } else {
                let count = route.jumps.count
                let first = route.jumps[0]
                emit(.stage(.connectingJump(index: 1, count: count, displayName: first.displayName)))
                var current = try await connectWithFallback(
                    hop: first,
                    authentication: try await authentication(for: first),
                    validator: try validator(for: first)
                )
                established.append(current)
                emit(.stage(.jumpConnected(index: 1, count: count, displayName: first.displayName)))

                for (index, hop) in route.jumps.dropFirst().enumerated() {
                    emit(.stage(.connectingJump(index: index + 2, count: count, displayName: hop.displayName)))
                    let settings = SSHClientSettings(
                        host: hop.endpoint.host,
                        port: hop.endpoint.port,
                        authenticationMethod: { [auth = try await authentication(for: hop)] in auth },
                        hostKeyValidator: try validator(for: hop)
                    )
                    let next = try await current.jump(to: settings)
                    established.append(next)
                    current = next
                    emit(.stage(.jumpConnected(index: index + 2, count: count, displayName: hop.displayName)))
                }

                emit(.stage(.tunnelingToTarget(host: target.endpoint.host, port: target.endpoint.port)))
                let targetSettings = SSHClientSettings(
                    host: target.endpoint.host,
                    port: target.endpoint.port,
                    authenticationMethod: { targetAuth },
                    hostKeyValidator: targetValidator
                )
                client = try await current.jump(to: targetSettings)
                jumpClients = established
            }
        } catch {
            for c in established.reversed() { try? await c.close() }
            if let challenge = challengeBox.take() {
                throw SSHHostTrustRequiredError(challenge: challenge)
            }
            if let trust = error as? SSHHostTrustRequiredError { throw trust }
            throw error
        }
        emit(.stage(.authenticating))
        guard client != nil else { throw SSHTransportError.connectionFailed }
        emit(.connected)
        startKeepAlive(options: target.options)
    }

    /// Modern algorithms first, then one retry with Citadel's compatibility set when the hop
    /// allows it (glas.sh `connectWithFallback`).
    private func connectWithFallback(hop: SSHHop, authentication: SSHAuthenticationMethod, validator: SSHHostKeyValidator) async throws -> SSHClient {
        do {
            return try await SSHClient.connect(
                host: hop.endpoint.host,
                port: hop.endpoint.port,
                authenticationMethod: authentication,
                hostKeyValidator: validator,
                reconnect: .never,
                algorithms: SSHAlgorithms()
            )
        } catch {
            if let challenge = challengeBox.take() { throw SSHHostTrustRequiredError(challenge: challenge) }
            guard SSHTransportError.shouldRetryWithLegacyAlgorithms(error, enabled: hop.options.allowLegacyAlgorithms) else { throw error }
            emit(.stage(.negotiatingCompatibility))
            do {
                return try await SSHClient.connect(
                    host: hop.endpoint.host,
                    port: hop.endpoint.port,
                    authenticationMethod: authentication,
                    hostKeyValidator: validator,
                    reconnect: .never,
                    algorithms: .all
                )
            } catch {
                if let challenge = challengeBox.take() { throw SSHHostTrustRequiredError(challenge: challenge) }
                throw error
            }
        }
    }

    private nonisolated func emit(_ event: SSHTransportEvent) {
        eventContinuation.yield(event)
    }

    // MARK: Keep-alive (glas.sh `startKeepAliveTimer`, Models.swift:2570)

    private func startKeepAlive(options: SSHConnectionOptions) {
        guard options.keepAliveInterval > 0, let client else { return }
        keepAliveTask?.cancel()
        missedKeepAlives = 0
        let interval = options.keepAliveInterval
        let maximum = max(1, options.keepAliveMaxMissed)
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { break }
                do {
                    try await client.sendKeepAlive()
                    await self.resetKeepAliveCounter()
                } catch {
                    let missed = await self.recordMissedKeepAlive(maximum: maximum)
                    if missed >= maximum {
                        await self.lostConnection(reason: "Connection timed out (server not responding)")
                        break
                    }
                }
            }
        }
    }

    /// Data from the server proves liveness; shell channels call this on every chunk.
    func resetKeepAliveCounter() { missedKeepAlives = 0 }

    private func recordMissedKeepAlive(maximum: Int) -> Int {
        missedKeepAlives += 1
        emit(.keepAliveMissed(count: missedKeepAlives, maximum: maximum))
        return missedKeepAlives
    }

    private func lostConnection(reason: String) async {
        _ = ownership.forceClose()
        await teardown(reason: .lost(reason))
    }

    // MARK: Channels

    /// Opens an interactive shell on a PTY. The channel is ready to accept input on return.
    public func openShell(pty: SSHPTYRequest) async throws -> SSHShellChannel {
        guard let client, client.isConnected else { throw SSHTransportError.notConnected }
        let channel = SSHShellChannel(pty: pty) { [weak self] in
            Task { await self?.resetKeepAliveCounter() }
        }
        try await channel.start(client: client, options: route.target.options)
        return channel
    }

    /// Runs one command and returns its output (glas.sh `executeRemoteCommand`).
    public func execute(_ command: String, maxResponseBytes: Int = .max) async throws -> String {
        guard let client, client.isConnected else { throw SSHTransportError.notConnected }
        let buffer = try await client.executeCommand(command, maxResponseSize: maxResponseBytes)
        return String(buffer: buffer)
    }

    /// Opens an SFTP subsystem channel over the existing connection.
    public func openSFTP() async throws -> any SFTPSession {
        guard let client, client.isConnected else { throw SSHTransportError.notConnected }
        return try await CitadelSFTPSession.open(over: client)
    }

    /// A raw direct-tcpip channel to `host:port` as seen from the server. Low level; prefer
    /// `forward`.
    public func openDirectChannel(toHost host: String, port: Int) async throws -> any Channel {
        guard let client, client.isConnected else { throw SSHTransportError.notConnected }
        return try await client.createDirectTCPIPChannel(
            using: .init(targetHost: host, targetPort: port, originatorAddress: try .init(ipAddress: "127.0.0.1", port: 0)),
            initialize: { $0.eventLoop.makeSucceededVoidFuture() }
        )
    }

    /// A local (`-L`) forward: 127.0.0.1:`localPort` (0 for any free port) → `host:port` through
    /// the server. The database and desktop capabilities connect to `tunnel.localPort`.
    public func forward(localPort: Int = 0, toHost host: String, port: Int) async throws -> SSHTunnel {
        guard isConnected else { throw SSHTransportError.notConnected }
        return try await SSHTunnelFactory.localForward(localPort: localPort, remoteHost: host, remotePort: port, provider: DirectChannelProvider(transport: self))
    }

    /// A dynamic (`-D`) forward: a SOCKS5 proxy on 127.0.0.1:`localPort` with the given
    /// proxy credentials, tunnelling each request through the server.
    public func socks5(localPort: Int = 0, credentials: SOCKS5Credentials) async throws -> SSHTunnel {
        guard isConnected else { throw SSHTransportError.notConnected }
        return try await SSHTunnelFactory.socks5(localPort: localPort, credentials: credentials, provider: DirectChannelProvider(transport: self))
    }

    /// A remote (`-R`) forward: the server listens on `remoteHost:remotePort` and sends
    /// connections back to `localHost:localPort` here.
    public func remoteForward(remoteHost: String, remotePort: Int, toLocalHost localHost: String = "127.0.0.1", localPort: Int) async throws -> SSHRemoteForward {
        guard let client, client.isConnected else { throw SSHTransportError.notConnected }
        return SSHRemoteForward(remoteHost: remoteHost, requestedRemotePort: remotePort, localHost: localHost, localPort: localPort) { onOpen in
            try await client.runRemotePortForward(host: remoteHost, port: remotePort, forwardingTo: localHost, port: localPort) { forward in
                onOpen(forward.boundPort)
            }
        }
    }

    private struct DirectChannelProvider: SSHDirectChannelProvider {
        let transport: SSHTransport
        func openDirectChannel(toHost host: String, port: Int) async throws -> any Channel {
            try await transport.openDirectChannel(toHost: host, port: port)
        }
    }
}
