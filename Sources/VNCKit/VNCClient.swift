import Foundation
import OSLog

public struct VNCConfiguration: Sendable {
    public var host: String
    public var port: UInt16
    public var username: String
    public var password: String
    public var sharedSession: Bool
    public var clipboardEnabled: Bool

    public init(host: String, port: UInt16 = 5900, username: String = "", password: String,
                sharedSession: Bool = true, clipboardEnabled: Bool = false) {
        self.host = host; self.port = port; self.username = username; self.password = password
        self.sharedSession = sharedSession; self.clipboardEnabled = clipboardEnabled
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
    public init() {}
}

/// One RFB client connection. `run` performs the handshake, authentication and update loop and
/// returns when the server closes the connection, or throws with a specific failure. Input
/// methods may be called concurrently once `connected` has fired.
public final class VNCClient: Sendable {
    private static let logger = Logger(subsystem: "app.glassdt.vnc", category: "client")
    private let configuration: VNCConfiguration
    private let callbacks: VNCClientCallbacks
    private let source: any RFBByteSource
    private let sink: any RFBByteSink
    private let closeAction: @Sendable () async -> Void
    private let state = ClientState()

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
        self.source = source
        self.sink = sink
        self.closeAction = close
        state.setOpen(open)
    }

    public var isReady: Bool { state.ready }

    public func cancel() {
        state.cancel()
        let close = closeAction
        Task { await close() }
    }

    // MARK: Session

    public func run() async throws {
        do {
            try await state.open()
            try checkCancelled()
            let info = try await handshake()
            try await sendSetPixelFormat()
            try await sendSetEncodings()
            let framebuffer = try RFBFramebuffer(width: info.width, height: info.height)
            state.setFramebufferSize(width: info.width, height: info.height)
            state.setReady(true)
            callbacks.connected(info)
            try await sendFramebufferUpdateRequest(incremental: false, framebuffer: framebuffer)
            try await updateLoop(framebuffer: framebuffer)
        } catch {
            state.setReady(false)
            await closeAction()
            if state.isCancelled { throw RFBError.cancelled }
            throw error
        }
        state.setReady(false)
        await closeAction()
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

    private func sendSetPixelFormat() async throws {
        try await sink.write([0, 0, 0, 0] + RFBPixelFormat.client.wireBytes)
    }

    private func sendSetEncodings() async throws {
        let encodings = RFBEncoding.advertised
        var message: [UInt8] = [2, 0] + UInt16(encodings.count).bigEndianBytes
        for encoding in encodings { message += encoding.rawValue.bigEndianBytes }
        try await sink.write(message)
    }

    private func sendFramebufferUpdateRequest(incremental: Bool, framebuffer: RFBFramebuffer) async throws {
        try await sink.write([3, incremental ? 1 : 0] + UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes
                             + UInt16(framebuffer.width).bigEndianBytes + UInt16(framebuffer.height).bigEndianBytes)
    }

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

    private func requireReady() throws {
        guard state.ready, !state.isCancelled else { throw RFBError.connectionClosed }
    }

    // MARK: Server messages

    private func updateLoop(framebuffer: RFBFramebuffer) async throws {
        let decoder = RFBRectangleDecoder()
        while true {
            try checkCancelled()
            let type = try await source.u8()
            switch type {
            case 0:
                _ = try await source.u8()
                let count = Int(try await source.u16())
                var changed = false
                rectangles: for _ in 0..<count {
                    let header = try await source.read(12)
                    var reader = ByteReader(header)
                    let rect = RFBRectangle(x: Int(try reader.u16()), y: Int(try reader.u16()),
                                            width: Int(try reader.u16()), height: Int(try reader.u16()))
                    let encodingValue = try reader.s32()
                    guard let encoding = RFBEncoding(rawValue: encodingValue) else {
                        throw RFBError.protocolViolation("The server used encoding \(encodingValue), which was not requested.")
                    }
                    switch encoding {
                    case .lastRect:
                        break rectangles
                    case .cursor:
                        if rect.isEmpty { callbacks.cursor(nil) } else {
                            let image = try await RFBRectangleDecoder.decodeCursor(rect, from: source)
                            callbacks.cursor(image)
                        }
                    case .desktopSize:
                        try framebuffer.resize(width: rect.width, height: rect.height)
                        state.setFramebufferSize(width: rect.width, height: rect.height)
                        try await sendFramebufferUpdateRequest(incremental: false, framebuffer: framebuffer)
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
                            try await sendFramebufferUpdateRequest(incremental: false, framebuffer: framebuffer)
                            changed = true
                        } else if rect.y != 0, rect.x == 1 {
                            Self.logger.notice("event=resize-refused status=\(rect.y)")
                        }
                    default:
                        let validated = try rect.validated(in: framebuffer.width, framebuffer.height)
                        try await decoder.decode(validated, encoding: encoding, from: source, into: framebuffer)
                        changed = true
                    }
                }
                if changed { callbacks.frame(framebuffer.width, framebuffer.height, framebuffer.snapshot()) }
                try await sendFramebufferUpdateRequest(incremental: true, framebuffer: framebuffer)
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
}
