import Foundation

/// Decodes one framebuffer-update rectangle from the connection into the framebuffer.
/// RFC 6143 §7.7 (Raw, CopyRect, RRE, Hextile, ZRLE) and the community registry (Zlib, Cursor).
final class RFBRectangleDecoder {
    private var zlibStream: ZlibInflater?
    private var zrleStream: ZlibInflater?
    private let tight = RFBTightDecoder()

    init() {}

    /// Decodes one rectangle, whose pixels are in `pixels`' format, and returns about how many
    /// bytes it took on the wire (RRE and Hextile, read piecemeal, report 0; the client measures
    /// the link from what arrives at the connection instead, `RFBCountingByteSource`).
    @discardableResult
    func decode(_ rect: RFBRectangle, encoding: RFBEncoding, from source: any RFBByteSource,
                into framebuffer: RFBFramebuffer, pixels: RFBPixelDecoder = .native) async throws -> Int {
        switch encoding {
        case .raw:
            let bytes = try await source.read(rect.width * rect.height * pixels.bytesPerPixel)
            try framebuffer.storeRaw(rect, source: pixels.bgra(bytes[...], count: rect.width * rect.height, width: .pixel)[...])
            return bytes.count
        case .copyRect:
            let sourceX = Int(try await source.u16()), sourceY = Int(try await source.u16())
            try framebuffer.copy(from: sourceX, sourceY, to: rect)
            return 4
        case .rre:
            try await decodeRRE(rect, from: source, into: framebuffer, pixels: pixels)
            return 0
        case .hextile:
            try await decodeHextile(rect, from: source, into: framebuffer, pixels: pixels)
            return 0
        case .zlib:
            let length = Int(try await source.u32())
            guard length <= RFBLimits.maximumEncodedRectangleBytes else {
                throw RFBError.resourceLimit("The compressed rectangle is too large.")
            }
            let compressed = try await source.read(length)
            if zlibStream == nil { zlibStream = try ZlibInflater() }
            let raw = try zlibStream!.inflate(compressed, expectedOutput: rect.width * rect.height * pixels.bytesPerPixel)
            try framebuffer.storeRaw(rect, source: pixels.bgra(raw[...], count: rect.width * rect.height, width: .pixel)[...])
            return 4 + length
        case .zrle:
            let length = Int(try await source.u32())
            guard length <= RFBLimits.maximumEncodedRectangleBytes else {
                throw RFBError.resourceLimit("The compressed rectangle is too large.")
            }
            let compressed = try await source.read(length)
            if zrleStream == nil { zrleStream = try ZlibInflater() }
            let tiles = try zrleStream!.inflateAll(compressed)
            try Self.decodeZRLETiles(tiles, rect: rect, into: framebuffer, pixels: pixels)
            return 4 + length
        case .tight:
            return try await tight.decode(rect, from: source, into: framebuffer, pixels: pixels)
        case .cursor, .desktopSize, .lastRect, .extendedDesktopSize, .appleDisplayInfo, .appleDisplayLayout,
             .appleCursorPosition, .appleCursorImage:
            throw RFBError.protocolViolation("Pseudo-encodings are handled by the client, not the rectangle decoder.")
        }
    }

    // MARK: RRE

    private func decodeRRE(_ rect: RFBRectangle, from source: any RFBByteSource, into framebuffer: RFBFramebuffer,
                           pixels: RFBPixelDecoder) async throws {
        let count = Int(try await source.u32())
        guard count <= rect.width * rect.height else { throw RFBError.protocolViolation("Too many RRE subrectangles.") }
        let size = pixels.bytesPerPixel
        let background = pixels.colour(try await source.read(size)[...], at: 0, width: .pixel)
        framebuffer.fill(rect, blue: background.blue, green: background.green, red: background.red)
        for _ in 0..<count {
            let entry = try await source.read(size + 8)
            let colour = pixels.colour(entry[...], at: 0, width: .pixel)
            var reader = ByteReader(entry, offset: size)
            let sub = try Self.subrectangle(x: Int(try reader.u16()), y: Int(try reader.u16()),
                                            width: Int(try reader.u16()), height: Int(try reader.u16()), within: rect)
            framebuffer.fill(sub, blue: colour.blue, green: colour.green, red: colour.red)
        }
    }

