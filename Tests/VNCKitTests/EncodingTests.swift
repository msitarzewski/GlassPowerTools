import Foundation
import Testing
@testable import VNCKit

@Suite("Framebuffer and encodings")
struct EncodingTests {
    private func pixel(_ framebuffer: RFBFramebuffer, _ x: Int, _ y: Int) -> [UInt8] {
        let offset = (y * framebuffer.width + x) * 4
        return Array(framebuffer.pixels[offset..<(offset + 4)])
    }

    @Test func framebufferBounds() throws {
        #expect(throws: RFBError.self) { try RFBFramebuffer(width: 0, height: 10) }
        #expect(throws: RFBError.self) { try RFBFramebuffer(width: 8193, height: 10) }
        #expect(throws: RFBError.self) { try RFBFramebuffer(width: 8192, height: 8192) }
        let framebuffer = try RFBFramebuffer(width: 4, height: 3)
        #expect(throws: RFBError.self) { try RFBRectangle(x: 2, y: 0, width: 3, height: 1).validated(in: 4, 3) }
        #expect(throws: RFBError.self) { try RFBRectangle(x: -1, y: 0, width: 1, height: 1).validated(in: 4, 3) }
        #expect(try RFBRectangle(x: 0, y: 0, width: 4, height: 3).validated(in: 4, 3) == RFBRectangle(x: 0, y: 0, width: 4, height: 3))
        try framebuffer.resize(width: 2, height: 2)
        #expect(framebuffer.pixels.count == 16)
    }

