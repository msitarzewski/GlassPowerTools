import Foundation
import Testing
@testable import VNCKit

/// W30: what this client asks a server to send, and decoding it at every colour depth it asks for.
@Suite("Colour depth")
struct ColourDepthTests {
    /// The framebuffer's pixel at (x, y) as (red, green, blue).
    private func rgb(_ fb: RFBFramebuffer, _ x: Int, _ y: Int) -> [UInt8] {
        let o = (y * fb.width + x) * 4
        return [fb.pixels[o + 2], fb.pixels[o + 1], fb.pixels[o]]
    }

    private let rgb565 = try! RFBPixelDecoder(format: .rgb565)
    private let bgr233 = try! RFBPixelDecoder(format: .bgr233)

    /// Little-endian RGB565 for red, green, blue in 0…31, 0…63, 0…31.
    private func pixel565(_ r: UInt16, _ g: UInt16, _ b: UInt16) -> [UInt8] {
        let value = r << 11 | g << 5 | b
        return [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    /// BGR233: red in bits 0–2, green 3–5, blue 6–7.
    private func pixel233(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt8 { r | g << 3 | b << 6 }

    @Test("each level asks for its own pixel format, and the wire sizes follow it")
    func pixelFormatsPerLevel() throws {
        #expect(VNCStreamProfile.best.colourDepth.pixelFormat.setPixelFormatMessage
                == [0, 0, 0, 0, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0])
        #expect(VNCStreamProfile.balanced.colourDepth == .full)
        #expect(VNCStreamProfile.dataSaver.colourDepth.pixelFormat.setPixelFormatMessage
                == [0, 0, 0, 0, 16, 16, 0, 1, 0, 31, 0, 63, 0, 31, 11, 5, 0, 0, 0, 0])
        #expect(VNCStreamProfile.lowest.colourDepth.pixelFormat.setPixelFormatMessage
                == [0, 0, 0, 0, 8, 8, 0, 1, 0, 7, 0, 7, 0, 3, 0, 3, 6, 0, 0, 0])
        let native = RFBPixelDecoder.native
        #expect((native.bytesPerPixel, native.compactBytes, native.tightBytes) == (4, 3, 3))
        #expect((rgb565.bytesPerPixel, rgb565.compactBytes, rgb565.tightBytes) == (2, 2, 2))
        #expect((bgr233.bytesPerPixel, bgr233.compactBytes, bgr233.tightBytes) == (1, 1, 1))
        #expect(throws: RFBError.self) {
            try RFBPixelDecoder(format: RFBPixelFormat(bitsPerPixel: 24, depth: 24, bigEndian: false, trueColour: true,
                                                       redMax: 255, greenMax: 255, blueMax: 255,
                                                       redShift: 16, greenShift: 8, blueShift: 0))
        }
    }

    @Test("a pixel value becomes full-range colour")
    func channelsScaleToFullRange() {
        #expect(rgb565.colour(pixel565(31, 0, 0)[...], at: 0, width: .pixel) == (0, 0, 255))
        #expect(rgb565.colour(pixel565(0, 63, 0)[...], at: 0, width: .pixel) == (0, 255, 0))
        #expect(rgb565.colour(pixel565(0, 0, 31)[...], at: 0, width: .pixel) == (255, 0, 0))
        #expect(rgb565.colour(pixel565(16, 32, 8)[...], at: 0, width: .pixel) == (66, 130, 132))
        #expect(bgr233.colour([pixel233(7, 0, 3)][...], at: 0, width: .pixel) == (255, 0, 255))
        #expect(bgr233.colour([pixel233(0, 7, 0)][...], at: 0, width: .pixel) == (0, 255, 0))
    }

    @Test("Raw, RRE and Hextile decode at 16 and 8 bits")
    func rawRREAndHextile() async throws {
        let decoder = RFBRectangleDecoder()
        let fb = try RFBFramebuffer(width: 4, height: 4)
        // Raw, 16 bits: red, green, blue, white.
        let raw = pixel565(31, 0, 0) + pixel565(0, 63, 0) + pixel565(0, 0, 31) + pixel565(31, 63, 31)
        try await decoder.decode(RFBRectangle(x: 0, y: 0, width: 4, height: 1), encoding: .raw,
                                 from: MemoryByteSource(raw), into: fb, pixels: rgb565)
        #expect(rgb(fb, 0, 0) == [255, 0, 0] && rgb(fb, 1, 0) == [0, 255, 0])
        #expect(rgb(fb, 2, 0) == [0, 0, 255] && rgb(fb, 3, 0) == [255, 255, 255])

        // RRE, 8 bits: a blue background with one green subrectangle.
        var rre = UInt32(1).bigEndianBytes + [pixel233(0, 0, 3)]
        rre += [pixel233(0, 7, 0)] + UInt16(1).bigEndianBytes + UInt16(1).bigEndianBytes
        rre += UInt16(2).bigEndianBytes + UInt16(1).bigEndianBytes
        try await decoder.decode(RFBRectangle(x: 0, y: 1, width: 4, height: 3), encoding: .rre,
                                 from: MemoryByteSource(rre), into: fb, pixels: bgr233)
        #expect(rgb(fb, 0, 1) == [0, 0, 255])
        #expect(rgb(fb, 1, 2) == [0, 255, 0] && rgb(fb, 2, 2) == [0, 255, 0] && rgb(fb, 3, 2) == [0, 0, 255])

        // Hextile, 16 bits: background red, foreground green, one foreground subrectangle at (1, 1).
        var hextile: [UInt8] = [2 | 4 | 8]
        hextile += pixel565(31, 0, 0) + pixel565(0, 63, 0)
        hextile += [1, 0x11, 0x00]
        try await decoder.decode(RFBRectangle(x: 0, y: 0, width: 4, height: 4), encoding: .hextile,
                                 from: MemoryByteSource(hextile), into: fb, pixels: rgb565)
        #expect(rgb(fb, 0, 0) == [255, 0, 0] && rgb(fb, 1, 1) == [0, 255, 0] && rgb(fb, 2, 2) == [255, 0, 0])

        // Hextile, 16 bits: a raw tile.
        let tile = (0..<16).flatMap { _ in pixel565(0, 0, 31) }
        try await decoder.decode(RFBRectangle(x: 0, y: 0, width: 4, height: 4), encoding: .hextile,
                                 from: MemoryByteSource([1] + tile), into: fb, pixels: rgb565)
        #expect(rgb(fb, 3, 3) == [0, 0, 255])
    }

    @Test("ZRLE's CPIXEL is two bytes at 16 bits and one at 8")
    func zrleCompactPixels() throws {
        let fb = try RFBFramebuffer(width: 2, height: 2)
        let rect = RFBRectangle(x: 0, y: 0, width: 2, height: 2)
        // Solid, 16 bits.
        try RFBRectangleDecoder.decodeZRLETiles([1] + pixel565(0, 63, 0), rect: rect, into: fb, pixels: rgb565)
        #expect(rgb(fb, 1, 1) == [0, 255, 0])
        // Raw, 8 bits: four one-byte pixels.
        try RFBRectangleDecoder.decodeZRLETiles([0, pixel233(7, 0, 0), pixel233(0, 7, 0), pixel233(0, 0, 3), pixel233(7, 7, 3)],
                                                rect: rect, into: fb, pixels: bgr233)
        #expect(rgb(fb, 0, 0) == [255, 0, 0] && rgb(fb, 1, 0) == [0, 255, 0])
        #expect(rgb(fb, 0, 1) == [0, 0, 255] && rgb(fb, 1, 1) == [255, 255, 255])
        // Packed palette, 16 bits: two entries, one bit each, rows padded to bytes.
        try RFBRectangleDecoder.decodeZRLETiles([2] + pixel565(31, 0, 0) + pixel565(0, 0, 31) + [0b0100_0000, 0b1000_0000],
                                                rect: rect, into: fb, pixels: rgb565)
        #expect(rgb(fb, 0, 0) == [255, 0, 0] && rgb(fb, 1, 0) == [0, 0, 255] && rgb(fb, 0, 1) == [0, 0, 255])
        // Plain RLE, 16 bits: one run of four.
        try RFBRectangleDecoder.decodeZRLETiles([128] + pixel565(31, 63, 0) + [3], rect: rect, into: fb, pixels: rgb565)
        #expect(rgb(fb, 1, 1) == [255, 255, 0])
        // Palette RLE, 8 bits: entry 1 for three pixels, then entry 0.
        try RFBRectangleDecoder.decodeZRLETiles([130, pixel233(7, 0, 0), pixel233(0, 0, 3), 0x81, 2, 0],
                                                rect: rect, into: fb, pixels: bgr233)
        #expect(rgb(fb, 0, 1) == [0, 0, 255] && rgb(fb, 1, 1) == [255, 0, 0])
        // The 32-bit client format still reads three-byte CPIXELs (B, G, R).
        try RFBRectangleDecoder.decodeZRLETiles([1, 10, 20, 30], rect: rect, into: fb)
        #expect(rgb(fb, 0, 0) == [30, 20, 10])
    }

    @Test("Tight's TPIXEL is a whole pixel at 16 and 8 bits: fill, palette, copy and gradient")
    func tightAtLowerDepths() async throws {
        let fb = try RFBFramebuffer(width: 4, height: 2)
        let rect = RFBRectangle(x: 0, y: 0, width: 4, height: 2)
        func decode(_ bytes: [UInt8], _ pixels: RFBPixelDecoder) async throws {
            _ = try await RFBTightDecoder().decode(rect, from: MemoryByteSource(bytes), into: fb, pixels: pixels)
        }
        // Fill, 16 bits.
        try await decode([0x80] + pixel565(0, 63, 31), rgb565)
        #expect(rgb(fb, 3, 1) == [0, 255, 255])
        // Two-colour palette, 8 bits: one bit a pixel, each row a byte (fewer than 12 bytes: sent plain).
        try await decode([0x40, 1, 1, pixel233(7, 0, 0), pixel233(0, 7, 0), 0b1010_0000, 0b0101_0000], bgr233)
        #expect(rgb(fb, 0, 0) == [0, 255, 0] && rgb(fb, 1, 0) == [255, 0, 0])
        #expect(rgb(fb, 0, 1) == [255, 0, 0] && rgb(fb, 1, 1) == [0, 255, 0])
        // Copy, 8 bits: eight one-byte pixels, fewer than 12, sent plain.
        let copy = [pixel233(7, 7, 3), pixel233(0, 0, 3), pixel233(7, 0, 0), pixel233(0, 7, 0),
                    pixel233(0, 0, 0), pixel233(7, 7, 3), pixel233(0, 0, 3), pixel233(7, 0, 0)]
        try await decode([0x00] + copy, bgr233)
        #expect(rgb(fb, 0, 0) == [255, 255, 255] && rgb(fb, 1, 0) == [0, 0, 255] && rgb(fb, 3, 1) == [255, 0, 0])
        // Gradient, 16 bits, on a 2 × 1 rectangle: a difference from the predicted left neighbour.
        let small = RFBRectangle(x: 0, y: 0, width: 2, height: 1)
        let gradient = pixel565(10, 20, 5) + pixel565(2, 3, 1)
        _ = try await RFBTightDecoder().decode(small, from: MemoryByteSource([0x40, 2] + gradient), into: fb, pixels: rgb565)
        #expect(rgb(fb, 0, 0) == rgb565.colourArray(pixel565(10, 20, 5)))
        #expect(rgb(fb, 1, 0) == rgb565.colourArray(pixel565(12, 23, 6)), "left + the difference, channel by channel")
    }

    @Test("a cursor's pixels are in the client's format")
    func cursorAtSixteenBits() async throws {
        let rect = RFBRectangle(x: 0, y: 0, width: 2, height: 1)
        let bytes = pixel565(31, 0, 0) + pixel565(0, 0, 31) + [0b1000_0000]
        let image = try await RFBRectangleDecoder.decodeCursor(rect, from: MemoryByteSource(bytes), pixels: rgb565)
        #expect(Array(image.bgra[0..<4]) == [0, 0, 255, 255])
        #expect(Array(image.bgra[4..<8]) == [255, 0, 0, 0], "transparent where the mask says so")
    }
}