    static func subrectangle(x: Int, y: Int, width: Int, height: Int, within rect: RFBRectangle) throws -> RFBRectangle {
        guard width >= 1, height >= 1, x + width <= rect.width, y + height <= rect.height else {
            throw RFBError.protocolViolation("The server sent a subrectangle outside its rectangle.")
        }
        return RFBRectangle(x: rect.x + x, y: rect.y + y, width: width, height: height)
    }

    // MARK: Hextile

    private func decodeHextile(_ rect: RFBRectangle, from source: any RFBByteSource, into framebuffer: RFBFramebuffer,
                               pixels: RFBPixelDecoder) async throws {
        let size = pixels.bytesPerPixel
        var background: (UInt8, UInt8, UInt8) = (0, 0, 0)
        var foreground: (UInt8, UInt8, UInt8) = (0, 0, 0)
        var tileY = rect.y
        while tileY < rect.maxY {
            let tileHeight = min(16, rect.maxY - tileY)
            var tileX = rect.x
            while tileX < rect.maxX {
                let tileWidth = min(16, rect.maxX - tileX)
                let tile = RFBRectangle(x: tileX, y: tileY, width: tileWidth, height: tileHeight)
                let subencoding = try await source.u8()
                if subencoding & 1 != 0 {
                    let bytes = try await source.read(tileWidth * tileHeight * size)
                    try framebuffer.storeRaw(tile, source: pixels.bgra(bytes[...], count: tileWidth * tileHeight, width: .pixel)[...])
                } else {
                    if subencoding & 2 != 0 {
                        let pixel = pixels.colour(try await source.read(size)[...], at: 0, width: .pixel)
                        background = (pixel.blue, pixel.green, pixel.red)
                    }
                    if subencoding & 4 != 0 {
                        let pixel = pixels.colour(try await source.read(size)[...], at: 0, width: .pixel)
                        foreground = (pixel.blue, pixel.green, pixel.red)
                    }
                    framebuffer.fill(tile, blue: background.0, green: background.1, red: background.2)
                    if subencoding & 8 != 0 {
                        let count = Int(try await source.u8())
                        let coloured = subencoding & 16 != 0
                        let payload = try await source.read(count * (coloured ? size + 2 : 2))
                        var reader = ByteReader(payload)
                        for _ in 0..<count {
                            var colour = foreground
                            if coloured {
                                let pixel = try reader.bytes(size)
                                let value = pixels.colour(pixel, at: pixel.startIndex, width: .pixel)
                                colour = (value.blue, value.green, value.red)
                            }
                            let xy = try reader.u8(), wh = try reader.u8()
                            let sub = try Self.subrectangle(x: Int(xy >> 4), y: Int(xy & 15), width: Int(wh >> 4) + 1,
                                                            height: Int(wh & 15) + 1, within: tile)
                            framebuffer.fill(sub, blue: colour.0, green: colour.1, red: colour.2)
                        }
                    }
                }
                tileX += 16
            }
            tileY += 16
        }
    }

    // MARK: ZRLE

    /// Pixels are CPIXELs (RFC 6143 §7.7.6): three bytes (B, G, R) in the 32-bit client format,
    /// whose colour bits are all in its least significant three bytes; two at 16 bits; one at 8.
    /// Bytes left over once every tile is read throw `RFBZRLETrailingData`, after the tiles are drawn.
    static func decodeZRLETiles(_ bytes: [UInt8], rect: RFBRectangle, into framebuffer: RFBFramebuffer,
                                pixels: RFBPixelDecoder = .native) throws {
        var reader = ByteReader(bytes)
        var census = RFBZRLETrailingData.Census()
        var tileY = rect.y
        while tileY < rect.maxY {
            let tileHeight = min(64, rect.maxY - tileY)
            var tileX = rect.x
            while tileX < rect.maxX {
                let tileWidth = min(64, rect.maxX - tileX)
                let tile = RFBRectangle(x: tileX, y: tileY, width: tileWidth, height: tileHeight)
                if reader.offset < bytes.count { census.count(bytes[reader.offset]) }
                try decodeZRLETile(&reader, tile: tile, into: framebuffer, pixels: pixels)
                tileX += 64
            }
            tileY += 64
        }
        guard reader.isAtEnd else {
            throw RFBZRLETrailingData(rectangle: rect, inflated: bytes, consumed: reader.offset, census: census)
        }
    }

