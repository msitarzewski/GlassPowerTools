//
//  KeychainManager.swift
//  glassdb
//
//  Thin wrapper delegating to GlasSecretStore's KeychainOperations and SSHKeyKeychainStore.
//  Provides app-specific convenience methods while sharing Keychain with glas.sh.
//

import Foundation
import GlasSecretStore
import GlassDBKit
import LocalAuthentication
import os
import Security

enum KeychainManager {

    private static let accessGroupInfoKey = "GlasKeychainAccessGroup"
    static let credentialMigrationVersionKey = "app.glassdb.connectionCredentialMigrationVersion"
    static let currentCredentialMigrationVersion = 2

    struct CredentialMigrationReport: Sendable {
        let migratedDatabasePasswords: Int
        let migratedSSHPasswords: Int
        let failures: [String]

        var isSuccessful: Bool { failures.isEmpty }
    }

    struct CredentialMigrationStore: @unchecked Sendable {
        let retrieveData: (
            _ account: String,
            _ service: String,
            _ config: SecretStoreConfiguration
        ) throws -> Data
        let retrievePassword: (
            _ account: String,
            _ service: String,
            _ config: SecretStoreConfiguration
        ) throws -> String
        let savePassword: (
            _ value: String,
            _ account: String,
            _ service: String,
            _ config: SecretStoreConfiguration
        ) throws -> Void

        static let live = CredentialMigrationStore(
            retrieveData: { account, service, config in
                try KeychainOperations.retrieveData(
                    account: account,
                    service: service,
                    config: config
                )
            },
            retrievePassword: { account, service, config in
                try KeychainOperations.retrievePassword(
                    account: account,
                    service: service,
                    config: config
                )
            },
            savePassword: { value, account, service, config in
                try KeychainOperations.savePassword(
                    value,
                    account: account,
                    service: service,
                    config: config
                )
            }
        )
    }

    struct CredentialMigrationError: LocalizedError {
        let failures: [String]

        var errorDescription: String? {
            "Some saved credentials could not be upgraded. Your connections were kept, but affected credentials must be saved again. \(failures.joined(separator: " "))"
        }
    }

    enum CredentialKind: Sendable {
        case databasePassword
        case sshPassword
    }

    struct CredentialStorageDescriptor: Sendable {
        let service: String
        let config: SecretStoreConfiguration
        let accessPolicy: SecretAccessPolicy
        let authenticationPrompt: String?
        let isSharedWithGlas: Bool
    }

    struct CredentialPersistenceReport: Sendable {
        let cleanupWarnings: [String]
        let rollbackReceipt: CredentialDeletionReceipt
    }

    struct CredentialMutationStore: @unchecked Sendable {
        let retrieve: (_ account: String, _ descriptor: CredentialStorageDescriptor) throws -> String?
        let save: (_ value: String, _ account: String, _ descriptor: CredentialStorageDescriptor) throws -> Void
        let delete: (_ account: String, _ descriptor: CredentialStorageDescriptor) throws -> Void

        static let live = CredentialMutationStore(
            retrieve: { account, descriptor in
                do {
                    return try retrieveStablePassword(account: account, descriptor: descriptor)
                } catch GlasSecretStore.SecretStoreError.notFound {
                    return nil
                }
            },
            save: { value, account, descriptor in
                try KeychainManager.save(value, account: account, descriptor: descriptor)
            },
            delete: { account, descriptor in
                try KeychainManager.delete(account: account, descriptor: descriptor)
            }
        )
    }

    struct CredentialSnapshot: Sendable {
        let account: String
        let descriptor: CredentialStorageDescriptor
        let value: String?
    }

    struct CredentialDeletionReceipt: Sendable {
        let snapshots: [CredentialSnapshot]
    }

    enum CredentialPolicyError: LocalizedError {
        case authenticationUnavailable(String)
        case authenticationCancelledOrCredentialUnavailable
        case verificationFailed
        case mutationRollbackFailed

