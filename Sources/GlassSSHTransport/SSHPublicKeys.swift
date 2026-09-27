import Foundation
@preconcurrency import Citadel
@preconcurrency import NIOSSH
import Crypto
import _CryptoExtras
import GlasSecretStore

/// Derives the public half of stored key material for display and export, so capabilities never
/// need Citadel or NIOSSH themselves. Moved from glas.sh `SettingsManager.openSSHPublicKey(for:)`
/// (SettingsManager.swift:807-846); accepts the same three private-key encodings the
/// authentication builder does.
/// The key algorithm an OpenSSH private-key file declares in its header, before any decoding.
/// Consumers use it for import-form checks; full derivation is `SSHPublicKeys.algorithm(for:)`.
public enum SSHDeclaredKeyType: String, Sendable, Hashable, CaseIterable {
    case rsa = "ssh-rsa"
    case ed25519 = "ssh-ed25519"
    case ecdsaP256 = "ecdsa-sha2-nistp256"
    case ecdsaP384 = "ecdsa-sha2-nistp384"
    case ecdsaP521 = "ecdsa-sha2-nistp521"

    public var displayName: String {
        switch self {
        case .rsa: "RSA"
        case .ed25519: "ED25519"
        case .ecdsaP256: "ECDSA P-256"
        case .ecdsaP384: "ECDSA P-384"
        case .ecdsaP521: "ECDSA P-521"
        }
    }

    /// Whether a key of this type **imported from a file** can sign in (`SSHAuthenticationBuilder`
    /// reads OpenSSH RSA and Ed25519 keys). P-256 signs in only as a key made in the Secure Enclave,
    /// which never passes through a file; an imported P-256 key was shown as usable and then
    /// refused on Save (2026-09-27).
    public var isSupportedForAuthentication: Bool {
        switch self {
        case .rsa, .ed25519: true
        case .ecdsaP256, .ecdsaP384, .ecdsaP521: false
        }
    }

    init?(_ citadel: SSHKeyType) { self.init(rawValue: citadel.rawValue) }
}

/// Why a private-key header could not be read (`SSHPublicKeys.declaredKeyType(inOpenSSHPrivateKey:)`).
public enum SSHKeyHeaderError: Error, Sendable, Equatable {
    /// Not an OpenSSH private key (missing or wrong PEM armour).
    case notAnOpenSSHPrivateKey
    /// Armour present but the header block does not parse.
    case malformedHeader
    /// The header names a type the engine does not model.
    case unsupportedKeyType(String)
}

public enum SSHPublicKeys {
    /// Reads only the OpenSSH private-key header (armour, magic, key type) — no key material is
    /// decoded and no passphrase is needed — so import forms can classify a key before deciding
    /// what to do with it. Wraps Citadel's `SSHKeyDetection.detectPrivateKeyType`.
    public static func declaredKeyType(inOpenSSHPrivateKey text: String) throws -> SSHDeclaredKeyType {
        let detected: SSHKeyType
        do {
            detected = try SSHKeyDetection.detectPrivateKeyType(from: text)
        } catch let error as SSHKeyDetectionError {
            switch error {
            case .invalidPrivateKeyFormat, .invalidKeyFormat: throw SSHKeyHeaderError.notAnOpenSSHPrivateKey
            case .unsupportedKeyType(let type): throw SSHKeyHeaderError.unsupportedKeyType(type ?? "unknown")
            case .malformedKey, .encryptedPrivateKey, .passphraseRequired, .incorrectPassphrase: throw SSHKeyHeaderError.malformedHeader
            }
        }
        guard let type = SSHDeclaredKeyType(detected) else {
            throw SSHKeyHeaderError.unsupportedKeyType(detected.rawValue)
        }
        return type
    }

    /// Same, over stored material (decodes only the UTF-8 text, never the key).
    public static func declaredKeyType(in material: SSHKeyMaterial) throws -> SSHDeclaredKeyType {
        guard let text = material.privateKey.toUTF8String() else { throw SSHTransportError.invalidCredentialEncoding }
        return try declaredKeyType(inOpenSSHPrivateKey: text)
    }

    /// The `authorized_keys` line for `material`, e.g. `ssh-ed25519 AAAA… comment`.
    public static func openSSHLine(for material: SSHKeyMaterial, comment: String? = nil) throws -> String {
        let key = try publicKey(for: material)
        let line = String(openSSHPublicKey: key)
        guard let comment, !comment.isEmpty else { return line }
        return "\(line) \(comment)"
    }

    /// The key-type token of the public key (`ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-nistp256`).
    public static func algorithm(for material: SSHKeyMaterial) throws -> String {
        let line = try openSSHLine(for: material)
        return String(line.split(separator: " ", maxSplits: 1).first ?? "")
    }

    /// `SHA256:…` fingerprint in OpenSSH's presentation (unpadded base64).
    ///
    /// Reads the derived line through `OpenSSHPublicKeyLine`, the same parser the key manager's
    /// display fingerprint goes through, so a key cannot present one fingerprint here and another
    /// in the library.
    public static func sha256Fingerprint(for material: SSHKeyMaterial) throws -> String {
        let line = try openSSHLine(for: material)
        guard let fingerprint = OpenSSHPublicKeyLine.sha256Fingerprint(in: line) else {
            throw SSHTransportError.invalidPrivateKey("The derived public key could not be encoded.")
        }
        return fingerprint
    }

    static func publicKey(for material: SSHKeyMaterial) throws -> NIOSSHPublicKey {
        guard let privateKeyString = material.privateKey.toUTF8String() else {
            throw SSHTransportError.invalidCredentialEncoding
        }
        let passphraseData = material.passphrase?.toData()
        do {
            if privateKeyString.hasPrefix("TRUE_SE_P256:") {
                let payload = String(privateKeyString.dropFirst("TRUE_SE_P256:".count))
                guard let dataRep = Data(base64Encoded: payload) else {
                    throw SSHTransportError.invalidPrivateKey("Invalid true Secure Enclave P-256 data representation.")
                }
                let seKey = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: dataRep)
                return NIOSSHPrivateKey(secureEnclaveP256Key: seKey).publicKey
            }
            if privateKeyString.hasPrefix("SECURE_ENCLAVE_P256:") {
                let payload = String(privateKeyString.dropFirst("SECURE_ENCLAVE_P256:".count))
                guard let rawData = Data(base64Encoded: payload) else {
                    throw SSHTransportError.invalidPrivateKey("Invalid Secure Enclave P-256 payload.")
                }
                return NIOSSHPrivateKey(p256Key: try P256.Signing.PrivateKey(rawRepresentation: rawData)).publicKey
            }
            let keyType = try SSHKeyDetection.detectPrivateKeyType(from: privateKeyString)
            switch keyType {
            case .rsa:
                return NIOSSHPrivateKey(custom: try Insecure.RSA.PrivateKey(sshRsa: privateKeyString, decryptionKey: passphraseData)).publicKey
            case .ed25519:
                return NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(sshEd25519: privateKeyString, decryptionKey: passphraseData)).publicKey
            default:
                throw SSHTransportError.unsupportedKeyType(keyType.description)
            }
        } catch let error as SSHTransportError {
            throw error
        } catch {
            throw SSHTransportError.invalidPrivateKey("The stored key material could not be decoded.")
        }
    }
}
