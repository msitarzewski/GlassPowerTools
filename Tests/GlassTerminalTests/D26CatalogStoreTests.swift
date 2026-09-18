//
//  D26CatalogStoreTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  D26: the catalog is the one store for a connection. These walk the seam end to end — a server
//  saved through `ServerManager` is written onto its service link, read back from the link, and
//  survives a manager that knows nothing except the catalog.
//
//  The point is the *join*. Every other terminal test uses `ServerPersistenceStore.live` and would
//  pass with the catalog never involved, which is exactly the shape of defect this project keeps
//  finding — so these build a real `GlassShellModel` and drive the manager through it.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlassShell
import GlasSecretStore
@testable import GlassTerminal

@MainActor
@Suite("The catalog is the one store for a connection (D26)")
struct D26CatalogStoreTests {

    private func makeShell() throws -> (GlassShellModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D26Store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        return (model, root)
    }

    /// A manager with no defaults behind it at all: everything it knows must come from the catalog.
    /// No Keychain behind it. Deleting a server asks the password store to remove the credential
    /// and verify its absence, and against the real Keychain in a test process that fails and rolls
    /// the whole delete back — which says nothing about the catalog, which is what these test.
    private var stubPasswords: ServerPasswordStore {
        ServerPasswordStore(retrieve: { _ in throw SecretStoreError.notFound },
                            save: { _, _ in },
                            delete: { _ in })
    }

    private func makeManager(_ model: GlassShellModel) -> ServerManager {
        let manager = ServerManager(loadImmediately: false,
                                    defaults: UserDefaults(suiteName: "d26.\(UUID().uuidString)")!,
                                    passwordStore: stubPasswords)
        manager.adoptHost = { hostName, address, serviceName in
            try await model.adoptService(kind: .ssh, hostName: hostName, address: address,
                                         serviceName: serviceName).rawValue
        }
        manager.discardAdoption = { await model.detachService(EndpointID(rawValue: $0)) }
        manager.attach(store: .catalog(model))
        return manager
    }

