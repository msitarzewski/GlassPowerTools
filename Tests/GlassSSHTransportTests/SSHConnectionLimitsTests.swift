import Foundation
import Testing
import Citadel
import Crypto
import GlasSecretStore
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH
import os
@testable import GlassSSHTransport

/// W21 (2026-10-10): opening many terminals to one host stays within what an OpenSSH server allows —
/// `MaxSessions` session channels per connection and `MaxStartups` connections signing in at once.
/// The pool tests use transport doubles; the loopback tests sign in to an SSH server in this
/// process. No real host is involved.
@Suite("Connections within the server's limits (W21)")
struct SSHConnectionLimitsTests {
    /// The standard numbers with pauses short enough for a test.
    static let limits = SSHConnectionLimits(
        sessionsPerConnection: 6, commandsPerConnection: 2, handshakesPerRoute: 2,
        connectAttempts: 3, retryDelays: [.milliseconds(40), .milliseconds(80)], retryJitter: 0
    )

    static func route(port: Int = 22) -> SSHRoute {
        SSHRoute(target: SSHHop(displayName: "alpha", endpoint: SSHEndpoint(host: "alpha.example.com", port: port, username: "me"),
                                credential: .custom("test")))
    }

    // MARK: Many terminals at once, and one by one

    @Test func sixteenOpenedTogetherShareThreeConnectionsWithAtMostTwoSigningIn() async throws {
        let server = FakeServer(handshake: .milliseconds(80))
        let pool = SSHTransportPool<FakeTransport>(limits: Self.limits)
        let route = Self.route()
        let leased = try await withThrowingTaskGroup(of: FakeTransport.self, returning: [FakeTransport].self) { group in
            for _ in 0..<16 {
                group.addTask { try await pool.lease(route, owner: UUID(), candidate: FakeTransport(route: route, server: server)) }
            }
            var all: [FakeTransport] = []
            for try await transport in group { all.append(transport) }
            return all
        }
        let connections = Dictionary(grouping: leased, by: { ObjectIdentifier($0) }).values.map { $0[0] }
        #expect(connections.count == 3, "⌈16 / 6⌉ connections, not one per terminal")
        #expect(server.snapshot.connectAttempts == 3)
        #expect(server.snapshot.mostSigningIn == 2, "never more than two signing in at once")
        var owners: [Int] = []
        for connection in connections {
            owners.append(await connection.ownerCount)
            #expect(await connection.isConnected)
        }
        #expect(owners.allSatisfy { $0 <= 6 }, "no connection past six terminals: \(owners)")
        #expect(owners.reduce(0, +) == 16)
    }

    @Test func sixteenOpenedOneByOneFillEachConnectionBeforeTheNext() async throws {
        let server = FakeServer(handshake: .milliseconds(5))
        let pool = SSHTransportPool<FakeTransport>(limits: Self.limits)
        let route = Self.route()
        var leased: [FakeTransport] = []
        for _ in 0..<16 {
            leased.append(try await pool.lease(route, owner: UUID(), candidate: FakeTransport(route: route, server: server)))
        }
        var order: [ObjectIdentifier] = []
        for transport in leased where !order.contains(ObjectIdentifier(transport)) { order.append(ObjectIdentifier(transport)) }
        #expect(order.count == 3)
        var owners: [Int] = []
        for id in order { owners.append(await leased.first { ObjectIdentifier($0) == id }!.ownerCount) }
        #expect(owners == [6, 6, 4])
        #expect(server.snapshot.mostSigningIn == 1)
    }

    @Test func oneTerminalMakesOneConnection() async throws {
        let server = FakeServer(handshake: .milliseconds(5))
        let pool = SSHTransportPool<FakeTransport>(limits: .standard)
        let candidate = FakeTransport(route: Self.route(), server: server)
        let leased = try await pool.lease(Self.route(), owner: UUID(), candidate: candidate)
        #expect(leased === candidate, "a terminal alone uses the connection it made")
        #expect(server.snapshot.connectAttempts == 1)
        #expect(await leased.ownerCount == 1)
    }

