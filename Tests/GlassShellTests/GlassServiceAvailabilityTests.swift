import Foundation
import Network
import os
import Testing
import GlassConnectionKit
@testable import GlassShell

/// D41: the availability dots' probe and its rules (2026-09-30).
@Suite("Service availability")
struct GlassServiceAvailabilityTests {
    /// A listener on a free local port, accepting and dropping connections.
    private func listener() async throws -> (NWListener, Int) {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { $0.cancel() }
        let port: Int = try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.withLock({ done in defer { done = true }; return !done }) {
                        continuation.resume(returning: Int(listener.port?.rawValue ?? 0))
                    }
                case .failed(let error):
                    if resumed.withLock({ done in defer { done = true }; return !done }) { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.start(queue: .global())
        }
        return (listener, port)
    }

    @Test("a port that accepts is reachable; a closed one is not")
    func probe() async throws {
        let (open, port) = try await listener()
        #expect(await GlassAvailabilityMonitor.probe(host: "127.0.0.1", port: port) == .reachable)
        open.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await GlassAvailabilityMonitor.probe(host: "127.0.0.1", port: port) == .unreachable)
        #expect(await GlassAvailabilityMonitor.probe(host: "127.0.0.1", port: 0) == .unreachable)
    }

    @Test("one service down is the news for its kind")
    func worst() {
        #expect(GlassServiceAvailability.worst([]) == nil)
        #expect(GlassServiceAvailability.worst([.reachable, .reachable]) == .reachable)
        #expect(GlassServiceAvailability.worst([.reachable, .slow]) == .slow)
        #expect(GlassServiceAvailability.worst([.slow, .unreachable, .reachable]) == .unreachable)
    }

    @Test("at most one pass a minute")
    @MainActor func oncePerMinute() async throws {
        let (open, port) = try await listener()
        defer { open.cancel() }
        let monitor = GlassAvailabilityMonitor()
        let id = EndpointID()
        let start = Date()
        await monitor.refresh([.init(endpointID: id, host: "127.0.0.1", port: port)], now: start)
        #expect(monitor.states[id] == .reachable)
        let other = EndpointID()
        await monitor.refresh([.init(endpointID: other, host: "127.0.0.1", port: port)], now: start.addingTimeInterval(30))
        #expect(monitor.states[other] == nil, "30 seconds later nothing is probed")
        await monitor.refresh([.init(endpointID: other, host: "127.0.0.1", port: port)], now: start.addingTimeInterval(61))
        #expect(monitor.states[other] == .reachable)
    }
}
