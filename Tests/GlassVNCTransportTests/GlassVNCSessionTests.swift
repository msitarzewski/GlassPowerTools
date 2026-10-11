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
        // The link's statistics arrive once a second while connected (W30); the ending is a state.
        for await event in session.events {
            if case .linkStatistics = event { continue }
            terminal = event; break
        }
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

/// W30: the session carries its windows' displays and its quality into the client, and the
/// client's statistics out to the app.
@Suite("What the link carries")
struct VNCStreamSettingsTests {
    @Test func qualityAndRegionsSetBeforeConnectingShapeTheOpeningMessages() async throws {
        let source = MemoryByteSource(handshake(width: 3000, height: 1600), holdsOpen: true)
        let sink = MemoryByteSink()
        let session = GlassVNCSession { configuration, callbacks in
            VNCClient(configuration: configuration, callbacks: callbacks, source: source, sink: sink, close: { await source.close() })
        }
        // Through the protocol, as the desktop's session model calls it (rule 53).
        let transport: any GlassDesktopTransport = session
        await transport.setStreamQuality(.dataSaver)
        await transport.setVisibleRegions([GlassRemoteRegion(x: 2000, y: 0, width: 1000, height: 600)])
        try await session.connect(GlassVNCConfiguration(host: "fixture", password: "pw"))
        for await event in session.events where event == .state(.connected) { break }
        let written = await sink.written
        // After the version, the security type and ClientInit: SetPixelFormat at 16 bits.
        #expect(Array(written[14..<34]) == [0, 0, 0, 0, 16, 16, 0, 1, 0, 31, 0, 63, 0, 31, 11, 5, 0, 0, 0, 0])
        // And the first request is for the one display on screen, in full.
        let request: [UInt8] = [3, 0] + UInt16(2000).bigEndianBytes + UInt16(0).bigEndianBytes
            + UInt16(1000).bigEndianBytes + UInt16(600).bigEndianBytes
        let found = (0...(written.count - request.count)).contains { Array(written[$0..<($0 + request.count)]) == request }
        #expect(found)
        await session.disconnect()
    }

    @Test func statisticsAndRegionsTranslate() {
        let statistics = VNCLinkStatistics(bytesPerSecond: 125_000, updatesPerSecond: 12, profile: .dataSaver, quality: .automatic,
                                           encoding: .zrle, measuredKilobitsPerSecond: 2_000, regionLimited: true, paused: false,
                                           totalBytes: 1)
        let translated = GlassVNCSession.statistics(statistics)
        #expect(translated == GlassDesktopLinkStatistics(bytesPerSecond: 125_000, updatesPerSecond: 12, quality: .automatic,
                                                         level: .dataSaver, colourDepth: 16, encoding: "ZRLE",
                                                         measuredKilobitsPerSecond: 2_000, regionLimited: true, paused: false))
        #expect(GlassVNCSession.rectangles(nil) == nil)
        #expect(GlassVNCSession.rectangles([]) == [])
        #expect(GlassVNCSession.rectangles([GlassRemoteRegion(x: 10, y: 20, width: 30, height: 40),
                                            GlassRemoteRegion(x: -1, y: 0, width: 5, height: 5)])
                == [RFBRectangle(x: 10, y: 20, width: 30, height: 40)], "a region that is not one is dropped")
        for quality in GlassDesktopStreamQuality.allCases {
            #expect(GlassVNCSession.level(GlassVNCSession.quality(quality)) == quality)
        }
        // A Mac's confirmed scale reaches the readout; other servers have none.
        var scaled = statistics
        scaled.serverScale = 0.75
        #expect(GlassVNCSession.statistics(scaled).serverScale == 0.75)
        #expect(translated.serverScale == nil)
        #expect(GlassVNCSession.remoteScreens([VNCScreen(id: 4, x: 0, y: 0, width: 3200, height: 1800, flags: 1, isMain: true),
                                               VNCScreen(id: 1, x: 3200, y: 0, width: 1280, height: 800, flags: 0, isMain: false)])
                == [GlassRemoteScreen(id: 4, x: 0, y: 0, width: 3200, height: 1800, isPrimary: true),
                    GlassRemoteScreen(id: 1, x: 3200, y: 0, width: 1280, height: 800, isPrimary: false)])
    }
}

/// A Mac's greeting (RFB 003.889, no authentication) for a framebuffer of this size.
private func macGreeting(width: UInt16, height: UInt16) -> [UInt8] {
    var bytes: [UInt8] = Array("RFB 003.889\n".utf8)
    bytes += [1, 1] + UInt32(0).bigEndianBytes
    bytes += width.bigEndianBytes + height.bigEndianBytes + RFBPixelFormat.client.wireBytes + UInt32(0).bigEndianBytes
    return bytes
}

