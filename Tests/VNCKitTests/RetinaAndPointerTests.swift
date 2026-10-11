import Foundation
import Testing
@testable import VNCKit

// W38: a Mac's Retina displays at 1x (`SetServerScaling` by the displays' density, `SetDisplay` for a
// display window's own connection) and its pointer (CursorPos and the cursor cache). Byte forms are
// remotex's (https://github.com/andrewtheguy/remotex — docs/apple-vnc-889.md and the tests in
// src/vnc_apple.rs, whose SetDisplay vectors are repeated here).

private func decide(_ planner: RFBStreamPlanner, at now: ContinuousClock.Instant = .now) -> [UInt8] {
    var out: [UInt8] = []
    _ = planner.decide(at: now) { out += $0 }
    return out
}

private func mac(_ quality: VNCQuality, retina: Bool = true, width: Int = 4480, height: Int = 1800) -> RFBStreamPlanner {
    let planner = RFBStreamPlanner()
    planner.setQuality(quality)
    planner.setDensityScaling(retina)
    planner.start(width: width, height: height, dialect: .apple)
    _ = planner.openingMessages()
    return planner
}

/// The notes' measured Mac as the client hands it to the planner: display 4 at 2x, display 1 at 1x.
private let mixedScreens = [VNCScreen(id: 4, x: 0, y: 0, width: 3200, height: 1800, flags: 1, isMain: true, density: 2),
                            VNCScreen(id: 1, x: 3200, y: 0, width: 1280, height: 800, flags: 0, isMain: false, density: 1)]
private let mixedDensities: [UInt32: Double] = [4: 2, 1: 1]

/// The client messages of a write as (type, bytes), and the requests among them.
private func requests(_ bytes: [UInt8]) -> [[UInt8]] { clientMessages(bytes).filter { $0.type == 3 }.map(\.bytes) }

@Suite("Choosing a Mac's display")
struct SetDisplayTests {
    @Test("SetDisplay is eight bytes: 0x0d, 1 to combine or 0 for one display, a reserved u16, the id")
    func bytes() {
        // remotex's `arming_display_selection_and_server_scaling_are_fixed_shapes`.
        #expect(RFBAppleDisplayLayout.setDisplayMessage(0x2b00_4501) == [0x0d, 0x00, 0x00, 0x00, 0x2b, 0x00, 0x45, 0x01])
        #expect(RFBAppleDisplayLayout.setDisplayMessage(nil) == [0x0d, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        #expect(RFBAppleDisplayLayout.setDisplayMessage(4) == [0x0d, 0, 0, 0, 0, 0, 0, 4])
        #expect(RFBAppleDisplayLayout.setServerScalingMessage(0.5) == [0x08, 0x00, 0x3f, 0xe0, 0, 0, 0, 0, 0, 0])
        #expect(RFBDisplaySelection.display(4).matches(4) && !RFBDisplaySelection.display(4).matches(nil))
        #expect(RFBDisplaySelection.allDisplays.matches(nil) && RFBDisplaySelection.allDisplays.id == nil)
    }

