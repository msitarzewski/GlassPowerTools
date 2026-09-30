import Foundation
import Testing
@testable import VNCKit

private final class Collected: @unchecked Sendable {
    let lock = NSLock()
    var infos: [VNCServerInfo] = []
    var frames: [(Int, Int, Data)] = []
    var cursors: [VNCCursorImage?] = []
    var texts: [String] = []
    var screens: [[VNCScreen]] = []
    var resizeSupported = 0
    var callbacks: VNCClientCallbacks {
        var value = VNCClientCallbacks()
        value.connected = { info in self.lock.withLock { self.infos.append(info) } }
        value.frame = { w, h, data in self.lock.withLock { self.frames.append((w, h, data)) } }
        value.cursor = { cursor in self.lock.withLock { self.cursors.append(cursor) } }
        value.cutText = { text in self.lock.withLock { self.texts.append(text) } }
        value.desktopResizeSupported = { self.lock.withLock { self.resizeSupported += 1 } }
        value.screens = { list in self.lock.withLock { self.screens.append(list) } }
        return value
    }
}

private func serverInit(width: UInt16, height: UInt16, name: String) -> [UInt8] {
    var bytes = width.bigEndianBytes
    bytes += height.bigEndianBytes
    bytes += RFBPixelFormat.client.wireBytes
    bytes += UInt32(name.utf8.count).bigEndianBytes
    bytes += Array(name.utf8)
    return bytes
}

private func rectHeader(_ x: UInt16, _ y: UInt16, _ w: UInt16, _ h: UInt16, _ encoding: Int32) -> [UInt8] {
    var bytes = x.bigEndianBytes
    bytes += y.bigEndianBytes
    bytes += w.bigEndianBytes
    bytes += h.bigEndianBytes
    bytes += encoding.bigEndianBytes
    return bytes
}