private extension RFBPixelDecoder {
    func colourArray(_ bytes: [UInt8]) -> [UInt8] {
        let colour = colour(bytes[...], at: 0, width: .pixel)
        return [colour.red, colour.green, colour.blue]
    }
}

// MARK: - What is asked for

@Suite("Requests and quality")
struct StreamPlannerTests {
    private func started(_ planner: RFBStreamPlanner = RFBStreamPlanner(), width: Int = 3000, height: Int = 1600,
                         dialect: RFBServerDialect = .standard) -> RFBStreamPlanner {
        planner.start(width: width, height: height, dialect: dialect)
        _ = planner.openingMessages()
        return planner
    }

    private func decide(_ planner: RFBStreamPlanner, at now: ContinuousClock.Instant = .now) -> (bytes: [UInt8], wake: ContinuousClock.Instant?) {
        var out: [UInt8] = []
        let wake = planner.decide(at: now) { out += $0 }
        return (out, wake)
    }

    /// The FramebufferUpdateRequests in a write: (incremental, x, y, width, height).
    private func requests(_ bytes: [UInt8]) -> [(Bool, Int, Int, Int, Int)] {
        var found: [(Bool, Int, Int, Int, Int)] = []
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 0: index += 20
            case 2: index += 4 + (Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])) * 4
            case 3:
                func u16(_ at: Int) -> Int { Int(bytes[index + at]) << 8 | Int(bytes[index + at + 1]) }
                found.append((bytes[index + 1] == 1, u16(2), u16(4), u16(6), u16(8)))
                index += 10
            default: return found
            }
        }
        return found
    }

    @Test("with nothing said about windows, the whole framebuffer is asked for")
    func wholeFramebuffer() {
        let planner = started()
        let first = requests(decide(planner).bytes)
        #expect(first.count == 1 && first[0] == (false, 0, 0, 3000, 1600))
        _ = planner.updateBegan()
        let next = requests(decide(planner).bytes)
        #expect(next.count == 1 && next[0] == (true, 0, 0, 3000, 1600), "the next is asked for as an update begins")
    }

    @Test("only the display on screen is asked for, and CopyRect is not offered meanwhile")
    func oneDisplayOnly() {
        let planner = RFBStreamPlanner()
        planner.setRegions([RFBRectangle(x: 2000, y: 0, width: 1000, height: 600)])
        planner.start(width: 3000, height: 1600)
        let opening = planner.openingMessages()
        let encodings = stride(from: 4, to: opening.encodings.count, by: 4).map {
            Int32(bitPattern: UInt32(opening.encodings[$0]) << 24 | UInt32(opening.encodings[$0 + 1]) << 16
                  | UInt32(opening.encodings[$0 + 2]) << 8 | UInt32(opening.encodings[$0 + 3]))
        }
        #expect(!encodings.contains(RFBEncoding.copyRect.rawValue))
        let first = requests(decide(planner).bytes)
        #expect(first.count == 1 && first[0] == (false, 2000, 0, 1000, 600))
        _ = planner.updateBegan()
        #expect(requests(decide(planner).bytes).first.map { $0 == (true, 2000, 0, 1000, 600) } == true)

        // Both displays on screen: their bounding rectangle, all of it here, and CopyRect again.
        planner.setRegions([RFBRectangle(x: 0, y: 0, width: 2000, height: 1600),
                            RFBRectangle(x: 2000, y: 0, width: 1000, height: 600)])
        let grown = decide(planner).bytes
        #expect(grown.first == 2, "SetEncodings first, with CopyRect back")
        #expect(requests(grown).first.map { $0 == (false, 0, 0, 3000, 1600) } == true,
                "a display coming on screen is asked for in full at once")
    }

    @Test("with no window on screen, nothing but a single pixel is asked for, every two seconds")
    func paused() {
        let planner = started()
        let start = ContinuousClock.now
        _ = decide(planner, at: start)
        planner.setRegions([])
        _ = planner.updateBegan()
        let early = decide(planner, at: start + .milliseconds(500))
        #expect(early.bytes.isEmpty && early.wake == start + .seconds(2))
        #expect(requests(decide(planner, at: start + .seconds(2)).bytes).first.map { $0 == (true, 0, 0, 1, 1) } == true)
        // On screen again: the display, in full, at once.
        planner.setRegions(nil)
        #expect(requests(decide(planner, at: start + .milliseconds(2100)).bytes).first.map { $0 == (false, 0, 0, 3000, 1600) } == true)
    }

    @Test("a capped level waits out its interval before asking again")
    func pacing() {
        let planner = RFBStreamPlanner()
        planner.setQuality(.dataSaver)
        _ = started(planner)
        let start = ContinuousClock.now
        _ = decide(planner, at: start)
        _ = planner.updateBegan()
        let early = decide(planner, at: start + .milliseconds(10))
        #expect(early.bytes.isEmpty)
        #expect(early.wake == start + .seconds(1) / 15)
        #expect(requests(decide(planner, at: start + .milliseconds(70)).bytes).count == 1)
    }

    @Test("a change of colour depth waits until the server holds no request, then sends SetPixelFormat with a full request")
    func colourDepthWaitsForTheLine() {
        let planner = started()
        let start = ContinuousClock.now
        _ = decide(planner, at: start)                                  // one request held
        planner.setQuality(.dataSaver)
        planner.waitingForMessage(at: start)
        #expect(decide(planner, at: start + .milliseconds(100)).bytes.isEmpty, "a request is held: no SetPixelFormat yet")
        planner.messageArrived()
        let pixels = planner.updateBegan()                               // that update, in the old format
        #expect(pixels.colourDepth == .full)
        #expect(decide(planner, at: start + .milliseconds(200)).bytes.isEmpty, "not mid-update, and nothing new asked for")
        planner.waitingForMessage(at: start + .milliseconds(300))
        let switched = decide(planner, at: start + .milliseconds(300)).bytes
        #expect(Array(switched.prefix(20)) == RFBPixelFormat.rgb565.setPixelFormatMessage)
        #expect(requests(switched).first.map { $0.0 == false } == true, "and the whole picture again, in the new format")
        #expect(planner.currentDecoder().colourDepth == .thousands)
    }

    @Test("a held request that is never answered stops blocking the change after two quiet seconds")
    func quietLine() {
        let planner = started()
        let start = ContinuousClock.now
        _ = decide(planner, at: start)                                  // held, and never answered
        planner.setQuality(.best)
        planner.setQuality(.lowest)
        planner.waitingForMessage(at: start)
        #expect(decide(planner, at: start + .seconds(1)).bytes.isEmpty)
        let switched = decide(planner, at: start + .seconds(2)).bytes
        #expect(Array(switched.prefix(20)) == RFBPixelFormat.bgr233.setPixelFormatMessage)
    }

    @Test("Lowest asks a server that sends Tight for 16 bits, where its JPEG still works; 8 bits otherwise")
    func lowestKeepsJPEGWhereTheServerHasIt() {
        let planner = RFBStreamPlanner()
        planner.setQuality(.lowest)
        _ = started(planner)
        #expect(planner.currentDecoder().colourDepth == .colours256)
        let start = ContinuousClock.now
        _ = decide(planner, at: start)
        _ = planner.updateBegan()
        planner.updateEnded(bytes: 100, seconds: 0.1, changed: true, encodingBytes: [RFBEncoding.tight.rawValue: 90], at: start)
        planner.waitingForMessage(at: start)
        let switched = decide(planner, at: start + .milliseconds(10)).bytes
        #expect(Array(switched.prefix(20)) == RFBPixelFormat.rgb565.setPixelFormatMessage)
    }

    @Test("Apple's server: ZRLE first, its display layout asked for, and never fewer than 16 bits")
    func appleDialect() {
        let planner = RFBStreamPlanner()
        planner.setQuality(.lowest)
        planner.start(width: 100, height: 100, dialect: RFBServerDialect(version: RFBProtocolVersion(major: 3, minor: 889)))
        let opening = planner.openingMessages()
        #expect(opening.pixelFormat == RFBPixelFormat.rgb565.setPixelFormatMessage)
        let values = RFBEncoding.setEncodingsValues(profile: .lowest, copyRect: true, dialect: .apple)
        #expect(values.first == RFBEncoding.zrle.rawValue)
        #expect(values.contains(RFBEncoding.appleDisplayLayout.rawValue))
        #expect(!RFBEncoding.setEncodingsValues(profile: .lowest, copyRect: true).contains(1105))
        #expect(RFBServerDialect(version: RFBProtocolVersion(major: 3, minor: 8)) == .standard)
    }
}