    @Test func aTerminalThatClosesLetsAnotherTakeItsPlace() async throws {
        let server = FakeServer(handshake: .milliseconds(5))
        let pool = SSHTransportPool<FakeTransport>(limits: Self.limits)
        let route = Self.route()
        let owners = (0..<6).map { _ in UUID() }
        var first: FakeTransport?
        for owner in owners { first = try await pool.lease(route, owner: owner, candidate: FakeTransport(route: route, server: server)) }
        await pool.release(first!, owner: owners[0])
        let next = try await pool.lease(route, owner: UUID(), candidate: FakeTransport(route: route, server: server))
        #expect(next === first)
        #expect(server.snapshot.connectAttempts == 1)
    }

    // MARK: Turned away while signing in (MaxStartups)

    @Test func aConnectionTheServerDropsIsTriedAgainAfterAPause() async throws {
        let server = FakeServer(handshake: .milliseconds(5), drops: 2)
        let pool = SSHTransportPool<FakeTransport>(limits: Self.limits)
        let clock = ContinuousClock()
        let start = clock.now
        let leased = try await pool.lease(Self.route(), owner: UUID(), candidate: FakeTransport(route: Self.route(), server: server))
        #expect(await leased.isConnected)
        #expect(server.snapshot.connectAttempts == 3)
        #expect(clock.now - start >= .milliseconds(120), "40 ms, then 80 ms, between the tries")
    }

