import Foundation
import Testing
import GlassRDPTransport
import VNCKit
@testable import GlassVNCTransport

private func handshake(width: UInt16, height: UInt16) -> [UInt8] {
    var bytes: [UInt8] = Array("RFB 003.008\n".utf8)
    bytes += [1, 1]
    bytes += UInt32(0).bigEndianBytes
    bytes += width.bigEndianBytes
    bytes += height.bigEndianBytes
    bytes += RFBPixelFormat.client.wireBytes
    bytes += UInt32(0).bigEndianBytes
    return bytes
}

@Suite("GlassVNCSession")
struct GlassVNCSessionTests {
    @Test func cursorConversionMatchesRDPLayout() throws {
        var bgra = Data(count: 3 * 2 * 4), mask = Data(count: 6)
        for pixel in 0..<6 { bgra[pixel * 4] = UInt8(pixel); bgra[pixel * 4 + 1] = 10; bgra[pixel * 4 + 2] = 20 }
        mask[0] = 1; mask[2] = 1; mask[4] = 1
        let converted = try #require(GlassVNCSession.cursorImage(VNCCursorImage(width: 3, height: 2, hotSpotX: 5, hotSpotY: 0, bgra: bgra, mask: mask)))
        #expect(converted.hotSpotX == 2 && converted.hotSpotY == 0 && converted.xorBitsPerPixel == 32)
        #expect(converted.xorMask.count == 24 && converted.andMask.count == 4)
        // Bottom-up: row 0 of the XOR mask is the source's last row (pixels 3, 4, 5).
        #expect(converted.xorMask[0] == 3 && converted.xorMask[3] == 0 && converted.xorMask[4] == 4 && converted.xorMask[7] == 255)
        #expect(converted.xorMask[12] == 0 && converted.xorMask[15] == 255)
        // AND mask: 1 = transparent. Source row 1 (bottom-up row 0): pixels 3 (transparent), 4 (opaque), 5 (transparent) → 1010 0000.
        #expect(converted.andMask[0] == 0b1010_0000 && converted.andMask[1] == 0)
        #expect(converted.andMask[2] == 0b0100_0000)
        #expect(GlassVNCSession.cursorImage(VNCCursorImage(width: 0, height: 0, hotSpotX: 0, hotSpotY: 0, bgra: Data(), mask: Data())) == nil)
    }

    @Test func inputTranslatesScancodesAndScrollNotches() async throws {
        let source = MemoryByteSource(handshake(width: 640, height: 480), holdsOpen: true)
        let sink = MemoryByteSink()
        let session = GlassVNCSession { configuration, callbacks in
            VNCClient(configuration: configuration, callbacks: callbacks, source: source, sink: sink, close: { await source.close() })
        }
        try await session.connect(GlassVNCConfiguration(host: "fixture", password: "pw"))
        var events: [GlassRDPEvent] = []
        for await event in session.events {
            events.append(event)
            if event == .state(.connected) { break }
        }
        #expect(events == [.state(.connecting), .state(.connected)])
        _ = await sink.drain()
        try await session.keyboard(scancode: 0x1E, extended: false, isDown: true, isRepeat: false)
        try await session.keyboard(scancode: 0x1D, extended: true, isDown: true, isRepeat: false)
        await #expect(throws: GlassRDPError.self) { try await session.keyboard(scancode: 0x7F, extended: false, isDown: true, isRepeat: false) }
        try await session.pointerButton(button: .left, isDown: true, x: 10, y: 20)
        try await session.scroll(vertical: 100, horizontal: 0, x: 10, y: 20)
        try await session.scroll(vertical: 20, horizontal: -240, x: 10, y: 20)
        try await session.releaseInputs()
        try await session.sendText("é")
        let written = await sink.drain()
        var expected: [UInt8] = [4, 1, 0, 0, 0, 0, 0, 0x61]
        expected += [4, 1, 0, 0, 0, 0, 0xFF, 0xE4]
        expected += [5, 1, 0, 10, 0, 20]
        // First scroll: 100 units, below one notch. Second: 120 total → one notch up (button 4), horizontal two notches left (button 6).
        expected += [5, 9, 0, 10, 0, 20]
        expected += [5, 1, 0, 10, 0, 20]
        expected += [5, 33, 0, 10, 0, 20]
        expected += [5, 1, 0, 10, 0, 20]
        expected += [5, 33, 0, 10, 0, 20]
        expected += [5, 1, 0, 10, 0, 20]
        // Release: pressed keys up (set order is not defined), then buttons cleared.
        let releaseKeys: Set<[UInt8]> = [[4, 0, 0, 0, 0, 0, 0, 0x61], [4, 0, 0, 0, 0, 0, 0xFF, 0xE4]]
        let head = Array(written[0..<expected.count])
        #expect(head == expected)
        let offset = expected.count
        let releaseA = Array(written[offset..<(offset + 8)])
        let releaseB = Array(written[(offset + 8)..<(offset + 16)])
        #expect(releaseKeys == Set([releaseA, releaseB]))
        let cleared: [UInt8] = [5, 0, 0, 10, 0, 20]
        #expect(Array(written[(offset + 16)..<(offset + 22)]) == cleared)
        let text: [UInt8] = [4, 1, 0, 0, 0, 0, 0, 0xE9, 4, 0, 0, 0, 0, 0, 0, 0xE9]
        #expect(Array(written[(offset + 22)...]) == text)
        await #expect(throws: GlassRDPError.self) { try await session.resize(width: 800, height: 600, desktopScale: 100) }
        await session.disconnect()
        var terminal: GlassRDPEvent?
        for await event in session.events { terminal = event; break }
        #expect(terminal == .state(.disconnected))
    }