        var errorDescription: String? {
            switch self {
            case .authenticationUnavailable(let reason):
                return "Device-owner authentication is unavailable. \(reason)"
            case .authenticationCancelledOrCredentialUnavailable:
                return "Authentication was canceled, failed, or the protected credential is unavailable."
            case .verificationFailed:
                return "The credential could not be verified in its new secure storage location. The previous copy was retained."
            case .mutationRollbackFailed:
                return "A credential operation failed and the previous credentials could not be fully restored. Re-enter both database and SSH credentials before connecting again."
            }
        }
    }

    static let sharedConfig = SecretStoreConfiguration(
        serviceNamePrefix: "sh.glas",
        accessGroup: resolvedAccessGroup,
        legacyServiceNamePrefixes: ["app.glassdb"],
        useDataProtectionKeychain: useDataProtectionKeychain
    )

    static let appOnlyConfig = SecretStoreConfiguration(
        serviceNamePrefix: "app.glassdb.private",
        accessGroup: nil,
        useDataProtectionKeychain: useDataProtectionKeychain
    )

    static let authenticatedConfig = SecretStoreConfiguration(
        serviceNamePrefix: "app.glassdb.protected",
        accessGroup: nil,
        useDataProtectionKeychain: useDataProtectionKeychain
    )

    #if os(macOS)
    private static let useDataProtectionKeychain = true
    #else
    private static let useDataProtectionKeychain = false
    #endif