    @Test func aServerThatKeepsDroppingSaysItIsBusy() async throws {
        let server = FakeServer(handshake: .milliseconds(5), drops: 10)
        let pool = SSHTransportPool<FakeTransport>(limits: Self.limits)
        await #expect(throws: SSHTransportError.serverBusy) {
            _ = try await pool.lease(Self.route(), owner: UUID(), candidate: FakeTransport(route: Self.route(), server: server))
        }
        #expect(server.snapshot.connectAttempts == 3)
        #expect(await pool.transports(for: Self.route()).isEmpty)
    }

    @Test func aRejectedSignInIsTriedOnceForEveryTerminalWaitingOnIt() async throws {
        let server = FakeServer(handshake: .milliseconds(60), failure: SSHTransportError.authenticationFailed)
        let pool = SSHTransportPool<FakeTransport>(limits: Self.limits)
        let route = Self.route()
        let outcomes = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for _ in 0..<6 {
                group.addTask {
                    do { _ = try await pool.lease(route, owner: UUID(), candidate: FakeTransport(route: route, server: server)); return "connected" }
                    catch { return "\(error)" }
                }
            }
            var all: [String] = []
            for await outcome in group { all.append(outcome) }
            return all
        }
        #expect(outcomes == Array(repeating: "\(SSHTransportError.authenticationFailed)", count: 6))
        #expect(server.snapshot.connectAttempts == 1, "one sign-in tried, not six")
        #expect(await pool.transports(for: route).isEmpty)
    }

    // MARK: A session refused (MaxSessions below ours)

    @Test func aRefusedSessionIsOpenedOnAnotherConnection() async throws {
        let server = FakeServer(handshake: .milliseconds(5), sessionsPerConnection: 2)
        let pool = SSHTransportPool<FakeTransport>(limits: Self.limits)
        let route = Self.route()
        var used: [FakeTransport] = []
        for _ in 0..<4 {
            let opened = try await pool.openSession(route, owner: UUID(), candidate: FakeTransport(route: route, server: server)) {
                try await $0.openSession()
            }
            used.append(opened.transport)
        }
        #expect(used[0] === used[1])
        #expect(used[2] !== used[0], "the third session went to a new connection")
        #expect(used[3] === used[2])
        #expect(await used[0].ownerCount == 2)
        #expect(await used[2].ownerCount == 2)
        #expect(!(await used[0].acquire(owner: UUID(), limit: 6)), "the refusing connection takes no newcomers")
        #expect(server.snapshot.connectAttempts == 2)
    }

    /// A Reconnect, or a new terminal, must not keep joining a connection that died with its socket
    /// still looking open: the session open goes unanswered (Citadel's 15-second timer), and the
    /// terminal moves to a fresh connection.
    @Test func aConnectionThatNeverAnswersIsLeftForAFreshOne() async throws {
        let server = FakeServer(handshake: .milliseconds(5))
        let pool = SSHTransportPool<FakeTransport>(limits: Self.limits)
        let route = Self.route()
        let first = try await pool.openSession(route, owner: UUID(), candidate: FakeTransport(route: route, server: server)) {
            try await $0.openSession()
        }
        await first.transport.goSilent()
        let next = try await pool.openSession(route, owner: UUID(), candidate: FakeTransport(route: route, server: server)) {
            try await $0.openSession()
        }
        #expect(next.transport !== first.transport)
        #expect(server.snapshot.connectAttempts == 2)
        #expect(!(await first.transport.acquire(owner: UUID(), limit: 6)), "the silent connection takes no newcomers")
    }

    @Test func aSessionRefusedTwiceSaysWhy() async throws {
        let server = FakeServer(handshake: .milliseconds(5), sessionsPerConnection: 0)
        let pool = SSHTransportPool<FakeTransport>(limits: Self.limits)
        await #expect(throws: SSHTransportError.sessionLimitReached) {
            _ = try await pool.openSession(Self.route(), owner: UUID(), candidate: FakeTransport(route: Self.route(), server: server)) {
                try await $0.openSession()
            }
        }
        #expect(server.snapshot.connectAttempts == 2, "one more connection, not more")
    }

    // MARK: The transport's own limits

    @Test func ownersAreCappedAtomically() async {
        let transport = SSHTransport(route: Self.route(), credentials: NoCredentials(), trustStore: InMemoryHostTrustStore())
        let accepted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<16 { group.addTask { await transport.acquire(owner: UUID(), limit: 6) } }
            var count = 0
            for await ok in group where ok { count += 1 }
            return count
        }
        #expect(accepted == 6)
        #expect(await transport.ownerCount == 6)
    }

    @Test func commandsOnOneConnectionNeverExceedTheLimit() async throws {
        let transport = SSHTransport(route: Self.route(), credentials: NoCredentials(), trustStore: InMemoryHostTrustStore())
        let running = OSAllocatedUnfairLock(initialState: (now: 0, most: 0))
        await transport.setCommandRunnerForTesting { command in
            running.withLock { $0.now += 1; $0.most = max($0.most, $0.now) }
            try await Task.sleep(for: .milliseconds(30))
            running.withLock { $0.now -= 1 }
            return command
        }
        let answers = try await withThrowingTaskGroup(of: String.self, returning: [String].self) { group in
            for index in 0..<10 { group.addTask { try await transport.execute("read \(index)", timeout: .seconds(15)) } }
            var all: [String] = []
            for try await answer in group { all.append(answer) }
            return all
        }
        #expect(answers.count == 10, "every queued command still runs")
        #expect(running.withLock { $0.most } == SSHConnectionLimits.standard.commandsPerConnection)
        #expect(running.withLock { $0.most } == 2)
        #expect(await transport.commandsRunning == 0)
    }

    @Test func aQueuedCommandGivesUpAtItsTimeout() async throws {
        let transport = SSHTransport(route: Self.route(), credentials: NoCredentials(), trustStore: InMemoryHostTrustStore(), commandLimit: 1)
        await transport.setCommandRunnerForTesting { command in
            if command == "slow" { try await Task.sleep(for: .milliseconds(600)) }
            return command
        }
        let slow = Task { try await transport.execute("slow") }
        try await Task.sleep(for: .milliseconds(20))
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: (any Error).self) { _ = try await transport.execute("read", timeout: .milliseconds(60)) }
        #expect(clock.now - start < .milliseconds(400), "it stopped waiting at its own timeout")
        #expect(await transport.commandsWaiting == 0)
        #expect(try await slow.value == "slow")
    }

    // MARK: Against an SSH server in this process

    @Test(arguments: [LoopbackSSHServer.Drop.endOfFile, .reset])
    func loopbackMaxStartupsDropIsRecognisedAndRetried(_ drop: LoopbackSSHServer.Drop) async throws {
        let once = try await LoopbackSSHServer.start(dropFirst: 1, as: drop, sessionsPerConnection: 10)
        do {
            let plain = once.transport()
            let clock = ContinuousClock()
            let start = clock.now
            do {
                try await plain.connect()
                Issue.record("the first connection should have been turned away")
            } catch {
                #expect(SSHTransportError.isDroppedDuringSetup(error), "what a MaxStartups drop looks like here: \(String(reflecting: type(of: error))) \(error)")
            }
            #expect(clock.now - start < .seconds(5), "the drop is seen at once, not at a timeout")
            await plain.close()
        }
        await once.stop()

        let twice = try await LoopbackSSHServer.start(dropFirst: 2, as: drop, sessionsPerConnection: 10)
        let pool = SSHTransportPool<SSHTransport>(limits: Self.limits)
        let owner = UUID()
        let leased = try await pool.lease(twice.route, owner: owner, candidate: twice.transport())
        #expect(await leased.isConnected)
        #expect(twice.counts.withLock { $0 } == .init(accepted: 3, dropped: 2, signedIn: 1, sessionsRefused: 0))
        await pool.release(leased, owner: owner)
        await twice.stop()
    }

    /// Shared connections are left while they sign in — six terminals closed before it finished.
    /// The connection must not survive its owners.
    @Test func loopbackConnectionEveryoneLeftWhileSigningInIsClosed() async throws {
        let server = try await LoopbackSSHServer.start(dropFirst: 0, sessionsPerConnection: 10, signInDelay: .milliseconds(300))
        let transport = server.transport()
        let owner = UUID()
        #expect(await transport.acquire(owner: owner, limit: 6))
        let connecting = Task { try await transport.connect() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.counts.withLock { $0 }.accepted == 1)
        await transport.release(owner: owner)      // the last owner leaves mid sign-in
        await #expect(throws: SSHTransportError.notConnected) { try await connecting.value }
        #expect(!(await transport.isConnected))
        for _ in 0..<50 where server.openConnections > 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(server.openConnections == 0, "nothing is left connected for nobody")
        await server.stop()
    }

    @Test func loopbackRefusedSessionGoesToAFreshConnection() async throws {
        let server = try await LoopbackSSHServer.start(dropFirst: 0, sessionsPerConnection: 2)
        // What the engine says when the server refuses a shell or a command.
        let plain = server.transport()
        try await plain.connect()
        let first = try await plain.openShell(pty: SSHPTYRequest())
        let second = try await plain.openShell(pty: SSHPTYRequest())
        await #expect(throws: SSHTransportError.sessionLimitReached) { _ = try await plain.openShell(pty: SSHPTYRequest()) }
        await #expect(throws: SSHTransportError.sessionLimitReached) { _ = try await plain.execute("true", timeout: .seconds(5)) }
        await first.close(); await second.close()
        await plain.close()

        // Through the pool: the third shell opens on a second connection.
        server.counts.withLock { $0 = .init() }
        let pool = SSHTransportPool<SSHTransport>(limits: Self.limits)
        var shells: [SSHShellChannel] = []
        var transports: [SSHTransport] = []
        for _ in 0..<3 {
            let opened = try await pool.openSession(server.route, owner: UUID(), candidate: server.transport()) {
                try await $0.openShell(pty: SSHPTYRequest())
            }
            shells.append(opened.value)
            transports.append(opened.transport)
        }
        #expect(transports[0] === transports[1])
        #expect(transports[2] !== transports[0])
        #expect(server.counts.withLock { $0 }.signedIn == 2)
        #expect(server.counts.withLock { $0 }.sessionsRefused == 1)
        for shell in shells { #expect(await shell.isOpen); await shell.close() }
        var closed: [SSHTransport] = []
        for transport in transports where !closed.contains(where: { $0 === transport }) {
            closed.append(transport)
            await transport.close()
        }
        await server.stop()
    }
}

