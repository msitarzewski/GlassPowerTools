//
//  KeychainManager.swift
//  glas.sh
//
//  Thin wrapper delegating to GlasSecretStore's KeychainOperations and SSHKeyKeychainStore.
//  Provides app-specific convenience methods while sharing Keychain with glassdb.
//

import Foundation
import GlassLayers
import GlasSecretStore
import os

nonisolated struct CredentialMigrationReport: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case verified
        case completed
        case failed
    }

    let fromVersion: Int
    let toVersion: Int
    let state: State
    let serverProfileCount: Int
    let uniqueServerTupleCount: Int
    let duplicateServerProfileCount: Int
    let legacyServerSourceCount: Int
    let exclusiveServerTupleCount: Int
    let ambiguousServerTupleCount: Int
    let unavailableMetadataTupleCount: Int
    let migratedServerDestinationCount: Int
    let alreadyPresentDestinationCount: Int
    let conflictCount: Int
    let tailscaleLegacySourceCount: Int
    let tailscaleMigratedCredentialCount: Int
    let verifiedDestinationCount: Int
    let deletedLegacySourceCount: Int
    let failedCount: Int
    let failureCode: String?
    let recordedAt: Date
}

nonisolated enum CredentialMigrationMetadata: Equatable, Sendable {
    /// glassdb currently keeps its profiles in its private standard defaults,
    /// which glas.sh cannot inspect. `available` is reserved for an authoritative
    /// shared metadata snapshot once both apps publish one.
    case unavailable
    case available(glassDBLegacyPasswordAccounts: Set<String>)
}

nonisolated struct CredentialMigrationStore {
    let read: (String) throws -> Data?
    let addIfAbsent: (Data, String) throws -> Bool
    let loadReport: () throws -> CredentialMigrationReport?
    let saveReport: (CredentialMigrationReport) throws -> Void
    let removeReport: () throws -> Void
    let loadVersion: () -> Int
    let saveVersion: (Int) throws -> Void

    static func live(defaults: UserDefaults) -> CredentialMigrationStore {
        CredentialMigrationStore(
            read: { account in
                do {
                    return try KeychainOperations.retrieveData(
                        account: account,
                        service: KeychainManager.config.passwordsService,
                        config: KeychainManager.config
                    )
                } catch SecretStoreError.notFound {
                    return nil
                }
            },
            addIfAbsent: { data, account in
                try KeychainOperations.addDataIfAbsent(
                    data,
                    account: account,
                    service: KeychainManager.config.passwordsService,
                    config: KeychainManager.config
                )
            },
            loadReport: {
                guard let data = defaults.data(forKey: UserDefaultsKeys.credentialMigrationReport) else {
                    return nil
                }
                return try JSONDecoder().decode(CredentialMigrationReport.self, from: data)
            },
            saveReport: { report in
                let data = try JSONEncoder().encode(report)
                defaults.set(data, forKey: UserDefaultsKeys.credentialMigrationReport)
                guard defaults.data(forKey: UserDefaultsKeys.credentialMigrationReport) == data else {
                    throw CredentialMigrationError.persistenceReadbackMismatch
                }
            },
            removeReport: {
                defaults.removeObject(forKey: UserDefaultsKeys.credentialMigrationReport)
                guard defaults.data(forKey: UserDefaultsKeys.credentialMigrationReport) == nil else {
                    throw CredentialMigrationError.persistenceReadbackMismatch
                }
            },
            loadVersion: {
                defaults.integer(forKey: UserDefaultsKeys.credentialMigrationVersion)
            },
            saveVersion: { version in
                defaults.set(version, forKey: UserDefaultsKeys.credentialMigrationVersion)
                guard defaults.integer(forKey: UserDefaultsKeys.credentialMigrationVersion) == version else {
                    throw CredentialMigrationError.persistenceReadbackMismatch
                }
            }
        )
    }
}

nonisolated struct TailscaleOAuthCredentialStore {
    let read: (String) throws -> Data?
    let addIfAbsent: (Data, String) throws -> Bool
    let delete: (String) throws -> Void

    static var live: TailscaleOAuthCredentialStore {
        TailscaleOAuthCredentialStore(
            read: { account in
                do {
                    return try KeychainOperations.retrieveData(
                        account: account,
                        service: KeychainManager.config.passwordsService,
                        config: KeychainManager.config
                    )
                } catch SecretStoreError.notFound {
                    return nil
                }
            },
            addIfAbsent: { data, account in
                try KeychainOperations.addDataIfAbsent(
                    data,
                    account: account,
                    service: KeychainManager.config.passwordsService,
                    config: KeychainManager.config
                )
            },
            delete: { account in
                try KeychainOperations.deleteItem(
                    account: account,
                    service: KeychainManager.config.passwordsService,
                    config: KeychainManager.config
                )
            }
        )
    }
}

/// Injectable boundary for the two Keychain records that make an SSH password
/// available both to this terminal profile and to other Glass apps. The live
/// implementation still delegates every operation to GlasSecretStore.
struct ServerCredentialStore {
    let read: (_ account: String, _ service: String) throws -> Data?
    let save: (_ data: Data, _ account: String, _ service: String) throws -> Void
    let addIfAbsent: (_ data: Data, _ account: String, _ service: String) throws -> Bool
    let delete: (_ account: String, _ service: String) throws -> Void

