//
//  GlassServiceStoreTests.swift
//  Glass Power Tools — GlassShellTests
//
//  `GlassServiceStore`'s convenience overload recursed forever and nothing caught it, because it
//  had no callers until D26 stage 1 reached it. What it did when it finally ran:
//
//      func setConfiguration<T: Encodable>(_ value: T, for: EndpointID) async throws {
//          try await setConfiguration(JSONEncoder().encode(value), for: endpointID)
//      }
//
//  `Data` is `Encodable`. Passing `Data` matched the generic *exactly* while matching the `Data?`
//  requirement only through optional promotion, so Swift chose the generic — which encoded the
//  `Data` as a base64 JSON string, producing more `Data`, and called itself. It ran until the
//  process was killed at 90 GB, leaving no crash report and no test output, because that is what an
//  out-of-memory kill leaves.
//
//  These tests exist so that can never come back quietly. Each one completes in microseconds when
//  the API is right and does not complete at all when it is not.
//

import Foundation
import Testing
import GlassConnectionKit
@testable import GlassShell

@MainActor
@Suite("The narrow door capabilities reach a configuration through")
struct GlassServiceStoreTests {

    private struct Record: Codable, Equatable {
        var name: String
        var port: Int
    }

    @Test func encodingAValueTerminatesAndRoundTrips() async throws {
        let store = GlassInMemoryServiceStore()
        let endpoint = EndpointID()

        try await store.setConfiguration(encoding: Record(name: "alpha", port: 22), for: endpoint)

        #expect(store.configuration(Record.self, for: endpoint) == Record(name: "alpha", port: 22))
    }

    /// The exact shape that recursed: the value handed in *is* `Data`.
    @Test func storingRawDataTerminatesAndStoresThoseBytes() async throws {
        let store = GlassInMemoryServiceStore()
        let endpoint = EndpointID()
        let bytes = try JSONEncoder().encode(Record(name: "bravo", port: 2222))

        try await store.setConfiguration(bytes, for: endpoint)

        // Byte-for-byte what went in — not a base64 re-encoding of it, which is what the recursion
        // was producing on its way up to 90 GB.
        #expect(store.configuration(for: endpoint) == bytes)
    }

    @Test func encodingDataItselfStoresItOnceRatherThanWrappingIt() async throws {
        let store = GlassInMemoryServiceStore()
        let endpoint = EndpointID()
        let bytes = Data("plain".utf8)

        // Deliberately the ambiguous case, spelled the safe way. It must encode exactly once.
        try await store.setConfiguration(encoding: bytes, for: endpoint)

        let stored = try #require(store.configuration(for: endpoint))
        #expect(try JSONDecoder().decode(Data.self, from: stored) == bytes)
    }

    @Test func clearingAConfigurationRemovesIt() async throws {
        let store = GlassInMemoryServiceStore()
        let endpoint = EndpointID()
        try await store.setConfiguration(encoding: Record(name: "alpha", port: 22), for: endpoint)

        try await store.setConfiguration(nil, for: endpoint)

        #expect(store.configuration(for: endpoint) == nil)
    }
}
