//
//  SpatialTextureTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/SpatialTextureTests.swift` on 2026-09-27.
//  Adapted: `GlassDesktopUI` is `GlassDesktop` here. Every test and assertion is unchanged. These
//  need a Metal device: `#require` fails, rather than skips, on a machine without one.
//

import Foundation
import Metal
import Testing
import GlassRDPTransport
@testable import GlassDesktop

@Suite("Spatial texture output") @MainActor
struct SpatialTextureTests {
    private let pixels: [UInt8] = [0,0,0,255, 0,0,255,255, 0,255,0,255, 255,0,0,255]

    @Test func sharedRendererPreservesRowsAndMaskInDynamicTexture() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try DesktopMetalRenderer(device: device, pixelFormat: .bgra8Unorm) { Issue.record("\($0)") }
        renderer.frame = try GlassRDPFrame(width: 2, height: 2, bytesPerRow: 8, pixels: Data(pixels), sequence: 1)
        #expect(try read(renderer, device: device) == pixels)
        renderer.settings.mode = .removeBlack
        var expected = pixels; expected[3] = 0
        #expect(try read(renderer, device: device) == expected)
        renderer.frame = nil
        #expect(try read(renderer, device: device) == Array(repeating: 0, count: 16))
    }

    @Test func spatialSRGBTexturePreservesEncodedMidtones() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try DesktopMetalRenderer(device: device, pixelFormat: .bgra8Unorm) { Issue.record("\($0)") }
        let midtones: [UInt8] = [40,60,80,255, 100,120,140,255, 160,180,200,255, 20,30,50,255]
        renderer.frame = try GlassRDPFrame(width: 2, height: 2, bytesPerRow: 8, pixels: Data(midtones), sequence: 1)
        #expect(try read(renderer, device: device, srgb: true) == midtones)
    }

    @Test func cursorUsesRemoteCoordinatesBeforeSurfaceCurvature() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try DesktopMetalRenderer(device: device, pixelFormat: .bgra8Unorm) { Issue.record("\($0)") }
        renderer.frame = try GlassRDPFrame(width: 2, height: 2, bytesPerRow: 8, pixels: Data(pixels), sequence: 1)
        renderer.cursor = try DesktopCursorDecoder.decode(width: 1, height: 1, hotSpotX: 0, hotSpotY: 0,
            bitsPerPixel: 32, xorMask: Data([255,255,255,255]), andMask: Data([0,0]))
        renderer.pointer = .init(x: 1, y: 1)
        var expected = pixels; expected.replaceSubrange(12..<16, with: [255,255,255,255])
        #expect(try read(renderer, device: device) == expected)
        renderer.pointer = .init(x: 0, y: 0)
        expected = pixels; expected.replaceSubrange(0..<4, with: [255,255,255,255])
        #expect(try read(renderer, device: device) == expected)
    }

    private func read(_ renderer: DesktopMetalRenderer, device: any MTLDevice, srgb: Bool = false) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: srgb ? .bgra8Unorm_srgb : .bgra8Unorm, width: 2, height: 2, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .pixelFormatView]; descriptor.storageMode = .shared
        let output = try #require(device.makeTexture(descriptor: descriptor))
        var submitted: (any MTLCommandBuffer)?
        try renderer.drawTexture { submitted = $0; return try #require(output.makeTextureView(pixelFormat: .bgra8Unorm)) }
        let command = try #require(submitted)
        command.waitUntilCompleted()
        #expect(command.status == .completed)
        var bytes = [UInt8](repeating: 0, count: 16)
        output.getBytes(&bytes, bytesPerRow: 8, from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
        return bytes
    }
}