    @Test func aSavedServerIsWrittenOntoItsServiceLink() async throws {
        let (model, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let manager = makeManager(model)

        let adopted = try await manager.adoptedIdentity(hostName: "oscar", address: "oscar.example",
                                                    serviceName: "Terminal")
        try await manager.addServerOrThrow(
            ServerConfiguration(id: adopted.id, name: "oscar", host: "oscar.example", username: "michael"))

        // The catalog holds it, under the endpoint id the link uses — the invariant every
        // capability already relied on and D26 makes load-bearing.
        let stored = try #require(model.configuration(ServerConfiguration.self,
                                                      for: EndpointID(rawValue: adopted.id)))
        #expect(stored.name == "oscar")
        #expect(stored.username == "michael")
    }

    @Test func aFreshManagerReadsEveryServerBackOutOfTheCatalog() async throws {
        let (model, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let manager = makeManager(model)

        for name in ["alpha", "beta", "gamma"] {
            let adopted = try await manager.adoptedIdentity(hostName: name, address: "\(name).example",
                                                        serviceName: "Terminal")
            try await manager.addServerOrThrow(
                ServerConfiguration(id: adopted.id, name: name, host: "\(name).example", username: "m"))
        }

        // A second manager, its own empty defaults, nothing but the catalog to go on.
        let relaunched = makeManager(model)
        #expect(relaunched.servers.map(\.name).sorted() == ["alpha", "beta", "gamma"])
    }

    @Test func deletingAServerTakesItsServiceLinkWithIt() async throws {
        let (model, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let manager = makeManager(model)

        let adopted = try await manager.adoptedIdentity(hostName: "oscar", address: "oscar.example",
                                                    serviceName: "Terminal")
        let server = ServerConfiguration(id: adopted.id, name: "oscar", host: "oscar.example", username: "m")
        try await manager.addServerOrThrow(server)
        #expect(model.catalogHosts.flatMap(\.services).count == 1)

        try await manager.deleteServer(server)

        // Both halves, or it is an orphan either way round: no configuration, and no link pointing
        // at a configuration that is gone.
        #expect(model.configuration(for: EndpointID(rawValue: adopted.id)) == nil)
        #expect(model.catalogHosts.flatMap(\.services).isEmpty,
                "the service link outlived the server it described")
    }

    @Test func editingAServerRewritesTheLinkRatherThanAddingASecond() async throws {
        let (model, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let manager = makeManager(model)

        let adopted = try await manager.adoptedIdentity(hostName: "oscar", address: "oscar.example",
                                                    serviceName: "Terminal")
        var server = ServerConfiguration(id: adopted.id, name: "oscar", host: "oscar.example", username: "m")
        try await manager.addServerOrThrow(server)

        server.username = "michael"
        try await manager.updateServerOrThrow(server)

        #expect(model.catalogHosts.flatMap(\.services).count == 1)
        let stored = try #require(model.configuration(ServerConfiguration.self,
                                                      for: EndpointID(rawValue: adopted.id)))
        #expect(stored.username == "michael")
    }

    /// Reported 2026-09-17: a terminal service set up on the iPhone arrived on the Mac as a link
    /// the library offered Connect for, and connecting said it had never been set up. The desktop
    /// service added in the same sitting worked.
    ///
    /// The difference was not the sync. The catalog carried both configurations; the terminal
    /// **read its servers once**. `loadServersIfNeeded` refuses every call after the first, which
    /// is right for "the store can answer now" and wrong for "the store says something different
    /// now" — and the catalog says something different every time D19 delivers another device's
    /// changes. The desktop and the database have always re-read here.
    @Test func aServiceThatArrivesAfterTheFirstLoadIsStillFound() async throws {
        let (model, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let manager = makeManager(model)

        // Launch: the catalog can answer and holds nothing for this capability yet.
        manager.reloadFromStore()
        #expect(manager.servers.isEmpty)

        // Another device adds a terminal service and its configuration. This is what lands in the
        // catalog when D19 delivers; the shell then tells every capability the catalog has loaded.
        let adopted = try await manager.adoptedIdentity(hostName: "juliet",
                                                        address: "192.0.2.12",
                                                        serviceName: "Terminal")
        // One record per service link, which is how the catalog stores a configuration — not a
        // list on one link.
        try await model.setConfiguration(
            encoding: ServerConfiguration(id: adopted.id, name: "juliet",
                                          host: "192.0.2.12", username: "michael"),
            for: EndpointID(rawValue: adopted.id))

        // The shell's notification after a later load. Before the fix this was a no-op and the
        // server stayed invisible, so Connect reported a service that had never been set up.
        manager.reloadFromStore()
        #expect(manager.servers.contains { $0.id == adopted.id },
                "a service that arrived after the first load was never read")
        #expect(manager.server(for: adopted.id)?.host == "192.0.2.12")
    }

    /// The other half of the same report. When a service link arrives without its configuration,
    /// the library offers "Edit the service to set it up, or remove it" — and Edit had no draft to
    /// show, so the only offered action that worked was the destructive one. A person following
    /// the instruction deletes the thing instead of fixing it.
    @Test func aServiceWithNoConfigurationCanStillBeSetUp() async throws {
        let (model, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let manager = makeManager(model)
        let capability = GlassTerminalCapability(runtime: GlassTerminalRuntime(layers: GlassLayerStore()))

        // A link with nothing behind it: what another device's sync leaves when the configuration
        // has not arrived.
        let adopted = try await manager.adoptedIdentity(hostName: "juliet",
                                                        address: "192.0.2.12",
                                                        serviceName: "Terminal")
        await model.load()
        let endpoint = EndpointID(rawValue: adopted.id)
        let host = try #require(model.hosts.compactMap { model.record($0.id) }
            .first { $0.services.contains { $0.endpointID == endpoint } })
        let link = try #require(host.services.first { $0.endpointID == endpoint })
        #expect(link.configuration == nil, "this test is only meaningful for an unconfigured link")

        #expect(capability.setupDraft(for: link, host: host) != nil,
                "Edit offered no way to set up a service the app told the user to edit")
    }

    /// **How the configuration was destroyed, not merely unread.**
    ///
    /// `GlassServiceRecords.replaceAll` reconciles the catalog to the list it is handed: every
    /// stored configuration of that kind which is *not* in the list is deleted. That is correct
    /// when the list is current and catastrophic when it is stale — and the terminal's list was
    /// stale by construction, because it read once and ignored every later catalog load.
    ///
    /// So a terminal service set up on the iPhone reached the Mac, and the Mac's next save wrote
    /// its own stale list back over the catalog and removed the configuration the phone had put
    /// there. The link survived, because a reconcile clears configurations and not links — which
    /// is exactly the state that was reported: a service the library offers Connect for, with
    /// nothing behind it.
    ///
    /// The guard in `replaceAll` catches "the catalog was never read". It cannot catch "the
    /// catalog was read, and then changed underneath us", which is what D19 does on every
    /// delivery. Freshness is the capability's to maintain, and this is the test that says so.
    @Test func aStaleListDeletesAnotherDevicesConfiguration() async throws {
        let (model, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let manager = makeManager(model)
        manager.reloadFromStore()

        // This device saves one server.
        let mine = try await manager.adoptedIdentity(hostName: "oscar", address: "oscar.example",
                                                     serviceName: "Terminal")
        try await manager.addServerOrThrow(
            ServerConfiguration(id: mine.id, name: "oscar", host: "oscar.example", username: "michael"))

        // Another device adds its own terminal service and configuration; D19 delivers it into the
        // catalog. This device has not looked again.
        let theirs = try await manager.adoptedIdentity(hostName: "juliet",
                                                       address: "192.0.2.12",
                                                       serviceName: "Terminal")
        try await model.setConfiguration(
            encoding: ServerConfiguration(id: theirs.id, name: "juliet",
                                          host: "192.0.2.12", username: "michael"),
            for: EndpointID(rawValue: theirs.id))
        #expect(model.configuration(ServerConfiguration.self,
                                    for: EndpointID(rawValue: theirs.id)) != nil)

        // Re-reading is what keeps the next write honest. This is what `catalogDidLoad` now does,
        // and what it did not do before.
        manager.reloadFromStore()

        // Any save now reconciles the catalog to this device's list. With the list current, the
        // other device's record is in it and survives.
        try await manager.updateServerOrThrow(
            ServerConfiguration(id: mine.id, name: "oscar renamed", host: "oscar.example",
                                username: "michael"))
        #expect(model.configuration(ServerConfiguration.self,
                                    for: EndpointID(rawValue: theirs.id)) != nil,
                "a save on this device deleted a configuration another device had written")
    }
}
