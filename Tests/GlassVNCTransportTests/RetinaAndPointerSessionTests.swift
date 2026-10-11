import Foundation
import Testing
import GlassRDPTransport
@testable import VNCKit
@testable import GlassVNCTransport

// W38: what the session carries for a Mac's Retina displays, a display window's own connection and
// the Mac's pointer.

private func greeting(width: UInt16, height: UInt16) -> [UInt8] {
    var bytes: [UInt8] = Array("RFB 003.889\n".utf8)
    bytes += [1, 1] + UInt32(0).bigEndianBytes
    bytes += width.bigEndianBytes + height.bigEndianBytes + RFBPixelFormat.client.wireBytes + UInt32(0).bigEndianBytes
    return bytes
}

private func header(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ encoding: Int32) -> [UInt8] {
    UInt16(x).bigEndianBytes + UInt16(y).bigEndianBytes + UInt16(width).bigEndianBytes + UInt16(height).bigEndianBytes
        + encoding.bigEndianBytes
}

/// One 2x display covering the framebuffer: a single Retina Mac.
private func retinaLayout(width: UInt16, height: UInt16, scale: Double = 1) -> [UInt8] {
    let edges = UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes + height.bigEndianBytes + width.bigEndianBytes
    let points = UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes + (height / 2).bigEndianBytes + (width / 2).bigEndianBytes
    var payload = UInt16(5).bigEndianBytes + (width / 2).bigEndianBytes + (height / 2).bigEndianBytes
    payload += width.bigEndianBytes + height.bigEndianBytes
    payload += UInt32.max.bigEndianBytes + UInt32(4).bigEndianBytes + UInt16(1).bigEndianBytes
    payload += Double(2).bitPattern.bigEndianBytes + scale.bitPattern.bigEndianBytes + UInt32(1).bigEndianBytes
    payload += points + edges + UInt32(1).bigEndianBytes + RFBPixelFormat.client.wireBytes
    return [0, 0, 0, 1] + header(0, 0, 0, 0, 1105) + UInt16(payload.count).bigEndianBytes + payload
}

/// The factors of the SetServerScaling messages a client wrote, read message by message after the
/// version, security type and ClientInit (14 bytes with no authentication).
private func scales(_ written: [UInt8]) -> [Double] {
    let bytes = Array(written.dropFirst(14))
    var found: [Double] = []
    var index = 0
    while index < bytes.count {
        let length: Int
        switch bytes[index] {
        case 0: length = 20
        case 2: guard index + 4 <= bytes.count else { return found }
            length = 4 + (Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])) * 4
        case 3, 8: length = 10
        case 4, 13: length = 8
        case 5: length = 6
        default: return found
        }
        guard index + length <= bytes.count else { return found }
        if bytes[index] == 8 {
            found.append(Double(bitPattern: bytes[(index + 2)..<(index + 10)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }))
        }
        index += length
    }
    return found
}

private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [VNCConfiguration] = []
    var configurations: [VNCConfiguration] { lock.withLock { list } }
    func note(_ value: VNCConfiguration) { lock.withLock { list.append(value) } }
}

@Suite("Retina displays and a display's own connection, in the session")
struct RetinaSessionTests {
    @Test("a single Retina Mac is asked for 1x, and Native 2x asks for its own pixels again")
    func retinaAtOneX() async throws {
        let source = MemoryByteSource(greeting(width: 3024, height: 1964), holdsOpen: true)
        let sink = MemoryByteSink()
        let session = GlassVNCSession { configuration, callbacks in
            VNCClient(configuration: configuration, callbacks: callbacks, source: source, sink: sink, close: { await source.close() })
        }
        // Through the protocol, as the desktop's session model calls it (rule 53).
        let transport: any GlassDesktopTransport = session
        await transport.setStreamQuality(.best)
        try await session.connect(GlassVNCConfiguration(host: "mac.example", password: "pw"))
        for await event in session.events where event == .state(.connected) { break }
        await source.append(retinaLayout(width: 3024, height: 1964))
        try await waitUntil { scales(await sink.written) == [0.5] }
        await source.append(retinaLayout(width: 1512, height: 982, scale: 0.5))
        try await Task.sleep(for: .milliseconds(50))
        await transport.setRetinaDisplays(.native)
        try await waitUntil { scales(await sink.written) == [0.5, 1] }
        await session.disconnect()
    }

    @Test("a display window's connection asks its client for that display alone")
    func displayConfiguration() async throws {
        let asked = Asked()
        let session = GlassVNCSession { configuration, callbacks in
            asked.note(configuration)
            return VNCClient(configuration: configuration, callbacks: callbacks,
                             source: MemoryByteSource(greeting(width: 4, height: 4)), sink: MemoryByteSink())
        }
        try await session.connect(GlassVNCConfiguration(host: "mac.example", username: "ann", password: "pw",
                                                        clipboardEnabled: false, display: 4))
        for await event in session.events {
            if case .state(.failed) = event { break }
            if event == .state(.disconnected) { break }
        }
        #expect(asked.configurations.map(\.display) == [4])
        #expect(asked.configurations.map(\.username) == ["ann"] && asked.configurations.map(\.clipboardEnabled) == [false])
    }

    @Test("a display's density reaches the app")
    func densityCarried() {
        #expect(GlassVNCSession.remoteScreens([VNCScreen(id: 4, x: 0, y: 0, width: 3200, height: 1800, flags: 1, isMain: true, density: 2)])
                == [GlassRemoteScreen(id: 4, x: 0, y: 0, width: 3200, height: 1800, isPrimary: true, density: 2)])
    }
}

