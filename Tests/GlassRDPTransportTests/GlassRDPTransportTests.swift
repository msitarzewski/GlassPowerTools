import CoreVideo
import Foundation
@testable import GlassRDPTransport
import Testing

@Test func canonicalFrameCopiesPaddedRowsWithoutLosingPixels() throws {
    var source: CVPixelBuffer?
    let result = CVPixelBufferCreate(kCFAllocatorDefault, 3, 2, kCVPixelFormatType_32BGRA,
        [kCVPixelBufferBytesPerRowAlignmentKey: 64] as CFDictionary, &source)
    #expect(result == kCVReturnSuccess)
    let buffer = try #require(source)
    CVPixelBufferLockBaseAddress(buffer, [])
    let address = try #require(CVPixelBufferGetBaseAddress(buffer))
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for row in 0..<2 {
        for column in 0..<12 { address.storeBytes(of: UInt8(row * 12 + column), toByteOffset: row * stride + column, as: UInt8.self) }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    let frame = try FrameConverter().copy(buffer, receivedAt: Date(), decodedAt: Date(), hardware: false)
    #expect(frame.bytesPerRow == 12)
    #expect(frame.pixels == Data(0..<24))
    CVPixelBufferLockBaseAddress(buffer, [])
    address.storeBytes(of: UInt8(200), as: UInt8.self)
    CVPixelBufferUnlockBaseAddress(buffer, [])
    #expect(frame.pixels.first == 0)
}

@Test func malformedFrameDimensionsAndStridesAreRejected() throws {
    #expect(throws: GlassRDPError.invalidFrame) {
        try GlassRDPFrame(width: Int.max, height: 2, bytesPerRow: 4, pixels: Data(), sequence: 1)
    }
    #expect(throws: GlassRDPError.invalidFrame) {
        try GlassRDPFrame(width: 2, height: 2, bytesPerRow: 8, pixels: Data(count: 15), sequence: 1)
    }
}

@Test func sourceResizingRespectsServerAreaAndEvenWidth() {
    let capabilities = GlassRDPDisplayCapabilities(maximumMonitors: 1, maximumArea: 1920 * 1080)
    #expect(capabilities.supports(width: 1920, height: 1080))
    #expect(!capabilities.supports(width: 1921, height: 1000))
    #expect(!capabilities.supports(width: 1920, height: 1081))
    #expect(!capabilities.supports(width: -2, height: 1080))
    #expect(!GlassRDPDisplayCapabilities(maximumMonitors: 0, maximumArea: UInt64.max).supports(width: 800, height: 600))
}

@Test func invalidConnectNeverStartsTransport() async throws {
    let session = GlassRDPSession()
    await #expect(throws: GlassRDPError.invalidConfiguration) {
        try await session.connect(.init(host: " ", username: "user", password: "fixture"))
    }
    await #expect(throws: GlassRDPError.notConnected) {
        try await session.sendText("text")
    }
    await session.disconnect()
}

@Test func connectionFailureIsAnActualTerminalEvent() async throws {
    let session = GlassRDPSession()
    try await session.connect(.init(host: "127.0.0.1", port: 1, username: "fixture-user", password: "fixture"))
    var connected = false
    for await event in session.events {
        if case .state(.connected) = event { connected = true }
        if case let .state(.failed(message)) = event {
            #expect(!message.isEmpty)
            #expect(!connected)
            break
        }
    }
    await session.disconnect()
}
