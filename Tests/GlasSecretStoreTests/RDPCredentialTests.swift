import Foundation
import Security
import Testing
@testable import GlasSecretStore

private final class RDPStoreProbe {
    var items: [String: Data] = [:]
    var readFailure: Error?
    var addCount = 0
    var allowsUI: [Bool] = []
    var addedThenUnavailable = false
    private func key(_ account: String, _ service: String, _ config: SecretStoreConfiguration) -> String {
        "\(config.mobilityPolicy.rawValue)|\(service)|\(account)"
    }
    var operations: RDPCredentialOperations {
        RDPCredentialOperations(
            read: { account, service, config, _, allowUI in
                self.allowsUI.append(allowUI)
                if let error = self.readFailure { throw error }
                if self.addedThenUnavailable && self.addCount > 0 { throw SecretStoreError.queryFailed(status: errSecInteractionNotAllowed) }
                guard let data = self.items[self.key(account, service, config)] else { throw SecretStoreError.notFound }
                return data
            },
            save: { data, account, service, config, _ in self.items[self.key(account, service, config)] = data },
            add: { data, account, service, config, _ in
                self.addCount += 1
                let key = self.key(account, service, config)
                guard self.items[key] == nil else { return false }
                self.items[key] = data
                return true
            },
            delete: { account, service, config in self.items.removeValue(forKey: self.key(account, service, config)) }
        )
    }
}

@Suite("RDP credential policy and migration")
struct RDPCredentialTests {
    private let local = SecretStoreConfiguration(serviceNamePrefix: "test.glassdt")
    private let mobile = SecretStoreConfiguration(serviceNamePrefix: "test.glassdt", mobilityPolicy: .iCloudKeychain)

    @Test("Defaults preserve existing SSH and database device-only policy")
    func existingDefaults() {
        #expect(local.mobilityPolicy == .deviceOnly)
        #expect(local.accessibility == kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        #expect(local.passwordsService == "test.glassdt.passwords")
        #expect(local.sshPasswordsService == "test.glassdt.sshpasswords")
        #expect(mobile.accessibility == kSecAttrAccessibleWhenUnlocked)
    }

    @Test("RDP local Keychain save, retrieve and delete use the shared package")
    func liveLocalKeychainRoundTrip() throws {
        let config = SecretStoreConfiguration(serviceNamePrefix: "test.glassdt.rdp.\(UUID())")
        let id = UUID()
        defer { try? RDPCredentialStore.delete(for: id, config: config) }
        try RDPCredentialStore.save(RDPCredential(username: "fixture-user", domain: "FIXTURE", password: "fixture-only"),
                                    for: id, config: config)
        let credential = try RDPCredentialStore.retrieve(for: id, config: config)
        #expect(credential.username == "fixture-user")
        #expect(credential.domain == "FIXTURE")
        #expect(credential.password.toUTF8String() == "fixture-only")
        try RDPCredentialStore.delete(for: id, config: config)
        #expect(RDPCredentialStore.availability(for: id, config: config) == .missing)
    }

    @Test("Mobile imported-key deletion never touches device-bound artifacts or hardware")
    func mobileImportedDeletion() throws {
        let id = UUID()
        var touched: [String] = []
        var hardwareCalls = 0
        let operations = SSHKeyDeletionOperations(
            read: { _, service, _ in touched.append(service); return nil },
            delete: { _, service, _ in touched.append(service) },
            addIfAbsent: { _, _, _, _ in false },
            secureEnclaveKeyExists: { _ in hardwareCalls += 1; return true },
            deleteSecureEnclaveKey: { _ in hardwareCalls += 1 }
        )
        try SSHKeyKeychainStore.delete(for: id, config: mobile, operations: operations)
        #expect(Set(touched) == Set([mobile.sshKeysPrivateService, mobile.sshKeysPassphraseService]))
        #expect(hardwareCalls == 0)
    }