@Suite("Client session")
struct ClientTests {
    @Test func vncAuthenticationHandshakeAndUpdates() async throws {
        let challenge = [UInt8](repeating: 0x42, count: 16)
        var server: [UInt8] = Array("RFB 003.008\n".utf8)
        server += [2, 30, 2]
        server += challenge
        server += UInt32(0).bigEndianBytes
        server += serverInit(width: 4, height: 2, name: "Fixture")
        // Update: raw rectangle, cursor, then LastRect terminates a claimed count of 3.
        server += [0, 0] + UInt16(3).bigEndianBytes
        server += rectHeader(0, 0, 4, 2, 0)
        for index in 0..<8 { server += [UInt8(index), 1, 2, 0] }
        server += rectHeader(1, 1, 2, 2, -239)
        server += [UInt8](repeating: 9, count: 16)
        server += [0b1100_0000, 0b0100_0000]
        server += rectHeader(0, 0, 0, 0, -224)
        // ServerCutText, a bell, then EOF.
        server += [3, 0, 0, 0]
        server += UInt32(3).bigEndianBytes
        server += Array("hé!".unicodeScalars.map { UInt8($0.value) })
        server += [2]
        let source = MemoryByteSource(server), sink = MemoryByteSink()
        let collected = Collected()
        let client = VNCClient(configuration: VNCConfiguration(host: "fixture", password: "secret", clipboardEnabled: true),
                               callbacks: collected.callbacks, source: source, sink: sink)
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }
        let written = await sink.written
        #expect(Array(written[0..<12]) == Array("RFB 003.008\n".utf8))
        #expect(written[12] == 2)
        let expectedResponse = try RFBSecurity.vncAuthenticationResponse(challenge: challenge, password: "secret")
        #expect(Array(written[13..<29]) == expectedResponse)
        #expect(written[29] == 1)
        #expect(Array(written[30..<50]) == [0, 0, 0, 0] + RFBPixelFormat.client.wireBytes)
        #expect(written[50] == 2)
        let encodingCount = Int(written[52]) << 8 | Int(written[53])
        #expect(encodingCount == RFBEncoding.advertised.count)
        let requestOffset = 54 + encodingCount * 4
        #expect(Array(written[requestOffset..<(requestOffset + 10)]) == [3, 0, 0, 0, 0, 0, 0, 4, 0, 2])
        #expect(Array(written[(requestOffset + 10)..<(requestOffset + 20)]) == [3, 1, 0, 0, 0, 0, 0, 4, 0, 2])
        #expect(collected.infos.count == 1)
        #expect(collected.infos.first?.securityType == .vncAuthentication)
        #expect(collected.infos.first?.name == "Fixture")
        #expect(collected.frames.count == 1)
        #expect(collected.frames.first?.2[0..<4] == Data([0, 1, 2, 255]))
        #expect(collected.cursors.count == 1)
        #expect(collected.cursors.first??.hotSpotX == 1)
        #expect(collected.texts == ["hé!"])
        #expect(client.isReady == false)
    }

    @Test func appleRemoteDesktopIsChosenWithAccount() async throws {
        let prime = hexBytes(Vectors.prime), serverPublic = hexBytes(Vectors.serverPublic)
        var server: [UInt8] = Array("RFB 003.889\n".utf8)
        server += [2, 30, 35]
        server += UInt16(2).bigEndianBytes
        server += UInt16(128).bigEndianBytes
        server += prime
        server += serverPublic
        server += UInt32(1).bigEndianBytes
        server += UInt32(15).bigEndianBytes
        server += Array("Wrong password.".utf8)
        let source = MemoryByteSource(server), sink = MemoryByteSink()
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.local", username: "alice", password: "secret"),
                               callbacks: VNCClientCallbacks(), source: source, sink: sink)
        await #expect(throws: RFBError.authenticationFailed("Wrong password.")) { try await client.run() }
        let written = await sink.written
        #expect(written[12] == 30)
        #expect(written.count == 13 + 256)
    }

    @Test func serverRefusalAndUnsupportedTypes() async throws {
        var refused: [UInt8] = Array("RFB 003.008\n".utf8)
        refused += [0]
        refused += UInt32(4).bigEndianBytes
        refused += Array("Busy".utf8)
        let client = VNCClient(configuration: VNCConfiguration(host: "x", password: ""), callbacks: VNCClientCallbacks(),
                               source: MemoryByteSource(refused), sink: MemoryByteSink())
        await #expect(throws: RFBError.connectionFailed("The server refused the connection: Busy")) { try await client.run() }

        var onlyARD: [UInt8] = Array("RFB 003.889\n".utf8)
        onlyARD += [1, 30]
        let noAccount = VNCClient(configuration: VNCConfiguration(host: "x", password: "pw"), callbacks: VNCClientCallbacks(),
                                  source: MemoryByteSource(onlyARD), sink: MemoryByteSink())
        await #expect(throws: RFBError.self) { try await noAccount.run() }

        var tls: [UInt8] = Array("RFB 003.008\n".utf8)
        tls += [1, 19]
        let unsupported = VNCClient(configuration: VNCConfiguration(host: "x", password: "pw"), callbacks: VNCClientCallbacks(),
                                    source: MemoryByteSource(tls), sink: MemoryByteSink())
        await #expect(throws: RFBError.self) { try await unsupported.run() }

        var version33: [UInt8] = Array("RFB 003.003\n".utf8)
        version33 += UInt32(1).bigEndianBytes
        version33 += serverInit(width: 2, height: 2, name: "")
        let legacy = VNCClient(configuration: VNCConfiguration(host: "x", password: ""), callbacks: VNCClientCallbacks(),
                               source: MemoryByteSource(version33), sink: MemoryByteSink())
        await #expect(throws: RFBError.connectionClosed) { try await legacy.run() }
    }

    @Test func desktopSizeChangesResizeTheFramebuffer() async throws {
        var server: [UInt8] = Array("RFB 003.008\n".utf8)
        server += [1, 1]
        server += UInt32(0).bigEndianBytes
        server += serverInit(width: 2, height: 2, name: "")
        server += [0, 0, 0, 1]
        server += rectHeader(0, 0, 3, 3, -308)
        server += [1, 0, 0, 0]
        server += [UInt8](repeating: 0, count: 16)
        server += [0, 0, 0, 1]
        server += rectHeader(0, 0, 3, 3, 1)
        server += [0, 0, 0, 0]
        let collected = Collected()
        let client = VNCClient(configuration: VNCConfiguration(host: "x", password: ""), callbacks: collected.callbacks,
                               source: MemoryByteSource(server), sink: MemoryByteSink())
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }
        #expect(collected.resizeSupported == 1)
        #expect(collected.frames.map { ($0.0, $0.1) }.last.map { $0 == (3, 3) } == true)
        #expect(collected.frames.last?.2.count == 36)
    }

    /// The next update is requested as soon as an update begins, not after it is decoded: the
    /// request is on the wire even though this update's only rectangle is rejected.
    @Test func theNextUpdateIsRequestedBeforeThisOneIsDecoded() async throws {
        var server: [UInt8] = Array("RFB 003.008\n".utf8)
        server += [1, 1]
        server += UInt32(0).bigEndianBytes
        server += serverInit(width: 2, height: 2, name: "")
        server += [0, 0, 0, 1]
        server += rectHeader(1, 0, 2, 1, 0)   // outside the framebuffer: decoding fails
        let sink = MemoryByteSink()
        await #expect(throws: RFBError.self) {
            try await VNCClient(configuration: VNCConfiguration(host: "x", password: ""), callbacks: VNCClientCallbacks(),
                                source: MemoryByteSource(server), sink: sink).run()
        }
        let written = await sink.written
        let requests = stride(from: 0, to: written.count - 9, by: 1).filter {
            written[$0] == 3 && Array(written[($0 + 2)..<($0 + 10)]) == [0, 0, 0, 0, 0, 2, 0, 2]
        }.map { written[$0 + 1] }
        #expect(requests == [0, 1], "the first full request, then the incremental one sent before the rectangle")
    }

    @Test func malformedServerMessagesFail() async throws {
        var base: [UInt8] = Array("RFB 003.008\n".utf8)
        base += [1, 1]
        base += UInt32(0).bigEndianBytes
        var hugeName = base
        hugeName += [0, 2, 0, 2]
        hugeName += RFBPixelFormat.client.wireBytes
        hugeName += UInt32(5000).bigEndianBytes
        await #expect(throws: RFBError.self) {
            try await VNCClient(configuration: VNCConfiguration(host: "x", password: ""), callbacks: VNCClientCallbacks(),
                                source: MemoryByteSource(hugeName), sink: MemoryByteSink()).run()
        }
        var outside = base
        outside += serverInit(width: 2, height: 2, name: "")
        outside += [0, 0, 0, 1]
        outside += rectHeader(1, 0, 2, 1, 0)
        await #expect(throws: RFBError.self) {
            try await VNCClient(configuration: VNCConfiguration(host: "x", password: ""), callbacks: VNCClientCallbacks(),
                                source: MemoryByteSource(outside), sink: MemoryByteSink()).run()
        }
        var unknown = base
        unknown += serverInit(width: 2, height: 2, name: "")
        unknown += [200]
        await #expect(throws: RFBError.protocolViolation("The server sent an unknown message type 200.")) {
            try await VNCClient(configuration: VNCConfiguration(host: "x", password: ""), callbacks: VNCClientCallbacks(),
                                source: MemoryByteSource(unknown), sink: MemoryByteSink()).run()
        }
    }

    @Test func inputMessages() async throws {
        let sink = MemoryByteSink()
        var handshake: [UInt8] = Array("RFB 003.008\n".utf8)
        handshake += [1, 1]
        handshake += UInt32(0).bigEndianBytes
        handshake += serverInit(width: 100, height: 50, name: "")
        let source = MemoryByteSource(handshake, holdsOpen: true)
        let client = VNCClient(configuration: VNCConfiguration(host: "x", password: ""), callbacks: VNCClientCallbacks(),
                               source: source, sink: sink, close: { await source.close() })
        await #expect(throws: RFBError.self) { try await client.sendKey(keysym: 0x61, down: true) }
        let run = Task { try await client.run() }
        for _ in 0..<400 where !client.isReady { try await Task.sleep(for: .milliseconds(5)) }
        #expect(client.isReady)
        _ = await sink.drain()
        try await client.sendKey(keysym: 0x61, down: true)
        try await client.sendPointer(buttonMask: 1, x: 500, y: -4)
        try await client.sendCutText("ok€")
        await #expect(throws: RFBError.self) { try await client.requestDesktopSize(width: 10, height: 10) }
        let written = await sink.drain()
        var expected: [UInt8] = [4, 1, 0, 0, 0, 0, 0, 0x61]
        expected += [5, 1, 0, 99, 0, 0]
        expected += [6, 0, 0, 0, 0, 0, 0, 2, 0x6F, 0x6B]
        #expect(written == expected)
        client.cancel()
        await #expect(throws: RFBError.self) { try await run.value }
        #expect(client.isReady == false)
    }
}