/// The same against the disposable test host (gated like the other real-host tests): sixteen
/// shells opened together, then eight commands at once beside six shells on each connection.
/// Without W21 a stock OpenSSH meets both limits: sixteen connections signing in at once is past
/// MaxStartups' ten (some dropped, at random), and six shells plus eight commands is past
/// MaxSessions' ten (the rest refused).
@Suite("Connections within the server's limits, real host (gated)", .serialized)
struct SSHConnectionLimitsLiveTests {
    @Test func sixteenShellsTogetherThenCommandsBesideThem() async throws {
        do { try IntegrationEnvironment.skipUnlessConfigured() } catch { print("NOT RUN:", error); return }
        let pool = SSHTransportPool<SSHTransport>(limits: .standard)
        let route = IntegrationTransport.make().route
        let opened = try await withThrowingTaskGroup(of: (SSHTransport, SSHShellChannel).self,
                                                     returning: [(SSHTransport, SSHShellChannel)].self) { group in
            for _ in 0..<16 {
                group.addTask {
                    let opened = try await pool.openSession(route, owner: UUID(), candidate: IntegrationTransport.make()) {
                        try await $0.openShell(pty: SSHPTYRequest())
                    }
                    return (opened.transport, opened.value)
                }
            }
            var all: [(SSHTransport, SSHShellChannel)] = []
            for try await pair in group { all.append(pair) }
            return all
        }
        var connections: [SSHTransport] = []
        for (transport, _) in opened where !connections.contains(where: { $0 === transport }) { connections.append(transport) }
        #expect(connections.count == 3)
        for (_, shell) in opened { #expect(await shell.isOpen) }

        for connection in connections {
            let answers = try await withThrowingTaskGroup(of: String.self, returning: [String].self) { group in
                for index in 0..<8 { group.addTask { try await connection.execute("echo w21-\(index)", timeout: .seconds(15)) } }
                var all: [String] = []
                for try await answer in group { all.append(answer.trimmingCharacters(in: .whitespacesAndNewlines)) }
                return all
            }
            #expect(Set(answers) == Set((0..<8).map { "w21-\($0)" }))
        }
        for (_, shell) in opened { await shell.close() }
        for connection in connections { await connection.close() }
    }
}

// MARK: - Doubles

private struct NoCredentials: SSHCredentialResolver {
    func resolve(_ reference: SSHCredentialReference, for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential {
        .password(SecureBytes(Data("x".utf8)))
    }
}

/// What a server did, shared by every connection a test makes to it.
final class FakeServer: Sendable {
    struct Snapshot { var connectAttempts = 0, signingIn = 0, mostSigningIn = 0, dropsLeft = 0 }
    let handshake: Duration
    let sessionsPerConnection: Int
    let failure: SSHTransportError?
    private let state: OSAllocatedUnfairLock<Snapshot>

