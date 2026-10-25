import Foundation
@testable import RDPKit
import Testing

extension RDPConnectionConfiguration {
    /// Trusts the mock server's certificate and nothing more: the configuration otherwise stays as
    /// the app sends it, with cross-host redirection and auxiliary input channels off. A test of either
    /// turns it on itself.
    func trustFixtureCertificate() -> Self {
        var configuration = self
        configuration.certificatePolicy = MockKRDPTLS.certificatePolicy(host: host, port: port)
        return configuration
    }
}

@Test func certificateAuthorizationRejectsUntrustedBeforeCredSSP() throws {
    let credentials = RDPCredentials(username: "fixture-user", password: "fixture-password")
    let server = try MockKRDPServer.start(securityProtocol: .credSSP(credentials: credentials))
    defer { server.stop() }
    let report = RDPPreflightClient().run(configuration: RDPConnectionConfiguration(
        host: "127.0.0.1", port: server.port, credentials: credentials, hideCertificateWarnings: true
    ))
    #expect(report.status == "failure")
    #expect(report.error?.contains("certificate identity was not authorized") == true)
    #expect(server.transcript.snapshot.credSSPMessages.isEmpty)
}

@Test func certificateAuthorizationPinIsEndpointBoundAndFailClosed() {
    let digest = String(repeating: "ab", count: 32)
    let pin = RDPServerCertificateTrustKey(host: "example.test", port: 3389, sha256: digest)!
    let policy = RDPServerCertificatePolicy.pinned(pin)
    let matching = RDPServerCertificateInfo(trusted: false, sha256: digest, warnings: [])
    #expect(policy.accepts(matching, host: "example.test", port: 3389))
    #expect(!policy.accepts(matching, host: "other.test", port: 3389))
    #expect(!policy.accepts(matching, host: "example.test", port: 3390))
    #expect(!policy.accepts(.init(trusted: true, sha256: String(repeating: "cd", count: 32), warnings: []),
                          host: "example.test", port: 3389))
    #expect(!RDPServerCertificatePolicy.systemTrust.accepts(matching, host: "example.test", port: 3389))
    #expect(!RDPServerCertificatePolicy.pinned(.init(host: "example.test", port: 3389, sha256: "ab")!)
        .accepts(.init(trusted: false, sha256: "ab", warnings: []), host: "example.test", port: 3389))
}

@Test func networkLevelAuthenticationCannotSilentlyDowngrade() throws {
    let server = try MockKRDPServer.start()
    defer { server.stop() }
    var configuration = RDPConnectionConfiguration(host: "127.0.0.1", port: server.port)
    configuration.requireNetworkLevelAuthentication = true
    let report = RDPPreflightClient().run(configuration: configuration)
    #expect(report.status == "failure")
    #expect(report.error?.contains("required Network Level Authentication") == true)
}
