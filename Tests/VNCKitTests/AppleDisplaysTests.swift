import Foundation
import Testing
@testable import VNCKit

// W36: a Mac's displays and its server-side scaling, from byte fixtures built to the form in
// remotex's notes (https://github.com/andrewtheguy/remotex/blob/main/docs/apple-vnc-889.md, "The
// display layout", "A display record, as sent", "Server-side scaling in Standard mode").

/// A display record as the notes give it: two f64s, an id, logical and backing edges (top, left,
/// bottom, right), flags and a pixel format.
struct MacDisplay {
    var id: UInt32
    var density: Double
    var scale: Double = 1
    /// Points: top, left, bottom, right.
    var logical: (Int, Int, Int, Int)
    /// Framebuffer pixels: top, left, bottom, right.
    var backing: (Int, Int, Int, Int)
    var flags: UInt32 = 0
}

enum MacLayout {
    static func payload(points: (Int, Int), framebuffer: (Int, Int), current: UInt32 = .max, state: UInt32 = 4,
                        displays: [MacDisplay], count: Int? = nil) -> [UInt8] {
        var bytes = UInt16(5).bigEndianBytes + UInt16(points.0).bigEndianBytes + UInt16(points.1).bigEndianBytes
        bytes += UInt16(framebuffer.0).bigEndianBytes + UInt16(framebuffer.1).bigEndianBytes
        bytes += current.bigEndianBytes + state.bigEndianBytes + UInt16(count ?? displays.count).bigEndianBytes
        for display in displays {
            bytes += display.density.bitPattern.bigEndianBytes + display.scale.bitPattern.bigEndianBytes
            bytes += display.id.bigEndianBytes + edges(display.logical) + edges(display.backing)
            bytes += display.flags.bigEndianBytes + RFBPixelFormat.client.wireBytes
        }
        return bytes
    }

    static func edges(_ value: (Int, Int, Int, Int)) -> [UInt8] {
        [value.0, value.1, value.2, value.3].flatMap { UInt16(bitPattern: Int16($0)).bigEndianBytes }
    }

    /// As it arrives: the `u16` counting the bytes after itself, then the payload.
    static func wire(_ payload: [UInt8]) -> [UInt8] { UInt16(payload.count).bigEndianBytes + payload }

    /// A framebuffer update holding only this layout.
    static func update(_ payload: [UInt8]) -> [UInt8] {
        [0, 0, 0, 1] + rectangleHeader(0, 0, 0, 0, .appleDisplayLayout) + wire(payload)
    }

    static func rectangleHeader(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ encoding: RFBEncoding) -> [UInt8] {
        UInt16(x).bigEndianBytes + UInt16(y).bigEndianBytes + UInt16(width).bigEndianBytes + UInt16(height).bigEndianBytes
            + encoding.rawValue.bigEndianBytes
    }

    /// The notes' measured Mac ("Picking a physical screen in Standard mode"): display 4, 3200 × 1800
    /// at 2x, beside display 1, 1280 × 800 at 1x; all displays together 4480 × 1800.
    static let mixed: [MacDisplay] = [
        MacDisplay(id: 4, density: 2, logical: (0, 0, 900, 1600), backing: (0, 0, 1800, 3200), flags: 1),
        MacDisplay(id: 1, density: 1, logical: (0, 1600, 800, 2880), backing: (0, 3200, 800, 4480)),
    ]
    static var mixedPayload: [UInt8] { payload(points: (2880, 900), framebuffer: (4480, 1800), displays: mixed) }

    /// The same Mac after SetServerScaling(0.5): every record states the factor, the framebuffer and
    /// the backing rectangles are half the size.
    static func halved(backingUnscaled: Bool = false) -> [UInt8] {
        let displays = [
            MacDisplay(id: 4, density: 2, scale: 0.5, logical: (0, 0, 900, 1600),
                       backing: backingUnscaled ? (0, 0, 1800, 3200) : (0, 0, 900, 1600), flags: 1),
            MacDisplay(id: 1, density: 1, scale: 0.5, logical: (0, 1600, 800, 2880),
                       backing: backingUnscaled ? (0, 3200, 800, 4480) : (0, 1600, 400, 2240)),
        ]
        return payload(points: (2880, 900), framebuffer: (2240, 900), displays: displays)
    }