// MARK: - Apple's display layout

@Suite("Apple display layout")
struct AppleDisplayLayoutTests {
    /// A layout as published reverse engineering describes it: a u16 length, a 0x14-byte header,
    /// 0x38 bytes a display.
    static func layout(_ displays: [(id: UInt32, left: UInt16, top: UInt16, right: UInt16, bottom: UInt16, main: Bool)],
                       framebuffer: (UInt16, UInt16), lengthCountsItself: Bool = false) -> [UInt8] {
        var header = UInt16(5).bigEndianBytes + UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes
        header += framebuffer.0.bigEndianBytes + framebuffer.1.bigEndianBytes
        header += UInt32.max.bigEndianBytes + UInt32(0).bigEndianBytes + UInt16(displays.count).bigEndianBytes
        var body: [UInt8] = []
        for display in displays {
            var record = [UInt8](repeating: 0, count: 0x10)
            record += display.id.bigEndianBytes
            record += display.top.bigEndianBytes + display.left.bigEndianBytes + display.bottom.bigEndianBytes + display.right.bigEndianBytes
            record += display.top.bigEndianBytes + display.left.bigEndianBytes + display.bottom.bigEndianBytes + display.right.bigEndianBytes
            record += UInt32(display.main ? 1 : 0).bigEndianBytes
            record += RFBPixelFormat.client.wireBytes
            body += record
        }
        let length = header.count + body.count + (lengthCountsItself ? 2 : 0)
        return UInt16(length).bigEndianBytes + header + body
    }