    @Test("asked once the Mac has sent a layout: SetDisplay, then the display's 1x, then the whole old picture")
    func askedAfterTheFirstLayoutWithItsScale() {
        let planner = mac(.best)
        planner.setDisplay(.display(4))
        // Before any layout: a pixel, enough to carry the layout, and no SetDisplay yet.
        let first = decide(planner)
        #expect(!first.contains(0x0d) || clientMessages(first).allSatisfy { $0.type != 13 })
        #expect(requests(first) == [RFBRectangle(x: 0, y: 0, width: 1, height: 1).updateRequest(incremental: false)])
        #expect(planner.holdingForDisplay)
        _ = planner.updateBegan()
        planner.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800, displays: mixedScreens, densities: mixedDensities)
        let messages = clientMessages(decide(planner))
        #expect(messages.map(\.type) == [13, 8, 3], "the display, its scale, then the picture")
        #expect(messages[0].bytes == RFBAppleDisplayLayout.setDisplayMessage(4))
        #expect(serverScales(messages.flatMap(\.bytes)) == [0.5], "display 4 is a 2x display: its 1x is half")
        #expect(messages[2].bytes == RFBRectangle(x: 0, y: 0, width: 4480, height: 1800).updateRequest(incremental: false),
                "the whole picture in the bounds the Mac has now, which it answers for the display it switches to")
        #expect(planner.awaitingDisplay && planner.holdingForDisplay)
        // The layout naming it confirms it; the framebuffer is that display's, at its 1x.
        _ = planner.updateBegan()
        planner.appleLayoutArrived(serverScale: 0.5, width: 1600, height: 900,
                                   displays: [VNCScreen(id: 4, x: 0, y: 0, width: 1600, height: 900, flags: 1, isMain: true, density: 2)],
                                   densities: mixedDensities, current: 4)
        #expect(!planner.awaitingDisplay && !planner.holdingForDisplay && planner.currentDisplay == 4)
        let after = decide(planner)
        #expect(serverScales(after).isEmpty && !clientMessages(after).contains { $0.type == 13 })
        #expect(requests(after).last == RFBRectangle(x: 0, y: 0, width: 1600, height: 900).updateRequest(incremental: false))
    }

    @Test("a display no layout names within ten seconds is refused, and so is a Mac that sends no layout")
    func refused() {
        let start = ContinuousClock.now
        let planner = mac(.best)
        planner.setDisplay(.display(1))
        #expect(!planner.displayRefused(at: start))
        #expect(planner.displayRefused(at: start + .seconds(11)), "no layout at all in ten seconds")

        let asked = mac(.best)
        asked.setDisplay(.display(1))
        asked.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800, displays: mixedScreens, densities: mixedDensities)
        var out: [UInt8] = []
        _ = asked.decide(at: start) { out += $0 }
        #expect(clientMessages(out).contains { $0.type == 13 })
        // A layout still sending all of them does not confirm it.
        asked.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800, displays: mixedScreens, densities: mixedDensities)
        _ = asked.decide(at: start + .seconds(5)) { _ in }
        #expect(!asked.displayRefused(at: start + .seconds(5)))
        _ = asked.decide(at: start + .seconds(10) + .milliseconds(1)) { _ in }
        #expect(asked.displayRefused(at: start + .seconds(10) + .milliseconds(1)))
        #expect(asked.holdingForDisplay, "still nothing but a pixel: the whole desktop is not what it is for")
    }

    @Test("a server that is not a Mac is never sent SetDisplay, and nothing is held for it")
    func notAMac() {
        let planner = RFBStreamPlanner()
        planner.setDisplay(.display(4))
        planner.start(width: 640, height: 480, dialect: .standard)
        _ = planner.openingMessages()
        let out = decide(planner)
        #expect(!clientMessages(out).contains { $0.type == 13 })
        #expect(!planner.holdingForDisplay)
        #expect(requests(out) == [RFBRectangle(x: 0, y: 0, width: 640, height: 480).updateRequest(incremental: false)])
    }
}

@Suite("Retina displays at 1x")
struct RetinaScaleTests {
    @Test("one over the density of the displays fetched, where they share one; mixed, or all 1x, is 1")
    func densityRule() {
        #expect(RFBStreamPlanner.densityFactor([2]) == 0.5)
        #expect(RFBStreamPlanner.densityFactor([2, 2]) == 0.5)
        #expect(RFBStreamPlanner.densityFactor([1]) == 1)
        #expect(RFBStreamPlanner.densityFactor([2, 1]) == 1, "Apple's viewer's mixed: a 1x beside a 2x")
        // remotex's `hidpi` case: HiDPI displays that differ among themselves are served uniformly.
        #expect(RFBStreamPlanner.densityFactor([1.5, 2]) == 0.5)
    }

    @Test("the density's factor times the quality level's: a 2x display at Best 0.5, Data Saver 0.375, Lowest 0.25")
    func factorTimesQuality() {
        let single = [VNCScreen(id: 9, x: 0, y: 0, width: 3024, height: 1964, flags: 1, isMain: true, density: 2)]
        for (quality, expected) in [(VNCQuality.best, 0.5), (.balanced, 0.5), (.dataSaver, 0.375), (.lowest, 0.25)] {
            let planner = mac(quality, width: 3024, height: 1964)
            planner.appleLayoutArrived(serverScale: 1, width: 3024, height: 1964, displays: single, densities: [9: 2])
            #expect(serverScales(decide(planner)) == [expected], "\(quality)")
        }
        // Native 2x: the level's alone, as before W38.
        let native = mac(.dataSaver, retina: false, width: 3024, height: 1964)
        native.appleLayoutArrived(serverScale: 1, width: 3024, height: 1964, displays: single, densities: [9: 2])
        #expect(serverScales(decide(native)) == [0.75])
        #expect(RFBStreamPlanner.combined(0.75, 0.5) == 0.375 && RFBStreamPlanner.combined(2, 1) == 1)
    }