    /// A Mac's greeting: version 003.889, no authentication, and a framebuffer of this size.
    static func greeting(width: Int, height: Int) -> [UInt8] {
        var bytes: [UInt8] = Array("RFB 003.889\n".utf8)
        bytes += [1, 1] + UInt32(0).bigEndianBytes
        bytes += UInt16(width).bigEndianBytes + UInt16(height).bigEndianBytes + RFBPixelFormat.client.wireBytes
        bytes += UInt32(0).bigEndianBytes
        return bytes
    }
}

/// The client messages in a write, by type: SetPixelFormat, SetEncodings, FramebufferUpdateRequest,
/// SetServerScaling, PointerEvent and SetDisplay.
func clientMessages(_ bytes: [UInt8]) -> [(type: UInt8, bytes: [UInt8])] {
    var found: [(type: UInt8, bytes: [UInt8])] = []
    var index = 0
    while index < bytes.count {
        let length: Int
        switch bytes[index] {
        case 0: length = 20
        case 2: length = 4 + (Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])) * 4
        case 3, 8: length = 10
        case 5: length = 6
        case 13: length = 8
        default: return found
        }
        guard index + length <= bytes.count else { return found }
        found.append((bytes[index], Array(bytes[index..<(index + length)])))
        index += length
    }
    return found
}

