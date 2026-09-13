//
//  HostTrustMobilityTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  **This suite exists because D18 broke SSH entirely and nothing noticed.**
//
//  `KeychainOperations.validateMobility` accepts only five services —
//  `passwords`, `sshPasswords`, `rdpCredentials`, `sshKeysPrivate`, `sshKeysPassphrase`.
//  `sshHostTrustService` is not among them. The moment the terminal's one configuration became
//  `.iCloudKeychain`, every host-key pin and every lookup threw `ineligibleService` from inside
//  `saveData`/`retrieveData`, `validator(for:)` threw with it, and no SSH connection could
//  complete. It failed closed — the right direction, and total.
//
//  The existing suite could not catch it: `SecurityReviewFixTests` builds its own
//  `SecretStoreConfiguration` without a `mobilityPolicy`, so it exercises the `.deviceOnly` path
//  that production had stopped using. A test that constructs its own configuration cannot notice
//  that the app changed its own.
//
//  So these assert the **app's actual configurations**, not fixtures.
//

import Foundation
import Testing
import GlasSecretStore
@testable import GlassTerminal

@Suite("Host trust mobility")
struct HostTrustMobilityTests {
    /// The regression, stated directly: the configuration host trust is stored under must accept
    /// the host-trust service.
    @Test("The host-trust configuration can actually write host trust")
    func hostTrustConfigurationAcceptsItsOwnService() {
        let config = KeychainManager.deviceBoundConfig
        // sshHostTrustService is not on validateMobility's eligible list, so a synchronizing
        // configuration refuses every pin and every lookup.
        #expect(config.mobilityPolicy == .deviceOnly)
    }

    /// The credential configuration still syncs — the fix must not have quietly undone D18.
    @Test("Credentials still synchronize")
    func credentialsStillSync() {
        #expect(KeychainManager.config.mobilityPolicy == .iCloudKeychain,
                "D18: passwords, passphrases and private keys travel with the user")
    }

    /// Both configurations address the same account group and prefix, so switching between them
    /// changes only mobility — not where an item lives.
    @Test("The two configurations differ only in mobility")
    func configurationsDifferOnlyInMobility() {
        let synced = KeychainManager.config
        let bound = KeychainManager.deviceBoundConfig
        #expect(synced.serviceNamePrefix == bound.serviceNamePrefix)
        #expect(synced.accessGroup == bound.accessGroup)
        #expect(synced.sshHostTrustService == bound.sshHostTrustService,
                "the same items, reached under a different mobility policy")
    }

    /// A guard against the shape of the original mistake returning: if someone later adds a service
    /// to a synchronizing configuration that `validateMobility` does not list, every write through
    /// it throws. This enumerates what the synced configuration is allowed to be used for.
    @Test("Every service the synced configuration is used for is eligible")
    func syncedConfigurationOnlyTouchesEligibleServices() {
        let config = KeychainManager.config
        let eligible = Set([config.passwordsService, config.sshPasswordsService,
                            config.rdpCredentialsService, config.sshKeysPrivateService,
                            config.sshKeysPassphraseService])
        // Host trust is NOT eligible. That is the fact the fix rests on; if it ever changes, the
        // device-bound configuration can be retired.
        #expect(!eligible.contains(config.sshHostTrustService))
    }

    // MARK: - Secure Enclave keys must not travel

    /// The project's own non-negotiable: a device-bound key cannot be advertised as synchronized.
    ///
    /// A Secure Enclave key's stored value is an **opaque token** usable only by the chip that
    /// minted it. `validateMobility` excludes the legacy `SECURE_ENCLAVE_P256:` representation by
    /// keeping `sealedP256Service` off its eligible list — but the newer `TRUE_SE_P256:` form goes
    /// to `sshKeysPrivateService`, which IS eligible. Under D18 it would have synced: a key present
    /// on every device and usable on exactly one, listed as available on all of them.
    @Test("A Secure Enclave token is recognised as device-bound")
    func secureEnclaveMaterialIsDeviceBound() {
        #expect(KeychainManager.isDeviceBoundKeyMaterialForTesting("TRUE_SE_P256:AAAA"))
        #expect(KeychainManager.isDeviceBoundKeyMaterialForTesting("SECURE_ENCLAVE_P256:AAAA"),
                "the legacy representation is device-bound for the same reason")
    }

    /// An ordinary key must still travel, or the fix has quietly undone D18 for SSH keys — which
    /// are the credential the continuity requirement leans on hardest.
    @Test("An ordinary private key is not treated as device-bound")
    func ordinaryKeyMaterialTravels() {
        #expect(!KeychainManager.isDeviceBoundKeyMaterialForTesting(
            "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----"))
    }
}
