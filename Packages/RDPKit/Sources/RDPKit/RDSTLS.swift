import Foundation
import Security

/// MS-RDPBCGR 2.2.17: authentication data issued by an already trusted server.
/// The encrypted password is opaque. It must never become an NTLM password.
struct RDSTLSRedirectionCredentials: Equatable, Sendable {
    let username: String
    let domain: String
    let redirectionGUID: Data
    let encryptedPassword: Data
    let certificateDER: Data

    init(redirection: RDPServerRedirectionPDU) throws {
        guard redirection.flags.contains(.passwordIsPKEncrypted),
              let username = redirection.username, !username.isEmpty,
              let password = redirection.encryptedPassword, !password.isEmpty,
              password.count <= Int(UInt16.max),
              let guid = redirection.redirectionGuid,
              let encodedCertificate = redirection.targetCertificate else {
            throw RDSTLSError.invalidRedirection
        }
        let guidString = try Self.unicodeString(guid)
        guard Data(base64Encoded: guidString)?.count == 16 else {
            throw RDSTLSError.invalidRedirection
        }
        let certificateString = try Self.unicodeString(encodedCertificate)
        guard let container = Data(base64Encoded: certificateString) else {
            throw RDSTLSError.invalidRedirection
        }
        var cursor = ByteCursor(container)
        // MS-RDPBCGR 2.2.13.1.2: ignore unrelated metadata in the container.
        var certificate: Data?
        while cursor.remaining > 0 {
            let type = try cursor.readLittleEndianUInt32()
            let encoding = try cursor.readLittleEndianUInt32()
            let length = try Int(cursor.readLittleEndianUInt32())
            let element = try cursor.readData(count: length)
            if type == 32 && encoding == 1 {
                guard certificate == nil else { throw RDSTLSError.invalidRedirection }
                certificate = element
            }
        }
        guard let der = certificate, SecCertificateCreateWithData(nil, der as CFData) != nil else {
            throw RDSTLSError.invalidRedirection
        }
        self.username = username
        self.domain = redirection.domain ?? ""
        self.redirectionGUID = guid
        self.encryptedPassword = password
        self.certificateDER = der
        _ = try authenticationRequest()
    }

    func authenticationRequest() throws -> Data {
        var packet = Data()
        packet.appendLittleEndianUInt16(1)
        packet.appendLittleEndianUInt16(2)
        packet.appendLittleEndianUInt16(1)
        for field in [redirectionGUID, try Self.unicodeBytes(username),
                      try Self.unicodeBytes(domain), encryptedPassword] {
            guard let length = UInt16(exactly: field.count) else { throw RDSTLSError.invalidRedirection }
            packet.appendLittleEndianUInt16(length)
            packet.append(field)
        }
        return packet
    }

    func verifyCertificate(_ der: Data) throws {
        guard der == certificateDER else { throw RDSTLSError.certificateMismatch }
    }

    private static func unicodeString(_ bytes: Data) throws -> String {
        guard !bytes.isEmpty, bytes.count <= Int(UInt16.max), bytes.count.isMultiple(of: 2),
              var value = String(data: bytes, encoding: .utf16LittleEndian) else {
            throw RDSTLSError.invalidRedirection
        }
        if value.last == "\0" { value.removeLast() }
        guard !value.contains("\0") else { throw RDSTLSError.invalidRedirection }
        return value
    }

    private static func unicodeBytes(_ value: String) throws -> Data {
        guard !value.utf16.contains(0), value.utf16.count < Int(UInt16.max) / 2 else {
            throw RDSTLSError.invalidRedirection
        }
        var bytes = Data()
        for unit in value.utf16 { bytes.appendLittleEndianUInt16(unit) }
        bytes.appendLittleEndianUInt16(0)
        return bytes
    }
}

enum RDSTLSPDU {
    static func validateCapabilities(_ packet: Data) throws {
        guard packet.count == 8, packet.prefix(6) == Data([1, 0, 1, 0, 1, 0]) else {
            throw RDSTLSError.invalidCapabilities
        }
        // FreeRDP 3.31 advertises v1 and v2 together. Our password request
        // still selects v1; v2-only and unknown version bits remain unsupported.
        var cursor = ByteCursor(Data(packet.suffix(2)))
        let versions = try cursor.readLittleEndianUInt16()
        guard versions == 1 || versions == 3 else { throw RDSTLSError.invalidCapabilities }
    }

    static func validateAuthenticationResponse(_ packet: Data) throws {
        guard packet.count == 10, packet.prefix(6) == Data([1, 0, 4, 0, 1, 0]) else {
            throw RDSTLSError.invalidAuthenticationResponse
        }
        var cursor = ByteCursor(Data(packet.suffix(4)))
        let result = try cursor.readLittleEndianUInt32()
        guard result == 0 else { throw RDSTLSError.authenticationFailed(result) }
    }
}

enum RDSTLSError: Error, Equatable, CustomStringConvertible {
    case invalidRedirection
    case certificateMismatch
    case invalidCapabilities
    case invalidAuthenticationResponse
    case authenticationFailed(UInt32)

    var description: String {
        switch self {
        case .invalidRedirection: "The server supplied invalid RDSTLS redirection credentials."
        case .certificateMismatch: "The RDSTLS target certificate does not match the authenticated redirection."
        case .invalidCapabilities: "The server supplied invalid RDSTLS capabilities."
        case .invalidAuthenticationResponse: "The server supplied an invalid RDSTLS authentication response."
        case .authenticationFailed(let code): "RDSTLS authentication failed with status 0x\(String(format: "%08x", code))."
        }
    }
}
