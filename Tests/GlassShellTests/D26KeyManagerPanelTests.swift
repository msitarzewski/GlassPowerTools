//
//  D26KeyManagerPanelTests.swift
//  Glass Power Tools — GlassShellTests
//
//  D26 stage 4: the key manager, and the sentence it exists to be able to say.
//
//  The panel is a read over `services(usingKey:)` and `usageCount(ofKey:)`, which stage 4's model
//  layer already proved. What is new, and what these tests are about, is the **join**: that the
//  library actually offers the panel when something holds keys, and that the delete confirmation
//  names the services a real catalog says will be left without one. Testing the sentence alone
//  would leave exactly the gap this project keeps finding — every part present, nothing connected.
//

import Foundation
import Testing
import SwiftUI
import GlassConnectionKit
import GlassLayers
import GlasSecretStore
@testable import GlassShell

/// Holds keys and nothing else. The sheets are never presented here; the material lifecycle lives
/// in the capability that owns it, and is tested there.
@MainActor
private final class StubKeyStore: GlassKeyStore {
    var keys: [StoredSSHKey]
    private(set) var deleted: [UUID] = []
    var loadCount = 0

    init(keys: [StoredSSHKey] = []) { self.keys = keys }

    func loadIfNeeded() { loadCount += 1 }
    func publicKey(for keyID: UUID) throws -> String {
        OpenSSHPublicKeyLineFixture.line
    }
    func delete(_ keyID: UUID) async throws {
        deleted.append(keyID)
        keys.removeAll { $0.id == keyID }
    }
    func importKeySheet() -> AnyView { AnyView(EmptyView()) }
    func generateKeySheet() -> AnyView { AnyView(EmptyView()) }
    func renameSheet(for key: StoredSSHKey) -> AnyView { AnyView(EmptyView()) }
}

private enum OpenSSHPublicKeyLineFixture {
    /// A throwaway key generated for the test suite; its fingerprint is checked against
    /// `ssh-keygen -lf` in `OpenSSHPublicKeyLineTests`.
    static let line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPul03MQqt3wecXgHLPsgIoyPud7YN/SERCWtX/ckfdu glass-test"
    static let fingerprint = "SHA256:dwZSTpODvDloFr6s7D6NOzR/+JhKxFaG6jgQCzW9bKk"
}

@MainActor
private final class CredentialCapability: GlassCapability {
    let kind: HostServiceKind = .ssh
    let displayName = "Terminal"
    let symbolName = "terminal"
    var credentials: [EndpointID: GlassServiceCredential] = [:]

    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.failed("not used")) }
    func credential(for service: HostServiceLink, host: HostProfile) -> GlassServiceCredential {
        credentials[service.endpointID] ?? .ownedByService
    }
}

@MainActor
@Suite("The key manager panel (D26 stage 4)")
struct D26KeyManagerPanelTests {

    private func makeShell() throws -> (GlassShellModel, CredentialCapability, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D26KeyPanel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        let capability = CredentialCapability()
        model.registry.register(capability)
        return (model, capability, root)
    }

    private func key(_ name: String, storage: SSHKeyStorageKind = .imported) -> StoredSSHKey {
        StoredSSHKey(name: name, algorithm: "ssh-ed25519", storageKind: storage, algorithmKind: .ed25519)
    }

    // MARK: The panel reaches the library at all

