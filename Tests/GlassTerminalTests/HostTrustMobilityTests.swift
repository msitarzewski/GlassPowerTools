//
//  HostTrustMobilityTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  **This suite exists because D18 broke SSH entirely and nothing noticed, and then the fix for
//  that broke the trust prompt and nothing noticed either.**
//
//  First failure: `KeychainOperations.validateMobility` accepted five services and
//  `sshHostTrustService` was not among them, so the moment the terminal's one configuration became
//  `.iCloudKeychain`, every host-key pin and every lookup threw `ineligibleService` and no SSH
//  connection could complete. It failed closed — the right direction, and total.
//
//  Second failure: host trust was moved to a separate device-bound configuration, which fixed the
//  transport's pinning and left `KeychainManager.savePinnedHostKey`, `replaceHostKey`,
//  `allPinnedHostKeys` and `trustedHostKeyBase64Set` on the synchronizing one. Those are the
//  *trust prompt's* destination. Accepting a fingerprint still threw, and a pin written on connect
//  lived in a different Keychain item from the one the prompt would have written. Nothing failed
//  because nobody had driven the prompt.
//
//  D23 settles it: a pinned host key is a public key, it is eligible, and there is exactly one
//  configuration for it.
//
//  These assert the **app's actual configurations**, never a fixture. `SecurityReviewFixTests`
//  builds its own `SecretStoreConfiguration` without a `mobilityPolicy`, so it exercises a path
//  production had stopped using — a test that constructs its own configuration cannot notice that
//  the app changed its own, and that is precisely how the first failure survived a green suite.
//

import Foundation
import Testing
import GlasSecretStore
@testable import GlassTerminal

@Suite("Host trust mobility")
struct HostTrustMobilityTests {
    /// The first regression, stated directly: the configuration host trust is stored under must
    /// accept the host-trust service, or every pin and every lookup throws from inside
    /// `saveData`/`retrieveData` and SSH stops working altogether.
    @Test("The host-trust configuration can actually write host trust")
    func hostTrustConfigurationAcceptsItsOwnService() {
        let config = KeychainManager.hostTrustConfig
        #expect(config.synchronizableServices.contains(config.sshHostTrustService),
                "ineligible means validateMobility throws on every pin and every lookup")
    }

    /// The second regression: the transport pinned under one configuration while this type's own
    /// methods — the ones the trust prompt calls — used another. A synchronizable Keychain item and
    /// a device-only one with the same account are **different items**, so the two paths could not
    /// see each other's pins even where neither threw. Both now read `hostTrustConfig`; what this
    /// pins is that it stays the credentials' configuration, since moving it would leave every pin
    /// already made under the old one unread.
    @Test("Host trust is stored under the credentials' configuration")
    func oneConfigurationForBothTrustPaths() {
        let promptDestination = KeychainManager.hostTrustConfig
        let transportDestination = KeychainManager.config
        #expect(promptDestination.mobilityPolicy == transportDestination.mobilityPolicy)
        #expect(promptDestination.sshHostTrustService == transportDestination.sshHostTrustService)
        #expect(promptDestination.accessGroup == transportDestination.accessGroup)
    }

    /// D23 in one line: trusting a machine on the Mac trusts it on the Vision Pro. Without this the
    /// continuity requirement ends at "and then re-approve every host on the second device".
    @Test("Host trust travels with the user")
    func hostTrustSynchronizes() {
        #expect(KeychainManager.hostTrustConfig.mobilityPolicy == .iCloudKeychain)
    }

    /// The credential configuration still syncs — none of this may quietly undo D18.
    @Test("Credentials still synchronize")
    func credentialsStillSync() {
        #expect(KeychainManager.config.mobilityPolicy == .iCloudKeychain,
                "D18: passwords, passphrases and private keys travel with the user")
    }

    /// Both configurations address the same account group and prefix, so the only thing that
    /// differs is mobility — not where an item lives.
    @Test("The two configurations differ only in mobility")
    func configurationsDifferOnlyInMobility() {
        let synced = KeychainManager.config
        let bound = KeychainManager.deviceBoundConfig
        #expect(synced.serviceNamePrefix == bound.serviceNamePrefix)
        #expect(synced.accessGroup == bound.accessGroup)
        #expect(synced.sshKeysPrivateService == bound.sshKeysPrivateService,
                "the same items, reached under a different mobility policy")
        #expect(bound.mobilityPolicy == .deviceOnly)
    }

    /// Every service the app writes through its synchronizing configuration must be eligible. This
    /// is the guard against the original mistake's *shape* returning: add a service to a syncing
    /// configuration that `validateMobility` does not list, and every write through it throws.
    @Test("Every service the synced configuration is used for is eligible")
    func syncedConfigurationOnlyTouchesEligibleServices() {
        let config = KeychainManager.config
        let used = [config.passwordsService, config.sshPasswordsService,
                    config.sshKeysPrivateService, config.sshKeysPassphraseService,
                    config.sshHostTrustService]
        for service in used {
            #expect(config.synchronizableServices.contains(service),
                    "\(service) is written under the synchronizing configuration")
        }
    }

    // MARK: - Secure Enclave keys must not travel

    /// The project's own non-negotiable: a device-bound key cannot be advertised as synchronized.
    ///
    /// A Secure Enclave key's stored value is an **opaque token** usable only by the chip that
    /// minted it. `validateMobility` excludes the legacy `SECURE_ENCLAVE_P256:` representation by
    /// keeping `sealedP256Service` off the eligible set — but the newer `TRUE_SE_P256:` form goes
    /// to `sshKeysPrivateService`, which IS eligible. Under D18 it would have synced: a key present
    /// on every device and usable on exactly one, listed as available on all of them.
    @Test("A Secure Enclave token is recognised as device-bound")
    func secureEnclaveMaterialIsDeviceBound() {
        #expect(KeychainManager.isDeviceBoundKeyMaterialForTesting("TRUE_SE_P256:AAAA"))
        #expect(KeychainManager.isDeviceBoundKeyMaterialForTesting("SECURE_ENCLAVE_P256:AAAA"),
                "the legacy representation is device-bound for the same reason")
    }

    /// The sealed services stay off the eligible set. Widening `synchronizableServices` is now a
    /// one-line edit, so the thing it must never swallow is stated as a test rather than a comment.
    @Test("Secure Enclave services are never eligible for synchronization")
    func sealedServicesAreNeverEligible() {
        let config = KeychainManager.config
        #expect(!config.synchronizableServices.contains(config.sealedP256Service))
        #expect(!config.synchronizableServices.contains(config.sealedP256TagService))
    }

    /// An ordinary key must still travel, or the fix has quietly undone D18 for SSH keys — the
    /// credential the continuity requirement leans on hardest.
    @Test("An ordinary private key is not treated as device-bound")
    func ordinaryKeyMaterialTravels() {
        #expect(!KeychainManager.isDeviceBoundKeyMaterialForTesting(
            "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----"))
    }
}
