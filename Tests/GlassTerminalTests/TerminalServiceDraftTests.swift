import Foundation
import Testing
import GlassConnectionKit
import GlasSecretStore
import GlassShell
@testable import GlassTerminal

/// The terminal's service draft: what the shell's host sheet composes and commits.
@Suite("Terminal service draft", .serialized)
@MainActor
struct TerminalServiceDraftTests {
    /// An in-memory password store so the draft's persistence runs without the keychain.
    private func managers() -> (ServerManager, SettingsManager, String) {
        let suiteName = "sh.glas.test.draft.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        final class Passwords: @unchecked Sendable { var values: [UUID: String] = [:] }
        let passwords = Passwords()
        let store = ServerPasswordStore(
            retrieve: { server in
                guard let value = passwords.values[server.id] else { throw SecretStoreError.notFound }
                return value
            },
            save: { value, server in passwords.values[server.id] = value },
            delete: { id in passwords.values[id] = nil }
        )
        let servers = ServerManager(loadImmediately: false, defaults: defaults, passwordStore: store)
        servers.loadServersIfNeeded()
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        return (servers, settings, suiteName)
    }

    @Test("Draft → configuration → draft round-trips every field; the address comes from the host")
    func roundTrip() throws {
        let (servers, settings, suite) = managers()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let key = StoredSSHKey(name: "k", algorithm: "ssh-ed25519")
        settings.sshKeys = [key]
        let draft = TerminalServiceDraft(serverManager: servers, settingsManager: settings)
        draft.username = " casey "
        draft.port = "2222"
        draft.authMethod = .sshKey
        draft.sshKeyID = key.id
        draft.allowLegacyAlgorithms = true
        draft.colorTag = .green
        draft.usesAppDefaultTerminalSize = false
        draft.initialTerminalColumns = 132
        draft.initialTerminalRows = 40
        draft.name = ""
        let id = UUID()
        let configuration = try #require(draft.configuration(id: id, address: "192.0.2.6", name: draft.serviceDisplayName(hostName: "golf")))
        #expect(configuration.id == id && configuration.host == "192.0.2.6" && configuration.port == 2222)
        #expect(configuration.username == "casey" && configuration.name == "Terminal on golf")
        #expect(configuration.authMethod == .sshKey && configuration.sshKeyID == key.id)
        #expect(configuration.legacyAlgorithmsEnabled && configuration.colorTag == .green)
        #expect(configuration.initialTerminalColumns == 132 && configuration.initialTerminalRows == 40)

        let reloaded = TerminalServiceDraft(editing: configuration, serverManager: servers, settingsManager: settings)
        #expect(reloaded.username == "casey" && reloaded.port == "2222" && reloaded.authMethod == .sshKey)
        #expect(reloaded.sshKeyID == key.id && reloaded.allowLegacyAlgorithms && reloaded.colorTag == .green)
        #expect(!reloaded.usesAppDefaultTerminalSize && reloaded.initialTerminalColumns == 132 && reloaded.initialTerminalRows == 40)
        #expect(reloaded.name == "Terminal on golf" && reloaded.isEditing)
    }

    @Test("Validation as the shell sees it: no name needed, the host's address stands in, user and credential required")
    func validationForTheShell() {
        let (servers, settings, suite) = managers()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let draft = TerminalServiceDraft(serverManager: servers, settingsManager: settings)
        var issues = draft.validate(address: "10.0.0.1")
        #expect(issues.map(\.field) == ["username", "password"], "password is the default method")
        draft.username = "u"
        draft.authMethod = .sshKey
        issues = draft.validate(address: "10.0.0.1")
        #expect(issues.map(\.field) == ["sshKey"], "no key in the catalog: the key is the issue")
        let key = StoredSSHKey(name: "k", algorithm: "ssh-ed25519")
        settings.sshKeys = [key]
        draft.normalizeSelectedSSHKey()
        #expect(draft.sshKeyID == key.id, "the only key is selected")
        #expect(draft.validate(address: "10.0.0.1").isEmpty)
        draft.port = "70000"
        #expect(draft.validate(address: "10.0.0.1").map(\.field) == ["port"])
        draft.focusFirstIssue(draft.validate(address: "10.0.0.1"))
        #expect(draft.attemptedSave && draft.focusRequest == .port)
    }

    @Test("Commit persists under the shell's endpoint id with the host's address; rollback removes it")
    func commitAndRollback() async throws {
        let (servers, settings, suite) = managers()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let key = StoredSSHKey(name: "k", algorithm: "ssh-ed25519")
        settings.sshKeys = [key]
        let draft = TerminalServiceDraft(serverManager: servers, settingsManager: settings)
        draft.username = "casey"
        draft.authMethod = .sshKey
        draft.sshKeyID = key.id
        let endpoint = EndpointID()
        let host = try HostProfile(displayName: "golf", address: "192.0.2.6")
        try await draft.commit(endpointID: endpoint, host: host, address: "192.0.2.6")
        let saved = try #require(servers.server(for: endpoint.rawValue))
        #expect(saved.host == "192.0.2.6" && saved.username == "casey" && saved.name == "Terminal on golf")

        // Editing commits under the same id and keeps it one server.
        let edit = TerminalServiceDraft(editing: saved, serverManager: servers, settingsManager: settings)
        edit.port = "2200"
        try await edit.commit(endpointID: endpoint, host: host, address: "192.0.2.7")
        #expect(servers.servers.count == 1 && servers.server(for: endpoint.rawValue)?.port == 2200)
        #expect(servers.server(for: endpoint.rawValue)?.host == "192.0.2.7", "the address follows the host")

        await draft.rollback(endpointID: endpoint)
        #expect(servers.server(for: endpoint.rawValue) == nil)
        await draft.rollback(endpointID: endpoint)   // nothing left: tolerated
    }

    @Test("An invalid draft refuses to commit and reveals its issues")
    func invalidCommitThrows() async throws {
        let (servers, settings, suite) = managers()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let draft = TerminalServiceDraft(serverManager: servers, settingsManager: settings)
        let host = try HostProfile(displayName: "x", address: "x.example")
        await #expect(throws: TerminalServiceDraftError.self) {
            try await draft.commit(endpointID: EndpointID(), host: host, address: "x.example")
        }
        #expect(draft.attemptedSave && draft.touchedFields.contains(.username))
        #expect(servers.servers.isEmpty)
    }

    @Test("The capability hands the shell a fresh draft, a loaded one for a saved server, and a settable one for a bare link")
    func capabilityContract() throws {
        let runtime = GlassTerminalRuntime()
        let capability = GlassTerminalCapability(runtime: runtime)
        let fresh = capability.makeSetupDraft()
        #expect(fresh.kind == .ssh && fresh is TerminalServiceDraft)
        let host = try HostProfile(displayName: "h", address: "h.example")
        let link = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "t")

        // A link with no saved server behind it used to answer nil, and the sheet had nothing to
        // show. That is the state another device's sync leaves when the service arrives and its
        // configuration does not — and the failure the user is given says "Edit the service to set
        // it up, or remove it". Answering nil made Edit a dead end for the one case the sentence
        // is about, leaving the destructive action as the only one that worked.
        let draft = try #require(capability.setupDraft(for: link, host: host),
                                 "Edit offered no way to set up a service the app said to edit")
        #expect(draft is TerminalServiceDraft)
        // A *new* draft rather than an editor over nothing: commit binds to the endpoint it is
        // given, so setting it up fills this link instead of making a second service beside it.
        #expect((draft as? TerminalServiceDraft)?.editing == nil)
    }
}
