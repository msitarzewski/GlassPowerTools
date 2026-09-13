//
//  HostTrustSynchronizationTests.swift
//  Glass Power Tools — GlasSecretStoreTests
//
//  **The test nothing had: a pinned host key written and read back through the real Keychain under
//  a synchronizing configuration.**
//
//  Two defects lived in the gap it fills. Enabling D18 made `validateMobility` refuse
//  `sshHostTrustService`, so every pin and every lookup threw and SSH stopped connecting. The fix
//  moved the transport's trust store to a device-bound configuration and left `KeychainManager`'s
//  own methods — the ones the trust *prompt* calls — on the synchronizing one, so accepting a
//  fingerprint still threw and a pin written on connect was a different Keychain item from the one
//  the prompt would have written.
//
//  Neither was visible from below. The real-host integration suite passes an
//  `InMemoryHostTrustStore`, so it proves SSH works and proves nothing about storage.
//  `SecurityReviewFixTests` builds a `SecretStoreHostTrustStore` but only to reject malformed
//  base64 — it never writes. And every other mobility test asserts a configuration's *properties*
//  rather than driving an item through the store.
//
//  These write to the login Keychain under a per-run service prefix and delete what they wrote. They
//  never touch `sh.glas`, so the user's own pins are not involved.
//
//  **They are skipped, not passed, in an unsigned test process — and that fact is the finding.**
//  Measured on this machine: `SecItemAdd` with `kSecAttrSynchronizable: true` returns
//  `errSecMissingEntitlement` (-34018) whether or not the data-protection Keychain is requested,
//  because a synchronizable item needs `com.apple.application-identifier`. Ad-hoc signing the test
//  binary with that entitlement does not help; the kernel kills the process on launch. So no
//  `swift test` run can ever exercise this path, which is precisely how two consecutive defects in
//  it reached a green suite. The signed app can, and the run that proves it end to end is the
//  macOS UI test driving the trust prompt against a real host.
//

import Foundation
import Security
import Testing
@testable import GlasSecretStore

/// Whether this process may write a synchronizable Keychain item at all. Probed once, by writing
/// one — the entitlement cannot be read back from an unsigned process, only observed by its
/// absence. The probe cleans up after itself and never touches an app service name.
enum SynchronizableKeychainAvailability {
    static let isEntitled: Bool = {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.glasspowertools.entitlement-probe",
            kSecAttrAccount as String: UUID().uuidString,
            kSecValueData as String: Data("probe".utf8),
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { SecItemDelete(query as CFDictionary) }
        return status == errSecSuccess || status == errSecDuplicateItem
    }()

    static let reason: Comment = "a synchronizable Keychain item needs com.apple.application-identifier; an unsigned swift-test process cannot write one (errSecMissingEntitlement). Run this inside the signed app."
}

@Suite("Host trust synchronization", .serialized,
       .enabled(if: SynchronizableKeychainAvailability.isEntitled,
                SynchronizableKeychainAvailability.reason))
struct HostTrustSynchronizationTests {
    /// A prefix unique to the run, so a crashed earlier run cannot make a later one pass or fail.
    private static func prefix() -> String {
        "com.glasspowertools.hosttrust-tests.\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func syncingConfiguration(_ prefix: String) -> SecretStoreConfiguration {
        // Data protection on, matching the app: every configuration in Glass Power Tools sets it,
        // and a synchronizable item needs the same entitlement either way (measured — the file
        // Keychain refuses one too), so turning it off would only make this less like production.
        SecretStoreConfiguration(serviceNamePrefix: prefix,
                                 accessGroup: nil,
                                 useDataProtectionKeychain: true,
                                 mobilityPolicy: .iCloudKeychain)
    }

    private func key(host: String = "vm.example", port: Int = 22) -> PinnedSSHHostKey {
        PinnedSSHHostKey(host: host, port: port, algorithm: "ssh-ed25519",
                         publicKeyData: Data([0x01, 0x02, 0x03, 0x04]))
    }

    /// The whole point, in one assertion: a pin survives a write and a read under the configuration
    /// the app actually uses. If `sshHostTrustService` is ever taken off
    /// `synchronizableServices` again, this throws `ineligibleService` on the *save* and says so.
    @Test("A pin round-trips through the Keychain under a synchronizing configuration")
    func pinRoundTripsWhenSynchronizing() throws {
        let config = syncingConfiguration(Self.prefix())
        let pinned = key()
        defer { try? SSHHostTrustKeychainStore.delete(host: pinned.host, port: pinned.port, config: config) }

        try SSHHostTrustKeychainStore.save(pinned, config: config)
        let read = try SSHHostTrustKeychainStore.retrieve(
            host: pinned.host, port: pinned.port,
            algorithm: pinned.algorithm, publicKeyData: pinned.publicKeyData, config: config)
        #expect(read == pinned)
        #expect(SSHHostTrustKeychainStore.contains(host: pinned.host, port: pinned.port, config: config))
    }