/// The factors in the SetServerScaling messages of a write.
func serverScales(_ bytes: [UInt8]) -> [Double] {
    clientMessages(bytes).filter { $0.type == 8 }.map { message in
        Double(bitPattern: message.bytes[2...].reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
    }
}

@Suite("Apple display layout")
struct AppleDisplayLayoutTests {
    @Test("the length counts the bytes after itself, 0x14 + displays × 0x38, and exactly that is read")
    func lengthCountsWhatFollows() async throws {
        let payload = MacLayout.mixedPayload
        #expect(payload.count == 0x14 + 2 * 0x38)
        let wire = MacLayout.wire(payload)
        #expect(Array(wire.prefix(2)) == [0x00, 0x84])
        let source = MemoryByteSource(wire + [0xEE])
        #expect(try await RFBAppleDisplayLayout.readPayload(from: source) == payload)
        #expect(await source.remaining == 1, "the layout and nothing after it")
    }

    @Test("the header and each record decode at the notes' offsets")
    func headerAndRecords() throws {
        let layout = try #require(RFBAppleDisplayLayout(payload: MacLayout.mixedPayload))
        #expect(layout.version == 5)
        #expect(layout.pointsWidth == 2880 && layout.pointsHeight == 900)
        #expect(layout.framebufferWidth == 4480 && layout.framebufferHeight == 1800)
        #expect(layout.currentDisplay == nil, "0xffffffff is all displays")
        #expect(layout.sessionState == 4)
        #expect(layout.records.map(\.id) == [4, 1])
        #expect(layout.records[0].density == 2 && layout.records[0].scale == 1)
        #expect(layout.records[0].isMain && !layout.records[1].isMain)
        #expect(layout.records[1].logical == .init(top: 0, left: 1600, bottom: 800, right: 2880))
        #expect(layout.records[1].backing == .init(top: 0, left: 3200, bottom: 800, right: 4480))
        #expect(layout.records[1].pixelFormat == RFBPixelFormat.client.wireBytes)
        #expect(layout.serverScale == 1)

        let selected = MacLayout.payload(points: (2880, 900), framebuffer: (3200, 1800), current: 4, displays: MacLayout.mixed)
        #expect(RFBAppleDisplayLayout(payload: selected)?.currentDisplay == 4)
    }

    @Test("with one display being sent, the framebuffer is that display's own pixels")
    func oneDisplaySelected() throws {
        // The notes' table: display 1 selected, a 1280 × 800 framebuffer; the records keep their
        // places among all the displays.
        let payload = MacLayout.payload(points: (2880, 900), framebuffer: (1280, 800), current: 1, displays: MacLayout.mixed)
        let layout = try #require(RFBAppleDisplayLayout(payload: payload))
        #expect(layout.screens(inFramebufferWidth: 1280, height: 800)
                == [VNCScreen(id: 1, x: 0, y: 0, width: 1280, height: 800, flags: 0, isMain: false, density: 1)])
    }

    @Test("two displays of mixed density: each display's own pixels, the main one marked")
    func mixedDensity() throws {
        let layout = try #require(RFBAppleDisplayLayout(payload: MacLayout.mixedPayload))
        #expect(layout.screens(inFramebufferWidth: 4480, height: 1800) == [
            VNCScreen(id: 4, x: 0, y: 0, width: 3200, height: 1800, flags: 1, isMain: true, density: 2),
            VNCScreen(id: 1, x: 3200, y: 0, width: 1280, height: 800, flags: 0, isMain: false, density: 1),
        ])
        #expect(layout.densities == [4: 2, 1: 1], "every display's density, by id")
    }

    @Test("a mirror set is offered once, by its first member")
    func mirrorSet() throws {
        let displays = [
            MacDisplay(id: 1, density: 2, logical: (0, 0, 900, 1440), backing: (0, 0, 1800, 2880), flags: 0b011),
            MacDisplay(id: 2, density: 2, logical: (0, 0, 900, 1440), backing: (0, 0, 1800, 2880), flags: 0b010),
            MacDisplay(id: 3, density: 1, logical: (0, 1440, 1080, 3360), backing: (0, 2880, 1080, 4800)),
        ]
        let layout = try #require(RFBAppleDisplayLayout(payload: MacLayout.payload(points: (3360, 1080), framebuffer: (4800, 1800),
                                                                                    displays: displays)))
        #expect(layout.records[0].isMirrored && layout.records[1].isMirrored && !layout.records[2].isMirrored)
        #expect(layout.screens(inFramebufferWidth: 4800, height: 1800).map(\.id) == [1, 3])
    }

    @Test("a density of 0 comes from the rectangles, and a record that does not hold up costs only itself")
    func oddRecords() throws {
        let displays = [
            MacDisplay(id: 1, density: 0, logical: (0, 0, 900, 1440), backing: (0, 0, 1800, 2880), flags: 1),
            MacDisplay(id: 2, density: 1, logical: (0, 1440, 900, 2880), backing: (0, 4320, 900, 2880)),
            MacDisplay(id: 3, density: 9, logical: (0, 2880, 900, 4320), backing: (0, 2880, 900, 4320)),
            MacDisplay(id: 5, density: 1, logical: (-900, 0, 0, 1440), backing: (0, 2880, 900, 4320)),
        ]
        let layout = try #require(RFBAppleDisplayLayout(payload: MacLayout.payload(points: (4320, 1800), framebuffer: (4320, 1800),
                                                                                    displays: displays)))
        #expect(layout.records[0].nativeDensity == 2)
        #expect(layout.records[3].logical.top == -900, "logical edges are signed: a display above the main one")
        #expect(layout.screens(inFramebufferWidth: 4320, height: 1800).map(\.id) == [1, 5],
                "a backing edge out of order and an impossible density drop those displays only")
    }

    @Test("a payload that is not a layout reads as none")
    func notALayout() {
        let payload = MacLayout.mixedPayload
        #expect(RFBAppleDisplayLayout(payload: Array(payload.prefix(0x13))) == nil, "shorter than the header")
        #expect(RFBAppleDisplayLayout(payload: Array(payload.dropLast())) == nil, "shorter than its records")
        #expect(RFBAppleDisplayLayout(payload: MacLayout.payload(points: (1, 1), framebuffer: (1, 1), displays: [], count: 0)) == nil)
        #expect(RFBAppleDisplayLayout(payload: MacLayout.payload(points: (1, 1), framebuffer: (1, 1), displays: MacLayout.mixed,
                                                                 count: 26)) == nil, "1–25 displays")
        #expect(RFBAppleDisplayLayout(payload: payload + [0, 0, 0, 0]) != nil, "bytes past the last record are allowed")
    }

    @Test("after SetServerScaling the layout states the factor, and the displays are the scaled framebuffer's pixels")
    func scaledLayout() throws {
        let expected = [VNCScreen(id: 4, x: 0, y: 0, width: 1600, height: 900, flags: 1, isMain: true, density: 2),
                        VNCScreen(id: 1, x: 1600, y: 0, width: 640, height: 400, flags: 0, isMain: false, density: 1)]
        let layout = try #require(RFBAppleDisplayLayout(payload: MacLayout.halved()))
        #expect(layout.serverScale == 0.5)
        #expect(layout.framebufferSize?.width == 2240 && layout.framebufferSize?.height == 900)
        #expect(layout.screens(inFramebufferWidth: 2240, height: 900) == expected)
        // Should a Mac state the backing rectangles unscaled, they would not fit; scaled, they do.
        let unscaled = try #require(RFBAppleDisplayLayout(payload: MacLayout.halved(backingUnscaled: true)))
        #expect(unscaled.screens(inFramebufferWidth: 2240, height: 900) == expected)
        // A factor outside (0, 1] reads as unscaled.
        var odd = MacLayout.mixed
        odd[0].scale = 1.5; odd[1].scale = 1.5
        #expect(RFBAppleDisplayLayout(payload: MacLayout.payload(points: (2880, 900), framebuffer: (4480, 1800), displays: odd))?
            .serverScale == 1)
    }

    @Test("SetServerScaling is ten bytes: type 8, a zero, the factor as a big-endian f64 in (0, 1]")
    func setServerScalingBytes() {
        #expect(RFBAppleDisplayLayout.setServerScalingMessage(0.5) == [8, 0, 0x3F, 0xE0, 0, 0, 0, 0, 0, 0])
        #expect(RFBAppleDisplayLayout.setServerScalingMessage(0.75) == [8, 0, 0x3F, 0xE8, 0, 0, 0, 0, 0, 0])
        #expect(RFBAppleDisplayLayout.setServerScalingMessage(1) == [8, 0, 0x3F, 0xF0, 0, 0, 0, 0, 0, 0])
        #expect(RFBAppleDisplayLayout.setServerScalingMessage(2) == RFBAppleDisplayLayout.setServerScalingMessage(1),
                "the Mac cannot enlarge")
        #expect(RFBAppleDisplayLayout.setServerScalingMessage(0) == RFBAppleDisplayLayout.setServerScalingMessage(1))
    }

    @Test("DisplayInfo is stepped over exactly: ten header bytes, the count at bytes 8–9, then 0x1c bytes a display")
    func displayInfo() async throws {
        var bytes = UInt16(4480).bigEndianBytes + UInt16(1800).bigEndianBytes + UInt32(1).bigEndianBytes + UInt16(2).bigEndianBytes
        bytes += [UInt8](repeating: 0xA1, count: 0x1c) + [UInt8](repeating: 0xB2, count: 0x1c)
        let source = MemoryByteSource(bytes + [0xEE])
        let info = try await RFBAppleDisplayInfo.read(from: source)
        #expect(info.width == 4480 && info.height == 1800 && info.flags == 1)
        #expect(info.records == [[UInt8](repeating: 0xA1, count: 0x1c), [UInt8](repeating: 0xB2, count: 0x1c)])
        #expect(await source.remaining == 1)
        let outOfStep = UInt16(1).bigEndianBytes + UInt16(1).bigEndianBytes + UInt32(0).bigEndianBytes + UInt16(65_535).bigEndianBytes
        await #expect(throws: RFBError.self) { _ = try await RFBAppleDisplayInfo.read(from: MemoryByteSource(outOfStep)) }
    }

    @Test("pointer positions reach a scaled Mac in its unscaled framebuffer's pixels")
    func pointerScaling() {
        let half = VNCClient.unscaled(x: 100, y: 50, scale: 0.5)
        #expect(half.x == 200 && half.y == 100)
        let threeQuarters = VNCClient.unscaled(x: 3, y: 3, scale: 0.75)
        #expect(threeQuarters.x == 4 && threeQuarters.y == 4)
        let unscaled = VNCClient.unscaled(x: 100, y: 50, scale: 1)
        #expect(unscaled.x == 100 && unscaled.y == 50)
    }
}

