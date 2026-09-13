import Foundation
import Security

public enum CredentialMobilityError: Error, Equatable, LocalizedError, Sendable {
    case deviceBoundProtection
    case incompatibleAccessibility
    case ineligibleService
    case invalidCredential
    case conflictingDestination
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .deviceBoundProtection: "Authentication-protected credentials must stay on this device."
        case .incompatibleAccessibility: "The selected Keychain accessibility does not permit iCloud synchronization."
        case .ineligibleService: "This kind of secure item is not eligible for iCloud synchronization."
        case .invalidCredential: "The remote desktop credential is invalid or exceeds its storage limit."
        case .conflictingDestination: "A different credential already exists at the destination. Both copies were preserved."
        case .verificationFailed: "The credential could not be verified. The source was preserved."
        }
    }
}

/// Secret material is never Codable or part of connection/host metadata.
public struct RDPCredential: Sendable {
    public let username: String
    public let domain: String?
    public let password: SecureBytes

    public init(username: String, domain: String? = nil, password: SecureBytes) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.domain = domain.flatMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        self.password = password
    }

    public init(username: String, domain: String? = nil, password: String) {
        self.init(username: username, domain: domain, password: SecureBytes(Data(password.utf8)))
    }

    fileprivate func validate() throws {
        let bytes = password.toData()
        guard !username.isEmpty, username.utf8.count <= 1024,
              (domain?.utf8.count ?? 0) <= 1024, password.count <= 64 * 1024,
              !username.contains("\0"), !(domain?.contains("\0") ?? false),
              !bytes.contains(0), String(data: bytes, encoding: .utf8) != nil else {
            throw CredentialMobilityError.invalidCredential
        }
    }
}

public enum RDPCredentialAvailability: Equatable, Sendable {
    case available
    /// Absence is not evidence of whether iCloud has finished syncing.
    case missing
    case locked
    case authenticationRequired
    case invalidPolicy
    case failed(OSStatus)
}

public enum RDPCredentialMigrationResult: Equatable, Sendable {
    case copiedSourceRetained
    case matchingDestinationSourceRetained
}

// Same synchronous injected-operation pattern used by SSHKeyKeychainStore.
struct RDPCredentialOperations: @unchecked Sendable {
    let read: (String, String, SecretStoreConfiguration, String?, Bool) throws -> Data
    let save: (Data, String, String, SecretStoreConfiguration, SecretAccessPolicy) throws -> Void
    let add: (Data, String, String, SecretStoreConfiguration, SecretAccessPolicy) throws -> Bool
    let delete: (String, String, SecretStoreConfiguration) throws -> Void
    static let live = Self(
        read: { account, service, config, prompt, allowUI in
            try KeychainOperations.retrieveData(account: account, service: service, config: config,
                                               authenticationPrompt: prompt, allowAuthenticationUI: allowUI)
        },
        save: { try KeychainOperations.saveData($0, account: $1, service: $2, config: $3, policy: $4) },
        add: { try KeychainOperations.addDataIfAbsent($0, account: $1, service: $2, config: $3, policy: $4) },
        delete: { try KeychainOperations.deleteItem(account: $0, service: $1, config: $2) }
    )
}

public enum RDPCredentialStore: Sendable {
    private struct Stored: Codable {
        let version: UInt16
        let username: String
        let domain: String?
        let password: Data
    }

    public static func save(_ credential: RDPCredential, for credentialID: UUID,
                            config: SecretStoreConfiguration, policy: SecretAccessPolicy = .standard) throws {
        try save(credential, for: credentialID, config: config, policy: policy, operations: .live)
    }

    static func save(_ credential: RDPCredential, for credentialID: UUID,
                     config: SecretStoreConfiguration, policy: SecretAccessPolicy = .standard,
                     operations: RDPCredentialOperations) throws {
        try validate(config, policy)
        try credential.validate()
        let data = try encoded(credential)
        try operations.save(data, account(credentialID), service(config, policy), config, policy)
    }

    public static func retrieve(for credentialID: UUID, config: SecretStoreConfiguration,
                                policy: SecretAccessPolicy = .standard,
                                authenticationPrompt: String? = nil) throws -> RDPCredential {
        try retrieve(for: credentialID, config: config, policy: policy,
                     authenticationPrompt: authenticationPrompt, operations: .live)
    }

