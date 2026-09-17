//
//  OpenSSHPublicKeyLineTests.swift
//  Glass Power Tools — GlasSecretStoreTests
//
//  The key manager shows a fingerprint so a user can compare it with what `ssh-keygen -lf` or a
//  server reports. A fingerprint that is merely self-consistent is worthless for that, so the
//  vector here was produced by OpenSSH itself and pasted in:
//
//      ssh-keygen -t ed25519 -N "" -C glass-test -f k
//      ssh-keygen -lf k.pub
//      256 SHA256:dwZSTpODvDloFr6s7D6NOzR/+JhKxFaG6jgQCzW9bKk glass-test (ED25519)
//
//  The key is a throwaway generated for this test and holds nothing.
//

import Foundation
import Testing
@testable import GlasSecretStore

@Suite("OpenSSH public key lines")
struct OpenSSHPublicKeyLineTests {
    static let line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPul03MQqt3wecXgHLPsgIoyPud7YN/SERCWtX/ckfdu glass-test"
    static let fingerprint = "SHA256:dwZSTpODvDloFr6s7D6NOzR/+JhKxFaG6jgQCzW9bKk"

    @Test func matchesOpenSSHsOwnFingerprint() {
        #expect(OpenSSHPublicKeyLine.sha256Fingerprint(in: Self.line) == Self.fingerprint)
    }

    @Test func readsTheAlgorithmToken() {
        #expect(OpenSSHPublicKeyLine.algorithm(in: Self.line) == "ssh-ed25519")
    }

    /// The comment is not part of the key. Two files that differ only in what a user typed after
    /// the blob describe the same key and must fingerprint the same — otherwise renaming a key by
    /// re-exporting it would look like a different key to whoever is comparing.
    @Test func ignoresTheComment() {
        let noComment = Self.line.replacingOccurrences(of: " glass-test", with: "")
        let otherComment = noComment + " michael@somewhere-else"
        #expect(OpenSSHPublicKeyLine.sha256Fingerprint(in: noComment) == Self.fingerprint)
        #expect(OpenSSHPublicKeyLine.sha256Fingerprint(in: otherComment) == Self.fingerprint)
    }

    @Test func toleratesSurroundingWhitespaceAndTabs() {
        let padded = "  " + Self.line.replacingOccurrences(of: " AAAA", with: "\tAAAA") + "\n"
        #expect(OpenSSHPublicKeyLine.sha256Fingerprint(in: padded) == Self.fingerprint)
    }

    /// Nil, never a fingerprint of nothing. An empty blob hashes to a perfectly valid-looking
    /// `SHA256:…` string, and a key manager that prints one is lying with a straight face.
    @Test func refusesWhatIsNotAPublicKey() {
        for text in ["", "ssh-ed25519", "not a key at all", "ssh-ed25519 !!!not-base64!!!"] {
            #expect(OpenSSHPublicKeyLine.sha256Fingerprint(in: text) == nil, "accepted \"\(text)\"")
            #expect(OpenSSHPublicKeyLine.blob(in: text) == nil, "decoded \"\(text)\"")
        }
    }
}
