import Foundation
import OSLog

public struct VNCConfiguration: Sendable {
    public var host: String
    public var port: UInt16
    public var username: String
    public var password: String
    public var sharedSession: Bool
    public var clipboardEnabled: Bool
    /// Ask Apple's server for its displays (encodings 1101 and 1105, `RFBAppleDisplays.swift`). Off
    /// after a Mac ended a session in a protocol error once it had sent them (`GlassVNCSession`).
    public var requestsAppleDisplayLayout: Bool
    /// Ask Apple's server to render smaller at the lower quality levels (`SetServerScaling`). Off
    /// after a Mac ended a session while a factor was unanswered (`GlassVNCSession`).
    public var allowsServerScaling: Bool
    /// Ask Apple's server where its pointer is and for its shapes in its own cache (encodings 1100
    /// and 1104, `RFBAppleCursor.swift`). Off after a Mac broke the protocol once it had sent one (W38).
    public var requestsAppleCursor: Bool
    /// A Mac's display this connection exists to show alone (`SetDisplay`, W38): until a layout says
    /// it is being sent, no picture is fetched or handed on, and a Mac that does not switch to it ends
    /// the session. Nil shows what the Mac sends.
    public var display: UInt32?
    /// Answer a Mac in its own revision, RFB 003.889, with its record layer: the session encrypted
    /// after sign-in, which 3.8 never asks for (`RFBAppleRecordLayer`, 2026-10-11). Off: 3.8, as
    /// common clients answer. Other servers are answered as before either way.
    public var appleProtocol: Bool