/// A framebuffer update holding one display layout in the form of remotex's notes
/// (https://github.com/andrewtheguy/remotex/blob/main/docs/apple-vnc-889.md, "The display layout"):
/// one main display covering the framebuffer, at this scale.
private func macLayoutUpdate(width: UInt16, height: UInt16, scale: Double = 1) -> [UInt8] {
    func f64(_ value: Double) -> [UInt8] { withUnsafeBytes(of: value.bitPattern.bigEndian, Array.init) }
    let edges = UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes + height.bigEndianBytes + width.bigEndianBytes
    var payload = UInt16(5).bigEndianBytes + width.bigEndianBytes + height.bigEndianBytes + width.bigEndianBytes + height.bigEndianBytes
    payload += UInt32.max.bigEndianBytes + UInt32(4).bigEndianBytes + UInt16(1).bigEndianBytes
    payload += f64(1) + f64(scale) + UInt32(1).bigEndianBytes + edges + edges + UInt32(1).bigEndianBytes
    payload += RFBPixelFormat.client.wireBytes
    return [0, 0, 0, 1] + [UInt8](repeating: 0, count: 8) + RFBEncoding.appleDisplayLayout.rawValue.bigEndianBytes
        + UInt16(payload.count).bigEndianBytes + payload
}

/// An update with a rectangle outside a 2 × 2 framebuffer: a protocol violation.
private let rectangleOutside: [UInt8] = [0, 0, 0, 1] + UInt16(1).bigEndianBytes + UInt16(0).bigEndianBytes
    + UInt16(2).bigEndianBytes + UInt16(1).bigEndianBytes + Int32(0).bigEndianBytes

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [VNCConfiguration] = []
    var configurations: [VNCConfiguration] { lock.withLock { list } }
    func note(_ value: VNCConfiguration) { lock.withLock { list.append(value) } }
}

/// The failure a session ended with; nil when it ended normally.
private func ending(_ session: GlassVNCSession) async -> String? {
    for await event in session.events {
        if case .state(.failed(let message)) = event { return message }
        if event == .state(.disconnected) { return nil }
    }
    return nil
}

/// W30, W36: a Mac's displays and scale are read from forms known only from others' measurements.
/// If a Mac breaks the protocol once it has sent its displays, or ends the session while a scale is
/// unanswered, the next connection does not ask it again, so Reconnect works.
@Suite("Apple displays and scaling fallback")
struct AppleLayoutFallbackTests {
    private func session(_ mac: [UInt8], asked: Asked, sink: MemoryByteSink = MemoryByteSink()) -> GlassVNCSession {
        GlassVNCSession { configuration, callbacks in
            asked.note(configuration)
            return VNCClient(configuration: configuration, callbacks: callbacks, source: MemoryByteSource(mac), sink: sink)
        }
    }

    @Test func aMacThatBreaksTheProtocolAfterSendingItsDisplaysIsNotAskedForThemAgain() async throws {
        let asked = Asked()
        let host = "mac-\(UUID().uuidString.prefix(8)).example"
        let first = session(macGreeting(width: 2, height: 2) + macLayoutUpdate(width: 2, height: 2) + rectangleOutside, asked: asked)
        try await first.connect(GlassVNCConfiguration(host: host, password: "pw"))
        let failure = await ending(first)
        #expect(failure?.hasSuffix("Reconnect connects without asking this Mac where its displays are.") == true)

        let second = session(macGreeting(width: 2, height: 2), asked: asked)
        try await second.connect(GlassVNCConfiguration(host: host, password: "pw"))
        for await event in second.events where event == .state(.connected) { break }
        await second.disconnect()
        #expect(asked.configurations.map(\.requestsAppleDisplayLayout) == [true, false])
    }

    @Test func aViolationAfterAPictureWasReadInStepDoesNotStopAskingForThem() async throws {
        // 2026-10-11: a picture error 0.9 s after a layout cost a headset its two displays.
        let asked = Asked()
        let host = "mac-\(UUID().uuidString.prefix(8)).example"
        let pixel: [UInt8] = [0, 0, 0, 1] + UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes + UInt16(1).bigEndianBytes
            + UInt16(1).bigEndianBytes + Int32(0).bigEndianBytes + [1, 2, 3, 0]
        let first = session(macGreeting(width: 2, height: 2) + macLayoutUpdate(width: 2, height: 2) + pixel + rectangleOutside,
                            asked: asked)
        try await first.connect(GlassVNCConfiguration(host: host, password: "pw"))
        let failure = await ending(first)
        #expect(failure != nil)
        #expect(failure?.contains("Reconnect connects without") == false, "the layout was read right: a picture followed it in step")

        let second = session(macGreeting(width: 2, height: 2), asked: asked)
        try await second.connect(GlassVNCConfiguration(host: host, password: "pw"))
        for await event in second.events where event == .state(.connected) { break }
        await second.disconnect()
        #expect(asked.configurations.map(\.requestsAppleDisplayLayout) == [true, true])
    }