    @Test("a Mac's two displays are read from its layout, main display marked")
    func twoDisplays() async throws {
        let bytes = Self.layout([(1, 0, 0, 3840, 2160, true), (2, 3840, 98, 6864, 2062, false)], framebuffer: (6864, 2160))
        let source = MemoryByteSource(bytes + [0xEE])
        let layout = try #require(try await RFBAppleDisplayLayout.read(from: source))
        #expect(layout.screens == [VNCScreen(id: 1, x: 0, y: 0, width: 3840, height: 2160, flags: 1, isMain: true),
                                   VNCScreen(id: 2, x: 3840, y: 98, width: 3024, height: 1964, flags: 0, isMain: false)])
        #expect(layout.width == 6864 && layout.height == 2160)
        #expect(await source.remaining == 1, "exactly the layout is read")
    }

    @Test("a length that counts itself, and a layout that does not hold up, never desynchronise the stream")
    func readSafely() async throws {
        let counted = MemoryByteSource(Self.layout([(1, 0, 0, 100, 100, true)], framebuffer: (100, 100), lengthCountsItself: true) + [0xEE])
        #expect(try await RFBAppleDisplayLayout.read(from: counted)?.screens.count == 1)
        #expect(await counted.remaining == 1)

        // Bounds that are not a rectangle: no layout, and the stream is still where it should be.
        let broken = MemoryByteSource(Self.layout([(1, 100, 0, 50, 100, true)], framebuffer: (100, 100)) + [0xEE])
        #expect(try await RFBAppleDisplayLayout.read(from: broken) == nil)
        #expect(await broken.remaining == 1)

        // A length past any layout is refused rather than read.
        await #expect(throws: RFBError.self) {
            _ = try await RFBAppleDisplayLayout.read(from: MemoryByteSource(UInt16(60_000).bigEndianBytes))
        }
    }

    @Test("a mirror set's members share one window")
    func mirrorSet() {
        let bytes = Self.layout([(1, 0, 0, 100, 100, true), (2, 0, 0, 100, 100, false)], framebuffer: (100, 100))
        let header = Array(bytes[2..<22]), body = Array(bytes[22...])
        #expect(RFBAppleDisplayLayout.parse(header: header, body: body, count: 2)?.map(\.id) == [1])
    }

    @Test("the client publishes a Mac's displays from its layout")
    func clientPublishes() async throws {
        var server: [UInt8] = Array("RFB 003.889\n".utf8)
        server += [1, 1]
        server += UInt32(0).bigEndianBytes
        server += UInt16(300).bigEndianBytes + UInt16(100).bigEndianBytes + RFBPixelFormat.client.wireBytes + UInt32(0).bigEndianBytes
        server += [0, 0, 0, 1]
        server += UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes
        server += RFBEncoding.appleDisplayLayout.rawValue.bigEndianBytes
        server += Self.layout([(7, 0, 0, 200, 100, true), (9, 200, 20, 300, 80, false)], framebuffer: (300, 100))
        final class Box: @unchecked Sendable { var screens: [[VNCScreen]] = [] }
        let box = Box()
        var callbacks = VNCClientCallbacks()
        callbacks.screens = { box.screens.append($0) }
        let sink = MemoryByteSink()
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", password: ""), callbacks: callbacks,
                               source: MemoryByteSource(server), sink: sink)
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }
        #expect(box.screens.last?.map(\.id) == [7, 9])
        #expect(box.screens.last?.first?.isMain == true)
        let written = await sink.written
        // The SetEncodings list after the 20-byte SetPixelFormat: ZRLE first.
        let encodingsStart = 13 + 1 + 20
        #expect(written[encodingsStart] == 2)
        #expect(Array(written[(encodingsStart + 4)..<(encodingsStart + 8)]) == RFBEncoding.zrle.rawValue.bigEndianBytes)
    }
}

