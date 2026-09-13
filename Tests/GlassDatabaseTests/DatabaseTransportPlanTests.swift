//
//  DatabaseTransportPlanTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  Where the driver's socket goes, and which name TLS is checked against, once the tunnel is
//  the host's Terminal service rather than a per-connection SSH configuration (D7).
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

private let transportPlanCertificatePEM = """
-----BEGIN CERTIFICATE-----
MIIDVzCCAj+gAwIBAgIUV3wDIwbSRLq92vNQjAI7pW2jApswDQYJKoZIhvcNAQEL
BQAwOzE5MDcGA1UEAwwwR2xhc3MgUG93ZXIgVG9vbHMgVGVzdCBDQSAobm90IGEg
cmVhbCBhdXRob3JpdHkpMB4XDTI2MDkxMjE5MzE1NVoXDTQ2MDkwNzE5MzE1NVow
OzE5MDcGA1UEAwwwR2xhc3MgUG93ZXIgVG9vbHMgVGVzdCBDQSAobm90IGEgcmVh
bCBhdXRob3JpdHkpMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqAqJ
8fpDJY5Rn2EHZlqyHmK/7m3dbM3jtBEVq06n/zkvzMa44+wF4qsGvl94vHwO9qV6
kJdNUIH4+QQtsfpoln6ULCJ0KGeIpG8ALQp6vIEOAmLy2HRNkZG/AEDYZ2hxaoBo
GMnREfEeMoUotPpE+tgDWE28/K3kta9wIEQCZAITL6FCupI1fogvBZhEJLWF40p3
KbuWQENBS4X1B+ZknIFAem7t6SFHKCQfBroObfhJfBYSVb2c1KfUkbiqlwikvKK8
2ERqmhaSYT283kaRYCMN3oBroahgkMIVEYG8dyuXXFMzGVuiT7ioWtwCcHRPC0eq
abPnNA/GnX/m9Q4l3QIDAQABo1MwUTAdBgNVHQ4EFgQUJfKynwiJ4zo0PUrtXF4P
DCC1E4EwHwYDVR0jBBgwFoAUJfKynwiJ4zo0PUrtXF4PDCC1E4EwDwYDVR0TAQH/
BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAXfdyHs0O/RcjXNf7HUFbgKEm1fQ2
EZ2iNjJsm8lPZl1Q+V/WSP3c/oDK/X1JdEO+nWP2JAAAfqEXn/jd9pVqIaqTRNhn
Mbn8jJNL8yhNYtTBuuzaEKqRl5uAWmuKaDiK59TM3FPtpWAuivzd9JYTUxXyit0m
8MTDkQFE/aCtjJyUFQMuw3i1N54vwfjmUY013EW0SUpd66pztIqeKffXkM+ztNkw
CAYTtMs2R+RUqIzOL/kK6V6Gltv5esnXLyhD7huTs/7TrgCyJAv2UnjL5RsQw4vl
DshIAueLo5G03I6meg5BZwifBCfJTQzcITj7WsfYg6s35c8puZ8uFpDIPw==
-----END CERTIFICATE-----
"""

@Suite("Transport plan")
struct DatabaseTransportPlanTests {

    private func config(engine: DatabaseEngineType = .mysql,
                        tunnel: Bool = false,
                        tls: Bool = false,
                        verification: DatabaseTLSVerification = .systemTrust,
                        certificate: Data? = nil) -> DatabaseConnectionConfig {
        DatabaseConnectionConfig(name: "Fixture", engine: engine, host: "db.example.test",
                                 port: 3306, username: "reader", usesHostTunnel: tunnel, useTLS: tls,
                                 tlsVerification: verification, tlsCertificate: certificate)
    }

    /// A self-signed CA that signed nothing, used only so the plan has parseable material.
    private var certificatePEM: Data { Data(transportPlanCertificatePEM.utf8) }

