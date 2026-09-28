//
//  ColorKeyPresentationTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/ColorKeyPresentationTests.swift` on 2026-09-27.
//  Adapted: glassDT's `GlassDesktopCore` + `GlassDesktopUI` imports became `GlassDesktop`, which
//  holds both here. The tests and assertions are unchanged. Like the original, each renderer test
//  requires a real Metal device for shader readback and fails, rather than skips, without one.
//

import Foundation
import CoreGraphics
import ImageIO
import Metal
import Testing
import GlassRDPTransport
@testable import GlassDesktop

@Suite("Background color presentation") @MainActor
struct ColorKeyPresentationTests {
    // Magenta/black on the first row, white/green on the second.
    private let pixels: [UInt8] = [255,0,255,255, 0,0,0,255, 255,255,255,255, 0,255,0,255]

    @Test func desktopOpacityComposesWithMaskAndRestoresUnmodifiedPixels() throws {
        let (device, renderer) = try renderer()
        renderer.settings.opacity = 0.5
        let partial = try read(renderer, device: device)
        for (actual, source) in zip(partial, pixels) {
            #expect(abs(Int(actual) - Int((Double(source) * 0.5).rounded())) <= 1)
        }
        renderer.settings.mode = .removeColor
        let masked = try read(renderer, device: device)
        #expect(Array(masked[0..<4]) == [0,0,0,0])
        #expect(Array(masked[4...]) == Array(partial[4...]))
        renderer.settings.opacity = 0
        #expect(try read(renderer, device: device) == Array(repeating: 0, count: 16))
        renderer.settings.mode = .original
        renderer.settings.opacity = 1
        #expect(try read(renderer, device: device) == pixels)
        #expect(renderer.frame?.pixels == Data(pixels))
    }

    @Test func invalidOpacityCannotMakeTheDesktopUnrecoverable() throws {
        let (device, renderer) = try renderer()
        for value in [Double.nan, .infinity, -.infinity, 2] {
            renderer.settings.opacity = value
            #expect(try read(renderer, device: device) == pixels)
        }
        renderer.settings.opacity = -1
        #expect(try read(renderer, device: device) == Array(repeating: 0, count: 16))
        #expect(renderer.frame?.pixels == Data(pixels))
    }

    @Test func colorKeyRemovesChosenColorAndPreservesBlackWhiteAndForeground() throws {
        let (device, renderer) = try renderer()
        renderer.settings.mode = .removeColor
        var expected = pixels
        expected.replaceSubrange(0..<4, with: [0,0,0,0])
        #expect(try read(renderer, device: device) == expected)
        #expect(renderer.frame?.pixels == Data(pixels))

        renderer.settings.keyColor = [0, 1, 0]
        expected = pixels
        expected.replaceSubrange(12..<16, with: [0,0,0,0])
        #expect(try read(renderer, device: device) == expected)
        #expect(renderer.frame?.pixels == Data(pixels))
    }

    @Test func featheringMatchesCPUAlphaAndPremultipliesRGB() throws {
        let nearKey: [UInt8] = [255,31,255,255, 255,0,255,255, 0,0,0,255, 255,255,255,255]
        let (device, renderer) = try renderer(pixels: nearKey)
        renderer.settings.mode = .removeColor
        renderer.settings.threshold = 0.1
        renderer.settings.feather = 0.05
        let output = try read(renderer, device: device)
        let alpha = PresentationSettings.alpha(red: 1, green: 31.0 / 255, blue: 1, reference: nil,
            mode: .removeColor, threshold: 0.1, feather: 0.05)
        #expect(alpha > 0 && alpha < 1)
        for (channel, value) in zip(0..<4, [Float(255), 31, 255, 255]) {
            #expect(abs(Int(output[channel]) - Int((value * alpha).rounded())) <= 1)
        }
        #expect(Array(output[4..<8]) == [0,0,0,0])
        #expect(Array(output[8...]) == Array(nearKey[8...]))
    }

    @Test func originalRestoresPixelsAndColorKeyPreservesWallpaperReference() throws {
        let (device, renderer) = try renderer()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wallpaperURL = directory.appendingPathComponent("reference.png")
        try writeWallpaper(to: wallpaperURL)
        renderer.setWallpaper(wallpaperURL)
        renderer.settings.mode = .removeWallpaper
        #expect(try read(renderer, device: device) == Array(repeating: 0, count: 16))
        renderer.settings.mode = .removeColor
        renderer.settings.keyColor = [1, 0, 1]
        var expected = pixels
        expected.replaceSubrange(0..<4, with: [0,0,0,0])
        #expect(try read(renderer, device: device) == expected)
        renderer.settings.mode = .original
        #expect(try read(renderer, device: device) == pixels)
        renderer.settings.mode = .removeWallpaper
        #expect(try read(renderer, device: device) == Array(repeating: 0, count: 16))
        #expect(renderer.frame?.pixels == Data(pixels))
    }