    static let live = ServerCredentialStore(
        read: { account, service in
            do {
                return try KeychainOperations.retrieveData(
                    account: account,
                    service: service,
                    config: KeychainManager.config
                )
            } catch SecretStoreError.notFound {
                return nil
            }
        },
        save: { data, account, service in
            try KeychainOperations.saveData(
                data,
                account: account,
                service: service,
                config: KeychainManager.config
            )
        },
        addIfAbsent: { data, account, service in
            try KeychainOperations.addDataIfAbsent(
                data,
                account: account,
                service: service,
                config: KeychainManager.config
            )
        },
        delete: { account, service in
            try KeychainOperations.deleteItem(
                account: account,
                service: service,
                config: KeychainManager.config
            )
        }
    )
}

/// Short-lived, verified restoration handle for a multi-record server
/// credential transaction. The captured values never leave process memory and
/// are released with the surrounding profile mutation.
struct ServerCredentialRollback {
    private let operation: () throws -> Void

    init(operation: @escaping () throws -> Void) {
        self.operation = operation
    }

    func restore() throws {
        try operation()
    }
}

nonisolated enum CredentialMigrationError: LocalizedError {
    case keychainReadbackMismatch
    case persistenceReadbackMismatch
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .keychainReadbackMismatch:
            return "A migrated credential could not be verified in Keychain."
        case .persistenceReadbackMismatch:
            return "The credential migration report or version could not be verified."
        case .rollbackFailed:
            return "Credential migration failed and its rollback could not be fully verified."
        }
    }

    var code: String {
        switch self {
        case .keychainReadbackMismatch: return "keychain-readback-mismatch"
        case .persistenceReadbackMismatch: return "persistence-readback-mismatch"
        case .rollbackFailed: return "rollback-failed"
        }
    }
}

enum ServerCredentialError: LocalizedError {
    case readbackMismatch
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .readbackMismatch:
            return "The shared SSH credential could not be verified in Keychain."
        case .rollbackFailed:
            return "The SSH credential write failed and its previous Keychain records could not be restored."
        }
    }
}

nonisolated struct CredentialMigrationServer: Sendable {
    let id: UUID
    let username: String
    let host: String
    let port: Int
    let usesPasswordAuthentication: Bool
}

enum KeychainManager {

    nonisolated private static let accessGroupInfoKey = "GlasKeychainAccessGroup"
    nonisolated private static let terminalAccountPrefix = "terminal"
    nonisolated static let currentCredentialMigrationVersion = 1
    nonisolated static let legacyTailscaleAPIKeyAccount = "tailscale-api-key"
    nonisolated static let legacyTailscaleOAuthClientIDAccount = "tailscale-oauth-client-id"
    nonisolated static let legacyTailscaleOAuthClientSecretAccount = "tailscale-oauth-client-secret"

    // D18/D21: SSH passwords, key passphrases and private keys travel with the user.
    //
    // Apple synchronizes password-class items only — not keys or certificates — which would rule
    // SSH keys out, except that `GlasSecretStore` stores everything as `kSecClassGenericPassword`,
    // so the key bytes ride inside a password item. That is why `sshKeysPrivateService` is already
    // on `validateMobility`'s eligible list. Secure Enclave–backed keys are the real exception and
    // are refused there regardless of this setting.
    /// Secure Enclave key material, which can never travel.
    ///
    /// A `TRUE_SE_P256:` or `SECURE_ENCLAVE_P256:` value is an opaque token usable only by the chip
    /// that minted it, and it is written to `sshKeysPrivateService` — which *is* eligible for
    /// synchronization. Without this configuration it would sync: a key present on every device and
    /// usable on exactly one, listed as available on all of them. `isDeviceBoundKeyMaterial` routes
    /// it here, and this is the only thing that still belongs on `.deviceOnly`.
    ///
    /// **Host-key pins used to live here too, and that was a half-fix.** Enabling D18 on the one
    /// shared configuration made every pin throw `ineligibleService` — `sshHostTrustService` was not
    /// on `validateMobility`'s eligible list — so the trust store moved here and SSH connected
    /// again. But `KeychainManager`'s own host-trust methods kept using `config`, so the *user*
    /// accepting a fingerprint still threw, and a pin written by one path could not be read by the
    /// other. D23 settles it: host trust is eligible and synchronizes, and there is one
    /// configuration for it.
    nonisolated static let deviceBoundConfig = SecretStoreConfiguration(
        serviceNamePrefix: "sh.glas",
        accessGroup: resolvedAccessGroup,
        useDataProtectionKeychain: true
    )

    nonisolated static let config = SecretStoreConfiguration(
        serviceNamePrefix: "sh.glas",
        accessGroup: resolvedAccessGroup,
        useDataProtectionKeychain: true,
        mobilityPolicy: .iCloudKeychain
    )

    /// The configuration pinned host keys are stored under (D23).
    ///
    /// It is a named property rather than `config` spelled out at each call site because the last
    /// defect here was two paths disagreeing: the transport pinned under one configuration while
    /// this type's own `savePinnedHostKey`/`replaceHostKey` used another, so a pin written on
    /// connect could not be read by the trust prompt, and the prompt itself threw. One name means
    /// one answer, and one place for a future change to land.
    nonisolated static var hostTrustConfig: SecretStoreConfiguration { config }

