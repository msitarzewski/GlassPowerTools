import Foundation
import Testing
import GlassConnectionKit
import GlassHostCatalog
import GlassLayers
@testable import GlassShell

@MainActor private func makeModel() throws -> (GlassShellModel, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassShellAddressTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                sharedContainerURL: root.appendingPathComponent("group"),
                                resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                layers: GlassLayerStore())
    return (model, root)
}

/// A capability that remembers what the shell told it about addresses and what it was handed
/// to open with.
@MainActor
private final class AddressAwareCapability: GlassCapability {
    let kind: HostServiceKind
    var displayName: String { "Address-aware" }
    var symbolName: String { "circle" }
    var addressChanges: [(HostID, String?)] = []
    var openedWith: [GlassCapabilityHostAccess] = []
    /// Endpoints the capability already holds a saved record for, with that record's address.
    var savedAddresses: [EndpointID: String] = [:]
    init(kind: HostServiceKind) { self.kind = kind }
    func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
    func open(service: HostServiceLink, host: HostProfile, hostAccess: GlassCapabilityHostAccess,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
        openedWith.append(hostAccess)
        report(.dismissed)
    }
    func hostAddressDidChange(host: HostProfile, address: String?) { addressChanges.append((host.id, address)) }
    func knownAddress(service: HostServiceLink, host: HostProfile) -> String? { savedAddresses[service.endpointID] }
}