    @Test func colorKeyDoesNotMaskCursor() throws {
        let (device, renderer) = try renderer()
        renderer.settings.mode = .removeColor
        renderer.cursor = try DesktopCursorDecoder.decode(width: 1, height: 1, hotSpotX: 0, hotSpotY: 0,
            bitsPerPixel: 32, xorMask: Data([255,0,255,255]), andMask: Data([0,0]))
        renderer.pointer = .init(x: 1, y: 0)
        var expected = pixels
        expected.replaceSubrange(0..<4, with: [0,0,0,0])
        expected.replaceSubrange(4..<8, with: [255,0,255,255])
        #expect(try read(renderer, device: device) == expected)
    }

    @Test func invalidMaskInputsStayFiniteAndAgreeWithGPU() throws {
        let (device, renderer) = try renderer()
        renderer.settings.mode = .removeColor
        renderer.settings.keyColor = [.nan, -.infinity, .infinity]
        renderer.settings.threshold = .nan
        renderer.settings.feather = .nan
        #expect(renderer.settings.keyColor == SIMD3<Float>(1, 0, 1))
        var expected = pixels
        expected.replaceSubrange(0..<4, with: [0,0,0,0])
        #expect(try read(renderer, device: device) == expected)
        #expect(PresentationSettings.alpha(red: 1, green: 0, blue: 1, reference: nil,
            mode: .removeColor, threshold: .nan, feather: .nan, keyColor: [.nan, -.infinity, .infinity]) == 0)
        renderer.settings.keyColor = [2, -1, 3]
        #expect(renderer.settings.keyColor == SIMD3<Float>(1, 0, 1))
        #expect(try read(renderer, device: device) == expected)
        #expect(PresentationSettings.alpha(red: .nan, green: 0, blue: 1, reference: nil,
            mode: .removeColor, threshold: 0.04, feather: 0.02) == 1)
    }

    @Test func colorMaskIsIndependentOfReferenceAndOriginalIsAlwaysOpaque() {
        let differentReference = SIMD3<Float>(0, 1, 0)
        #expect(PresentationSettings.alpha(red: 1, green: 0, blue: 1, reference: differentReference,
            mode: .removeColor, threshold: 0.04, feather: 0.02) == 0)
        #expect(PresentationSettings.alpha(red: 0, green: 0, blue: 0, reference: nil,
            mode: .removeColor, threshold: 0.04, feather: 0.02) == 1)
        #expect(PresentationSettings.alpha(red: 1, green: 0, blue: 1, reference: nil,
            mode: .original, threshold: 1, feather: 0) == 1)
        #expect(PresentationSettings.alpha(red: 1, green: 0, blue: 1, reference: nil,
            mode: .removeWallpaper, threshold: 1, feather: 0) == 1)
    }

    private func renderer(pixels: [UInt8]? = nil) throws -> (any MTLDevice, DesktopMetalRenderer) {
        let device = try #require(MTLCreateSystemDefaultDevice(), "A real Metal device is required for shader readback")
        let renderer = try DesktopMetalRenderer(device: device, pixelFormat: .bgra8Unorm) { Issue.record("\($0)") }
        renderer.frame = try GlassRDPFrame(width: 2, height: 2, bytesPerRow: 8,
            pixels: Data(pixels ?? self.pixels), sequence: 1)
        return (device, renderer)
    }

    private func read(_ renderer: DesktopMetalRenderer, device: any MTLDevice) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 2, height: 2, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let output = try #require(device.makeTexture(descriptor: descriptor))
        var submitted: (any MTLCommandBuffer)?
        #expect(try renderer.drawTexture { submitted = $0; return output })
        let command = try #require(submitted)
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        #expect(command.status == .completed)
        var bytes = [UInt8](repeating: 0, count: 16)
        output.getBytes(&bytes, bytesPerRow: 8, from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
        return bytes
    }

    private func writeWallpaper(to url: URL) throws {
        var rgba = pixels
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba.swapAt(index, index + 2)
        }
        let provider = try #require(CGDataProvider(data: Data(rgba) as CFData))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 8, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
