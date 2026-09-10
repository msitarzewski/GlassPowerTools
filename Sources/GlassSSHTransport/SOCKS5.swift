import Foundation
import NIOCore

// The SOCKS5 (RFC 1928 / RFC 1929) parsing, credential policy and connection limiting moved
// verbatim from glas.sh PortForwardManager.swift:16-80 and :775-960. The server loop that
// uses them is in SSHTunnels.swift.

public struct SOCKS5Target: Equatable, Sendable, Hashable {
    public let host: String
    public let port: Int
    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public enum SOCKS5GreetingParseResult: Equatable, Sendable {
    case incomplete
    case selectUsernamePassword
    case rejectAuthenticationMethods
    case invalidVersion
}

public struct SOCKS5CredentialBytes: Equatable, Sendable {
    public let username: [UInt8]
    public let password: [UInt8]
    public init(username: [UInt8], password: [UInt8]) {
        self.username = username
        self.password = password
    }
}

public enum SOCKS5AuthenticationParseResult: Equatable, Sendable {
    case incomplete
    case authenticate(SOCKS5CredentialBytes)
    case invalidVersion
    case invalidCredentials
}

public enum SOCKS5RequestParseResult: Equatable, Sendable {
    case incomplete
    case connect(SOCKS5Target)
    case invalidVersion
    case invalidReservedByte
    case unsupportedCommand
    case unsupportedAddressType
    case invalidAddress
}

/// Proxy credentials for one dynamic forward. Process-memory only: never encoded, logged or
/// persisted. Construction validates RFC 1929's 1...255-byte field lengths.
public struct SOCKS5Credentials: Sendable, Equatable {
    let bytes: SOCKS5CredentialBytes
    public init?(username: String, password: String) {
        guard let bytes = SOCKS5Protocol.credentials(username: username, password: password) else { return nil }
        self.bytes = bytes
    }
}

public actor SOCKS5ConnectionLimiter {
    private let maximumConnections: Int
    private var activeConnections = 0

    public init(maximumConnections: Int) {
        self.maximumConnections = max(1, maximumConnections)
    }

    public func acquire() -> Bool {
        guard activeConnections < maximumConnections else { return false }
        activeConnections += 1
        return true
    }

    public func release() {
        activeConnections = max(0, activeConnections - 1)
    }
}

/// An idempotent permit keeps failed and cancelled handshakes from leaking a limiter slot
/// while allowing established tunnels to run independently of the pre-authentication cap.
public actor SOCKS5ConnectionPermit {
    private let limiter: SOCKS5ConnectionLimiter
    private var isReleased = false

    public init(limiter: SOCKS5ConnectionLimiter) {
        self.limiter = limiter
    }

    public func release() async {
        guard !isReleased else { return }
        isReleased = true
        await limiter.release()
    }
}

public enum SOCKS5Protocol {
    public static let maximumConcurrentConnections = 64
    public static let handshakeTimeout: Duration = .seconds(15)
    public static let maximumGreetingBytes = 257
    public static let maximumAuthenticationBytes = 513
    public static let maximumConnectRequestBytes = 262
    public static let maximumBufferedHandshakeBytes = 64 * 1024

    public static func appendHandshakeBytes(_ chunk: inout ByteBuffer, to buffer: inout ByteBuffer) -> Bool {
        guard buffer.readableBytes <= maximumBufferedHandshakeBytes,
              chunk.readableBytes <= maximumBufferedHandshakeBytes - buffer.readableBytes else {
            return false
        }
        buffer.writeBuffer(&chunk)
        return true
    }

    public static func credentials(username: String, password: String) -> SOCKS5CredentialBytes? {
        let usernameBytes = Array(username.utf8)
        let passwordBytes = Array(password.utf8)
        guard (1...255).contains(usernameBytes.count), (1...255).contains(passwordBytes.count) else {
            return nil
        }
        return SOCKS5CredentialBytes(username: usernameBytes, password: passwordBytes)
    }

    /// Fixed-work comparison across RFC 1929's entire 255-byte field capacity. Both username
    /// and password comparisons are always evaluated by the caller.
    public static func constantTimeFieldEquals(_ presented: [UInt8], _ expected: [UInt8]) -> Bool {
        var difference = UInt16(presented.count ^ expected.count)
        for index in 0..<255 {
            let presentedByte = index < presented.count ? presented[index] : 0
            let expectedByte = index < expected.count ? expected[index] : 0
            difference |= UInt16(presentedByte ^ expectedByte)
        }
        return difference == 0
    }

    public static func authenticate(presented: SOCKS5CredentialBytes, expected: SOCKS5CredentialBytes) -> Bool {
        let usernameMatches = constantTimeFieldEquals(presented.username, expected.username)
        let passwordMatches = constantTimeFieldEquals(presented.password, expected.password)
        return usernameMatches && passwordMatches
    }

    public static func parseGreeting(from buffer: inout ByteBuffer) -> SOCKS5GreetingParseResult {
        let start = buffer.readerIndex
        guard buffer.readableBytes >= 2,
              let version = buffer.getInteger(at: start, as: UInt8.self),
              let methodCount = buffer.getInteger(at: start + 1, as: UInt8.self) else {
            return .incomplete
        }
        guard version == 0x05 else {
            buffer.moveReaderIndex(forwardBy: 2)
            return .invalidVersion
        }
        let messageLength = 2 + Int(methodCount)
        guard messageLength <= maximumGreetingBytes else {
            buffer.moveReaderIndex(forwardBy: 2)
            return .rejectAuthenticationMethods
        }
        guard buffer.readableBytes >= messageLength,
              let methods = buffer.getBytes(at: start + 2, length: Int(methodCount)) else {
            return .incomplete
        }
        buffer.moveReaderIndex(forwardBy: messageLength)
        guard methods.contains(0x02) else {
            return .rejectAuthenticationMethods
        }
        return .selectUsernamePassword
    }

