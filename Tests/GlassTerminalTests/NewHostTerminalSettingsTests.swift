import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlasSecretStore
import GlassShell
@testable import GlassTerminal

/// 2026-09-22: *"The whole set of settings for the terminal: user name, etc. — the settings weren't
/// saved."* A new machine ("Public") added through the host sheet, a first connect that failed at
/// the trust prompt, and Edit showing an empty Terminal form. These drive the real sheet and a
/// real catalog file to find which step loses them.
@MainActor
@Suite("A new machine's terminal settings survive")
struct NewHostTerminalSettingsTests {
    private func launch(over root: URL) -> (GlassShellModel, GlassTerminalRuntime) {
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false,
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
        return (model, runtime)
    }

    private func editDraft(_ model: GlassShellModel, host hostID: HostID) throws -> TerminalServiceDraft {
        let host = try #require(model.host(hostID))
        let link = try #require(model.services(for: hostID).first)
        let edit = GlassShellSetupModel(model: model, mode: .editService(host, link))
        return try #require(edit.draft(for: .ssh) as? TerminalServiceDraft)
    }

    @Test("Added through the sheet, the settings are what Edit shows — before and after a relaunch")
    func settingsSurviveEditAndRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewHost-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let (model, runtime) = launch(over: root)
        await model.load()
        let key = StoredSSHKey(name: "k", algorithm: "ssh-ed25519")
        runtime.settingsManager.sshKeys = [key]
        let setup = GlassShellSetupModel(model: model, mode: .addHost)
        setup.name = "Public"
        setup.address = "203.0.113.10"
        let draft = try #require(setup.draft(for: .ssh) as? TerminalServiceDraft)
        draft.username = "deploy"
        draft.port = "2222"
        draft.authMethod = .sshKey
        draft.sshKeyID = key.id
        let hostID = try #require(await setup.save(), "sheet: \(setup.error ?? "")")

        let before = try editDraft(model, host: hostID)
        #expect(before.username == "deploy", "Edit right after saving")
        #expect(before.port == "2222")

        let (model2, _) = launch(over: root)
        await model2.load()
        let after = try editDraft(model2, host: hostID)
        #expect(after.username == "deploy", "Edit after a relaunch")
        #expect(after.port == "2222")
    }
}