    @Test func framesAndFailuresArePublished() async throws {
        var bytes = handshake(width: 2, height: 1)
        bytes += [0, 0, 0, 1]
        bytes += [0, 0, 0, 0, 0, 2, 0, 1]
        bytes += Int32(0).bigEndianBytes
        bytes += [1, 2, 3, 0, 4, 5, 6, 0]
        bytes += [77]
        let source = MemoryByteSource(bytes), sink = MemoryByteSink()
        let session = GlassVNCSession { configuration, callbacks in
            VNCClient(configuration: configuration, callbacks: callbacks, source: source, sink: sink)
        }
        try await session.connect(GlassVNCConfiguration(host: "fixture", password: "pw"))
        var frame: GlassRDPFrame?
        for await value in session.frames { frame = value; break }
        #expect(frame?.width == 2 && frame?.height == 1 && frame?.bytesPerRow == 8)
        #expect(frame?.pixels == Data([1, 2, 3, 255, 4, 5, 6, 255]))
        var last: GlassRDPEvent?
        for await event in session.events {
            last = event
            if case .state(.failed) = event { break }
            if event == .state(.disconnected) { break }
        }
        #expect(last == .state(.failed("The server sent an unknown message type 77.")))
        await #expect(throws: GlassRDPError.self) { try await session.connect(GlassVNCConfiguration(host: "", password: "pw")) }
    }
}

@Suite("Session ending")
struct VNCSessionEndingTests {
    /// Signing out of the remote session closes the transport. After a desktop has been shown that
    /// is a normal ending, so the app closes the window instead of showing a failure panel.
    @Test func closeAfterFramesEndsNormally() async throws {
        var stream = handshake(width: 2, height: 1)
        stream += [0, 0, 0, 1]
        stream += [0, 0, 0, 0, 0, 2, 0, 1]
        stream += Int32(0).bigEndianBytes
        stream += [1, 2, 3, 0, 4, 5, 6, 0]
        let bytes = stream
        let session = GlassVNCSession { configuration, callbacks in
            VNCClient(configuration: configuration, callbacks: callbacks,
                      source: MemoryByteSource(bytes), sink: MemoryByteSink())
        }
        try await session.connect(GlassVNCConfiguration(host: "fixture", password: "pw"))
        var states: [GlassRDPState] = []
        for await event in session.events {
            if case .state(let value) = event {
                states.append(value)
                if value == .disconnected { break }
                if case .failed = value { break }
            }
        }
        #expect(states == [.connecting, .connected, .disconnected])
    }

    /// A close before any desktop appeared is still a failure worth reporting.
    @Test func closeBeforeAnyFrameIsAFailure() async throws {
        let session = GlassVNCSession { configuration, callbacks in
            VNCClient(configuration: configuration, callbacks: callbacks,
                      source: MemoryByteSource(handshake(width: 2, height: 1)), sink: MemoryByteSink())
        }
        try await session.connect(GlassVNCConfiguration(host: "fixture", password: "pw"))
        var last: GlassRDPState?
        for await event in session.events {
            if case .state(let value) = event {
                last = value
                if case .failed = value { break }
                if value == .disconnected { break }
            }
        }
        #expect(last == .failed(RFBError.connectionClosed.localizedDescription))
    }
}