// MARK: - Automatic on a slow link, whatever the encoding

/// A source that delivers bytes no faster than `kilobitsPerSecond`: a slow link in memory.
private actor ThrottledSource: RFBByteSource {
    private let base: MemoryByteSource
    private let kilobitsPerSecond: Double
    init(_ bytes: [UInt8], kilobitsPerSecond: Double) {
        base = MemoryByteSource(bytes); self.kilobitsPerSecond = kilobitsPerSecond
    }
    func read(_ count: Int) async throws -> [UInt8] {
        if count > 1024 { try await Task.sleep(for: .seconds(Double(count) * 8 / 1000 / kilobitsPerSecond)) }
        return try await base.read(count)
    }
}

@Suite("Automatic quality", .serialized)
struct AutomaticQualityTests {
    @Test("the governor steps down after three slow measurements and up only after five fast ones")
    func hysteresis() {
        var governor = RFBLinkQualityGovernor()
        #expect(governor.level == .balanced && governor.jpegQuality == 8)
        // 100 KB in a second: 800 kbit/s, Data Saver.
        #expect(governor.observe(bytes: 100_000, seconds: 1) == nil)
        #expect(governor.observe(bytes: 100_000, seconds: 1) == nil)
        #expect(governor.observe(bytes: 100_000, seconds: 1) == .dataSaver)
        // One fast burst does not flip it back, and an interrupted run starts again.
        #expect(governor.observe(bytes: 1_000_000, seconds: 1) == nil)
        #expect(governor.observe(bytes: 300_000, seconds: 1) == nil)
        #expect(governor.level == .dataSaver)
        // 4 Mbit/s is Balanced's floor, but not 25% above it: no step.
        for _ in 0..<6 { #expect(governor.observe(bytes: 500_000, seconds: 1) == nil) }
        // 6 Mbit/s, five times: one level up, not two.
        for _ in 0..<4 { #expect(governor.observe(bytes: 750_000, seconds: 1) == nil) }
        #expect(governor.observe(bytes: 750_000, seconds: 1) == .balanced)
        // A very slow link drops straight to Lowest.
        for _ in 0..<2 { _ = governor.observe(bytes: 20_000, seconds: 1) }
        #expect(governor.observe(bytes: 20_000, seconds: 1) == .lowest)
    }

    @Test("small updates say nothing about the link")
    func smallUpdatesIgnored() {
        var governor = RFBLinkQualityGovernor()
        for _ in 0..<10 { #expect(governor.observe(bytes: 2_000, seconds: 1) == nil) }
        #expect(governor.level == .balanced)
    }

    @Test("a slow link sending Raw — no Tight at all — lowers the colour depth on the wire")
    func rawOnASlowLink() async throws {
        var server: [UInt8] = Array("RFB 003.008\n".utf8)
        server += [1, 1]
        server += UInt32(0).bigEndianBytes
        server += UInt16(64).bigEndianBytes + UInt16(64).bigEndianBytes + RFBPixelFormat.client.wireBytes + UInt32(0).bigEndianBytes
        // Four full-screen Raw updates of 16 KB, over a 300 kbit/s link.
        for _ in 0..<4 {
            server += [0, 0, 0, 1]
            server += UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes + UInt16(64).bigEndianBytes + UInt16(64).bigEndianBytes
            server += RFBEncoding.raw.rawValue.bigEndianBytes
            server += [UInt8](repeating: 0x40, count: 64 * 64 * 4)
        }
        let sink = MemoryByteSink()
        final class Box: @unchecked Sendable { var depths: [RFBColourDepth] = [] }
        let box = Box()
        var callbacks = VNCClientCallbacks()
        callbacks.update = { box.depths.append($0.colourDepth) }
        let client = VNCClient(configuration: VNCConfiguration(host: "slow.example", password: ""), callbacks: callbacks,
                               source: ThrottledSource(server, kilobitsPerSecond: 300), sink: sink)
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }
        let written = await sink.written
        let switchMessage = RFBPixelFormat.bgr233.setPixelFormatMessage
        let found = (0...(written.count - switchMessage.count)).contains { Array(written[$0..<($0 + switchMessage.count)]) == switchMessage }
        #expect(found, "300 kbit/s is Lowest's: 8-bit colour asked for")
        #expect(box.depths == [.full, .full, .full, .full], "every update that was in flight decoded in the format it was sent in")
        #expect(client.totalBytesReceived == server.count, "every byte counted, whatever the encoding")
    }
}