    @Test("the displays fetched decide it: the 2x display alone at 1x, both together at their own pixels")
    func followsTheRegions() {
        let start = ContinuousClock.now
        let planner = mac(.best)
        planner.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800, displays: mixedScreens, densities: mixedDensities)
        var out: [UInt8] = []
        _ = planner.decide(at: start) { out += $0 }
        #expect(serverScales(out).isEmpty, "the whole picture is mixed: its own pixels, as Apple's viewer shows it")

        // Only the 2x display on screen (its 1x display has a connection of its own).
        planner.setRegions([RFBRectangle(x: 0, y: 0, width: 3200, height: 1800)])
        out = []
        let wake = planner.decide(at: start + .milliseconds(10)) { out += $0 }
        #expect(serverScales(out).isEmpty, "a change the windows cause waits a second to settle")
        #expect(wake.map { $0 <= start + .milliseconds(10) + .seconds(1) } == true)
        out = []
        _ = planner.decide(at: start + .milliseconds(1100)) { out += $0 }
        #expect(serverScales(out) == [0.5])
        planner.appleLayoutArrived(serverScale: 0.5, width: 2240, height: 900,
                                   displays: mixedScreens.map { $0.scaled(by: 0.5) }, densities: mixedDensities)
        #expect(planner.serverScaleInForce == 0.5)
        // At a scale, the whole picture is asked for: a Mac asked for the 2x display alone, its edge
        // on the seam, failed to read the scaled part back and sent nothing more (2026-10-11).
        out = []
        _ = planner.decide(at: start + .milliseconds(1200)) { out += $0 }
        #expect(requests(out) == [RFBRectangle(x: 0, y: 0, width: 2240, height: 900).updateRequest(incremental: false)])
        #expect(serverScales(out).isEmpty, "the factor stays the 2x display's")

        // Only the 1x display: its own pixels.
        planner.setRegions([RFBRectangle(x: 1600, y: 0, width: 640, height: 400)])
        out = []
        _ = planner.decide(at: start + .seconds(2)) { out += $0 }
        _ = planner.decide(at: start + .seconds(4)) { out += $0 }
        #expect(serverScales(out) == [1])

