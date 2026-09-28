//
//  GPUPresentationTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/GPUPresentationTests.swift` on 2026-09-27.
//  Adapted: the `GlassDesktopUI` import became `GlassDesktop`. The tests and assertions are
//  unchanged. The renderer's `Uniforms` has gained fields since (opacity, offset, key colour,
//  source rectangle), all defaulted to the whole, opaque texture, so the original initialiser call
//  still describes the same draw. Like the original, each test requires a real Metal device and
//  fails, rather than skips, without one.
//

import Foundation
import Metal
import Testing
@testable import GlassDesktop

@Suite("Metal presentation readback") @MainActor
struct GPUPresentationTests {
    // BGRA rows: black/red, green/blue. Distinct rows catch vertical inversion.
    private let pixels: [UInt8] = [0,0,0,255, 0,0,255,255, 0,255,0,255, 255,0,0,255]

    @Test func originalPreservesColorsAndOrientation() throws {
        let output = try render(mode: 0)
        #expect(output == pixels)
    }

    @Test func blackMaskOnlyChangesPresentationAlpha() throws {
        let original = pixels
        let output = try render(mode: 1)
        #expect(Array(output[0..<4]) == [0,0,0,0])
        #expect(Array(output[4...]) == Array(pixels[4...]))
        #expect(pixels == original)
    }

    @Test func matchingWallpaperRemovesAllMatchedPixels() throws {
        let output = try render(mode: 2, wallpaper: pixels)
        #expect(output.allSatisfy { $0 == 0 })
    }

    @Test func wallpaperDifferencePreservesForeground() throws {
        var reference = pixels
        reference.replaceSubrange(4..<8, with: [0,0,0,255])
        let output = try render(mode: 2, wallpaper: reference)
        #expect(Array(output[4..<8]) == [0,0,255,255])
        #expect(Array(output[0..<4]) == [0,0,0,0])
        #expect(output[11] == 0 && output[15] == 0)
    }

    @Test func aspectFitLeavesTransparentLetterboxes() throws {
        let output = try render(mode: 0, width: 4, height: 2)
        for row in 0..<2 {
            #expect(Array(output[(row * 16)..<(row * 16 + 4)]) == [0,0,0,0])
            #expect(Array(output[(row * 16 + 12)..<(row * 16 + 16)]) == [0,0,0,0])
            #expect(Array(output[(row * 16 + 4)..<(row * 16 + 12)]) == Array(pixels[(row * 8)..<(row * 8 + 8)]))
        }
    }

    private func render(mode: UInt32, wallpaper: [UInt8]? = nil, width: Int = 2, height: Int = 2) throws -> [UInt8] {
        let device = try #require(MTLCreateSystemDefaultDevice(), "A real Metal device is required for shader readback")
        let queue = try #require(device.makeCommandQueue())
        let library = try device.makeLibrary(source: DesktopMetalRenderer.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "desktopVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "desktopFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        func texture(width: Int, height: Int, usage: MTLTextureUsage) throws -> any MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = usage
            descriptor.storageMode = .shared
            return try #require(device.makeTexture(descriptor: descriptor))
        }
        let input = try texture(width: 2, height: 2, usage: .shaderRead)
        let reference = try texture(width: 2, height: 2, usage: .shaderRead)
        for (target, bytes) in [(input, pixels), (reference, wallpaper ?? pixels)] {
            bytes.withUnsafeBytes { raw in
                target.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
                               withBytes: raw.baseAddress!, bytesPerRow: 8)
            }
        }
        let output = try texture(width: width, height: height, usage: .renderTarget)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = .init(red: 0, green: 0, blue: 0, alpha: 0)
        let command = try #require(queue.makeCommandBuffer())
        let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
        let scale = min(Float(width) / 2, Float(height) / 2)
        var uniforms = DesktopMetalRenderer.Uniforms(contentScale: .init(2 * scale / Float(width), 2 * scale / Float(height)),
                                                     threshold: 0.04, feather: 0.02, mode: mode)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<DesktopMetalRenderer.Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DesktopMetalRenderer.Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(input, index: 0)
        encoder.setFragmentTexture(reference, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        command.commit()
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
}
