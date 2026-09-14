import Foundation
@testable import RDPKit
import Testing

enum RDSTLSFixture {
    static let username = "handoff-user"
    static let password = Data([0x00, 0xFF, 0x42, 0x80, 0x00])
    static let guid = unicode(Data(0..<16).base64EncodedString())

    static func unicode(_ value: String) -> Data {
        var data = Data()
        for unit in value.utf16 { data.appendLittleEndianUInt16(unit) }
        data.appendLittleEndianUInt16(0)
        return data
    }

    static func certificateDER() throws -> Data {
        var cursor = ByteCursor(try MockKRDPTLS.rdpX509CertificateChain())
        _ = try cursor.readLittleEndianUInt32()
        _ = try cursor.readLittleEndianUInt32()
        let length = try Int(cursor.readLittleEndianUInt32())
        return try cursor.readData(count: length)
    }

    static func certificateContainer() throws -> Data {
        let certificate = try certificateDER()
        var data = Data()
        data.appendLittleEndianUInt32(32)
        data.appendLittleEndianUInt32(1)
        data.appendLittleEndianUInt32(UInt32(certificate.count))
        data.append(certificate)
        return unicode(data.base64EncodedString())
    }

    static func redirection() throws -> RDPServerRedirectionPDU {
        RDPServerRedirectionPDU(channelID: 1003, totalLength: 20, pduSource: 0,
            redirectionPacketFlags: 0x400, redirectionLength: 12, sessionID: 42,
            flags: [.loadBalanceInfo, .username, .password, .passwordIsPKEncrypted, .redirectionGuid, .targetCertificate],
            loadBalanceInfo: Data("Cookie: mststs=fixture\r\n".utf8), targetNetAddress: nil,
            username: username, domain: nil, password: nil, encryptedPassword: password,
            targetFQDN: nil, targetNetBIOSName: nil, targetNetAddresses: [], tsvURL: nil,
            redirectionGuid: guid, targetCertificate: try certificateContainer())
    }

    static var expectedRequest: Data {
        var data = Data([1, 0, 2, 0, 1, 0])
        for field in [guid, unicode(username), unicode(""), password] {
            data.appendLittleEndianUInt16(UInt16(field.count))
            data.append(field)
        }
        return data
    }
}

@Test func rdstlsPreservesOpaquePasswordAndExactCertificate() throws {
    let credentials = try RDSTLSRedirectionCredentials(redirection: RDSTLSFixture.redirection())
    #expect(try credentials.authenticationRequest() == RDSTLSFixture.expectedRequest)
    #expect(credentials.encryptedPassword == RDSTLSFixture.password)
    try credentials.verifyCertificate(RDSTLSFixture.certificateDER())
    #expect(throws: RDSTLSError.certificateMismatch) { try credentials.verifyCertificate(Data([1])) }
}

@Test func rdstlsRejectsIncompleteOrMalformedRedirection() throws {
    let original = try RDSTLSFixture.redirection()
    for index in 0..<8 {
        var value = original
        switch index {
        case 0: value.encryptedPassword = nil
        case 1: value.username = ""
        case 2: value.redirectionGuid = RDSTLSFixture.unicode("not-a-guid")
        case 3: value.targetCertificate = RDSTLSFixture.unicode("not-base64")
        case 4: value.targetCertificate = Data([1])
        case 5: value.flags.remove(.passwordIsPKEncrypted)
        case 6: value.domain = "bad\0domain"
        default: value.encryptedPassword = Data(repeating: 1, count: 65_536)
        }
        #expect(throws: (any Error).self) { try RDSTLSRedirectionCredentials(redirection: value) }
    }
}

