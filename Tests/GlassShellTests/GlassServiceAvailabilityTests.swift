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

    @Test("each service at most once a minute, or as seldom as its capability asks")
    @MainActor func ownInterval() async throws {
        let (open, port) = try await listener()
        let monitor = GlassAvailabilityMonitor()
        let ssh = EndpointID(), vnc = EndpointID()
        let start = Date()
        func targets() -> [GlassAvailabilityMonitor.Target] {
            [.init(endpointID: ssh, host: "127.0.0.1", port: port), .init(endpointID: vnc, host: "127.0.0.1", port: port, interval: 600)]
        }
        await monitor.refresh(targets(), now: start)
        #expect(monitor.states[ssh] == .reachable && monitor.states[vnc] == .reachable)
        open.cancel()
        try await Task.sleep(for: .milliseconds(200))
        await monitor.refresh(targets(), now: start.addingTimeInterval(30))
        #expect(monitor.states[ssh] == .reachable, "30 seconds later nothing is probed")
        await monitor.refresh(targets(), now: start.addingTimeInterval(61))
        #expect(monitor.states[ssh] == .unreachable, "a minute on, the port that closed is seen closed")
        #expect(monitor.states[vnc] == .reachable, "not yet its ten minutes")
        await monitor.refresh(targets(), now: start.addingTimeInterval(601))
        #expect(monitor.states[vnc] == .unreachable)
        await monitor.refresh([], now: start.addingTimeInterval(700))
        #expect(monitor.states.isEmpty, "a service no longer listed has no dot")
    }

    @Test("a service with a session open is not probed: it answers")
    @MainActor func connectedIsNotProbed() async throws {
        let monitor = GlassAvailabilityMonitor()
        let id = EndpointID()
        // Nothing listens on port 1; a probe would find it unreachable.
        let target = GlassAvailabilityMonitor.Target(endpointID: id, host: "127.0.0.1", port: 1)
        let start = Date()
        await monitor.refresh([target], connected: [id], now: start)
        #expect(monitor.states[id] == .reachable)
        await monitor.refresh([target], now: start.addingTimeInterval(1))
        #expect(monitor.states[id] == .unreachable, "closed, and never probed before: probed at once")
    }
}