@Suite("Host address in the shell", .serialized)
@MainActor
struct GlassShellHostAddressTests {
    @Test("The address is stored on the host, normalised, shown once, and survives reload")
    func addressIsOnTheHost() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let created = try await model.addHost(displayName: "golf", address: " Scratch.Example.COM ")
        #expect(created.address == "golf.example.com")
        #expect(model.host(created.id)?.address == "golf.example.com")
        let blank = try await model.addHost(displayName: "noaddr", address: "   ")
        #expect(blank.address == nil, "blank means unset, not an invalid empty address")
        await #expect(throws: HostProfileError.invalidAddress) {
            _ = try await model.addHost(displayName: "bad", address: "user@host:22")
        }
        #expect(GlassShellError.message(for: HostProfileError.invalidAddress).contains("hostname or an IP"))

        let reloaded = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                       sharedContainerURL: root.appendingPathComponent("group"),
                                       resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                       layers: GlassLayerStore())
        await reloaded.load()
        #expect(reloaded.host(created.id)?.address == "golf.example.com")
    }

    @Test("Editing the address tells every capability with a service on the host, once per member record")
    func addressChangeReachesCapabilities() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = AddressAwareCapability(kind: .ssh), rdp = AddressAwareCapability(kind: .rdp)
        model.registry.register(ssh); model.registry.register(rdp)
        let host = try await model.addHost(displayName: "box", address: "10.0.0.1")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)

        try await model.updateHost(host.id, displayName: "box", address: "10.0.0.2", aliases: [], tags: [])
        #expect(ssh.addressChanges.map(\.1) == ["10.0.0.2"], "the ssh capability owns a service on the record")
        #expect(rdp.addressChanges.isEmpty, "no rdp service on the host: nothing to update")

        try await model.updateHost(host.id, displayName: "box renamed", address: "10.0.0.2", aliases: ["b"], tags: ["Lab"])
        #expect(ssh.addressChanges.count == 1, "an unchanged address is not announced")

        try await model.updateHost(host.id, displayName: "box renamed", address: "", aliases: [], tags: [])
        #expect(ssh.addressChanges.last?.1 == nil, "clearing is announced as nil")
        #expect(model.host(host.id)?.address == nil)
    }

    @Test("Connect hands the capability the host's address, read-only; a record without one is opened as is")
    func connectPassesTheHostAddress() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = AddressAwareCapability(kind: .ssh)
        model.registry.register(ssh)
        let host = try await model.addHost(displayName: "ready", address: "ready.example")
        let link = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)
        model.connect(hostID: host.id, endpointID: link.endpointID)
        #expect(ssh.openedWith.map(\.address) == ["ready.example"])

        // A record another family app wrote without an address: the capability still opens with
        // what it has; nothing in this app prompts for a setup on connect.
        let foreign = try await model.addHost(displayName: "foreign")
        let saved = try await model.addService(kind: .ssh, displayName: "Terminal", to: foreign.id)
        ssh.savedAddresses[saved.endpointID] = "10.0.0.5"
        model.connect(hostID: foreign.id, endpointID: saved.endpointID)
        #expect(ssh.openedWith.count == 2)
        #expect(model.errorMessage == nil)
    }

    @Test("A record another app saved with an address lends it to the host, on load")
    func knownAddressIsAdopted() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = AddressAwareCapability(kind: .ssh)
        model.registry.register(ssh)
        let host = try await model.addHost(displayName: "old")
        let saved = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)
        let pending = try await model.addService(kind: .ssh, displayName: "Second terminal", to: host.id)
        ssh.savedAddresses[saved.endpointID] = "10.0.0.7"
        #expect(model.host(host.id)?.address == nil)

        await model.load()
        #expect(model.host(host.id)?.address == "10.0.0.7", "adopted from the saved record on load")

        // Connecting the other service hands the capability the adopted address.
        model.connect(hostID: host.id, endpointID: pending.endpointID)
        #expect(ssh.openedWith.map(\.address) == ["10.0.0.7"])

        // Disagreeing records are not guessed at.
        let torn = try await model.addHost(displayName: "torn")
        let a = try await model.addService(kind: .ssh, displayName: "A", to: torn.id)
        let b = try await model.addService(kind: .ssh, displayName: "B", to: torn.id)
        ssh.savedAddresses[a.endpointID] = "10.1.0.1"; ssh.savedAddresses[b.endpointID] = "10.1.0.2"
        await model.load()
        #expect(model.host(torn.id)?.address == nil, "two different saved addresses: left for the user")
        #expect(model.knownAddress(for: try #require(model.host(torn.id))) == nil)
    }

    @Test("Records that carry the same address are one host; a disagreement is surfaced, then settled by one edit")
    func addressGroupsAndDisagreementIsSettled() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let sibling = HostCatalogStore(fileURL: root.appendingPathComponent("group/GlassHostCatalog/hosts.json"))
        let a = try HostProfile(displayName: "Terminal box", address: "10.9.9.9",
                                services: [HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "t")],
                                createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
        let b = try HostProfile(displayName: "Desktop box", address: "10.9.9.9",
                                services: [HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "d")],
                                createdAt: Date(timeIntervalSince1970: 2), updatedAt: Date(timeIntervalSince1970: 2))
        let loop1 = try HostProfile(displayName: "Local A", address: "127.0.0.1")
        let loop2 = try HostProfile(displayName: "Local B", address: "127.0.0.1")
        // Same name, different addresses: grouped by name, and the disagreement is visible.
        let c1 = try HostProfile(displayName: "drift", address: "10.1.1.1",
                                 createdAt: Date(timeIntervalSince1970: 3), updatedAt: Date(timeIntervalSince1970: 3))
        let c2 = try HostProfile(displayName: "drift", address: "10.1.1.2",
                                 createdAt: Date(timeIntervalSince1970: 4), updatedAt: Date(timeIntervalSince1970: 4))
        for record in [a, b, loop1, loop2, c1, c2] { try await sibling.upsert(record) }
        await model.load()
        #expect(model.catalogHosts.count == 4, "same address groups; loopback never does; same name groups")
        let grouped = try #require(model.host(a.id))
        // Two records that agree on the address are one record after load, not a lasting group
        // (2026-09-21); `b` is folded into `a`, and `b.id` still resolves to it.
        #expect(grouped.members.map(\.id) == [b.id] && grouped.address == "10.9.9.9" && grouped.addresses == ["10.9.9.9"],
                "the most recently updated member survives the fold")
        #expect(grouped.services.count == 2)
        #expect(model.host(a.id)?.id == b.id)

        let drift = try #require(model.host(c1.id))
        #expect(drift.addresses == ["10.1.1.1", "10.1.1.2"] && drift.address == "10.1.1.1", "canonical first; both surfaced")
        try await model.updateHost(drift.id, displayName: "drift", address: "10.1.1.2", aliases: [], tags: [])
        let settled = try #require(model.host(c1.id))
        #expect(settled.addresses == ["10.1.1.2"], "one edit applies to every member record")
        #expect(try await sibling.snapshot().filter { $0.displayName == "drift" }.allSatisfy { $0.address == "10.1.1.2" })
    }
}

@Suite("Detail text")
@MainActor
struct GlassShellDetailTextTests {
    @Test("Connect opens names the kind first and drops a redundant endpoint name")
    func connectOpensText() throws {
        let host = GlassShellHost(members: [try HostProfile(displayName: "What is this?")])
        let kindOnly = HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "What is this?")
        #expect(GlassShellLibraryView.connectOpensText(kindOnly, host: host) == "Desktop")
        let shellDefault = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on What is this?")
        #expect(GlassShellLibraryView.connectOpensText(shellDefault, host: host) == "Terminal")
        let named = HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "Postgres 16")
        #expect(GlassShellLibraryView.connectOpensText(named, host: host) == "Database · Postgres 16")
    }

    @Test("Row subtitle names up to two kinds and counts more")
    func subtitle() {
        #expect(GlassShellModel.subtitle(for: []) == "No services yet")
        #expect(GlassShellModel.subtitle(for: [.rdp, .ssh]) == "Desktop · Terminal")
        #expect(GlassShellModel.subtitle(for: [.rdp, .ssh, .database]) == "3 services")
    }
}
