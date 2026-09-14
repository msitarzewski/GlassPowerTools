import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Authentication primitives for the supported security types.
enum RFBSecurity {
    /// VNC Authentication (RFC 6143 §7.2.2): the 16-byte challenge is DES-ECB encrypted with a key
    /// made from the first eight password bytes, each with its bit order reversed (the historic
    /// VNC quirk that every server honours).
    static func vncAuthenticationResponse(challenge: [UInt8], password: String) throws -> [UInt8] {
        guard challenge.count == 16 else { throw RFBError.protocolViolation("The VNC authentication challenge is malformed.") }
        var key = [UInt8](repeating: 0, count: 8)
        for (index, byte) in Array(password.utf8).prefix(8).enumerated() {
            key[index] = reverseBits(byte)
        }
        defer { key = [UInt8](repeating: 0, count: 8) }
        return try encryptECB(algorithm: CCAlgorithm(kCCAlgorithmDES), key: key, plaintext: challenge)
    }

    static func reverseBits(_ byte: UInt8) -> UInt8 {
        var value = byte, result: UInt8 = 0
        for _ in 0..<8 { result = result << 1 | (value & 1); value >>= 1 }
        return result
    }

    /// Apple Remote Desktop authentication (security type 30), as implemented by Apple Screen
    /// Sharing and the open-source clients that interoperate with it (libvncclient, gtk-vnc):
    /// the server sends a Diffie-Hellman generator, key length, prime and public value; the client
    /// answers with AES-128-ECB(MD5(shared secret)) of a 128-byte block holding the user name and
    /// password, followed by its own public value.
    struct AppleRemoteDesktopChallenge: Equatable, Sendable {
        let generator: UInt16
        let keyLength: Int
        let prime: [UInt8]
        let serverPublicKey: [UInt8]

        static func parse(generator: UInt16, keyLength: UInt16, body: [UInt8]) throws -> AppleRemoteDesktopChallenge {
            let length = Int(keyLength)
            guard length >= RFBLimits.minimumDiffieHellmanKeyBytes, length <= RFBLimits.maximumDiffieHellmanKeyBytes,
                  body.count == length * 2, generator >= 2 else {
                throw RFBError.protocolViolation("The Apple Remote Desktop authentication parameters are invalid.")
            }
            return AppleRemoteDesktopChallenge(generator: generator, keyLength: length,
                                               prime: Array(body[0..<length]), serverPublicKey: Array(body[length..<(2 * length)]))
        }
    }

    struct AppleRemoteDesktopResponse: Equatable {
        let encryptedCredentials: [UInt8]
        let clientPublicKey: [UInt8]
        var wireBytes: [UInt8] { encryptedCredentials + clientPublicKey }
    }

    static func appleRemoteDesktopResponse(_ challenge: AppleRemoteDesktopChallenge, username: String, password: String,
                                           random: (Int) throws -> [UInt8] = secureRandom) throws -> AppleRemoteDesktopResponse {
        guard username.utf8.count <= 63, password.utf8.count <= 63 else {
            throw RFBError.invalidConfiguration("Apple Remote Desktop authentication supports user names and passwords of up to 63 bytes.")
        }
        let exponentiation = try ModularExponentiation(modulusBigEndian: challenge.prime)
        var privateKey = try random(challenge.keyLength)
        defer { privateKey = [UInt8](repeating: 0, count: privateKey.count) }
        var generator = challenge.generator.bigEndianBytes
        while generator.count > 1, generator[0] == 0 { generator.removeFirst() }
        let clientPublicKey = fit(try exponentiation.power(baseBigEndian: generator, exponentBigEndian: privateKey), to: challenge.keyLength)
        var sharedSecret = fit(try exponentiation.power(baseBigEndian: challenge.serverPublicKey, exponentBigEndian: privateKey),
                               to: challenge.keyLength)
        defer { sharedSecret = [UInt8](repeating: 0, count: sharedSecret.count) }
        var aesKey = Array(Insecure.MD5.hash(data: sharedSecret))
        defer { aesKey = [UInt8](repeating: 0, count: aesKey.count) }
        var credentials = try random(128)
        defer { credentials = [UInt8](repeating: 0, count: credentials.count) }
        for (index, byte) in Array(username.utf8).enumerated() { credentials[index] = byte }
        credentials[username.utf8.count] = 0
        for (index, byte) in Array(password.utf8).enumerated() { credentials[64 + index] = byte }
        credentials[64 + password.utf8.count] = 0
        let encrypted = try encryptECB(algorithm: CCAlgorithm(kCCAlgorithmAES128), key: aesKey, plaintext: credentials)
        return AppleRemoteDesktopResponse(encryptedCredentials: encrypted, clientPublicKey: clientPublicKey)
    }

    static func fit(_ bytes: [UInt8], to length: Int) -> [UInt8] {
        if bytes.count == length { return bytes }
        if bytes.count > length { return Array(bytes[(bytes.count - length)...]) }
        return [UInt8](repeating: 0, count: length - bytes.count) + bytes
    }

    static func secureRandom(_ count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw RFBError.connectionFailed("Secure random bytes are unavailable.")
        }
        return bytes
    }

    static func encryptECB(algorithm: CCAlgorithm, key: [UInt8], plaintext: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: plaintext.count + 16)
        var moved = 0
        let status = key.withUnsafeBytes { keyBytes in
            plaintext.withUnsafeBytes { input in
                output.withUnsafeMutableBytes { out in
                    CCCrypt(CCOperation(kCCEncrypt), algorithm, CCOptions(kCCOptionECBMode), keyBytes.baseAddress, key.count,
                            nil, input.baseAddress, plaintext.count, out.baseAddress, out.count, &moved)
                }
            }
        }
        guard status == kCCSuccess, moved == plaintext.count else {
            throw RFBError.connectionFailed("The authentication response could not be encrypted.")
        }
        return Array(output[0..<moved])
    }
}