    nonisolated private static var resolvedAccessGroup: String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: accessGroupInfoKey) as? String else {
            return nil
        }
        return validatedSharedAccessGroup(rawValue)
    }

    nonisolated static func validatedSharedAccessGroup(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        let components = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2,
              components[0].count == 10,
              components[0].allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }),
              components[1] == GlassAppIdentity.keychainGroupSuffix else {
            return nil
        }
        return value
    }

    // MARK: - Server Password

    static func savePassword(
        _ password: String,
        for server: ServerConfiguration,
        store: ServerCredentialStore = .live
    ) throws {
        guard !password.isEmpty, let data = password.data(using: .utf8) else {
            throw SecretStoreError.encodingFailed
        }
        let locations = serverCredentialLocations(for: server)
        let snapshots = try locations.map { location in
            (location, try store.read(location.account, location.service))
        }

        do {
            for location in locations {
                try store.save(data, location.account, location.service)
                guard try store.read(location.account, location.service) == data else {
                    throw ServerCredentialError.readbackMismatch
                }
            }
        } catch {
            do {
                for (location, snapshot) in snapshots.reversed() {
                    if let snapshot {
                        try store.save(snapshot, location.account, location.service)
                        guard try store.read(location.account, location.service) == snapshot else {
                            throw ServerCredentialError.readbackMismatch
                        }
                    } else {
                        try store.delete(location.account, location.service)
                        guard try store.read(location.account, location.service) == nil else {
                            throw ServerCredentialError.readbackMismatch
                        }
                    }
                }
            } catch {
                throw ServerCredentialError.rollbackFailed
            }
            throw error
        }
    }

    static func passwordRollback(
        for server: ServerConfiguration,
        store: ServerCredentialStore = .live
    ) throws -> ServerCredentialRollback {
        let snapshots = try serverCredentialLocations(for: server).map { location in
            (location, try store.read(location.account, location.service))
        }
        return ServerCredentialRollback {
            for (location, snapshot) in snapshots {
                if let snapshot {
                    try store.save(snapshot, location.account, location.service)
                    guard try store.read(location.account, location.service) == snapshot else {
                        throw ServerCredentialError.readbackMismatch
                    }
                } else {
                    do {
                        try store.delete(location.account, location.service)
                    } catch SecretStoreError.notFound {
                        // Absence is the captured state; verify it below.
                    }
                    guard try store.read(location.account, location.service) == nil else {
                        throw ServerCredentialError.readbackMismatch
                    }
                }
            }
        }
    }

    static func retrievePassword(
        for server: ServerConfiguration,
        store: ServerCredentialStore = .live
    ) throws -> String {
        let primary = serverCredentialLocations(for: server)[0]
        if let data = try store.read(primary.account, primary.service) {
            return try decodedPassword(data)
        }

        guard let compatibility = sharedSSHPasswordLocation(for: server),
              let sharedData = try store.read(compatibility.account, compatibility.service) else {
            throw SecretStoreError.notFound
        }
        let sharedPassword = try decodedPassword(sharedData)

        if try store.addIfAbsent(sharedData, primary.account, primary.service) {
            guard try store.read(primary.account, primary.service) == sharedData else {
                throw ServerCredentialError.readbackMismatch
            }
            return sharedPassword
        }

        // Another app instance may have created the profile record after our
        // initial lookup. Its profile-specific value deterministically wins.
        guard let concurrentData = try store.read(primary.account, primary.service) else {
            throw ServerCredentialError.readbackMismatch
        }
        return try decodedPassword(concurrentData)
    }

    static func deletePassword(
        for server: ServerConfiguration,
        store: ServerCredentialStore = .live
    ) throws {
        // The compatibility record is shared ownership. Deleting a glas.sh
        // profile must never revoke a credential still used by glassdb.
        try store.delete(serverPasswordAccount(for: server.id), config.passwordsService)
    }

    /// Restores the exact pre-write state after a higher-level profile
    /// transaction fails. This is intentionally separate from normal profile
    /// deletion, which must retain the cross-app compatibility record.
    static func deletePublishedPassword(
        for server: ServerConfiguration,
        store: ServerCredentialStore = .live
    ) throws {
        for location in serverCredentialLocations(for: server) {
            do {
                try store.delete(location.account, location.service)
            } catch SecretStoreError.notFound {
                // The rollback target is absence; continue verifying every
                // location even when one record was already absent.
            }
            guard try store.read(location.account, location.service) == nil else {
                throw ServerCredentialError.readbackMismatch
            }
        }
    }

    /// Removes only the endpoint-scoped compatibility record shared with
    /// other Glass apps. Normal profile deletion deliberately does not call
    /// this because the record may still be owned by glassdb.
    static func deleteSharedCompatibilityPassword(
        for server: ServerConfiguration,
        store: ServerCredentialStore = .live
    ) throws {
        guard let location = sharedSSHPasswordLocation(for: server) else { return }
        do {
            try store.delete(location.account, location.service)
        } catch SecretStoreError.notFound {
            // Absence is the requested state; verify it below.
        }
        guard try store.read(location.account, location.service) == nil else {
            throw ServerCredentialError.readbackMismatch
        }
    }

    /// Stable per-profile namespace. Deliberately does not use the legacy
    /// `username@host:port` tuple because that account may belong to glassdb in
    /// the shared Keychain service.
    nonisolated static func serverPasswordAccount(for serverID: UUID) -> String {
        "\(terminalAccountPrefix).server-password.\(serverID.uuidString.lowercased())"
    }

    static func legacyServerPasswordAccount(for server: ServerConfiguration) -> String {
        "\(server.username)@\(server.host):\(server.port)"
    }

    nonisolated static func legacyServerPasswordAccount(
        for server: CredentialMigrationServer
    ) -> String {
        "\(server.username)@\(server.host):\(server.port)"
    }

    static func credentialMigrationServers(
        from servers: [ServerConfiguration]
    ) -> [CredentialMigrationServer] {
        servers.map {
            CredentialMigrationServer(
                id: $0.id,
                username: $0.username,
                host: $0.host,
                port: $0.port,
                usesPasswordAuthentication: $0.authMethod == .password
            )
        }
    }

    /// Cross-app SSH compatibility account used by glassdb in the shared
    /// `sh.glas.sshpasswords` service.
    static func sharedSSHPasswordAccount(for server: ServerConfiguration) -> String? {
        let username = server.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !host.isEmpty else { return nil }
        return "ssh:\(username)@\(host):\(server.port)"
    }

    private struct ServerCredentialLocation {
        let account: String
        let service: String
    }

    private static func serverCredentialLocations(
        for server: ServerConfiguration
    ) -> [ServerCredentialLocation] {
        var locations = [ServerCredentialLocation(
            account: serverPasswordAccount(for: server.id),
            service: config.passwordsService
        )]
        if let shared = sharedSSHPasswordLocation(for: server) {
            locations.append(shared)
        }
        return locations
    }

    private static func sharedSSHPasswordLocation(
        for server: ServerConfiguration
    ) -> ServerCredentialLocation? {
        guard let account = sharedSSHPasswordAccount(for: server) else { return nil }
        return ServerCredentialLocation(account: account, service: config.sshPasswordsService)
    }

    private static func decodedPassword(_ data: Data) throws -> String {
        guard let password = String(data: data, encoding: .utf8), !password.isEmpty else {
            throw SecretStoreError.encodingFailed
        }
        return password
    }

    // MARK: - SSH Keys

    /// Secure Enclave keys are stored device-bound; everything else travels.
    ///
    /// A Secure Enclave key's stored value is not key material at all — it is an **opaque token**
    /// that only the chip which minted it can use (`SettingsManager.generateSecureEnclaveP256Key`
    /// encodes `dataRepresentation` behind a `TRUE_SE_P256:` prefix). Syncing it would put a key on
    /// every device that works on exactly one of them, and list it as available on the others.
    ///
    /// `validateMobility` already excludes the *legacy* `SECURE_ENCLAVE_P256:` representation by
    /// keeping `sealedP256Service` off its eligible list — but the newer `TRUE_SE_P256:` form never
    /// touches that service. It goes to `sshKeysPrivateService`, which **is** eligible, so under
    /// D18 it would have synchronized: the guard existed and this path walked around it.
    ///
    /// This is the project's own non-negotiable — *device-bound keys cannot be advertised as
    /// synchronized* — so the decision is made here, by where the key is written, rather than left
    /// to the eligibility list to catch.
    /// Exposed for the test that pins this rule; the decision itself stays private.
    static func isDeviceBoundKeyMaterialForTesting(_ privateKey: String) -> Bool {
        isDeviceBoundKeyMaterial(privateKey)
    }

    private static func isDeviceBoundKeyMaterial(_ privateKey: String) -> Bool {
        privateKey.hasPrefix("TRUE_SE_P256:") || privateKey.hasPrefix("SECURE_ENCLAVE_P256:")
    }

    static func saveSSHKey(_ privateKey: String, passphrase: String?, for keyID: UUID) throws {
        let secureKey = SecureBytes(Data(privateKey.utf8))
        let securePassphrase = passphrase.map { SecureBytes(Data($0.utf8)) }
        let destination = isDeviceBoundKeyMaterial(privateKey) ? deviceBoundConfig : config
        try SSHKeyKeychainStore.save(privateKey: secureKey, passphrase: securePassphrase,
                                     for: keyID, config: destination)
    }

    /// Tries the synchronized store first and falls back to the device-bound one.
    ///
    /// Which store a key is in depends on what kind it is, and the caller has only an id — the
    /// prefix that decides is *inside* the value. Two lookups is the price of not making every
    /// caller know that.
    static func retrieveSSHKey(for keyID: UUID) throws -> SSHKeyMaterial {
        do {
            return try SSHKeyKeychainStore.retrieve(for: keyID, config: config)
        } catch {
            return try SSHKeyKeychainStore.retrieve(for: keyID, config: deviceBoundConfig)
        }
    }

    /// Deletes from both, because a key written before this split may be in either and leaving one
    /// behind is how a secret becomes unreachable but not gone.
    // MARK: - SSH Key Records (D26)

    /// Saves a key's record to the same store its material went to.
    ///
    /// The routing decision is made **once**, here, for both halves: `saveSSHKey` sends Secure
    /// Enclave material to the device-bound configuration, and a record for a key that cannot leave
    /// this device must not leave it either — a key listed on another device and guaranteed to fail
    /// there is worse than one that is simply not listed.
    ///
    /// `storageKind` is the record's own statement of what it is, set when the key was created or
    /// imported from the same prefix check that routes the material, so the two cannot disagree.
    static func saveSSHKeyRecord(_ record: StoredSSHKey) throws {
        try SSHKeyRecordStore.save(record, config: recordDestination(for: record))
    }

    /// Which store a record belongs in. Separated from the write so the *decision* can be tested
    /// without a Keychain the test process is allowed to use — the production configuration carries
    /// a real access group, which an unsigned test binary cannot write to. `isDeviceBoundKeyMaterial`
    /// already has the same seam for the same reason.
    static func recordDestination(for record: StoredSSHKey) -> SecretStoreConfiguration {
        record.storageKind == .secureEnclave ? deviceBoundConfig : config
    }

    /// Every key record this device can use: the synchronized ones, plus the hardware keys that
    /// belong to this device alone. Sorted oldest first so the library has a stable order.
    ///
    /// A failure reading either store is **not** swallowed into an empty list — "no keys" and "the
    /// Keychain would not answer" are different, and only one of them is safe to show a user who is
    /// about to decide a key is gone.
    static func allSSHKeyRecords() throws -> [StoredSSHKey] {
        let synchronized = try SSHKeyRecordStore.all(config: config)
        let deviceBound = try SSHKeyRecordStore.all(config: deviceBoundConfig)
        return (synchronized + deviceBound).sorted { $0.createdAt < $1.createdAt }
    }

    /// Removes the record from both stores, for the same reason `deleteSSHKey` does: the caller has
    /// an id, and which store holds it depends on what kind of key it was.
    static func deleteSSHKeyRecord(for keyID: UUID) throws {
        var firstError: (any Error)?
        do { try SSHKeyRecordStore.delete(keyID, config: config) } catch { firstError = error }
        do { try SSHKeyRecordStore.delete(keyID, config: deviceBoundConfig) } catch {
            if firstError == nil { firstError = error }
        }
        if let firstError { throw firstError }
    }

    static func deleteSSHKey(for keyID: UUID) throws {
        var firstError: (any Error)?
        do { try SSHKeyKeychainStore.delete(for: keyID, config: config) } catch { firstError = error }
        do { try SSHKeyKeychainStore.delete(for: keyID, config: deviceBoundConfig) } catch {
            if firstError == nil { firstError = error }
        }
        if let firstError { throw firstError }
    }

    // MARK: - SSH Host Trust

    static func saveHostKey(_ challenge: HostKeyTrustChallenge) throws {
        let publicKeyData = try validatedHostKeyData(
            base64: challenge.keyDataBase64,
            claimedFingerprint: challenge.fingerprintSHA256
        )
        let hostKey = PinnedSSHHostKey(
            host: challenge.host,
            port: challenge.port,
            algorithm: challenge.algorithm,
            publicKeyData: publicKeyData
        )
        try hostKey.validate()
        try SSHHostTrustKeychainStore.save(hostKey, config: hostTrustConfig)
    }

    static func replaceHostKey(with challenge: HostKeyTrustChallenge) throws {
        let publicKeyData = try validatedHostKeyData(
            base64: challenge.keyDataBase64,
            claimedFingerprint: challenge.fingerprintSHA256
        )
        let replacement = PinnedSSHHostKey(
            host: challenge.host,
            port: challenge.port,
            algorithm: challenge.algorithm,
            publicKeyData: publicKeyData
        )
        try SSHHostTrustKeychainStore.replace(with: replacement, config: hostTrustConfig)
    }

    static func saveHostKey(_ entry: TrustedHostKeyEntry) throws {
        try savePinnedHostKey(try pinnedHostKey(from: entry))
    }

    static func pinnedHostKey(from entry: TrustedHostKeyEntry) throws -> PinnedSSHHostKey {
        let publicKeyData = try validatedHostKeyData(
            base64: entry.keyDataBase64,
            claimedFingerprint: entry.fingerprintSHA256
        )
        let hostKey = PinnedSSHHostKey(
            host: entry.host,
            port: entry.port,
            algorithm: entry.algorithm,
            publicKeyData: publicKeyData,
            createdAt: entry.addedAt,
            lastSeenAt: entry.addedAt
        )
        try hostKey.validate()
        return hostKey
    }

    private static func validatedHostKeyData(base64: String, claimedFingerprint: String) throws -> Data {
        guard let publicKeyData = Data(base64Encoded: base64), !publicKeyData.isEmpty else {
            throw SecretStoreError.encodingFailed
        }
        let canonical = PinnedSSHHostKey.sha256Fingerprint(for: publicKeyData)
        let unpadded = String(canonical.dropFirst("SHA256:".count))
        let padded = unpadded + String(repeating: "=", count: (4 - unpadded.count % 4) % 4)
        guard claimedFingerprint == canonical
                || claimedFingerprint == unpadded
                || claimedFingerprint == padded else {
            throw SecretStoreError.encodingFailed
        }
        return publicKeyData
    }

    static func savePinnedHostKey(_ hostKey: PinnedSSHHostKey) throws {
        try SSHHostTrustKeychainStore.save(hostKey, config: hostTrustConfig)
    }

    static func allPinnedHostKeys() throws -> [PinnedSSHHostKey] {
        try SSHHostTrustKeychainStore.allPinnedHosts(config: hostTrustConfig)
    }

    /// Forgets every key trusted for `host`:`port`; the next connection asks again (Ask mode) or is
    /// refused (Strict).
    static func forgetHostKeys(host: String, port: Int) throws {
        try SSHHostTrustKeychainStore.delete(host: host, port: port, config: hostTrustConfig)
    }

    static func trustedHostKeyBase64Set(host: String, port: Int) throws -> Set<String> {
        let records = try SSHHostTrustKeychainStore.authorizedRecords(host: host, port: port, config: hostTrustConfig)
        return Set(records.map { $0.publicKeyData.base64EncodedString() })
    }

    // MARK: - Tailscale API Key

    nonisolated static let tailscaleAPIKeyAccount = "\(terminalAccountPrefix).tailscale.api-key"

    static func saveTailscaleAPIKey(_ apiKey: String) throws {
        try KeychainOperations.savePassword(
            apiKey,
            account: tailscaleAPIKeyAccount,
            service: config.passwordsService,
            config: config
        )
    }

    nonisolated static func retrieveTailscaleAPIKey() throws -> String {
        try KeychainOperations.retrievePassword(
            account: tailscaleAPIKeyAccount,
            service: config.passwordsService,
            config: config
        )
    }

    static func deleteTailscaleAPIKey() throws {
        try KeychainOperations.deletePassword(
            account: tailscaleAPIKeyAccount,
            service: config.passwordsService,
            config: config
        )
    }

    // MARK: - Tailscale OAuth Credentials

    nonisolated static let tailscaleOAuthClientIDAccount = "\(terminalAccountPrefix).tailscale.oauth.client-id"
    nonisolated static let tailscaleOAuthClientSecretAccount = "\(terminalAccountPrefix).tailscale.oauth.client-secret"
    nonisolated static let tailscaleOAuthCredentialsAccount = "\(terminalAccountPrefix).tailscale.oauth.credentials"

    nonisolated private struct TailscaleOAuthCredentials: Codable, Equatable {
        let clientID: String
        let clientSecret: String
    }

    static func saveTailscaleOAuthCredentials(clientID: String, clientSecret: String) throws {
        let credentials = TailscaleOAuthCredentials(clientID: clientID, clientSecret: clientSecret)
        let data = try JSONEncoder().encode(credentials)
        try KeychainOperations.saveData(
            data,
            account: tailscaleOAuthCredentialsAccount,
            service: config.passwordsService,
            config: config
        )
    }

    nonisolated static func retrieveTailscaleOAuthCredentials() throws -> (clientID: String, clientSecret: String) {
        try retrieveTailscaleOAuthCredentials(store: .live)
    }

    static func deleteTailscaleOAuthCredentials() throws {
        try deleteTailscaleOAuthCredentials(store: .live)
    }

    nonisolated static func retrieveTailscaleOAuthCredentials(
        store: TailscaleOAuthCredentialStore
    ) throws -> (clientID: String, clientSecret: String) {
        // Resolve all accounts before mutation. The live store maps only an
        // actual notFound to nil; access/query errors propagate unchanged.
        let bundledData = try store.read(tailscaleOAuthCredentialsAccount)
        let splitIDData = try store.read(tailscaleOAuthClientIDAccount)
        let splitSecretData = try store.read(tailscaleOAuthClientSecretAccount)

        let bundledCredentials: TailscaleOAuthCredentials?
        if let bundledData {
            guard let decoded = try? JSONDecoder().decode(
                TailscaleOAuthCredentials.self,
                from: bundledData
            ) else {
                throw SecretStoreError.encodingFailed
            }
            bundledCredentials = decoded
        } else {
            bundledCredentials = nil
        }

        let splitCredentials: TailscaleOAuthCredentials?
        if let splitIDData, let splitSecretData {
            guard let clientID = String(data: splitIDData, encoding: .utf8),
                  let clientSecret = String(data: splitSecretData, encoding: .utf8) else {
                throw SecretStoreError.encodingFailed
            }
            splitCredentials = .init(clientID: clientID, clientSecret: clientSecret)
        } else {
            splitCredentials = nil
        }

        let credentials: TailscaleOAuthCredentials
        if let bundledCredentials {
            credentials = bundledCredentials
        } else if let splitCredentials {
            credentials = splitCredentials
            let encoded = try JSONEncoder().encode(credentials)
            _ = try store.addIfAbsent(encoded, tailscaleOAuthCredentialsAccount)
            guard let stored = try store.read(tailscaleOAuthCredentialsAccount),
                  let storedCredentials = try? JSONDecoder().decode(
                    TailscaleOAuthCredentials.self,
                    from: stored
                  ),
                  storedCredentials == credentials else {
                throw CredentialMigrationError.keychainReadbackMismatch
            }
        } else {
            throw SecretStoreError.notFound
        }

        // Retain split sources after forward migration. Keychain offers no
        // atomic compare-and-delete operation, so deleting from an earlier
        // snapshot could erase a concurrent rotation by another app instance.
        return (credentials.clientID, credentials.clientSecret)
    }

    static func deleteTailscaleOAuthCredentials(
        store: TailscaleOAuthCredentialStore
    ) throws {
        let accounts = [
            tailscaleOAuthCredentialsAccount,
            tailscaleOAuthClientIDAccount,
            tailscaleOAuthClientSecretAccount,
        ]
        var firstFailure: Error?
        for account in accounts {
            do {
                try store.delete(account)
            } catch SecretStoreError.notFound {
                // Idempotent delete; absence is verified below.
            } catch {
                firstFailure = firstFailure ?? error
            }
        }
        for account in accounts {
            do {
                if try store.read(account) != nil {
                    firstFailure = firstFailure ?? CredentialMigrationError.keychainReadbackMismatch
                }
            } catch {
                firstFailure = firstFailure ?? error
            }
        }
        if let firstFailure { throw firstFailure }
    }

    // MARK: - Credential Namespace Migration

    /// Migrates only credentials whose ownership can be established without
    /// guessing. The report contains counts only; it never persists endpoint or
    /// credential material.
    @discardableResult
    static func runCredentialMigrationIfNeeded(
        servers: [ServerConfiguration],
        metadata: CredentialMigrationMetadata,
        store: CredentialMigrationStore
    ) throws -> CredentialMigrationReport {
        try runCredentialMigrationIfNeeded(
            serverSnapshots: credentialMigrationServers(from: servers),
            metadata: metadata,
            store: store
        )
    }

    @discardableResult
    nonisolated static func runCredentialMigrationIfNeeded(
        serverSnapshots: [CredentialMigrationServer],
        metadata: CredentialMigrationMetadata,
        store: CredentialMigrationStore
    ) throws -> CredentialMigrationReport {
        let previousVersion = store.loadVersion()
        if previousVersion >= currentCredentialMigrationVersion,
           let report = try store.loadReport(), report.state == .completed {
            return report
        }

        let previousReport = try store.loadReport()
        let passwordServers = serverSnapshots
            .filter(\.usesPasswordAuthentication)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        var groupedServers: [String: [CredentialMigrationServer]] = [:]
        for server in passwordServers {
            groupedServers[legacyServerPasswordAccount(for: server), default: []].append(server)
        }
        let sortedTuples = groupedServers.keys.sorted()

        var legacyServerSourceCount = 0
        var exclusiveServerTupleCount = 0
        var ambiguousServerTupleCount = 0
        var unavailableMetadataTupleCount = 0
        var migratedServerDestinationCount = 0
        var alreadyPresentDestinationCount = 0
        var conflictCount = 0
        var tailscaleLegacySourceCount = 0
        var tailscaleMigratedCredentialCount = 0
        var verifiedDestinationCount = 0
        let deletedLegacySourceCount = 0

        var values: [String: Data] = [:]
        let serverAccounts = sortedTuples + passwordServers.map { serverPasswordAccount(for: $0.id) }
        let tailscaleAccounts = [
            legacyTailscaleAPIKeyAccount,
            legacyTailscaleOAuthClientIDAccount,
            legacyTailscaleOAuthClientSecretAccount,
            tailscaleAPIKeyAccount,
            tailscaleOAuthClientIDAccount,
            tailscaleOAuthClientSecretAccount,
            tailscaleOAuthCredentialsAccount
        ]

        func report(state: CredentialMigrationReport.State, failedCount: Int, failureCode: String?) -> CredentialMigrationReport {
            CredentialMigrationReport(
                fromVersion: previousVersion,
                toVersion: currentCredentialMigrationVersion,
                state: state,
                serverProfileCount: passwordServers.count,
                uniqueServerTupleCount: sortedTuples.count,
                duplicateServerProfileCount: passwordServers.count - sortedTuples.count,
                legacyServerSourceCount: legacyServerSourceCount,
                exclusiveServerTupleCount: exclusiveServerTupleCount,
                ambiguousServerTupleCount: ambiguousServerTupleCount,
                unavailableMetadataTupleCount: unavailableMetadataTupleCount,
                migratedServerDestinationCount: migratedServerDestinationCount,
                alreadyPresentDestinationCount: alreadyPresentDestinationCount,
                conflictCount: conflictCount,
                tailscaleLegacySourceCount: tailscaleLegacySourceCount,
                tailscaleMigratedCredentialCount: tailscaleMigratedCredentialCount,
                verifiedDestinationCount: verifiedDestinationCount,
                deletedLegacySourceCount: deletedLegacySourceCount,
                failedCount: failedCount,
                failureCode: failureCode,
                recordedAt: Date()
            )
        }

        func restorePersistence() throws {
            if let previousReport {
                try store.saveReport(previousReport)
            } else {
                try store.removeReport()
            }
            try store.saveVersion(previousVersion)
        }

        func rollback() throws {
            // Never delete a destination written earlier in this transaction.
            // Keychain has no atomic compare-and-delete primitive, so a
            // read-then-delete rollback could erase another process's rotation.
            // Keeping the verified forward copy is lossless and retryable.
            try restorePersistence()
        }

        do {
            // Resolve every possible source and destination before the first
            // mutation. Only an actual notFound is represented as nil by the
            // live store; access and query errors abort the migration.
            for account in Set(serverAccounts + tailscaleAccounts).sorted() {
                if let data = try store.read(account) {
                    values[account] = data
                }
            }

            var plannedWrites: [String: Data] = [:]

            for tuple in sortedTuples {
                guard let legacyValue = values[tuple], let profiles = groupedServers[tuple] else { continue }
                legacyServerSourceCount += 1

                let isExclusive: Bool
                switch metadata {
                case .unavailable:
                    unavailableMetadataTupleCount += 1
                    isExclusive = false
                case .available(let glassDBAccounts):
                    if glassDBAccounts.contains(tuple) {
                        ambiguousServerTupleCount += 1
                        isExclusive = false
                    } else {
                        exclusiveServerTupleCount += 1
                        isExclusive = true
                    }
                }

                guard isExclusive else { continue }
                var tupleHasConflict = false
                for profile in profiles.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                    let destination = serverPasswordAccount(for: profile.id)
                    if let existing = values[destination] {
                        if existing == legacyValue {
                            alreadyPresentDestinationCount += 1
                        } else {
                            conflictCount += 1
                            tupleHasConflict = true
                        }
                    } else {
                        plannedWrites[destination] = legacyValue
                    }
                }
                if tupleHasConflict {
                    for profile in profiles {
                        plannedWrites.removeValue(forKey: serverPasswordAccount(for: profile.id))
                    }
                }
            }

            func planSingleCredential(source: String, destination: String) {
                guard let sourceValue = values[source] else { return }
                tailscaleLegacySourceCount += 1
                if let destinationValue = values[destination] {
                    if destinationValue == sourceValue {
                        alreadyPresentDestinationCount += 1
                    } else {
                        conflictCount += 1
                    }
                } else {
                    plannedWrites[destination] = sourceValue
                    tailscaleMigratedCredentialCount += 1
                }
            }

            planSingleCredential(source: legacyTailscaleAPIKeyAccount, destination: tailscaleAPIKeyAccount)

            struct OAuthSplitSource {
                let credentials: TailscaleOAuthCredentials
            }

            let oauthAccountPairs = [
                (legacyTailscaleOAuthClientIDAccount, legacyTailscaleOAuthClientSecretAccount),
                (tailscaleOAuthClientIDAccount, tailscaleOAuthClientSecretAccount)
            ]
            var completeOAuthSources: [OAuthSplitSource] = []
            for (clientIDAccount, clientSecretAccount) in oauthAccountPairs {
                let clientIDData = values[clientIDAccount]
                let clientSecretData = values[clientSecretAccount]
                tailscaleLegacySourceCount += [clientIDData, clientSecretData].compactMap { $0 }.count

                guard let clientIDData, let clientSecretData else {
                    if clientIDData != nil || clientSecretData != nil {
                        conflictCount += 1
                    }
                    continue
                }
                guard let clientID = String(data: clientIDData, encoding: .utf8),
                      let clientSecret = String(data: clientSecretData, encoding: .utf8) else {
                    conflictCount += 1
                    continue
                }
                completeOAuthSources.append(OAuthSplitSource(
                    credentials: TailscaleOAuthCredentials(
                        clientID: clientID,
                        clientSecret: clientSecret
                    )
                ))
            }

            if let candidate = completeOAuthSources.first {
                let sourcesAgree = completeOAuthSources.dropFirst().allSatisfy {
                    $0.credentials == candidate.credentials
                }
                if !sourcesAgree {
                    conflictCount += 1
                } else {
                    if let destinationData = values[tailscaleOAuthCredentialsAccount] {
                        let destination = try? JSONDecoder().decode(
                            TailscaleOAuthCredentials.self,
                            from: destinationData
                        )
                        if destination == candidate.credentials {
                            alreadyPresentDestinationCount += 1
                        } else {
                            conflictCount += 1
                        }
                    } else {
                        plannedWrites[tailscaleOAuthCredentialsAccount] = try JSONEncoder().encode(candidate.credentials)
                        tailscaleMigratedCredentialCount += 1
                    }
                }
            }

            for account in plannedWrites.keys.sorted() {
                guard let data = plannedWrites[account] else { continue }
                let isServerDestination = account.hasPrefix(
                    "\(terminalAccountPrefix).server-password."
                )
                guard try store.addIfAbsent(data, account) else {
                    guard let concurrentValue = try store.read(account) else {
                        throw CredentialMigrationError.keychainReadbackMismatch
                    }
                    if concurrentValue == data {
                        alreadyPresentDestinationCount += 1
                    } else {
                        conflictCount += 1
                    }
                    if !isServerDestination {
                        tailscaleMigratedCredentialCount -= 1
                    }
                    continue
                }
                guard try store.read(account) == data else {
                    throw CredentialMigrationError.keychainReadbackMismatch
                }
                verifiedDestinationCount += 1
                if isServerDestination {
                    migratedServerDestinationCount += 1
                }
            }

            let verifiedReport = report(state: .verified, failedCount: 0, failureCode: nil)
            try store.saveReport(verifiedReport)
            guard try store.loadReport() == verifiedReport else {
                throw CredentialMigrationError.persistenceReadbackMismatch
            }

            // Source cleanup is deliberately forward-only. Retaining the
            // verified legacy records avoids deleting a credential rotated by
            // glassdb or another app instance after this process's preflight.

            let completedReport = report(state: .completed, failedCount: 0, failureCode: nil)
            try store.saveReport(completedReport)
            guard try store.loadReport() == completedReport else {
                throw CredentialMigrationError.persistenceReadbackMismatch
            }
            try store.saveVersion(currentCredentialMigrationVersion)
            guard store.loadVersion() == currentCredentialMigrationVersion else {
                throw CredentialMigrationError.persistenceReadbackMismatch
            }
            return completedReport
        } catch {
            do {
                try rollback()
            } catch {
                let failedReport = report(state: .failed, failedCount: 1, failureCode: CredentialMigrationError.rollbackFailed.code)
                try store.saveReport(failedReport)
                guard try store.loadReport() == failedReport else {
                    throw CredentialMigrationError.persistenceReadbackMismatch
                }
                throw CredentialMigrationError.rollbackFailed
            }
            let failureCode = (error as? CredentialMigrationError)?.code ?? "keychain-query-store-failure"
            let failedReport = report(state: .failed, failedCount: 1, failureCode: failureCode)
            try store.saveReport(failedReport)
            guard try store.loadReport() == failedReport else {
                throw CredentialMigrationError.persistenceReadbackMismatch
            }
            throw error
        }
    }

}
