import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlassShell
import GlasSecretStore
@testable import GlassTerminal

/// D44: a connection records whether the host has tmux, and the first one that finds it asks once.
@Suite("tmux availability and the offer")
@MainActor
struct TerminalTmuxOfferTests {
    private func fixture() async throws -> (SessionManager, ServerConfiguration, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TmuxOffer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"), sharedContainerURL: nil,
                                    resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        await model.load()
        let servers = ServerManager(loadImmediately: false,
                                    defaults: UserDefaults.forTest(suiteName: "tmux.\(UUID().uuidString)")!,
                                    passwordStore: ServerPasswordStore(retrieve: { _ in throw SecretStoreError.notFound },
                                                                       save: { _, _ in }, delete: { _ in }))
        servers.adoptHost = { hostName, address, serviceName in
            try await model.adoptService(kind: .ssh, hostName: hostName, address: address, serviceName: serviceName).rawValue
        }
        servers.discardAdoption = { await model.detachService(EndpointID(rawValue: $0)) }
        servers.attach(store: .catalog(model))
        let adopted = try await servers.adoptedIdentity(hostName: "alpha", address: "alpha.example", serviceName: "Terminal")
        try await servers.addServerOrThrow(ServerConfiguration(id: adopted.id, name: "alpha", host: "alpha.example", username: "ann"))
        return (SessionManager(serverManager: servers, loadImmediately: false), try #require(servers.server(for: adopted.id)), root)
    }

    @Test("found once: recorded, offered; answered: never offered again, on any device")
    func offerOnce() async throws {
        let (manager, server, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = TerminalSession(server: server)
        await manager.noteTmuxAvailability(true, on: first)?.value
        #expect(first.tmuxOffer)
        #expect(manager.serverManager.server(for: server.id)?.tmuxAvailable == true)

        await manager.answerTmuxOffer(for: first, turnOn: true)
        let saved = try #require(manager.serverManager.server(for: server.id))
        #expect(!first.tmuxOffer && saved.tmuxOffered == true && saved.keepsSessionsInTmux)

        let second = TerminalSession(server: saved)
        manager.noteTmuxAvailability(true, on: second)
        #expect(!second.tmuxOffer, "already on, and already answered")
    }

    @Test("Not Now is remembered, and a host without tmux is never offered")
    func declineAndMissing() async throws {
        let (manager, server, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = TerminalSession(server: server)
        await manager.noteTmuxAvailability(false, on: missing)?.value
        #expect(!missing.tmuxOffer)
        #expect(manager.serverManager.server(for: server.id)?.tmuxAvailable == false)

        let found = TerminalSession(server: server)
        manager.noteTmuxAvailability(true, on: found)
        #expect(found.tmuxOffer)
        await manager.answerTmuxOffer(for: found, turnOn: false)
        let saved = try #require(manager.serverManager.server(for: server.id))
        #expect(saved.tmuxOffered == true && !saved.keepsSessionsInTmux)
        let later = TerminalSession(server: saved)
        manager.noteTmuxAvailability(true, on: later)
        #expect(!later.tmuxOffer)
    }
}
