//
//  GlassShellServiceStateTests.swift
//  Glass Power Tools — GlassShellTests
//
//  A service link with nothing behind it is a different thing from a service, and the library has
//  to be able to tell them apart.
//
//  Reported 2026-09-16: oscar showed **two Terminals and two Desktops**, identical in every visible
//  way. One of each was dead — the persistence defect emptied the configuration behind a link
//  without removing the link, and re-adding the service created a second link beside the corpse.
//  Pressing Connect on the wrong one said "has no saved configuration", which is the first moment
//  anything told the user which was which.
//
//  This is the model half of the fix: the shell can answer "is there a record behind this link?"
//  without asking a capability to build a draft. The row's wording is a view and is not tested
//  here; what is tested is that the question has the right answer, including for the built-in
//  local services that are *supposed* to have nothing stored (D8).
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

@MainActor
private final class StubCapability: GlassCapability {
    let kind: HostServiceKind
    let displayName = "Stub"
    let symbolName = "circle"
    var builtIn: [HostServiceLink] = []

    init(kind: HostServiceKind = .ssh) { self.kind = kind }

    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.failed("not used")) }
    func builtInLocalServices() -> [HostServiceLink] { builtIn }
}

@MainActor
@Suite("A link with nothing behind it")
struct GlassShellServiceStateTests {

    private func makeShell() throws -> (GlassShellModel, StubCapability, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServiceState-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        let capability = StubCapability()
        model.registry.register(capability)
        return (model, capability, root)
    }

    /// The exact shape the user saw: one machine, two links of the same kind, one configured.
    @Test func aConfiguredLinkAndABareOneAreDistinguishable() async throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let live = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                address: "192.0.2.10", serviceName: "Terminal on oscar")
        let dead = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                address: "192.0.2.10", serviceName: "Terminal on oscar")
        try await model.setConfiguration(Data("a saved server".utf8), for: live)

        #expect(model.configuration(for: live) != nil, "the configured link reads as empty")
        #expect(model.configuration(for: dead) == nil, "the bare link reads as configured")

        // Both are on the same machine, which is why they look identical in the list.
        let host = try #require(model.hosts.first { $0.displayName == "oscar" })
        let terminals = host.services.filter { $0.kind == .ssh }
        #expect(terminals.count == 2)
    }

    /// Removing the dead one leaves the live one alone — the actual repair a user performs.
    @Test func removingTheBareLinkKeepsTheConfiguredOne() async throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let live = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                address: "192.0.2.10", serviceName: "Terminal on oscar")
        let dead = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                address: "192.0.2.10", serviceName: "Terminal on oscar")
        try await model.setConfiguration(Data("a saved server".utf8), for: live)

        let host = try #require(model.hosts.first { $0.displayName == "oscar" })
        try await model.removeService(dead, from: host.id)

        let after = try #require(model.hosts.first { $0.displayName == "oscar" })
        #expect(after.services.filter { $0.kind == .ssh }.count == 1)
        #expect(model.configuration(for: live) != nil, "removing the dead link took the live one's record")
    }

    /// The device's own services store nothing by design (D8) and must never be called unset —
    /// marking them would put a warning on every launch, on the one host nobody can repair.
    @Test func builtInLocalServicesAreNotUnconfigured() async throws {
        let (model, capability, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        capability.builtIn = [HostServiceLink(endpointID: EndpointID(rawValue: UUID()),
                                              kind: .ssh, displayName: "This Mac")]
        await model.load()

        let local = try #require(model.hosts.first { $0.isLocal })
        for service in local.services {
            // Nothing stored…
            #expect(model.configuration(for: service.endpointID) == nil)
            // …and that is correct, not a fault: the host says so itself.
            #expect(local.isBuiltIn(service.endpointID),
                    "\(service.displayName) is stored-less but not marked built in")
        }
    }
}