    /// The stored item must actually carry `kSecAttrSynchronizable`, or "host trust travels" is a
    /// claim about a property rather than about an item. This reads the attribute back from the
    /// Keychain itself rather than from the configuration that asked for it.
    @Test("The stored item is marked synchronizable")
    func storedItemIsSynchronizable() throws {
        let prefix = Self.prefix()
        let config = syncingConfiguration(prefix)
        let pinned = key(host: "marked.example")
        defer { try? SSHHostTrustKeychainStore.delete(host: pinned.host, port: pinned.port, config: config) }
        try SSHHostTrustKeychainStore.save(pinned, config: config)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: config.sshHostTrustService,
            kSecAttrAccount as String: pinned.storageAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        #expect(status == errSecSuccess)
        let attributes = result as? [String: Any]
        #expect(attributes?[kSecAttrSynchronizable as String] as? Bool == true,
                "a pin that is not marked synchronizable reaches no other device")
    }

    /// Accepting a *changed* fingerprint is the trust prompt's other path, and it does more work
    /// than a save: it supersedes the prior generation and verifies each readback. It has to run
    /// under the same configuration for that verification to find what it just wrote.
    @Test("Accepting a changed fingerprint supersedes the previous pin")
    func replacementSupersedesUnderSynchronization() throws {
        let config = syncingConfiguration(Self.prefix())
        let original = key(host: "rotating.example")
        let rotated = PinnedSSHHostKey(host: original.host, port: original.port,
                                       algorithm: original.algorithm,
                                       publicKeyData: Data([0x09, 0x08, 0x07, 0x06]))
        defer { try? SSHHostTrustKeychainStore.delete(host: original.host, port: original.port, config: config) }

        try SSHHostTrustKeychainStore.save(original, config: config)
        _ = try SSHHostTrustKeychainStore.replace(with: rotated, config: config)

        let authorized = try SSHHostTrustKeychainStore.authorizedRecords(
            host: original.host, port: original.port, config: config)
        #expect(authorized.count == 1)
        #expect(authorized.first?.publicKeyData == rotated.publicKeyData,
                "the accepted key authorizes the endpoint")
        #expect(authorized.first?.generation == 1)
    }

}

/// The negative half, kept outside the gated suite because it needs no entitlement: `validateMobility`
/// refuses Secure Enclave material before anything reaches the Keychain, so this runs everywhere and
/// stops the skipped round-trip above from being read as "mobility is unchecked".
@Suite("Host trust synchronization — refusals")
struct HostTrustSynchronizationRefusalTests {
    private let config = SecretStoreConfiguration(serviceNamePrefix: "com.glasspowertools.hosttrust-tests",
                                                  accessGroup: nil,
                                                  useDataProtectionKeychain: true,
                                                  mobilityPolicy: .iCloudKeychain)

    @Test("Secure Enclave material is still refused under a synchronizing configuration")
    func sealedMaterialStillRefused() {
        #expect(throws: CredentialMobilityError.ineligibleService) {
            try KeychainOperations.validateMobility(config: config, service: config.sealedP256Service)
        }
        #expect(throws: CredentialMobilityError.ineligibleService) {
            try KeychainOperations.validateMobility(config: config, service: config.sealedP256TagService)
        }
    }

    /// D23 at the validator, where the two defects actually lived.
    @Test("Host trust is accepted by the validator")
    func hostTrustIsAccepted() {
        #expect(throws: Never.self) {
            try KeychainOperations.validateMobility(config: config, service: config.sshHostTrustService)
        }
    }

    /// A `.requireAuthentication` secret can never travel, whatever service it names: the item is
    /// stored with user-presence protection, which is device-bound by construction.
    @Test("User presence still refuses mobility for an eligible service")
    func userPresenceStillRefused() {
        #expect(throws: CredentialMobilityError.deviceBoundProtection) {
            try KeychainOperations.validateMobility(config: config,
                                                    service: config.sshHostTrustService,
                                                    policy: .userPresence)
        }
    }
}