    private static var resolvedAccessGroup: String? {
        #if os(visionOS)
        // The Vision Pro target uses Xcode's generated plist; its provisioning
        // profile and entitlement are fixed to the shared Glass team group.
        return "7JQGQ7CRH8.sh.glas.shared"
        #else
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: accessGroupInfoKey
        ) as? String else { return nil }
        return validatedSharedAccessGroup(rawValue)
        #endif
    }

    static var sharedCredentialAccessAvailable: Bool {
        sharedConfig.accessGroup != nil
    }

    static func validatedSharedAccessGroup(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        let components = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2,
              components[0].count == 10,
              components[0].allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }),
              components[1] == "sh.glas.shared" else {
            return nil
        }
        return value
    }


    /// SSH keys and host pins remain intentionally shared with glas.sh.
    static let config = sharedConfig

    // MARK: - Database Password

    static func savePassword(_ password: String, for connection: DatabaseConnectionConfig) throws {
        try save(password, account: databaseAccount(for: connection.id), descriptor: descriptor(
            for: connection.databaseCredentialPolicy,
            kind: .databasePassword
        ))
    }

    static func retrievePassword(for connection: DatabaseConnectionConfig) throws -> String {
        let storage = descriptor(for: connection.databaseCredentialPolicy, kind: .databasePassword)
        do {
            return try retrieveStablePassword(
                account: databaseAccount(for: connection.id),
                descriptor: storage
            )
        } catch GlasSecretStore.SecretStoreError.notFound {
            guard connection.databaseCredentialPolicy == .sharedWithGlas else {
                throw GlasSecretStore.SecretStoreError.notFound
            }
            let password = try retrieveLegacyPassword(
                account: legacyDatabaseAccount(for: connection),
                primaryService: sharedConfig.passwordsService,
                legacySuffix: "passwords"
            )
            try savePassword(password, for: connection)
            return password
        }
    }

    static func deletePassword(for connection: DatabaseConnectionConfig) throws {
        try delete(account: databaseAccount(for: connection.id), descriptor: descriptor(
            for: connection.databaseCredentialPolicy,
            kind: .databasePassword
        ))
    }

    // MARK: - SSH Password
    //
    // Deliberately absent. glassdb stored an SSH password per database connection
    // (`../glassdb/glassdb/KeychainManager.swift:249-297`). Under D7 the tunnel is the host's
    // Terminal service, which already holds that machine's credential; a second copy here
    // would be a second thing to rotate and a second thing to leak.

    /// Saves and verifies every destination before removing prior-policy records.
    /// Every touched record is snapshotted first so a later database/SSH write or
    /// cleanup failure restores the complete pre-mutation state.
    static func saveCredentials(
        databasePassword: String,
        for connection: DatabaseConnectionConfig,
        replacing previousConnection: DatabaseConnectionConfig?,
        store: CredentialMutationStore = .live
    ) throws -> CredentialPersistenceReport {
        var writes: [CredentialWrite] = []
        if !databasePassword.isEmpty {
            writes.append(CredentialWrite(
                value: databasePassword,
                account: databaseAccount(for: connection.id),
                destination: descriptor(for: connection.databaseCredentialPolicy, kind: .databasePassword),
                source: previousConnection.map {
                    descriptor(for: $0.databaseCredentialPolicy, kind: .databasePassword)
                }
            ))
        }

        var deletions: [CredentialLocation] = []
        for write in writes {
            if let source = write.source, !write.destination.matches(source) {
                deletions.append(CredentialLocation(account: write.account, descriptor: source))
            }
        }
        if let previousConnection,
           previousConnection.engine.supportsCredentials,
           !connection.engine.supportsCredentials {
            deletions.append(CredentialLocation(
                account: databaseAccount(for: previousConnection.id),
                descriptor: descriptor(
                    for: previousConnection.databaseCredentialPolicy,
                    kind: .databasePassword
                )
            ))
        }
        let snapshots = try applyCredentialMutation(
            writes: writes,
            deletions: deletions,
            store: store
        )
        return CredentialPersistenceReport(
            cleanupWarnings: [],
            rollbackReceipt: CredentialDeletionReceipt(snapshots: snapshots)
        )
    }

    static func deleteCredentials(
        for connection: DatabaseConnectionConfig,
        store: CredentialMutationStore = .live
    ) throws -> CredentialDeletionReceipt {
        var locations: [CredentialLocation] = []
        if connection.engine.supportsCredentials {
            locations.append(CredentialLocation(
                account: databaseAccount(for: connection.id),
                descriptor: descriptor(for: connection.databaseCredentialPolicy, kind: .databasePassword)
            ))
        }
        // A version-1 record may still have an SSH password glassdb wrote for it. This app
        // never writes one, but deleting the service must not leave that secret behind, so
        // every descriptor it could have been written under is swept.
        for policy in [CredentialStoragePolicy.sharedWithGlas, .appOnly, .requireAuthentication] {
            locations.append(CredentialLocation(
                account: sshAccount(for: connection.id),
                descriptor: descriptor(for: policy, kind: .sshPassword)
            ))
        }

        let snapshots = try snapshotCredentials(at: locations, store: store)
        do {
            for snapshot in snapshots where snapshot.value != nil {
                try store.delete(snapshot.account, snapshot.descriptor)
                guard try store.retrieve(snapshot.account, snapshot.descriptor) == nil else {
                    throw CredentialPolicyError.verificationFailed
                }
            }
        } catch {
            do {
                try restoreCredentialSnapshots(snapshots, store: store)
            } catch {
                throw CredentialPolicyError.mutationRollbackFailed
            }
            throw error
        }
        return CredentialDeletionReceipt(snapshots: snapshots)
    }

    static func restoreCredentials(
        _ receipt: CredentialDeletionReceipt,
        store: CredentialMutationStore = .live
    ) throws {
        do {
            try restoreCredentialSnapshots(receipt.snapshots, store: store)
        } catch {
            throw CredentialPolicyError.mutationRollbackFailed
        }
    }

    // MARK: - SSH Keys
    //
    // Deliberately absent. glassdb kept its own private-key store
    // (`../glassdb/glassdb/KeychainManager.swift:431-445`) behind its own SSH Keys settings
    // page. The merged product has one SSH key catalog, owned by the capability that owns
    // `.ssh` and shown on its Connections settings page; a database service needs none.

    // MARK: - SSH Host Trust
    //
    // Deliberately absent. glassdb pinned the tunnel's host key here
    // (`../glassdb/glassdb/KeychainManager.swift:449-464`) because it opened its own SSH
    // connection. Under D7 the tunnel is the host's Terminal service, so the capability that
    // owns `.ssh` owns its trust store too; a second pinning path here would be a second place
    // for the same machine's key to disagree.

    // MARK: - Migration

    @discardableResult
    static func runMigrationsIfNeeded(
        connections: [DatabaseConnectionConfig],
        defaults: UserDefaults = .standard
    ) throws -> CredentialMigrationReport {
        let migrationManager = SecretStoreMigrationManager(config: config)
        migrationManager.runScaffoldIfNeeded()

        guard defaults.integer(forKey: credentialMigrationVersionKey) < currentCredentialMigrationVersion else {
            return CredentialMigrationReport(
                migratedDatabasePasswords: 0,
                migratedSSHPasswords: 0,
                failures: []
            )
        }

        var databaseCount = 0
        var failures: [String] = []

        for connection in connections {
            do {
                if try migrateLegacyCredentialIfPresent(
                    destinationAccount: databaseAccount(for: connection.id),
                    legacyAccount: legacyDatabaseAccount(for: connection),
                    primaryService: config.passwordsService,
                    legacySuffix: "passwords"
                ) {
                    databaseCount += 1
                }
            } catch {
                failures.append("Database password for ‘\(connection.name)’ was not migrated.")
            }

        }

        let report = CredentialMigrationReport(
            migratedDatabasePasswords: databaseCount,
            migratedSSHPasswords: 0,
            failures: failures
        )
        if report.isSuccessful {
            defaults.set(currentCredentialMigrationVersion, forKey: credentialMigrationVersionKey)
        } else {
            throw CredentialMigrationError(failures: failures)
        }
        return report
    }

    static func databaseAccount(for connectionID: UUID) -> String {
        GlassFamilyCredentialAccount.databasePassword(profileID: connectionID)
    }

    static func sshAccount(for connectionID: UUID) -> String {
        GlassFamilyCredentialAccount.sshPassword(profileID: connectionID)
    }

    static func legacyDatabaseAccount(for connection: DatabaseConnectionConfig) -> String {
        "\(connection.username)@\(connection.host):\(connection.port)"
    }

    /// Compatibility identity published only for an explicitly shared SSH
    /// password. glas.sh uses this endpoint-scoped alias while glassdb retains
    /// its UUID primary record, so either app can import the same shared value.
    /// Reads the shared endpoint record behind a catalog identity.
    ///
    /// A connection authenticating with a credential glas.sh owns has no
    /// private copy of the secret by design, so test and connect read it from
    /// the shared account instead of from a field the user never filled in.
    static func retrieveSharedSSHPassword(
        for identity: SharedSSHCredentialIdentity
    ) throws -> String {
        try retrieveLegacyPassword(
            account: identity.id,
            primaryService: sharedConfig.sshPasswordsService,
            legacySuffix: "sshpasswords"
        )
    }

    // MARK: - Shared SSH Credential Catalog

    /// Endpoint identity of a shared Glass-family SSH password record — the
    /// "ssh:user@host:port" accounts either app publishes into the shared
    /// access group. Identity only; no secret material.
    struct SharedSSHCredentialIdentity: Identifiable, Hashable, Sendable {
        let username: String
        let host: String
        let port: Int

        var id: String { "ssh:\(username)@\(host):\(port)" }

        /// Host leads so the machine is scannable at a glance; the port
        /// appears only when nonstandard.
        var displayName: String {
            port == 22 ? "\(host) — \(username)" : "\(host):\(port) — \(username)"
        }
    }

    /// Parses a shared endpoint account of the form "ssh:user@host:port".
    /// Canonical UUID-profile accounts and malformed records return nil. The
    /// port separator is the last colon, so IPv6 hosts parse intact.
    static func sharedSSHCredentialIdentity(
        fromAccount account: String
    ) -> SharedSSHCredentialIdentity? {
        guard account.hasPrefix("ssh:") else { return nil }
        let body = account.dropFirst(4)
        guard let atIndex = body.firstIndex(of: "@") else { return nil }
        let username = String(body[..<atIndex])
        let hostPort = body[body.index(after: atIndex)...]
        guard let colonIndex = hostPort.lastIndex(of: ":") else { return nil }
        let host = String(hostPort[..<colonIndex])
        let portText = hostPort[hostPort.index(after: colonIndex)...]
        guard !username.isEmpty, !host.isEmpty,
              let port = Int(portText), (1...65_535).contains(port) else {
            return nil
        }
        return SharedSSHCredentialIdentity(username: username, host: host, port: port)
    }

    /// Lists the endpoint identities of shared SSH password records visible
    /// in the Glass-family access group — credentials either app published.
    /// Reads account attributes only; secret data never leaves the Keychain.
    static func sharedSSHCredentialIdentities() -> [SharedSSHCredentialIdentity] {
        guard let accessGroup = sharedConfig.accessGroup else { return [] }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: sharedConfig.sshPasswordsService,
            kSecAttrAccessGroup as String: accessGroup,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }
        let identities = Set(items.compactMap { item -> SharedSSHCredentialIdentity? in
            guard let account = item[kSecAttrAccount as String] as? String else { return nil }
            return sharedSSHCredentialIdentity(fromAccount: account)
        })
        return identities.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func descriptor(
        for policy: CredentialStoragePolicy,
        kind: CredentialKind
    ) -> CredentialStorageDescriptor {
        let config: SecretStoreConfiguration
        let accessPolicy: SecretAccessPolicy
        let prompt: String?
        let isShared: Bool
        switch policy {
        case .sharedWithGlas:
            config = sharedConfig
            accessPolicy = .standard
            prompt = nil
            isShared = config.accessGroup != nil
        case .appOnly:
            config = appOnlyConfig
            accessPolicy = .standard
            prompt = nil
            isShared = false
        case .requireAuthentication:
            config = authenticatedConfig
            accessPolicy = .userPresence
            prompt = kind == .databasePassword
                ? "Authenticate to use this database password."
                : "Authenticate to use this SSH password."
            isShared = false
        }
        let service = kind == .databasePassword
            ? config.passwordsService
            : config.sshPasswordsService
        return CredentialStorageDescriptor(
            service: service,
            config: config,
            accessPolicy: accessPolicy,
            authenticationPrompt: prompt,
            isSharedWithGlas: isShared
        )
    }

    private static func retrieveLegacyPassword(
        account: String,
        primaryService: String,
        legacySuffix: String,
        store: CredentialMigrationStore = .live
    ) throws -> String {
        do {
            return try store.retrievePassword(account, primaryService, config)
        } catch GlasSecretStore.SecretStoreError.notFound {
            // Only a verified absence permits lookup in the next legacy service.
        }
        for prefix in config.legacyServiceNamePrefixes {
            do {
                return try store.retrievePassword(
                    account,
                    "\(prefix).\(legacySuffix)",
                    config
                )
            } catch GlasSecretStore.SecretStoreError.notFound {
                continue
            }
        }
        throw GlasSecretStore.SecretStoreError.notFound
    }

    static func migrateLegacyCredentialIfPresent(
        destinationAccount: String,
        legacyAccount: String,
        primaryService: String,
        legacySuffix: String,
        store: CredentialMigrationStore = .live
    ) throws -> Bool {
        do {
            _ = try store.retrieveData(destinationAccount, primaryService, config)
            return false
        } catch GlasSecretStore.SecretStoreError.notFound {
            // Only a verified absence permits consulting legacy credentials.
        }

        let value: String
        do {
            value = try retrieveLegacyPassword(
                account: legacyAccount,
                primaryService: primaryService,
                legacySuffix: legacySuffix,
                store: store
            )
        } catch GlasSecretStore.SecretStoreError.notFound {
            return false
        }
        try store.savePassword(
            value,
            destinationAccount,
            primaryService,
            config
        )
        return true
    }

    private struct CredentialWrite {
        let value: String
        let account: String
        let destination: CredentialStorageDescriptor
        let source: CredentialStorageDescriptor?
    }

    private struct CredentialLocation {
        let account: String
        let descriptor: CredentialStorageDescriptor

        func matches(_ other: CredentialLocation) -> Bool {
            account == other.account && descriptor.matches(other.descriptor)
        }
    }

    private static func uniqueLocations(_ locations: [CredentialLocation]) -> [CredentialLocation] {
        locations.reduce(into: []) { result, location in
            if !result.contains(where: { $0.matches(location) }) {
                result.append(location)
            }
        }
    }

    private static func snapshotCredentials(
        at locations: [CredentialLocation],
        store: CredentialMutationStore
    ) throws -> [CredentialSnapshot] {
        try uniqueLocations(locations).map { location in
            CredentialSnapshot(
                account: location.account,
                descriptor: location.descriptor,
                value: try store.retrieve(location.account, location.descriptor)
            )
        }
    }

    private static func applyCredentialMutation(
        writes: [CredentialWrite],
        deletions: [CredentialLocation],
        store: CredentialMutationStore
    ) throws -> [CredentialSnapshot] {
        let locations = writes.map {
            CredentialLocation(account: $0.account, descriptor: $0.destination)
        } + deletions
        let snapshots = try snapshotCredentials(at: locations, store: store)
        do {
            for write in writes {
                try store.save(write.value, write.account, write.destination)
                let verified = try store.retrieve(write.account, write.destination)
                guard verified == write.value else { throw CredentialPolicyError.verificationFailed }
            }
            for deletion in uniqueLocations(deletions) {
                guard try store.retrieve(deletion.account, deletion.descriptor) != nil else { continue }
                try store.delete(deletion.account, deletion.descriptor)
                guard try store.retrieve(deletion.account, deletion.descriptor) == nil else {
                    throw CredentialPolicyError.verificationFailed
                }
            }
        } catch {
            do {
                try restoreCredentialSnapshots(snapshots, store: store)
            } catch {
                throw CredentialPolicyError.mutationRollbackFailed
            }
            throw error
        }
        return snapshots
    }

    private static func restoreCredentialSnapshots(
        _ snapshots: [CredentialSnapshot],
        store: CredentialMutationStore
    ) throws {
        for snapshot in snapshots.reversed() {
            if let value = snapshot.value {
                try store.save(value, snapshot.account, snapshot.descriptor)
                guard try store.retrieve(snapshot.account, snapshot.descriptor) == value else {
                    throw CredentialPolicyError.verificationFailed
                }
            } else if try store.retrieve(snapshot.account, snapshot.descriptor) != nil {
                try store.delete(snapshot.account, snapshot.descriptor)
                guard try store.retrieve(snapshot.account, snapshot.descriptor) == nil else {
                    throw CredentialPolicyError.verificationFailed
                }
            }
        }
    }

    private static func save(
        _ value: String,
        account: String,
        descriptor: CredentialStorageDescriptor
    ) throws {
        try KeychainOperations.savePassword(
            value,
            account: account,
            service: descriptor.service,
            config: descriptor.config,
            policy: descriptor.accessPolicy
        )
    }

    private static func delete(
        account: String,
        descriptor: CredentialStorageDescriptor
    ) throws {
        try KeychainOperations.deletePassword(
            account: account,
            service: descriptor.service,
            config: descriptor.config
        )
    }

    private static func retrieveStablePassword(
        account: String,
        descriptor: CredentialStorageDescriptor
    ) throws -> String {
        if descriptor.accessPolicy == .userPresence {
            let context = LAContext()
            var evaluationError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
                throw CredentialPolicyError.authenticationUnavailable(
                    evaluationError?.localizedDescription ?? "Configure a device passcode or biometric authentication and try again."
                )
            }
        }
        let data: Data
        do {
            data = try KeychainOperations.retrieveData(
                account: account,
                service: descriptor.service,
                config: descriptor.config,
                authenticationPrompt: descriptor.authenticationPrompt
            )
        } catch GlasSecretStore.SecretStoreError.notFound {
            throw GlasSecretStore.SecretStoreError.notFound
        } catch {
            if descriptor.accessPolicy == .userPresence {
                throw CredentialPolicyError.authenticationCancelledOrCredentialUnavailable
            }
            throw error
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw GlasSecretStore.SecretStoreError.encodingFailed
        }
        return value
    }
}

private extension KeychainManager.CredentialStorageDescriptor {
    func matches(_ other: KeychainManager.CredentialStorageDescriptor?) -> Bool {
        guard let other else { return false }
        return service == other.service && isSharedWithGlas == other.isSharedWithGlas
    }
}
