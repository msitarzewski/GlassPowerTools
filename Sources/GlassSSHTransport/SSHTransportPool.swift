import Foundation
import GlasSecretStore

/// Shares one connected transport per identity across sessions, the way glas.sh's terminal
/// and SFTP sessions shared a `SharedSSHTransport` for the same server and jump chain.
public actor SSHTransportPool {
    private var transports: [SSHTransportIdentity: SSHTransport] = [:]
    private let makeTransport: @Sendable (SSHRoute) -> SSHTransport

    public init(makeTransport: @escaping @Sendable (SSHRoute) -> SSHTransport) {
        self.makeTransport = makeTransport
    }

    public init(secrets: SecretStoreConfiguration, trustDecider: (any SSHHostTrustDecider)? = nil) {
        self.init { route in SSHTransport(route: route, secrets: secrets, trustDecider: trustDecider) }
    }

    /// Returns a transport for the route with `owner` registered on it, reusing a connected
    /// one when it can still take owners. The caller connects it if needed.
    public func transport(for route: SSHRoute, owner: UUID) async -> SSHTransport {
        let identity = route.identity
        if let existing = transports[identity], await existing.isConnected, await existing.acquire(owner: owner) {
            return existing
        }
        let fresh = makeTransport(route)
        _ = await fresh.acquire(owner: owner)
        transports[identity] = fresh
        return fresh
    }

    /// Releases `owner`; the transport closes when it was the last one.
    public func release(_ transport: SSHTransport, owner: UUID) async {
        await transport.release(owner: owner)
        if await transport.isClosing, transports[transport.identity] === transport {
            transports.removeValue(forKey: transport.identity)
        }
    }

    public func connectedTransportCount() async -> Int {
        var count = 0
        for transport in transports.values where await transport.isConnected { count += 1 }
        return count
    }
}