    @Test("A direct connection goes to the host's own address and port")
    func directPlan() throws {
        let plan = try DatabaseSessionManager.transportPlan(for: config())
        #expect(plan.databaseHost == "db.example.test")
        #expect(plan.databasePort == 3306)
        #expect(plan.tlsPolicy == .disabled)
    }

    @Test("Through a tunnel the socket goes to loopback on the forward's local port")
    func tunnelledPlan() throws {
        let plan = try DatabaseSessionManager.transportPlan(for: config(tunnel: true), tunnelLocalPort: 54_321)
        #expect(plan.databaseHost == "127.0.0.1")
        #expect(plan.databasePort == 54_321)
        // The plan says where the socket goes and nothing else. It used to carry the tunnel's
        // remote host and port as well, written and never read; they looked like the forward's
        // target and were not one — the forward goes to `127.0.0.1` **as the host's machine sees
        // it**, which is what lets a loopback-only database be reached at all (D7).
    }

    @Test("TLS through a tunnel is still checked against the machine's real name, never loopback")
    func tunnelledTLSChecksTheRealName() throws {
        let plan = try DatabaseSessionManager.transportPlan(for: config(tunnel: true, tls: true), tunnelLocalPort: 54_321)
        #expect(plan.databaseHost == "127.0.0.1")
        #expect(plan.tlsPolicy == .requiredSystemTrustForHost("db.example.test"))
    }

    @Test("A direct TLS connection uses plain system trust")
    func directTLS() throws {
        let plan = try DatabaseSessionManager.transportPlan(for: config(tls: true))
        #expect(plan.tlsPolicy == .requiredSystemTrust)
    }

    // MARK: The pinned modes (D13 / R7)

    @Test("A pinned certificate is verified against the machine's name, tunnel or not")
    func pinnedCertificateChecksTheRealName() throws {
        let expected = DatabaseTLSPolicy.requiredCertificates(
            [DatabaseTLSCertificate(bytes: certificatePEM, format: .pem)],
            serverName: "db.example.test"
        )
        let direct = try DatabaseSessionManager.transportPlan(
            for: config(tls: true, verification: .pinnedCertificate, certificate: certificatePEM)
        )
        #expect(direct.tlsPolicy == expected)

        let tunnelled = try DatabaseSessionManager.transportPlan(
            for: config(tunnel: true, tls: true, verification: .pinnedCertificate, certificate: certificatePEM),
            tunnelLocalPort: 54_321
        )
        #expect(tunnelled.databaseHost == "127.0.0.1")
        // Loopback is where the socket goes; the certificate is still checked against the
        // machine, which is what makes a tunnelled TLS connection worth anything.
        #expect(tunnelled.tlsPolicy == expected)
    }

    @Test("The CA-only mode matches no name at all — the point of D13")
    func certificateAuthorityOnlyMatchesNoName() throws {
        let expected = DatabaseTLSPolicy.requiredCertificatesWithoutHostnameVerification(
            [DatabaseTLSCertificate(bytes: certificatePEM, format: .pem)]
        )
        for tunnelled in [false, true] {
            let plan = try DatabaseSessionManager.transportPlan(
                for: config(tunnel: tunnelled, tls: true,
                            verification: .pinnedCertificateAuthorityOnly, certificate: certificatePEM),
                tunnelLocalPort: tunnelled ? 54_321 : nil
            )
            // Identical with and without a tunnel: there is no name in it to differ.
            #expect(plan.tlsPolicy == expected)
            #expect(!plan.tlsPolicy.verifiesServerIdentity)
        }
    }

