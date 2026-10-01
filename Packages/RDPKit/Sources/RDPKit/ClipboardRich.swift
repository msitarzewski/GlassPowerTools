import Foundation
import ImageIO
import CoreGraphics

/// What a copy carries beyond plain text (D42a, 2026-09-30): the same text, and where the source
/// had them, HTML, RTF and an image. Published to the server as every format present, and received
/// as every format the server offers that maps to one of these.
public struct RDPClipboardRichContent: Sendable, Equatable {
    public var text: String?
    public var html: String?
    public var rtf: Data?
    /// The image as PNG. Sent as CF_DIB, which every Windows server takes; received from CF_DIB,
    /// CF_DIBV5 or a registered "PNG" format.
    public var png: Data?

    public init(text: String? = nil, html: String? = nil, rtf: Data? = nil, png: Data? = nil) {
        self.text = text; self.html = html; self.rtf = rtf; self.png = png
    }

    public var isEmpty: Bool { text == nil && html == nil && rtf == nil && png == nil }
}

enum RDPClipboardRichFormat: Equatable, Sendable {
    case text, html, rtf, dib, png

    static let dibFormatID: UInt32 = 8
    static let dibV5FormatID: UInt32 = 17
    static let htmlName = "HTML Format"
    static let rtfName = "Rich Text Format"
    static let pngName = "PNG"
    /// IDs this client gives its registered formats in its own format list.
    static let localHTMLFormatID: UInt32 = 0xC002
    static let localRTFFormatID: UInt32 = 0xC003
}

// MARK: - HTML ("HTML Format", the CF_HTML wrapper)

/// Windows' clipboard HTML: a header of byte offsets into UTF-8, then the document with the copied
/// fragment marked.
enum RDPClipboardHTML {
    static func encode(_ html: String) -> Data {
        let prefix = "<html><body><!--StartFragment-->"
        let suffix = "<!--EndFragment--></body></html>"
        let headerTemplate = "Version:0.9\r\nStartHTML:%010d\r\nEndHTML:%010d\r\nStartFragment:%010d\r\nEndFragment:%010d\r\n"
        let headerLength = String(format: headerTemplate, 0, 0, 0, 0).utf8.count
        let startHTML = headerLength
        let startFragment = startHTML + prefix.utf8.count
        let endFragment = startFragment + html.utf8.count
        let endHTML = endFragment + suffix.utf8.count
        let header = String(format: headerTemplate, startHTML, endHTML, startFragment, endFragment)
        var data = Data((header + prefix + html + suffix).utf8)
        data.append(0)
        return data
    }

    /// The fragment that was copied, or the whole document if the offsets are missing.
    static func decode(_ data: Data) -> String? {
        let bytes = data.prefix { $0 != 0 }
        guard let text = String(data: bytes, encoding: .utf8) else { return nil }
        func offset(_ key: String) -> Int? {
            guard let range = text.range(of: key + ":") else { return nil }
            let digits = text[range.upperBound...].prefix { $0.isNumber || $0 == "-" }
            return Int(digits)
        }
        let utf8 = Array(bytes)
        if let start = offset("StartFragment"), let end = offset("EndFragment"),
           start >= 0, start <= end, end <= utf8.count {
            return String(decoding: utf8[start..<end], as: UTF8.self)
        }
        if let start = offset("StartHTML"), let end = offset("EndHTML"), start >= 0, start <= end, end <= utf8.count {
            return String(decoding: utf8[start..<end], as: UTF8.self)
        }
        return text
    }
}

// MARK: - Images (CF_DIB and PNG)

enum RDPClipboardBitmap {
    /// A PNG as a CF_DIB: a BITMAPINFOHEADER and 32-bit BGRX rows, bottom-up.
    static func dib(fromPNG png: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let pixels = bgra(image) else { return nil }
        let width = image.width, height = image.height
        var data = Data()
        data.appendLittleEndianUInt32(40)
        data.appendLittleEndianUInt32(UInt32(width))
        data.appendLittleEndianUInt32(UInt32(height))          // positive: bottom-up
        data.appendLittleEndianUInt16(1)
        data.appendLittleEndianUInt16(32)
        data.appendLittleEndianUInt32(0)                        // BI_RGB
        data.appendLittleEndianUInt32(UInt32(width * height * 4))
        data.appendLittleEndianUInt32(2835)
        data.appendLittleEndianUInt32(2835)
        data.appendLittleEndianUInt32(0)
        data.appendLittleEndianUInt32(0)
        for row in (0..<height).reversed() {
            data.append(contentsOf: pixels[(row * width * 4)..<((row + 1) * width * 4)])
        }
        return data
    }

    /// A CF_DIB or CF_DIBV5 (24- or 32-bit, uncompressed or standard bitfields) as a PNG.
    static func png(fromDIB dib: Data) -> Data? {
        let bytes = [UInt8](dib)
        func u32(_ at: Int) -> UInt32? {
            guard at + 4 <= bytes.count else { return nil }
            return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        func u16(_ at: Int) -> UInt16? {
            guard at + 2 <= bytes.count else { return nil }
            return UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
        }
        guard let headerSize = u32(0), [40, 108, 124].contains(headerSize),
              let rawWidth = u32(4), let rawHeight = u32(8), let bitCount = u16(14), let compression = u32(16)
        else { return nil }
        let width = Int(Int32(bitPattern: rawWidth))
        let signedHeight = Int(Int32(bitPattern: rawHeight))
        let height = abs(signedHeight), topDown = signedHeight < 0
        guard width > 0, height > 0, width <= 16_384, height <= 16_384,
              bitCount == 24 || bitCount == 32, compression == 0 || compression == 3 else { return nil }
        // BI_BITFIELDS with a 40-byte header puts three masks after it.
        let pixelStart = Int(headerSize) + (compression == 3 && headerSize == 40 ? 12 : 0)
        let stride = ((width * Int(bitCount) + 31) / 32) * 4
        guard pixelStart + stride * height <= bytes.count else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let step = Int(bitCount) / 8
        for row in 0..<height {
            let sourceRow = topDown ? row : height - 1 - row
            for column in 0..<width {
                let from = pixelStart + sourceRow * stride + column * step
                let to = (row * width + column) * 4
                pixels[to] = bytes[from]; pixels[to + 1] = bytes[from + 1]; pixels[to + 2] = bytes[from + 2]
            }
        }
        return encodePNG(bgra: pixels, width: width, height: height)
    }

    private static func bgra(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 16_384, height <= 16_384 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    private static func encodePNG(bgra pixels: [UInt8], width: Int, height: Int) -> Data? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