// MARK: - The planner

@Suite("A Mac's scale")
struct ServerScalingPlannerTests {
    private func mac(_ quality: VNCQuality, scaling: Bool = true, layout: Bool = true,
                     dialect: RFBServerDialect = .apple) -> RFBStreamPlanner {
        let planner = RFBStreamPlanner()
        planner.setQuality(quality)
        planner.start(width: 4480, height: 1800, dialect: dialect, appleDisplayLayout: layout, serverScaling: scaling)
        _ = planner.openingMessages()
        return planner
    }

    private func decide(_ planner: RFBStreamPlanner, at now: ContinuousClock.Instant = .now) -> [UInt8] {
        var out: [UInt8] = []
        _ = planner.decide(at: now) { out += $0 }
        return out
    }

    @Test("a Mac is asked to scale only once it has sent a layout, and once for each factor")
    func askedAfterTheFirstLayout() {
        // Data Saver and Lowest are both 16-bit on a Mac, so no colour change waits in between.
        let planner = mac(.lowest)
        #expect(serverScales(decide(planner)).isEmpty, "no layout yet: nothing could confirm a factor")
        #expect(planner.statistics(totalBytes: 0, at: .now).serverScale == nil)
        planner.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800)
        #expect(serverScales(decide(planner)) == [0.5])
        #expect(planner.awaitingServerScale)
        #expect(serverScales(decide(planner)).isEmpty, "one request at a time")
        planner.appleLayoutArrived(serverScale: 0.5, width: 2240, height: 900)
        #expect(!planner.awaitingServerScale && planner.serverScaleInForce == 0.5)
        #expect(serverScales(decide(planner)).isEmpty)
        #expect(planner.statistics(totalBytes: 0, at: .now).serverScale == 0.5)
        planner.setQuality(.dataSaver)
        #expect(serverScales(decide(planner)) == [0.75])
        planner.appleLayoutArrived(serverScale: 0.75, width: 3360, height: 1350)
        // A Mac that goes back to its own size — a user switch, say — is asked again.
        planner.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800)
        #expect(serverScales(decide(planner)) == [0.75])
    }

    @Test("a factor no layout confirms within ten seconds is given up, and asked for again only when another is wanted")
    func unconfirmed() {
        let planner = mac(.dataSaver)
        let start = ContinuousClock.now
        planner.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800)
        var out: [UInt8] = []
        let wake = planner.decide(at: start) { out += $0 }
        #expect(serverScales(out) == [0.75])
        #expect(wake.map { $0 <= start + .seconds(10) } == true, "it looks again when the answer is due")
        // A layout at the old factor — an answer to something else — does not confirm it.
        planner.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800)
        #expect(serverScales(decide(planner, at: start + .seconds(5))).isEmpty)
        #expect(planner.awaitingServerScale)
        #expect(serverScales(decide(planner, at: start + .seconds(10) + .milliseconds(1))).isEmpty)
        #expect(!planner.awaitingServerScale)
        #expect(serverScales(decide(planner, at: start + .seconds(20))).isEmpty, "not asked for again")
        #expect(planner.serverScaleInForce == 1)
        planner.setQuality(.lowest)
        #expect(serverScales(decide(planner, at: start + .seconds(21))) == [0.5])
    }

    @Test("a server that is not a Mac, and a Mac not to be asked, are never asked")
    func neverAsked() {
        for planner in [mac(.lowest, dialect: .standard), mac(.lowest, scaling: false), mac(.lowest, layout: false)] {
            planner.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800)
            #expect(serverScales(decide(planner)).isEmpty)
        }
        let standard = mac(.lowest, dialect: .standard)
        #expect(standard.statistics(totalBytes: 0, at: .now).serverScale == nil)
    }

    @Test("an override asks for its factor whatever the level, and nil goes back to the level's")
    func override() {
        let planner = mac(.best)
        planner.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800)
        #expect(serverScales(decide(planner)).isEmpty)
        planner.setServerScaleOverride(0.6)
        #expect(serverScales(decide(planner)) == [0.6])
        planner.appleLayoutArrived(serverScale: 0.6, width: 2688, height: 1080)
        planner.setServerScaleOverride(nil)
        #expect(serverScales(decide(planner)) == [1])
        planner.setServerScaleOverride(7)
        #expect(serverScales(decide(planner)).isEmpty, "a factor outside (0, 1] is no override")
    }

    @Test("the displays on screen are asked for at their own size; at a scale, the whole picture")
    func regionsFollowTheScale() {
        let planner = mac(.dataSaver)
        planner.setRegions([RFBRectangle(x: 3200, y: 0, width: 1280, height: 800)])
        planner.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800)
        let before = clientMessages(decide(planner)).filter { $0.type == 3 }.map(\.bytes)
        #expect(before.last == RFBRectangle(x: 3200, y: 0, width: 1280, height: 800).updateRequest(incremental: false))
        _ = planner.updateBegan()
        planner.appleLayoutArrived(serverScale: 0.75, width: 3360, height: 1350)
        let after = clientMessages(decide(planner)).filter { $0.type == 3 }.map(\.bytes)
        // A Mac asked for part of a scaled picture failed to read it back and stopped sending (2026-10-11).
        #expect(after.last == RFBRectangle(x: 0, y: 0, width: 3360, height: 1350).updateRequest(incremental: false))
    }
}

