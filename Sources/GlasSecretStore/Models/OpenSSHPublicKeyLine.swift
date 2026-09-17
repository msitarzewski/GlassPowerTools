//
//  OpenSSHPublicKeyLine.swift
//  GlasSecretStore
//
//  An `authorized_keys` line — `ssh-ed25519 AAAA… comment` — read for display.
//
//  The key manager shows a fingerprint, and a fingerprint is taken over the *wire-format blob*
//  inside that line rather than over the line's text: two files that differ only in their comment
//  describe the same key and must fingerprint the same. The digest itself is
//  `PinnedSSHHostKey.sha256Fingerprint(for:)`, which already presents OpenSSH's unpadded base64 —
//  this is the parser in front of it, not a second implementation of it.
//

import Foundation

public enum OpenSSHPublicKeyLine {

    /// The key-type token, e.g. `ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-nistp256`.
    public static func algorithm(in line: String) -> String? {
        fields(in: line).first.map(String.init)
    }

    /// The wire-format public key the fingerprint is taken over.
    ///
    /// Nil rather than empty when the line is not a public key: an empty `Data` would hash to a
    /// perfectly valid-looking fingerprint of nothing, which is exactly the kind of confident wrong
    /// answer a key manager must not give.
    public static func blob(in line: String) -> Data? {
        let fields = fields(in: line)
        guard fields.count >= 2 else { return nil }
        return Data(base64Encoded: String(fields[1]))
    }

    /// `SHA256:…` in OpenSSH's own presentation, or nil when `line` is not a public key.
    public static func sha256Fingerprint(in line: String) -> String? {
        blob(in: line).map(PinnedSSHHostKey.sha256Fingerprint(for:))
    }

    private static func fields(in line: String) -> [Substring] {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
    }
}
