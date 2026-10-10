import Foundation
import GlasSecretStore
import os

/// What `SSHTransportPool` needs of a connection. `SSHTransport` is the real one; tests use doubles.
public protocol SSHPooledTransport: Actor {
    nonisolated var identity: SSHTransportIdentity { get }
    /// Another, unconnected transport for the same route, credentials and trust.
    nonisolated func makeSibling() -> Self
    var isConnected: Bool { get }
    var isClosing: Bool { get }
    var ownerCount: Int { get }
    func acquire(owner: UUID) -> Bool
    func acquire(owner: UUID, limit: Int) -> Bool
    func release(owner: UUID) async
    func refuseNewOwners()
    func connect() async throws
}

/// Shares connections per route across sessions, the way glas.sh's terminal and SFTP sessions
/// shared a `SharedSSHTransport` for the same server and jump chain — within what the server
/// allows (W21, 2026-10-10; numbers and reasons in `SSHConnectionLimits`).
///
/// `lease` is how terminals get a connection. A terminal joins a connection to its route that has
/// room, **connected or still signing in**, so terminals opening together wait for one handshake
/// instead of starting one each. A connection takes `sessionsPerConnection` owners; the next opens
/// another, and no more than `handshakesPerRoute` connections to one route sign in at once — the
/// rest wait for one to finish. A connection the server closes before it is set up (MaxStartups)
/// is tried again after a pause, a couple of times. `openSession` adds the other limit: when the
/// server refuses a session channel (MaxSessions lower than ours), that connection takes no new
/// owners and the session is tried once more on another.
///
/// `transport(for:owner:)` is the original sharing — one transport per route, any number of owners,
/// connected by the caller — kept for the callers and tests that use it.
public actor SSHTransportPool<Transport: SSHPooledTransport> {
    public nonisolated let limits: SSHConnectionLimits
    private let makeTransport: (@Sendable (SSHRoute) -> Transport)?
    private var routes: [SSHTransportIdentity: Route] = [:]
    private var routeCount = 0

    private struct Connection {
        let transport: Transport
        let number: Int
        /// The sign-in, retries included, that every owner waits for; nil for a connection made by
        /// `transport(for:owner:)`, which its caller connects.
        let ready: Task<Void, any Error>?
        /// The sign-in finished and succeeded.
        var signedIn = false
    }

    private struct Route {
        let number: Int
        var connections: [Connection] = []
        var connectionsMade = 0
        var handshakes = 0
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    public init(limits: SSHConnectionLimits = .standard, makeTransport: @escaping @Sendable (SSHRoute) -> Transport) {
        self.limits = limits
        self.makeTransport = makeTransport
    }

    /// A pool whose transports come from each `lease` call's candidate.
    public init(limits: SSHConnectionLimits = .standard) {
        self.limits = limits
        self.makeTransport = nil
    }

    // MARK: One transport per route (the original sharing)

    /// Returns a transport for the route with `owner` registered on it, reusing one when it can
    /// still take owners. The caller connects it if needed.
    public func transport(for route: SSHRoute, owner: UUID) async -> Transport {
        guard let makeTransport else {
            preconditionFailure("SSHTransportPool.transport(for:owner:) needs a pool made with makeTransport")
        }
        let identity = route.identity
        // A transport that is still connecting is reusable; only a closing one is not (S2).
        for connection in routes[identity]?.connections ?? [] where connection.ready == nil {
            if await connection.transport.acquire(owner: owner) { return connection.transport }
            remove(connection.transport, identity: identity)
        }
        // Record before any suspension so a concurrent caller finds this one, not a second.
        let fresh = makeTransport(route)
        _ = register(fresh, identity: identity, ready: nil)
        _ = await fresh.acquire(owner: owner)
        return fresh
    }

    /// Releases `owner`; the transport closes when it was the last one.
    public func release(_ transport: Transport, owner: UUID) async {
        await transport.release(owner: owner)
        if await transport.isClosing { remove(transport, identity: transport.identity) }
    }

    public func connectedTransportCount() async -> Int {
        var count = 0
        for route in routes.values {
            for connection in route.connections where await connection.transport.isConnected { count += 1 }
        }
        return count
    }

    /// Connections the pool holds for `route`, open or signing in (tests and diagnostics).
    public func transports(for route: SSHRoute) -> [Transport] {
        routes[route.identity]?.connections.map(\.transport) ?? []
    }

    // MARK: Within the server's limits (W21)

    /// A connected transport for `route` with `owner` registered on it. Joins a connection with
    /// room — connected, or signing in, in which case it waits for that sign-in — or opens another
    /// from `candidate` (then from its siblings), at most `handshakesPerRoute` signing in at once.
    /// A failed sign-in fails every owner waiting for it, so a wrong password is tried once, not
    /// once per terminal.
    public func lease(_ route: SSHRoute, owner: UUID, candidate: Transport? = nil) async throws -> Transport {
        let identity = route.identity
        var unused = candidate
        var waitLogged = false
        while true {
            try Task.checkCancellation()
            let number = routeNumber(identity)

            // A connection with room.
            let scanned = routes[identity]?.connections ?? []
            for connection in scanned {
                guard let ready = connection.ready else { continue }
                if connection.signedIn, !(await connection.transport.isConnected) { continue }
                guard await connection.transport.acquire(owner: owner, limit: limits.sessionsPerConnection) else { continue }
                let owners = await connection.transport.ownerCount
                Logger.sshConnections.info("SSH route r\(number, privacy: .public): joined connection c\(connection.number, privacy: .public) (\(owners, privacy: .public)/\(self.limits.sessionsPerConnection, privacy: .public) owners, \(connection.signedIn ? "connected" : "signing in", privacy: .public))")
                return try await signedIn(connection.transport, ready: ready, owner: owner)
            }

            // Another connection, when fewer than the limit are signing in — and only when every
            // connection there is now was tried: one opened while the joins above waited may have
            // room. (The route is looked up again: it may have been let go meanwhile.)
            _ = routeNumber(identity)
            let current = routes[identity]?.connections.map { ObjectIdentifier($0.transport) } ?? []
            guard current == scanned.map({ ObjectIdentifier($0.transport) }) else { continue }
            if let state = routes[identity], state.handshakes < limits.handshakesPerRoute {
                let fresh: Transport
                if let candidate = unused {
                    fresh = candidate
                    unused = nil
                } else if let candidate {
                    fresh = candidate.makeSibling()
                } else if let makeTransport {
                    fresh = makeTransport(route)
                } else {
                    preconditionFailure("SSHTransportPool.lease needs a candidate or a pool made with makeTransport")
                }
                let (made, ready) = startSigningIn(fresh, identity: identity)
                Logger.sshConnections.notice("SSH route r\(number, privacy: .public): opening connection c\(made, privacy: .public) (\(state.connections.count + 1, privacy: .public) to this route, \(state.handshakes + 1, privacy: .public)/\(self.limits.handshakesPerRoute, privacy: .public) signing in)")
                if await fresh.acquire(owner: owner, limit: limits.sessionsPerConnection) {
                    return try await signedIn(fresh, ready: ready, owner: owner)
                }
                continue
            }

            // Wait for a sign-in to finish, then look again.
            if !waitLogged {
                waitLogged = true
                Logger.sshConnections.notice("SSH route r\(number, privacy: .public): every connection is full and \(self.limits.handshakesPerRoute, privacy: .public) are signing in; waiting")
            }
            await waitForHandshake(identity)
        }
    }

    /// `lease`, then `open` — a shell, an SFTP channel — on the connection. When the server refuses
    /// the session channel (its MaxSessions is below `sessionsPerConnection`), or never answers it
    /// (the connection is dead though it looks open), that connection keeps its owners but takes no
    /// new ones, and the session is tried once more on another connection: one with room, or a new
    /// one. The owner is released on any failure.
    public func openSession<Value: Sendable>(
        _ route: SSHRoute,
        owner: UUID,
        candidate: Transport? = nil,
        open: @escaping @Sendable (Transport) async throws -> Value
    ) async throws -> (transport: Transport, value: Value) {
        var next = candidate
        var refusedOnce = false
        while true {
            let transport = try await lease(route, owner: owner, candidate: next)
            do {
                return (transport, try await open(transport))
            } catch where !refusedOnce && (SSHTransportError.isSessionChannelRefused(error)
                                           || SSHTransportError.isSessionOpenUnanswered(error)) {
                refusedOnce = true
                await transport.refuseNewOwners()
                let owners = await transport.ownerCount
                let why = SSHTransportError.isSessionChannelRefused(error)
                    ? "refused a session (MaxSessions)" : "did not answer a session open in time"
                Logger.sshConnections.notice("SSH route r\(self.routeNumber(route.identity), privacy: .public): the server \(why, privacy: .public) on a connection with \(owners, privacy: .public) owners; it takes no more, trying another")
                await release(transport, owner: owner)
                next = candidate?.makeSibling()
            } catch {
                await release(transport, owner: owner)
                throw error
            }
        }
    }

    // MARK: Bookkeeping

    private func routeNumber(_ identity: SSHTransportIdentity) -> Int {
        if let existing = routes[identity] { return existing.number }
        routeCount += 1
        routes[identity] = Route(number: routeCount)
        let hops = identity.hops.count
        // Debug only, and private: the engine names no host at info level or above.
        Logger.sshConnections.debug("SSH route r\(self.routeCount, privacy: .public) is \(identity.target.displayName) (\(hops, privacy: .public) jump hosts)")
        return routeCount
    }

    @discardableResult
    private func register(_ transport: Transport, identity: SSHTransportIdentity, ready: Task<Void, any Error>?) -> Int {
        _ = routeNumber(identity)
        routes[identity]!.connectionsMade += 1
        let number = routes[identity]!.connectionsMade
        routes[identity]!.connections.append(Connection(transport: transport, number: number, ready: ready))
        return number
    }

    /// Records the connection and starts its sign-in before anything suspends, so a terminal that
    /// asks next joins it rather than opening another.
    private func startSigningIn(_ transport: Transport, identity: SSHTransportIdentity) -> (number: Int, ready: Task<Void, any Error>) {
        let route = routeNumber(identity)
        let number = (routes[identity]?.connectionsMade ?? 0) + 1
        let limits = self.limits
        // Isolated to the pool, as the method that makes it; the sign-in itself runs off it.
        let ready = Task<Void, any Error> {
            do {
                try await Self.signIn(transport, limits: limits, route: route, connection: number)
                handshakeEnded(identity, transport, succeeded: true)
            } catch {
                handshakeEnded(identity, transport, succeeded: false)
                throw error
            }
        }
        routes[identity]!.handshakes += 1
        register(transport, identity: identity, ready: ready)
        return (number, ready)
    }

    /// Connects, trying again after a pause when the server closes the connection before it is set
    /// up. Anything else — a wrong password, an unknown host key, a refused port — fails at once.
    private static func signIn(_ transport: Transport, limits: SSHConnectionLimits, route: Int, connection: Int) async throws {
        var attempt = 1
        while true {
            do {
                try await transport.connect()
                return
            } catch {
                guard SSHTransportError.isDroppedDuringSetup(error) else { throw error }
                let category = String(reflecting: type(of: error))
                guard attempt < limits.connectAttempts else {
                    Logger.sshConnections.error("SSH route r\(route, privacy: .public): connection c\(connection, privacy: .public) closed by the server before it was set up, \(attempt, privacy: .public) times (MaxStartups?); giving up. Last: \(category, privacy: .public) \(String(describing: error), privacy: .public)")
                    throw SSHTransportError.serverBusy
                }
                let delay = limits.retryDelay(afterAttempt: attempt)
                Logger.sshConnections.notice("SSH route r\(route, privacy: .public): connection c\(connection, privacy: .public) closed by the server before it was set up (MaxStartups?); trying again in \(delay.description, privacy: .public). \(category, privacy: .public)")
                try await Task.sleep(for: delay)
                attempt += 1
            }
        }
    }

    /// Waits for `ready`; when it failed, gives the owner back and passes the failure on.
    private func signedIn(_ transport: Transport, ready: Task<Void, any Error>, owner: UUID) async throws -> Transport {
        do {
            try await ready.value
            return transport
        } catch {
            await release(transport, owner: owner)
            throw error
        }
    }

    private func handshakeEnded(_ identity: SSHTransportIdentity, _ transport: Transport, succeeded: Bool) {
        guard var route = routes[identity] else { return }
        route.handshakes = max(0, route.handshakes - 1)
        if let index = route.connections.firstIndex(where: { $0.transport === transport }) {
            if succeeded {
                route.connections[index].signedIn = true
            } else {
                // Nobody joins a failed sign-in; its owners have the error and let go.
                route.connections.remove(at: index)
            }
        }
        let waiters = route.waiters
        route.waiters.removeAll()
        routes[identity] = route
        for waiter in waiters.values { waiter.resume() }
        pruneIfUnused(identity)
    }

    private func waitForHandshake(_ identity: SSHTransportIdentity) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Nothing to wait for when a sign-in finished in the meantime: look again now.
                guard let route = routes[identity], route.handshakes >= limits.handshakesPerRoute else {
                    continuation.resume()
                    return
                }
                routes[identity]!.waiters[id] = continuation
            }
        } onCancel: {
            Task { await self.stopWaiting(id, identity: identity) }
        }
    }

    private func stopWaiting(_ id: UUID, identity: SSHTransportIdentity) {
        routes[identity]?.waiters.removeValue(forKey: id)?.resume()
    }

    private func remove(_ transport: Transport, identity: SSHTransportIdentity) {
        routes[identity]?.connections.removeAll { $0.transport === transport }
        pruneIfUnused(identity)
    }

    private func pruneIfUnused(_ identity: SSHTransportIdentity) {
        guard let route = routes[identity], route.connections.isEmpty, route.handshakes == 0, route.waiters.isEmpty else { return }
        routes.removeValue(forKey: identity)
    }
}

public extension SSHTransportPool where Transport == SSHTransport {
    init(secrets: SecretStoreConfiguration, trustDecider: (any SSHHostTrustDecider)? = nil) {
        self.init { route in SSHTransport(route: route, secrets: secrets, trustDecider: trustDecider) }
    }
}