    @Test("A pinned mode with no usable certificate is refused, never downgraded")
    func pinnedModeWithoutACertificateIsRefused() {
        for mode in [DatabaseTLSVerification.pinnedCertificate, .pinnedCertificateAuthorityOnly] {
            // The sheet will not save this, so it can only arrive from a hand-edited defaults
            // plist or a partial restore. Falling back to system trust would change what the
            // connection verifies without telling anyone.
            #expect(throws: DatabaseSessionManager.SessionError.self) {
                _ = try DatabaseSessionManager.transportPlan(
                    for: config(tls: true, verification: mode, certificate: nil)
                )
            }
            // An oversized blob is not usable material either, and is refused the same way
            // rather than being handed to the parser.
            #expect(throws: DatabaseSessionManager.SessionError.self) {
                _ = try DatabaseSessionManager.transportPlan(
                    for: config(tls: true, verification: mode,
                                certificate: Data(repeating: 0x41,
                                                  count: DatabaseConnectionConfig.maximumTLSCertificateBytes + 1))
                )
            }
        }
    }

    @Test("A pinned mode with TLS off is plaintext, not a pinned connection")
    func pinnedModeWithTLSOffIsDisabled() throws {
        let plan = try DatabaseSessionManager.transportPlan(
            for: config(tls: false, verification: .pinnedCertificateAuthorityOnly, certificate: certificatePEM)
        )
        #expect(plan.tlsPolicy == .disabled)
    }

    @Test("A tunnel with no local port is refused rather than connected somewhere arbitrary")
    func tunnelWithoutPortIsRefused() {
        #expect(throws: DatabaseSessionManager.SessionError.self) {
            _ = try DatabaseSessionManager.transportPlan(for: config(tunnel: true), tunnelLocalPort: nil)
        }
        #expect(throws: DatabaseSessionManager.SessionError.self) {
            _ = try DatabaseSessionManager.transportPlan(for: config(tunnel: true), tunnelLocalPort: 0)
        }
    }

    @Test("SQLite is a local file: it refuses a tunnel and refuses TLS")
    func sqliteRefusesTransport() throws {
        let plain = try DatabaseSessionManager.transportPlan(for: config(engine: .sqlite))
        #expect(plain.databasePort == 0)
        #expect(plain.tlsPolicy == .disabled)

        #expect(throws: DatabaseSessionManager.SessionError.self) {
            _ = try DatabaseSessionManager.transportPlan(for: config(engine: .sqlite, tunnel: true))
        }
        #expect(throws: DatabaseSessionManager.SessionError.self) {
            _ = try DatabaseSessionManager.transportPlan(for: config(engine: .sqlite, tls: true))
        }
    }

    @MainActor
    @Test("A service set to tunnel with no forward available fails saying so, and connects nowhere")
    func tunnelWithoutAProviderFailsHonestly() async {
        let manager = DatabaseSessionManager(loadImmediately: false)
        await #expect(throws: (any Error).self) {
            _ = try await manager.connect(config: config(tunnel: true), password: "", openForward: nil)
        }
        // The failed attempt leaves no session behind.
        #expect(manager.sessions.isEmpty)
    }
}

@Suite("What the connection detail says TLS verifies")
struct TransportVerificationSummaryTests {

    private func config(tls: Bool, verification: DatabaseTLSVerification) -> DatabaseConnectionConfig {
        DatabaseConnectionConfig(
            name: "db", engine: .mysql, host: "db.example.test", port: 3306,
            username: "reader", defaultDatabase: "gpt_test",
            useTLS: tls, tlsVerification: verification
        )
    }

    @Test("Each mode says what it checks, so 'TLS' never stands alone")
    func everyModeIsDistinguishable() {
        let summaries = DatabaseTLSVerification.allCases.map {
            config(tls: true, verification: $0).transportVerificationSummary
        }
        #expect(Set(summaries).count == DatabaseTLSVerification.allCases.count,
                "two modes reading the same is the bug this guards")
        // The weaker mode says so in the words a user reads, not only in the picker.
        #expect(config(tls: true, verification: .pinnedCertificateAuthorityOnly)
            .transportVerificationSummary.contains("not checked"))
        #expect(config(tls: true, verification: .pinnedCertificate)
            .transportVerificationSummary.contains("checked"))
    }

    @Test("TLS off is stated plainly rather than implied by omission")
    func tlsOffIsExplicit() {
        #expect(config(tls: false, verification: .systemTrust)
            .transportVerificationSummary == "Not encrypted")
    }
}