        // Nothing on screen: nothing to say, the factor stays.
        planner.appleLayoutArrived(serverScale: 1, width: 4480, height: 1800, displays: mixedScreens, densities: mixedDensities)
        planner.setRegions([])
        out = []
        _ = planner.decide(at: start + .seconds(6)) { out += $0 }
        _ = planner.decide(at: start + .seconds(8)) { out += $0 }
        #expect(serverScales(out).isEmpty)
    }

    /// remotex's notes: a Mac sends its pointer only to a viewer that armed `AutoFrameBufferUpdate`,
    /// and every layout drops the arming. The owner (2026-10-11): the pointer moved on the headset
    /// only when moved from there.
    @Test("a Mac is armed for the whole picture after each layout, never while a scale waits, and off with nothing on screen")
    func arming() {
        func armings(_ bytes: [UInt8]) -> [[UInt8]] { clientMessages(bytes).filter { $0.type == 9 }.map(\.bytes) }
        let start = ContinuousClock.now
        let planner = mac(.best, retina: false, width: 3024, height: 1964)
        var out: [UInt8] = []
        _ = planner.decide(at: start) { out += $0 }
        #expect(armings(out).isEmpty, "not before a layout")
        planner.appleLayoutArrived(serverScale: 1, width: 3024, height: 1964)
        out = []
        _ = planner.decide(at: start + .milliseconds(10)) { out += $0 }
        #expect(armings(out) == [[0x09, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0x0b, 0xd0, 0x07, 0xac]],
                "version 1, as fast as the Mac captures (0, as Apple's viewer arms), the whole 3024 × 1964 picture")
        out = []
        _ = planner.decide(at: start + .milliseconds(20)) { out += $0 }
        #expect(armings(out).isEmpty, "armed once")

        // A scale is asked: not armed again until the layout says the new size.
        planner.setServerScaleOverride(0.5)
        planner.appleLayoutArrived(serverScale: 1, width: 3024, height: 1964)
        out = []
        _ = planner.decide(at: start + .milliseconds(30)) { out += $0 }
        #expect(serverScales(out) == [0.5] && armings(out).isEmpty, "never armed for a picture about to shrink")
        planner.appleLayoutArrived(serverScale: 0.5, width: 1512, height: 982)
        out = []
        _ = planner.decide(at: start + .milliseconds(40)) { out += $0 }
        #expect(armings(out) == [RFBAppleDisplayLayout.autoFramebufferUpdateMessage(interval: 0, width: 1512, height: 982)])

        // Nothing on screen: pushes off.
        planner.setRegions([])
        out = []
        _ = planner.decide(at: start + .milliseconds(50)) { out += $0 }
        #expect(armings(out) == [RFBAppleDisplayLayout.autoFramebufferUpdateMessage(interval: .max, width: 1512, height: 982)])

        // Another server is never sent it.
        let standard = RFBStreamPlanner()
        standard.start(width: 640, height: 480)
        #expect(armings(decide(standard)).isEmpty)
    }

    @Test("turning Retina at 1x on or off is asked for at once")
    func choiceIsImmediate() {
        let planner = mac(.best, retina: false, width: 3024, height: 1964)
        let single = [VNCScreen(id: 9, x: 0, y: 0, width: 3024, height: 1964, flags: 1, isMain: true, density: 2)]
        planner.appleLayoutArrived(serverScale: 1, width: 3024, height: 1964, displays: single, densities: [9: 2])
        #expect(serverScales(decide(planner)).isEmpty)
        planner.setDensityScaling(true)
        #expect(serverScales(decide(planner)) == [0.5])
        planner.appleLayoutArrived(serverScale: 0.5, width: 1512, height: 982,
                                   displays: single.map { $0.scaled(by: 0.5) }, densities: [9: 2])
        planner.setDensityScaling(false)
        #expect(serverScales(decide(planner)) == [1])
    }

    @Test("a Mac's encodings include its pointer's two, unless it is not to be asked")
    func pointerEncodings() {
        let apple = RFBEncoding.setEncodingsValues(profile: .best, copyRect: true, dialect: .apple)
        #expect(apple.contains(1100) && apple.contains(1104))
        #expect(apple.contains(RFBEncoding.cursor.rawValue), "the standard Cursor stays: whichever the Mac sends is drawn")
        let notAsked = RFBEncoding.setEncodingsValues(profile: .best, copyRect: true, dialect: .apple, appleCursor: false)
        #expect(!notAsked.contains(1100) && !notAsked.contains(1104))
        let standard = RFBEncoding.setEncodingsValues(profile: .best, copyRect: true)
        #expect(!standard.contains(1100) && !standard.contains(1104), "only a Mac is asked")
    }
}

// MARK: - The pointer

/// A shape as a Mac stores it: BGRX pixels, then a separate alpha plane, as one zlib stream.
private func storedShape(width: Int, height: Int, alpha: (Int) -> UInt8) -> (raw: [UInt8], deflated: [UInt8]) {
    var raw: [UInt8] = []
    for pixel in 0..<(width * height) { raw += [UInt8(10 + pixel % 200), 20, 30, 0xFF] }
    for pixel in 0..<(width * height) { raw.append(alpha(pixel)) }
    return (raw, TightTests.Deflater().compress(raw))
}

/// A cursor-cache rectangle: hotspot and size in the header, then the id, the length and the bytes.
private func cursorRectangle(id: UInt32, hotSpot: (Int, Int), size: (Int, Int), deflated: [UInt8]) -> [UInt8] {
    MacLayout.rectangleHeader(hotSpot.0, hotSpot.1, size.0, size.1, .appleCursorImage)
        + id.bigEndianBytes + UInt32(deflated.count).bigEndianBytes + deflated
}

