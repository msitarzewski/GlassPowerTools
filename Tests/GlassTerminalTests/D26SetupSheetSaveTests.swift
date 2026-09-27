//
//  D26SetupSheetSaveTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  Adding a service through the host sheet, against a **real** `GlassShellModel` and a real
//  capability.
//
//  This exists because D26 stage 1 broke exactly this and every test passed. The capability tests
//  drive `GlassInMemoryServiceStore`, which will store a configuration for any endpoint id; the real
//  model will not, because a configuration lives *on* a service link and there has to be a link to
//  hang it on. The sheet committed the draft before creating the link, so the first thing a user did
//  after installing was "That service is no longer on the host."
//
//  A test double more permissive than production is not a test double, it is a second
//  implementation with different rules. These use the real one.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlasSecretStore
import GlassShell
@testable import GlassTerminal

@MainActor
@Suite("Saving a service through the host sheet (D26)")
struct D26SetupSheetSaveTests {

    private func makeShell() throws -> (GlassShellModel, GlassTerminalRuntime, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D26Sheet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        let runtime = GlassTerminalRuntime()
        model.registry.register(GlassTerminalCapability(runtime: runtime))
        runtime.connectToLibrary(
            store: model,
            adopt: { hostName, address, serviceName in
                try await model.adoptService(kind: .ssh, hostName: hostName, address: address,
                                             serviceName: serviceName).rawValue
            },
            discard: { await model.detachService(EndpointID(rawValue: $0)) })
        return (model, runtime, root)
    }

    /// The exact flow that failed: Add Host with a Terminal service, in one save.
    @Test func addingAHostWithATerminalServiceSavesBoth() async throws {
        let (model, runtime, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let setup = GlassShellSetupModel(model: model, mode: .addHost)
        setup.name = "scratch"
        setup.address = "192.0.2.6"
        let draft = try #require(setup.draft(for: .ssh) as? TerminalServiceDraft)
        draft.username = "michael"
        draft.port = "22"
        // Key auth, because the password path writes to the real Keychain and this suite is about
        // the order the link and the record are created in, not about credentials.
        let key = StoredSSHKey(name: "k", algorithm: "ssh-ed25519")
        runtime.settingsManager.sshKeys = [key]
        draft.authMethod = .sshKey
        draft.sshKeyID = key.id

        let issues = setup.validateForSave()
        #expect(issues.host.isEmpty && issues.services.isEmpty,
                "validation refused: host \(issues.host.map(\.message)) services \(issues.services.mapValues { $0.map(\.message) })")
        let hostID = await setup.save()

        #expect(setup.error == nil, "the sheet reported: \(setup.error ?? "")")
        let saved = try #require(hostID, "sheet error: \(setup.error ?? "none")")
        let services = model.services(for: saved)
        #expect(services.count == 1, "the service link was not created")

        // The link exists *and* the capability's record is behind it. Either alone is the bug.
        let endpoint = try #require(services.first).endpointID
        #expect(model.configuration(for: endpoint) != nil,
                "the link has no configuration behind it")
        #expect(runtime.sessionManager.serverManager.server(for: endpoint.rawValue)?.username == "michael")
    }

    /// Adding a second service to a machine that already exists, which is the other door in.
    @Test func addingAServiceToAnExistingHostSavesIt() async throws {
        let (model, runtime, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let created = try await model.addHost(displayName: "alpha", address: "alpha.example")
        let host = try #require(model.host(created.id))

        let setup = GlassShellSetupModel(model: model, mode: .addService(host, .ssh))
        let draft = try #require(setup.draft(for: .ssh) as? TerminalServiceDraft)
        draft.username = "michael"
        draft.port = "22"
        // Key auth, because the password path writes to the real Keychain and this suite is about
        // the order the link and the record are created in, not about credentials.
        let key = StoredSSHKey(name: "k", algorithm: "ssh-ed25519")
        runtime.settingsManager.sshKeys = [key]
        draft.authMethod = .sshKey
        draft.sshKeyID = key.id

        let hostID = await setup.save()

        #expect(setup.error == nil, "the sheet reported: \(setup.error ?? "")")
        let saved = try #require(hostID, "sheet error: \(setup.error ?? "none")")
        let endpoint = try #require(model.services(for: saved).first).endpointID
        #expect(model.configuration(for: endpoint) != nil)
        #expect(runtime.sessionManager.serverManager.server(for: endpoint.rawValue) != nil)
    }

    /// A draft that cannot commit must leave no half-made machine behind.
    @Test func aFailedCommitLeavesNoLinkBehind() async throws {
        let (model, runtime, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let setup = GlassShellSetupModel(model: model, mode: .addHost)
        setup.name = "scratch"
        setup.address = "192.0.2.6"
        let draft = try #require(setup.draft(for: .ssh) as? TerminalServiceDraft)
        draft.username = ""          // required; the draft refuses to commit
        draft.port = "not a port"

        let hostID = await setup.save()

        #expect(hostID == nil, "a save that could not commit reported success")
        #expect(model.catalogHosts.flatMap(\.services).isEmpty,
                "a service link outlived the record it was made for")
    }
}
