//
//  DatabaseCertificateTrustTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  R7 / D13: the app's half of trusting a self-signed database certificate. The engine's half —
//  that the CA-only policy actually connects to a stock MySQL — is in `GlassDBKitTests` against
//  the real server; nothing here can prove that, and these do not pretend to.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

/// A self-signed CA that signed nothing, used as import material. Its private key was discarded
/// and never existed in this repository; a certificate is public in any case.
private let sampleCertificatePEM = """
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

/// The same certificate in DER. Base64 only because a Swift source file cannot hold raw bytes;
/// it is decoded back to DER before it reaches the parser, so this exercises the DER path and not
/// the PEM one.
private let sampleCertificateDERBase64 = """
MIIDVzCCAj+gAwIBAgIUV3wDIwbSRLq92vNQjAI7pW2jApswDQYJKoZIhvcNAQELBQAwOzE5MDcGA1UEAwwwR2xh
c3MgUG93ZXIgVG9vbHMgVGVzdCBDQSAobm90IGEgcmVhbCBhdXRob3JpdHkpMB4XDTI2MDkxMjE5MzE1NVoXDTQ2
MDkwNzE5MzE1NVowOzE5MDcGA1UEAwwwR2xhc3MgUG93ZXIgVG9vbHMgVGVzdCBDQSAobm90IGEgcmVhbCBhdXRo
b3JpdHkpMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqAqJ8fpDJY5Rn2EHZlqyHmK/7m3dbM3jtBEV
q06n/zkvzMa44+wF4qsGvl94vHwO9qV6kJdNUIH4+QQtsfpoln6ULCJ0KGeIpG8ALQp6vIEOAmLy2HRNkZG/AEDY
Z2hxaoBoGMnREfEeMoUotPpE+tgDWE28/K3kta9wIEQCZAITL6FCupI1fogvBZhEJLWF40p3KbuWQENBS4X1B+Zk
nIFAem7t6SFHKCQfBroObfhJfBYSVb2c1KfUkbiqlwikvKK82ERqmhaSYT283kaRYCMN3oBroahgkMIVEYG8dyuX
XFMzGVuiT7ioWtwCcHRPC0eqabPnNA/GnX/m9Q4l3QIDAQABo1MwUTAdBgNVHQ4EFgQUJfKynwiJ4zo0PUrtXF4P
DCC1E4EwHwYDVR0jBBgwFoAUJfKynwiJ4zo0PUrtXF4PDCC1E4EwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0B
AQsFAAOCAQEAXfdyHs0O/RcjXNf7HUFbgKEm1fQ2EZ2iNjJsm8lPZl1Q+V/WSP3c/oDK/X1JdEO+nWP2JAAAfqEX
n/jd9pVqIaqTRNhnMbn8jJNL8yhNYtTBuuzaEKqRl5uAWmuKaDiK59TM3FPtpWAuivzd9JYTUxXyit0m8MTDkQFE
/aCtjJyUFQMuw3i1N54vwfjmUY013EW0SUpd66pztIqeKffXkM+ztNkwCAYTtMs2R+RUqIzOL/kK6V6Gltv5esnX
LyhD7huTs/7TrgCyJAv2UnjL5RsQw4vlDshIAueLo5G03I6meg5BZwifBCfJTQzcITj7WsfYg6s35c8puZ8uFpDI
Pw==
"""

@Suite("Database certificate trust")
struct DatabaseCertificateTrustTests {

    private var pem: Data { Data(sampleCertificatePEM.utf8) }

    // MARK: The modes

    @Test("Exactly one mode declines to verify the server's identity, and says so")
    func modesDeclareWhatTheyVerify() {
        #expect(DatabaseTLSVerification.systemTrust.verifiesServerIdentity)
        #expect(DatabaseTLSVerification.pinnedCertificate.verifiesServerIdentity)
        #expect(!DatabaseTLSVerification.pinnedCertificateAuthorityOnly.verifiesServerIdentity)

        #expect(!DatabaseTLSVerification.systemTrust.requiresCertificate)
        #expect(DatabaseTLSVerification.pinnedCertificate.requiresCertificate)
        #expect(DatabaseTLSVerification.pinnedCertificateAuthorityOnly.requiresCertificate)

        // Each mode has to be able to tell the user what it gives up; a blank explanation would
        // leave the weakest one looking like the others.
        for mode in DatabaseTLSVerification.allCases {
            #expect(!mode.displayName.isEmpty)
            #expect(!mode.explanation.isEmpty)
            #expect(!mode.shortDescription.isEmpty)
        }
        #expect(DatabaseTLSVerification.pinnedCertificateAuthorityOnly.explanation.contains("not checked"))
    }

    // MARK: Import

    @Test("A PEM certificate imports and reports a fingerprint that can be compared")
    func pemImports() throws {
        let inspection = try DatabaseCertificateImport.inspect(pem)
        #expect(inspection.count == 1)
        let fingerprint = try #require(inspection.certificates.first).fingerprintSHA256
        // OpenSSL's presentation: uppercase hex pairs joined by colons, 32 bytes.
        #expect(fingerprint.split(separator: ":").count == 32)
        #expect(fingerprint.allSatisfy { $0.isHexDigit || $0 == ":" })
        #expect(fingerprint == fingerprint.uppercased())
        #expect(DatabaseCertificateImport.summary(of: inspection).contains(fingerprint))
        #expect(DatabaseCertificateImport.summary(of: inspection).contains("1 certificate"))
    }

    @Test("A file that is not a certificate is refused at import, not at the next connection")
    func nonCertificatesAreRefused() {
        #expect(throws: DatabaseCertificateImportError.self) {
            try DatabaseCertificateImport.inspect(Data("hello, this is not a certificate".utf8))
        }
        #expect(throws: DatabaseCertificateImportError.self) {
            try DatabaseCertificateImport.inspect(Data([0x30, 0x82, 0x00, 0x01]))
        }
        #expect(throws: DatabaseCertificateImportError.self) {
            try DatabaseCertificateImport.inspect(Data())
        }
    }

    @Test("An expired certificate is reported in the summary rather than silently accepted")
    func expiryIsReported() throws {
        let inspection = try DatabaseCertificateImport.inspect(pem)
        let certificate = try #require(inspection.certificates.first)
        #expect(!certificate.isExpired(asOf: Date()))
        // Far past its notAfter: the summary has to say so, because a user comparing only the
        // fingerprint would otherwise have no sign that this root can no longer validate anyone.
        let afterwards = certificate.notValidAfter.addingTimeInterval(86_400)
        #expect(certificate.isExpired(asOf: afterwards))
        #expect(DatabaseCertificateImport.summary(of: inspection, asOf: afterwards)
            .contains("validity window"))
    }

    @Test("The format is decided by the contents, not by the file's extension")
    func formatIsDetectedFromContents() throws {
        #expect(DatabaseConnectionConfig.certificateFormat(of: pem) == .pem)
        let der = try #require(Data(base64Encoded: sampleCertificateDERBase64,
                                    options: .ignoreUnknownCharacters))
        #expect(DatabaseConnectionConfig.certificateFormat(of: der) == .der)
    }

    @Test("A real DER certificate imports, and describes the same certificate as its PEM")
    func derImports() throws {
        let der = try #require(Data(base64Encoded: sampleCertificateDERBase64,
                                    options: .ignoreUnknownCharacters))
        let fromDER = try DatabaseCertificateImport.inspect(der)
        let fromPEM = try DatabaseCertificateImport.inspect(pem)
        #expect(fromDER.count == 1)
        // Same bytes, differently armoured: the fingerprint is over the DER either way, so the
        // two must agree. If they did not, one of the two paths would be parsing something else.
        #expect(fromDER.certificates.first?.fingerprintSHA256
                == fromPEM.certificates.first?.fingerprintSHA256)
        #expect(fromDER.certificates.first?.notValidAfter == fromPEM.certificates.first?.notValidAfter)
    }

    // MARK: The record

    @Test("A record round-trips its verification mode and its certificate")
    func recordRoundTrip() throws {
        let original = DatabaseConnectionConfig(
            name: "Fixture", engine: .mysql, host: "db.example.test", port: 3306,
            username: "reader", useTLS: true,
            tlsVerification: .pinnedCertificateAuthorityOnly, tlsCertificate: pem
        )
        let decoded = try JSONDecoder().decode(
            DatabaseConnectionConfig.self,
            from: try JSONEncoder().encode(original)
        )
        #expect(decoded.tlsVerification == .pinnedCertificateAuthorityOnly)
        #expect(decoded.tlsCertificate == pem)
        #expect(decoded.tlsCertificateMaterial?.format == .pem)
    }

    @Test("A record written before D13 reads as system trust, which is what it meant")
    func recordsWithoutTheFieldsDefaultToSystemTrust() throws {
        let json = """
        {
          "schemaVersion": 2,
          "id": "8B1E5C2A-0000-4000-8000-000000000042",
          "name": "Older", "engine": "mysql", "host": "db.example.test",
          "port": 3306, "username": "reader", "usesHostTunnel": false,
          "isReadOnly": false, "databaseCredentialPolicy": "glassdbOnly",
          "useTLS": true, "isFavorite": false, "colorTag": "none",
          "dateAdded": 760000000, "tags": []
        }
        """.data(using: .utf8)!
        let record = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: json)
        #expect(record.useTLS)
        #expect(record.tlsVerification == .systemTrust)
        #expect(record.tlsCertificate == nil)
        #expect(record.transportVerificationSummary == DatabaseTLSVerification.systemTrust.shortDescription)
    }

    @Test("An oversized blob does not become trust material")
    func oversizedCertificateIsNotUsed() {
        let record = DatabaseConnectionConfig(
            name: "Fixture", useTLS: true, tlsVerification: .pinnedCertificate,
            tlsCertificate: Data(repeating: 0x41,
                                 count: DatabaseConnectionConfig.maximumTLSCertificateBytes + 1)
        )
        // Refused as material rather than handed to the parser, so a hand-edited defaults plist
        // cannot make the app read a megabyte of anything as a trust root.
        #expect(record.tlsCertificateMaterial == nil)
    }

    @Test("The transport summary never says encrypted without saying what is checked")
    func transportSummaryIsHonest() {
        let plain = DatabaseConnectionConfig(name: "a", engine: .mysql, useTLS: false)
        #expect(plain.transportVerificationSummary == "Not encrypted")

        let caOnly = DatabaseConnectionConfig(name: "b", engine: .mysql, useTLS: true,
                                              tlsVerification: .pinnedCertificateAuthorityOnly)
        #expect(caOnly.transportVerificationSummary.contains("not checked"))

        let sqlite = DatabaseConnectionConfig(name: "c", engine: .sqlite, useTLS: false)
        #expect(sqlite.transportVerificationSummary == "Not encrypted in transit")
    }
}
