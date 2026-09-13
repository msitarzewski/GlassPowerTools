//
//  GlassShellTunnelHopTests.swift
//  Glass Power Tools — GlassShellTests
//
//  Which machine a borrowed SSH forward actually runs through.
//
//  **A host in this product is a group, not a machine.** `GlassShellHostGrouping.group` joins
//  records whose normalised display names match — one of three ways in, and it does not require
//  their addresses to agree. `GlassShellHost` is candid about it: `addresses` is plural and
//  `address` is simply the first. Two records both called "db" on different machines are one row,
//  which is exactly what the three source apps produced.
//
//  The hazard the 2026-09-13 security review found: `portForwardProvider` took the first member
//  with an `.ssh` service, which picks a machine by creation order. A database on the newer record
//  would be tunnelled through the SSH service on the **older** one, and `DatabaseSessionManager`
//  then opens the forward to `127.0.0.1:port` as that other machine sees it and sends the username
//  and password down it. With TLS off — the ordinary setting for a tunnelled database — nothing
//  detects it.
//
//  These tests pin the rule that replaced it: the SSH service must belong to the machine the host
//  *is*, and an ambiguous group refuses rather than guesses.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassHostCatalog
import GlassLayers
@testable import GlassShell

@MainActor private func makeHopModel() throws -> (GlassShellModel, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("GlassShellTunnelHop-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                sharedContainerURL: root.appendingPathComponent("group"),
                                resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                layers: GlassLayerStore())
    return (model, root)
}

@Suite("Borrowed forwards choose the right machine", .serialized)
@MainActor
struct GlassShellTunnelHopTests {
    private func sshLink(_ name: String = "shell") -> HostServiceLink {
        HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: name)
    }

    private func databaseLink() -> HostServiceLink {
        HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "db")
    }

    /// The defect in its simplest form: same name, different machines, and the SSH service on the
    /// one the host is *not*.
    @Test("A group whose SSH member is a different machine offers no forward")
    func mismatchedAddressRefusesToTunnel() async throws {
        let (model, root) = try makeHopModel()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = HostCatalogStore(fileURL: model.catalogFileURL)
        // Oldest first: this one supplies `host.address`, and carries no SSH service.
        try await store.upsert(try HostProfile(displayName: "db", address: "10.0.0.1",
                                               services: [databaseLink()]))
        // Same display name, different machine, and this is the one with SSH.
        try await store.upsert(try HostProfile(displayName: "db", address: "10.0.0.99",
                                               services: [sshLink()]))
        await model.load()

        let host = try #require(model.catalogHosts.first { $0.displayName == "db" })
        #expect(host.members.count == 2, "the two records group under one row, which is the premise")

        // The only SSH service belongs to 10.0.0.99 while the host is 10.0.0.1: refuse rather than
        // send this database's credentials to a machine the user did not choose.
        #expect(model.sshMember(of: host) == nil)
        #expect(!model.hostAccess(for: host.id).canForwardPorts)
    }

    /// The ordinary case must keep working, or the fix has simply disabled tunnelling.
    @Test("A host whose SSH service is on its own machine still offers a forward")
    func matchingAddressStillTunnels() async throws {
        let (model, root) = try makeHopModel()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = HostCatalogStore(fileURL: model.catalogFileURL)
        try await store.upsert(try HostProfile(displayName: "box", address: "10.0.0.5",
                                               services: [sshLink(), databaseLink()]))
        await model.load()

        let host = try #require(model.catalogHosts.first { $0.displayName == "box" })
        // Asked of the selection itself: `canForwardPorts` is additionally false whenever no `.ssh`
        // capability is registered, which is the case in a bare test model, so it cannot tell a
        // correct choice from a refused one.
        let member = try #require(model.sshMember(of: host), "one machine, its own SSH service")
        #expect(member.address == "10.0.0.5")
    }

    /// Two records for the same machine — the case grouping exists for — must still tunnel.
    @Test("Two records at the same address are one machine and still tunnel")
    func duplicateRecordsAtOneAddressStillTunnel() async throws {
        let (model, root) = try makeHopModel()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = HostCatalogStore(fileURL: model.catalogFileURL)
        try await store.upsert(try HostProfile(displayName: "dup", address: "10.0.0.7",
                                               services: [databaseLink()]))
        try await store.upsert(try HostProfile(displayName: "dup", address: "10.0.0.7",
                                               services: [sshLink()]))
        await model.load()

        let host = try #require(model.catalogHosts.first { $0.displayName == "dup" })
        #expect(host.members.count == 2)
        let member = try #require(model.sshMember(of: host),
                                  "same address, so the SSH service reaches the right machine")
        #expect(member.address == "10.0.0.7")
    }

    /// Trust and the forward must choose the same member, or a user could approve a fingerprint
    /// for one machine while their data goes to another. The two resolvers are documented as
    /// answering on identical conditions; this holds them to it.
    @Test("Trust resolution is offered on exactly the conditions a forward is")
    func trustAndForwardAgree() async throws {
        let (model, root) = try makeHopModel()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = HostCatalogStore(fileURL: model.catalogFileURL)
        try await store.upsert(try HostProfile(displayName: "split", address: "10.0.0.1",
                                               services: [databaseLink()]))
        try await store.upsert(try HostProfile(displayName: "split", address: "10.0.0.99",
                                               services: [sshLink()]))
        await model.load()

        let host = try #require(model.catalogHosts.first { $0.displayName == "split" })
        // Both resolvers are built from the same selection, so neither can offer what the other
        // cannot: with no usable SSH member, trust reports `.unavailable` and no forward is offered.
        #expect(model.sshMember(of: host) == nil)
        let access = model.hostAccess(for: host.id)
        #expect(!access.canForwardPorts)
        #expect(await access.resolveHostTrust() == .unavailable,
                "resolveHostTrust must not promise more than forwardPort can deliver")
    }
}
