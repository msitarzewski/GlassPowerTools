import Foundation
import GlassRDPTransport

/// Top-down premultiplied RGBA8 cursor pixels, plus exact legacy XOR composition.
public struct DesktopCursorBitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let hotSpotX: Int
    public let hotSpotY: Int
    /// Valid as a static overlay only when `requiresDesktopComposition` is false.
    public let pixels: Data
    public let requiresDesktopComposition: Bool
    /// Measured in the host's points: drawn at the shown display's pixels per point (W38).
    public let isPointSized: Bool
    private let legacyXOR: Data?
    private let legacyAND: Data?

    fileprivate init(width: Int, height: Int, hotSpotX: Int, hotSpotY: Int, pixels: Data,
                     requiresDesktopComposition: Bool, legacyXOR: Data?, legacyAND: Data?, isPointSized: Bool = false) {
        self.width = width; self.height = height; self.hotSpotX = hotSpotX; self.hotSpotY = hotSpotY
        self.pixels = pixels; self.requiresDesktopComposition = requiresDesktopComposition
        self.legacyXOR = legacyXOR; self.legacyAND = legacyAND; self.isPointSized = isPointSized
    }

    /// The same shape, measured in the host's points.
    fileprivate func pointSized(_ value: Bool) -> DesktopCursorBitmap {
        DesktopCursorBitmap(width: width, height: height, hotSpotX: hotSpotX, hotSpotY: hotSpotY, pixels: pixels,
                            requiresDesktopComposition: requiresDesktopComposition, legacyXOR: legacyXOR,
                            legacyAND: legacyAND, isPointSized: value)
    }

    /// Returns a cursor-sized RGBA overlay. Recompute when the cursor or underlying desktop changes.
    /// AND=1/XOR=0 remains transparent; inversion samples the original, unkeyed remote desktop.
    public func compositedPixels(over desktop: GlassRDPFrame, pointerX: Int, pointerY: Int) throws -> Data {
        guard requiresDesktopComposition, let xor = legacyXOR, let and = legacyAND else { return pixels }
        guard (-8192...16384).contains(pointerX), (-8192...16384).contains(pointerY) else {
            throw DesktopCursorError.invalidPosition
        }
        var result = pixels
        for y in 0..<height {
            for x in 0..<width {
                let pixel = y * width + x, offset = pixel * 4
                guard and[pixel] != 0, xor[offset] != 0 || xor[offset + 1] != 0 || xor[offset + 2] != 0 else { continue }
                let sourceX = pointerX - hotSpotX + x, sourceY = pointerY - hotSpotY + y
                guard (0..<desktop.width).contains(sourceX), (0..<desktop.height).contains(sourceY) else { continue }
                let source = desktop.pixels.startIndex + sourceY * desktop.bytesPerRow + sourceX * 4
                result[offset] = desktop.pixels[source + 2] ^ xor[offset]
                result[offset + 1] = desktop.pixels[source + 1] ^ xor[offset + 1]
                result[offset + 2] = desktop.pixels[source] ^ xor[offset + 2]
                result[offset + 3] = 255
            }
        }
        return result
    }
}

public enum DesktopCursorError: Error, Equatable, Sendable, LocalizedError {
    case invalidDimensions, invalidMasks, invalidPosition, unsupportedDepth(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidDimensions: "The remote cursor dimensions or hotspot are invalid."
        case .invalidMasks: "The remote cursor bitmap is malformed."
        case .invalidPosition: "The remote cursor position is invalid."
        case let .unsupportedDepth(depth): "The remote cursor's \(depth)-bit color format is not available."
        }
    }
}

public enum DesktopCursorDecoder {
    /// MS-RDPBCGR Color/New Pointer Update: 2-byte row alignment, bottom-up masks.
    /// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/71fad4fc-6ad4-4c7f-8103-a442bebaf7d2
    /// Indexed formats use the server palette; missing or short palettes fail explicitly.
    public static func decode(_ raw: GlassRDPCursorImage) throws -> DesktopCursorBitmap {
        try decode(width: raw.width, height: raw.height, hotSpotX: raw.hotSpotX, hotSpotY: raw.hotSpotY,
                   bitsPerPixel: raw.xorBitsPerPixel, xorMask: raw.xorMask, andMask: raw.andMask,
                   paletteEntries: raw.paletteEntries).pointSized(raw.isPointSized)
    }