    public static func parseAuthentication(from buffer: inout ByteBuffer) -> SOCKS5AuthenticationParseResult {
        let start = buffer.readerIndex
        guard buffer.readableBytes >= 2,
              let version = buffer.getInteger(at: start, as: UInt8.self),
              let usernameLength = buffer.getInteger(at: start + 1, as: UInt8.self) else {
            return .incomplete
        }
        guard version == 0x01 else {
            buffer.moveReaderIndex(forwardBy: 2)
            return .invalidVersion
        }
        guard usernameLength > 0 else {
            buffer.moveReaderIndex(forwardBy: 2)
            return .invalidCredentials
        }
        let passwordLengthIndex = start + 2 + Int(usernameLength)
        guard buffer.writerIndex > passwordLengthIndex,
              let passwordLength = buffer.getInteger(at: passwordLengthIndex, as: UInt8.self) else {
            return .incomplete
        }
        guard passwordLength > 0 else {
            buffer.moveReaderIndex(forwardBy: 3 + Int(usernameLength))
            return .invalidCredentials
        }
        let messageLength = 3 + Int(usernameLength) + Int(passwordLength)
        guard messageLength <= maximumAuthenticationBytes else {
            buffer.moveReaderIndex(forwardBy: 2)
            return .invalidCredentials
        }
        guard buffer.readableBytes >= messageLength,
              let username = buffer.getBytes(at: start + 2, length: Int(usernameLength)),
              let password = buffer.getBytes(at: passwordLengthIndex + 1, length: Int(passwordLength)) else {
            return .incomplete
        }
        buffer.moveReaderIndex(forwardBy: messageLength)
        return .authenticate(.init(username: username, password: password))
    }

    public static func parseConnectRequest(from buffer: inout ByteBuffer) -> SOCKS5RequestParseResult {
        let start = buffer.readerIndex
        guard buffer.readableBytes >= 4,
              let version = buffer.getInteger(at: start, as: UInt8.self),
              let command = buffer.getInteger(at: start + 1, as: UInt8.self),
              let reserved = buffer.getInteger(at: start + 2, as: UInt8.self),
              let addressType = buffer.getInteger(at: start + 3, as: UInt8.self) else {
            return .incomplete
        }
        guard version == 0x05 else {
            buffer.moveReaderIndex(forwardBy: 4)
            return .invalidVersion
        }
        guard reserved == 0x00 else {
            buffer.moveReaderIndex(forwardBy: 4)
            return .invalidReservedByte
        }
        guard command == 0x01 else {
            buffer.moveReaderIndex(forwardBy: 4)
            return .unsupportedCommand
        }

        let host: String
        let requestLength: Int
        switch addressType {
        case 0x01:
            requestLength = 10
            guard buffer.readableBytes >= requestLength,
                  let address = buffer.getBytes(at: start + 4, length: 4) else {
                return .incomplete
            }
            host = address.map(String.init).joined(separator: ".")
        case 0x03:
            guard buffer.readableBytes >= 5,
                  let nameLength = buffer.getInteger(at: start + 4, as: UInt8.self) else {
                return .incomplete
            }
            guard nameLength > 0 else {
                buffer.moveReaderIndex(forwardBy: 5)
                return .invalidAddress
            }
            requestLength = 7 + Int(nameLength)
            guard buffer.readableBytes >= requestLength,
                  let nameBytes = buffer.getBytes(at: start + 5, length: Int(nameLength)),
                  let name = String(bytes: nameBytes, encoding: .utf8) else {
                return buffer.readableBytes >= requestLength ? .invalidAddress : .incomplete
            }
            host = name
        case 0x04:
            requestLength = 22
            guard buffer.readableBytes >= requestLength else {
                return .incomplete
            }
            var segments: [String] = []
            segments.reserveCapacity(8)
            for offset in stride(from: 4, to: 20, by: 2) {
                guard let segment = buffer.getInteger(at: start + offset, endianness: .big, as: UInt16.self) else {
                    return .incomplete
                }
                segments.append(String(segment, radix: 16))
            }
            host = segments.joined(separator: ":")
        default:
            buffer.moveReaderIndex(forwardBy: 4)
            return .unsupportedAddressType
        }

        guard requestLength <= maximumConnectRequestBytes else {
            buffer.moveReaderIndex(forwardBy: 4)
            return .invalidAddress
        }
        guard let port = buffer.getInteger(at: start + requestLength - 2, endianness: .big, as: UInt16.self) else {
            return .incomplete
        }
        buffer.moveReaderIndex(forwardBy: requestLength)
        guard port > 0 else {
            return .invalidAddress
        }
        return .connect(SOCKS5Target(host: host, port: Int(port)))
    }

    static func reply(code: UInt8) -> ByteBuffer {
        var reply = ByteBuffer()
        reply.writeBytes([0x05, code, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        return reply
    }
}
