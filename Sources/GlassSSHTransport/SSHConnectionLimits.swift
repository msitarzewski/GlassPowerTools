import Foundation

/// How much Glass asks of one SSH server at once (W21, 2026-10-10).
///
/// OpenSSH's defaults set the bounds. **`MaxSessions 10`**: one connection carries at most ten
/// session channels, and every shell, every exec and every SFTP subsystem is one; the eleventh is
/// refused ("administratively prohibited"). **`MaxStartups 10:30:100`**: once ten connections are
/// still signing in, sshd turns new ones away — three in ten at first, all of them by a hundred —
/// by writing "Exceeded MaxStartups" and closing.
///
/// The owner met both on Vision Pro, opening his usual sets of terminals to one Mac. Opened one
/// after another, every terminal joined the first connection: eight shells, plus the exec channels
/// that claim and read each one's tmux session, and the next one was refused. Opened together,
/// nothing was connected yet, so every terminal started a connection of its own at once, and sshd
/// dropped those past ten.
public struct SSHConnectionLimits: Sendable, Equatable {
    /// Owners — terminals, SFTP browsers, Active's probes — on one connection; each holds at most one
    /// long-lived session channel. Six leave four of MaxSessions' ten: two for
    /// `commandsPerConnection`, one for an SFTP channel a drop or the file browser opens on the
    /// terminal's connection, and one for a channel the server has not finished closing.
    public var sessionsPerConnection: Int
    /// Exec channels at once on one connection — tmux claims, name reads, Active's listings, Find,
    /// the file browser's commands — queued first come, first served beyond this.
    public var commandsPerConnection: Int
    /// Connections to one route signing in at once. Two keeps any one route far below MaxStartups'
    /// ten while the person's other devices, and other routes to the same server, sign in too, and
    /// still opens sixteen terminals' three connections in about two handshakes' time.
    public var handshakesPerRoute: Int
    /// Tries for a connection the server closes or resets before it is set up: the first, and
    /// `retryDelays.count` more at most.
    public var connectAttempts: Int
    /// The pause before each further try. A MaxStartups drop lasts only while other connections are
    /// still signing in, which takes about a second, so a second or two is enough.
    public var retryDelays: [Duration]
    /// Each pause varies by up to this fraction either way, so devices turned away together do not
    /// come back together.
    public var retryJitter: Double

    public init(
        sessionsPerConnection: Int,
        commandsPerConnection: Int,
        handshakesPerRoute: Int,
        connectAttempts: Int,
        retryDelays: [Duration],
        retryJitter: Double
    ) {
        self.sessionsPerConnection = max(1, sessionsPerConnection)
        self.commandsPerConnection = max(1, commandsPerConnection)
        self.handshakesPerRoute = max(1, handshakesPerRoute)
        self.connectAttempts = max(1, connectAttempts)
        self.retryDelays = retryDelays
        self.retryJitter = min(max(0, retryJitter), 1)
    }

    public static let standard = SSHConnectionLimits(
        sessionsPerConnection: 6,
        commandsPerConnection: 2,
        handshakesPerRoute: 2,
        connectAttempts: 3,
        retryDelays: [.seconds(1), .seconds(2)],
        retryJitter: 0.5
    )

    /// The pause after failed attempt `attempt` (1-based), jittered.
    func retryDelay(afterAttempt attempt: Int) -> Duration {
        guard !retryDelays.isEmpty else { return .zero }
        let base = retryDelays[min(max(attempt, 1), retryDelays.count) - 1]
        guard retryJitter > 0 else { return base }
        return base * Double.random(in: (1 - retryJitter)...(1 + retryJitter))
    }
}

/// Permits handed out first come, first served by the actor that keeps this value. A permit
/// returned while someone waits passes straight to the longest waiter, so a burst cannot overtake
/// the queue.
struct SSHPermitQueue {
    let limit: Int
    private(set) var inUse = 0
    private var waiting: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

    init(limit: Int) { self.limit = max(1, limit) }

    var waitingCount: Int { waiting.count }

    /// Takes a permit now, when one is free and nobody is ahead in the queue.
    mutating func tryTake() -> Bool {
        guard inUse < limit, waiting.isEmpty else { return false }
        inUse += 1
        return true
    }

    mutating func enqueue(_ id: UUID, _ continuation: CheckedContinuation<Void, any Error>) {
        waiting.append((id, continuation))
    }

    /// Returns a permit. When someone waits, it is theirs now: resume what this returns.
    mutating func give() -> CheckedContinuation<Void, any Error>? {
        guard !waiting.isEmpty else {
            inUse = max(0, inUse - 1)
            return nil
        }
        return waiting.removeFirst().continuation
    }

    /// Takes a waiter out of the queue — it gave up — or nil when it already holds a permit.
    mutating func withdraw(_ id: UUID) -> CheckedContinuation<Void, any Error>? {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return nil }
        return waiting.remove(at: index).continuation
    }
}
