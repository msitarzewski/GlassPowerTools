//
//  DesktopPresentationTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/DesktopPresentationTests.swift` on 2026-09-27.
//  Adapted: the `GlassDesktopUI` import became `GlassDesktop`, which holds glassDT's desktop core
//  and UI here. The tests (audio queue budget, PCM16 conversion, cursor decoding) and their
//  assertions are unchanged.
//

import AVFoundation
import Foundation
@testable import GlassDesktop
import GlassRDPTransport
import Testing

@Test func audioQueueRejectsOvershootAndStaleCompletions() throws {
    var queue = DesktopAudioQueueBudget()
    queue.reset(maximumFrames: 100)
    let oldReservation = queue.reserve(90)
    let oldGeneration = try #require(oldReservation)
    let overshoot = queue.reserve(11), enormous = queue.reserve(Int.max)
    #expect(overshoot == nil)
    #expect(enormous == nil)
    #expect(queue.queuedFrames == 90)
    queue.reset(maximumFrames: 50)
    let newReservation = queue.reserve(40)
    let current = try #require(newReservation)
    queue.complete(90, generation: oldGeneration)
    #expect(queue.queuedFrames == 40)
    queue.complete(40, generation: current)
    #expect(queue.queuedFrames == 0)
}

@Test func PCM16LittleEndianConvertsToPlanarFloat() throws {
    let data = Data([0, 128, 255, 127, 255, 255, 0, 0])
    let buffer = try DesktopPCM16.buffer(sampleRate: 48_000, channels: 2, data: data)
    let samples = try #require(buffer.floatChannelData)
    #expect(buffer.frameLength == 2)
    #expect(samples[0][0] == -1)
    #expect(samples[1][0] == Float(32767) / 32768)
    #expect(samples[0][1] == -1 / Float(32768))
    #expect(samples[1][1] == 0)
    #expect(throws: DesktopAudioError.invalidData) {
        try DesktopPCM16.validate(sampleRate: 48_000, channels: 2, data: Data([1]))
    }
    #expect(throws: DesktopAudioError.invalidFormat) {
        try DesktopPCM16.validate(sampleRate: .infinity, channels: 2, data: data)
    }
}

@Test func colorCursorUsesBottomUpAlignedRows() throws {
    let cursor = try DesktopCursorDecoder.decode(width: 1, height: 2, hotSpotX: 0, hotSpotY: 1,
        bitsPerPixel: 24, xorMask: Data([255, 0, 0, 0, 0, 0, 255, 0]), andMask: Data([0, 0, 0, 0]))
    #expect(cursor.pixels == Data([255, 0, 0, 255, 0, 0, 255, 255]))
    #expect(!cursor.requiresDesktopComposition)
}

@Test func monochromeCursorPreservesAllFourRasterOperations() throws {
    let cursor = try DesktopCursorDecoder.decode(width: 4, height: 1, hotSpotX: 0, hotSpotY: 0,
        bitsPerPixel: 1, xorMask: Data([0b01010000, 0]), andMask: Data([0b00110000, 0]))
    #expect(cursor.requiresDesktopComposition)
    let desktop = try GlassRDPFrame(width: 4, height: 1, bytesPerRow: 16,
        pixels: Data(repeating: 0x35, count: 16), sequence: 1)
    let pixels = try cursor.compositedPixels(over: desktop, pointerX: 0, pointerY: 0)
    #expect(pixels == Data([0,0,0,255, 255,255,255,255, 0,0,0,0, 0xCA,0xCA,0xCA,255]))
    #expect(desktop.pixels == Data(repeating: 0x35, count: 16))
}

@Test func alphaCursorIgnoresAndMaskAndPremultiplies() throws {
    let cursor = try DesktopCursorDecoder.decode(width: 1, height: 1, hotSpotX: 0, hotSpotY: 0,
        bitsPerPixel: 32, xorMask: Data([0, 0, 255, 128]), andMask: Data([255,255]))
    #expect(cursor.pixels == Data([128,0,0,128]))
    #expect(!cursor.requiresDesktopComposition)
}

@Test func cursorRejectsMissingMasksAndUnavailablePalette() throws {
    #expect(throws: DesktopCursorError.invalidMasks) {
        try DesktopCursorDecoder.decode(width: 2, height: 2, hotSpotX: 0, hotSpotY: 0,
            bitsPerPixel: 24, xorMask: Data(), andMask: Data())
    }
    #expect(throws: DesktopCursorError.invalidMasks) {
        try DesktopCursorDecoder.decode(width: 2, height: 2, hotSpotX: 0, hotSpotY: 0,
            bitsPerPixel: 8, xorMask: Data(), andMask: Data())
    }
}

@Test func cursorDecodesRGB565AndIndexedRGBPalette() throws {
    let packed = try DesktopCursorDecoder.decode(width: 2, height: 1, hotSpotX: 0, hotSpotY: 0,
        bitsPerPixel: 16, xorMask: Data([0, 248, 224, 7]), andMask: Data([0, 0]))
    #expect(packed.pixels == Data([255, 0, 0, 255, 0, 255, 0, 255]))
    var palette = Data(repeating: 0, count: 256 * 3)
    palette[3] = 25; palette[4] = 50; palette[5] = 75
    palette[6] = 100; palette[7] = 125; palette[8] = 150
    for depth in [4, 8] {
        let bitmap = try DesktopCursorDecoder.decode(width: 2, height: 1, hotSpotX: 0, hotSpotY: 0,
            bitsPerPixel: depth, xorMask: depth == 4 ? Data([0x12, 0]) : Data([1, 2]),
            andMask: Data([0, 0]), paletteEntries: palette)
        #expect(bitmap.pixels == Data([25, 50, 75, 255, 100, 125, 150, 255]))
    }
}
