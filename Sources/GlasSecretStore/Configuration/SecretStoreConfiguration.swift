//
//  SecretStoreConfiguration.swift
//  GlasSecretStore
//
//  Value-type configuration for Keychain operations.
//  Each app creates its own configuration at launch.
//

import Foundation
import Security

/// Per-item protection applied in addition to the configuration's access
/// group and service isolation.
public enum SecretAccessPolicy: String, Codable, CaseIterable, Sendable {
    /// Available whenever the configured Keychain accessibility permits.
    case standard

    /// Requires device-owner authentication for every retrieval.
    case userPresence
}

/// Canonical UUID-scoped account names for credentials intentionally shared by
/// Glass-family apps. Keeping this identity contract in GlasSecretStore prevents
/// each app from growing a subtly incompatible account namespace while retaining
/// per-profile isolation for otherwise identical endpoints.
public enum GlassFamilyCredentialAccount: Sendable {
    public static func rdpCredential(credentialID: UUID) -> String {
        "rdp:\(credentialID.uuidString.lowercased())"
    }

    public static func databasePassword(profileID: UUID) -> String {
        "database:\(profileID.uuidString.lowercased())"
    }

    public static func sshPassword(profileID: UUID) -> String {
        "ssh:\(profileID.uuidString.lowercased())"
    }
}

/// App sharing and device mobility are independent choices. Existing callers
/// remain device-only. Sync uses Apple's eligible Keychain item path.
public enum SecretMobilityPolicy: String, Codable, CaseIterable, Sendable {
    case deviceOnly
    case iCloudKeychain
}

public struct SecretStoreConfiguration: @unchecked Sendable {
    /// Primary service name prefix (e.g. "sh.glas").
    /// Keychain service names are derived as "\(prefix).passwords", "\(prefix).sshkeys.private", etc.
    public let serviceNamePrefix: String

    /// Keychain access group for cross-app sharing (e.g. "TEAMID.sh.glas.shared").
    /// When non-nil, injected into every SecItem* call.
    public let accessGroup: String?

    /// Keychain accessibility level.
    public let accessibility: CFString
    public let mobilityPolicy: SecretMobilityPolicy

    /// Migration marker comment stamped on migrated items.
    public let migrationMarkerComment: String

    /// Legacy service name prefixes to search during fallback retrieval.
    /// For example, glassdb passes `["app.glassdb"]` to find items saved before unification.
    public let legacyServiceNamePrefixes: [String]

    /// Opts macOS callers into the modern data-protection Keychain. Other
    /// Apple platforms already use it and ignore this setting.
    public let useDataProtectionKeychain: Bool

    public init(
        serviceNamePrefix: String = "sh.glas",
        accessGroup: String? = nil,
        accessibility: CFString? = nil,
        migrationMarkerComment: String = "sh.glas.secretstore.v1",
        legacyServiceNamePrefixes: [String] = [],
        useDataProtectionKeychain: Bool = false,
        mobilityPolicy: SecretMobilityPolicy = .deviceOnly
    ) {
        self.serviceNamePrefix = serviceNamePrefix
        self.accessGroup = accessGroup
        self.mobilityPolicy = mobilityPolicy
        self.accessibility = accessibility ?? (mobilityPolicy == .iCloudKeychain
            ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        self.migrationMarkerComment = migrationMarkerComment
        self.legacyServiceNamePrefixes = legacyServiceNamePrefixes
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    // MARK: - Derived Service Names

    public var rdpCredentialsService: String { "\(serviceNamePrefix).rdp.credentials" }
    public var passwordsService: String { "\(serviceNamePrefix).passwords" }
    public var sshPasswordsService: String { "\(serviceNamePrefix).sshpasswords" }
    public var sshKeysPrivateService: String { "\(serviceNamePrefix).sshkeys.private" }
    public var sshKeysPassphraseService: String { "\(serviceNamePrefix).sshkeys.passphrase" }
    public var sealedP256Service: String { "\(serviceNamePrefix).sshkeys.sealedp256" }
    public var sealedP256TagService: String { "\(serviceNamePrefix).sshkeys.sealedp256.tag" }
    public var sshHostTrustService: String { "\(serviceNamePrefix).ssh.hosttrust" }

    // MARK: - Mobility Eligibility

    /// The services `KeychainOperations.validateMobility` permits under `.iCloudKeychain`.
    ///
    /// **This is public because it is a contract, not an implementation detail.** It used to be a
    /// literal inside `validateMobility`, and a caller had no way to ask whether the service it was
    /// about to write was on it — so enabling D18 on a configuration that also stored host-key pins
    /// made every pin and every lookup throw `ineligibleService`, and nothing failed until SSH
    /// stopped connecting altogether. A test that rebuilt the list by hand could not notice either.
    /// Anything that wants to know now reads the same property the validator does.
    ///
    /// `sealedP256Service` and `sealedP256TagService` are deliberately absent: a Secure Enclave
    /// token is usable only by the chip that minted it, so a copy on another device would be a key
    /// listed as available and guaranteed to fail.
    public var synchronizableServices: Set<String> {
        [
            passwordsService,
            sshPasswordsService,
            rdpCredentialsService,
            sshKeysPrivateService,
            sshKeysPassphraseService,
            // D23: a pinned host key is a *public* key — the fingerprint `ssh-keygen` prints, not a
            // secret. Trusting a machine on the Mac has to mean trusting it on the Vision Pro, or
            // the continuity requirement ends at "you still have to re-approve every host".
            sshHostTrustService,
        ]
    }
}