    @Test("Mobility selection scopes Keychain queries independently of app sharing")
    func queryScope() {
        let id = UUID()
        let shared = SecretStoreConfiguration(accessGroup: "TEAMID.sh.glas.shared")
        let a = KeychainOperations.baseQuery(account: id.uuidString, service: local.rdpCredentialsService, config: local)
        let b = KeychainOperations.baseQuery(account: id.uuidString, service: mobile.rdpCredentialsService, config: mobile)
        let c = KeychainOperations.baseQuery(account: id.uuidString, service: shared.rdpCredentialsService, config: shared)
        #expect(a[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(b[kSecAttrSynchronizable as String] as? Bool == true)
        #expect(b[kSecAttrAccessGroup as String] == nil)
        #expect(c[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(c[kSecAttrAccessGroup as String] as? String == shared.accessGroup)
    }

    @Test("User presence, device-only accessibility and Secure Enclave refuse mobility")
    func ineligiblePolicies() throws {
        #expect(throws: CredentialMobilityError.deviceBoundProtection) {
            try KeychainOperations.validateMobility(config: mobile, service: mobile.rdpCredentialsService, policy: .userPresence)
        }
        let bad = SecretStoreConfiguration(accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                           mobilityPolicy: .iCloudKeychain)
        #expect(throws: CredentialMobilityError.incompatibleAccessibility) {
            try KeychainOperations.validateMobility(config: bad, service: bad.rdpCredentialsService)
        }
        // Secure Enclave material stays ineligible and always will: the stored value is an opaque
        // token usable only by the chip that minted it, so a copy on a second device would be a key
        // listed as available and guaranteed to fail.
        for service in [mobile.sealedP256Service, mobile.sealedP256TagService] {
            #expect(throws: CredentialMobilityError.ineligibleService) {
                try KeychainOperations.validateMobility(config: mobile, service: service)
            }
        }
        // D23, 2026-09-13: host trust used to be refused here alongside them, and that was wrong
        // for a different reason than it looked. A pinned host key is a *public* key — the
        // fingerprint `ssh-keygen` prints — so there is nothing to protect by keeping it local, and
        // refusing it meant a machine trusted on the Mac had to be re-approved on every other
        // device. It is eligible now.
        #expect(throws: Never.self) {
            try KeychainOperations.validateMobility(config: mobile, service: mobile.sshHostTrustService)
        }
    }

    @Test("RDP username, domain and password round-trip in one independent record")
    func roundTrip() throws {
        let probe = RDPStoreProbe(), id = UUID()
        let credential = RDPCredential(username: " user ", domain: " EXAMPLE ", password: "test-fixture-only")
        try RDPCredentialStore.save(credential, for: id, config: local, operations: probe.operations)
        let read = try RDPCredentialStore.retrieve(for: id, config: local, operations: probe.operations)
        #expect(read.username == "user")
        #expect(read.domain == "EXAMPLE")
        #expect(read.password.toData() == credential.password.toData())
        #expect(probe.items.count == 1)
        #expect(probe.items.keys.allSatisfy { $0.contains(".rdp.credentials|rdp:") })
        #expect(throws: SecretStoreError.self) {
            try RDPCredentialStore.retrieve(for: UUID(), config: local, operations: probe.operations)
        }
    }

    @Test("Availability distinguishes missing, locked and authentication without UI")
    func availability() throws {
        let probe = RDPStoreProbe(), id = UUID()
        #expect(RDPCredentialStore.availability(for: id, config: local, operations: probe.operations) == .missing)
        probe.readFailure = SecretStoreError.queryFailed(status: errSecInteractionNotAllowed)
        #expect(RDPCredentialStore.availability(for: id, config: local, operations: probe.operations) == .locked)
        #expect(RDPCredentialStore.availability(for: id, config: local, policy: .userPresence, operations: probe.operations) == .authenticationRequired)
        probe.readFailure = SecretStoreError.queryFailed(status: errSecAuthFailed)
        #expect(RDPCredentialStore.availability(for: id, config: local, operations: probe.operations) == .authenticationRequired)
        #expect(probe.allowsUI.allSatisfy { !$0 })
    }

    @Test("No fallback reads between device and cloud records")
    func noSilentFallback() throws {
        let probe = RDPStoreProbe(), id = UUID()
        try RDPCredentialStore.save(RDPCredential(username: "user", password: "fixture"), for: id,
                                    config: local, operations: probe.operations)
        #expect(RDPCredentialStore.availability(for: id, config: mobile, operations: probe.operations) == .missing)
    }

    @Test("Forward migration verifies destination and retains source for interrupted metadata commits")
    func migration() throws {
        let probe = RDPStoreProbe(), id = UUID()
        try RDPCredentialStore.save(RDPCredential(username: "user", password: "fixture"), for: id,
                                    config: local, operations: probe.operations)
        #expect(try RDPCredentialStore.prepareMobilityMigration(for: id, from: local, to: mobile,
                                                               operations: probe.operations) == .copiedSourceRetained)
        #expect(probe.items.count == 2)
        #expect(try RDPCredentialStore.prepareMobilityMigration(for: id, from: local, to: mobile,
                                                               operations: probe.operations) == .matchingDestinationSourceRetained)
        #expect(probe.items.count == 2)
    }

    @Test("Conflicting concurrent destination is not overwritten")
    func conflict() throws {
        let probe = RDPStoreProbe(), id = UUID()
        try RDPCredentialStore.save(RDPCredential(username: "user", password: "local-fixture"), for: id,
                                    config: local, operations: probe.operations)
        try RDPCredentialStore.save(RDPCredential(username: "user", password: "cloud-fixture"), for: id,
                                    config: mobile, operations: probe.operations)
        let before = probe.items
        #expect(throws: CredentialMobilityError.conflictingDestination) {
            try RDPCredentialStore.prepareMobilityMigration(for: id, from: local, to: mobile, operations: probe.operations)
        }
        #expect(probe.items == before)
    }

    @Test("Locked or missing migration source performs no writes")
    func missingMigration() {
        let probe = RDPStoreProbe(), id = UUID()
        #expect(throws: SecretStoreError.self) {
            try RDPCredentialStore.prepareMobilityMigration(for: id, from: local, to: mobile, operations: probe.operations)
        }
        probe.readFailure = SecretStoreError.queryFailed(status: errSecInteractionNotAllowed)
        #expect(throws: SecretStoreError.self) {
            try RDPCredentialStore.prepareMobilityMigration(for: id, from: local, to: mobile, operations: probe.operations)
        }
        #expect(probe.addCount == 0)
        #expect(probe.items.isEmpty)
    }

    @Test("Failure after destination add preserves source")
    func interruptionAfterAdd() throws {
        let probe = RDPStoreProbe(), id = UUID()
        try RDPCredentialStore.save(RDPCredential(username: "user", password: "fixture"), for: id,
                                    config: local, operations: probe.operations)
        let source = probe.items
        probe.addedThenUnavailable = true
        #expect(throws: SecretStoreError.self) {
            try RDPCredentialStore.prepareMobilityMigration(for: id, from: local, to: mobile, operations: probe.operations)
        }
        for (key, value) in source { #expect(probe.items[key] == value) }
    }

    @Test("Protected and standard RDP storage never silently change access control")
    func protectedIsolation() throws {
        let probe = RDPStoreProbe(), id = UUID()
        try RDPCredentialStore.save(RDPCredential(username: "user", password: "fixture"), for: id,
                                    config: local, policy: .userPresence, operations: probe.operations)
        #expect(RDPCredentialStore.availability(for: id, config: local, operations: probe.operations) == .missing)
        #expect(RDPCredentialStore.availability(for: id, config: local, policy: .userPresence, operations: probe.operations) == .available)
        #expect(throws: CredentialMobilityError.deviceBoundProtection) {
            try RDPCredentialStore.save(RDPCredential(username: "user", password: "fixture"), for: id,
                                        config: mobile, policy: .userPresence, operations: probe.operations)
        }
    }

    @Test("Malformed credential and excessive values fail before writing")
    func malformed() {
        let probe = RDPStoreProbe()
        #expect(throws: CredentialMobilityError.invalidCredential) {
            try RDPCredentialStore.save(RDPCredential(username: "", password: "fixture"), for: UUID(),
                                        config: local, operations: probe.operations)
        }
        #expect(throws: CredentialMobilityError.invalidCredential) {
            try RDPCredentialStore.save(RDPCredential(username: "user", password: String(repeating: "x", count: 65_537)),
                                        for: UUID(), config: local, operations: probe.operations)
        }
        #expect(throws: CredentialMobilityError.invalidCredential) {
            try RDPCredentialStore.save(RDPCredential(username: "user", password: "nul\0fixture"),
                                        for: UUID(), config: local, operations: probe.operations)
        }
        #expect(probe.items.isEmpty)
    }
}