    static func retrieve(for credentialID: UUID, config: SecretStoreConfiguration,
                         policy: SecretAccessPolicy = .standard, authenticationPrompt: String? = nil,
                         operations: RDPCredentialOperations) throws -> RDPCredential {
        try validate(config, policy)
        return try decoded(operations.read(account(credentialID), service(config, policy), config,
                                           authenticationPrompt, true))
    }

    public static func delete(for credentialID: UUID, config: SecretStoreConfiguration,
                              policy: SecretAccessPolicy = .standard) throws {
        try validate(config, policy)
        try RDPCredentialOperations.live.delete(account(credentialID), service(config, policy), config)
    }

    public static func availability(for credentialID: UUID, config: SecretStoreConfiguration,
                                    policy: SecretAccessPolicy = .standard) -> RDPCredentialAvailability {
        availability(for: credentialID, config: config, policy: policy, operations: .live)
    }

    static func availability(for credentialID: UUID, config: SecretStoreConfiguration,
                             policy: SecretAccessPolicy = .standard,
                             operations: RDPCredentialOperations) -> RDPCredentialAvailability {
        do {
            try validate(config, policy)
            _ = try decoded(operations.read(account(credentialID), service(config, policy), config, nil, false))
            return .available
        } catch SecretStoreError.notFound { return .missing
        } catch SecretStoreError.queryFailed(let status) {
            switch status {
            case errSecInteractionNotAllowed: return policy == .userPresence ? .authenticationRequired : .locked
            case errSecAuthFailed, errSecUserCanceled: return .authenticationRequired
            default: return .failed(status)
            }
        } catch CredentialMobilityError.invalidCredential { return .failed(errSecDecode)
        } catch is CredentialMobilityError { return .invalidPolicy
        } catch { return .failed(errSecDecode) }
    }

    /// Explicit forward migration: add-if-absent and verify the new record before
    /// the caller commits its non-secret storage policy. Never removes the source
    /// or overwrites a conflicting/concurrently created destination. Keeping the
    /// source makes interrupted metadata commits and older app versions recoverable.
    public static func prepareMobilityMigration(for credentialID: UUID,
                                                from source: SecretStoreConfiguration,
                                                to destination: SecretStoreConfiguration) throws -> RDPCredentialMigrationResult {
        try prepareMobilityMigration(for: credentialID, from: source, to: destination, operations: .live)
    }

    static func prepareMobilityMigration(for credentialID: UUID,
                                         from source: SecretStoreConfiguration,
                                         to destination: SecretStoreConfiguration,
                                         operations: RDPCredentialOperations) throws -> RDPCredentialMigrationResult {
        try validate(source, .standard)
        try validate(destination, .standard)
        let account = account(credentialID)
        let sourceBytes = try operations.read(account, source.rdpCredentialsService, source, nil, true)
        let sourceCredential = try decoded(sourceBytes)
        let canonicalSource = try encoded(sourceCredential)
        let didAdd = try operations.add(canonicalSource, account, destination.rdpCredentialsService,
                                        destination, .standard)
        let destinationBytes = try operations.read(account, destination.rdpCredentialsService, destination, nil, true)
        guard try encoded(decoded(destinationBytes)) == canonicalSource else {
            throw didAdd ? CredentialMobilityError.verificationFailed : .conflictingDestination
        }
        return didAdd ? .copiedSourceRetained : .matchingDestinationSourceRetained
    }

    private static func account(_ id: UUID) -> String {
        GlassFamilyCredentialAccount.rdpCredential(credentialID: id)
    }

    private static func service(_ config: SecretStoreConfiguration, _ policy: SecretAccessPolicy) -> String {
        // Access-control changes cannot safely use SecItemUpdate on the same
        // identity. Distinct storage prevents weakening/ignoring user presence.
        config.rdpCredentialsService + (policy == .userPresence ? ".protected" : "")
    }

    private static func validate(_ config: SecretStoreConfiguration, _ policy: SecretAccessPolicy) throws {
        try KeychainOperations.validateMobility(config: config, service: config.rdpCredentialsService, policy: policy)
    }

    private static func encoded(_ credential: RDPCredential) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Stored(version: 1, username: credential.username,
                                         domain: credential.domain, password: credential.password.toData()))
    }

    private static func decoded(_ data: Data) throws -> RDPCredential {
        guard data.count <= 128 * 1024 else { throw CredentialMobilityError.invalidCredential }
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        guard stored.version == 1 else { throw CredentialMobilityError.invalidCredential }
        let credential = RDPCredential(username: stored.username, domain: stored.domain,
                                       password: SecureBytes(stored.password))
        try credential.validate()
        return credential
    }
}