    /// 2026-10-11: a Mac is answered in its own revision, encrypted; one that fails before its record
    /// layer is up is answered in 3.8 on Reconnect.
    @Test func aMacThatFailsBeforeItsRecordLayerIsAnsweredInTheStandardProtocolNext() async throws {
        let asked = Asked()
        let host = "mac-\(UUID().uuidString.prefix(8)).example"
        // Type 30 with a toy group, accepted; the enhanced ServerInit; then the Mac goes away before
        // sending its encryption key.
        var mac: [UInt8] = Array("RFB 003.889\n".utf8) + [1, 30]
        mac += UInt16(2).bigEndianBytes + UInt16(16).bigEndianBytes
        mac += [UInt8](repeating: 0xff, count: 15) + [0xfb] + [UInt8](repeating: 0x07, count: 16)
        mac += UInt32(0).bigEndianBytes
        mac += UInt16(2).bigEndianBytes + UInt16(2).bigEndianBytes + RFBPixelFormat.client.wireBytes
        let name: [UInt8] = [0, 0] + UInt32(0x12).bigEndianBytes + [UInt8](repeating: 0xff, count: 16)
        mac += UInt32(name.count).bigEndianBytes + name
        let first = session(mac, asked: asked)
        try await first.connect(GlassVNCConfiguration(host: host, username: "ann", password: "pw"))
        let failure = await ending(first)
        #expect(failure?.hasSuffix("Reconnect connects in the standard protocol, which this Mac does not encrypt.") == true)

        let second = session(macGreeting(width: 2, height: 2), asked: asked)
        try await second.connect(GlassVNCConfiguration(host: host, username: "ann", password: "pw"))
        _ = await ending(second)
        #expect(asked.configurations.map(\.appleProtocol) == [true, false])
    }

    @Test func aViolationBeforeAnyDisplayMetadataDoesNotStopAskingForThem() async throws {
        let asked = Asked()
        let host = "mac-\(UUID().uuidString.prefix(8)).example"
        let first = session(macGreeting(width: 2, height: 2) + rectangleOutside, asked: asked)
        try await first.connect(GlassVNCConfiguration(host: host, password: "pw"))
        let failure = await ending(first)
        #expect(failure != nil)
        #expect(failure?.contains("Reconnect connects without") == false, "nothing the Mac said about its displays was misread")

        let second = session(macGreeting(width: 2, height: 2), asked: asked)
        try await second.connect(GlassVNCConfiguration(host: host, password: "pw"))
        for await event in second.events where event == .state(.connected) { break }
        await second.disconnect()
        #expect(asked.configurations.map(\.requestsAppleDisplayLayout) == [true, true])
    }

    @Test func aMacThatEndsTheSessionWhileAScaleIsUnansweredIsNotAskedToScaleAgain() async throws {
        let asked = Asked()
        let host = "mac-\(UUID().uuidString.prefix(8)).example"
        let sink = MemoryByteSink()
        let first = session(macGreeting(width: 64, height: 64) + macLayoutUpdate(width: 64, height: 64), asked: asked, sink: sink)
        await first.setStreamQuality(.dataSaver)
        try await first.connect(GlassVNCConfiguration(host: host, password: "pw"))
        let failure = await ending(first)
        #expect(failure?.hasSuffix("Reconnect connects without asking this Mac to send a smaller picture.") == true)
        let scaling: [UInt8] = [8, 0, 0x3F, 0xE8, 0, 0, 0, 0, 0, 0]
        let written = await sink.written
        #expect((0...(written.count - scaling.count)).contains { Array(written[$0..<($0 + scaling.count)]) == scaling },
                "Data Saver asked the Mac for three quarters of its size")

        let second = session(macGreeting(width: 64, height: 64), asked: asked)
        try await second.connect(GlassVNCConfiguration(host: host, password: "pw"))
        for await event in second.events where event == .state(.connected) { break }
        await second.disconnect()
        #expect(asked.configurations.map(\.allowsServerScaling) == [true, false])
        #expect(asked.configurations.map(\.requestsAppleDisplayLayout) == [true, true], "its displays are still asked for")
    }
}
