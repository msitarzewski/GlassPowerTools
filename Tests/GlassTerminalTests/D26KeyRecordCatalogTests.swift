//
//  D26KeyRecordCatalogTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  D26 stage 3: a key's record lives in the Keychain beside its material, so it travels wherever
//  that material may travel and nowhere it may not.
//
//  What is pinned here is the **routing decision**, not the Keychain round-trip: the production
//  configuration carries a real access group and an unsigned test binary cannot write to it, which
//  is why every other Keychain test builds its own. The round-trip itself is covered against a test
//  configuration in `GlasSecretStoreTests/SSHKeyRecordStoreTests`.
//
//  The decision is the rule anyway. A record for a Secure Enclave key that reached the synchronized
//  store would name, on another device, a key guaranteed to fail there.
//

import Testing
import Foundation
import GlasSecretStore
@testable import GlassTerminal

@MainActor
@Suite("Key records are routed like the material they name (D26)")
struct D26KeyRecordCatalogTests {

    private func key(_ name: String, kind: SSHKeyStorageKind) -> StoredSSHKey {
        StoredSSHKey(name: name, algorithm: "ssh-ed25519", storageKind: kind)
    }

    @Test func aSecureEnclaveRecordIsRoutedToTheDeviceBoundStore() {
        let destination = KeychainManager.recordDestination(for: key("hardware", kind: .secureEnclave))
        #expect(destination.mobilityPolicy != .iCloudKeychain,
                "a hardware key's record would have synchronized to devices that cannot use it")
    }

    @Test func anImportedRecordIsRoutedToTheSynchronizedStore() {
        let destination = KeychainManager.recordDestination(for: key("portable", kind: .imported))
        #expect(destination.mobilityPolicy == .iCloudKeychain,
                "a portable key's record must travel with the material it names")
    }

    /// `legacy` predates the distinction and must be treated as portable, not stranded on one
    /// device by a default that happens to be safe-looking.
    @Test func aLegacyRecordIsTreatedAsPortable() {
        let destination = KeychainManager.recordDestination(for: key("old", kind: .legacy))
        #expect(destination.mobilityPolicy == .iCloudKeychain)
    }

    /// The record service has to be eligible, or every write to it fails closed at the mobility
    /// check rather than at anything the caller can see.
    @Test func theRecordServiceIsEligibleToSynchronize() {
        #expect(KeychainManager.config.synchronizableServices.contains(
            KeychainManager.config.sshKeysRecordService))
    }
}
