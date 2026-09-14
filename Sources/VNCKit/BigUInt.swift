import Foundation

/// Fixed-width unsigned integers for Diffie-Hellman modular exponentiation (Apple Remote Desktop
/// authentication). Little-endian 32-bit limbs; Montgomery multiplication keeps the 1024-bit
/// exponentiation fast without a general division routine.
struct ModularExponentiation {
    let modulus: [UInt32]
    private let limbs: Int
    private let negativeInverse: UInt32
    private let rSquared: [UInt32]

    init(modulusBigEndian: [UInt8]) throws {
        let modulus = Self.limbs(fromBigEndian: modulusBigEndian)
        guard let top = modulus.last, top != 0 || modulus.count == 1, modulus[0] & 1 == 1,
              !(modulus.count == 1 && modulus[0] <= 1) else {
            throw RFBError.protocolViolation("The Diffie-Hellman modulus is not an odd number greater than one.")
        }
        self.modulus = modulus
        self.limbs = modulus.count
        var inverse: UInt32 = 1
        for _ in 0..<6 { inverse = inverse &* (2 &- modulus[0] &* inverse) }
        self.negativeInverse = 0 &- inverse
        // R mod m and R^2 mod m by repeated modular doubling: 64·limbs doublings.
        var value = [UInt32](repeating: 0, count: limbs); value[0] = 1
        for _ in 0..<(64 * limbs) { value = Self.doubleMod(value, modulus) }
        self.rSquared = value
    }

    static func limbs(fromBigEndian bytes: [UInt8]) -> [UInt32] {
        var trimmed = bytes[...]
        while trimmed.count > 1, trimmed.first == 0 { trimmed = trimmed.dropFirst() }
        let count = max(1, (trimmed.count + 3) / 4)
        var limbs = [UInt32](repeating: 0, count: count)
        for (index, byte) in trimmed.reversed().enumerated() {
            limbs[index / 4] |= UInt32(byte) << UInt32(8 * (index % 4))
        }
        return limbs
    }

    static func bigEndian(_ limbs: [UInt32], byteCount: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in 0..<min(byteCount, limbs.count * 4) {
            bytes[byteCount - 1 - index] = UInt8((limbs[index / 4] >> UInt32(8 * (index % 4))) & 0xFF)
        }
        return bytes
    }

    private static func compare(_ a: [UInt32], _ b: [UInt32]) -> Int {
        for index in stride(from: max(a.count, b.count) - 1, through: 0, by: -1) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    private static func subtract(_ a: inout [UInt32], _ b: [UInt32]) {
        var borrow: UInt64 = 0
        for index in 0..<a.count {
            let y = UInt64(index < b.count ? b[index] : 0)
            let value = UInt64(a[index]) &- y &- borrow
            a[index] = UInt32(truncatingIfNeeded: value)
            borrow = (value >> 63) & 1
        }
    }

    private static func doubleMod(_ value: [UInt32], _ modulus: [UInt32]) -> [UInt32] {
        var result = [UInt32](repeating: 0, count: value.count)
        var carry: UInt32 = 0
        for index in 0..<value.count {
            result[index] = value[index] << 1 | carry
            carry = value[index] >> 31
        }
        if carry != 0 || compare(result, modulus) >= 0 { subtract(&result, modulus) }
        return result
    }

    private func montgomeryMultiply(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        let n = limbs
        var t = [UInt32](repeating: 0, count: n + 2)
        for i in 0..<n {
            var carry: UInt64 = 0
            let bi = UInt64(b[i])
            for j in 0..<n {
                let value = UInt64(t[j]) + UInt64(a[j]) * bi + carry
                t[j] = UInt32(truncatingIfNeeded: value); carry = value >> 32
            }
            var value = UInt64(t[n]) + carry
            t[n] = UInt32(truncatingIfNeeded: value); t[n + 1] = UInt32(truncatingIfNeeded: value >> 32)
            let u = UInt64(t[0] &* negativeInverse)
            carry = (UInt64(t[0]) + u * UInt64(modulus[0])) >> 32
            for j in 1..<n {
                value = UInt64(t[j]) + u * UInt64(modulus[j]) + carry
                t[j - 1] = UInt32(truncatingIfNeeded: value); carry = value >> 32
            }
            value = UInt64(t[n]) + carry
            t[n - 1] = UInt32(truncatingIfNeeded: value)
            t[n] = t[n + 1] &+ UInt32(truncatingIfNeeded: value >> 32)
            t[n + 1] = 0
        }
        var result = Array(t[0..<n])
        if t[n] != 0 || Self.compare(result, modulus) >= 0 { Self.subtract(&result, modulus) }
        return result
    }

    /// `base ^ exponent mod modulus`, requiring `base < modulus`.
    func power(baseBigEndian: [UInt8], exponentBigEndian: [UInt8]) throws -> [UInt8] {
        var base = Self.limbs(fromBigEndian: baseBigEndian)
        guard Self.compare(base, modulus) < 0 else {
            throw RFBError.protocolViolation("The Diffie-Hellman public value is not smaller than the modulus.")
        }
        base += [UInt32](repeating: 0, count: limbs - base.count)
        let baseM = montgomeryMultiply(base, rSquared)
        var one = [UInt32](repeating: 0, count: limbs); one[0] = 1
        var result = montgomeryMultiply(one, rSquared)
        for byte in exponentBigEndian {
            for bit in stride(from: 7, through: 0, by: -1) {
                result = montgomeryMultiply(result, result)
                if (byte >> UInt8(bit)) & 1 == 1 { result = montgomeryMultiply(result, baseM) }
            }
        }
        result = montgomeryMultiply(result, one)
        return Self.bigEndian(result, byteCount: limbs * 4)
    }
}