    /// With nothing holding keys there is no manager, and the sidebar says nothing rather than
    /// offering a row that can only be empty.
    @Test func withoutAKeyStoreThereIsNoPanel() throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.libraryPanels().isEmpty)
    }

    @Test func attachingAKeyStoreOffersThePanelWithItsCount() throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        model.attachKeyStore(StubKeyStore(keys: [key("work"), key("home")]))

        let panels = model.libraryPanels()
        #expect(panels.count == 1)
        let panel = try #require(panels.first)
        #expect(panel.id == "ssh-keys")
        #expect(panel.sectionTitle == "Keys")
        #expect(panel.count == 2)
    }

    // MARK: What deleting will take with it

    /// The user's own scenario: one key signing in to two machines. Deleting it must name both.
    @Test func deletingNamesEveryServiceTheCatalogSaysUsesTheKey() async throws {
        let (model, capability, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let stored = key("shared")
        let onOscar = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                  address: "oscar.example", serviceName: "Terminal")
        let onJuliet = try await model.adoptService(kind: .ssh, hostName: "juliet",
                                                      address: "juliet.example", serviceName: "Terminal")
        capability.credentials = [onOscar: .sharedKey(id: stored.id, deviceBound: false),
                                  onJuliet: .sharedKey(id: stored.id, deviceBound: false)]
        model.attachKeyStore(StubKeyStore(keys: [stored]))

        let panel = GlassKeyManagerPanel(presentation: .detail, model: model, panel: model.keyPanel)
        let warning = panel.deletionWarning(for: stored)

        #expect(warning.contains("'shared'"))
        #expect(warning.contains("2 services will be left without a key"))
        #expect(warning.contains("Terminal on oscar"))
        #expect(warning.contains("Terminal on juliet"))
    }

    /// A key nothing uses says so plainly — the case where deleting is safe is worth stating, or a
    /// user hesitates over every key.
    @Test func deletingAnUnusedKeySaysNoServiceUsesIt() async throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()
        let stored = key("spare")
        model.attachKeyStore(StubKeyStore(keys: [stored]))

        let panel = GlassKeyManagerPanel(presentation: .detail, model: model, panel: model.keyPanel)
        let warning = panel.deletionWarning(for: stored)
        #expect(warning.contains("No service uses it."))
        #expect(!warning.contains("will be left without a key"))
    }

    /// A service this build cannot read may be using the key, and the dialog must not promise a
    /// smaller consequence than it can actually deliver.
    @Test func unreadableServicesAreCountedInTheWarning() async throws {
        let (model, capability, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        let stored = key("shared")
        let readable = try await model.adoptService(kind: .ssh, hostName: "oscar",
                                                    address: "oscar.example", serviceName: "Terminal")
        let opaque = try await model.adoptService(kind: .ssh, hostName: "newer",
                                                  address: "newer.example", serviceName: "Terminal")
        capability.credentials = [readable: .sharedKey(id: stored.id, deviceBound: false),
                                  opaque: .unreadable]
        model.attachKeyStore(StubKeyStore(keys: [stored]))

        let panel = GlassKeyManagerPanel(presentation: .detail, model: model, panel: model.keyPanel)
        let warning = panel.deletionWarning(for: stored)
        #expect(warning.contains("1 service will be left without a key"))
        #expect(warning.contains("1 service could not be read by this build"))
    }

    /// Long lists stop being readable; the count has to carry what the names cannot.
    @Test func manyUsersAreSummarisedRatherThanListedInFull() {
        let uses = (1...7).map { (host: "machine\($0)", service: "Terminal") }
        let text = GlassKeyDeletionSummary.text(keyName: "fleet", uses: uses, unreadable: 0)
        #expect(text.contains("7 services will be left without a key"))
        #expect(text.contains("Terminal on machine4"))
        #expect(!text.contains("Terminal on machine5"))
        #expect(text.contains("and 3 more"))
    }

    // MARK: Small things the panel shows

    /// The fingerprint the panel displays is OpenSSH's, derived from the public key the store
    /// supplies — not a second implementation with its own idea of the format.
    @Test func theFingerprintComesFromThePublicKey() throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        let stored = key("work")
        let store = StubKeyStore(keys: [stored])
        model.attachKeyStore(store)
        #expect(store.fingerprint(for: stored.id) == OpenSSHPublicKeyLineFixture.fingerprint)
    }

    /// Secure Enclave material cannot be copied, so its key is this device's alone. Every other
    /// kind travels with the account.
    @Test func mobilityFollowsWhetherTheMaterialCanLeaveTheDevice() {
        #expect(GlassKeyMobility(key("imported")) == .synchronized)
        #expect(GlassKeyMobility(key("legacy", storage: .legacy)) == .synchronized)
        #expect(GlassKeyMobility(key("hardware", storage: .secureEnclave)) == .thisDeviceOnly)
    }

    @Test func exportedFilenamesAreTheUsersNameMadeSafe() {
        #expect(GlassKeyManagerPanel.exportFilename(for: key("oscar key")) == "oscar_key.pub")
        #expect(GlassKeyManagerPanel.exportFilename(for: key("../../etc/passwd")) == "etc_passwd.pub")
        #expect(GlassKeyManagerPanel.exportFilename(for: key("///")) == "ssh_key.pub")
    }
}

extension GlassKeyMobility: Equatable {}