@Suite("Multi-display layout")
struct ScreenListTests {
    /// A host with two displays publishes one framebuffer covering both, plus a screen list saying
    /// where each display sits inside it.
    @Test func extendedDesktopSizePublishesEveryScreen() async throws {
        var server: [UInt8] = Array("RFB 003.008\n".utf8)
        server += [1, 1]
        server += UInt32(0).bigEndianBytes
        server += serverInit(width: 3000, height: 1600, name: "Two Displays")
        server += [0, 0, 0, 1]
        server += rectHeader(0, 0, 3000, 1600, -308)
        server += [2, 0, 0, 0]
        // Main display at the origin, then a smaller one to its right.
        server += UInt32(1).bigEndianBytes + UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes
        server += UInt16(2000).bigEndianBytes + UInt16(1200).bigEndianBytes + UInt32(0).bigEndianBytes
        server += UInt32(2).bigEndianBytes + UInt16(2000).bigEndianBytes + UInt16(0).bigEndianBytes
        server += UInt16(1000).bigEndianBytes + UInt16(600).bigEndianBytes + UInt32(0).bigEndianBytes
        let collected = Collected()
        let client = VNCClient(configuration: VNCConfiguration(host: "x", password: ""), callbacks: collected.callbacks,
                               source: MemoryByteSource(server), sink: MemoryByteSink())
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }
        #expect(collected.screens.count == 1)
        let screens = try #require(collected.screens.first)
        #expect(screens == [VNCScreen(id: 1, x: 0, y: 0, width: 2000, height: 1200, flags: 0),
                            VNCScreen(id: 2, x: 2000, y: 0, width: 1000, height: 600, flags: 0)])
        #expect(collected.resizeSupported == 1)
    }

    /// A screen reaching outside the framebuffer cannot be shown and is dropped rather than trusted.
    @Test func screensOutsideTheFramebufferAreDiscarded() async throws {
        var server: [UInt8] = Array("RFB 003.008\n".utf8)
        server += [1, 1]
        server += UInt32(0).bigEndianBytes
        server += serverInit(width: 800, height: 600, name: "")
        server += [0, 0, 0, 1]
        server += rectHeader(0, 0, 800, 600, -308)
        server += [2, 0, 0, 0]
        server += UInt32(1).bigEndianBytes + UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes
        server += UInt16(800).bigEndianBytes + UInt16(600).bigEndianBytes + UInt32(0).bigEndianBytes
        server += UInt32(2).bigEndianBytes + UInt16(700).bigEndianBytes + UInt16(0).bigEndianBytes
        server += UInt16(800).bigEndianBytes + UInt16(600).bigEndianBytes + UInt32(0).bigEndianBytes
        let collected = Collected()
        let client = VNCClient(configuration: VNCConfiguration(host: "x", password: ""), callbacks: collected.callbacks,
                               source: MemoryByteSource(server), sink: MemoryByteSink())
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }
        #expect(collected.screens.first?.map(\.id) == [1])
    }
}
