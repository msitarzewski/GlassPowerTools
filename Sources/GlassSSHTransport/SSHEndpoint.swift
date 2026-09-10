import Foundation

/// A machine to reach over SSH. Host names are normalised the way glas.sh normalised them
/// (`SSHConnection.normalizedHost`): trimmed, with any `ssh://` prefix removed.
public struct SSHEndpoint: Sendable, Hashable, Codable {
    public var host: String
    public var port: Int
    public var username: String

    public init(host: String, port: Int = 22, username: String) {
        self.host = SSHEndpoint.normalizedHost(host)
        self.port = port
        self.username = username
    }

    public static func normalizedHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ssh://", with: "", options: [.caseInsensitive])
    }

    public var hasValidHost: Bool { !host.isEmpty }
    public var hasValidPort: Bool { (1...65_535).contains(port) }
    public var displayAddress: String { "\(host):\(port)" }

    /// Throws the same validation errors glas.sh raised before opening a socket.
    public func validate() throws {
        guard hasValidHost else { throw SSHTransportError.invalidHost(host) }
        guard hasValidPort else { throw SSHTransportError.invalidPort(port) }
    }
}

/// Per-hop connection behaviour. Defaults match glas.sh's `ServerConfiguration` defaults.
public struct SSHConnectionOptions: Sendable, Hashable, Codable {
    /// Retry the key exchange once with Citadel's compatibility algorithm set when the modern
    /// set is rejected. Off by default; glas.sh exposes it per server as "legacy algorithms".
    public var allowLegacyAlgorithms: Bool
    /// Carried for transport identity; agent forwarding is not implemented by the Citadel path.
    public var forwardAgent: Bool
    /// Seconds between keep-alives; `0` disables them.
    public var keepAliveInterval: Int
    /// Consecutive failed keep-alives before the transport reports itself lost.
    public var keepAliveMaxMissed: Int
    /// Terminal type advertised for PTY requests and `TERM`.
    public var terminalType: String
    /// Environment requests sent with a PTY. `TERM` and `COLORTERM` are filled in if absent.
    public var environment: [String: String]

    public init(
        allowLegacyAlgorithms: Bool = false,
        forwardAgent: Bool = false,
        keepAliveInterval: Int = 0,
        keepAliveMaxMissed: Int = 3,
        terminalType: String = "xterm-256color",
        environment: [String: String] = [:]
    ) {
        self.allowLegacyAlgorithms = allowLegacyAlgorithms
        self.forwardAgent = forwardAgent
        self.keepAliveInterval = keepAliveInterval
        self.keepAliveMaxMissed = keepAliveMaxMissed
        self.terminalType = terminalType
        self.environment = environment
    }
}

/// One authenticated hop: where to connect and how to authenticate there.
public struct SSHHop: Sendable, Hashable, Codable {
    /// The catalog or capability record this hop came from, if any. Used only for identity
    /// and progress messages; never for authentication.
    public var recordID: UUID?
    public var displayName: String
    public var endpoint: SSHEndpoint
    public var credential: SSHCredentialReference
    public var options: SSHConnectionOptions

    public init(
        recordID: UUID? = nil,
        displayName: String? = nil,
        endpoint: SSHEndpoint,
        credential: SSHCredentialReference,
        options: SSHConnectionOptions = SSHConnectionOptions()
    ) {
        self.recordID = recordID
        self.displayName = displayName ?? endpoint.host
        self.endpoint = endpoint
        self.credential = credential
        self.options = options
    }
}

/// A target hop reached through zero or more jump hops (ProxyJump), in order.
public struct SSHRoute: Sendable, Hashable, Codable {
    public var target: SSHHop
    public var jumps: [SSHHop]
    public var trustPolicy: SSHHostTrustPolicy

    public init(target: SSHHop, jumps: [SSHHop] = [], trustPolicy: SSHHostTrustPolicy = .ask) {
        self.target = target
        self.jumps = jumps
        self.trustPolicy = trustPolicy
    }

    public var identity: SSHTransportIdentity { SSHTransportIdentity(route: self) }
}

/// What makes two transports interchangeable: the same route, credentials, options and trust
/// policy. Moved from glas.sh `SSHTransportIdentity` (Models.swift:1852); the endpoint fields it
/// compared are all present in `SSHHop`.
public struct SSHTransportIdentity: Sendable, Hashable {
    public let target: SSHHop
    public let hops: [SSHHop]
    public let trustPolicy: SSHHostTrustPolicy

    public init(route: SSHRoute) {
        target = route.target
        hops = route.jumps
        trustPolicy = route.trustPolicy
    }
}

/// Explicit owners make final-release behaviour deterministic across async channel shutdowns.
/// A closing transport cannot acquire a new owner. Moved verbatim from glas.sh
/// `SSHTransportOwnership` (Models.swift:1890).
public struct SSHTransportOwnership: Sendable, Equatable {
    public private(set) var owners: Set<UUID> = []
    public private(set) var isClosing = false

    public init() {}

    public mutating func acquire(_ owner: UUID) -> Bool {
        guard !isClosing else { return false }
        owners.insert(owner)
        return true
    }

    /// Returns true exactly once, when the final owner releases the transport.
    public mutating func release(_ owner: UUID) -> Bool {
        guard !isClosing, owners.remove(owner) != nil, owners.isEmpty else { return false }
        isClosing = true
        return true
    }

    /// Marks the transport closing regardless of owners (an explicit `close()`).
    public mutating func forceClose() -> Bool {
        guard !isClosing else { return false }
        owners.removeAll()
        isClosing = true
        return true
    }
}
