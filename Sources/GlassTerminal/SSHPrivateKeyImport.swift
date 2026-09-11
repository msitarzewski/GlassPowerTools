//
//  SSHPrivateKeyImport.swift
//  Glass Power Tools — GlassTerminal
//
//  User requirement (2026-09-10): "We need a way to choose a file instead of a paste." Reads a
//  private-key file the user picked, classifies it through the engine's header probe, and tells
//  the form whether a passphrase is needed and what comment the key carries — without keeping
//  the path or the contents anywhere but the form's state until `addSSHKey` stores them.
//

import Foundation
import GlassSSHTransport

struct SSHPrivateKeyInspection: Equatable, Sendable {
    let keyType: SSHDeclaredKeyType
    /// True when the OpenSSH container names a cipher; the comment is then unreadable until the
    /// passphrase is supplied, so the form asks for it.
    let isPassphraseProtected: Bool
    /// The key's own comment (typically `user@host`), when the private section is readable.
    let comment: String?
}

enum SSHPrivateKeyImportError: LocalizedError, Equatable {
    case unreadable
    case tooLarge(Int)
    case notText
    case notAnOpenSSHPrivateKey
    case unsupportedKeyType(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file could not be read."
        case .tooLarge(let bytes): "The file is \(bytes) bytes; a private key is far smaller. Choose the key file itself."
        case .notText: "The file is not a text private key."
        case .notAnOpenSSHPrivateKey: "This is not an OpenSSH private key (expected a BEGIN OPENSSH PRIVATE KEY block)."
        case .unsupportedKeyType(let type): "Keys of type \(type) are not supported."
        }
    }
}

enum SSHPrivateKeyImport {
    /// Private keys are a few hundred bytes to a few kilobytes; anything larger is the wrong file.
    static let maximumFileSize = 64 * 1024

    /// Reads a user-chosen file inside its security scope and returns the key text plus what the
    /// header says about it. The caller keeps the text only in view state.
    static func read(from url: URL) throws -> (text: String, inspection: SSHPrivateKeyInspection) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Refuse by size before loading anything: a mischosen multi-gigabyte file must not be
        // read into memory just to be rejected.
        let size: Int
        do { size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 } catch { throw SSHPrivateKeyImportError.unreadable }
        guard size <= maximumFileSize else { throw SSHPrivateKeyImportError.tooLarge(size) }
        let data: Data
        do { data = try Data(contentsOf: url, options: [.uncached]) } catch { throw SSHPrivateKeyImportError.unreadable }
        guard data.count <= maximumFileSize else { throw SSHPrivateKeyImportError.tooLarge(data.count) }
        guard let text = String(data: data, encoding: .utf8) else { throw SSHPrivateKeyImportError.notText }
        return (text, try inspect(text))
    }

    /// Header-only classification through the engine, plus the OpenSSH container's cipher name
    /// and (when unencrypted) the comment. Never derives or decrypts key material.
    static func inspect(_ text: String) throws -> SSHPrivateKeyInspection {
        let keyType: SSHDeclaredKeyType
        do {
            keyType = try SSHPublicKeys.declaredKeyType(inOpenSSHPrivateKey: text)
        } catch SSHKeyHeaderError.unsupportedKeyType(let type) {
            throw SSHPrivateKeyImportError.unsupportedKeyType(type)
        } catch {
            throw SSHPrivateKeyImportError.notAnOpenSSHPrivateKey
        }
        let container = OpenSSHContainer(text)
        return SSHPrivateKeyInspection(
            keyType: keyType,
            isPassphraseProtected: container?.isEncrypted ?? false,
            comment: container?.comment
        )
    }

    /// Suggested catalog name: the key's comment, else the file name.
    static func suggestedName(comment: String?, fileURL: URL) -> String {
        if let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return comment }
        return fileURL.deletingPathExtension().lastPathComponent
    }
}

/// Minimal reader for the `openssh-key-v1` container: cipher name and, for unencrypted keys, the
/// comment that follows the key pair. Field layout per PROTOCOL.key in OpenSSH.
private struct OpenSSHContainer {
    let isEncrypted: Bool
    let comment: String?

    init?(_ text: String) {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let begin = lines.firstIndex(where: { $0 == "-----BEGIN OPENSSH PRIVATE KEY-----" }),
              let end = lines[begin...].firstIndex(where: { $0 == "-----END OPENSSH PRIVATE KEY-----" }),
              let blob = Data(base64Encoded: lines[(begin + 1)..<end].joined()) else { return nil }
        var reader = Reader(blob)
        guard reader.skip("openssh-key-v1\0".utf8.count),
              let cipher = reader.string(), reader.string() != nil, reader.bytes() != nil,
              let keyCount = reader.uint32(), keyCount == 1, reader.bytes() != nil,
              let privateSection = reader.bytes() else { return nil }
        isEncrypted = cipher != "none"
        guard !isEncrypted else { comment = nil; return }
        var section = Reader(privateSection)
        guard section.uint32() != nil, section.uint32() != nil, let keyType = section.string() else { comment = nil; return }
        let fieldCount: Int
        switch keyType {
        case "ssh-ed25519": fieldCount = 2                 // public, private
        case "ssh-rsa": fieldCount = 6                      // n e d iqmp p q
        case let t where t.hasPrefix("ecdsa-sha2-"): fieldCount = 3   // curve, Q, d
        default: comment = nil; return
        }
        for _ in 0..<fieldCount { guard section.bytes() != nil else { comment = nil; return } }
        comment = section.string()
    }

    private struct Reader {
        private let data: Data
        private var offset: Int
        init(_ data: Data) { self.data = data; offset = 0 }
        mutating func skip(_ count: Int) -> Bool {
            guard data.count - offset >= count else { return false }
            offset += count; return true
        }
        mutating func uint32() -> UInt32? {
            guard data.count - offset >= 4 else { return nil }
            let slice = data[data.startIndex + offset ..< data.startIndex + offset + 4]
            offset += 4
            return slice.reduce(0) { $0 << 8 | UInt32($1) }
        }
        mutating func bytes() -> Data? {
            guard let length = uint32(), length <= 1 << 20, data.count - offset >= Int(length) else { return nil }
            let slice = data[data.startIndex + offset ..< data.startIndex + offset + Int(length)]
            offset += Int(length)
            return Data(slice)
        }
        mutating func string() -> String? {
            guard let bytes = bytes() else { return nil }
            return String(data: bytes, encoding: .utf8)
        }
    }
}