@Suite("A Mac's pointer")
struct ApplePointerTests {
    @Test("a stored shape is BGRX then its own alpha plane, measured in points; a select brings it back")
    func storeAndSelect() throws {
        let cache = RFBAppleCursorCache()
        let shape = storedShape(width: 2, height: 2) { [0x00, 0x40, 0x80, 0xFF][$0] }
        guard case .shape(let image) = cache.accept(id: 1000, hotSpotX: 1, hotSpotY: 1, width: 2, height: 2, deflated: shape.deflated) else {
            Issue.record("a store is a shape"); return
        }
        #expect(image.width == 2 && image.height == 2 && image.hotSpotX == 1 && image.hotSpotY == 1)
        #expect(image.isPointSized, "the same pixmap whatever the display's density")
        // The fourth byte of each pixel is not the alpha: the plane after them is.
        #expect(Array(image.bgra) == [10, 20, 30, 0x00, 11, 20, 30, 0x40, 12, 20, 30, 0x80, 13, 20, 30, 0xFF])
        #expect(Array(image.mask) == [0, 1, 1, 1])
        #expect(cache.accept(id: 1000, hotSpotX: 0, hotSpotY: 0, width: 0, height: 0, deflated: []) == .shape(image),
                "a select carries no pixels and zeroed geometry")
        #expect(cache.accept(id: 1001, hotSpotX: 0, hotSpotY: 0, width: 0, height: 0, deflated: []) == .unknown,
                "an id never stored leaves the pointer as it is")
    }

    @Test("each store is its own zlib stream, and a bad one costs only itself")
    func independentStores() {
        let cache = RFBAppleCursorCache()
        let first = storedShape(width: 2, height: 2) { _ in 0xFF }
        let second = storedShape(width: 3, height: 1) { _ in 0x80 }
        #expect(cache.accept(id: 1, hotSpotX: 0, hotSpotY: 0, width: 2, height: 2, deflated: first.deflated) != .unknown)
        guard case .shape = cache.accept(id: 2, hotSpotX: 0, hotSpotY: 0, width: 3, height: 1, deflated: second.deflated) else {
            Issue.record("a second store starts a new stream"); return
        }
        if case .unreadable = cache.accept(id: 3, hotSpotX: 0, hotSpotY: 0, width: 2, height: 2, deflated: [1, 2, 3]) {} else {
            Issue.record("garbage is unreadable")
        }
        if case .unreadable = cache.accept(id: 4, hotSpotX: 0, hotSpotY: 0, width: 257, height: 1, deflated: first.deflated) {} else {
            Issue.record("past remotex's 256-pixel edge")
        }
        if case .unreadable = cache.accept(id: 5, hotSpotX: 0, hotSpotY: 0, width: 3, height: 3, deflated: first.deflated) {} else {
            Issue.record("a size its bytes do not fill")
        }
        #expect(cache.accept(id: 3, hotSpotX: 0, hotSpotY: 0, width: 0, height: 0, deflated: []) == .unknown, "nothing was stored")
        guard case .shape = cache.accept(id: 1, hotSpotX: 0, hotSpotY: 0, width: 0, height: 0, deflated: []) else {
            Issue.record("the first is still there"); return
        }
    }

    @Test("CursorPos is in the Mac's own pixels until its answers say the picture's; neither, over and over, is not used")
    func positionSpace() {
        let start = ContinuousClock.now
        var space = RFBCursorPositionSpace()
        // At a scale of 0.5, (2000, 600) in the Mac's pixels is (1000, 300) in the picture.
        #expect(space.map(x: 2000, y: 600, scale: 0.5, width: 2240, height: 900, at: start)! == (1000, 300))
        #expect(space.map(x: 5000, y: 600, scale: 0.5, width: 2240, height: 900, at: start) == nil, "not in this picture")
        // The Mac answers a move to picture (100, 100) — Mac (200, 200) — with (100, 100): the picture's.
        space.pointerSent(picture: (100, 100), wire: (200, 200), at: start)
        #expect(space.map(x: 100, y: 100, scale: 0.5, width: 2240, height: 900, at: start + .milliseconds(100))! == (100, 100))
        #expect(space.space == .scaled)
        // Answers at the Mac's own pixels put it back.
        space.pointerSent(picture: (300, 300), wire: (600, 600), at: start + .seconds(5))
        #expect(space.map(x: 600, y: 600, scale: 0.5, width: 2240, height: 900, at: start + .seconds(5))! == (300, 300))
        #expect(space.space == .unscaled)
        // At a scale of 1 both agree, and the space is not told apart.
        var plain = RFBCursorPositionSpace()
        plain.pointerSent(picture: (40, 40), wire: (40, 40), at: start)
        #expect(plain.map(x: 40, y: 40, scale: 1, width: 100, height: 100, at: start)! == (40, 40))
        #expect(plain.space == .unknown)
        // Reports that match no move, again and again — another space — stop being used.
        var other = RFBCursorPositionSpace()
        for step in 0..<RFBCursorPositionSpace.missesBeforeDistrust {
            let at = start + .milliseconds(100 * step)
            other.pointerSent(picture: (10, 10), wire: (10, 10), at: at)
            _ = other.map(x: 900, y: 10, scale: 1, width: 1280, height: 800, at: at)
        }
        #expect(other.space == .untrusted)
        #expect(other.map(x: 10, y: 10, scale: 1, width: 1280, height: 800, at: start + .seconds(30)) == nil)
    }

    @Test("end to end: CursorPos and the cache's shapes reach the app, the stream in step after both")
    func endToEnd() async throws {
        final class Seen: @unchecked Sendable {
            private let lock = NSLock()
            private var shapes: [VNCCursorImage?] = [], positions: [String] = [], messages: [VNCCursorMessage] = [], frames = 0
            var cursor: [VNCCursorImage?] { lock.withLock { shapes } }
            var at: [String] { lock.withLock { positions } }
            var said: [VNCCursorMessage] { lock.withLock { messages } }
            var pictures: Int { lock.withLock { frames } }
            func callbacks() -> VNCClientCallbacks {
                var callbacks = VNCClientCallbacks()
                callbacks.cursor = { value in self.lock.withLock { self.shapes.append(value) } }
                callbacks.cursorPosition = { x, y in self.lock.withLock { self.positions.append("\(x),\(y)") } }
                callbacks.cursorMessage = { value in self.lock.withLock { self.messages.append(value) } }
                callbacks.frame = { _, _, _ in self.lock.withLock { self.frames += 1 } }
                return callbacks
            }
        }
        let shape = storedShape(width: 2, height: 2) { _ in 0xFF }
        var stream = MacLayout.greeting(width: 64, height: 64)
        stream += [0, 0, 0, 4]
        stream += MacLayout.rectangleHeader(30, 20, 0, 0, .appleCursorPosition)
        stream += cursorRectangle(id: 7, hotSpot: (1, 0), size: (2, 2), deflated: shape.deflated)
        stream += cursorRectangle(id: 7, hotSpot: (0, 0), size: (0, 0), deflated: [])
        stream += MacLayout.rectangleHeader(63, 63, 1, 1, .raw) + [1, 2, 3, 0]
        let seen = Seen(), sink = MemoryByteSink()
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", password: ""), callbacks: seen.callbacks(),
                               source: MemoryByteSource(stream), sink: sink)
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }
        #expect(seen.at == ["30,20"])
        #expect(seen.cursor.count == 2 && seen.cursor.allSatisfy { $0?.isPointSized == true && $0?.width == 2 })
        #expect(seen.said == [.applePosition(x: 30, y: 20),
                              .appleStored(id: 7, width: 2, height: 2, hotSpotX: 1, hotSpotY: 0,
                                           compressedBytes: shape.deflated.count, decoded: true),
                              .appleSelected(id: 7, known: true)])
        #expect(seen.pictures == 1, "the pixel after them decoded")
        #expect(client.receivedAppleCursor)
        #expect(client.lastAppleEncoding == nil, "the pixel after them shows they were read in step")
        let encodings = try #require(clientMessages(Array(await sink.written.dropFirst(13 + 1))).first { $0.type == 2 }).bytes
        let listed = stride(from: 4, to: encodings.count, by: 4).map { Int32(bitPattern: UInt32(encodings[$0]) << 24
            | UInt32(encodings[$0 + 1]) << 16 | UInt32(encodings[$0 + 2]) << 8 | UInt32(encodings[$0 + 3])) }
        #expect(listed.contains(1100) && listed.contains(1104))
    }

    @Test("a Mac's standard Cursor is measured in points too; an empty one hides the pointer")
    func richCursorOnAMac() async throws {
        final class Shapes: @unchecked Sendable {
            private let lock = NSLock(); private var list: [VNCCursorImage?] = []
            var all: [VNCCursorImage?] { lock.withLock { list } }
            func add(_ value: VNCCursorImage?) { lock.withLock { list.append(value) } }
        }
        var stream = MacLayout.greeting(width: 8, height: 8)
        stream += [0, 0, 0, 2]
        stream += MacLayout.rectangleHeader(0, 0, 1, 1, .cursor) + [9, 9, 9, 0] + [0x80]
        stream += MacLayout.rectangleHeader(0, 0, 0, 0, .cursor)
        let shapes = Shapes()
        var callbacks = VNCClientCallbacks()
        callbacks.cursor = { shapes.add($0) }
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", password: ""), callbacks: callbacks,
                               source: MemoryByteSource(stream), sink: MemoryByteSink())
        await #expect(throws: RFBError.connectionClosed) { try await client.run() }
        #expect(shapes.all.count == 2 && shapes.all[0]?.isPointSized == true && shapes.all[1] == nil)
    }
}

