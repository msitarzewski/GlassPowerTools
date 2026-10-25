//
//  D28KeyUsageTests.swift
//  Glass Power Tools — GlassShellTests
//
//  D28: what authenticates what is **derived, never stored**. The edge already exists on each
//  service's configuration, so a usage table would be a second copy of an existing truth that has
//  to be kept in step through deletion, editing, sync and merge — and D25 is the bug where deleting
//  a thing forgot to tell the other store.
//
//  The scenario these exist for is the user's: *bravo and alpha share a key, and the bravo
//  terminal using it is deleted. alpha's terminal still uses it.*
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// Answers whatever the test declares for each endpoint.
@MainActor
private final class CredentialCapability: GlassCapability {
    let kind: HostServiceKind = .ssh
    let displayName = "Credentials"
    let symbolName = "key"
    var credentials: [EndpointID: GlassServiceCredential] = [:]

    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.failed("not used")) }
    func credential(for service: HostServiceLink, host: HostProfile) -> GlassServiceCredential {
        credentials[service.endpointID] ?? .ownedByService
    }
}

@MainActor
@Suite("Which services use a key (D28)")
struct D28KeyUsageTests {

    private func makeShell() throws -> (GlassShellModel, CredentialCapability, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D28Usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore.forTest())
        let capability = CredentialCapability()
        model.registry.register(capability)
        return (model, capability, root)
    }

    /// The user's scenario, end to end.
    @Test func deletingOneUserOfASharedKeyLeavesTheOther() async throws {
        let (model, capability, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let key = UUID()

        let onAlpha = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                  address: "alpha.example", serviceName: "Terminal")
        let onBravo = try await model.adoptService(kind: .ssh, hostName: "bravo",
                                                      address: "bravo.example", serviceName: "Terminal")
        capability.credentials = [onAlpha: .sharedKey(id: key, deviceBound: false),
                                  onBravo: .sharedKey(id: key, deviceBound: false)]

        #expect(model.usageCount(ofKey: key).readable == 2)

        // bravo's terminal goes. Nothing points the key at alpha — it was never a stored edge.
        let bravoID = try #require(model.catalogHosts.first { $0.displayName == "bravo" }).id
        try await model.removeService(onBravo, from: bravoID)

        let remaining = model.services(usingKey: key)
        #expect(remaining.count == 1)
        #expect(remaining.first?.host.displayName == "alpha")
        #expect(model.usageCount(ofKey: key).readable == 1)
    }

    @Test func aPasswordIsNotSharedAndNeverCountsTowardsAKey() async throws {
        let (model, capability, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let key = UUID()

        let withKey = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                   address: "alpha.example", serviceName: "Key")
        let withPassword = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                        address: "alpha.example", serviceName: "Password")
        capability.credentials = [withKey: .sharedKey(id: key, deviceBound: false),
                                  withPassword: .ownedByService]

        #expect(model.services(usingKey: key).map(\.service.endpointID) == [withKey])
        #expect(model.usageCount(ofKey: key) == (readable: 1, unreadable: 0))
    }

    /// The failure mode designed in from the start: a key in use must never read as unused because
    /// this build could not read the record that uses it.
    @Test func anUnreadableConfigurationIsCountedRatherThanIgnored() async throws {
        let (model, capability, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let key = UUID()

        let readable = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                    address: "alpha.example", serviceName: "Known")
        let opaque = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                  address: "alpha.example", serviceName: "Newer build")
        capability.credentials = [readable: .sharedKey(id: key, deviceBound: false),
                                  opaque: .unreadable]

        let count = model.usageCount(ofKey: key)
        #expect(count == (readable: 1, unreadable: 1),
                "a record this build cannot read was silently treated as using nothing")
    }

    /// A key nothing uses says so plainly — the state after the user's deletion, and the signal
    /// that it is safe to delete.
    @Test func aKeyUsedByNothingReportsZero() async throws {
        let (model, capability, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let endpoint = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                    address: "alpha.example", serviceName: "Terminal")
        capability.credentials = [endpoint: .sharedKey(id: UUID(), deviceBound: false)]

        #expect(model.services(usingKey: UUID()).isEmpty)
        #expect(model.usageCount(ofKey: UUID()) == (readable: 0, unreadable: 0))
    }

    /// Both facts come from one question, so a device-bound key is still found by "used by".
    @Test func aDeviceBoundKeyIsStillCountedAsUsed() async throws {
        let (model, capability, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let key = UUID()

        let endpoint = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                    address: "alpha.example", serviceName: "Hardware")
        capability.credentials = [endpoint: .sharedKey(id: key, deviceBound: true)]

        #expect(model.usageCount(ofKey: key).readable == 1)
    }
}
