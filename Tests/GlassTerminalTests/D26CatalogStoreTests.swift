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
}