@Suite("A display window's own connection, end to end", .serialized)
struct OneDisplayClientTests {
    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var sizes: [String] = []
        var frames: [String] { lock.withLock { sizes } }
        func callbacks() -> VNCClientCallbacks {
            var callbacks = VNCClientCallbacks()
            callbacks.frame = { width, height, _ in self.lock.withLock { self.sizes.append("\(width)x\(height)") } }
            return callbacks
        }
    }

    @Test("asks for its display, hands on no picture until a layout names it, and then that display's 1x")
    func oneDisplayAtOneX() async throws {
        let source = MemoryByteSource(MacLayout.greeting(width: 4480, height: 1800), holdsOpen: true)
        let sink = MemoryByteSink()
        let seen = Seen()
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", password: "", display: 4),
                               callbacks: seen.callbacks(), source: source, sink: sink, close: { await source.close() })
        client.setQuality(.best)
        client.setDensityScaling(true)
        let run = Task { try? await client.run() }
        defer { client.cancel(); run.cancel() }
        try await waitUntil { client.isReady }
        // The first layout, every display; then a pixel of the whole desktop, which is not handed on.
        await source.append(MacLayout.update(MacLayout.mixedPayload))
        await source.append([0, 0, 0, 1] + MacLayout.rectangleHeader(0, 0, 1, 1, .raw) + [1, 2, 3, 0])
        try await waitUntil { client.awaitingDisplay }
        try await Task.sleep(for: .milliseconds(50))
        #expect(seen.frames.isEmpty, "the whole desktop is not what this connection is for")
        let written = clientMessages(Array(await sink.written.dropFirst(13 + 1)))
        let display = try #require(written.firstIndex { $0.type == 13 })
        #expect(written[display].bytes == [13, 0, 0, 0, 0, 0, 0, 4])
        #expect(serverScales(written.flatMap(\.bytes)) == [0.5])
        #expect(written.firstIndex { $0.type == 8 }.map { $0 > display } == true, "the scale after the display it is for")
        // The Mac switches: display 4 alone, at half its pixels.
        let selected = [MacDisplay(id: 4, density: 2, scale: 0.5, logical: (0, 0, 900, 1600), backing: (0, 0, 900, 1600), flags: 1),
                        MacDisplay(id: 1, density: 1, scale: 0.5, logical: (0, 1600, 800, 2880), backing: (0, 1600, 400, 2240))]
        await source.append(MacLayout.update(MacLayout.payload(points: (2880, 900), framebuffer: (1600, 900), current: 4,
                                                               displays: selected)))
        await source.append([0, 0, 0, 1] + MacLayout.rectangleHeader(1599, 899, 1, 1, .raw) + [1, 2, 3, 0])
        try await waitUntil { !seen.frames.isEmpty }
        #expect(seen.frames.allSatisfy { $0 == "1600x900" }, "only the display's own pixels are handed on")
        #expect(client.currentDisplay == 4 && client.serverScale == 0.5)
        // Its pointer: the display's own pixels, divided by the factor, as on every Mac connection.
        _ = await sink.drain()
        try await client.sendPointer(buttonMask: 0, x: 100, y: 50)
        #expect(clientMessages(await sink.drain()).filter { $0.type == 5 }.map(\.bytes) == [[5, 0, 0, 200, 0, 100]])
        await source.close()
        _ = await run.value
    }
}
