//
//  GlassServiceAvailability.swift
//  Glass Power Tools — GlassShell
//
//  Whether each service answers (D41, 2026-09-30): a dot beside its icon in the library, when the
//  owner turns on Settings ▸ General ▸ Show Service Availability (off by default). A plain TCP
//  connection to the service's port — never a sign-in, nothing sent — only while the library is on
//  screen, at most once a minute, closed as soon as it answers.
//

import Foundation
import Network
import os
import Observation
import GlassConnectionKit

public enum GlassServiceAvailability: Sendable, Equatable {
    /// Accepted a connection within a second.
    case reachable
    /// Accepted one, slowly.
    case slow
    /// Refused, or no answer in time.
    case unreachable

    /// The worst of several services of one kind: one down is the news.
    static func worst(_ states: [GlassServiceAvailability]) -> GlassServiceAvailability? {
        if states.contains(.unreachable) { return .unreachable }
        if states.contains(.slow) { return .slow }
        return states.isEmpty ? nil : .reachable
    }
}

@MainActor @Observable
public final class GlassAvailabilityMonitor {
    public static let settingKey = "com.glasspowertools.library.showsAvailability"
    public static let interval: TimeInterval = 60

    public private(set) var states: [EndpointID: GlassServiceAvailability] = [:]
    private var lastRun: Date?

    public init() {}

    public struct Target: Sendable {
        public var endpointID: EndpointID
        public var host: String
        public var port: Int
    }

    /// Probes every target, unless the last pass was under a minute ago.
    public func refresh(_ targets: [Target], now: Date = Date()) async {
        if let lastRun, now.timeIntervalSince(lastRun) < Self.interval { return }
        lastRun = now
        let results = await withTaskGroup(of: (EndpointID, GlassServiceAvailability).self) { group in
            // Eight at a time: start eight, then one more as each finishes.
            var remaining = targets.makeIterator()
            func startNext() {
                guard let target = remaining.next() else { return }
                group.addTask { (target.endpointID, await Self.probe(host: target.host, port: target.port)) }
            }
            for _ in 0..<8 { startNext() }
            var collected: [(EndpointID, GlassServiceAvailability)] = []
            while let result = await group.next() {
                collected.append(result)
                startNext()
            }
            return collected
        }
        states = Dictionary(results, uniquingKeysWith: { _, last in last })
    }

    /// One TCP connection attempt: ready within `slowAfter` is reachable, later is slow, and a
    /// failure or no answer within `timeout` is unreachable. Nothing is sent.
    nonisolated static func probe(host: String, port: Int, slowAfter: Duration = .seconds(1),
                                  timeout: Duration = .seconds(3)) async -> GlassServiceAvailability {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port > 0 else { return .unreachable }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let started = ContinuousClock.now
        let outcome: GlassServiceAvailability = await withCheckedContinuation { continuation in
            let finished = OSAllocatedUnfairLock(initialState: false)
            @Sendable func finish(_ value: GlassServiceAvailability) {
                guard finished.withLock({ done in defer { done = true }; return !done }) else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(ContinuousClock.now - started <= slowAfter ? .reachable : .slow)
                case .failed, .waiting: finish(.unreachable)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(timeout.components.seconds)) { finish(.unreachable) }
        }
        return outcome
    }
}
