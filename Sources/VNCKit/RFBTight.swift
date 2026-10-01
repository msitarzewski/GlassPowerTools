import Foundation
import ImageIO
import CoreGraphics

/// Tight encoding (encoding 7, from the RFB community registry as TightVNC and TigerVNC implement
/// it): per rectangle a fill, a JPEG, or zlib-compressed pixels through one of four persistent
/// streams with a copy, palette or gradient filter. It is what lets a server send a slow link JPEG
/// at a quality the client chooses, instead of lossless tiles the link cannot carry
/// (2026-09-30, a desktop "terribly slow" on Vision Pro).
///
/// Pixels here are TPIXELs: with this client's format (32 bpp, depth 24, true colour, 8 bits a
/// channel) each is three bytes, red, green, blue.
final class RFBTightDecoder {
    private var streams: [ZlibInflater?] = [nil, nil, nil, nil]

    /// Decodes one Tight rectangle; returns the bytes it read from the connection.
    func decode(_ rect: RFBRectangle, from source: any RFBByteSource, into framebuffer: RFBFramebuffer) async throws -> Int {
        let control = try await source.u8()
        var consumed = 1
        for index in 0..<4 where control & (1 << index) != 0 {
            streams[index] = nil
        }
        let method = control >> 4
        switch method {
        case 0x08:
            let pixel = try await source.read(3)
            framebuffer.fill(rect, blue: pixel[2], green: pixel[1], red: pixel[0])
            return consumed + 3
        case 0x09:
            let length = try await Self.compactLength(from: source, consumed: &consumed)
            let jpeg = try await source.read(length)
            try Self.storeJPEG(jpeg, rect: rect, into: framebuffer)
            return consumed + length
        case 0x00...0x07:
            let streamIndex = Int(method & 0x03)
            let filter: UInt8
            if method & 0x04 != 0 {
                filter = try await source.u8()
                consumed += 1
            } else {
                filter = 0
            }
            switch filter {
            case 0:
                let data = try await readData(count: rect.width * rect.height * 3, stream: streamIndex,
                                              from: source, consumed: &consumed)
                Self.storeTPixels(data, rect: rect, into: framebuffer)
            case 1:
                let colours = Int(try await source.u8()) + 1
                let palette = try await source.read(colours * 3)
                consumed += 1 + colours * 3
                let rowBytes = colours == 2 ? (rect.width + 7) / 8 : rect.width
                let data = try await readData(count: rowBytes * rect.height, stream: streamIndex,
                                              from: source, consumed: &consumed)
                try Self.storePalette(data, palette: palette, colours: colours, rowBytes: rowBytes,
                                      rect: rect, into: framebuffer)
            case 2:
                let data = try await readData(count: rect.width * rect.height * 3, stream: streamIndex,
                                              from: source, consumed: &consumed)
                Self.storeTPixels(Self.ungradient(data, width: rect.width, height: rect.height),
                                  rect: rect, into: framebuffer)
            default:
                throw RFBError.protocolViolation("The server used an unknown Tight filter \(filter).")
            }
            return consumed
        default:
            throw RFBError.protocolViolation("The server used an unknown Tight compression method \(method).")
        }
    }

    /// Fewer than 12 bytes are sent as they are; anything more is a compact length and zlib data
    /// continuing the chosen stream.
    private func readData(count: Int, stream index: Int, from source: any RFBByteSource,
                          consumed: inout Int) async throws -> [UInt8] {
        guard count <= RFBLimits.maximumEncodedRectangleBytes else {
            throw RFBError.resourceLimit("The Tight rectangle is too large.")
        }
        if count < 12 {
            consumed += count
            return try await source.read(count)
        }
        let length = try await Self.compactLength(from: source, consumed: &consumed)
        let compressed = try await source.read(length)
        consumed += length
        if streams[index] == nil { streams[index] = try ZlibInflater() }
        return try streams[index]!.inflate(compressed, expectedOutput: count)
    }

    /// One to three bytes, seven bits each, low bits first.
    static func compactLength(from source: any RFBByteSource, consumed: inout Int) async throws -> Int {
        var length = 0
        for index in 0..<3 {
            let byte = try await source.u8()
            consumed += 1
            length |= Int(index < 2 ? byte & 0x7F : byte) << (7 * index)
            if byte & 0x80 == 0 || index == 2 { break }
        }
        guard length <= RFBLimits.maximumEncodedRectangleBytes else {
            throw RFBError.resourceLimit("The Tight rectangle is too large.")
        }
        return length
    }

    static func storeTPixels(_ data: [UInt8], rect: RFBRectangle, into framebuffer: RFBFramebuffer) {
        var input = 0
        for y in rect.y..<rect.maxY {
            for x in rect.x..<rect.maxX {
                framebuffer.store(x: x, y: y, blue: data[input + 2], green: data[input + 1], red: data[input])
                input += 3
            }
        }
    }

    static func storePalette(_ data: [UInt8], palette: [UInt8], colours: Int, rowBytes: Int,
                             rect: RFBRectangle, into framebuffer: RFBFramebuffer) throws {
        for row in 0..<rect.height {
            for column in 0..<rect.width {
                let index: Int
                if colours == 2 {
                    let byte = data[row * rowBytes + column / 8]
                    index = Int(byte >> (7 - UInt8(column % 8))) & 1
                } else {
                    index = Int(data[row * rowBytes + column])
                }
                guard index < colours else {
                    throw RFBError.protocolViolation("A Tight palette index is outside its palette.")
                }
                framebuffer.store(x: rect.x + column, y: rect.y + row, blue: palette[index * 3 + 2],
                                  green: palette[index * 3 + 1], red: palette[index * 3])
            }
        }
    }

    /// The gradient filter: each channel is sent as its difference from left + above − above-left.
    static func ungradient(_ data: [UInt8], width: Int, height: Int) -> [UInt8] {
        var output = data
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    let left = x > 0 ? Int(output[(y * width + x - 1) * 3 + channel]) : 0
                    let above = y > 0 ? Int(output[((y - 1) * width + x) * 3 + channel]) : 0
                    let aboveLeft = x > 0 && y > 0 ? Int(output[((y - 1) * width + x - 1) * 3 + channel]) : 0
                    let predicted = min(255, max(0, left + above - aboveLeft))
                    let index = (y * width + x) * 3 + channel
                    output[index] = UInt8((predicted + Int(data[index])) & 0xFF)
                }
            }
        }
        return output
    }

    /// A JPEG rectangle, decoded by ImageIO into this framebuffer's B, G, R, X layout.
    static func storeJPEG(_ jpeg: [UInt8], rect: RFBRectangle, into framebuffer: RFBFramebuffer) throws {
        guard !rect.isEmpty else { return }
        guard let imageSource = CGImageSourceCreateWithData(Data(jpeg) as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              image.width == rect.width, image.height == rect.height else {
            throw RFBError.protocolViolation("The server sent a JPEG rectangle that could not be decoded.")
        }
        var pixels = [UInt8](repeating: 0, count: rect.width * rect.height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: rect.width, height: rect.height,
                                          bitsPerComponent: 8, bytesPerRow: rect.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            return true
        }
        guard drawn else { throw RFBError.resourceLimit("The JPEG rectangle could not be drawn.") }
        try framebuffer.storeRaw(rect, source: pixels[...])
    }
}