    init(handshake: Duration, drops: Int = 0, sessionsPerConnection: Int = 10, failure: SSHTransportError? = nil) {
        self.handshake = handshake
        self.sessionsPerConnection = sessionsPerConnection
        self.failure = failure
        state = OSAllocatedUnfairLock(initialState: Snapshot(dropsLeft: drops))
    }

    var snapshot: Snapshot { state.withLock { $0 } }

    /// Starts a sign-in; true when this one is to be dropped as past MaxStartups.
    func beginSignIn() -> Bool {
        state.withLock { s in
            s.connectAttempts += 1
            s.signingIn += 1
            s.mostSigningIn = max(s.mostSigningIn, s.signingIn)
            guard s.dropsLeft > 0 else { return false }
            s.dropsLeft -= 1
            return true
        }
    }

    func endSignIn() { state.withLock { $0.signingIn -= 1 } }
}

actor FakeTransport: SSHPooledTransport {
    nonisolated let route: SSHRoute
    nonisolated let identity: SSHTransportIdentity
    nonisolated let server: FakeServer
    private var ownership = SSHTransportOwnership()
    private var connected = false
    private var sessions = 0

    init(route: SSHRoute, server: FakeServer) {
        self.route = route
        self.identity = route.identity
        self.server = server
    }

    nonisolated func makeSibling() -> Self { Self(route: route, server: server) }
    var isConnected: Bool { connected && !ownership.isClosing }
    var isClosing: Bool { ownership.isClosing }
    var ownerCount: Int { ownership.owners.count }
    func acquire(owner: UUID) -> Bool { ownership.acquire(owner) }
    func acquire(owner: UUID, limit: Int) -> Bool { ownership.acquire(owner, limit: limit) }
    func release(owner: UUID) async { if ownership.release(owner) { connected = false } }
    func refuseNewOwners() { ownership.refuseNewOwners() }

    func connect() async throws {
        if connected { return }
        let dropped = server.beginSignIn()
        try? await Task.sleep(for: server.handshake)
        server.endSignIn()
        if dropped { throw ChannelError.eof }
        if let failure = server.failure { throw failure }
        connected = true
    }

    /// A session channel, refused as a server with `sessionsPerConnection` would.
    func openSession() throws {
        if silent { throw CitadelError.channelCreationFailed }
        guard sessions < server.sessionsPerConnection else { throw SSHTransportError.sessionLimitReached }
        sessions += 1
    }

    /// The connection dies with its socket still looking open: session opens go unanswered.
    func goSilent() { silent = true }
    private var silent = false
}

// MARK: - An SSH server in this process

/// Just enough of an SSH server on the loopback to sign in to (any password), to turn the first
/// connections away as OpenSSH does past MaxStartups — "Exceeded MaxStartups", then close — and to
/// refuse session channels past a per-connection limit as it does past MaxSessions.
final class LoopbackSSHServer: Sendable {
    struct Counts: Equatable { var accepted = 0, dropped = 0, signedIn = 0, sessionsRefused = 0 }
    let counts = OSAllocatedUnfairLock(initialState: Counts())
    private let open = OSAllocatedUnfairLock(initialState: 0)
    /// TCP connections accepted and not yet closed.
    var openConnections: Int { open.withLock { $0 } }
    private let listener: OSAllocatedUnfairLock<(any Channel)?> = OSAllocatedUnfairLock(initialState: nil)
    private let portBox = OSAllocatedUnfairLock(initialState: 0)

