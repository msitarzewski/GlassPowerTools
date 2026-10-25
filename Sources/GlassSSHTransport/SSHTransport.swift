import Foundation
@preconcurrency import Citadel
import NIOCore
@preconcurrency import NIOSSH
import GlasSecretStore
import Crypto
import _CryptoExtras
import os

/// Algorithm policy for the whole engine (security review S4). RSA host keys are registered
/// once, deliberately, at engine load — NIOSSH's registry is process-wide, and glas.sh's
/// legacy fallback used to register them as a side effect of one connection, so which host-key
/// algorithms were accepted depended on connection history. The per-hop legacy option now
/// enables only the per-connection parts: SHA-1 group-14 key exchange and AES-128-CTR.
public enum SSHEngineAlgorithms {
    /// Idempotent; NIOSSH ignores repeat registrations of the same type.
    public static let registerHostKeyAlgorithmsOnce: Void = {
        NIOSSHAlgorithms.register(publicKey: Insecure.RSA.PublicKey.self, signature: Insecure.RSA.Signature.self)
    }()

    /// What `allowLegacyAlgorithms` turns on for one connection. No public-key registration.
    static let legacy: SSHAlgorithms = {
        var algorithms = SSHAlgorithms()
        algorithms.transportProtectionSchemes = .add([AES128CTR.self])
        algorithms.keyExchangeAlgorithms = .add([DiffieHellmanGroup14Sha1.self, DiffieHellmanGroup14Sha256.self])
        return algorithms
    }()

    /// True when the legacy set registers no host-key algorithms (the property S4 requires).
    public static var legacySetRegistersNoPublicKeyAlgorithms: Bool { legacy.publicKeyAlgorihtms == nil }
}

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
    /// The transport declared itself lost (keep-alives exhausted, no answer after a wake, or the
    /// connection found closed under a shell) and closed.
    case lost(String)
    case closed
}

/// How a command run with `SSHTransport.run` ended, and what it wrote to each stream.
public struct SSHCommandOutput: Sendable, Equatable {
    /// Nil when the server closed the channel without saying.
    public let exitStatus: Int?
    public let standardOutput: Data
    public let standardError: Data