    private static func decodeZRLETile(_ reader: inout ByteReader, tile: RFBRectangle, into framebuffer: RFBFramebuffer,
                                       pixels: RFBPixelDecoder) throws {
        let subencoding = try reader.u8()
        let pixelCount = tile.width * tile.height
        let size = pixels.compactBytes
        /// Palette entries as B, G, R triplets, whatever the CPIXEL's size.
        func readPalette(_ count: Int) throws -> [UInt8] {
            let raw = try reader.bytes(count * size)
            var palette = [UInt8](repeating: 0, count: count * 3)
            for index in 0..<count {
                let colour = pixels.colour(raw, at: raw.startIndex + index * size, width: .compact)
                palette[index * 3] = colour.blue; palette[index * 3 + 1] = colour.green; palette[index * 3 + 2] = colour.red
            }
            return palette
        }
        switch subencoding {
        case 0:
            let raw = try reader.bytes(pixelCount * size)
            var input = raw.startIndex
            for y in tile.y..<tile.maxY {
                for x in tile.x..<tile.maxX {
                    let colour = pixels.colour(raw, at: input, width: .compact)
                    framebuffer.store(x: x, y: y, blue: colour.blue, green: colour.green, red: colour.red)
                    input += size
                }
            }
        case 1:
            let pixel = try reader.bytes(size)
            let colour = pixels.colour(pixel, at: pixel.startIndex, width: .compact)
            framebuffer.fill(tile, blue: colour.blue, green: colour.green, red: colour.red)
        case 2...16:
            let paletteSize = Int(subencoding)
            let palette = try readPalette(paletteSize)
            let bitsPerIndex = paletteSize == 2 ? 1 : (paletteSize <= 4 ? 2 : 4)
            let rowBytes = (tile.width * bitsPerIndex + 7) / 8
            let packed = try reader.bytes(rowBytes * tile.height)
            let mask = UInt8((1 << bitsPerIndex) - 1)
            for row in 0..<tile.height {
                var bitOffset = (packed.startIndex + row * rowBytes) * 8
                for column in 0..<tile.width {
                    let byte = packed[bitOffset / 8]
                    let shift = 8 - bitsPerIndex - (bitOffset % 8)
                    let index = Int((byte >> UInt8(shift)) & mask)
                    guard index < paletteSize else { throw RFBError.protocolViolation("ZRLE palette index out of range.") }
                    framebuffer.store(x: tile.x + column, y: tile.y + row, blue: palette[index * 3],
                                      green: palette[index * 3 + 1], red: palette[index * 3 + 2])
                    bitOffset += bitsPerIndex
                }
            }
        case 128:
            var written = 0
            while written < pixelCount {
                let pixel = try reader.bytes(size)
                let colour = pixels.colour(pixel, at: pixel.startIndex, width: .compact)
                let length = try runLength(&reader)
                guard written + length <= pixelCount else { throw RFBError.protocolViolation("ZRLE run overflows its tile.") }
                storeRun(tile: tile, from: written, length: length, blue: colour.blue,
                         green: colour.green, red: colour.red, into: framebuffer)
                written += length
            }
        case 130...255:
            let paletteSize = Int(subencoding) - 128
            let palette = try readPalette(paletteSize)
            var written = 0
            while written < pixelCount {
                let entry = try reader.u8()
                let index = Int(entry & 0x7F)
                guard index < paletteSize else { throw RFBError.protocolViolation("ZRLE palette index out of range.") }
                let length = entry & 0x80 != 0 ? try runLength(&reader) : 1
                guard written + length <= pixelCount else { throw RFBError.protocolViolation("ZRLE run overflows its tile.") }
                storeRun(tile: tile, from: written, length: length, blue: palette[index * 3],
                         green: palette[index * 3 + 1], red: palette[index * 3 + 2], into: framebuffer)
                written += length
            }
        default:
            throw RFBError.protocolViolation("Unsupported ZRLE subencoding \(subencoding).")
        }
    }

    private static func runLength(_ reader: inout ByteReader) throws -> Int {
        var length = 1
        while true {
            let byte = try reader.u8()
            length += Int(byte)
            guard length <= 64 * 64 + 1 else { throw RFBError.protocolViolation("ZRLE run length is too long.") }
            if byte != 255 { return length }
        }
    }

