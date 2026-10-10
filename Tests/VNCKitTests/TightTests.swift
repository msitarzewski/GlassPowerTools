import Foundation
import Testing
import zlib
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import VNCKit

/// Tight (encoding 7), 2026-09-30.
@Suite("Tight encoding")
struct TightTests {
    /// A zlib stream that keeps its state across rectangles, as a Tight server's does.
    final class Deflater {
        private var stream = z_stream()
        init() { deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) }
        deinit { deflateEnd(&stream) }
        func compress(_ input: [UInt8]) -> [UInt8] {
            var input = input
            var output = [UInt8](repeating: 0, count: input.count + 1024)
            let produced: Int = input.withUnsafeMutableBufferPointer { inBuf in
                output.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_in = inBuf.baseAddress; stream.avail_in = UInt32(inBuf.count)
                    stream.next_out = outBuf.baseAddress; stream.avail_out = UInt32(outBuf.count)
                    deflate(&stream, Z_SYNC_FLUSH)
                    return outBuf.count - Int(stream.avail_out)
                }
            }
            return Array(output[0..<produced])
        }
    }

    static func compact(_ length: Int) -> [UInt8] {
        if length < 0x80 { return [UInt8(length)] }
        if length < 0x4000 { return [UInt8(length & 0x7F | 0x80), UInt8(length >> 7)] }
        return [UInt8(length & 0x7F | 0x80), UInt8((length >> 7) & 0x7F | 0x80), UInt8(length >> 14)]
    }

    /// The framebuffer's pixel at (x, y) as (red, green, blue).
    static func pixel(_ fb: RFBFramebuffer, _ x: Int, _ y: Int) -> [UInt8] {
        let o = (y * fb.width + x) * 4
        return [fb.pixels[o + 2], fb.pixels[o + 1], fb.pixels[o]]
    }

    private func decode(_ bytes: [UInt8], rect: RFBRectangle, fb: RFBFramebuffer,
                        decoder: RFBTightDecoder = RFBTightDecoder()) async throws -> Int {
        try await decoder.decode(rect, from: MemoryByteSource(bytes), into: fb)
    }

    @Test func fillPaintsOneColour() async throws {
        let fb = try RFBFramebuffer(width: 4, height: 4)
        let read = try await decode([0x80, 10, 20, 30], rect: .init(x: 1, y: 1, width: 2, height: 2), fb: fb)
        #expect(read == 4)
        #expect(Self.pixel(fb, 2, 2) == [10, 20, 30])
        #expect(Self.pixel(fb, 0, 0) == [0, 0, 0])
    }

    @Test func shortCopyIsSentUncompressed() async throws {
        let fb = try RFBFramebuffer(width: 2, height: 1)
        _ = try await decode([0x00, 1, 2, 3, 4, 5, 6], rect: .init(x: 0, y: 0, width: 2, height: 1), fb: fb)
        #expect(Self.pixel(fb, 0, 0) == [1, 2, 3] && Self.pixel(fb, 1, 0) == [4, 5, 6])
    }

    @Test func compressedCopyContinuesItsStreamAcrossRectangles() async throws {
        let fb = try RFBFramebuffer(width: 8, height: 2)
        let decoder = RFBTightDecoder(), deflater = Deflater()
        for row in 0..<2 {
            let raw: [UInt8] = (0..<8).flatMap { column -> [UInt8] in [UInt8(column * 10 + row), UInt8(row), 200] }
            let z = deflater.compress(raw)
            _ = try await decode([0x10] + Self.compact(z.count) + z,   // stream 1, no filter
                                 rect: .init(x: 0, y: row, width: 8, height: 1), fb: fb, decoder: decoder)
        }
        #expect(Self.pixel(fb, 7, 1) == [71, 1, 200])
    }

    @Test func twoColourPaletteIsABitmap() async throws {
        let fb = try RFBFramebuffer(width: 9, height: 2)
        // Palette filter (control 0x40 = basic, stream 0, filter id follows), 2 colours.
        var bytes: [UInt8] = [0x40, 1, 1, 255, 0, 0, 0, 0, 255]
        // Rows of 9 pixels are 2 bytes each: 0b1000_0000 0b1000_0000, then 0b0000_0000 0b0000_0000.
        bytes += [0x80, 0x80, 0x00, 0x00]
        _ = try await decode(bytes, rect: .init(x: 0, y: 0, width: 9, height: 2), fb: fb)
        #expect(Self.pixel(fb, 0, 0) == [0, 0, 255] && Self.pixel(fb, 1, 0) == [255, 0, 0])
        #expect(Self.pixel(fb, 8, 0) == [0, 0, 255] && Self.pixel(fb, 8, 1) == [255, 0, 0])
    }

    @Test func gradientFilterReconstructsFromNeighbours() {
        // 2×2 of one colour (50, 60, 70): only the first pixel carries it; the rest predict it.
        let sent: [UInt8] = [50, 60, 70, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let out = RFBTightDecoder.ungradient(sent, width: 2, height: 2)
        #expect(out == [50, 60, 70, 50, 60, 70, 50, 60, 70, 50, 60, 70])
    }

    @Test func jpegRectangleIsDecoded() async throws {
        let width = 16, height = 8
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) { rgba[i * 4] = 220; rgba[i * 4 + 1] = 40; rgba[i * 4 + 2] = 40; rgba[i * 4 + 3] = 255 }
        let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        CGImageDestinationFinalize(destination)
        let jpeg = [UInt8](data as Data)

        let fb = try RFBFramebuffer(width: width, height: height)
        let read = try await decode([0x90] + Self.compact(jpeg.count) + jpeg,
                                    rect: .init(x: 0, y: 0, width: width, height: height), fb: fb)
        #expect(read == 1 + Self.compact(jpeg.count).count + jpeg.count)
        let middle = Self.pixel(fb, 8, 4)
        #expect(abs(Int(middle[0]) - 220) < 12 && abs(Int(middle[1]) - 40) < 12 && abs(Int(middle[2]) - 40) < 12)
    }

    @Test func compactLengthsOfOneTwoAndThreeBytes() async throws {
        for length in [5, 300, 70_000] {
            var consumed = 0
            let value = try await RFBTightDecoder.compactLength(from: MemoryByteSource(Self.compact(length)), consumed: &consumed)
            #expect(value == length && consumed == Self.compact(length).count)
        }
    }

    @Test func unknownMethodsAndFiltersAreRefused() async throws {
        let fb = try RFBFramebuffer(width: 2, height: 2)
        await #expect(throws: RFBError.self) { _ = try await decode([0xA0], rect: .init(x: 0, y: 0, width: 1, height: 1), fb: fb) }
        await #expect(throws: RFBError.self) { _ = try await decode([0x40, 9], rect: .init(x: 0, y: 0, width: 1, height: 1), fb: fb) }
    }

    // The governor moved with W30 to `StreamingTests` (AutomaticQualityTests): it now measures every
    // encoding and chooses a level, not only Tight's JPEG quality.
}
