import Foundation
import ImageIO
import CoreGraphics

/// Tight encoding (encoding 7, from the RFB community registry as TightVNC and TigerVNC implement
/// it): per rectangle a fill, a JPEG, or zlib-compressed pixels through one of four persistent
/// streams with a copy, palette or gradient filter. It is what lets a server send a slow link JPEG
/// at a quality the client chooses, instead of lossless tiles the link cannot carry
/// (2026-09-30, a desktop "terribly slow" on Vision Pro).
///
/// Pixels here are TPIXELs: with this client's 32-bit format (depth 24, true colour, 8 bits a
/// channel) each is three bytes, red, green, blue; at 16 and 8 bits each is a whole pixel value.
final class RFBTightDecoder {
    private var streams: [ZlibInflater?] = [nil, nil, nil, nil]

    /// Decodes one Tight rectangle, whose TPIXELs are in `pixels`' format; returns the bytes it read
    /// from the connection.
    func decode(_ rect: RFBRectangle, from source: any RFBByteSource, into framebuffer: RFBFramebuffer,
                pixels: RFBPixelDecoder = .native) async throws -> Int {
        let control = try await source.u8()
        var consumed = 1
        for index in 0..<4 where control & (1 << index) != 0 {
            streams[index] = nil
        }
        let size = pixels.tightBytes
        let method = control >> 4
        switch method {
        case 0x08:
            let pixel = pixels.colour(try await source.read(size)[...], at: 0, width: .tight)
            framebuffer.fill(rect, blue: pixel.blue, green: pixel.green, red: pixel.red)
            return consumed + size
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
                let data = try await readData(count: rect.width * rect.height * size, stream: streamIndex,
                                              from: source, consumed: &consumed)
                Self.storeTPixels(Self.rgb(data, count: rect.width * rect.height, pixels: pixels), rect: rect, into: framebuffer)
            case 1:
                let colours = Int(try await source.u8()) + 1
                let palette = try await source.read(colours * size)
                consumed += 1 + colours * size
                let rowBytes = colours == 2 ? (rect.width + 7) / 8 : rect.width
                let data = try await readData(count: rowBytes * rect.height, stream: streamIndex,
                                              from: source, consumed: &consumed)
                try Self.storePalette(data, palette: Self.rgb(palette, count: colours, pixels: pixels), colours: colours,
                                      rowBytes: rowBytes, rect: rect, into: framebuffer)
            case 2:
                let data = try await readData(count: rect.width * rect.height * size, stream: streamIndex,
                                              from: source, consumed: &consumed)
                let rgb = size == 3
                    ? Self.ungradient(data, width: rect.width, height: rect.height)
                    : Self.ungradient(data, width: rect.width, height: rect.height, pixels: pixels)
                Self.storeTPixels(rgb, rect: rect, into: framebuffer)
            default:
                throw RFBError.protocolViolation("The server used an unknown Tight filter \(filter).")
            }
            return consumed
        default:
            throw RFBError.protocolViolation("The server used an unknown Tight compression method \(method).")
        }
    }

    /// TPIXELs as red, green, blue triplets: as they are when a TPIXEL is three bytes, converted
    /// from the pixel format otherwise.
    static func rgb(_ data: [UInt8], count: Int, pixels: RFBPixelDecoder) -> [UInt8] {
        guard pixels.tightBytes != 3 else { return data }
        var output = [UInt8](repeating: 0, count: count * 3)
        let slice = data[...]
        for index in 0..<count {
            let colour = pixels.colour(slice, at: index * pixels.tightBytes, width: .tight)
            output[index * 3] = colour.red; output[index * 3 + 1] = colour.green; output[index * 3 + 2] = colour.blue
        }
        return output
    }

    /// The gradient filter for pixel formats whose TPIXEL is a whole pixel value: each component,
    /// at its own depth, is the difference from left + above − above-left, clamped to its range,
    /// as TightVNC's FilterGradient16/32 define it. Returns red, green, blue triplets.
    static func ungradient(_ data: [UInt8], width: Int, height: Int, pixels: RFBPixelDecoder) -> [UInt8] {
        let format = pixels.format, size = pixels.tightBytes
        let maxima = [UInt32(format.redMax), UInt32(format.greenMax), UInt32(format.blueMax)]
        let shifts = [UInt32(format.redShift), UInt32(format.greenShift), UInt32(format.blueShift)]
        var above = [UInt32](repeating: 0, count: width * 3), row = above
        var output = [UInt8](repeating: 0, count: width * height * 3)
        let slice = data[...]
        for y in 0..<height {
            for x in 0..<width {
                let difference = pixels.value(slice, at: (y * width + x) * size, width: .tight)
                var value: UInt32 = 0
                for channel in 0..<3 {
                    let left = x > 0 ? Int(row[(x - 1) * 3 + channel]) : 0
                    let up = Int(above[x * 3 + channel])
                    let upLeft = x > 0 ? Int(above[(x - 1) * 3 + channel]) : 0
                    let predicted = UInt32(min(Int(maxima[channel]), max(0, left + up - upLeft)))
                    let component = ((difference >> shifts[channel]) &+ predicted) & maxima[channel]
                    row[x * 3 + channel] = component
                    value |= component << shifts[channel]
                }
                let colour = pixels.bgr(value)
                let offset = (y * width + x) * 3
                output[offset] = colour.red; output[offset + 1] = colour.green; output[offset + 2] = colour.blue
            }
            swap(&above, &row)
        }
        return output
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
