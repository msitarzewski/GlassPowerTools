import Foundation

/// Client-side reconstruction of the remote framebuffer as top-down BGRA8 pixels.
/// Every write is bounds-checked against the current dimensions.
public final class RFBFramebuffer {
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int) throws {
        try Self.validate(width: width, height: height)
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    public static func validate(width: Int, height: Int) throws {
        guard width >= 1, height >= 1, width <= RFBLimits.maximumDimension, height <= RFBLimits.maximumDimension,
              width * height <= RFBLimits.maximumPixels else {
            throw RFBError.resourceLimit("The server desktop size \(width) × \(height) is outside the supported range.")
        }
    }

    public var bytesPerRow: Int { width * 4 }

    /// The share of `rect` that is not black, on a grid of samples, in whole percent: whether a
    /// display's part of the picture holds anything (the log's flow line, 2026-10-11).
    func litPercent(in rect: RFBRectangle, samples: Int = 24) -> Int? {
        guard let area = rect.clipped(width: width, height: height), area.width > 0, area.height > 0 else { return nil }
        var lit = 0, total = 0
        for row in 0..<samples {
            let y = area.y + (area.height * (2 * row + 1)) / (2 * samples)
            for column in 0..<samples {
                let x = area.x + (area.width * (2 * column + 1)) / (2 * samples)
                let offset = (y * width + x) * 4
                total += 1
                if pixels[offset] > 24 || pixels[offset + 1] > 24 || pixels[offset + 2] > 24 { lit += 1 }
            }
        }
        return total == 0 ? nil : lit * 100 / total
    }

    /// Contents after a resize are undefined until the next full update, as RFC 6143 §7.8.2 permits.
    public func resize(width: Int, height: Int) throws {
        try Self.validate(width: width, height: height)
        guard width != self.width || height != self.height else { return }
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    public func snapshot() -> Data { Data(pixels) }

    @inline(__always)
    func store(x: Int, y: Int, blue: UInt8, green: UInt8, red: UInt8) {
        let offset = (y * width + x) * 4
        pixels[offset] = blue; pixels[offset + 1] = green; pixels[offset + 2] = red; pixels[offset + 3] = 255
    }

    func fill(_ rect: RFBRectangle, blue: UInt8, green: UInt8, red: UInt8) {
        guard !rect.isEmpty else { return }
        for y in rect.y..<rect.maxY {
            var offset = (y * width + rect.x) * 4
            for _ in 0..<rect.width {
                pixels[offset] = blue; pixels[offset + 1] = green; pixels[offset + 2] = red; pixels[offset + 3] = 255
                offset += 4
            }
        }
    }

    /// Writes rows of client-format pixels (B, G, R, X per pixel) into `rect`.
    func storeRaw(_ rect: RFBRectangle, source: ArraySlice<UInt8>) throws {
        guard source.count == rect.width * rect.height * 4 else {
            throw RFBError.protocolViolation("The raw rectangle payload has the wrong length.")
        }
        guard !rect.isEmpty else { return }
        var input = source.startIndex
        for y in rect.y..<rect.maxY {
            var offset = (y * width + rect.x) * 4
            for _ in 0..<rect.width {
                pixels[offset] = source[input]; pixels[offset + 1] = source[input + 1]
                pixels[offset + 2] = source[input + 2]; pixels[offset + 3] = 255
                offset += 4; input += 4
            }
        }
    }

    func copy(from sourceX: Int, _ sourceY: Int, to rect: RFBRectangle) throws {
        guard sourceX >= 0, sourceY >= 0, sourceX + rect.width <= width, sourceY + rect.height <= height else {
            throw RFBError.protocolViolation("The CopyRect source lies outside the framebuffer.")
        }
        guard !rect.isEmpty else { return }
        let rowBytes = rect.width * 4
        // Overlapping regions copy in the safe direction, like memmove.
        let rows = sourceY < rect.y ? Array((0..<rect.height).reversed()) : Array(0..<rect.height)
        pixels.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            for row in rows {
                let from = base + ((sourceY + row) * width + sourceX) * 4
                let to = base + ((rect.y + row) * width + rect.x) * 4
                memmove(to, from, rowBytes)
            }
        }
    }
}
