import Foundation
import OSLog

public struct VNCConfiguration: Sendable {
    public var host: String
    public var port: UInt16
    public var username: String
    public var password: String
    public var sharedSession: Bool
    public var clipboardEnabled: Bool
    /// Ask Apple's server for its display layout (encoding 1105, `RFBAppleDisplayLayout`). Off
    /// after a Mac ended a session in a protocol error once asked for it (`GlassVNCSession`).
    public var requestsAppleDisplayLayout: Bool

    public init(host: String, port: UInt16 = 5900, username: String = "", password: String,
                sharedSession: Bool = true, clipboardEnabled: Bool = false, requestsAppleDisplayLayout: Bool = true) {
        self.host = host; self.port = port; self.username = username; self.password = password
        self.sharedSession = sharedSession; self.clipboardEnabled = clipboardEnabled
        self.requestsAppleDisplayLayout = requestsAppleDisplayLayout
    }
}

/// Callbacks run on the client's connection task; keep them short and hand work off.
public struct VNCClientCallbacks: Sendable {
    public var connected: @Sendable (VNCServerInfo) -> Void = { _ in }
    public var frame: @Sendable (_ width: Int, _ height: Int, _ bgra: Data) -> Void = { _, _, _ in }
    public var cursor: @Sendable (VNCCursorImage?) -> Void = { _ in }
    public var cutText: @Sendable (String) -> Void = { _ in }
    public var desktopResizeSupported: @Sendable () -> Void = {}
    /// The displays inside the framebuffer, whenever the server publishes or updates the list.
    public var screens: @Sendable ([VNCScreen]) -> Void = { _ in }
    public var bell: @Sendable () -> Void = {}
    /// What the link is doing, once a second while the session runs.
    public var statistics: @Sendable (VNCLinkStatistics) -> Void = { _ in }
    /// Every framebuffer update as it arrived: its rectangles, encodings and bytes.
    public var update: @Sendable (VNCUpdateSummary) -> Void = { _ in }
    public init() {}
}

/// One RFB client connection. `run` performs the handshake, authentication and update loop and
/// returns when the server closes the connection, or throws with a specific failure. Input
/// methods may be called concurrently once `connected` has fired.
public final class VNCClient: Sendable {
    private static let logger = Logger(subsystem: "app.glassdt.vnc", category: "client")
    private let configuration: VNCConfiguration
    private let callbacks: VNCClientCallbacks
    private let source: RFBCountingByteSource
    private let sink: any RFBByteSink
    private let closeAction: @Sendable () async -> Void
    private let state = ClientState()
    /// What to ask the server for, and when (`VNCStreaming.swift`).
    private let planner = RFBStreamPlanner()
    /// SetPixelFormat, SetEncodings and FramebufferUpdateRequest, in the order the planner decided
    /// them, written by one task. Input goes straight to the sink: its order against these does
    /// not matter, theirs against each other does.
    private let outbox: AsyncStream<[UInt8]>
    private let outboxContinuation: AsyncStream<[UInt8]>.Continuation

    public convenience init(configuration: VNCConfiguration, callbacks: VNCClientCallbacks) throws {
        let channel = try RFBNetworkChannel(host: configuration.host, port: configuration.port)
        self.init(configuration: configuration, callbacks: callbacks, source: channel, sink: channel,
                  open: { try await channel.open() }, close: { await channel.close() })
    }

    public init(configuration: VNCConfiguration, callbacks: VNCClientCallbacks, source: any RFBByteSource,
                sink: any RFBByteSink, open: @escaping @Sendable () async throws -> Void = {},
                close: @escaping @Sendable () async -> Void = {}) {
        self.configuration = configuration
        self.callbacks = callbacks
        self.source = RFBCountingByteSource(source)
        self.sink = sink
        self.closeAction = close
        (outbox, outboxContinuation) = AsyncStream.makeStream(of: [UInt8].self)
        state.setOpen(open)
    }

    public var isReady: Bool { state.ready }

