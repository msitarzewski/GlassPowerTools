import Foundation

/// The colour depths this client asks a server for with SetPixelFormat (RFC 6143 §7.5.1). Fewer
/// bits a pixel is fewer bytes for every encoding that carries pixels: Raw, RRE, Hextile, Zlib,
/// ZRLE's CPIXEL and Tight's TPIXEL all shrink with it. It is the one lever that works on a server
/// that never sends Tight, which is why a data-saving level lowers it rather than only asking for
/// JPEG (the way Apple's own viewer's adaptive quality lowers its colour depth).
public enum RFBColourDepth: Int, Sendable, CaseIterable, Comparable {
    /// 8 bits a channel: 32 bits per pixel on the wire, three bytes in ZRLE and Tight.
    case full = 24
    /// RGB 5-6-5: two bytes per pixel.
    case thousands = 16
    /// BGR 2-3-3 true colour: one byte per pixel, 256 colours.
    case colours256 = 8

    public var pixelFormat: RFBPixelFormat {
        switch self {
        case .full: .client
        case .thousands: .rgb565
        case .colours256: .bgr233
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public extension RFBPixelFormat {
    /// 16 bits per pixel, little-endian, red in the top five bits, green in the middle six.
    static let rgb565 = RFBPixelFormat(bitsPerPixel: 16, depth: 16, bigEndian: false, trueColour: true,
                                       redMax: 31, greenMax: 63, blueMax: 31,
                                       redShift: 11, greenShift: 5, blueShift: 0)
    /// 8 bits per pixel true colour: red in bits 0–2, green 3–5, blue 6–7 (TigerVNC's "bgr233").
    static let bgr233 = RFBPixelFormat(bitsPerPixel: 8, depth: 8, bigEndian: false, trueColour: true,
                                       redMax: 7, greenMax: 7, blueMax: 3,
                                       redShift: 0, greenShift: 3, blueShift: 6)
}

/// Turns pixels as the server sends them, in the format this client asked for, into the
/// framebuffer's B, G, R, X. Every decoder reads pixels through one of these, so a change of colour
/// depth is a change of decoder and nothing else.
///
/// Three pixel widths exist on the wire (RFC 6143 §7.7.6 and the Tight specification in the
/// community registry): a PIXEL is `bitsPerPixel / 8` bytes; ZRLE's CPIXEL is three bytes when a
/// 32-bit pixel's colour fits in three of its bytes; Tight's TPIXEL is three bytes, red, green,
/// blue, when a 32-bit pixel has 8-bit channels at depth 24. Otherwise both equal the PIXEL.
struct RFBPixelDecoder: Sendable, Equatable {
    enum Width: Sendable { case pixel, compact, tight }

    let format: RFBPixelFormat
    let bytesPerPixel: Int
    let compactBytes: Int
    let tightBytes: Int
    /// The 32-bit client format: bytes on the wire are already B, G, R, X.
    let isNative: Bool
    /// When a three-byte CPIXEL holds the most significant bytes, its value is shifted up by this.
    private let compactShift: UInt32
    private let red: [UInt8], green: [UInt8], blue: [UInt8]

    static let native = try! RFBPixelDecoder(format: .client)

    init(format: RFBPixelFormat) throws {
        guard format.trueColour, [8, 16, 32].contains(format.bitsPerPixel),
              format.redMax > 0, format.greenMax > 0, format.blueMax > 0,
              format.redShift < 32, format.greenShift < 32, format.blueShift < 32 else {
            throw RFBError.unsupported("Only true-colour 8, 16 and 32 bit pixel formats are supported.")
        }
        self.format = format
        bytesPerPixel = Int(format.bitsPerPixel) / 8
        let mask = { (max: UInt16, shift: UInt8) -> UInt64 in UInt64(max) << UInt64(shift) }
        let colourBits = mask(format.redMax, format.redShift) | mask(format.greenMax, format.greenShift)
            | mask(format.blueMax, format.blueShift)
        if format.bitsPerPixel == 32, format.depth <= 24, colourBits & ~0x00FF_FFFF == 0 {
            compactBytes = 3; compactShift = 0
        } else if format.bitsPerPixel == 32, format.depth <= 24, colourBits & ~0xFFFF_FF00 == 0 {
            compactBytes = 3; compactShift = 8
        } else {
            compactBytes = bytesPerPixel; compactShift = 0
        }
        tightBytes = format.bitsPerPixel == 32 && format.depth == 24
            && format.redMax == 255 && format.greenMax == 255 && format.blueMax == 255 ? 3 : bytesPerPixel
        isNative = format == .client
        func table(_ max: UInt16) -> [UInt8] {
            // Large maxima are scaled on demand; the table covers the formats this client asks for.
            let size = Int(min(max, 1023)) + 1
            return (0..<size).map { UInt8((Int($0) * 255 + Int(max) / 2) / Int(max)) }
        }
        red = table(format.redMax); green = table(format.greenMax); blue = table(format.blueMax)
    }

    /// The colour depth this decoder's format is, for the readout.
    var colourDepth: RFBColourDepth {
        RFBColourDepth.allCases.first { $0.pixelFormat == format } ?? .full
    }

    func size(_ width: Width) -> Int {
        switch width {
        case .pixel: bytesPerPixel
        case .compact: compactBytes
        case .tight: tightBytes
        }
    }

    /// A pixel value of `width` read at `index`. Not used for a three-byte TPIXEL, which is
    /// red, green and blue rather than a pixel value (`colour(_:at:width:)` handles both).
    @inline(__always)
    func value(_ bytes: ArraySlice<UInt8>, at index: Int, width: Width) -> UInt32 {
        let count = size(width)
        var value: UInt32 = 0
        if format.bigEndian {
            for offset in 0..<count { value = value << 8 | UInt32(bytes[index + offset]) }
        } else {
            for offset in (0..<count).reversed() { value = value << 8 | UInt32(bytes[index + offset]) }
        }
        return width == .compact && count == 3 ? value << compactShift : value
    }

    @inline(__always)
    func components(_ value: UInt32) -> (red: UInt32, green: UInt32, blue: UInt32) {
        ((value >> UInt32(format.redShift)) & UInt32(format.redMax),
         (value >> UInt32(format.greenShift)) & UInt32(format.greenMax),
         (value >> UInt32(format.blueShift)) & UInt32(format.blueMax))
    }

    @inline(__always)
    private func scale(_ component: UInt32, _ max: UInt16, _ table: [UInt8]) -> UInt8 {
        Int(component) < table.count ? table[Int(component)] : UInt8(Int(component) * 255 / Int(max))
    }

    /// The pixel value's colour as B, G, R.
    @inline(__always)
    func bgr(_ value: UInt32) -> (blue: UInt8, green: UInt8, red: UInt8) {
        let parts = components(value)
        return (scale(parts.blue, format.blueMax, blue), scale(parts.green, format.greenMax, green),
                scale(parts.red, format.redMax, red))
    }

    /// One pixel of `width` at `index`, as B, G, R.
    @inline(__always)
    func colour(_ bytes: ArraySlice<UInt8>, at index: Int, width: Width) -> (blue: UInt8, green: UInt8, red: UInt8) {
        if width == .tight, tightBytes == 3 {
            return (bytes[index + 2], bytes[index + 1], bytes[index])
        }
        if isNative, width != .tight {
            // B, G, R in the first three bytes, whether PIXEL or CPIXEL.
            return (bytes[index], bytes[index + 1], bytes[index + 2])
        }
        return bgr(value(bytes, at: index, width: width))
    }

    /// `count` pixels of `width` from `source`, as B, G, R, X rows ready for the framebuffer.
    func bgra(_ source: ArraySlice<UInt8>, count: Int, width: Width) throws -> [UInt8] {
        let step = size(width)
        guard source.count == count * step else {
            throw RFBError.protocolViolation("The pixel data has the wrong length.")
        }
        if isNative, width == .pixel { return Array(source) }
        var output = [UInt8](repeating: 255, count: count * 4)
        var input = source.startIndex
        for pixel in 0..<count {
            let colour = colour(source, at: input, width: width)
            let offset = pixel * 4
            output[offset] = colour.blue; output[offset + 1] = colour.green; output[offset + 2] = colour.red
            input += step
        }
        return output
    }
}