@Suite("A Mac's pointer, in the session")
struct ApplePointerSessionTests {
    /// Every pointer event, until the session ends.
    private func cursorEvents(_ session: GlassVNCSession) async -> [GlassRDPCursor] {
        var found: [GlassRDPCursor] = []
        for await event in session.events {
            if case .cursor(let value) = event { found.append(value) }
            if case .state(.failed) = event { break }
            if event == .state(.disconnected) { break }
        }
        return found
    }

    @Test("CursorPos is a position; a pointer the Mac hid comes back when it moves")
    func positionAndReshow() async throws {
        var stream = greeting(width: 8, height: 8)
        stream += [0, 0, 0, 3]
        stream += header(0, 0, 1, 1, -239) + [9, 9, 9, 0] + [0x80]
        stream += header(0, 0, 0, 0, -239)
        stream += header(5, 6, 0, 0, 1100)
        let bytes = stream
        let session = GlassVNCSession { configuration, callbacks in
            VNCClient(configuration: configuration, callbacks: callbacks, source: MemoryByteSource(bytes), sink: MemoryByteSink())
        }
        try await session.connect(GlassVNCConfiguration(host: "mac.example", password: "pw"))
        let events = await cursorEvents(session)
        #expect(events.count == 4)
        guard events.count == 4 else { return }
        guard case .image(let shape) = events[0] else { Issue.record("a shape first"); return }
        #expect(shape.isPointSized, "a Mac's pointer is measured in its points")
        #expect(events[1] == .hidden)
        #expect(events[2] == .image(shape), "moved: shown again, as a Mac shows its own")
        #expect(events[3] == .position(x: 5, y: 6))
    }

    @Test("a pointer hidden by a Mac comes back when this app moves it")
    func reshowOnLocalMove() async throws {
        let source = MemoryByteSource(greeting(width: 8, height: 8), holdsOpen: true)
        let session = GlassVNCSession { configuration, callbacks in
            VNCClient(configuration: configuration, callbacks: callbacks, source: source, sink: MemoryByteSink(),
                      close: { await source.close() })
        }
        try await session.connect(GlassVNCConfiguration(host: "mac.example", password: "pw"))
        var iterator = session.events.makeAsyncIterator()
        while let event = await iterator.next(), event != .state(.connected) {}
        await source.append([0, 0, 0, 2] + header(0, 0, 1, 1, -239) + [9, 9, 9, 0] + [0x80] + header(0, 0, 0, 0, -239))
        var seen: [GlassRDPCursor] = []
        while seen.count < 2, let event = await iterator.next() { if case .cursor(let value) = event { seen.append(value) } }
        #expect(seen.last == .hidden)
        try await session.movePointer(x: 3, y: 3)
        while seen.count < 3, let event = await iterator.next() { if case .cursor(let value) = event { seen.append(value) } }
        if case .image = seen.last {} else { Issue.record("shown again: \(String(describing: seen.last))") }
        await session.disconnect()
    }

    @Test("a shape with soft edges keeps them; the standard Cursor's opaque pixels stay opaque")
    func alphaKept() throws {
        let bgra = Data([1, 2, 3, 0x40, 4, 5, 6, 0x00]), mask = Data([1, 1])
        let converted = try #require(GlassVNCSession.cursorImage(VNCCursorImage(width: 2, height: 1, hotSpotX: 0, hotSpotY: 0,
                                                                                 bgra: bgra, mask: mask, isPointSized: true)))
        #expect(converted.xorMask[3] == 0x40 && converted.xorMask[7] == 0xFF)
        #expect(converted.isPointSized)
    }

    @Test("a Mac that breaks the protocol right after its pointer's messages is not asked for them again")
    func cursorFallback() async throws {
        let asked = Asked()
        let host = "mac-\(UUID().uuidString.prefix(8)).example"
        let outside: [UInt8] = [0, 0, 0, 1] + header(1, 0, 2, 1, 0)
        let broken = greeting(width: 2, height: 2) + [0, 0, 0, 1] + header(1, 1, 0, 0, 1100) + outside
        let first = GlassVNCSession { configuration, callbacks in
            asked.note(configuration)
            return VNCClient(configuration: configuration, callbacks: callbacks, source: MemoryByteSource(broken), sink: MemoryByteSink())
        }
        try await first.connect(GlassVNCConfiguration(host: host, password: "pw"))
        var failure: String?
        for await event in first.events {
            if case .state(.failed(let message)) = event { failure = message; break }
            if event == .state(.disconnected) { break }
        }
        #expect(failure?.hasSuffix("Reconnect connects without asking this Mac where its pointer is.") == true)
        let second = GlassVNCSession { configuration, callbacks in
            asked.note(configuration)
            return VNCClient(configuration: configuration, callbacks: callbacks,
                             source: MemoryByteSource(greeting(width: 2, height: 2)), sink: MemoryByteSink())
        }
        try await second.connect(GlassVNCConfiguration(host: host, password: "pw"))
        for await event in second.events where event == .state(.connected) { break }
        await second.disconnect()
        #expect(asked.configurations.map(\.requestsAppleCursor) == [true, false])
        #expect(asked.configurations.map(\.requestsAppleDisplayLayout) == [true, true], "its displays are still asked for")
    }
}

/// Polls until `condition` holds, for up to two seconds.
private func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw RFBError.cancelled }
        try await Task.sleep(for: .milliseconds(10))
    }
}