@Test func rdstlsRequiresCorrectPDUAtEachAuthenticationStep() throws {
    let capabilities = Data([1, 0, 1, 0, 1, 0, 1, 0])
    let success = Data([1, 0, 4, 0, 1, 0, 0, 0, 0, 0])
    try RDSTLSPDU.validateCapabilities(capabilities)
    try RDSTLSPDU.validateAuthenticationResponse(success)
    #expect(throws: RDSTLSError.invalidAuthenticationResponse) {
        try RDSTLSPDU.validateAuthenticationResponse(capabilities)
    }
    #expect(throws: RDSTLSError.invalidCapabilities) { try RDSTLSPDU.validateCapabilities(success) }
    for index in 0..<6 {
        var altered = success
        altered[index] ^= 0x80
        #expect(throws: RDSTLSError.invalidAuthenticationResponse) {
            try RDSTLSPDU.validateAuthenticationResponse(altered)
        }
    }
    #expect(throws: RDSTLSError.invalidAuthenticationResponse) {
        try RDSTLSPDU.validateAuthenticationResponse(success + Data([0]))
    }
}

@Test func rdstlsSkipsCertificateMetadataButRejectsAmbiguousCertificates() throws {
    var value = try RDSTLSFixture.redirection()
    let certificateField = try #require(value.targetCertificate)
    let encoded = try #require(String(data: certificateField, encoding: .utf16LittleEndian))
    let container = try #require(Data(base64Encoded: String(encoded.dropLast())))
    let metadata = Data([5, 0, 0, 0, 99, 0, 0, 0, 3, 0, 0, 0, 10, 11, 12])
    value.targetCertificate = RDSTLSFixture.unicode((metadata + container + metadata).base64EncodedString())
    let credentials = try RDSTLSRedirectionCredentials(redirection: value)
    try credentials.verifyCertificate(RDSTLSFixture.certificateDER())
    value.targetCertificate = RDSTLSFixture.unicode((container + container).base64EncodedString())
    #expect(throws: RDSTLSError.invalidRedirection) { try RDSTLSRedirectionCredentials(redirection: value) }
    value.targetCertificate = RDSTLSFixture.unicode((container + metadata.dropLast()).base64EncodedString())
    #expect(throws: (any Error).self) { try RDSTLSRedirectionCredentials(redirection: value) }
}

@Test(arguments: [UInt32(5), 0x52e, 0x530, 0x532, 0x533, 0x773, 0x775, UInt32.max])
func rdstlsNeverTreatsAuthenticationFailureAsSuccess(_ code: UInt32) throws {
    var response = Data([1, 0, 4, 0, 1, 0])
    response.appendLittleEndianUInt32(code)
    #expect(throws: RDSTLSError.authenticationFailed(code)) {
        try RDSTLSPDU.validateAuthenticationResponse(response)
    }
}

@Test func rdstlsAcceptsKnownVersionMaskWithoutSelectingVersionTwo() throws {
    for versions: UInt16 in [1, 3] {
        var capabilities = Data([1, 0, 1, 0, 1, 0])
        capabilities.appendLittleEndianUInt16(versions)
        try RDSTLSPDU.validateCapabilities(capabilities)
        let credentials = try RDSTLSRedirectionCredentials(redirection: RDSTLSFixture.redirection())
        #expect(try credentials.authenticationRequest().prefix(2) == Data([1, 0]))
    }
    for versions: UInt16 in [0, 2, 4, 5, 0x8001, UInt16.max] {
        var capabilities = Data([1, 0, 1, 0, 1, 0])
        capabilities.appendLittleEndianUInt16(versions)
        #expect(throws: RDSTLSError.invalidCapabilities) {
            try RDSTLSPDU.validateCapabilities(capabilities)
        }
    }
}

@Test func rdstlsRejectsMalformedCapabilitiesWithVersionMask() throws {
    let valid = Data([1, 0, 1, 0, 1, 0, 3, 0])
    for index in 0..<6 {
        var altered = valid
        altered[index] ^= 0x80
        #expect(throws: RDSTLSError.invalidCapabilities) {
            try RDSTLSPDU.validateCapabilities(altered)
        }
    }
    for packet in [Data(), Data(valid.dropLast()), valid + Data([0])] {
        #expect(throws: RDSTLSError.invalidCapabilities) {
            try RDSTLSPDU.validateCapabilities(packet)
        }
    }
}
