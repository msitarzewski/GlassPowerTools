//
//  GlassShellHostTrustTests.swift
//  Glass Power Tools — GlassShellTests
//
//  D14: a capability may have a machine's SSH host-key trust settled on its behalf, by the
//  capability that owns `.ssh`, without importing it. Three outcomes rather than a boolean,
//  because the sheet must say something different about each.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

@MainActor
private final class TrustingCapability: GlassCapability {
    let kind: HostServiceKind = .ssh
    var displayName: String { "Terminal" }
    var symbolName: String { "terminal" }
    var asked: [String] = []
    var outcome: GlassHostTrustOutcome = .trusted

    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}

    func resolveHostTrust(host: HostProfile) async -> GlassHostTrustOutcome {
        asked.append(host.displayName)
        return outcome
    }
}

/// Never adopted the hook, to prove the default refuses rather than pretending.
@MainActor
private final class SilentSSHCapability: GlassCapability {
    let kind: HostServiceKind = .ssh
    var displayName: String { "Terminal" }
    var symbolName: String { "terminal" }
    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
}

@MainActor
private func makeModel(registry: GlassCapabilityRegistry) throws -> (GlassShellModel, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassShellTrust-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                sharedContainerURL: root.appendingPathComponent("group"),
                                resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                layers: GlassLayerStore.forTest(), registry: registry)
    return (model, root)
}

@Suite("Resolving the host's SSH trust", .serialized)
@MainActor
struct GlassShellHostTrustTests {

    @Test("A host with an SSH service has its trust resolved by whichever capability owns it")
    func resolvesThroughTheSSHCapability() async throws {
        let registry = GlassCapabilityRegistry()
        let ssh = TrustingCapability()
        registry.register(ssh)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }

        let host = try await model.addHost(displayName: "Box", address: "10.0.0.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)

        #expect(await model.hostAccess(for: host.id).resolveHostTrust() == .trusted)
        #expect(ssh.asked == ["Box"])
    }

    @Test("Declining is carried through as declining, not flattened into unavailable")
    func decliningIsItsOwnOutcome() async throws {
        let registry = GlassCapabilityRegistry()
        let ssh = TrustingCapability()
        ssh.outcome = .declined
        registry.register(ssh)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }

        let host = try await model.addHost(displayName: "Box", address: "10.0.0.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)
        #expect(await model.hostAccess(for: host.id).resolveHostTrust() == .declined)
    }

    @Test("A host with no SSH service has nobody to ask")
    func noSSHServiceIsUnavailable() async throws {
        let registry = GlassCapabilityRegistry()
        registry.register(TrustingCapability())
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }

        let host = try await model.addHost(displayName: "DBOnly", address: "10.0.0.10")
        _ = try await model.addService(kind: .database, displayName: "Postgres", to: host.id)
        #expect(await model.hostAccess(for: host.id).resolveHostTrust() == .unavailable)
    }

    @Test("With no capability registered for SSH there is nobody to ask")
    func noCapabilityIsUnavailable() async throws {
        let (model, root) = try makeModel(registry: GlassCapabilityRegistry())
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Box", address: "10.0.0.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)
        #expect(await model.hostAccess(for: host.id).resolveHostTrust() == .unavailable)
    }

    @Test("A capability that never adopted the hook refuses rather than pretending")
    func unadoptedHookRefuses() async throws {
        let registry = GlassCapabilityRegistry()
        registry.register(SilentSSHCapability())
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }

        let host = try await model.addHost(displayName: "Box", address: "10.0.0.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)
        #expect(await model.hostAccess(for: host.id).resolveHostTrust() == .unavailable)
    }

    @Test("Trust resolution and the forward resolve on the same conditions")
    func trustAndForwardAgree() async throws {
        let registry = GlassCapabilityRegistry()
        registry.register(TrustingCapability())
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }

        // No SSH service: neither is possible, so the sheet cannot promise what connect cannot do.
        let dbOnly = try await model.addHost(displayName: "DBOnly", address: "10.0.0.10")
        _ = try await model.addService(kind: .database, displayName: "Postgres", to: dbOnly.id)
        let dbAccess = model.hostAccess(for: dbOnly.id)
        #expect(!dbAccess.canForwardPorts)
        #expect(await dbAccess.resolveHostTrust() == .unavailable)

        let box = try await model.addHost(displayName: "Box", address: "10.0.0.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: box.id)
        let boxAccess = model.hostAccess(for: box.id)
        #expect(boxAccess.canForwardPorts)
        #expect(await boxAccess.resolveHostTrust() == .trusted)
    }
}
