import CommonCrypto
import Foundation
import Testing
@testable import VNCKit

@Suite("Security primitives")
struct SecurityTests {
    @Test func bitReversal() {
        #expect(RFBSecurity.reverseBits(0b1000_0000) == 0b0000_0001)
        #expect(RFBSecurity.reverseBits(0b1011_0010) == 0b0100_1101)
        #expect(RFBSecurity.reverseBits(0xFF) == 0xFF)
    }

    /// Classic DES known answer ("The DES Algorithm Illustrated"): key 133457799BBCDFF1,
    /// plaintext 0123456789ABCDEF, ciphertext 85E813540F0AB405.
    @Test func desKnownAnswer() throws {
        let out = try RFBSecurity.encryptECB(algorithm: CCAlgorithm(kCCAlgorithmDES), key: hexBytes("133457799bbcdff1"),
                                             plaintext: hexBytes("0123456789abcdef"))
        #expect(out.hex == "85e813540f0ab405")
    }

    /// FIPS-197 Appendix C.1 AES-128 known answer.
    @Test func aesKnownAnswer() throws {
        let out = try RFBSecurity.encryptECB(algorithm: CCAlgorithm(kCCAlgorithmAES128), key: hexBytes("000102030405060708090a0b0c0d0e0f"),
                                             plaintext: hexBytes("00112233445566778899aabbccddeeff"))
        #expect(out.hex == "69c4e0d86a7b0430d8cdb78070b4c55a")
    }

    /// The VNC key is the password bit-reversed per byte; a plain "password" therefore encrypts
    /// each 8-byte challenge block with DES key derived from bit-reversed "password".
    @Test func vncAuthenticationUsesReversedPasswordKey() throws {
        let challenge = hexBytes("0123456789abcdef0123456789abcdef")
        let response = try RFBSecurity.vncAuthenticationResponse(challenge: challenge, password: "pässword-too-long")
        let key = Array("pässword-too-long".utf8).prefix(8).map(RFBSecurity.reverseBits)
        let expected = try RFBSecurity.encryptECB(algorithm: CCAlgorithm(kCCAlgorithmDES), key: Array(key), plaintext: challenge)
        #expect(response == expected)
        #expect(response.count == 16)
        #expect(response[0..<8] == response[8..<16])
        #expect(throws: RFBError.self) { try RFBSecurity.vncAuthenticationResponse(challenge: [1, 2, 3], password: "x") }
    }

    @Test func modularExponentiationSmallAndMedium() throws {
        let small = try ModularExponentiation(modulusBigEndian: [11])
        #expect(RFBSecurity.fit(try small.power(baseBigEndian: [3], exponentBigEndian: [7]), to: 1) == [9])
        let medium = try ModularExponentiation(modulusBigEndian: bigEndianBytes(Vectors.midModulus))
        let result = try medium.power(baseBigEndian: bigEndianBytes(Vectors.midBase), exponentBigEndian: bigEndianBytes(Vectors.midExponent))
        #expect(RFBSecurity.fit(result, to: 8) == RFBSecurity.fit(bigEndianBytes(Vectors.midResult), to: 8))
        #expect(throws: RFBError.self) { try ModularExponentiation(modulusBigEndian: [12]) }
        #expect(throws: RFBError.self) { try small.power(baseBigEndian: [11], exponentBigEndian: [1]) }
    }

    @Test func modularExponentiation1024BitMatchesPython() throws {
        let exponentiation = try ModularExponentiation(modulusBigEndian: hexBytes(Vectors.prime))
        let publicKey = try exponentiation.power(baseBigEndian: [2], exponentBigEndian: hexBytes(Vectors.clientPrivate))
        #expect(RFBSecurity.fit(publicKey, to: 128).hex == Vectors.clientPublic)
        let shared = try exponentiation.power(baseBigEndian: hexBytes(Vectors.serverPublic), exponentBigEndian: hexBytes(Vectors.clientPrivate))
        #expect(RFBSecurity.fit(shared, to: 128).hex == Vectors.shared)
    }

    @Test func appleRemoteDesktopResponseLayout() throws {
        let challenge = try RFBSecurity.AppleRemoteDesktopChallenge.parse(
            generator: 2, keyLength: 128, body: hexBytes(Vectors.prime) + hexBytes(Vectors.serverPublic))
        var randomCalls: [Int] = []
        let response = try RFBSecurity.appleRemoteDesktopResponse(challenge, username: "alice", password: "secret") { count in
            randomCalls.append(count)
            return count == 128 && randomCalls.count == 1 ? hexBytes(Vectors.clientPrivate) : [UInt8](repeating: 0x5A, count: count)
        }
        #expect(randomCalls == [128, 128])
        #expect(response.clientPublicKey.hex == Vectors.clientPublic)
        #expect(response.encryptedCredentials.count == 128)
        #expect(response.wireBytes.count == 256)
        // Decrypt with the expected AES key to confirm the credential block layout.
        var plain = [UInt8](repeating: 0, count: 144)
        var moved = 0
        let key = hexBytes(Vectors.aesKeyMD5)
        let status = key.withUnsafeBytes { k in
            response.encryptedCredentials.withUnsafeBytes { c in
                plain.withUnsafeMutableBytes { p in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionECBMode), k.baseAddress, 16,
                            nil, c.baseAddress, 128, p.baseAddress, 144, &moved)
                }
            }
        }
        #expect(status == kCCSuccess && moved == 128)
        #expect(Array(plain[0..<5]) == Array("alice".utf8))
        #expect(plain[5] == 0)
        #expect(plain[6] == 0x5A)
        #expect(Array(plain[64..<70]) == Array("secret".utf8))
        #expect(plain[70] == 0)
        #expect(plain[127] == 0x5A)
        #expect(throws: RFBError.self) {
            try RFBSecurity.appleRemoteDesktopResponse(challenge, username: String(repeating: "a", count: 64), password: "x")
        }
        #expect(throws: RFBError.self) {
            try RFBSecurity.AppleRemoteDesktopChallenge.parse(generator: 2, keyLength: 8, body: [UInt8](repeating: 1, count: 16))
        }
        #expect(throws: RFBError.self) {
            try RFBSecurity.AppleRemoteDesktopChallenge.parse(generator: 2, keyLength: 128, body: [UInt8](repeating: 1, count: 100))
        }
    }
}
