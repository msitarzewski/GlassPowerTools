import Foundation
import Testing
@testable import GlassSSHTransport

@Suite("Host trust")
struct SSHHostTrustTests {
    private let keyA = Data("ssh-ed25519 AAAA-first".utf8).base64EncodedString()
    private let keyB = Data("ssh-ed25519 AAAA-second".utf8).base64EncodedString()

    @Test func unknownHostProducesAnUnknownChallenge() {
        let challenge = SSHHostTrustEvaluator.evaluate(presentedKeyBase64: keyA, algorithm: "ssh-ed25519", fingerprintSHA256: "fp", host: "h", port: 22, authorizedKeys: [])
        #expect(challenge?.reason == .unknown)
        #expect(challenge?.keyDataBase64 == keyA)
        #expect(challenge?.summary.contains("first time") == true)
    }

    @Test func pinnedKeyIsAccepted() {
        #expect(SSHHostTrustEvaluator.evaluate(presentedKeyBase64: keyA, algorithm: "ssh-ed25519", fingerprintSHA256: "fp", host: "h", port: 22, authorizedKeys: [keyA]) == nil)
    }

    @Test func differentKeyForPinnedHostIsAChangedChallenge() {
        let challenge = SSHHostTrustEvaluator.evaluate(presentedKeyBase64: keyB, algorithm: "ssh-ed25519", fingerprintSHA256: "fp", host: "h", port: 22, authorizedKeys: [keyA])
        #expect(challenge?.reason == .changed)
        #expect(challenge?.summary.contains("changed") == true)
    }

    @Test func inMemoryStorePinsAndSupersedes() throws {
        let store = InMemoryHostTrustStore()
        #expect(try store.authorizedKeys(host: "h", port: 22).isEmpty)
        try store.pin(SSHHostTrustChallenge(host: "h", port: 22, algorithm: "a", fingerprintSHA256: "f", keyDataBase64: keyA, reason: .unknown))
        #expect(try store.authorizedKeys(host: "h", port: 22) == [keyA])
        try store.pin(SSHHostTrustChallenge(host: "h", port: 22, algorithm: "a", fingerprintSHA256: "f", keyDataBase64: keyB, reason: .changed))
        #expect(try store.authorizedKeys(host: "h", port: 22) == [keyB], "a changed key supersedes the previous generation")
        #expect(try store.authorizedKeys(host: "h", port: 2222).isEmpty, "trust is per host and port")
    }

    @Test func wireDataAlgorithmIsDerivedFromTheKeyBlob() {
        var blob = Data([0x00, 0x00, 0x00, 0x0B])
        blob.append(contentsOf: "ssh-ed25519".utf8)
        blob.append(contentsOf: [1, 2, 3])
        #expect(SSHHostTrustEvaluator.algorithm(fromWireData: blob) == "ssh-ed25519")
        #expect(SSHHostTrustEvaluator.algorithm(fromWireData: Data([0, 0])) == "unknown")
    }

    /// The fingerprint must be the string OpenSSH prints, not merely the right 32 bytes.
    ///
    /// This is a **known-answer test**: the blob and the expected fingerprint were produced by
    /// `ssh-keygen -t ed25519` and `ssh-keygen -lf` on a throwaway key whose private half was
    /// destroyed, so the expectation comes from OpenSSH rather than from this implementation
    /// agreeing with itself. A public key blob is not secret.
    ///
    /// The previous version of this test asserted `.count == 44`, which **pinned the defect**:
    /// 44 characters is bare base64 *with* its padding, and OpenSSH prints 43 characters after a
    /// `SHA256:` prefix. Both spellings hash the same bytes, so nothing failed and nothing could
    /// — the damage was to the one person D14 asks to compare two strings by eye.
    @Test func fingerprintIsSpelledTheWayOpenSSHSpellsIt() throws {
        let blob = try #require(Data(base64Encoded:
            "AAAAC3NzaC1lZDI1NTE5AAAAIP/2cuwqHC8FXKsS5HkDszxrr/hjCRi1avykqzrxgvCf"))
        let fingerprint = SSHHostTrustEvaluator.sha256Fingerprint(of: blob)
        #expect(fingerprint == "SHA256:g2yTKmItHjGynkazA4MAUR1lvsDTkLXPRusxTHFs6/8")
        #expect(fingerprint.hasPrefix("SHA256:"), "a user compares this against ssh-keygen output")
        #expect(!fingerprint.hasSuffix("="), "OpenSSH strips base64 padding; a trailing = does not match")
    }

    @Test func challengeRoundTripsThroughCodable() throws {
        let challenge = SSHHostTrustChallenge(host: "h", port: 22, algorithm: "a", fingerprintSHA256: "f", keyDataBase64: keyA, reason: .changed)
        let decoded = try JSONDecoder().decode(SSHHostTrustChallenge.self, from: JSONEncoder().encode(challenge))
        #expect(decoded == challenge)
        #expect(decoded.keyData == Data(base64Encoded: keyA))
    }

    @Test func userFacingMessagesNameTheEndpointNotTheSecret() {
        let endpoint = SSHEndpoint(host: "box.local", port: 2222, username: "me")
        let challenge = SSHHostTrustChallenge(host: "box.local", port: 2222, algorithm: "a", fingerprintSHA256: "f", keyDataBase64: keyA, reason: .unknown)
        let message = SSHTransportError.userFacingMessage(for: SSHHostTrustRequiredError(challenge: challenge), endpoint: endpoint, usesPrivateKey: true)
        #expect(message.contains("box.local:2222"))
        #expect(!message.contains(keyA))
        #expect(SSHTransportError.userFacingMessage(for: SSHTransportError.authenticationFailed, endpoint: endpoint, usesPrivateKey: false).contains("me@box.local:2222"))
        #expect(SSHTransportError.userFacingMessage(for: SSHTransportError.tunnelBindFailed(port: 8080, reason: "Port 8080 is already in use."), endpoint: endpoint, usesPrivateKey: false).contains("8080"))
    }
}
