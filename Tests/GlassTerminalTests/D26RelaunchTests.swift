//
//  D26RelaunchTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  What a relaunch does to saved settings, against a **real** `GlassShellModel` and a real host
//  catalog file on disk — the only arrangement that can see this.
//
//  The user reported it as *"Why are my connection settings reset each time?"*: the machine stayed
//  in the library, the SSH key stayed in the key list, and the terminal's service said **"This
//  terminal has no saved configuration behind it."**
//
//  The composition root attaches the catalog-backed store in `App.init`, and `attach(store:)` reads
//  it straight away — but `GlassShellModel.load()` runs later, from the library view's `.task`. So
//  the read happens against a model whose `records` are still empty, and an empty catalog and a
//  catalog nobody has read yet are indistinguishable through `configurations(ofKind:)`. The manager
//  concludes there are no saved servers, and the next write reconciles the catalog to match —
//  deleting every configuration it was supposed to be loading.
//
//  Both halves are tested: reading nothing, and then destroying what was there.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlasSecretStore
import GlassShell
@testable import GlassTerminal

@MainActor
@Suite("Relaunching with saved servers (D26)")
struct D26RelaunchTests {

    /// One process: a model over `root`, and a terminal runtime wired to it exactly as the
    /// composition root wires them.
    private func launch(over root: URL) -> (GlassShellModel, GlassTerminalRuntime) {
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore.forTest())
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        model.registry.register(GlassTerminalCapability(runtime: runtime))
        // Exactly the order `GlassPowerToolsApp.init` uses: attach first, load later.
        runtime.connectToLibrary(
            store: model,
            adopt: { hostName, address, serviceName in
                try await model.adoptService(kind: .ssh, hostName: hostName, address: address,
                                             serviceName: serviceName).rawValue
            },
            discard: { await model.detachService(EndpointID(rawValue: $0)) })
        return (model, runtime)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D26Relaunch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A saved server has to still be there after the app is started again.
    @Test func aSavedServerSurvivesARelaunch() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // First launch: add a machine with a terminal on it.
        let (model, runtime) = launch(over: root)
        await model.load()
        let manager = runtime.sessionManager.serverManager
        let endpoint = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                    address: "192.0.2.10", serviceName: "Terminal")
        let server = ServerConfiguration(id: endpoint.rawValue, name: "Terminal on alpha",
                                         host: "192.0.2.10", port: 22, username: "casey",
                                         authMethod: .sshKey)
        try await manager.addServerOrThrow(server)
        #expect(model.configuration(for: endpoint) != nil, "the first launch did not save the server")

        // Second launch, over the same storage.
        let (model2, runtime2) = launch(over: root)
        await model2.load()
        let manager2 = runtime2.sessionManager.serverManager

        #expect(manager2.servers.count == 1,
                "the saved server was not read back after relaunch — the terminal shows no saved configuration")
        #expect(manager2.serverCatalogLoadError == nil,
                "reading the catalog reported \(String(describing: manager2.serverCatalogLoadError))")
    }

    /// The half that destroys data: having read nothing, the next write must not conclude that
    /// nothing is what the catalog should contain.
    @Test func aWriteAfterARelaunchDoesNotEraseWhatWasAlreadyStored() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let (model, runtime) = launch(over: root)
        await model.load()
        let kept = try await model.adoptService(kind: .ssh, hostName: "alpha",
                                                address: "192.0.2.10", serviceName: "Terminal")
        let server = ServerConfiguration(id: kept.rawValue, name: "Terminal on alpha",
                                         host: "192.0.2.10", port: 22, username: "casey",
                                         authMethod: .sshKey)
        try await runtime.sessionManager.serverManager.addServerOrThrow(server)

        // Relaunch, then do something that persists — adding a second machine, the most ordinary
        // action there is.
        let (model2, runtime2) = launch(over: root)
        await model2.load()
        let manager2 = runtime2.sessionManager.serverManager
        let second = try await model2.adoptService(kind: .ssh, hostName: "bravo",
                                                   address: "198.51.100.9", serviceName: "Terminal")
        let another = ServerConfiguration(id: second.rawValue, name: "Terminal on bravo",
                                          host: "198.51.100.9", port: 22, username: "casey",
                                          authMethod: .sshKey)
        try await manager2.addServerOrThrow(another)

        #expect(model2.configuration(for: kept) != nil,
                "adding a second machine deleted the first machine's saved terminal")
        #expect(model2.configuration(for: second) != nil, "the second machine was not saved")
    }
}
