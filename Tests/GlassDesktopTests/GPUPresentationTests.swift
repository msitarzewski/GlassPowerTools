//
//  GPUPresentationTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/GPUPresentationTests.swift` on 2026-09-27.
//  Adapted: the `GlassDesktopUI` import became `GlassDesktop`. The assertions are unchanged.
//  Since 2026-10-24 each draw goes through the renderer itself (`drawTexture`), with the wallpaper
//  loaded from a file as the app loads it; the tests had built a pipeline and uniforms of their own,
//  a copy of the renderer's that its own bindings could drift from unnoticed. Like the original,
//  each test requires a real Metal device and fails, rather than skips, without one.
//

import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
import GlassRDPTransport
@testable import GlassDesktop

@Suite("Metal presentation readback") @MainActor
struct GPUPresentationTests {
    // BGRA rows: black/red, green/blue. Distinct rows catch vertical inversion.
    private let pixels: [UInt8] = [0,0,0,255, 0,0,255,255, 0,255,0,255, 255,0,0,255]

    @Test func originalPreservesColorsAndOrientation() throws {
        let output = try render(mode: .original)
        #expect(output == pixels)
    }

    @Test func blackMaskOnlyChangesPresentationAlpha() throws {
        let original = pixels
        let output = try render(mode: .removeBlack)
        #expect(Array(output[0..<4]) == [0,0,0,0])
        #expect(Array(output[4...]) == Array(pixels[4...]))
        #expect(pixels == original)
    }

    @Test func matchingWallpaperRemovesAllMatchedPixels() throws {
        let output = try render(mode: .removeWallpaper, wallpaper: pixels)
        #expect(output.allSatisfy { $0 == 0 })
    }

    @Test func wallpaperDifferencePreservesForeground() throws {
        var reference = pixels
        reference.replaceSubrange(4..<8, with: [0,0,0,255])
        let output = try render(mode: .removeWallpaper, wallpaper: reference)
        #expect(Array(output[4..<8]) == [0,0,255,255])
        #expect(Array(output[0..<4]) == [0,0,0,0])
        #expect(output[11] == 0 && output[15] == 0)
    }

    @Test func aspectFitLeavesTransparentLetterboxes() throws {
        let output = try render(mode: .original, width: 4, height: 2)
        for row in 0..<2 {
            #expect(Array(output[(row * 16)..<(row * 16 + 4)]) == [0,0,0,0])
            #expect(Array(output[(row * 16 + 12)..<(row * 16 + 16)]) == [0,0,0,0])
            #expect(Array(output[(row * 16 + 4)..<(row * 16 + 12)]) == Array(pixels[(row * 8)..<(row * 8 + 8)]))
        }
    }

    private func render(mode: TransparencyMode, wallpaper: [UInt8]? = nil, width: Int = 2, height: Int = 2) throws -> [UInt8] {
        let device = try #require(MTLCreateSystemDefaultDevice(), "A real Metal device is required for shader readback")
        let renderer = try DesktopMetalRenderer(device: device, pixelFormat: .bgra8Unorm) { Issue.record("\($0)") }
        renderer.frame = try GlassRDPFrame(width: 2, height: 2, bytesPerRow: 8, pixels: Data(pixels), sequence: 1)
        renderer.settings.mode = mode
        if let wallpaper {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("gpu-wallpaper-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: file) }
            try writePNG(wallpaper, to: file)
            renderer.setWallpaper(file)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let output = try #require(device.makeTexture(descriptor: descriptor))
        var submitted: (any MTLCommandBuffer)?
        #expect(try renderer.drawTexture { submitted = $0; return output })
        let command = try #require(submitted)
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        #expect(command.status == .completed)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            output.getBytes(raw.baseAddress!, bytesPerRow: width * 4,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return bytes
    }

    /// A 2 × 2 BGRA picture as a PNG, the form a wallpaper reaches the renderer in.
    private func writePNG(_ bgra: [UInt8], to url: URL) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let provider = try #require(CGDataProvider(data: Data(bgra) as CFData))
        let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                         space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                                         decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