    @Test func rawAndCopyRect() async throws {
        let framebuffer = try RFBFramebuffer(width: 4, height: 2)
        let decoder = RFBRectangleDecoder()
        var raw: [UInt8] = []
        for index in 0..<8 { raw += [UInt8(index), UInt8(index + 10), UInt8(index + 20), 7] }
        try await decoder.decode(RFBRectangle(x: 0, y: 0, width: 4, height: 2), encoding: .raw,
                                 from: MemoryByteSource(raw), into: framebuffer)
        #expect(pixel(framebuffer, 3, 1) == [7, 17, 27, 255])
        // Overlapping CopyRect moves the left three columns of both rows one column right.
        try await decoder.decode(RFBRectangle(x: 1, y: 0, width: 3, height: 2), encoding: .copyRect,
                                 from: MemoryByteSource([0, 0, 0, 0]), into: framebuffer)
        #expect(pixel(framebuffer, 1, 0) == [0, 10, 20, 255])
        #expect(pixel(framebuffer, 3, 1) == [6, 16, 26, 255])
        #expect(pixel(framebuffer, 0, 0) == [0, 10, 20, 255])
        await #expect(throws: RFBError.self) {
            try await decoder.decode(RFBRectangle(x: 0, y: 0, width: 4, height: 2), encoding: .copyRect,
                                     from: MemoryByteSource([0, 1, 0, 0]), into: framebuffer)
        }
        await #expect(throws: RFBError.self) {
            try await decoder.decode(RFBRectangle(x: 0, y: 0, width: 4, height: 2), encoding: .raw,
                                     from: MemoryByteSource([1, 2, 3]), into: framebuffer)
        }
    }

    @Test func rre() async throws {
        let framebuffer = try RFBFramebuffer(width: 4, height: 4)
        var bytes: [UInt8] = [0, 0, 0, 1]
        bytes += [9, 9, 9, 0]
        bytes += [1, 2, 3, 0]
        bytes += [0, 1, 0, 1, 0, 2, 0, 2]
        try await RFBRectangleDecoder().decode(RFBRectangle(x: 0, y: 0, width: 4, height: 4), encoding: .rre,
                                               from: MemoryByteSource(bytes), into: framebuffer)
        #expect(pixel(framebuffer, 0, 0) == [9, 9, 9, 255])
        #expect(pixel(framebuffer, 2, 2) == [1, 2, 3, 255])
        #expect(pixel(framebuffer, 3, 3) == [9, 9, 9, 255])
        var outside: [UInt8] = [0, 0, 0, 1]
        outside += [9, 9, 9, 0]
        outside += [1, 2, 3, 0]
        outside += [0, 3, 0, 3, 0, 2, 0, 2]
        await #expect(throws: RFBError.self) {
            try await RFBRectangleDecoder().decode(RFBRectangle(x: 0, y: 0, width: 4, height: 4), encoding: .rre,
                                                   from: MemoryByteSource(outside), into: framebuffer)
        }
    }

    @Test func hextile() async throws {
        let framebuffer = try RFBFramebuffer(width: 20, height: 3)
        // Tile 1 (16x3): background + foreground + one coloured subrect; tile 2 (4x3): raw.
        var bytes: [UInt8] = [2 | 4 | 8 | 16]
        bytes += [5, 5, 5, 0]
        bytes += [6, 6, 6, 0]
        bytes += [1]
        bytes += [1, 2, 3, 0, 0x12, 0x20]
        bytes += [1]
        bytes += [UInt8](repeating: 0xAB, count: 4 * 3 * 4)
        try await RFBRectangleDecoder().decode(RFBRectangle(x: 0, y: 0, width: 20, height: 3), encoding: .hextile,
                                               from: MemoryByteSource(bytes), into: framebuffer)
        #expect(pixel(framebuffer, 0, 0) == [5, 5, 5, 255])
        #expect(pixel(framebuffer, 1, 2) == [1, 2, 3, 255])
        #expect(pixel(framebuffer, 3, 2) == [1, 2, 3, 255])
        #expect(pixel(framebuffer, 4, 2) == [5, 5, 5, 255])
        #expect(pixel(framebuffer, 19, 2) == [0xAB, 0xAB, 0xAB, 255])
        let overflow: [UInt8] = [8, 1, 0xF0, 0x10]
        await #expect(throws: RFBError.self) {
            try await RFBRectangleDecoder().decode(RFBRectangle(x: 0, y: 0, width: 4, height: 3), encoding: .hextile,
                                                   from: MemoryByteSource(overflow), into: framebuffer)
        }
    }

    @Test func zlibAndZRLEStreamsPersistAcrossRectangles() async throws {
        let framebuffer = try RFBFramebuffer(width: 70, height: 5)
        let decoder = RFBRectangleDecoder()
        let zlib = hexBytes(Vectors.zlibRaw)
        try await decoder.decode(RFBRectangle(x: 0, y: 0, width: 2, height: 2), encoding: .zlib,
                                 from: MemoryByteSource(UInt32(zlib.count).bigEndianBytes + zlib), into: framebuffer)
        #expect(pixel(framebuffer, 1, 1) == [10, 11, 12, 255])
        let first = hexBytes(Vectors.zrle1), second = hexBytes(Vectors.zrle2)
        try await decoder.decode(RFBRectangle(x: 0, y: 0, width: 4, height: 3), encoding: .zrle,
                                 from: MemoryByteSource(UInt32(first.count).bigEndianBytes + first), into: framebuffer)
        #expect(pixel(framebuffer, 3, 2) == [1, 2, 3, 255])
        try await decoder.decode(RFBRectangle(x: 0, y: 3, width: 70, height: 2), encoding: .zrle,
                                 from: MemoryByteSource(UInt32(second.count).bigEndianBytes + second), into: framebuffer)
        #expect(pixel(framebuffer, 0, 3) == [10, 20, 30, 255])
        #expect(pixel(framebuffer, 63, 4) == [40, 50, 60, 255])
        #expect(pixel(framebuffer, 64, 3) == [7, 8, 9, 255])
        #expect(pixel(framebuffer, 69, 4) == [7, 8, 9, 255])
    }

    @Test func zrleRejectsMalformedTiles() throws {
        let framebuffer = try RFBFramebuffer(width: 4, height: 4)
        let rect = RFBRectangle(x: 0, y: 0, width: 4, height: 4)
        #expect(throws: RFBError.self) { try RFBRectangleDecoder.decodeZRLETiles([2, 1, 1, 1, 2, 2, 2, 0x80, 0, 0, 0, 0x80], rect: rect, into: framebuffer) }
        #expect(throws: RFBError.self) { try RFBRectangleDecoder.decodeZRLETiles([128, 1, 2, 3, 200], rect: rect, into: framebuffer) }
        #expect(throws: RFBError.self) { try RFBRectangleDecoder.decodeZRLETiles([130, 1, 1, 1, 2, 2, 2, 0x82, 0], rect: rect, into: framebuffer) }
        #expect(throws: RFBError.self) { try RFBRectangleDecoder.decodeZRLETiles([1, 1, 2, 3, 9], rect: rect, into: framebuffer) }
        #expect(throws: RFBError.self) { try RFBRectangleDecoder.decodeZRLETiles([17], rect: rect, into: framebuffer) }
        try RFBRectangleDecoder.decodeZRLETiles([130, 1, 1, 1, 2, 2, 2, 0x81, 15], rect: rect, into: framebuffer)
        #expect(Array(framebuffer.pixels[60..<63]) == [2, 2, 2])
    }

    @Test func cursorDecoding() async throws {
        var bytes: [UInt8] = []
        for index in 0..<6 { bytes += [UInt8(index), 0, 0, 0] }
        bytes += [0b1010_0000, 0b0100_0000]
        let cursor = try await RFBRectangleDecoder.decodeCursor(RFBRectangle(x: 1, y: 0, width: 3, height: 2), from: MemoryByteSource(bytes))
        #expect(cursor.hotSpotX == 1 && cursor.hotSpotY == 0)
        #expect(Array(cursor.mask) == [1, 0, 1, 0, 1, 0])
        #expect(cursor.bgra[3] == 255 && cursor.bgra[7] == 0 && cursor.bgra[8] == 2)
        await #expect(throws: RFBError.self) {
            _ = try await RFBRectangleDecoder.decodeCursor(RFBRectangle(x: 0, y: 0, width: 400, height: 2), from: MemoryByteSource([]))
        }
    }

    @Test func keysyms() {
        #expect(RFBKeysym.keysym(scancode: 0x1E, extended: false) == 0x61)
        #expect(RFBKeysym.keysym(scancode: 0x1D, extended: true) == RFBKeysym.controlRight)
        #expect(RFBKeysym.keysym(scancode: 0x53, extended: true) == RFBKeysym.delete)
        #expect(RFBKeysym.keysym(scancode: 0x53, extended: false) == 0xFF9F)
        #expect(RFBKeysym.keysym(scancode: 0x7F, extended: false) == nil)
        #expect(RFBKeysym.keysym(for: "A") == 0x41)
        #expect(RFBKeysym.keysym(for: "é") == 0xE9)
        #expect(RFBKeysym.keysym(for: "€") == 0x0100_20AC)
        #expect(RFBKeysym.keysym(for: "\n") == RFBKeysym.return)
        #expect(RFBKeysym.keysym(for: Unicode.Scalar(0x07)) == nil)
    }

    @Test func protocolVersions() throws {
        #expect(try RFBProtocolVersion.parse(Array("RFB 003.889\n".utf8)).negotiated == RFBProtocolVersion(major: 3, minor: 8))
        #expect(try RFBProtocolVersion.parse(Array("RFB 003.007\n".utf8)).negotiated == RFBProtocolVersion(major: 3, minor: 7))
        #expect(try RFBProtocolVersion.parse(Array("RFB 003.003\n".utf8)).negotiated == RFBProtocolVersion(major: 3, minor: 3))
        #expect(RFBProtocolVersion(major: 3, minor: 8).wireBytes == Array("RFB 003.008\n".utf8))
        #expect(throws: RFBError.self) { try RFBProtocolVersion.parse(Array("HTTP/1.1 200\n".utf8)) }
        #expect(throws: RFBError.self) { try RFBProtocolVersion.parse(Array("RFB 004.000\n".utf8)) }
    }
}
