import CoreGraphics
import SwiftUI
import Testing
@testable import GlassLayers
@testable import GlassTerminal
@testable import GlassTerminalEmulator

@MainActor
@Suite("The Coding Agent look, drawn")
struct TerminalAgentBackdropRenderTests {
    @Test("the agent's mark is drawn in the middle, in its colour")
    func markIsDrawn() throws {
        let view = TerminalAgentBackdrop(agent: .claudeCode, color: Color(red: 0.85, green: 0.47, blue: 0.34),
                                         working: false, still: true, frameInterval: 1.0 / 30, intensity: 1)
            .frame(width: 400, height: 300)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let brightest = try Self.brightestRedInTheMiddle(of: try #require(renderer.cgImage))
        #expect(brightest > 0.12, "the middle is dark: \(brightest)")
    }

    @Test("in a window's backdrop, scrim and ceiling included, the mark still shows")
    func markInTheBackdrop() throws {
        let style = TerminalLookStyle.resolved(TerminalLookPreset.agent.applied(to: GlassWindowOverrides()))
        let view = TerminalBackdropView(style: style, theme: .default, findAgent: { .claudeCode })
            .frame(width: 400, height: 300)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let brightest = try Self.brightestRedInTheMiddle(of: try #require(renderer.cgImage))
        #expect(brightest > 0.2, "the middle is too dark to see the mark: \(brightest)")
    }

    /// The highest sRGB red, 0 to 1, over every fourth pixel of the middle (x 120..<280, y 80..<220) of a
    /// 400 × 300 drawing. Core Graphics rather than AppKit's bitmap, so the suite runs on every platform.
    /// The drawing is 8-bit sRGB, so these are its own values. AppKit's `colorAt` called them
    /// calibrated RGB and `usingColorSpace(.sRGB)` converted them again: higher, 0.313 for the
    /// backdrop's 0.243 and 0.729 for the mark's 0.667 (2026-11-06).
    private static func brightestRedInTheMiddle(of image: CGImage) throws -> Double {
        let width = image.width, height = image.height
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn, "no sRGB context for a \(width) × \(height) image")
        try #require(width >= 280 && height >= 220, "the drawing is \(width) × \(height)")
        var brightest = 0
        for x in stride(from: 120, to: 280, by: 4) {
            for y in stride(from: 80, to: 220, by: 4) {
                brightest = max(brightest, Int(pixels[(y * width + x) * 4]))
            }
        }
        return Double(brightest) / 255
    }
}
