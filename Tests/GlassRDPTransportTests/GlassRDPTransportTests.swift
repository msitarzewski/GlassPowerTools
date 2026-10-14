import CoreVideo
import Foundation
@testable import GlassRDPTransport
import RDPKit
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

/// B-F32: each graphics choice asks the engine for the matching capability profile — H.264 4:2:0 is
/// graphics pipeline 8.1, without H.264 is 8.0 — and Automatic stays the default.
@Test func graphicsModeChoosesTheEngineProfile() throws {
    let base = GlassRDPConfiguration(host: "server.example", username: "alice", password: "secret",
                                     width: 1280, height: 800)
    #expect(base.graphicsMode == .automatic)
    #expect(try GlassRDPSession.engineConfiguration(base).graphicsCapabilityProfile == .automatic)
    let expected: [GlassRDPGraphicsMode: RDPGraphicsCapabilityProfile] = [
        .automatic: .automatic, .h264: .avc420, .withoutH264: .legacy,
    ]
    for mode in GlassRDPGraphicsMode.allCases {
        var configuration = base
        configuration.graphicsMode = mode
        #expect(try GlassRDPSession.engineConfiguration(configuration).graphicsCapabilityProfile == expected[mode])
    }
}

/// The clipboard's log line names each message by type, in order, and marks a refusal — "it never
/// opened" and "it refused our list" are different fixes — and never carries the clipboard itself.
@Test func clipboardLogNamesEachMessageWithoutItsContent() {
    let messages = [
        RDPClipboardMessageSummary(typeName: "clipboard-capabilities", messageFlags: 0, dataLength: 16),
        RDPClipboardMessageSummary(typeName: "clipboard-monitor-ready", messageFlags: 0, dataLength: 0),
        RDPClipboardMessageSummary(typeName: "clipboard-format-list-response", messageFlags: 0x0002, dataLength: 0),
    ]
    #expect(GlassRDPSession.clipboardTypes(messages) == "capabilities,monitor-ready,format-list-response:fail")
    #expect(GlassRDPSession.clipboardTypes(nil) == "none")
    let many = Array(repeating: messages[1], count: 43)
    #expect(GlassRDPSession.clipboardTypes(many).hasSuffix("monitor-ready,+3"))
}
