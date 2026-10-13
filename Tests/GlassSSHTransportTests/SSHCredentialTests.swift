import Foundation
import Testing
import GlasSecretStore
@testable import GlassSSHTransport

@Suite("Credential references and resolution")
struct SSHCredentialTests {
    private var testConfiguration: SecretStoreConfiguration {
        SecretStoreConfiguration(serviceNamePrefix: "com.glasspowertools.transport-tests", accessGroup: nil, useDataProtectionKeychain: true)
    }

    /// B-X18 (2026-10-13): the shown text listed ECDSA P-256 as supported while refusing a P-256
    /// key, and the error's own description said otherwise. One text now, and it is true.
    @Test("A key that cannot be imported is told one thing, which does not contradict itself")
    func unsupportedKeyTypeIsToldOneThing() {
        let error = SSHTransportError.unsupportedKeyType("ECDSA P-256")
        let shown = SSHTransportError.userFacingMessage(
            for: error, endpoint: SSHEndpoint(host: "alpha", username: "me"), usesPrivateKey: true)
        #expect(shown == error.errorDescription)
        #expect(shown.hasPrefix("ECDSA P-256 keys can't be imported"))
        #expect(!shown.contains("Supported key types"))
    }

    @Test func missingPasswordReportsUnavailableWithoutRevealingAnything() async {
        let resolver = SecretStoreCredentialResolver(configuration: testConfiguration)
        let endpoint = SSHEndpoint(host: "box.local", username: "me")
        await #expect(throws: SSHTransportError.credentialUnavailable("No password is stored for me@box.local:22.")) {
            _ = try await resolver.resolve(.password(profileID: UUID()), for: endpoint)
        }
    }

    @Test func missingPrivateKeyReportsUnavailable() async {
        let resolver = SecretStoreCredentialResolver(configuration: testConfiguration)
        let endpoint = SSHEndpoint(host: "box.local", username: "me")
        await #expect(throws: SSHTransportError.credentialUnavailable("The SSH key for me@box.local:22 was not found.")) {
            _ = try await resolver.resolve(.privateKey(keyID: UUID()), for: endpoint)
        }
    }

    @Test func agentAndUnknownCustomReferencesAreRefused() async {
        let resolver = SecretStoreCredentialResolver(configuration: testConfiguration)
        let endpoint = SSHEndpoint(host: "box.local", username: "me")
        await #expect(throws: SSHTransportError.unsupportedAuthenticationMethod("SSH Agent authentication is unavailable in this release.")) {
            _ = try await resolver.resolve(.agent, for: endpoint)
        }
        await #expect(throws: SSHTransportError.credentialUnavailable("No resolver handles the credential reference nope.")) {
            _ = try await resolver.resolve(.custom("nope"), for: endpoint)
        }
    }

    @Test func passwordLocationsAreTriedInOrder() async throws {
        // Two nonexistent locations: both are consulted, then the endpoint-specific error.
        let resolver = SecretStoreCredentialResolver(configuration: testConfiguration) { profileID in
            [SSHPasswordLocation(account: "terminal.\(profileID)", service: "com.glasspowertools.transport-tests.a"),
             SSHPasswordLocation(account: "family.\(profileID)", service: "com.glasspowertools.transport-tests.b")]
        }
        await #expect(throws: SSHTransportError.credentialUnavailable("No password is stored for me@box.local:22.")) {
            _ = try await resolver.resolve(.password(profileID: UUID()), for: SSHEndpoint(host: "box.local", username: "me"))
        }
    }

    @Test func builderRejectsMismatchedMaterialAndBadEncodings() throws {
        let password = SecureBytes(Data("pw".utf8))
        // Password reference with password material → password auth.
        _ = try SSHAuthenticationBuilder.method(username: "me", reference: .password(profileID: UUID()), credential: .password(password))
        // Password reference with key material is a mismatch.
        #expect(throws: SSHTransportError.credentialUnavailable("The resolved credential does not match the requested authentication method.")) {
            _ = try SSHAuthenticationBuilder.method(username: "me", reference: .password(profileID: UUID()), credential: .privateKey(SSHKeyMaterial(privateKey: password, passphrase: nil)))
        }
        // Key reference with password material is a mismatch.
        #expect(throws: SSHTransportError.credentialUnavailable("The resolved credential does not match the requested authentication method.")) {
            _ = try SSHAuthenticationBuilder.method(username: "me", reference: .privateKey(keyID: UUID()), credential: .password(password))
        }
        // Undecodable key material is reported without echoing it.
        #expect(throws: SSHTransportError.invalidPrivateKey("The stored key material could not be decoded.")) {
            _ = try SSHAuthenticationBuilder.method(username: "me", reference: .privateKey(keyID: UUID()), credential: .privateKey(SSHKeyMaterial(privateKey: SecureBytes(Data("not a key".utf8)), passphrase: nil)))
        }
        // Agent is refused before any material is examined.
        #expect(throws: SSHTransportError.unsupportedAuthenticationMethod("SSH Agent authentication is unavailable in this release.")) {
            _ = try SSHAuthenticationBuilder.method(username: "me", reference: .agent, credential: .password(password))
        }
        // Malformed Secure Enclave payloads are refused explicitly.
        #expect(throws: SSHTransportError.invalidPrivateKey("Invalid true Secure Enclave P-256 data representation.")) {
            _ = try SSHAuthenticationBuilder.method(username: "me", reference: .privateKey(keyID: UUID()), credential: .privateKey(SSHKeyMaterial(privateKey: SecureBytes(Data("TRUE_SE_P256:***".utf8)), passphrase: nil)))
        }
    }
}