    var port: Int { portBox.withLock { $0 } }
    var route: SSHRoute {
        SSHRoute(target: SSHHop(displayName: "loopback", endpoint: SSHEndpoint(host: "127.0.0.1", port: port, username: "me"),
                                credential: .custom("loopback")))
    }

    private let hostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())

    /// A transport that already trusts this server's key, so every connection counted is one the
    /// pool asked for (an unknown key costs one more, to be asked about).
    func transport() -> SSHTransport {
        var wire = ByteBufferAllocator().buffer(capacity: 128)
        _ = hostKey.publicKey.write(to: &wire)
        let pinned = [InMemoryHostTrustStore.key(host: "127.0.0.1", port: port): Set([Data(wire.readableBytesView).base64EncodedString()])]
        return SSHTransport(route: route, credentials: NoCredentials(), trustStore: InMemoryHostTrustStore(pinned: pinned))
    }

    static func start(dropFirst: Int, as dropKind: Drop = .endOfFile, sessionsPerConnection: Int,
                      signInDelay: Duration = .zero) async throws -> LoopbackSSHServer {
        let server = LoopbackSSHServer()
        let hostKey = server.hostKey
        let counts = server.counts
        let open = server.open
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                open.withLock { $0 += 1 }
                channel.closeFuture.whenComplete { _ in open.withLock { $0 -= 1 } }
                let drop = counts.withLock { c -> Bool in
                    c.accepted += 1
                    guard c.dropped < dropFirst else { return false }
                    c.dropped += 1
                    return true
                }
                if drop {
                    return channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandler(TurnAway(dropKind))
                    }
                }
                let gate = SessionGate(limit: sessionsPerConnection, counts: counts)
                return channel.eventLoop.makeCompletedFuture {
                    let handler = NIOSSHHandler(
                        role: .server(.init(hostKeys: [hostKey], userAuthDelegate: AnyPassword(counts: counts, delay: signInDelay))),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: { child, type in
                            guard case .session = type, gate.open() else {
                                return child.eventLoop.makeFailedFuture(SessionRefused())
                            }
                            child.closeFuture.whenComplete { _ in gate.close() }
                            return child.eventLoop.makeCompletedFuture {
                                try child.pipeline.syncOperations.addHandler(AcceptRequests())
                            }
                        }
                    )
                    try channel.pipeline.syncOperations.addHandler(handler)
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        server.listener.withLock { $0 = channel }
        server.portBox.withLock { $0 = channel.localAddress?.port ?? 0 }
        return server
    }