    public init(host: String, port: UInt16 = 5900, username: String = "", password: String,
                sharedSession: Bool = true, clipboardEnabled: Bool = false, requestsAppleDisplayLayout: Bool = true,
                allowsServerScaling: Bool = true, requestsAppleCursor: Bool = true, display: UInt32? = nil,
                appleProtocol: Bool = false) {
        self.appleProtocol = appleProtocol
        self.host = host; self.port = port; self.username = username; self.password = password
        self.sharedSession = sharedSession; self.clipboardEnabled = clipboardEnabled
        self.requestsAppleDisplayLayout = requestsAppleDisplayLayout
        self.allowsServerScaling = allowsServerScaling
        self.requestsAppleCursor = requestsAppleCursor
        self.display = display
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
    /// What a Mac said about its displays, as it said it: for diagnostics and the live probe.
    public var appleDisplayMetadata: @Sendable (RFBAppleDisplayMetadata) -> Void = { _ in }
    /// Where a Mac's pointer is, in the framebuffer's pixels as they arrive (W38).
    public var cursorPosition: @Sendable (_ x: Int, _ y: Int) -> Void = { _, _ in }
    /// Everything that arrived about the pointer, as it arrived: for diagnostics and the live probe.
    public var cursorMessage: @Sendable (VNCCursorMessage) -> Void = { _ in }
    /// A ZRLE rectangle had bytes left over and the session went on (`RFBZRLETrailingData`).
    public var zrleTrailingData: @Sendable (RFBZRLETrailingData) -> Void = { _ in }
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
    /// Under `source` and `sink`: the bytes as they come until a Mac's rekey, then its record layer.
    private let records: RFBAppleRecordLayer
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
        let records = RFBAppleRecordLayer(source: source, sink: sink)
        self.records = records
        self.source = RFBCountingByteSource(records)
        self.sink = records
        self.closeAction = close
        (outbox, outboxContinuation) = AsyncStream.makeStream(of: [UInt8].self)
        state.setOpen(open)
        if let display = configuration.display { planner.setDisplay(.display(display)) }
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

    /// Asks a Mac to render at this factor, in (0, 1], whatever the quality level says; nil goes back
    /// to the level's. Sent once the Mac has sent a display layout, and in force once a layout says
    /// so (`RFBStreamPlanner`). Other servers ignore it.
    public func setServerScaling(_ factor: Double?) {
        planner.setServerScaleOverride(factor)
        pump()
    }

    /// The factor a Mac has confirmed it renders at; 1 on every other server.
    public var serverScale: Double { planner.serverScaleInForce }

    /// Retina displays at 1x (W38): a Mac is asked to render the displays being fetched at one pixel
    /// per point — half a Retina display's pixels each way — times the quality level's own factor,
    /// where they share a density. Off sends a Mac's displays at their own pixels.
    public func setDensityScaling(_ on: Bool) {
        planner.setDensityScaling(on)
        pump()
    }

    /// Whether a Mac is armed to push its changes, its pointer's among them (`AutoFrameBufferUpdate`).
    /// On; the live probe turns it off to compare.
    public func setAppleUpdateArming(_ on: Bool, interval: UInt32 = 0) {
        planner.setArming(on, interval: interval)
        pump()
    }

    /// Whether a Mac is also asked for the standard PointerPos (−232). Off; the live probe tries it.
    public func setAsksForPointerPosition(_ on: Bool) {
        planner.setAsksForPointerPosition(on)
        pump()
    }

    /// Whether Apple's revision's prelude identifies this client (`ViewerInfo`). On; the live probe
    /// turns it off to compare. Set before `run`.
    public func setAppleViewerInfo(_ on: Bool) { state.setSendsViewerInfo(on) }

    /// Asks a Mac to send one display, its own pixels the whole framebuffer, or every display
    /// (`SetDisplay`, W38). Sent once the Mac has sent a layout; a layout naming it confirms it.
    public func setDisplay(_ selection: RFBDisplaySelection?) {
        planner.setDisplay(selection)
        pump()
    }

    /// The display a Mac's last layout says it is sending; nil for all of them, or no layout.
    public var currentDisplay: UInt32? { planner.currentDisplay }

    /// A display was asked of a Mac and no layout has confirmed it yet.
    public var awaitingDisplay: Bool { planner.awaitingDisplay }

    /// A Mac sent its pointer's position or a shape from its cache this session: a later protocol
    /// error may be a misreading of them (W38).
    public var receivedAppleCursor: Bool { state.appleCursor }

    /// The last of a Mac's own encodings (display metadata or the pointer's) read since a pixel
    /// rectangle was last read in step: the likeliest misreading behind a protocol error that follows
    /// it. Nil once a pixel rectangle has been read after it, which shows it was read right.
    public var lastAppleEncoding: RFBEncoding? { state.lastAppleEncoding }

    /// The session travels in a Mac's record layer, encrypted (003.889).
    public var isEncrypted: Bool { records.isEncrypted }

    /// How many picture rectangles each of a Mac's displays has received this connection, by display id.
    public var rectanglesPainted: [UInt32: Int] { state.paintedTotal }

    /// What each display's part of the picture holds, as the flow line samples it ("1:73%,4:97%").
    public var displayContent: String? { state.content }

    /// This client answered a Mac in its own revision, 003.889.
    public var answeredAppleProtocol: Bool { state.appleProtocol }

    /// ZRLE rectangles read with bytes left over this connection (`RFBZRLETrailingData`).
    public var zrleTrailingDataCount: Int { state.zrleTrailingDataCount }

    /// A factor was asked of a Mac and no layout has confirmed it yet.
    public var awaitingServerScaling: Bool { planner.awaitingServerScale }

    /// A Mac sent display metadata this session (its layout or `DisplayInfo`): a later protocol
    /// error may be a misreading of it.
    public var receivedAppleDisplayMetadata: Bool { state.appleDisplayMetadata }

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
            await records.finish()
        }
        do {
            try await state.open()
            try checkCancelled()
            var (info, wrapKey) = try await handshake()
            if info.negotiatedVersion == .apple {
                try await applePrelude(wrapKey: wrapKey)
                info.encrypted = true
                if info.appleAccepts(0x17) { state.setAcceptsAppleScroll() }
            }
            wrapKey = []
            planner.start(width: info.width, height: info.height, dialect: RFBServerDialect(version: info.serverVersion),
                          appleDisplayLayout: configuration.requestsAppleDisplayLayout,
                          serverScaling: configuration.allowsServerScaling,
                          appleCursor: configuration.requestsAppleCursor)
            let opening = planner.openingMessages()
            try await sink.write(opening.pixelFormat)
            try await sink.write(opening.encodings)
            // The first request is on the wire before the session says it is ready; later ones go
            // through the outbox, in the order the planner decides them.
            var first: [[UInt8]] = []
            _ = planner.decide(at: .now) { first.append($0) }
            for message in first { try await sink.write(message) }
            let framebuffer = try RFBFramebuffer(width: info.width, height: info.height)
            state.setFramebufferSize(width: info.width, height: info.height)
            let (sink, outbox) = (sink, outbox)
            streaming.append(Task {
                for await message in outbox {
                    do { try await sink.write(message) } catch { return }
                }
            })
            streaming.append(Task { [weak self] in
                var tick = 0
                var last = (updates: 0, frames: 0, rectangles: 0, bytes: 0)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    self.callbacks.statistics(self.statistics)
                    // Every five seconds, whether pictures keep coming: a session that takes input
                    // but stops drawing is told apart from one whose Mac stopped sending (2026-10-11).
                    tick += 1
                    if tick % 5 == 0 {
                        let counts = self.state.flowCounts, bytes = self.source.totalBytes
                        let flow = self.planner.flow(at: .now)
                        func seconds(_ value: Duration?) -> String {
                            value.map { String(format: "%.1f", Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18) } ?? "-"
                        }
                        let area = self.planner.requestedArea.map { "\($0.x),\($0.y),\($0.width)x\($0.height)" } ?? "none"
                        let painted = self.state.takePainted().sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
                        VNCDiagnostics.record(category: "client", "event=flow connection=\(self.configuration.display.map { "display-\($0)" } ?? "desktop") "
                            + "updates=\(counts.updates - last.updates) frames=\(counts.frames - last.frames) "
                            + "rects=\(counts.rectangles - last.rectangles) bytes=\(bytes - last.bytes) "
                            + "outstanding=\(flow.outstanding) sinceRequest=\(seconds(flow.sinceRequest)) waiting=\(seconds(flow.waiting)) "
                            + "requested=\(area) scale=\(self.planner.serverScaleInForce) sending=\(self.planner.currentDisplay.map(String.init) ?? "all") "
                            + "painted=\(painted.isEmpty ? "none" : painted) lit=\(self.state.content ?? "unknown")")
                        last = (counts.updates, counts.frames, counts.rectangles, bytes)
                    }
                    // A Mac that does not answer may send nothing at all: looked at here, not only
                    // as messages arrive.
                    if let display = self.configuration.display, self.planner.displayRefused(at: .now) {
                        self.fail(Self.displayRefusal(display))
                        return
                    }
                }
            })
            state.setReady(true)
            callbacks.connected(info)
            try await updateLoop(framebuffer: framebuffer)
        } catch {
            await finish()
            if let failure = state.failure { throw failure }
            if state.isCancelled { throw RFBError.cancelled }
            throw error
        }
        await finish()
    }

    static func displayRefusal(_ display: UInt32) -> RFBError {
        .unsupported("The Mac did not send display \(display) on a connection of its own within ten seconds.")
    }

    /// Ends the session with this failure rather than as cancelled.
    private func fail(_ error: RFBError) {
        state.fail(error)
        let close = closeAction
        Task { await close() }
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

    private func handshake() async throws -> (VNCServerInfo, wrapKey: [UInt8]) {
        let serverVersion = try RFBProtocolVersion.parse(try await source.read(12))
        // Only with the Mac's own sign-in: its record layer's key comes from type 30's exchange, so a
        // password-only connection is answered in 3.8 as before.
        let account = !configuration.username.isEmpty && !configuration.password.isEmpty
        let version = configuration.appleProtocol && account && serverVersion == .apple ? .apple : serverVersion.negotiated
        let apple = version == .apple
        if apple { state.setAppleProtocol() }
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
        let (keyExchange, wrapKey) = try await authenticate(securityType, version: version)
        // 0x80 asks a Mac for its enhanced ServerInit (remotex's notes, "Connecting").
        try await sink.write([(configuration.sharedSession ? 1 : 0) | (apple ? 0x80 : 0)])
        let initBytes = try await source.read(24)
        var reader = ByteReader(initBytes)
        let width = Int(try reader.u16()), height = Int(try reader.u16())
        let pixelFormat = try RFBPixelFormat.parse(&reader)
        let nameLength = Int(try reader.u32())
        guard nameLength <= RFBLimits.maximumNameBytes else { throw RFBError.resourceLimit("The server name is too long.") }
        try RFBFramebuffer.validate(width: width, height: height)
        let field = try await source.read(nameLength)
        // A Mac's enhanced ServerInit puts 22 bytes before the name: a zero `u16`, a `u32` of flags
        // and the 16-byte bitmap of the client messages it accepts (remotex's notes, "ServerInit's
        // name field is not a name").
        let enhanced = apple && field.count >= 22 && field[0] == 0
        let name = String(decoding: enhanced ? field[22...] : field[...], as: UTF8.self)
        guard !apple || wrapKey.count == 16 else {
            throw RFBError.unsupported("Apple's Screen Sharing protocol needs the Mac's own sign-in (a user name and password).")
        }
        let keyExchangeMilliseconds = keyExchange.map { Int(Self.seconds($0) * 1000) } ?? -1
        VNCDiagnostics.note(Self.logger, .default, category: "client", "event=connected version=\(serverVersion.major).\(serverVersion.minor) answered=\(version.major).\(version.minor) security=\(securityType.rawValue) width=\(width) height=\(height) keyExchangeMs=\(keyExchangeMilliseconds)")
        let info = VNCServerInfo(name: name, width: width, height: height, serverVersion: serverVersion,
                                 negotiatedVersion: version, securityType: securityType, serverPixelFormat: pixelFormat,
                                 keyExchangeDuration: keyExchange, appleCommands: enhanced ? Array(field[6..<22]) : nil)
        return (info, wrapKey)
    }

    // MARK: Apple's revision

    /// What a Mac needs after ServerInit on 003.889 before anything else, then its record layer
    /// (remotex's `apple_preface`): ViewerInfo, SetMode(control) and SetEncryption 1 and 2, back to
    /// back in the clear, then the rekey, read in the clear too. The Mac switches both its ciphers the
    /// moment it sends the rekey, so the layer goes up before this client writes another byte.
    private func applePrelude(wrapKey: [UInt8]) async throws {
        if state.sendsViewerInfo { try await sink.write(RFBAppleMessages.viewerInfo) }
        try await sink.write(RFBAppleMessages.setModeControl)
        try await sink.write(RFBAppleMessages.setEncryptionStart)
        try await sink.write(RFBAppleMessages.enableInboundDecryption)
        let keys = try await awaitRekey(wrapKey: wrapKey)
        try records.install(keys)
        VNCDiagnostics.note(Self.logger, .default, category: "client", "event=apple-record-layer active")
    }

    /// Reads the Mac's messages in the clear until the rekey, stepping over a Bell or a MiscStatus,
    /// which it may send unasked meanwhile; anything else means the stream went somewhere unexpected.
    private func awaitRekey(wrapKey: [UInt8]) async throws -> RFBAppleRecordKeys {
        while true {
            switch try await source.u8() {
            case 0:
                _ = try await source.u8()
                let count = try await source.u16()
                if count == 0 { continue }
                var header = ByteReader(try await source.read(12))
                _ = try header.bytes(8)
                let encoding = try header.s32()
                guard encoding == RFBAppleMessages.rekeyEncoding else {
                    throw RFBError.protocolViolation("The Mac sent encoding \(encoding) before its encryption key.")
                }
                let body = try await source.read(RFBAppleRecordKeys.rekeyLength)
                // Everything after the rekey is ciphertext: another rectangle here could not be read.
                guard count == 1 else { throw RFBError.protocolViolation("The Mac sent more after its encryption key.") }
                return try RFBAppleRecordKeys.unwrap(rekey: body, wrapKey: wrapKey).keys
            case 2:
                continue
            case 0x14:
                _ = try await source.u8()
                let length = Int(try await source.u16())
                guard length <= 64 else { throw RFBError.protocolViolation("The Mac sent a status message of \(length) bytes.") }
                _ = try await source.read(length)
            case let other:
                throw RFBError.protocolViolation("The Mac sent message \(other) before its encryption key.")
            }
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
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

    /// Returns how long type 30's key exchange took to compute on this device, nil for other types,
    /// and type 30's wrap key (`MD5(shared secret)`), empty for other types.
    private func authenticate(_ type: RFBSecurityType, version: RFBProtocolVersion) async throws -> (Duration?, [UInt8]) {
        switch type {
        case .none:
            if version.minor >= 8 { try await readSecurityResult(version) }
        case .vncAuthentication:
            let challenge = try await source.read(16)
            try await sink.write(try RFBSecurity.vncAuthenticationResponse(challenge: challenge, password: configuration.password))
            try await readSecurityResult(version)
        case .appleRemoteDesktop:
            let generator = try await source.u16(), keyLength = try await source.u16()
            guard (RFBLimits.minimumDiffieHellmanKeyBytes...RFBLimits.maximumDiffieHellmanKeyBytes).contains(Int(keyLength)) else {
                throw RFBError.protocolViolation("The Apple Remote Desktop key length \(keyLength) is invalid.")
            }
            let body = try await source.read(Int(keyLength) * 2)
            let challenge = try RFBSecurity.AppleRemoteDesktopChallenge.parse(generator: generator, keyLength: keyLength, body: body)
            let started = ContinuousClock.now
            let response = try RFBSecurity.appleRemoteDesktopResponse(challenge, username: configuration.username,
                                                                      password: configuration.password)
            let keyExchange = ContinuousClock.now - started
            try await sink.write(response.wireBytes)
            try await readSecurityResult(version)
            return (keyExchange, response.wrapKey)
        case .invalid:
            throw RFBError.protocolViolation("The server selected an invalid security type.")
        }
        return (nil, [])
    }

    private func readSecurityResult(_ version: RFBProtocolVersion) async throws {
        let result = try await source.u32()
        guard result == 0 else {
            var reason = "The server rejected the credentials."
            // A Mac sends its reason only to a 3.8 viewer; to 003.889 a refusal is the word alone,
            // and waiting for a reason would wait out the connection (remotex's notes).
            if version != .apple, let detail = try? await readReason(), !detail.isEmpty { reason = detail }
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

    /// A position in the framebuffer as it arrives. A Mac rendering at a server-side scale still
    /// reads pointer positions in its unscaled framebuffer's pixels, so they are divided by the
    /// factor its last layout confirmed (remotex's notes, "Server-side scaling in Standard mode").
    public func sendPointer(buttonMask: UInt8, x: Int, y: Int) async throws {
        try requireReady()
        let size = state.framebufferSize
        let clampedX = min(max(0, x), max(0, size.width - 1)), clampedY = min(max(0, y), max(0, size.height - 1))
        let wire = Self.unscaled(x: clampedX, y: clampedY, scale: planner.serverScaleInForce)
        state.pointerSent(picture: (clampedX, clampedY), wire: wire, at: .now)
        let mask = state.appleProtocol ? Self.applePointerMask(buttonMask) : buttonMask
        try await sink.write([5, mask] + UInt16(wire.x).bigEndianBytes + UInt16(wire.y).bigEndianBytes)
    }

    /// Whether a scroll can go to this Mac as a distance (`sendAppleScroll`): it was answered in its
    /// own revision and its ServerInit lists the second event message (0x17).
    public var acceptsAppleScroll: Bool { state.appleProtocol && state.acceptsAppleScroll }

    /// A scroll by a distance in the picture's points, up and left positive, at a position in the
    /// picture: as Apple's viewer scrolls a Mac, smoothly, where the wheel bits move it a couple of
    /// pixels a notch (remotex's notes, "A Mac scrolls by a distance").
    public func sendAppleScroll(horizontalPoints: Int, verticalPoints: Int, x: Int, y: Int) async throws {
        try requireReady()
        let size = state.framebufferSize
        let clampedX = min(max(0, x), max(0, size.width - 1)), clampedY = min(max(0, y), max(0, size.height - 1))
        let wire = Self.unscaled(x: clampedX, y: clampedY, scale: planner.serverScaleInForce)
        try await sink.write(RFBAppleMessages.scrollWheel(horizontalPoints: horizontalPoints, verticalPoints: verticalPoints,
                                                          x: wire.x, y: wire.y))
    }

    /// RFB's mask with its middle (0x02) and right (0x04) buttons swapped: a Mac reads a 003.889
    /// viewer's mask as macOS button numbers, left, right, middle, where it swaps them back for every
    /// other version; sent by the book, a right-click lands as a middle-click (remotex's notes, "Apple's
    /// revision reads the pointer mask as CGMouseButton numbers").
    static func applePointerMask(_ mask: UInt8) -> UInt8 {
        (mask & ~0x06) | (mask & 0x02) << 1 | (mask & 0x04) >> 1
    }

    /// A scaled framebuffer position in the unscaled framebuffer's pixels.
    static func unscaled(x: Int, y: Int, scale: Double) -> (x: Int, y: Int) {
        guard scale.isFinite, scale > 0, scale < 1 else { return (x, y) }
        let limit = Double(UInt16.max)
        return (Int(min(limit, (Double(x) / scale).rounded())), Int(min(limit, (Double(y) / scale).rounded())))
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
        let cursors = RFBAppleCursorCache()
        let apple = planner.serverDialect == .apple
        while true {
            try checkCancelled()
            // A connection for one display whose Mac did not switch to it ends: it was opened to send
            // that display alone, and the whole desktop is not what it is for (W38).
            if let display = configuration.display, planner.displayRefused(at: .now) {
                throw Self.displayRefusal(display)
            }
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
                        if rect.isEmpty {
                            callbacks.cursorMessage(.richCursorHidden)
                            callbacks.cursor(nil)
                        } else {
                            // A Mac's shape is in its points (W38): the owner's pointer on a Retina
                            // display, drawn as its pixels, was half the size it is on the Mac.
                            let image = try await RFBRectangleDecoder.decodeCursor(rect, from: source, pixels: pixels,
                                                                                   pointSized: apple)
                            callbacks.cursorMessage(.richCursor(width: rect.width, height: rect.height,
                                                               hotSpotX: rect.x, hotSpotY: rect.y))
                            callbacks.cursor(image)
                        }
                    case .appleCursorImage:
                        // A shape stored in, or selected from, the Mac's cache (`RFBAppleCursor.swift`):
                        // the header's x and y are its hotspot and its size the shape's.
                        state.noteApple(.appleCursorImage)
                        let body = try await RFBAppleCursorCache.readBody(from: source)
                        let outcome = cursors.accept(id: body.id, hotSpotX: rect.x, hotSpotY: rect.y,
                                                     width: rect.width, height: rect.height, deflated: body.deflated)
                        if body.deflated.isEmpty {
                            if case .shape = outcome { callbacks.cursorMessage(.appleSelected(id: body.id, known: true)) }
                            else { callbacks.cursorMessage(.appleSelected(id: body.id, known: false)) }
                        } else {
                            var decoded = false
                            if case .shape = outcome { decoded = true }
                            if case .unreadable(let reason) = outcome {
                                VNCDiagnostics.note(Self.logger, .error, category: "client", "event=apple-cursor unreadable id=\(body.id) reason=\(reason)")
                            }
                            callbacks.cursorMessage(.appleStored(id: body.id, width: rect.width, height: rect.height,
                                                                 hotSpotX: rect.x, hotSpotY: rect.y,
                                                                 compressedBytes: body.deflated.count, decoded: decoded))
                        }
                        // A shape this client cannot draw leaves the pointer as it is: closer to the
                        // truth than blanking it (remotex's `Cursor::Unchanged`).
                        if case .shape(let image) = outcome { callbacks.cursor(image) }
                    case .appleCursorPosition:
                        // Where the Mac's pointer is: the header's x and y, and nothing after them.
                        state.noteApple(.appleCursorPosition)
                        callbacks.cursorMessage(.applePosition(x: rect.x, y: rect.y))
                        if let point = state.mapCursorPosition(x: rect.x, y: rect.y, scale: planner.serverScaleInForce,
                                                               width: framebuffer.width, height: framebuffer.height) {
                            callbacks.cursorPosition(point.x, point.y)
                        }
                    case .pointerPosition:
                        // The standard PointerPos: the header's x and y, nothing after them.
                        callbacks.cursorMessage(.pointerPosition(x: rect.x, y: rect.y))
                        if let point = state.mapCursorPosition(x: rect.x, y: rect.y, scale: planner.serverScaleInForce,
                                                               width: framebuffer.width, height: framebuffer.height) {
                            callbacks.cursorPosition(point.x, point.y)
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
                            VNCDiagnostics.note(Self.logger, .default, category: "client", "event=resize-refused status=\(rect.y)")
                        }
                    case .appleDisplayLayout:
                        // A Mac's displays, the framebuffer's size and the scale in force
                        // (`RFBAppleDisplays.swift`). A Mac listing DisplayInfo sends no
                        // DesktopSize, so a size change — a display added, a scale applied —
                        // arrives only here.
                        state.noteAppleDisplayMetadata()
                        state.noteApple(.appleDisplayLayout)
                        let payload = try await RFBAppleDisplayLayout.readPayload(from: source)
                        guard let layout = RFBAppleDisplayLayout(payload: payload) else {
                            VNCDiagnostics.note(Self.logger, .error, category: "client", "event=apple-display-layout unreadable bytes=\(payload.count)")
                            callbacks.appleDisplayMetadata(.unreadableLayout(payload))
                            planner.framebufferResized(width: framebuffer.width, height: framebuffer.height)
                            pump()
                            continue rectangles
                        }
                        if let size = layout.framebufferSize, size.width != framebuffer.width || size.height != framebuffer.height {
                            if (try? RFBFramebuffer.validate(width: size.width, height: size.height)) != nil {
                                try framebuffer.resize(width: size.width, height: size.height)
                                state.setFramebufferSize(width: size.width, height: size.height)
                                changed = true
                            } else {
                                VNCDiagnostics.note(Self.logger, .error, category: "client", "event=apple-display-layout framebuffer=\(size.width)x\(size.height) unsupported")
                            }
                        }
                        let screens = layout.screens(inFramebufferWidth: framebuffer.width, height: framebuffer.height)
                        planner.appleLayoutArrived(serverScale: layout.serverScale, width: framebuffer.width, height: framebuffer.height,
                                                   displays: screens, densities: layout.densities, current: layout.currentDisplay)
                        let current = layout.currentDisplay.map(String.init) ?? "all"
                        VNCDiagnostics.note(Self.logger, .default, category: "client", "event=apple-display-layout version=\(layout.version) records=\(layout.records.count) displays=\(screens.count) framebuffer=\(layout.framebufferWidth)x\(layout.framebufferHeight) current=\(current) scale=\(layout.serverScale) state=\(layout.sessionState)")
                        callbacks.appleDisplayMetadata(.layout(layout))
                        // A layout none of whose displays holds up leaves the last list in place.
                        if !screens.isEmpty { callbacks.screens(screens) }
                        pump()
                    case .appleDisplayInfo:
                        // The older list, which a Mac sends instead of the layout only if it has
                        // none: stepped over, and reported.
                        state.noteAppleDisplayMetadata()
                        state.noteApple(.appleDisplayInfo)
                        let info = try await RFBAppleDisplayInfo.read(from: source)
                        VNCDiagnostics.note(Self.logger, .default, category: "client", "event=apple-display-info width=\(info.width) height=\(info.height) flags=\(info.flags) displays=\(info.records.count)")
                        callbacks.appleDisplayMetadata(.displayInfo(info))
                    default:
                        let validated = try rect.validated(in: framebuffer.width, framebuffer.height)
                        do {
                            try await decoder.decode(validated, encoding: encoding, from: source, into: framebuffer, pixels: pixels)
                        } catch let anomaly as RFBZRLETrailingData {
                            // Its length was read in full and the deflate stream inflated all of it, so
                            // the connection and the stream are still in step: only this rectangle is
                            // suspect. Keep the session, say so, and ask for the picture again
                            // (2026-10-11: ending here dropped a two-display session on a headset).
                            let count = state.noteZRLETrailingData()
                            if count <= 10 || count % 50 == 0 {
                                let area = planner.requestedArea.map { "\($0.x),\($0.y),\($0.width)x\($0.height)" } ?? "none"
                                VNCDiagnostics.note(Self.logger, .error, category: "client", "event=zrle-trailing count=\(count) \(anomaly.summary) "
                                    + "framebuffer=\(framebuffer.width)x\(framebuffer.height) scale=\(planner.serverScaleInForce) requested=\(area)")
                            }
                            callbacks.zrleTrailingData(anomaly)
                            planner.framebufferResized(width: framebuffer.width, height: framebuffer.height)
                            pump()
                        }
                        // A pixel rectangle read in step: whatever a Mac's own encoding said before it
                        // was read right, and is not what a later protocol error misread.
                        state.notePixelRectangle()
                        // Which displays it painted, for the flow line (2026-10-11: a display that
                        // never repainted on 003.889).
                        if !validated.isEmpty {
                            let hit = planner.currentDisplays.filter {
                                validated.intersects(RFBRectangle(x: $0.x, y: $0.y, width: $0.width, height: $0.height))
                            }.map(\.id)
                            state.notePainted(hit)
                        }
                        changed = true
                    }
                }
                // While waiting for its display, a one-display connection hands on no picture: what it
                // holds is the whole desktop's, not its display's (W38).
                let delivers = changed && !planner.holdingForDisplay
                if delivers {
                    callbacks.frame(framebuffer.width, framebuffer.height, framebuffer.snapshot())
                }
                state.noteUpdate(rectangles: rectangles.count, delivered: delivers)
                // What each display's part of the picture holds, now and then, for the flow line.
                if state.contentSampleDue(at: .now) {
                    let content = planner.currentDisplays.compactMap { display -> String? in
                        let rect = RFBRectangle(x: display.x, y: display.y, width: display.width, height: display.height)
                        return framebuffer.litPercent(in: rect).map { "\(display.id):\($0)%" }
                    }.joined(separator: ",")
                    state.noteContent(content)
                }
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
            case 0x14 where apple:
                // A Mac's `MiscStatus`: a pad byte, a `u16` length, then that many bytes — a `u16`
                // 1 and the command. Most are sent only to a viewer that says it handles them; the
                // user session changing (17) is sent to every viewer (remotex's notes, "MiscStatus").
                _ = try await source.u8()
                let length = Int(try await source.u16())
                guard length <= 64 else { throw RFBError.protocolViolation("The Mac sent a status message of \(length) bytes.") }
                var body = ByteReader(try await source.read(length))
                _ = try? body.u16()
                let command = (try? body.u16()).map(String.init) ?? "none"
                VNCDiagnostics.note(Self.logger, .default, category: "client", "event=apple-status command=\(command)")
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
    private var displayMetadata = false
    private var cursorSeen = false
    private var lastApple: RFBEncoding?
    private var cursorSpace = RFBCursorPositionSpace()

    var isCancelled: Bool { lock.withLock { cancelled } }
    var ready: Bool { lock.withLock { isReady } }
    var desktopResizeSupported: Bool { lock.withLock { resizeSupported } }
    var appleDisplayMetadata: Bool { lock.withLock { displayMetadata } }
    func noteAppleDisplayMetadata() { lock.withLock { displayMetadata = true } }
    var appleCursor: Bool { lock.withLock { cursorSeen } }
    var lastAppleEncoding: RFBEncoding? { lock.withLock { lastApple } }
    func noteApple(_ encoding: RFBEncoding) {
        lock.withLock {
            lastApple = encoding
            if encoding == .appleCursorImage || encoding == .appleCursorPosition { cursorSeen = true }
        }
    }
    func notePixelRectangle() { lock.withLock { lastApple = nil } }
    private var painted: [UInt32: Int] = [:]
    private var contentSampledAt: ContinuousClock.Instant?
    private var contentSummary: String?
    var content: String? { lock.withLock { contentSummary } }
    func noteContent(_ value: String) { lock.withLock { contentSummary = value } }
    func contentSampleDue(at now: ContinuousClock.Instant) -> Bool {
        lock.withLock {
            if let last = contentSampledAt, now - last < .seconds(4) { return false }
            contentSampledAt = now
            return true
        }
    }
    private var paintedAll: [UInt32: Int] = [:]
    var paintedTotal: [UInt32: Int] { lock.withLock { paintedAll } }
    func notePainted(_ displays: [UInt32]) {
        lock.withLock { for id in displays { painted[id, default: 0] += 1; paintedAll[id, default: 0] += 1 } }
    }
    func takePainted() -> [UInt32: Int] { lock.withLock { defer { painted = [:] }; return painted } }
    private var viewerInfo = true
    var sendsViewerInfo: Bool { lock.withLock { viewerInfo } }
    func setSendsViewerInfo(_ on: Bool) { lock.withLock { viewerInfo = on } }
    private var appleScroll = false
    var acceptsAppleScroll: Bool { lock.withLock { appleScroll } }
    func setAcceptsAppleScroll() { lock.withLock { appleScroll = true } }
    private var apple889 = false
    var appleProtocol: Bool { lock.withLock { apple889 } }
    func setAppleProtocol() { lock.withLock { apple889 = true } }
    private var flow = (updates: 0, frames: 0, rectangles: 0)
    var flowCounts: (updates: Int, frames: Int, rectangles: Int) { lock.withLock { flow } }
    func noteUpdate(rectangles: Int, delivered: Bool) {
        lock.withLock { flow.updates += 1; flow.rectangles += rectangles; if delivered { flow.frames += 1 } }
    }
    private var trailing = 0
    var zrleTrailingDataCount: Int { lock.withLock { trailing } }
    func noteZRLETrailingData() -> Int { lock.withLock { trailing += 1; return trailing } }
    func pointerSent(picture: (x: Int, y: Int), wire: (x: Int, y: Int), at now: ContinuousClock.Instant) {
        lock.withLock { cursorSpace.pointerSent(picture: picture, wire: wire, at: now) }
    }
    func mapCursorPosition(x: Int, y: Int, scale: Double, width: Int, height: Int) -> (x: Int, y: Int)? {
        lock.withLock { cursorSpace.map(x: x, y: y, scale: scale, width: width, height: height, at: .now) }
    }
    var framebufferSize: (width: Int, height: Int) { lock.withLock { (width, height) } }
    func cancel() { lock.withLock { cancelled = true; isReady = false } }
    private var failed: RFBError?
    var failure: RFBError? { lock.withLock { failed } }
    func fail(_ error: RFBError) { lock.withLock { failed = error; cancelled = true; isReady = false } }
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
