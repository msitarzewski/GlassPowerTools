import Foundation
import GlasSecretStore
import GlassConnectionKit
import Citadel
import Crypto
import _CryptoExtras

/// A reference to a credential held in GlasSecretStore. No secret material crosses the
/// engine's public API: the transport resolves references itself at connect time.
public enum SSHCredentialReference: Sendable, Hashable, Codable {
    /// A password stored for the SSH profile with this identifier.
    case password(profileID: UUID)
    /// A private key (and optional passphrase) stored under this key identifier.
    case privateKey(keyID: UUID)
    /// SSH agent authentication. Not available in the Citadel path; resolves to an error.
    case agent
    /// An opaque reference a custom `SSHCredentialResolver` knows how to resolve.
    case custom(String)

    /// Bridges to the shared catalog's `HostServiceLink.credentialID` where one applies.
    public var credentialID: CredentialID? {
        switch self {
        case .password(let id), .privateKey(let id): return CredentialID(rawValue: id)
        case .agent, .custom: return nil
        }
    }

    public var usesPrivateKey: Bool {
        if case .privateKey = self { return true }
        return false
    }
}

/// Secret material as GlasSecretStore hands it out. Both payload types zero their memory.
public enum SSHResolvedCredential: @unchecked Sendable {
    case password(SecureBytes)
    case privateKey(SSHKeyMaterial)
}

/// Turns a reference into material. The default implementation reads GlasSecretStore; the
/// terminal can supply one that prompts for user presence first.
public protocol SSHCredentialResolver: Sendable {
    func resolve(_ reference: SSHCredentialReference, for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential
}

/// A Keychain location for an SSH password, in lookup order.
public struct SSHPasswordLocation: Sendable, Hashable {
    public var account: String
    public var service: String
    public init(account: String, service: String) {
        self.account = account
        self.service = service
    }
}

/// The GlasSecretStore-backed resolver. Passwords are looked up at each location in order
/// (glas.sh keeps a profile-specific record and a family-shared fallback); keys come from
/// `SSHKeyKeychainStore`.
public struct SecretStoreCredentialResolver: SSHCredentialResolver {
    public let configuration: SecretStoreConfiguration
    public let passwordLocations: @Sendable (_ profileID: UUID) -> [SSHPasswordLocation]

    public init(
        configuration: SecretStoreConfiguration,
        passwordLocations: (@Sendable (_ profileID: UUID) -> [SSHPasswordLocation])? = nil
    ) {
        self.configuration = configuration
        self.passwordLocations = passwordLocations ?? { profileID in
            [SSHPasswordLocation(
                account: GlassFamilyCredentialAccount.sshPassword(profileID: profileID),
                service: configuration.sshPasswordsService
            )]
        }
    }

    public func resolve(_ reference: SSHCredentialReference, for endpoint: SSHEndpoint) async throws -> SSHResolvedCredential {
        switch reference {
        case .password(let profileID):
            for location in passwordLocations(profileID) {
                do {
                    let password = try KeychainOperations.retrievePassword(
                        account: location.account, service: location.service, config: configuration
                    )
                    return .password(SecureBytes(Data(password.utf8)))
                } catch SecretStoreError.notFound {
                    continue
                }
            }
            throw SSHTransportError.credentialUnavailable("No password is stored for \(endpoint.username)@\(endpoint.displayAddress).")
        case .privateKey(let keyID):
            do {
                return .privateKey(try SSHKeyKeychainStore.retrieve(for: keyID, config: configuration))
            } catch SecretStoreError.notFound {
                throw SSHTransportError.credentialUnavailable("The SSH key for \(endpoint.username)@\(endpoint.displayAddress) was not found.")
            }
        case .agent:
            throw SSHTransportError.unsupportedAuthenticationMethod("SSH Agent authentication is unavailable in this release.")
        case .custom(let identifier):
            throw SSHTransportError.credentialUnavailable("No resolver handles the credential reference \(identifier).")
        }
    }
}

/// Builds Citadel's authentication method from resolved material. Moved from glas.sh
/// `SSHConnection.resolveAuthMethod` (Models.swift:2010-2075), including the two Secure
/// Enclave encodings and the RSA/Ed25519 detection.
enum SSHAuthenticationBuilder {
    static func method(
        username: String,
        reference: SSHCredentialReference,
        credential: SSHResolvedCredential
    ) throws -> SSHAuthenticationMethod {
        switch (reference, credential) {
        case (.password, .password(let password)):
            guard let decoded = password.toUTF8String() else {
                throw SSHTransportError.invalidCredentialEncoding
            }
            return .passwordBased(username: username, password: decoded)

        case (.privateKey, .privateKey(let keyMaterial)), (.custom, .privateKey(let keyMaterial)):
            do {
                guard let privateKeyString = keyMaterial.privateKey.toUTF8String() else {
                    throw SSHTransportError.invalidCredentialEncoding
                }
                let passphraseData = keyMaterial.passphrase?.toData()

                if privateKeyString.hasPrefix("TRUE_SE_P256:") {
                    // True Secure Enclave key — signing happens in hardware.
                    let payload = String(privateKeyString.dropFirst("TRUE_SE_P256:".count))
                    guard let dataRep = Data(base64Encoded: payload) else {
                        throw SSHTransportError.invalidPrivateKey("Invalid true Secure Enclave P-256 data representation.")
                    }
                    let seKey = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: dataRep)
                    return .secureEnclaveP256(username: username, privateKey: seKey)
                } else if privateKeyString.hasPrefix("SECURE_ENCLAVE_P256:") {
                    // Legacy wrapped Secure Enclave key — backward compatible.
                    let payload = String(privateKeyString.dropFirst("SECURE_ENCLAVE_P256:".count))
                    guard let rawData = Data(base64Encoded: payload) else {
                        throw SSHTransportError.invalidPrivateKey("Invalid Secure Enclave P-256 payload.")
                    }
                    let key = try P256.Signing.PrivateKey(rawRepresentation: rawData)
                    return .p256(username: username, privateKey: key)
                } else {
                    let keyType = try SSHKeyDetection.detectPrivateKeyType(from: privateKeyString)
                    switch keyType {
                    case .rsa:
                        let key = try Insecure.RSA.PrivateKey(sshRsa: privateKeyString, decryptionKey: passphraseData)
                        return .rsa(username: username, privateKey: key)
                    case .ed25519:
                        let key = try Curve25519.Signing.PrivateKey(sshEd25519: privateKeyString, decryptionKey: passphraseData)
                        return .ed25519(username: username, privateKey: key)
                    default:
                        throw SSHTransportError.unsupportedKeyType(keyType.description)
                    }
                }
            } catch let error as SSHTransportError {
                throw error
            } catch {
                throw SSHTransportError.invalidPrivateKey("The stored key material could not be decoded.")
            }

        case (.custom, .password(let password)):
            guard let decoded = password.toUTF8String() else {
                throw SSHTransportError.invalidCredentialEncoding
            }
            return .passwordBased(username: username, password: decoded)

        case (.agent, _):
            throw SSHTransportError.unsupportedAuthenticationMethod("SSH Agent authentication is unavailable in this release.")

        case (.password, .privateKey), (.privateKey, .password):
            throw SSHTransportError.credentialUnavailable("The resolved credential does not match the requested authentication method.")
        }
    }
}