    func stop() async {
        let channel = listener.withLock { current -> (any Channel)? in defer { current = nil }; return current }
        try? await channel?.close()
    }

    private struct SessionRefused: Error {}

    /// What sshd does past MaxStartups (`sshd.c`): one line, then close. Closed with the client's
    /// banner unread, the close arrives as a reset; closed after reading it, as a plain end of
    /// file — which one depends on timing, so both are tried.
    enum Drop: Sendable { case reset, endOfFile }

    private final class TurnAway: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = ByteBuffer
        let drop: Drop
        init(_ drop: Drop) { self.drop = drop }

        func channelActive(context: ChannelHandlerContext) {
            let line = context.channel.allocator.buffer(string: "Exceeded MaxStartups\r\n")
            let written = context.writeAndFlush(NIOAny(line))
            if drop == .reset { written.whenComplete { _ in context.close(promise: nil) } }
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            if drop == .endOfFile { context.close(promise: nil) }
        }
    }

    /// Session channels open on one connection; used on that connection's event loop only.
    private final class SessionGate: @unchecked Sendable {
        let limit: Int
        let counts: OSAllocatedUnfairLock<Counts>
        var openCount = 0
        init(limit: Int, counts: OSAllocatedUnfairLock<Counts>) { self.limit = limit; self.counts = counts }
        func open() -> Bool {
            guard openCount < limit else { counts.withLock { $0.sessionsRefused += 1 }; return false }
            openCount += 1
            return true
        }
        func close() { openCount -= 1 }
    }

    private final class AnyPassword: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
        let counts: OSAllocatedUnfairLock<Counts>
        let delay: Duration
        init(counts: OSAllocatedUnfairLock<Counts>, delay: Duration) { self.counts = counts; self.delay = delay }
        var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .password }
        func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
            let counts = counts
            let (seconds, attoseconds) = delay.components
            let nanoseconds = seconds * 1_000_000_000 + attoseconds / 1_000_000_000
            responsePromise.futureResult.eventLoop.scheduleTask(in: .nanoseconds(nanoseconds)) {
                counts.withLock { $0.signedIn += 1 }
                responsePromise.succeed(.success)
            }
        }
    }

    /// Says yes to a PTY, a shell and environment; the shell then sits there.
    private final class AcceptRequests: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = SSHChannelData
        func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
            let wantsReply: Bool
            switch event {
            case let request as SSHChannelRequestEvent.PseudoTerminalRequest: wantsReply = request.wantReply
            case let request as SSHChannelRequestEvent.ShellRequest: wantsReply = request.wantReply
            case let request as SSHChannelRequestEvent.EnvironmentRequest: wantsReply = request.wantReply
            default:
                context.fireUserInboundEventTriggered(event)
                return
            }
            if wantsReply { context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil) }
        }
    }
}
