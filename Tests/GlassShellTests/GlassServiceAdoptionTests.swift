//
//  GlassServiceAdoptionTests.swift
//  Glass Power Tools — GlassShellTests
//
//  D27: some ways of making a connection never touch the host sheet — the terminal's Add Server
//  form and its `ssh_config` import both build a saved server directly. Those servers had no host
//  record and no service link, which made them invisible in the library, because the library
//  renders the catalog and nothing in the shell reads a capability's own store.
//
//  `adoptService` is what those paths call instead of inventing a `UUID()`.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

@MainActor
@Suite("Adopting a machine a capability created (D27)")
struct GlassServiceAdoptionTests {

    private func makeModel() throws -> (GlassShellModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassAdoption-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        return (model, root)
    }

    @Test func adoptingCreatesAMachineThatTheLibraryCanSee() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let endpoint = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                    address: "alpha.example", serviceName: "Terminal")

        let host = try #require(model.catalogHosts.first { $0.displayName == "alpha" })
        #expect(host.address == "alpha.example")
        #expect(host.services.map(\.endpointID) == [endpoint])
        #expect(host.services.first?.kind == .ssh)
    }

    @Test func aSecondServiceAtTheSameAddressJoinsTheMachineAlreadyThere() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let first = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                 address: "alpha.example", serviceName: "Terminal")
        // Same machine, named differently and cased differently — importing an `ssh_config` that
        // already has an alias for a known address must not stand a second barn beside it.
        let second = try await model.adoptService(kind: .ssh, hostName: "alpha-alias",
                                                  address: "ALPHA.Example", serviceName: "Terminal")

        // `catalogHosts` groups records that share an address into one row, so counting rows
        // would pass even if a second record had been created. Count the records themselves.
        #expect(model.records.filter { $0.deletedAt == nil }.count == 1,
                "a second host record was created for an address already in the library")
        let host = try #require(model.catalogHosts.first)
        #expect(host.displayName == "alpha", "the existing machine keeps its name")
        #expect(Set(host.services.map(\.endpointID)) == [first, second])
    }

    @Test func aDifferentAddressIsADifferentMachine() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        _ = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                         address: "alpha.example", serviceName: "Terminal")
        _ = try await model.adoptService(kind: .ssh, hostName: "bravo",
                                         address: "bravo.example", serviceName: "Terminal")

        #expect(model.catalogHosts.count == 2)
    }

    @Test func discardingAnAdoptionLeavesNoHalfMadeMachine() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let endpoint = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                    address: "alpha.example", serviceName: "Terminal")
        #expect(model.catalogHosts.count == 1)

        // The capability failed to save its own record, so the machine must not survive: this is
        // the same orphan D25 exists to prevent, arriving from the other direction.
        await model.discardAdoption(endpoint)

        #expect(model.catalogHosts.flatMap(\.services).isEmpty,
                "the service outlived the record it was made for")
    }

    @Test func adoptingRefusesAnEmptyAddress() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        // A machine with no address is not a machine anyone can connect to, and the library would
        // show a row that does nothing.
        await #expect(throws: (any Error).self) {
            _ = try await model.adoptService(kind: .ssh, hostName: "nowhere",
                                             address: "   ", serviceName: "Terminal")
        }
        #expect(model.catalogHosts.isEmpty)
    }
}