    private static func storeRun(tile: RFBRectangle, from start: Int, length: Int, blue: UInt8, green: UInt8, red: UInt8,
                                 into framebuffer: RFBFramebuffer) {
        for index in start..<(start + length) {
            framebuffer.store(x: tile.x + index % tile.width, y: tile.y + index / tile.width, blue: blue, green: green, red: red)
        }
    }

    // MARK: Cursor pseudo-encoding

    /// Cursor pixels use the client pixel format, followed by a 1-bit-per-pixel bitmask with rows
    /// padded to whole bytes, most significant bit first, where 1 marks an opaque pixel.
    static func decodeCursor(_ rect: RFBRectangle, from source: any RFBByteSource,
                             pixels: RFBPixelDecoder = .native, pointSized: Bool = false) async throws -> VNCCursorImage {
        guard rect.width <= 384, rect.height <= 384 else { throw RFBError.resourceLimit("The remote cursor is too large.") }
        let wire = try await source.read(rect.width * rect.height * pixels.bytesPerPixel)
        let pixelBytes = try pixels.bgra(wire[...], count: rect.width * rect.height, width: .pixel)
        let maskRowBytes = (rect.width + 7) / 8
        let maskBytes = try await source.read(maskRowBytes * rect.height)
        var bgra = Data(count: rect.width * rect.height * 4)
        var mask = Data(count: rect.width * rect.height)
        for y in 0..<rect.height {
            for x in 0..<rect.width {
                let pixel = y * rect.width + x, offset = pixel * 4
                let opaque = (maskBytes[y * maskRowBytes + x / 8] >> (7 - UInt8(x % 8))) & 1
                mask[pixel] = opaque
                bgra[offset] = pixelBytes[offset]; bgra[offset + 1] = pixelBytes[offset + 1]
                bgra[offset + 2] = pixelBytes[offset + 2]; bgra[offset + 3] = opaque != 0 ? 255 : 0
            }
        }
        return VNCCursorImage(width: rect.width, height: rect.height, hotSpotX: rect.x, hotSpotY: rect.y, bgra: bgra, mask: mask,
                              isPointSized: pointSized)
    }
}

/// A ZRLE rectangle whose tiles were all read with inflated bytes left over (2026-10-11: a Mac sent
/// one 0.9 s after it began rendering at half size, on the connection fetching one display of two
/// while a second connection held the other). Its compressed length was read in full and the
/// deflate stream inflated all of it, so the connection and the stream are still in step: the
/// client keeps the session, logs this and asks for the picture again (`VNCClient`). It carries
/// the inflated bytes for the live probe to keep; the app logs only the figures.
public struct RFBZRLETrailingData: Error, Sendable {
    /// How many tiles began with each kind of subencoding (RFC 6143 §7.7.6).
    public struct Census: Sendable, Equatable, CustomStringConvertible {
        public var raw = 0, solid = 0, packed = 0, runs = 0, paletteRuns = 0, other = 0
        mutating func count(_ subencoding: UInt8) {
            switch subencoding {
            case 0: raw += 1
            case 1: solid += 1
            case 2...16: packed += 1
            case 128: runs += 1
            case 130...255: paletteRuns += 1
            default: other += 1
            }
        }
        public var tiles: Int { raw + solid + packed + runs + paletteRuns + other }
        public var description: String {
            "raw:\(raw),solid:\(solid),packed:\(packed),runs:\(runs),paletteRuns:\(paletteRuns),other:\(other)"
        }
    }

    public let rectangle: RFBRectangle
    /// The rectangle's tiles, inflated.
    public let inflated: [UInt8]
    /// How many of them the tiles took.
    public let consumed: Int
    public let census: Census

    public var summary: String {
        "rect=\(rectangle.x),\(rectangle.y),\(rectangle.width)x\(rectangle.height) inflated=\(inflated.count) "
            + "consumed=\(consumed) tiles=\(census.tiles) census=\(census) next=\(consumed < inflated.count ? String(inflated[consumed]) : "none")"
    }
}

extension RFBZRLETrailingData: LocalizedError {
    public var errorDescription: String? { "The ZRLE rectangle has trailing data." }
}
