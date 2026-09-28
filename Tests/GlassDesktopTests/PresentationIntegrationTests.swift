//
//  PresentationIntegrationTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/PresentationIntegrationTests.swift` on 2026-09-27.
//  Adapted: glassDT's `GlassDesktopCore` and `GlassDesktopUI` are one module here, `GlassDesktop`,
//  so the two imports became one. Every test and assertion is unchanged.
//

import Foundation
import ImageIO
import MetalKit
@testable import GlassDesktop
import Testing

@Test func keypadAndModifierScancodesRemainDistinct() throws {
    #expect(DesktopKeyboard.key(hidUsage: 40) == DesktopKey(0x1c))
    #expect(DesktopKeyboard.key(hidUsage: 88) == DesktopKey(0x1c, extended: true))
    #expect(DesktopKeyboard.key(hidUsage: 84) == DesktopKey(0x35, extended: true))
    #expect(DesktopKeyboard.key(hidUsage: 230) == DesktopKey(0x38, extended: true))
    var state = DesktopModifierState()
    let changes = state.update(shift: true, control: true, alternate: false, command: false)
    #expect(changes.count == 2)
    #expect(changes.allSatisfy { $0.1 })
    let repeats = state.update(shift: true, control: true, alternate: false, command: false)
    #expect(repeats.isEmpty)
    let released = state.update(shift: false, control: false, alternate: false, command: false)
    #expect(released.count == 2)
    #expect(released.allSatisfy { !$0.1 })
    let altGr = state.update(shift: false, control: false, alternate: true, command: false, changedUsage: 230, isDown: true)
    #expect(altGr.count == 1)
    #expect(altGr.first?.0 == DesktopKey(0x38, extended: true))
}

@Test func wallpaperMetadataIsBoundedBeforeDecode() throws {
    try DesktopWallpaperBounds.validate([kCGImagePropertyPixelWidth: 4096, kCGImagePropertyPixelHeight: 4096])
    for size in [(8192.0, 8192.0), (0, 1), (.infinity, 1), (4.5, 4)] {
        #expect(throws: RendererError.wallpaperTooLarge) {
            try DesktopWallpaperBounds.validate([kCGImagePropertyPixelWidth: size.0, kCGImagePropertyPixelHeight: size.1])
        }
    }
}

@Test @MainActor func inputCoalescesMotionWithoutReorderingKeyRelease() async {
    let recorder = InputRecorder()
    let input = DesktopInput(dispatch: { await recorder.receive($0) }, onError: { _ in Issue.record("Input unexpectedly failed") })
    input.send(.key(0x1e, false, true, false))
    await recorder.waitForStart()
    input.send(.move(.init(x: 1, y: 2)))
    input.send(.move(.init(x: 50, y: 60)))
    input.send(.key(0x1e, false, false, false))
    await recorder.resume()
    await input.flush()
    #expect(await recorder.events == ["down", "move:50,60", "up"])
    input.stop()
    await input.flush()
}

@Test @MainActor func focusReleaseDiscardsUnsentPressesAndFollowsInFlightInput() async {
    let recorder = InputRecorder()
    let input = DesktopInput(dispatch: { await recorder.receive($0) }, onError: { _ in Issue.record("Input unexpectedly failed") })
    input.send(.key(0x1e, false, true, false))
    await recorder.waitForStart()
    input.send(.key(0x30, false, true, false))
    input.send(.move(.init(x: 100, y: 100)))
    input.stop()
    input.send(.key(0x20, false, true, false))
    await recorder.resume()
    await input.flush()
    #expect(await recorder.events == ["down", "release"])
}

@Test @MainActor func metalPresentationPipelineCompilesWhenDeviceIsAvailable() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "GPU verification requires an available Metal device")
    _ = try DesktopMetalRenderer(device: device, pixelFormat: .bgra8Unorm, onError: { _ in })
}

private actor InputRecorder {
    private(set) var events: [String] = []
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var gate: CheckedContinuation<Void, Never>?
    private var started = false
    func waitForStart() async {
        if !started { await withCheckedContinuation { startWaiter = $0 } }
    }
    func resume() { gate?.resume(); gate = nil }
    func receive(_ event: DesktopInput.Event) async {
        switch event {
        case let .key(_, _, down, _): events.append(down ? "down" : "up")
        case let .move(point): events.append("move:\(point.x),\(point.y)")
        case .release: events.append("release")
        default: events.append("other")
        }
        if !started {
            started = true
            await withCheckedContinuation { continuation in
                gate = continuation
                startWaiter?.resume(); startWaiter = nil
            }
        }
    }
}
