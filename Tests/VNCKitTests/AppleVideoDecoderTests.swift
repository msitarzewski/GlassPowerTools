import CoreVideo
import Foundation
import Testing
@testable import VNCKit

/// A Mac's High Performance picture through VideoToolbox: remotex's 64 × 48 HEVC 4:4:4 fixture (MIT),
/// the stream's own format, and the colours FFmpeg decodes it to.
@Suite("Apple media stream: decoding")
struct AppleVideoDecoderTests {
    /// The fixture's access units, one a picture: a VCL unit closes one.
    private func fixtureUnits() throws -> [[[UInt8]]] {
        let url = try #require(Bundle.module.url(forResource: "hevc-444-64x48", withExtension: "h265", subdirectory: "Fixtures"))
        let stream = [UInt8](try Data(contentsOf: url))
        var starts: [Int] = []
        var index = 0
        while index + 3 <= stream.count {
            if stream[index] == 0, stream[index + 1] == 0, stream[index + 2] == 1 { starts.append(index + 3); index += 3 } else { index += 1 }
        }
        var nals: [[UInt8]] = []
        for (number, start) in starts.enumerated() {
            var nal = Array(stream[start..<(number + 1 < starts.count ? starts[number + 1] - 3 : stream.count)])
            while nal.last == 0 { nal.removeLast() }
            nals.append(nal)
        }
        var units: [[[UInt8]]] = [[]]
        for nal in nals {
            units[units.count - 1].append(nal)
            if RFBAppleHEVC.nalType(nal[0]) < 32 { units.append([]) }
        }
        return units.filter { !$0.isEmpty }
    }

    @Test("the 4:4:4 stream decodes to the colours FFmpeg converts it to")
    func decodes444() throws {
        let units = try fixtureUnits()
        #expect(units.count == 3)
        let decoder = RFBAppleVideoDecoder()
        let pictures = try units.compactMap { try decoder.decode($0) }
        #expect(pictures.count == 3, "each unit yields its picture at once")
        #expect(decoder.size.map { [$0.width, $0.height] } == [64, 48])
        let last = try #require(pictures.last)
        #expect(CVPixelBufferGetPixelFormatType(last) == kCVPixelFormatType_32BGRA)
        CVPixelBufferLockBaseAddress(last, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(last, .readOnly) }
        let base = try #require(CVPixelBufferGetBaseAddress(last)).assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(last)
        for (x, y, want) in [(2, 2, [76, 0, 38]), (20, 10, [0, 60, 8]), (40, 10, [176, 141, 109]),
                             (60, 30, [2, 62, 62]), (10, 40, [255, 4, 0]), (33, 24, [0, 0, 62])] {
            let pixel = base + y * row + x * 4
            let got = [Int(pixel[2]), Int(pixel[1]), Int(pixel[0])]
            #expect(zip(got, want).allSatisfy { abs($0 - $1) <= 2 }, "pixel (\(x), \(y)) is \(got), FFmpeg says \(want)")
        }
    }

    @Test("a picture before any parameter sets is refused")
    func needsParameterSets() throws {
        let units = try fixtureUnits()
        let decoder = RFBAppleVideoDecoder()
        let picture = units[0].filter { RFBAppleHEVC.nalType($0[0]) < 32 }
        #expect(throws: RFBError.self) { try decoder.decode([picture[0]]) }
    }
}
