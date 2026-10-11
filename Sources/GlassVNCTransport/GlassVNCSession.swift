import Foundation
import GlassRDPTransport
import OSLog
import VNCKit

public struct GlassVNCConfiguration: Sendable, Equatable {
    public var host: String
    public var port: UInt16
    /// Empty selects password-only VNC Authentication; a user name selects Apple Remote Desktop
    /// authentication when the server offers it.
    public var username: String
    public var password: String
    public var clipboardEnabled: Bool

    public init(host: String, port: UInt16 = 5900, username: String = "", password: String, clipboardEnabled: Bool = false) {
        self.host = host; self.port = port; self.username = username; self.password = password
        self.clipboardEnabled = clipboardEnabled
    }
}

/// A VNC/RFB session behind the same transport surface as `GlassRDPSession`. Keyboard input arrives
/// as RDP set-1 scancodes from the native surfaces and is translated to X11 keysyms here.
public actor GlassVNCSession: GlassDesktopTransport {
    private static let logger = Logger(subsystem: "app.glassdt.vnc", category: "session")
    /// For this run of the app (W30): Macs not to ask for their display layout again.
    static let layoutRefusals = HostSet()
    /// For this run of the app (W36): Macs not to ask to scale their picture again.
    static let scalingRefusals = HostSet()
    public nonisolated let frames: AsyncStream<GlassRDPFrame>
    public nonisolated let events: AsyncStream<GlassRDPEvent>
    private let frameContinuation: AsyncStream<GlassRDPFrame>.Continuation
    private let eventContinuation: AsyncStream<GlassRDPEvent>.Continuation
    private var worker: Task<Void, Never>?
    private var client: VNCClient?
    private var activeID: UUID?
    private var stopRequested = false
    private var pressedKeysyms: Set<UInt32> = []
    private var buttonMask: UInt8 = 0
    private var pointer = (x: 0, y: 0)
    private var capsLockOn: Bool?
    private var scrollRemainder = (vertical: 0, horizontal: 0)
    /// Kept across connections, and handed to each new client before it runs, so a session opens
    /// at the level and over the area its windows asked for.
    private var quality = GlassDesktopStreamQuality.automatic
    private var regions: [GlassRemoteRegion]?
    private let sequence = FrameSequence()
    private let delivered = FrameDelivery()
    private let makeClient: @Sendable (VNCConfiguration, VNCClientCallbacks) throws -> VNCClient

    public init() {
        self.init(makeClient: { try VNCClient(configuration: $0, callbacks: $1) })
    }

    init(makeClient: @escaping @Sendable (VNCConfiguration, VNCClientCallbacks) throws -> VNCClient) {
        (frames, frameContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (events, eventContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(128))
        self.makeClient = makeClient
    }

    deinit {
        client?.cancel()
        frameContinuation.finish()
        eventContinuation.finish()
    }

    public func connect(_ configuration: GlassVNCConfiguration) throws {
        guard worker == nil else { throw GlassRDPError.alreadyConnected }
        let host = configuration.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, configuration.port > 0 else { throw GlassRDPError.invalidConfiguration }
        let id = UUID()
        Self.logger.notice("event=connect attempt=\(id.uuidString, privacy: .public) account=\(configuration.username.isEmpty ? "password-only" : "user", privacy: .public)")
        let eventSink = eventContinuation, frameSink = frameContinuation, sequence = sequence, delivered = delivered
        delivered.reset()
        var callbacks = VNCClientCallbacks()
        let layoutKey = "\(host.lowercased()):\(configuration.port)"
        let asksForLayout = !Self.layoutRefusals.contains(layoutKey)
        let asksToScale = !Self.scalingRefusals.contains(layoutKey)
        let apple = FrameDelivery()
        callbacks.connected = { info in
            if info.isAppleScreenSharing { apple.note() }
            eventSink.yield(.state(.connected))
        }
        callbacks.desktopResizeSupported = {
            eventSink.yield(.displayCapabilities(.init(maximumMonitors: 1, maximumArea: UInt64(RFBLimits.maximumPixels))))
        }
        callbacks.frame = { width, height, pixels in
            do {
                frameSink.yield(try GlassRDPFrame(width: width, height: height, bytesPerRow: width * 4, pixels: pixels,
                                                  sequence: sequence.next(), usesHardwareAcceleration: false))
                delivered.note()
            } catch {
                // The framebuffer bounds already match the frame's, so this cannot happen for a
                // well formed update. Report it rather than dropping the frame silently.
                eventSink.yield(.state(.failed(GlassRDPError.invalidFrame.localizedDescription)))
            }
        }
        callbacks.cursor = { image in
            guard let image else { eventSink.yield(.cursor(.hidden)); return }
            if let converted = Self.cursorImage(image) { eventSink.yield(.cursor(.image(converted))) }
        }
        callbacks.cutText = { eventSink.yield(.clipboard(GlassClipboardContent(text: $0))) }
        callbacks.screens = { eventSink.yield(.screens(Self.remoteScreens($0))) }
        callbacks.statistics = { eventSink.yield(.linkStatistics(Self.statistics($0))) }
        let client = try makeClient(VNCConfiguration(host: host, port: configuration.port, username: configuration.username,
                                                     password: configuration.password, sharedSession: true,
                                                     clipboardEnabled: configuration.clipboardEnabled,
                                                     requestsAppleDisplayLayout: asksForLayout,
                                                     allowsServerScaling: asksToScale), callbacks)
        client.setQuality(Self.quality(quality))
        client.setRequestedRegions(Self.rectangles(regions))
        self.client = client
        activeID = id
        stopRequested = false
        resetInputState()
        eventSink.yield(.state(.connecting))
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            var failure: String?
            do { try await client.run() } catch let error as RFBError {
                // Signing out of the remote session closes the transport. Once a desktop has been
                // shown, that is a normal ending rather than a failure to report.
                let normalEnd = error == .cancelled || (error == .connectionClosed && delivered.any)
                failure = normalEnd ? nil : error.localizedDescription
                // A Mac that ended the session while a scale it was asked for was unanswered is
                // not asked again while the app runs; Reconnect shows its picture at its own size (W36).
                if error != .cancelled, asksToScale, client.awaitingServerScaling {
                    Self.scalingRefusals.insert(layoutKey)
                    Self.logger.error("event=server-scale-refused")
                    if let message = failure {
                        failure = message + " Reconnect connects without asking this Mac to send a smaller picture."
                    }
                }
                // A Mac that broke the protocol after sending its displays — a form known only from
                // others' measurements — is not asked for them again while the app runs, so
                // Reconnect works, with its displays as one picture (W30). A violation before any
                // display metadata arrived cannot be a misreading of it, and changes nothing.
                else if case .protocolViolation = error, asksForLayout, apple.any, client.receivedAppleDisplayMetadata {
                    Self.layoutRefusals.insert(layoutKey)
                    Self.logger.error("event=apple-display-layout-refused")
                    failure = (failure ?? "") + " Reconnect connects without asking this Mac where its displays are."
                }
            } catch { failure = error.localizedDescription }
            await self?.finished(id: id, error: failure)
        }
    }

    public func disconnect() async {
        Self.logger.notice("event=disconnect-requested")
        stopRequested = true
        await releaseInputs()
        client?.cancel()
        await worker?.value
    }

    private func finished(id: UUID, error: String?) {
        guard activeID == id else { return }
        let cancelled = stopRequested
        Self.logger.notice("event=finished attempt=\(id.uuidString, privacy: .public) cancelled=\(cancelled) failed=\(error != nil)")
        worker = nil; client = nil; activeID = nil
        resetInputState()
        if !cancelled, let error { eventContinuation.yield(.state(.failed(error))) }
        else { eventContinuation.yield(.state(.disconnected)) }
    }

    private func resetInputState() {
        pressedKeysyms.removeAll(); buttonMask = 0; pointer = (0, 0); capsLockOn = nil; scrollRemainder = (0, 0)
    }

    private func readyClient() throws -> VNCClient {
        guard let client, client.isReady else { throw GlassRDPError.notConnected }
        return client
    }

    // MARK: Input

    public func keyboard(scancode: UInt16, extended: Bool, isDown: Bool, isRepeat: Bool) async throws {
        let client = try readyClient()
        guard let keysym = RFBKeysym.keysym(scancode: scancode, extended: extended) else {
            throw GlassRDPError.unsupported("This key has no VNC equivalent.")
        }
        if isDown { pressedKeysyms.insert(keysym) } else { pressedKeysyms.remove(keysym) }
        try await client.sendKey(keysym: keysym, down: isDown)
    }

    public func sendText(_ text: String) async throws {
        let client = try readyClient()
        for scalar in text.unicodeScalars {
            guard let keysym = RFBKeysym.keysym(for: scalar) else { continue }
            try await client.sendKey(keysym: keysym, down: true)
            try await client.sendKey(keysym: keysym, down: false)
        }
    }

    public func movePointer(x: Int, y: Int) async throws {
        let client = try readyClient()
        pointer = (x, y)
        try await client.sendPointer(buttonMask: buttonMask, x: x, y: y)
    }

    public func pointerButton(button: GlassRDPPointerButton, isDown: Bool, x: Int, y: Int) async throws {
        let client = try readyClient()
        let bit: UInt8 = switch button {
        case .left: 1 << 0
        case .middle: 1 << 1
        case .right: 1 << 2
        case .back: 1 << 7
        case .forward: throw GlassRDPError.unsupported("The forward pointer button is not available over VNC.")
        }
        if isDown { buttonMask |= bit } else { buttonMask &= ~bit }
        pointer = (x, y)
        try await client.sendPointer(buttonMask: buttonMask, x: x, y: y)
    }

    /// Wheel rotation arrives in RDP units (120 per notch); each notch becomes one press/release of
    /// buttons 4/5 (vertical) or 7/6 (horizontal). Fractional precise-scrolling remainders accumulate.
    public func scroll(vertical: Int, horizontal: Int, x: Int, y: Int) async throws {
        let client = try readyClient()
        pointer = (x, y)
        scrollRemainder.vertical += vertical
        scrollRemainder.horizontal += horizontal
        let verticalNotches = scrollRemainder.vertical / 120, horizontalNotches = scrollRemainder.horizontal / 120
        scrollRemainder.vertical -= verticalNotches * 120
        scrollRemainder.horizontal -= horizontalNotches * 120
        for _ in 0..<min(abs(verticalNotches), 32) {
            let bit: UInt8 = verticalNotches > 0 ? 1 << 3 : 1 << 4
            try await client.sendPointer(buttonMask: buttonMask | bit, x: x, y: y)
            try await client.sendPointer(buttonMask: buttonMask, x: x, y: y)
        }
        for _ in 0..<min(abs(horizontalNotches), 32) {
            let bit: UInt8 = horizontalNotches > 0 ? 1 << 6 : 1 << 5
            try await client.sendPointer(buttonMask: buttonMask | bit, x: x, y: y)
            try await client.sendPointer(buttonMask: buttonMask, x: x, y: y)
        }
    }

    public func releaseInputs() async {
        guard let client, client.isReady else { pressedKeysyms.removeAll(); buttonMask = 0; return }
        let keys = pressedKeysyms, hadButtons = buttonMask != 0, point = pointer
        pressedKeysyms.removeAll(); buttonMask = 0
        for keysym in keys { try? await client.sendKey(keysym: keysym, down: false) }
        if hadButtons { try? await client.sendPointer(buttonMask: 0, x: point.x, y: point.y) }
    }

    /// RFB has no lock-state synchronisation; a change in the local Caps Lock state is forwarded
    /// as one Caps Lock press so the remote toggle follows the local keyboard.
    public func synchronize(capsLock: Bool, numLock: Bool, scrollLock: Bool) async throws {
        let client = try readyClient()
        if let known = capsLockOn, known == capsLock { return }
        if capsLockOn != nil {
            try await client.sendKey(keysym: RFBKeysym.capsLock, down: true)
            try await client.sendKey(keysym: RFBKeysym.capsLock, down: false)
        }
        capsLockOn = capsLock
    }

    public func resize(width: Int, height: Int, desktopScale: Int) async throws {
        let client = try readyClient()
        do { try await client.requestDesktopSize(width: width, height: height) }
        catch let error as RFBError { throw GlassRDPError.unsupported(error.localizedDescription) }
    }

    /// VNC's clipboard is text: the copy's text goes, its other forms do not.
    public func sendClipboard(_ content: GlassClipboardContent) async throws {
        guard let text = content.text else { return }
        let client = try readyClient()
        do { try await client.sendCutText(text) }
        catch let error as RFBError { throw GlassRDPError.unsupported(error.localizedDescription) }
    }

    // MARK: What the link carries

    // Both are `async` on purpose: the protocol's defaults are, and in an async context Swift
    // prefers an async overload, so a synchronous method here lost to the default that does
    // nothing (found by `qualityAndRegionsSetBeforeConnectingShapeTheOpeningMessages`).

    /// Only these parts of the framebuffer are asked for (`VNCClient.setRequestedRegions`).
    public func setVisibleRegions(_ regions: [GlassRemoteRegion]?) async {
        guard regions != self.regions else { return }
        self.regions = regions
        client?.setRequestedRegions(Self.rectangles(regions))
    }

    public func setStreamQuality(_ quality: GlassDesktopStreamQuality) async {
        guard quality != self.quality else { return }
        self.quality = quality
        Self.logger.notice("event=quality requested=\(quality.rawValue, privacy: .public)")
        client?.setQuality(Self.quality(quality))
    }

    static func quality(_ quality: GlassDesktopStreamQuality) -> VNCQuality {
        switch quality {
        case .automatic: .automatic
        case .best: .best
        case .balanced: .balanced
        case .dataSaver: .dataSaver
        case .lowest: .lowest
        }
    }

    static func level(_ quality: VNCQuality) -> GlassDesktopStreamQuality {
        switch quality {
        case .automatic: .automatic
        case .best: .best
        case .balanced: .balanced
        case .dataSaver: .dataSaver
        case .lowest: .lowest
        }
    }

    static func rectangles(_ regions: [GlassRemoteRegion]?) -> [RFBRectangle]? {
        regions?.compactMap {
            guard $0.x >= 0, $0.y >= 0, $0.width > 0, $0.height > 0,
                  $0.x <= RFBLimits.maximumDimension, $0.y <= RFBLimits.maximumDimension else { return nil }
            return RFBRectangle(x: $0.x, y: $0.y, width: min($0.width, RFBLimits.maximumDimension),
                                height: min($0.height, RFBLimits.maximumDimension))
        }
    }

    static func statistics(_ value: VNCLinkStatistics) -> GlassDesktopLinkStatistics {
        GlassDesktopLinkStatistics(bytesPerSecond: value.bytesPerSecond, updatesPerSecond: value.updatesPerSecond,
                                   quality: level(value.quality), level: level(value.profile.level),
                                   colourDepth: value.profile.colourDepth.rawValue, encoding: value.encoding?.name,
                                   measuredKilobitsPerSecond: value.measuredKilobitsPerSecond,
                                   regionLimited: value.regionLimited, paused: value.paused,
                                   serverScale: value.serverScale)
    }

    /// The displays a server publishes, as the desktop shows them. ExtendedDesktopSize does not mark
    /// a primary screen, so the one at the framebuffer origin is treated as it; Apple's layout marks
    /// its main display. Public for the live probe, which prints what the app would be given.
    public static func remoteScreens(_ screens: [VNCScreen]) -> [GlassRemoteScreen] {
        screens.map {
            GlassRemoteScreen(id: $0.id, x: $0.x, y: $0.y, width: $0.width, height: $0.height,
                              isPrimary: $0.isMain ?? ($0.x == 0 && $0.y == 0))
        }
    }

    // MARK: Cursor conversion

    /// Repacks a top-down VNC cursor into the MS-RDPBCGR 32-bit pointer layout the shared cursor
    /// decoder consumes: bottom-up XOR rows with alpha, bottom-up 1-bpp AND rows (1 = transparent),
    /// each AND row padded to two bytes.
    static func cursorImage(_ image: VNCCursorImage) -> GlassRDPCursorImage? {
        guard (1...384).contains(image.width), (1...384).contains(image.height),
              image.bgra.count == image.width * image.height * 4, image.mask.count == image.width * image.height else { return nil }
        let hotSpotX = min(max(0, image.hotSpotX), image.width - 1), hotSpotY = min(max(0, image.hotSpotY), image.height - 1)
        let xorStride = image.width * 4, andStride = (((image.width + 7) / 8) + 1) & ~1
        var xor = Data(count: xorStride * image.height), and = Data(count: andStride * image.height)
        for y in 0..<image.height {
            let targetRow = image.height - 1 - y
            for x in 0..<image.width {
                let pixel = y * image.width + x, source = pixel * 4, target = targetRow * xorStride + x * 4
                xor[target] = image.bgra[source]; xor[target + 1] = image.bgra[source + 1]
                xor[target + 2] = image.bgra[source + 2]; xor[target + 3] = image.mask[pixel] != 0 ? 255 : 0
                if image.mask[pixel] == 0 { and[targetRow * andStride + x / 8] |= UInt8(0x80) >> UInt8(x % 8) }
            }
        }
        return GlassRDPCursorImage(width: image.width, height: image.height, hotSpotX: hotSpotX, hotSpotY: hotSpotY,
                                   xorBitsPerPixel: 32, xorMask: xor, andMask: and, paletteEntries: nil)
    }
}

/// Hosts whose Mac ended a session in a protocol error once asked for its display layout.
final class HostSet: @unchecked Sendable {
    private let lock = NSLock()
    private var values: Set<String> = []
    func contains(_ value: String) -> Bool { lock.withLock { values.contains(value) } }
    func insert(_ value: String) { lock.withLock { _ = values.insert(value) } }
}

private final class FrameDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var any: Bool { lock.withLock { value } }
    func note() { lock.withLock { value = true } }
    func reset() { lock.withLock { value = false } }
}

private final class FrameSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func next() -> UInt64 { lock.withLock { value &+= 1; return value } }
}
