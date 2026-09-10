import Foundation
import Citadel
import NIOSSH
import Crypto
import _CryptoExtras
import GlasSecretStore

/// Derives the public half of stored key material for display and export, so capabilities never
/// need Citadel or NIOSSH themselves. Moved from glas.sh `SettingsManager.openSSHPublicKey(for:)`
/// (SettingsManager.swift:807-846); accepts the same three private-key encodings the
/// authentication builder does.
public enum SSHPublicKeys {
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
    public static func sha256Fingerprint(for material: SSHKeyMaterial) throws -> String {
        let line = try openSSHLine(for: material)
        let fields = line.split(separator: " ")
        guard fields.count >= 2, let blob = Data(base64Encoded: String(fields[1])) else {
            throw SSHTransportError.invalidPrivateKey("The derived public key could not be encoded.")
        }
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString()
        return "SHA256:" + digest.trimmingCharacters(in: CharacterSet(charactersIn: "="))
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
