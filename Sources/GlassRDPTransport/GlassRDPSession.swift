import CoreImage
import CoreVideo
import Foundation
import OSLog
import RDPKit

/// A session owns one transport. `connect` starts it; terminal results arrive in `events`.
/// Consume `frames` and `events` once each for the lifetime of this object.
public actor GlassRDPSession {
    private static let logger = Logger(subsystem: "app.glassdt.rdp", category: "session")
    public nonisolated let frames: AsyncStream<GlassRDPFrame>
    public nonisolated let events: AsyncStream<GlassRDPEvent>
    private let frameContinuation: AsyncStream<GlassRDPFrame>.Continuation
    private let eventContinuation: AsyncStream<GlassRDPEvent>.Continuation
    private var worker: Task<Void, Never>?
    private var activeID: UUID?
    private var cancellation: RDPConnectionCancellation?
    private var controls: Controls?
    private var stopRequested = false
    private var inputState = RDPInputStateTracker()

    public init() {
        (frames, frameContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (events, eventContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(128))
    }

    deinit {
        cancellation?.cancel()
        frameContinuation.finish()
        eventContinuation.finish()
    }

    public func connect(_ configuration: GlassRDPConfiguration) throws {
        guard worker == nil else { throw GlassRDPError.alreadyConnected }
        let engineConfiguration = try Self.engineConfiguration(configuration)
        let id = UUID()
        Self.logger.notice("event=connect attempt=\(id.uuidString, privacy: .public) width=\(configuration.width) height=\(configuration.height) scale=\(configuration.desktopScaleFactor) graphics=\(configuration.graphicsMode.rawValue, privacy: .public)")
        let cancel = RDPConnectionCancellation()
        let controls = Controls()
        self.activeID = id; self.cancellation = cancel; self.controls = controls
        stopRequested = false
        inputState = RDPInputStateTracker()
        eventContinuation.yield(.state(.connecting))
        let eventSink = eventContinuation
        let frameSink = frameContinuation
        worker = Task.detached(priority: .userInitiated) { [weak self, engineConfiguration] in
            let result = Self.run(engineConfiguration, controls: controls, cancellation: cancel,
                                  frames: frameSink, events: eventSink)
            await self?.finished(id: id, error: result)
        }
    }

    /// What the engine is asked for, from what the app saved.
    nonisolated static func engineConfiguration(_ configuration: GlassRDPConfiguration) throws -> RDPConnectionConfiguration {
        let host = configuration.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, configuration.port > 0, !configuration.username.isEmpty,
              (200...8192).contains(configuration.width), (200...8192).contains(configuration.height),
              configuration.width.isMultiple(of: 2) else { throw GlassRDPError.invalidConfiguration }
        var engineConfiguration = RDPConnectionConfiguration(
            host: host, port: configuration.port,
            credentials: try RDPCredentials.validated(username: configuration.username,
                                                      domain: configuration.domain, password: configuration.password),
            graphicsFrameCaptureLimit: nil,
            desktopWidth: UInt16(configuration.width), desktopHeight: UInt16(configuration.height),
            desktopScaleFactor: UInt32(configuration.desktopScaleFactor),
            clipboardEnabled: configuration.clipboardEnabled, audioPlaybackEnabled: configuration.audioEnabled,
            graphicsCapabilityProfile: profile(configuration.graphicsMode)
        )
        engineConfiguration.requireNetworkLevelAuthentication = configuration.requiresNLA
        if let fingerprint = configuration.approvedCertificateSHA256 {
            guard let pin = RDPServerCertificateTrustKey(host: host, port: configuration.port, sha256: fingerprint) else {
                throw GlassRDPError.invalidConfiguration
            }
            engineConfiguration.certificatePolicy = .pinned(pin)
        }
        return engineConfiguration
    }

    /// The engine's capability profile for a mode: H.264 4:2:0 is graphics pipeline 8.1 with AVC420
    /// enabled; without H.264 is 8.0, which has none (MS-RDPEGFX 2.2.3).
    nonisolated static func profile(_ mode: GlassRDPGraphicsMode) -> RDPGraphicsCapabilityProfile {
        switch mode {
        case .automatic: .automatic
        case .h264: .avc420
        case .withoutH264: .legacy
        }
    }

    public func disconnect() async {
        Self.logger.notice("event=disconnect-requested")
        stopRequested = true
        releaseInputs()
        cancellation?.cancel()
        await worker?.value
    }

    public func keyboard(scancode: UInt16, extended: Bool = false, isDown: Bool, isRepeat: Bool = false) throws {
        let input = try readyInput()
        guard scancode <= 0xFF else { throw GlassRDPError.unsupported("The keyboard scancode is invalid.") }
        input.send(inputState.keyboard(scancode: .init(code: scancode, isExtended: extended),
                                       isReleased: !isDown, isRepeat: isRepeat))
    }

    public func sendText(_ text: String) throws {
        let input = try readyInput()
        guard input.supportsUnicodeInput else {
            throw GlassRDPError.unsupported("The server has not negotiated Unicode text input. Use keyboard scancodes.")
        }
        input.send(text.utf16.flatMap { [.unicode(codeUnit: $0, isReleased: false), .unicode(codeUnit: $0, isReleased: true)] })
    }

    public func movePointer(x: Int, y: Int) throws {
        let input = try readyInput()
        input.send(inputState.pointerMove(to: .init(x: UInt16(clamping: x), y: UInt16(clamping: y))))
    }

    public func pointerButton(button: GlassRDPPointerButton, isDown: Bool, x: Int, y: Int) throws {
        let input = try readyInput()
        let remoteButton: RDPPointerButton = switch button {
        case .left: .left; case .right: .right; case .middle: .middle; case .back: .extended1; case .forward: .extended2
        }
        if (remoteButton == .extended1 || remoteButton == .extended2) && !input.supportsExtendedPointerButtons {
            throw GlassRDPError.unsupported("The server has not negotiated extended pointer buttons.")
        }
        if let event = inputState.pointerButton(remoteButton, isDown: isDown,
                                               at: .init(x: UInt16(clamping: x), y: UInt16(clamping: y))) {
            input.send(event)
        }
    }

    public func scroll(vertical: Int, horizontal: Int = 0, x: Int, y: Int) throws {
        let input = try readyInput()
        guard horizontal == 0 || input.supportsHorizontalWheel else {
            throw GlassRDPError.unsupported("The server has not negotiated horizontal scrolling.")
        }
        let point = RDPRemotePoint(x: UInt16(clamping: x), y: UInt16(clamping: y))
        if vertical != 0 { input.send(.verticalWheel(rotation: vertical, x: point.x, y: point.y)) }
        if horizontal != 0 { input.send(.horizontalWheel(rotation: horizontal, x: point.x, y: point.y)) }
    }

    public func releaseInputs() {
        controls?.snapshot.input?.send(inputState.releasePressedInputs())
    }

    public func synchronize(capsLock: Bool, numLock: Bool = true, scrollLock: Bool = false) throws {
        let input = try readyInput()
        var flags: RDPToggleKeyFlags = []
        if capsLock { flags.insert(.capsLock) }
        if numLock { flags.insert(.numLock) }
        if scrollLock { flags.insert(.scrollLock) }
        input.send(inputState.synchronizationEvents(toggleFlags: flags))
    }

    public func resize(width: Int, height: Int, desktopScale: Int = 100) throws {
        guard let display = controls?.snapshot.display else {
            throw GlassRDPError.unsupported("The server has not negotiated dynamic display resizing.")
        }
        guard Self.capabilities(display.capabilities).supports(width: width, height: height),
              (100...500).contains(desktopScale) else {
            throw GlassRDPError.unsupported("The requested desktop size exceeds the negotiated display limits.")
        }
        Self.logger.notice("event=resize-request width=\(width) height=\(height) scale=\(desktopScale)")
        display.sendSingleMonitorLayout(width: UInt32(width), height: UInt32(height),
                                        desktopScaleFactor: UInt32(desktopScale), deviceScaleFactor: 100)
    }

    public func sendClipboard(_ content: GlassClipboardContent) throws {
        guard let clipboard = controls?.snapshot.clipboard else {
            throw GlassRDPError.unsupported("The remote computer hasn't opened its clipboard to this app yet.")
        }
        clipboard.publishLocalContent(RDPClipboardRichContent(text: content.text, html: content.html,
                                                              rtf: content.rtf, png: content.png))
    }

    private func readyInput() throws -> RDPInputSession {
        guard let input = controls?.snapshot.input, cancellation?.isCancelled == false else {
            throw GlassRDPError.notConnected
        }
        return input
    }

    private func finished(id: UUID, error: String?) {
        guard activeID == id else { return }
        let cancelled = stopRequested
        Self.logger.notice("event=finished attempt=\(id.uuidString, privacy: .public) cancelled=\(cancelled) failed=\(error != nil)")
        worker = nil; activeID = nil; controls = nil; cancellation = nil
        inputState = RDPInputStateTracker()
        if !cancelled, let error { eventContinuation.yield(.state(.failed(error))) }
        else { eventContinuation.yield(.state(.disconnected)) }
    }

    private nonisolated static func run(
        _ configuration: RDPConnectionConfiguration, controls: Controls, cancellation: RDPConnectionCancellation,
        frames: AsyncStream<GlassRDPFrame>.Continuation, events: AsyncStream<GlassRDPEvent>.Continuation
    ) -> String? {
        let converter = FrameConverter()
        let decode = RDPLatestFrameDecodeQueue(
            shouldCancel: { cancellation.isCancelled },
            onDecoded: { presentation, receivedAt, decodedAt, timing in
                guard !cancellation.isCancelled else { return }
                do {
                    let frame = try converter.copy(presentation.imageBuffer, receivedAt: receivedAt,
                                                   decodedAt: decodedAt, hardware: timing.usesHardwareAcceleration)
                    controls.noteFrame()
                    frames.yield(frame)
                } catch {
                    controls.setFailure(error.localizedDescription)
                    cancellation.cancel()
                }
            },
            onDecodeFailed: { _, error in controls.setFailure(error) },
            onSkippedFrames: { _, _ in }
        )
        defer { decode.cancel() }
        let report = RDPPreflightClient().run(
            configuration: configuration,
            onGraphicsFrame: { frame in
                try decode.submitAndWait(frame, receivedAt: Date(), shouldContinue: { !cancellation.isCancelled }).requireDecoded()
            },
            onRemotePointer: { pointer in
                switch pointer {
                case let .position(point): events.yield(.cursor(.position(x: Int(point.x), y: Int(point.y))))
                case .hidden: events.yield(.cursor(.hidden))
                case .systemDefault: events.yield(.cursor(.systemDefault))
                case let .image(image), let .cachedImage(image):
                    events.yield(.cursor(.image(.init(width: Int(image.width), height: Int(image.height),
                        hotSpotX: Int(image.hotSpot.x), hotSpotY: Int(image.hotSpot.y), xorBitsPerPixel: Int(image.xorBitsPerPixel),
                        xorMask: image.xorMaskData, andMask: image.andMaskData, paletteEntries: image.paletteEntries))))
                case .unresolvedCachedImage: events.yield(.cursor(.systemDefault))
                }
            },
            onInputReady: { input in
                controls.setInput(input)
                events.yield(.state(.connected))
            },
            onDisplayControlReady: { display in
                controls.setDisplay(display)
                events.yield(.displayCapabilities(capabilities(display.capabilities)))
            },
            onClipboardReady: { clipboard in
                logger.notice("event=clipboard-ready")
                defer { events.yield(.clipboardReady) }
                // Every format the server offers, not only its text (D42a).
                clipboard.setRemoteContentHandler { rich in
                    events.yield(.clipboard(GlassClipboardContent(text: rich.text, html: rich.html,
                                                                  rtf: rich.rtf, png: rich.png)))
                }
                controls.setClipboard(clipboard)
            },
            onClipboardText: { events.yield(.clipboard(GlassClipboardContent(text: $0))) },
            onAudioSample: { sample in
                if sample.format.isPCM16Bit {
                    events.yield(.audio(.init(sampleRate: Double(sample.format.samplesPerSecond),
                                             channels: Int(sample.format.channelCount), data: sample.data)))
                }
            },
            onCertificate: { certificate in
                events.yield(.certificate(.init(host: configuration.host, port: configuration.port,
                    sha256: certificate.sha256, systemTrusted: certificate.trusted,
                    isAccepted: configuration.certificatePolicy.accepts(certificate, host: configuration.host, port: configuration.port))))
            }, cancellation: cancellation
        )
        // Which graphics the server chose, for "the colours smear" (B-X6): the version it confirmed
        // says whether H.264 4:4:4 was on the table.
        if let version = report.rdpGraphicsSelectedCapabilityVersion {
            logger.notice("event=graphics profile=\(configuration.graphicsCapabilityProfile.rawValue, privacy: .public) version=\(String(format: "0x%08X", version), privacy: .public) flags=\(String(format: "0x%08X", report.rdpGraphicsSelectedCapabilityFlags ?? 0), privacy: .public)")
        }
        // Whether the server gave the clipboard a channel at all, and whether anything crossed it:
        // "never offered" and "offered late" are different fixes.
        if configuration.clipboardEnabled {
            logger.notice("event=clipboard channel=\(report.rdpClipboardChannelID.map(String.init) ?? "none", privacy: .public) ready=\(controls.snapshot.clipboard != nil) messages=\(report.rdpClipboardMessages?.count ?? 0)")
        }
        if let failure = controls.snapshot.failure { return failure }
        if report.status == "failure" {
            if controls.snapshot.receivedFrame, Self.endedNormally(report) { return nil }
            return report.error ?? "The remote connection failed."
        }
        if controls.snapshot.input == nil, !cancellation.isCancelled {
            return "The server ended connection setup before the desktop was ready (\(report.stage))."
        }
        return nil
    }

    /// Signing out of the remote desktop ends the session. Some servers announce it, some tear the
    /// session down, and some simply close the transport once the desktop is gone. Enumerating the
    /// wordings that mean "ended" proved fragile, so this asks the opposite question: once a desktop
    /// has actually been shown, an ending is normal unless it looks like a fault.
    ///
    /// A fault is a timeout or a failure that never reached the live graphics stage. Those keep their
    /// message and still raise the recovery panel with its Reconnect button. MS-RDPBCGR error info
    /// and disconnect reasons:
    /// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/6c74b3b9-1c1f-4a89-9b1e-0f3b0b0a1e2c
    private nonisolated static func endedNormally(_ report: RDPPreflightReport) -> Bool {
        let announcedSignOut: Set<String> = [
            "ERRINFO_RPC_INITIATED_DISCONNECT", "ERRINFO_RPC_INITIATED_LOGOFF",
            "ERRINFO_RPC_INITIATED_DISCONNECT_BY_USER", "ERRINFO_LOGOFF_BY_USER",
        ]
        if let name = report.rdpRemoteTerminationErrorInfoName, announcedSignOut.contains(name) { return true }
        if report.rdpRemoteTerminationDisconnectReason == 3 { return true }
        // Anything that ends the live session without timing out is treated as the session ending.
        guard report.stage == "rdp-graphics-dynamic-channel" else { return false }
        guard let error = report.error else { return true }
        return !error.contains("timed out")
    }

    private nonisolated static func capabilities(_ value: RDPDisplayControlCapabilities) -> GlassRDPDisplayCapabilities {
        let partial = UInt64(value.maxNumMonitors) * UInt64(value.maxMonitorAreaFactorA)
        let total = partial.multipliedReportingOverflow(by: UInt64(value.maxMonitorAreaFactorB))
        return .init(maximumMonitors: value.maxNumMonitors, maximumArea: total.overflow ? UInt64.max : total.partialValue)
    }
}

private final class Controls: @unchecked Sendable {
    struct Snapshot {
        var input: RDPInputSession?
        var display: RDPDisplayControlSession?
        var clipboard: RDPClipboardSession?
        var failure: String?
        var receivedFrame = false
    }
    private let lock = NSLock()
    private var state = Snapshot()
    var snapshot: Snapshot { lock.withLock { state } }
    func setInput(_ input: RDPInputSession) { lock.withLock { state.input = input } }
    func setDisplay(_ display: RDPDisplayControlSession) { lock.withLock { state.display = display } }
    func setClipboard(_ clipboard: RDPClipboardSession) { lock.withLock { state.clipboard = clipboard } }
    func setFailure(_ error: String) { lock.withLock { state.failure = error } }
    func noteFrame() { lock.withLock { state.receivedFrame = true } }
}

/// The decode queue serializes calls here. Decode remains in RDPKit/VideoToolbox/Metal;
/// immutable publication currently makes one BGRA copy, with CoreImage conversion for YUV buffers.
final class FrameConverter {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var sequence: UInt64 = 0

    func copy(_ source: CVPixelBuffer, receivedAt: Date, decodedAt: Date, hardware: Bool?) throws -> GlassRDPFrame {
        let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
        guard (1...8192).contains(width), (1...8192).contains(height) else { throw GlassRDPError.invalidFrame }
        let bytesPerRow = width * 4
        var data = Data(count: bytesPerRow * height)
        if CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA {
            guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { throw GlassRDPError.invalidFrame }
            defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
            guard let sourceAddress = CVPixelBufferGetBaseAddress(source),
                  CVPixelBufferGetBytesPerRow(source) >= bytesPerRow else { throw GlassRDPError.invalidFrame }
            let sourceStride = CVPixelBufferGetBytesPerRow(source)
            data.withUnsafeMutableBytes { destination in
                for row in 0..<height {
                    destination.baseAddress!.advanced(by: row * bytesPerRow)
                        .copyMemory(from: sourceAddress.advanced(by: row * sourceStride), byteCount: bytesPerRow)
                }
            }
        } else {
            let image = CIImage(cvPixelBuffer: source)
            data.withUnsafeMutableBytes { destination in
                context.render(image, toBitmap: destination.baseAddress!, rowBytes: bytesPerRow,
                               bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .BGRA8,
                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            }
        }
        sequence &+= 1
        return try GlassRDPFrame(width: width, height: height, bytesPerRow: bytesPerRow, pixels: data,
                                 sequence: sequence, receivedAt: receivedAt, decodedAt: decodedAt,
                                 usesHardwareAcceleration: hardware)
    }
}