    static func decode(width: Int, height: Int, hotSpotX: Int, hotSpotY: Int, bitsPerPixel: Int,
                       xorMask: Data, andMask: Data, paletteEntries: Data? = nil) throws -> DesktopCursorBitmap {
        guard (1...384).contains(width), (1...384).contains(height),
              (0..<width).contains(hotSpotX), (0..<height).contains(hotSpotY) else {
            throw DesktopCursorError.invalidDimensions
        }
        guard [1, 4, 8, 15, 16, 24, 32].contains(bitsPerPixel) else { throw DesktopCursorError.unsupportedDepth(bitsPerPixel) }
        if bitsPerPixel == 4 || bitsPerPixel == 8 {
            guard let paletteEntries, paletteEntries.count >= (bitsPerPixel == 4 ? 16 : 256) * 3 else {
                throw DesktopCursorError.invalidMasks
            }
        }
        let storedBits = bitsPerPixel == 15 ? 16 : bitsPerPixel
        let xorStride = (((width * storedBits + 7) / 8) + 1) & ~1
        let andStride = (((width + 7) / 8) + 1) & ~1
        guard xorMask.count == xorStride * height, andMask.count == andStride * height else {
            throw DesktopCursorError.invalidMasks
        }
        var colors = Data(count: width * height * 4)
        var mask = Data(count: width * height)
        var hasAlpha = false
        for y in 0..<height {
            let sourceY = height - 1 - y
            for x in 0..<width {
                let pixel = y * width + x, target = pixel * 4
                mask[pixel] = (andMask[andMask.startIndex + sourceY * andStride + x / 8] >> (7 - x % 8)) & 1
                if bitsPerPixel == 1 {
                    let white = ((xorMask[xorMask.startIndex + sourceY * xorStride + x / 8] >> (7 - x % 8)) & 1) != 0
                    colors[target] = white ? 255 : 0
                    colors[target + 1] = colors[target]; colors[target + 2] = colors[target]
                    colors[target + 3] = 255
                } else if bitsPerPixel == 4 || bitsPerPixel == 8, let paletteEntries {
                    let source = xorMask.startIndex + sourceY * xorStride + (bitsPerPixel == 4 ? x / 2 : x)
                    let index = bitsPerPixel == 4 ? Int((xorMask[source] >> (x.isMultiple(of: 2) ? 4 : 0)) & 15) : Int(xorMask[source])
                    let palette = paletteEntries.startIndex + index * 3
                    colors[target] = paletteEntries[palette]
                    colors[target + 1] = paletteEntries[palette + 1]
                    colors[target + 2] = paletteEntries[palette + 2]
                    colors[target + 3] = 255
                } else if bitsPerPixel == 15 || bitsPerPixel == 16 {
                    let source = xorMask.startIndex + sourceY * xorStride + x * 2
                    let packed = UInt16(xorMask[source]) | UInt16(xorMask[source + 1]) << 8
                    let greenBits = bitsPerPixel == 15 ? 5 : 6
                    let greenMax = (1 << greenBits) - 1
                    colors[target] = UInt8((Int(packed >> (5 + greenBits) & 31) * 255 + 15) / 31)
                    colors[target + 1] = UInt8((Int(packed >> 5) & greenMax) * 255 / greenMax)
                    colors[target + 2] = UInt8((Int(packed & 31) * 255 + 15) / 31)
                    colors[target + 3] = 255
                } else {
                    let source = xorMask.startIndex + sourceY * xorStride + x * (bitsPerPixel / 8)
                    colors[target] = xorMask[source + 2]
                    colors[target + 1] = xorMask[source + 1]
                    colors[target + 2] = xorMask[source]
                    colors[target + 3] = bitsPerPixel == 32 ? xorMask[source + 3] : 255
                    if bitsPerPixel == 32, colors[target + 3] != 0 { hasAlpha = true }
                }
            }
        }
        if bitsPerPixel == 32, hasAlpha {
            // Alpha cursors use source-over; the AND mask is ignored. Publish premultiplied bytes.
            // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-drawiconex
            for pixel in 0..<(width * height) {
                let offset = pixel * 4, alpha = UInt16(colors[offset + 3])
                for channel in 0..<3 { colors[offset + channel] = UInt8((UInt16(colors[offset + channel]) * alpha + 127) / 255) }
            }
            return .init(width: width, height: height, hotSpotX: hotSpotX, hotSpotY: hotSpotY,
                         pixels: colors, requiresDesktopComposition: false, legacyXOR: nil, legacyAND: nil)
        }
        var overlay = colors
        var needsDesktop = false
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            if mask[pixel] == 0 { overlay[offset + 3] = 255 }
            else {
                if colors[offset] != 0 || colors[offset + 1] != 0 || colors[offset + 2] != 0 { needsDesktop = true }
                for channel in 0..<4 { overlay[offset + channel] = 0 }
            }
        }
        return .init(width: width, height: height, hotSpotX: hotSpotX, hotSpotY: hotSpotY,
                     pixels: overlay, requiresDesktopComposition: needsDesktop,
                     legacyXOR: needsDesktop ? colors : nil, legacyAND: needsDesktop ? mask : nil)
    }
}