    public init(exitStatus: Int?, standardOutput: Data, standardError: Data = Data()) {
        self.exitStatus = exitStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// One authenticated SSH connection to a route, shared by every session on that route.
/// Moved from glas.sh `SharedSSHTransport` + the connection half of `SSHConnection`
/// (Models.swift:1909-2320); the terminal-specific half became `SSHShellChannel`.
///
/// Ownership: callers `acquire(owner:)` and `release(owner:)`; the final release closes the
/// connection. `close()` closes regardless. A closing transport refuses new owners.
public actor SSHTransport: SSHPooledTransport {
    public nonisolated let route: SSHRoute
    public nonisolated let identity: SSHTransportIdentity
    /// This connection's events. **Each read is a subscription of its own**, so every terminal
    /// sharing the connection hears every event, its end above all (B-X5); one read after the end
    /// hears the end. See `SSHTransportEventBroadcast`.
    public nonisolated var events: AsyncStream<SSHTransportEvent> { eventBroadcast.subscribe() }

    private let credentials: any SSHCredentialResolver
    private let trustStore: any SSHHostTrustStore
    private let trustDecider: (any SSHHostTrustDecider)?
    private let eventBroadcast = SSHTransportEventBroadcast()
    /// How this connection ended, recorded as the teardown begins: shells whose channels the
    /// teardown closes ask it why (`shellEndReason`).
    private var ending: SSHTransportEvent?
    private let challengeBox = SSHHostKeyChallengeBox()

    private var client: SSHClient?
    private var jumpClients: [SSHClient] = []
    /// The in-flight connect, so concurrent callers join it instead of failing (S3).
    private var connectTask: Task<Void, Error>?
    /// Remote forwards opened on this transport, cancelled at teardown (S9).
    private var remoteForwards: [UUID: SSHRemoteForward] = [:]
    private(set) public var ownership = SSHTransportOwnership()
    private var keepAliveTask: Task<Void, Never>?
    private var missedKeepAlives = 0
    /// Keys trusted for this transport's lifetime only (`.trust(remember: false)`), by host:port.
    private var sessionTrustedKeys: [String: Set<String>] = [:]
    /// Exec channels open at once on this connection, and those waiting for one (W21).
    private let commandLimit: Int
    private var commandPermits: SSHPermitQueue
    /// Tests run `execute` without a server through this; nil in the app.
    private var commandRunnerForTesting: (@Sendable (String) async throws -> String)?

    public init(
        route: SSHRoute,
        credentials: any SSHCredentialResolver,
        trustStore: any SSHHostTrustStore,
        trustDecider: (any SSHHostTrustDecider)? = nil,
        commandLimit: Int = SSHConnectionLimits.standard.commandsPerConnection
    ) {
        self.route = route
        self.identity = route.identity
        self.credentials = credentials
        self.trustStore = trustStore
        self.trustDecider = trustDecider
        self.commandLimit = max(1, commandLimit)
        self.commandPermits = SSHPermitQueue(limit: commandLimit)
        _ = SSHEngineAlgorithms.registerHostKeyAlgorithmsOnce
    }

    /// Another, unconnected transport for the same route, credentials and trust: a further
    /// connection when this one is full or the server refused it a session (W21). The credential
    /// material is the material this one already holds; nothing is read again.
    public nonisolated func makeSibling(trustDecider decider: (any SSHHostTrustDecider)?) -> SSHTransport {
        SSHTransport(route: route, credentials: credentials, trustStore: trustStore,
                     trustDecider: decider ?? trustDecider, commandLimit: commandLimit)
    }

    /// `SSHPooledTransport`'s sibling: the same trust decider as this one.
    public nonisolated func makeSibling() -> Self {
        Self(route: route, credentials: credentials, trustStore: trustStore,
             trustDecider: trustDecider, commandLimit: commandLimit)
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

    /// Registers `owner` only while fewer than `limit` own this connection (W21). Atomic on this
    /// actor, so terminals opening together can never take it past the limit.
    public func acquire(owner: UUID, limit: Int) -> Bool { ownership.acquire(owner, limit: limit) }

    public var ownerCount: Int { ownership.owners.count }

    /// The server refused a session here: keep the owners, take no more (W21).
    public func refuseNewOwners() { ownership.refuseNewOwners() }

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
        if ending == nil { ending = reason }
        keepAliveTask?.cancel()
        keepAliveTask = nil
        await SSHLiveTransports.shared.remove(self)
        let forwards = Array(remoteForwards.values)
        remoteForwards.removeAll()
        for forward in forwards { await forward.close() }
        let closing = [client].compactMap { $0 } + jumpClients.reversed()
        client = nil
        jumpClients.removeAll()
        for c in closing {
            do { try await c.close() } catch {
                Logger.sshTransport.error("SSH client close failed; category=\(String(reflecting: type(of: error)), privacy: .public)")
            }
        }
        eventBroadcast.finish(with: reason)
    }

    // MARK: Connect

    /// Connects (idempotent). Host-trust challenges go to the decider; with none, the
    /// challenge is thrown as `SSHHostTrustRequiredError` for the caller to handle and retry.
    public func connect() async throws {
        if isConnected { return }
        guard !ownership.isClosing else { throw SSHTransportError.notConnected }
        if let inFlight = connectTask {
            try await inFlight.value
            return
        }
        let task = Task { [self] in try await connectLoop() }
        connectTask = task
        defer { connectTask = nil }
        try await task.value
    }

    private func connectLoop() async throws {
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
        // Every owner left while this was signing in, and the teardown has run: close what just
        // opened rather than leave a connection nobody holds (W21 shares connections in flight).
        if ownership.isClosing {
            let opened = [client].compactMap { $0 } + jumpClients.reversed()
            client = nil
            jumpClients.removeAll()
            for c in opened { try? await c.close() }
            throw SSHTransportError.notConnected
        }
        emit(.connected)
        startKeepAlive(options: target.options)
        await SSHLiveTransports.shared.add(self)
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
                    algorithms: SSHEngineAlgorithms.legacy
                )
            } catch {
                if let challenge = challengeBox.take() { throw SSHHostTrustRequiredError(challenge: challenge) }
                throw error
            }
        }
    }

    private nonisolated func emit(_ event: SSHTransportEvent) {
        eventBroadcast.yield(event)
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
                    // Waits for the answer (Citadel F11): a send that only queued the request
                    // never failed on a connection that had died silently, so nothing was ever
                    // counted as missed.
                    try await client.checkAlive(timeout: .seconds(Int64(max(5, interval))))
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

    /// Asks the server to answer now, and ends the connection as lost if it does not in `timeout`
    /// (2026-10-12, B-X25). Called when the Mac wakes and when the app comes back to the
    /// foreground: a connection that died while the device slept looked alive — a terminal took
    /// typing and showed nothing — until TCP gave up minutes later. Lost is what every surface
    /// already shows with Reconnect, and a terminal in tmux reattaches.
    public func checkAlive(timeout: Duration = .seconds(8)) async {
        guard let client, client.isConnected, !ownership.isClosing else { return }
        let milliseconds = Int64(timeout.components.seconds) * 1000
            + Int64(timeout.components.attoseconds / 1_000_000_000_000_000)
        do {
            try await client.checkAlive(timeout: .milliseconds(max(1, milliseconds)))
            resetKeepAliveCounter()
        } catch {
            await lostConnection(reason: "The connection stopped answering — the device slept, or the network changed")
        }
    }

    /// Data from the server proves liveness; shell channels call this on every chunk.
    func resetKeepAliveCounter() { missedKeepAlives = 0 }

    private func recordMissedKeepAlive(maximum: Int) -> Int {
        guard !ownership.isClosing else { return 0 }
        missedKeepAlives += 1
        emit(.keepAliveMissed(count: missedKeepAlives, maximum: maximum))
        return missedKeepAlives
    }

    private func lostConnection(reason: String) async {
        guard ownership.forceClose() else { return }
        await teardown(reason: .lost(reason))
    }

    /// Why a shell's channel closed, asked by the shell as it ends (B-X5): nil when the shell
    /// itself ended (`exit`, logout) on a connection that stands, or when this connection was
    /// closed on purpose; otherwise the loss, in words for the terminal to show. A connection found
    /// closed here — the server or the network ended it before a keep-alive noticed — is declared
    /// lost now, so every terminal on it hears so, not only the one that asked.
    func shellEndReason() async -> String? {
        switch ending {
        case .lost(let reason): return reason
        case .some: return nil
        case nil: break
        }
        guard let client, !client.isConnected else { return nil }
        let reason = "The connection to the server closed"
        await lostConnection(reason: reason)
        if case .lost(let recorded) = ending { return recorded }
        return reason
    }

    // MARK: Channels

    /// Opens an interactive shell on a PTY. The channel is ready to accept input on return.
    public func openShell(pty: SSHPTYRequest) async throws -> SSHShellChannel {
        guard let client, client.isConnected else { throw SSHTransportError.notConnected }
        let channel = SSHShellChannel(pty: pty, onActivity: { [weak self] in
            Task { await self?.resetKeepAliveCounter() }
        }, connectionEndReason: { [weak self] in
            await self?.shellEndReason()
        })
        try await channel.start(client: client, options: route.target.options)
        return channel
    }

    /// Runs one command and returns its output. The one-hour timeout matches glas.sh
    /// `executeRemoteCommand` (Models.swift:2470); the response bound is new.
    /// Bound on `execute` output unless the caller raises it explicitly (S1).
    public static let defaultMaximumResponseBytes = 8 * 1024 * 1024

    ///
    /// W21: at most `commandLimit` commands run at once on one connection, each an exec channel the
    /// server counts against `MaxSessions` with the shells; the rest wait their turn, for no longer
    /// than `timeout`.
    public func execute(_ command: String, maxResponseBytes: Int = SSHTransport.defaultMaximumResponseBytes, timeout: Duration = .seconds(3_600)) async throws -> String {
        try await takeCommandPermit(waitingAtMost: timeout)
        defer { returnCommandPermit() }
        if let commandRunnerForTesting { return try await commandRunnerForTesting(command) }
        guard let client, client.isConnected else { throw SSHTransportError.notConnected }
        do {
            let buffer = try await client.executeCommand(command, maxResponseSize: maxResponseBytes, executionTimeout: TimeAmount(timeout))
            return String(buffer: buffer)
        } catch where SSHTransportError.isSessionChannelRefused(error) {
            Logger.sshConnections.notice("SSH: the server refused a command channel; \(self.ownership.owners.count, privacy: .public) owners on this connection")
            throw SSHTransportError.sessionLimitReached
        }
    }

    /// Runs one command and answers with how it ended and both its streams, apart (Citadel F12).
    /// `execute` throws on the first byte of standard error; `git` writes warnings there while
    /// succeeding, and says why it failed there too. The same permits and limits as `execute`.
    public func run(_ command: String, maxResponseBytes: Int = SSHTransport.defaultMaximumResponseBytes, timeout: Duration = .seconds(3_600)) async throws -> SSHCommandOutput {
        try await takeCommandPermit(waitingAtMost: timeout)
        defer { returnCommandPermit() }
        if let commandRunnerForTesting {
            return SSHCommandOutput(exitStatus: 0, standardOutput: Data(try await commandRunnerForTesting(command).utf8))
        }
        guard let client, client.isConnected else { throw SSHTransportError.notConnected }
        do {
            let result = try await client.executeCommandCollecting(command, maxResponseSize: maxResponseBytes, executionTimeout: TimeAmount(timeout))
            return SSHCommandOutput(exitStatus: result.exitStatus,
                                    standardOutput: Data(result.standardOutput.readableBytesView),
                                    standardError: Data(result.standardError.readableBytesView))
        } catch where SSHTransportError.isSessionChannelRefused(error) {
            Logger.sshConnections.notice("SSH: the server refused a command channel; \(self.ownership.owners.count, privacy: .public) owners on this connection")
            throw SSHTransportError.sessionLimitReached
        }
    }

    /// Commands running now, and waiting (tests and diagnostics).
    public var commandsRunning: Int { commandPermits.inUse }
    public var commandsWaiting: Int { commandPermits.waitingCount }

    func setCommandRunnerForTesting(_ runner: (@Sendable (String) async throws -> String)?) {
        commandRunnerForTesting = runner
    }

    private func takeCommandPermit(waitingAtMost timeout: Duration) async throws {
        if commandPermits.tryTake() { return }
        let id = UUID()
        let expiry = Task { [weak self] in
            guard (try? await Task.sleep(for: timeout)) != nil else { return }
            await self?.withdrawCommandWaiter(id, throwing: CitadelError.commandExecutionTimedOut)
        }
        defer { expiry.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                commandPermits.enqueue(id, continuation)
            }
        } onCancel: {
            Task { [weak self] in await self?.withdrawCommandWaiter(id, throwing: CancellationError()) }
        }
    }

    private func withdrawCommandWaiter(_ id: UUID, throwing error: any Error) {
        commandPermits.withdraw(id)?.resume(throwing: error)
    }

    private func returnCommandPermit() {
        commandPermits.give()?.resume()
    }

    /// Opens an SFTP subsystem channel over the existing connection.
    public func openSFTP() async throws -> any SFTPSession {
        guard let client, client.isConnected else { throw SSHTransportError.notConnected }
        do {
            return try await CitadelSFTPSession.open(over: client)
        } catch where SSHTransportError.isSessionChannelRefused(error) {
            throw SSHTransportError.sessionLimitReached
        }
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

    /// The same channel, wrapped **inside the channel initializer** rather than after the open
    /// returns.
    ///
    /// This matters for any protocol whose server speaks first. MySQL sends its greeting the
    /// moment the forwarded connection is accepted, and the SSH server can deliver that data in
    /// the same read as the channel-open confirmation — before a wrap performed afterwards has
    /// installed anything to consume it. The greeting is then dropped at the end of an empty
    /// pipeline, the client waits for a handshake it will never see, and the server gives up at
    /// its own `connect_timeout` with "Got timeout reading communication packets". PostgreSQL,
    /// where the client speaks first, never reproduces it — which is exactly how this hid.
    ///
    /// Wrapping in the initializer means the `NIOAsyncChannel` exists before the channel is ever
    /// active, so no inbound byte can arrive unclaimed.
    func openDirectAsyncChannel(toHost host: String, port: Int) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        guard let client, client.isConnected else { throw SSHTransportError.notConnected }
        let wrapped = OSAllocatedUnfairLock<Result<NIOAsyncChannel<ByteBuffer, ByteBuffer>, any Error>?>(initialState: nil)
        _ = try await client.createDirectTCPIPChannel(
            using: .init(targetHost: host, targetPort: port, originatorAddress: try .init(ipAddress: "127.0.0.1", port: 0)),
            initialize: { channel in
                do {
                    let async = try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
                    wrapped.withLock { $0 = .success(async) }
                    return channel.eventLoop.makeSucceededVoidFuture()
                } catch {
                    wrapped.withLock { $0 = .failure(error) }
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
        )
        // The initializer runs as part of the open, so this is populated by the time it returns.
        switch wrapped.withLock({ $0 }) {
        case .success(let channel): return channel
        case .failure(let error): throw error
        case nil: throw SSHTransportError.notConnected
        }
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
        let forward = SSHRemoteForward(remoteHost: remoteHost, requestedRemotePort: remotePort, localHost: localHost, localPort: localPort) { onOpen in
            try await client.runRemotePortForward(host: remoteHost, port: remotePort, forwardingTo: localHost, port: localPort) { forward in
                onOpen(forward.boundPort)
            }
        }
        remoteForwards[forward.id] = forward
        forward.onClosed = { [weak self] id in Task { await self?.forgetRemoteForward(id) } }
        return forward
    }

    private func forgetRemoteForward(_ id: UUID) { remoteForwards.removeValue(forKey: id) }

    /// Remote forwards currently tracked (for tests and diagnostics).
    public var remoteForwardCount: Int { remoteForwards.count }

    private struct DirectChannelProvider: SSHDirectChannelProvider {
        let transport: SSHTransport
        func openDirectChannel(toHost host: String, port: Int) async throws -> any Channel {
            try await transport.openDirectChannel(toHost: host, port: port)
        }
        func openDirectAsyncChannel(toHost host: String, port: Int) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
            try await transport.openDirectAsyncChannel(toHost: host, port: port)
        }
    }
}

/// Every connected transport in the process, held weakly (2026-10-12, B-X25): what a wake asks to
/// answer. Terminals share connections through `SSHTransportPool`, but an editor project, a
/// forward and a database or desktop tunnel each hold their own, so the pool alone would miss them.
public actor SSHLiveTransports {
    public static let shared = SSHLiveTransports()

    private struct Entry { weak var transport: SSHTransport? }
    private var entries: [ObjectIdentifier: Entry] = [:]

    func add(_ transport: SSHTransport) { entries[ObjectIdentifier(transport)] = Entry(transport: transport) }
    func remove(_ transport: SSHTransport) { entries[ObjectIdentifier(transport)] = nil }

    func contains(_ transport: SSHTransport) -> Bool { entries[ObjectIdentifier(transport)]?.transport != nil }

    /// Asks every connected transport to answer at once; those that do not are shown lost.
    public func checkAllAlive(timeout: Duration = .seconds(8)) async {
        entries = entries.filter { $0.value.transport != nil }
        let transports = entries.values.compactMap(\.transport)
        await withTaskGroup(of: Void.self) { group in
            for transport in transports {
                group.addTask { await transport.checkAlive(timeout: timeout) }
            }
        }
    }
}
