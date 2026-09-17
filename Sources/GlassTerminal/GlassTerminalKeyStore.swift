//
//  GlassTerminalKeyStore.swift
//  Glass Power Tools — GlassTerminal
//
//  The shell's key manager, over the manager that actually holds the keys.
//
//  Everything here is a forward. `SettingsManager` owns SSH key material: import with passphrase
//  inspection, Secure Enclave generation, the record that travels with the material (D26 stage 3),
//  and a deletion that is journalled so a crash halfway through unassigning cannot lose a key or
//  leave a server pointing at one that is gone. None of that is re-implemented for a new surface —
//  the surface moved to the library and the lifecycle stayed where it is correct and tested.
//
//  The three sheets come across as views for the same reason: they are already written to rule 15's
//  shape against this manager, and a second copy in the shell would be free to drift from the one
//  the settings page used to show.
//

import SwiftUI
import GlassShell
import GlasSecretStore

@MainActor
final class GlassTerminalKeyStore: GlassKeyStore {
    private let settingsManager: SettingsManager
    private let serverManager: ServerManager

    init(settingsManager: SettingsManager, serverManager: ServerManager) {
        self.settingsManager = settingsManager
        self.serverManager = serverManager
    }

    /// Read from `@Observable` storage, so the panel redraws when a key is added, renamed or
    /// deleted without anything having to tell it.
    var keys: [StoredSSHKey] { settingsManager.sshKeys }

    func loadIfNeeded() {
        settingsManager.loadPersistentStateIfNeeded()
        serverManager.loadServersIfNeeded()
    }

    func publicKey(for keyID: UUID) throws -> String {
        try settingsManager.openSSHPublicKey(for: keyID)
    }

    /// Unassigns the key from every saved server that referenced it, in the same transaction that
    /// removes it — `SettingsManager.deleteSSHKey` rolls both back together if either fails.
    func delete(_ keyID: UUID) async throws {
        try await settingsManager.deleteSSHKey(keyID, serverManager: serverManager)
    }

    func importKeySheet() -> AnyView {
        AnyView(AddSSHKeyView().environment(settingsManager))
    }

    func generateKeySheet() -> AnyView {
        AnyView(GenerateSecureEnclaveSSHKeyView().environment(settingsManager))
    }

    func renameSheet(for key: StoredSSHKey) -> AnyView {
        AnyView(RenameSSHKeyView(key: key).environment(settingsManager))
    }
}

public extension GlassTerminalRuntime {
    /// The shell's view of this capability's SSH keys, for `GlassShellModel.attachKeyStore(_:)`.
    ///
    /// A method on the runtime rather than access widened to its managers: the composition root is
    /// the only caller, and rule 32 is the scar from reaching into `sessionManager` instead.
    func keyStore() -> any GlassKeyStore {
        GlassTerminalKeyStore(settingsManager: settingsManager,
                              serverManager: sessionManager.serverManager)
    }
}
