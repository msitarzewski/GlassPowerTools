import Testing
import NIOCore
@testable import GlassSSHTransport

// Ported from glas.sh glas_shTests.swift:7436-7600 against the moved SOCKS5Protocol.
@Suite("SOCKS5 protocol")
struct SOCKS5ProtocolTests {
    @Test func greetingWaitsForAllMethodsAndRequiresUsernamePassword() {
        var fragmented = ByteBuffer(bytes: [0x05, 0x02, 0x00])
        #expect(SOCKS5Protocol.parseGreeting(from: &fragmented) == .incomplete)
        #expect(fragmented.readerIndex == 0)

        fragmented.writeInteger(UInt8(0x02))
        #expect(SOCKS5Protocol.parseGreeting(from: &fragmented) == .selectUsernamePassword)
        #expect(fragmented.readableBytes == 0)

        var unsupported = ByteBuffer(bytes: [0x05, 0x01, 0x00])
        #expect(SOCKS5Protocol.parseGreeting(from: &unsupported) == .rejectAuthenticationMethods)

        var wrongVersion = ByteBuffer(bytes: [0x04, 0x01, 0x00])
        #expect(SOCKS5Protocol.parseGreeting(from: &wrongVersion) == .invalidVersion)
    }

    @Test func rfc1929ParserIsIncrementalBoundedAndPreservesCoalescedRequest() throws {
        var authentication = ByteBuffer(bytes: [0x01, 0x04, 0x75, 0x73])
        #expect(SOCKS5Protocol.parseAuthentication(from: &authentication) == .incomplete)
        #expect(authentication.readerIndex == 0)

        authentication.writeBytes([0x65, 0x72, 0x06])
        authentication.writeBytes(Array("secret".utf8))
        authentication.writeBytes([0x05, 0x01, 0x00, 0x01])
        guard case .authenticate(let presented) = SOCKS5Protocol.parseAuthentication(from: &authentication) else {
            Issue.record("Expected parsed RFC 1929 credentials")
            return
        }
        #expect(presented.username == Array("user".utf8))
        #expect(presented.password == Array("secret".utf8))
        #expect(authentication.getBytes(at: authentication.readerIndex, length: authentication.readableBytes) == [0x05, 0x01, 0x00, 0x01])

        var emptyUsername = ByteBuffer(bytes: [0x01, 0x00])
        #expect(SOCKS5Protocol.parseAuthentication(from: &emptyUsername) == .invalidCredentials)
        var wrongVersion = ByteBuffer(bytes: [0x02, 0x01])
        #expect(SOCKS5Protocol.parseAuthentication(from: &wrongVersion) == .invalidVersion)
        #expect(SOCKS5Protocol.maximumAuthenticationBytes == 513)

        var bounded = ByteBuffer(bytes: Array(repeating: UInt8(0), count: SOCKS5Protocol.maximumBufferedHandshakeBytes))
        var excess = ByteBuffer(bytes: [0x00])
        #expect(!SOCKS5Protocol.appendHandshakeBytes(&excess, to: &bounded))
    }

    @Test func credentialPolicyValidatesUTF8LengthsAndComparesBothFields() throws {
        let expected = try #require(SOCKS5Protocol.credentials(username: "user", password: "secret"))
        #expect(SOCKS5Protocol.credentials(username: "", password: "secret") == nil)
        #expect(SOCKS5Protocol.credentials(username: "user", password: "") == nil)
        #expect(SOCKS5Protocol.credentials(username: String(repeating: "u", count: 256), password: "secret") == nil)
        #expect(SOCKS5Credentials(username: "user", password: "secret") != nil)
        #expect(SOCKS5Credentials(username: "", password: "secret") == nil)

        #expect(SOCKS5Protocol.authenticate(presented: expected, expected: expected))
        #expect(!SOCKS5Protocol.authenticate(presented: .init(username: Array("user".utf8), password: Array("secreu".utf8)), expected: expected))
        #expect(!SOCKS5Protocol.authenticate(presented: .init(username: Array("admin".utf8), password: Array("secret".utf8)), expected: expected))
        #expect(!SOCKS5Protocol.constantTimeFieldEquals(Array("user".utf8), Array("user\0".utf8)))
    }

    @Test func connectionLimiterRejectsExcessPreAuthenticationClients() async {
        let limiter = SOCKS5ConnectionLimiter(maximumConnections: 2)
        #expect(await limiter.acquire())
        #expect(await limiter.acquire())
        #expect(!(await limiter.acquire()))
        await limiter.release()
        #expect(await limiter.acquire())
        #expect(SOCKS5Protocol.maximumConcurrentConnections == 64)
        #expect(SOCKS5Protocol.handshakeTimeout == .seconds(15))
    }

    @Test func handshakePermitReleasesItsSlotExactlyOnce() async {
        let limiter = SOCKS5ConnectionLimiter(maximumConnections: 1)
        #expect(await limiter.acquire())
        let permit = SOCKS5ConnectionPermit(limiter: limiter)
        await permit.release()
        await permit.release()
        #expect(await limiter.acquire())
        #expect(!(await limiter.acquire()))
    }

    @Test func connectParserPreservesCoalescedPayload() {
        let domain = Array("example.com".utf8)
        var bytes: [UInt8] = [0x05, 0x01, 0x00, 0x03, UInt8(domain.count)]
        bytes.append(contentsOf: domain)
        bytes.append(contentsOf: [0x01, 0xBB])
        bytes.append(contentsOf: Array("GET /".utf8))
        var buffer = ByteBuffer(bytes: bytes)
        #expect(SOCKS5Protocol.parseConnectRequest(from: &buffer) == .connect(SOCKS5Target(host: "example.com", port: 443)))
        #expect(buffer.readString(length: buffer.readableBytes) == "GET /")
    }

    @Test func connectParserHandlesFragmentedIPv4AndValidatesHeader() {
        var fragmented = ByteBuffer(bytes: [0x05, 0x01, 0x00, 0x01, 127])
        #expect(SOCKS5Protocol.parseConnectRequest(from: &fragmented) == .incomplete)
        #expect(fragmented.readerIndex == 0)
        fragmented.writeBytes([0, 0, 1, 0x1F, 0x90])
        #expect(SOCKS5Protocol.parseConnectRequest(from: &fragmented) == .connect(SOCKS5Target(host: "127.0.0.1", port: 8080)))

        var badReserved = ByteBuffer(bytes: [0x05, 0x01, 0x01, 0x01])
        #expect(SOCKS5Protocol.parseConnectRequest(from: &badReserved) == .invalidReservedByte)
        var unsupportedCommand = ByteBuffer(bytes: [0x05, 0x02, 0x00, 0x01])
        #expect(SOCKS5Protocol.parseConnectRequest(from: &unsupportedCommand) == .unsupportedCommand)
        var unsupportedAddress = ByteBuffer(bytes: [0x05, 0x01, 0x00, 0x09])
        #expect(SOCKS5Protocol.parseConnectRequest(from: &unsupportedAddress) == .unsupportedAddressType)
        var zeroPort = ByteBuffer(bytes: [0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 0])
        #expect(SOCKS5Protocol.parseConnectRequest(from: &zeroPort) == .invalidAddress)
    }
}
