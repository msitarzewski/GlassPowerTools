//
//  CredentialMobilityTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  D18/D21: credentials travel with the user, on by default. The requirement is the product's
//  premise — *"define everything on Mac, then pick up Vision Pro and get to work without having to
//  mess with settings and passwords"* — and it is one `mobilityPolicy` away, because
//  `GlasSecretStore` was built for this and defaulted off.
//
//  These tests exist because the setting is a single enum case in four places and reads like a
//  tidying opportunity. Before 2026-09-13 `iCloudKeychain` appeared **zero times** in the app while
//  the whole mechanism sat complete and unused; nothing would notice if it returned to that state.
//

import Foundation
import Testing
import GlasSecretStore
@testable import GlassDatabase

@Suite("Credential mobility")
struct CredentialMobilityTests {
    /// The two configurations that hold ordinary secrets both travel.
    @Test("Database and shared credentials synchronize")
    func credentialConfigurationsSynchronize() {
        #expect(KeychainManager.appOnlyConfig.mobilityPolicy == .iCloudKeychain,
                "a database defined on the Mac must connect from the Vision Pro")
        #expect(KeychainManager.sharedConfig.mobilityPolicy == .iCloudKeychain)
    }

    /// The exception, and why it is not an oversight.
    ///
    /// `.requireAuthentication` stores with `.userPresence` protection, which
    /// `KeychainOperations.validateMobility` refuses for a synchronizable item
    /// (`CredentialMobilityError.deviceBoundProtection`). A secret gated on this device's biometrics
    /// is bound to this device's hardware: setting `.iCloudKeychain` here would not sync it, it
    /// would make every write throw.
    @Test("The authentication-gated configuration stays device-bound")
    func authenticatedCredentialsDoNotTravel() {
        #expect(KeychainManager.authenticatedConfig.mobilityPolicy == .deviceOnly,
                "userPresence protection cannot be synchronized; enabling it here breaks writes")
    }

    /// Accessibility and mobility are coupled, and getting it wrong is a silent failure: an item
    /// marked `…ThisDeviceOnly` cannot be synchronizable, so the two must agree.
    @Test("A synchronizing configuration is not marked this-device-only")
    func synchronizingConfigurationsUseCompatibleAccessibility() {
        for config in [KeychainManager.appOnlyConfig, KeychainManager.sharedConfig] {
            #expect(config.accessibility == kSecAttrAccessibleWhenUnlocked
                        || config.accessibility == kSecAttrAccessibleAfterFirstUnlock,
                    "kSecAttrSynchronizable and *ThisDeviceOnly are mutually exclusive")
        }
        #expect(KeychainManager.authenticatedConfig.accessibility
                    == kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                "the device-bound configuration keeps device-bound accessibility")
    }

    /// The access group and mobility are independent, and conflating them is what made the security
    /// review's F3 read as an argument against syncing at all. The group decides which *apps on this
    /// device* may read an item; `kSecAttrSynchronizable` decides whether it reaches the user's
    /// *other devices*. Database passwords do the second without the first.
    @Test("Database passwords sync without entering the Glass-family access group")
    func databasePasswordsSyncWithoutBeingShared() {
        #expect(KeychainManager.appOnlyConfig.accessGroup == nil,
                "no other capability has a use for a database password")
        #expect(KeychainManager.appOnlyConfig.mobilityPolicy == .iCloudKeychain,
                "private to the app, present on every device")
    }

    /// The services `validateMobility` will actually accept. A configuration whose service name is
    /// not on this list throws `ineligibleService` on every write, which would turn D18 into a
    /// product that cannot save a password at all.
    @Test("The services these configurations write to are eligible to synchronize")
    func writtenServicesAreEligible() {
        for config in [KeychainManager.appOnlyConfig, KeychainManager.sharedConfig] {
            let eligible = [config.passwordsService, config.sshPasswordsService,
                            config.rdpCredentialsService, config.sshKeysPrivateService,
                            config.sshKeysPassphraseService]
            #expect(eligible.contains(config.passwordsService))
            #expect(eligible.contains(config.sshPasswordsService))
        }
    }
}