// MARK: - The client

@Suite("A Mac's displays, end to end", .serialized)
struct AppleDisplaysClientTests {
    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var screenLists: [[VNCScreen]] = []
        private var metadataList: [RFBAppleDisplayMetadata] = []
        private var frameSizes: [String] = []
        var screens: [[VNCScreen]] { lock.withLock { screenLists } }
        var metadata: [RFBAppleDisplayMetadata] { lock.withLock { metadataList } }
        var frames: [String] { lock.withLock { frameSizes } }

        /// A value a callback sets from the client's task.
        final class Box<Value>: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: Value
            init(_ value: Value) { stored = value }
            var value: Value { lock.withLock { stored } }
            func update(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
        }

        func callbacks() -> VNCClientCallbacks {
            var callbacks = VNCClientCallbacks()
            callbacks.screens = { value in self.lock.withLock { self.screenLists.append(value) } }
            callbacks.appleDisplayMetadata = { value in self.lock.withLock { self.metadataList.append(value) } }
            callbacks.frame = { width, height, _ in self.lock.withLock { self.frameSizes.append("\(width)x\(height)") } }
            return callbacks
        }
    }

    @Test("a layout publishes the displays, and a scaled one resizes the framebuffer the next pictures arrive in")
    func layoutAndScale() async throws {
        var mac = MacLayout.greeting(width: 4480, height: 1800)
        mac += MacLayout.update(MacLayout.mixedPayload)
        mac += MacLayout.update(MacLayout.halved())
        // A pixel in the scaled framebuffer's last column: outside it until the layout resized it.
        mac += [0, 0, 0, 1] + MacLayout.rectangleHeader(2239, 899, 1, 1, .raw) + [1, 2, 3, 0]
        let seen = Seen()
        let sink = MemoryByteSink()
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", password: ""), callbacks: seen.callbacks(),
                               source: MemoryByteSource(mac), sink: sink)
        client.setQuality(.best)
        client.setServerScaling(0.5)
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }

        #expect(seen.screens.first?.map(\.id) == [4, 1])
        #expect(seen.screens.first?.first?.isMain == true)
        #expect(seen.screens.last == [VNCScreen(id: 4, x: 0, y: 0, width: 1600, height: 900, flags: 1, isMain: true, density: 2),
                                      VNCScreen(id: 1, x: 1600, y: 0, width: 640, height: 400, flags: 0, isMain: false, density: 1)])
        #expect(seen.frames.last == "2240x900")
        #expect(client.serverScale == 0.5 && !client.awaitingServerScaling)
        #expect(client.receivedAppleDisplayMetadata)
        #expect(seen.metadata.count == 2)

        let written = await sink.written
        let messages = clientMessages(Array(written.dropFirst(13 + 1)))
        let encodings = try #require(messages.first { $0.type == 2 }).bytes
        let listed = stride(from: 4, to: encodings.count, by: 4).map { Int32(bitPattern: UInt32(encodings[$0]) << 24
            | UInt32(encodings[$0 + 1]) << 16 | UInt32(encodings[$0 + 2]) << 8 | UInt32(encodings[$0 + 3])) }
        #expect(listed.first == RFBEncoding.zrle.rawValue)
        #expect(listed.contains(1101) && listed.contains(1105), "both, or a Mac reports nothing")
        #expect(serverScales(Array(written.dropFirst(13 + 1))) == [0.5], "asked once, after the first layout")
        let scaleIndex = try #require(messages.firstIndex { $0.type == 8 })
        let encodingsIndex = try #require(messages.firstIndex { $0.type == 2 })
        #expect(encodingsIndex < scaleIndex)
    }

    @Test("a ZRLE rectangle with bytes left over is reported and the session goes on")
    func zrleTrailingDataKeepsTheSession() async throws {
        // One solid tile and a byte after it, deflated with a sync flush as a Mac sends each rectangle.
        let deflated: [UInt8] = [0x78, 0x9c, 0x62, 0x14, 0x50, 0x30, 0xe0, 0x04, 0x00, 0x00, 0x00, 0xff, 0xff]
        var mac = MacLayout.greeting(width: 4480, height: 1800)
        mac += MacLayout.update(MacLayout.mixedPayload)
        mac += [0, 0, 0, 2] + MacLayout.rectangleHeader(0, 0, 2, 2, .zrle) + UInt32(deflated.count).bigEndianBytes + deflated
        mac += MacLayout.rectangleHeader(3, 3, 1, 1, .raw) + [7, 8, 9, 0]
        let seen = Seen()
        let reported = Seen.Box<[RFBZRLETrailingData]>([])
        var callbacks = seen.callbacks()
        callbacks.zrleTrailingData = { value in reported.update { $0.append(value) } }
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", password: ""), callbacks: callbacks,
                               source: MemoryByteSource(mac), sink: MemoryByteSink())
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }

        #expect(reported.value.map(\.consumed) == [4] && reported.value.map(\.inflated.count) == [5])
        #expect(client.zrleTrailingDataCount == 1)
        #expect(seen.frames.last == "4480x1800", "the update was drawn, the rectangle after it included")
        #expect(client.lastAppleEncoding == nil, "pixel rectangles were read in step after the layout")
    }

    @Test("a pointer position in the scaled picture reaches the Mac in its own pixels")
    func pointerAtScale() async throws {
        let source = MemoryByteSource(MacLayout.greeting(width: 4480, height: 1800), holdsOpen: true)
        let sink = MemoryByteSink()
        let seen = Seen()
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", password: ""), callbacks: seen.callbacks(),
                               source: source, sink: sink, close: { await source.close() })
        let run = Task { try? await client.run() }
        defer { client.cancel(); run.cancel() }
        try await waitUntil { client.isReady }
        await source.append(MacLayout.update(MacLayout.halved()))
        try await waitUntil { !seen.screens.isEmpty }
        _ = await sink.drain()
        try await client.sendPointer(buttonMask: 1, x: 100, y: 50)
        try await client.sendPointer(buttonMask: 0, x: 99_999, y: 99_999)
        let pointer = clientMessages(await sink.drain()).filter { $0.type == 5 }.map(\.bytes)
        #expect(pointer == [[5, 1, 0, 200, 0, 100],
                            [5, 0] + UInt16(4478).bigEndianBytes + UInt16(1798).bigEndianBytes],
                "clamped to the scaled framebuffer, then divided by the factor")
        await source.close()
        _ = await run.value
    }

    @Test("an unreadable layout and DisplayInfo are stepped over, and the pictures after them decode")
    func steppedOver() async throws {
        var mac = MacLayout.greeting(width: 64, height: 64)
        let unreadable = MacLayout.payload(points: (64, 64), framebuffer: (64, 64), displays: [], count: 0)
        var info = UInt16(64).bigEndianBytes + UInt16(64).bigEndianBytes + UInt32(0).bigEndianBytes + UInt16(1).bigEndianBytes
        info += [UInt8](repeating: 0x5A, count: 0x1c)
        mac += [0, 0, 0, 3]
        mac += MacLayout.rectangleHeader(0, 0, 0, 0, .appleDisplayLayout) + MacLayout.wire(unreadable)
        mac += MacLayout.rectangleHeader(0, 0, 0, 0, .appleDisplayInfo) + info
        mac += MacLayout.rectangleHeader(63, 63, 1, 1, .raw) + [1, 2, 3, 0]
        let seen = Seen()
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", password: ""), callbacks: seen.callbacks(),
                               source: MemoryByteSource(mac), sink: MemoryByteSink())
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }
        #expect(seen.screens.isEmpty, "nothing that does not hold up is published")
        #expect(seen.metadata == [.unreadableLayout(unreadable),
                                  .displayInfo(RFBAppleDisplayInfo(width: 64, height: 64, flags: 0,
                                                                   records: [[UInt8](repeating: 0x5A, count: 0x1c)]))])
        #expect(seen.frames == ["64x64"], "the pixel after them decoded")
    }
}

/// Polls until `condition` holds, for up to two seconds.
func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw RFBError.cancelled }
        try await Task.sleep(for: .milliseconds(10))
    }
}