    /// How to trade picture for bytes. May be set before `run` (the session opens at that level)
    /// or at any time after; a change of colour depth waits until the server holds no request.
    public func setQuality(_ quality: VNCQuality) {
        planner.setQuality(quality)
        pump()
    }

    /// The parts of the framebuffer on screen, in framebuffer coordinates: nil for all of it, empty
    /// for none. Updates are asked for only there — the bounding rectangle of what is listed — so a
    /// display with no window costs nothing. An area newly listed is asked for in full at once.
    public func setRequestedRegions(_ regions: [RFBRectangle]?) {
        planner.setRegions(regions)
        pump()
    }

    /// What the link is doing now.
    public var statistics: VNCLinkStatistics {
        planner.statistics(totalBytes: source.totalBytes, at: .now)
    }

    /// Bytes received so far, every message included.
    public var totalBytesReceived: Int { source.totalBytes }

    public func cancel() {
        state.cancel()
        let close = closeAction
        Task { await close() }
    }

    // MARK: Session

    public func run() async throws {
        var streaming: [Task<Void, Never>] = []
        /// Stops the timers, then lets the writer finish what was decided before the connection
        /// closes under it — after the close, a dead connection's writes fail at once.
        func finish() async {
            state.setReady(false)
            outboxContinuation.finish()
            for task in streaming.dropFirst() { task.cancel() }
            state.cancelWakes()
            await closeAction()
            await streaming.first?.value
        }
        do {
            try await state.open()
            try checkCancelled()
            let info = try await handshake()
            planner.start(width: info.width, height: info.height, dialect: RFBServerDialect(version: info.serverVersion),
                          appleDisplayLayout: configuration.requestsAppleDisplayLayout)
            let opening = planner.openingMessages()
            try await sink.write(opening.pixelFormat)
            try await sink.write(opening.encodings)
            // The first request is on the wire before the session says it is ready; later ones go
            // through the outbox, in the order the planner decides them.
            var first: [UInt8] = []
            _ = planner.decide(at: .now) { first += $0 }
            if !first.isEmpty { try await sink.write(first) }
            let framebuffer = try RFBFramebuffer(width: info.width, height: info.height)
            state.setFramebufferSize(width: info.width, height: info.height)
            let (sink, outbox) = (sink, outbox)
            streaming.append(Task {
                for await message in outbox {
                    do { try await sink.write(message) } catch { return }
                }
            })
            streaming.append(Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    self.callbacks.statistics(self.statistics)
                }
            })
            state.setReady(true)
            callbacks.connected(info)
            try await updateLoop(framebuffer: framebuffer)
        } catch {
            await finish()
            if state.isCancelled { throw RFBError.cancelled }
            throw error
        }
        await finish()
    }

    /// Sends what the planner decides now, and looks again when it is waiting on time.
    private func pump() {
        let wake = planner.decide(at: .now) { [outboxContinuation] bytes in outboxContinuation.yield(bytes) }
        guard let wake else { return }
        state.addWake(Task { [weak self] in
            try? await Task.sleep(until: wake, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.pump()
        })
    }

    private func checkCancelled() throws {
        if state.isCancelled { throw RFBError.cancelled }
    }

    private func handshake() async throws -> VNCServerInfo {
        let serverVersion = try RFBProtocolVersion.parse(try await source.read(12))
        let version = serverVersion.negotiated
        try await sink.write(version.wireBytes)
        let securityType: RFBSecurityType
        if version.minor == 3 {
            let selected = try await source.u32()
            if selected == 0 { throw RFBError.connectionFailed("The server refused the connection: \(try await readReason())") }
            guard let type = RFBSecurityType(rawValue: UInt8(clamping: selected)), selected <= 2 else {
                throw RFBError.unsupported("The server requires security type \(selected), which is not supported.")
            }
            securityType = type
        } else {
            let count = Int(try await source.u8())
            if count == 0 { throw RFBError.connectionFailed("The server refused the connection: \(try await readReason())") }
            let offered = try await source.read(count)
            securityType = try choose(offered)
            try await sink.write([securityType.rawValue])
        }
        try await authenticate(securityType, version: version)
        try await sink.write([configuration.sharedSession ? 1 : 0])
        let initBytes = try await source.read(24)
        var reader = ByteReader(initBytes)
        let width = Int(try reader.u16()), height = Int(try reader.u16())
        let pixelFormat = try RFBPixelFormat.parse(&reader)
        let nameLength = Int(try reader.u32())
        guard nameLength <= RFBLimits.maximumNameBytes else { throw RFBError.resourceLimit("The server name is too long.") }
        try RFBFramebuffer.validate(width: width, height: height)
        let name = String(decoding: try await source.read(nameLength), as: UTF8.self)
        Self.logger.notice("event=connected version=\(serverVersion.major).\(serverVersion.minor) security=\(securityType.rawValue) width=\(width) height=\(height)")
        return VNCServerInfo(name: name, width: width, height: height, serverVersion: serverVersion,
                             negotiatedVersion: version, securityType: securityType, serverPixelFormat: pixelFormat)
    }

    private func choose(_ offered: [UInt8]) throws -> RFBSecurityType {
        let hasUsername = !configuration.username.isEmpty
        let hasPassword = !configuration.password.isEmpty
        if offered.contains(RFBSecurityType.appleRemoteDesktop.rawValue), hasUsername, hasPassword { return .appleRemoteDesktop }
        if offered.contains(RFBSecurityType.vncAuthentication.rawValue), hasPassword { return .vncAuthentication }
        if offered.contains(RFBSecurityType.none.rawValue) { return .none }
        if offered.contains(RFBSecurityType.appleRemoteDesktop.rawValue) {
            throw RFBError.authenticationFailed("This server needs a Mac user name and password (Apple Remote Desktop authentication).")
        }
        if offered.contains(RFBSecurityType.vncAuthentication.rawValue) {
            throw RFBError.authenticationFailed("This server needs a VNC password.")
        }
        let list = offered.map(String.init).joined(separator: ", ")
        throw RFBError.unsupported("The server only offers unsupported security types (\(list)). Enable VNC password or user-account access on the host.")
    }

    private func authenticate(_ type: RFBSecurityType, version: RFBProtocolVersion) async throws {
        switch type {
        case .none:
            if version.minor >= 8 { try await readSecurityResult() }
        case .vncAuthentication:
            let challenge = try await source.read(16)
            try await sink.write(try RFBSecurity.vncAuthenticationResponse(challenge: challenge, password: configuration.password))
            try await readSecurityResult()
        case .appleRemoteDesktop:
            let generator = try await source.u16(), keyLength = try await source.u16()
            guard (RFBLimits.minimumDiffieHellmanKeyBytes...RFBLimits.maximumDiffieHellmanKeyBytes).contains(Int(keyLength)) else {
                throw RFBError.protocolViolation("The Apple Remote Desktop key length \(keyLength) is invalid.")
            }
            let body = try await source.read(Int(keyLength) * 2)
            let challenge = try RFBSecurity.AppleRemoteDesktopChallenge.parse(generator: generator, keyLength: keyLength, body: body)
            let response = try RFBSecurity.appleRemoteDesktopResponse(challenge, username: configuration.username,
                                                                      password: configuration.password)
            try await sink.write(response.wireBytes)
            try await readSecurityResult()
        case .invalid:
            throw RFBError.protocolViolation("The server selected an invalid security type.")
        }
    }

    private func readSecurityResult() async throws {
        let result = try await source.u32()
        guard result == 0 else {
            var reason = "The server rejected the credentials."
            if let detail = try? await readReason(), !detail.isEmpty { reason = detail }
            throw RFBError.authenticationFailed(reason)
        }
    }

    private func readReason() async throws -> String {
        let length = Int(try await source.u32())
        guard length <= RFBLimits.maximumReasonBytes else { throw RFBError.resourceLimit("The server reason is too long.") }
        return String(decoding: try await source.read(length), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Client messages

    public func sendKey(keysym: UInt32, down: Bool) async throws {
        try requireReady()
        try await sink.write([4, down ? 1 : 0, 0, 0] + keysym.bigEndianBytes)
    }

    public func sendPointer(buttonMask: UInt8, x: Int, y: Int) async throws {
        try requireReady()
        let size = state.framebufferSize
        let clampedX = min(max(0, x), max(0, size.width - 1)), clampedY = min(max(0, y), max(0, size.height - 1))
        try await sink.write([5, buttonMask] + UInt16(clampedX).bigEndianBytes + UInt16(clampedY).bigEndianBytes)
    }

    /// RFC 6143 §7.5.6: ClientCutText carries ISO 8859-1 text; characters outside it are dropped.
    public func sendCutText(_ text: String) async throws {
        try requireReady()
        let latin1 = text.unicodeScalars.compactMap { $0.value <= 0xFF ? UInt8($0.value) : nil }
        guard latin1.count <= RFBLimits.maximumCutTextBytes else { throw RFBError.resourceLimit("The clipboard text is too large to send.") }
        try await sink.write([6, 0, 0, 0] + UInt32(latin1.count).bigEndianBytes + latin1)
    }

    /// SetDesktopSize (ExtendedDesktopSize extension); the server answers with a rectangle whose
    /// status reports success or the reason for refusal.
    public func requestDesktopSize(width: Int, height: Int) async throws {
        try requireReady()
        guard state.desktopResizeSupported else { throw RFBError.unsupported("The server has not offered desktop resizing.") }
        try RFBFramebuffer.validate(width: width, height: height)
        var message: [UInt8] = [251, 0] + UInt16(width).bigEndianBytes + UInt16(height).bigEndianBytes + [1, 0]
        message += UInt32(0).bigEndianBytes + UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes
        message += UInt16(width).bigEndianBytes + UInt16(height).bigEndianBytes + UInt32(0).bigEndianBytes
        try await sink.write(message)
    }

    /// SetDesktopSize with a layout of several screens, each placed inside the new framebuffer —
    /// how a client asks a server that supports it (TigerVNC's Xvnc does) for more than one display.
    public func requestDesktopLayout(width: Int, height: Int, screens: [VNCScreen]) async throws {
        try requireReady()
        guard state.desktopResizeSupported else { throw RFBError.unsupported("The server has not offered desktop resizing.") }
        try RFBFramebuffer.validate(width: width, height: height)
        guard (1...255).contains(screens.count),
              screens.allSatisfy({ $0.validated(inFramebufferWidth: width, height: height) != nil }) else {
            throw RFBError.invalidConfiguration("Every screen must lie inside the requested desktop.")
        }
        var message: [UInt8] = [251, 0] + UInt16(width).bigEndianBytes + UInt16(height).bigEndianBytes
        message += [UInt8(screens.count), 0]
        for screen in screens {
            message += screen.id.bigEndianBytes + UInt16(screen.x).bigEndianBytes + UInt16(screen.y).bigEndianBytes
            message += UInt16(screen.width).bigEndianBytes + UInt16(screen.height).bigEndianBytes + screen.flags.bigEndianBytes
        }
        try await sink.write(message)
    }

    private func requireReady() throws {
        guard state.ready, !state.isCancelled else { throw RFBError.connectionClosed }
    }

    // MARK: Server messages

    private func updateLoop(framebuffer: RFBFramebuffer) async throws {
        let decoder = RFBRectangleDecoder()
        while true {
            try checkCancelled()
            planner.waitingForMessage(at: .now)
            pump()
            let type = try await source.u8()
            planner.messageArrived()
            switch type {
            case 0:
                let startBytes = source.totalBytes - 1
                _ = try await source.u8()
                let count = Int(try await source.u16())
                // The format this update's pixels are in: whatever was in effect when the server
                // wrote it, which a change of colour depth never overlaps (`RFBStreamPlanner`).
                let pixels = planner.updateBegan()
                // **Ask for the next update now, not after decoding this one.** The request used to
                // follow the decode and the frame's hand-off, so every frame waited a full round
                // trip plus its own decode, and a slow link crawled (2026-09-30). One request is
                // kept queued at the server while this one decodes, unless the quality level caps
                // the rate, when it waits out the interval instead. (RFB 7.5.3 allows several.)
                pump()
                let started = ContinuousClock.now
                var changed = false
                var encodingBytes: [Int32: Int] = [:]
                var rectangles: [RFBRectangle] = [], encodings: [RFBEncoding] = []
                rectangles: for _ in 0..<count {
                    let before = source.totalBytes
                    let header = try await source.read(12)
                    var reader = ByteReader(header)
                    let rect = RFBRectangle(x: Int(try reader.u16()), y: Int(try reader.u16()),
                                            width: Int(try reader.u16()), height: Int(try reader.u16()))
                    let encodingValue = try reader.s32()
                    guard let encoding = RFBEncoding(rawValue: encodingValue) else {
                        throw RFBError.protocolViolation("The server used encoding \(encodingValue), which was not requested.")
                    }
                    defer {
                        rectangles.append(rect); encodings.append(encoding)
                        encodingBytes[encoding.rawValue, default: 0] += source.totalBytes - before
                    }
                    switch encoding {
                    case .lastRect:
                        break rectangles
                    case .cursor:
                        if rect.isEmpty { callbacks.cursor(nil) } else {
                            let image = try await RFBRectangleDecoder.decodeCursor(rect, from: source, pixels: pixels)
                            callbacks.cursor(image)
                        }
                    case .desktopSize:
                        try framebuffer.resize(width: rect.width, height: rect.height)
                        state.setFramebufferSize(width: rect.width, height: rect.height)
                        // Its contents are undefined now (RFC 6143 §7.8.2): ask for all of it.
                        planner.framebufferResized(width: rect.width, height: rect.height)
                        pump()
                        changed = true
                    case .extendedDesktopSize:
                        let screenCount = Int(try await source.u8())
                        _ = try await source.read(3)
                        var screens: [VNCScreen] = []
                        for _ in 0..<screenCount {
                            let entry = try await source.read(16)
                            var reader = ByteReader(entry)
                            screens.append(VNCScreen(id: try reader.u32(), x: Int(try reader.u16()), y: Int(try reader.u16()),
                                                     width: Int(try reader.u16()), height: Int(try reader.u16()),
                                                     flags: try reader.u32()))
                        }
                        if !state.desktopResizeSupported {
                            state.setDesktopResizeSupported()
                            callbacks.desktopResizeSupported()
                        }
                        // The rectangle carries the new framebuffer size, so validate against it.
                        let boundsWidth = rect.width > 0 ? rect.width : framebuffer.width
                        let boundsHeight = rect.height > 0 ? rect.height : framebuffer.height
                        callbacks.screens(screens.compactMap { $0.validated(inFramebufferWidth: boundsWidth, height: boundsHeight) })
                        // x carries the reason, y the status; only a successful change resizes.
                        if rect.y == 0, rect.width > 0, rect.height > 0,
                           rect.width != framebuffer.width || rect.height != framebuffer.height {
                            try framebuffer.resize(width: rect.width, height: rect.height)
                            state.setFramebufferSize(width: rect.width, height: rect.height)
                            planner.framebufferResized(width: rect.width, height: rect.height)
                            pump()
                            changed = true
                        } else if rect.y != 0, rect.x == 1 {
                            Self.logger.notice("event=resize-refused status=\(rect.y)")
                        }
                    case .appleDisplayLayout:
                        // A Mac's displays (W30): where each sits inside the one framebuffer.
                        if let layout = try await RFBAppleDisplayLayout.read(from: source) {
                            let boundsWidth = max(framebuffer.width, layout.width ?? 0)
                            let boundsHeight = max(framebuffer.height, layout.height ?? 0)
                            let screens = layout.screens.compactMap { $0.validated(inFramebufferWidth: boundsWidth, height: boundsHeight) }
                            Self.logger.notice("event=apple-display-layout displays=\(screens.count)")
                            callbacks.screens(screens)
                        } else {
                            Self.logger.notice("event=apple-display-layout unreadable")
                        }
                        // After a layout the whole framebuffer is asked for again.
                        planner.framebufferResized(width: framebuffer.width, height: framebuffer.height)
                        pump()
                    default:
                        let validated = try rect.validated(in: framebuffer.width, framebuffer.height)
                        try await decoder.decode(validated, encoding: encoding, from: source, into: framebuffer, pixels: pixels)
                        changed = true
                    }
                }
                if changed { callbacks.frame(framebuffer.width, framebuffer.height, framebuffer.snapshot()) }
                // The link's speed, from every byte this update took to arrive whatever its
                // encoding, is what Automatic chooses its level by.
                let elapsed = ContinuousClock.now - started
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let bytes = source.totalBytes - startBytes
                planner.updateEnded(bytes: bytes, seconds: seconds, changed: changed, encodingBytes: encodingBytes, at: .now)
                callbacks.update(VNCUpdateSummary(rectangles: rectangles, encodings: encodings, bytes: bytes,
                                                  colourDepth: pixels.colourDepth))
            case 1:
                _ = try await source.u8()
                _ = try await source.u16()
                let count = Int(try await source.u16())
                _ = try await source.read(count * 6)
            case 2:
                callbacks.bell()
            case 3:
                _ = try await source.read(3)
                let rawLength = Int32(bitPattern: try await source.u32())
                if rawLength < 0 {
                    // Extended clipboard (TigerVNC) is not negotiated; skip its payload.
                    let length = Int(-Int64(rawLength))
                    guard length <= RFBLimits.maximumCutTextBytes else { throw RFBError.resourceLimit("The server clipboard message is too large.") }
                    _ = try await source.read(length)
                } else {
                    guard Int(rawLength) <= RFBLimits.maximumCutTextBytes else { throw RFBError.resourceLimit("The server clipboard message is too large.") }
                    let bytes = try await source.read(Int(rawLength))
                    if configuration.clipboardEnabled {
                        callbacks.cutText(String(bytes.map { Character(Unicode.Scalar($0)) }))
                    }
                }
            default:
                throw RFBError.protocolViolation("The server sent an unknown message type \(type).")
            }
        }
    }
}

private final class ClientState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var isReady = false
    private var resizeSupported = false
    private var width = 0, height = 0
    private var openAction: (@Sendable () async throws -> Void)?

    var isCancelled: Bool { lock.withLock { cancelled } }
    var ready: Bool { lock.withLock { isReady } }
    var desktopResizeSupported: Bool { lock.withLock { resizeSupported } }
    var framebufferSize: (width: Int, height: Int) { lock.withLock { (width, height) } }
    func cancel() { lock.withLock { cancelled = true; isReady = false } }
    func setReady(_ value: Bool) { lock.withLock { isReady = value } }
    func setDesktopResizeSupported() { lock.withLock { resizeSupported = true } }
    func setFramebufferSize(width: Int, height: Int) { lock.withLock { self.width = width; self.height = height } }
    func setOpen(_ action: @escaping @Sendable () async throws -> Void) { lock.withLock { openAction = action } }
    func open() async throws {
        let action = lock.withLock { openAction }
        try await action?()
    }

    /// Timers the planner asked for; cancelled when the session ends.
    private var wakes: [Task<Void, Never>] = []
    private var stopped = false
    func addWake(_ task: Task<Void, Never>) {
        let cancelNow = lock.withLock { () -> Bool in
            guard !stopped else { return true }
            // Earlier timers have fired by now; only the most recent few can still be waiting.
            if wakes.count >= 16 { wakes.removeFirst(wakes.count - 15) }
            wakes.append(task)
            return false
        }
        if cancelNow { task.cancel() }
    }
    func cancelWakes() {
        let pending = lock.withLock { () -> [Task<Void, Never>] in
            stopped = true
            defer { wakes = [] }
            return wakes
        }
        for task in pending { task.cancel() }
    }
}
