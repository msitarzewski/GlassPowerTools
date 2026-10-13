import Foundation
import os

/// A transport's events, for every subscriber its own copy (B-X5, 2026-10-13).
///
/// One connection carries several terminals (W21), and each listens for the connection's end.
/// The events were one `AsyncStream`, which hands each element to *one* of the tasks iterating it:
/// when a shared connection was lost, one terminal heard `.lost` and said so; the others saw only
/// their shell end, took it for an `exit`, and closed. Each subscription is now a stream of its
/// own. One made after the end hears the end and finishes, as a late reader of the single stream
/// did (the `.closed` that `close()` leaves).
final class SSHTransportEventBroadcast: Sendable {
    private struct State: Sendable {
        var subscribers: [UUID: AsyncStream<SSHTransportEvent>.Continuation] = [:]
        /// The event the transport ended with; set once.
        var end: SSHTransportEvent?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func subscribe() -> AsyncStream<SSHTransportEvent> {
        let (stream, continuation) = AsyncStream<SSHTransportEvent>.makeStream()
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        let end: SSHTransportEvent? = state.withLock { state in
            if let end = state.end { return end }
            state.subscribers[id] = continuation
            return nil
        }
        if let end {
            continuation.yield(end)
            continuation.finish()
        }
        return stream
    }

    func yield(_ event: SSHTransportEvent) {
        let subscribers = state.withLock { $0.end == nil ? Array($0.subscribers.values) : [] }
        for subscriber in subscribers { subscriber.yield(event) }
    }

    /// Ends every subscription with `event`. Only the first end counts.
    func finish(with event: SSHTransportEvent) {
        let subscribers: [AsyncStream<SSHTransportEvent>.Continuation] = state.withLock { state in
            guard state.end == nil else { return [] }
            state.end = event
            defer { state.subscribers.removeAll() }
            return Array(state.subscribers.values)
        }
        for subscriber in subscribers {
            subscriber.yield(event)
            subscriber.finish()
        }
    }
}
