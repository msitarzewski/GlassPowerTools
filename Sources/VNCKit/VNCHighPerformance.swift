//
//  VNCHighPerformance.swift
//  Glass Power Tools — VNCKit
//
//  A session in a Mac's High Performance mode, as Apple's viewer and remotex run it: the Mac moves its
//  windows to a virtual display of this client's size and sends its picture as HEVC over the media
//  stream, its sound as AAC-ELD, while RFB carries input, the pointer's shapes and the negotiation.
//
//  1. After the record layer: `SetDisplayConfiguration` for the virtual display, then the opening
//     pixel format and encodings, one pixel armed once a second.
//  2. Once a layout shows the virtual display: the encodings with the media stream first, held for
//     the rest of the session; the Mac then sends no pixels and names its media ports.
//  3. On the ports: the receiver binds them, and the offer goes out (`RFBAppleMediaSession`).
//  4. Pictures arrive decoded and are handed on as the whole framebuffer; a layout or the ports
//     named again mean a display change, and the next offer follows the next naming.
//
//  A Mac that cannot hold the mode (its ServerInit lists no SetDisplayConfiguration) is shown in
//  Standard mode, and the session says why. A stream that fails ends the session: Apple's viewer has
//  no way back to RFB pixels either.
//

import CoreVideo
import Foundation
import OSLog

/// What a High Performance session asks of a Mac.
public struct VNCHighPerformance: Sendable, Equatable {
    /// The virtual display's size in points.
    public var width: Int
    public var height: Int
    /// Pixels per point: 2 makes a Retina display; the Mac does not round other ratios.
    public var density: Double
    /// The offer's bitrate entries, capping the Mac's encoder; nil offers Apple's (the rate controller
    /// then moves between 20 and 60 Mbit/s by the delay this side reports).
    public var bitrates: [UInt64]?

    public init(width: Int, height: Int, density: Double, bitrates: [UInt64]? = nil) {
        self.width = width; self.height = height
        self.density = density >= 1.5 ? 2 : 1
        self.bitrates = bitrates
    }

    var mode: RFBAppleMedia.VirtualMode { RFBAppleMedia.VirtualMode(points: (width, height), density: density) }

    /// Bitrate entries capping the Mac's encoder at `bitsPerSecond`, in the offer's six slots.
    public static func capped(at bitsPerSecond: UInt64) -> [UInt64] { Array(repeating: bitsPerSecond, count: 6) }
}

/// What a High Performance session is doing, for the person looking at it.
public enum VNCHighPerformanceStatus: Sendable, Equatable {
    /// The Mac cannot hold the mode, or this connection cannot ask; the session shows its physical
    /// displays instead.
    case unavailable(String)
    /// The virtual display is asked for and the stream negotiated: no picture yet.
    case starting
    /// The stream's pictures are arriving.
    case streaming
    /// The display changed and the stream is starting again.
    case restarting
}

/// The High Performance part of one client's state, read and written from the update loop, the
/// receiver's threads and the timers.
final class VNCMediaState: @unchecked Sendable {
    private let lock = NSLock()
    private var media: RFBAppleMediaSession?
    private var receiver: RFBAppleMediaReceiver?
    private var request: VNCHighPerformance?
    private var configuredAt: ContinuousClock.Instant?
    private var streaming = false
    private var pictures = 0

    var session: RFBAppleMediaSession? { lock.withLock { media } }
    var wanted: VNCHighPerformance? { lock.withLock { request } }

    func begin(_ request: VNCHighPerformance, session: RFBAppleMediaSession, at now: ContinuousClock.Instant) {
        lock.withLock { self.request = request; media = session; configuredAt = now }
    }

    func configuredFor(at now: ContinuousClock.Instant) -> Duration? { lock.withLock { configuredAt.map { now - $0 } } }

    func setReceiver(_ value: RFBAppleMediaReceiver?) {
        let old = lock.withLock { () -> RFBAppleMediaReceiver? in defer { receiver = value }; return receiver }
        old?.stop()
    }

    /// A picture arrived: true for the first since the stream (re)started.
    func notePicture() -> Bool { lock.withLock { pictures += 1; defer { streaming = true }; return !streaming } }
    func noteStreamDown() { lock.withLock { streaming = false } }
    var pictureCount: Int { lock.withLock { pictures } }

    func stop() { setReceiver(nil) }
}

extension VNCClient {
    static let mediaLogger = Logger(subsystem: "app.glassdt.vnc", category: "media")
    /// How long a layout of one display of another size than asked is waited on before its size is
    /// taken as the virtual display's: the Mac may hold the size under its ceiling.
    static let virtualDisplaySettle: Duration = .seconds(5)
    static let maximumMediaReplyBytes = 64 * 1024

    /// After the record layer: whether this session is High Performance, and if so the virtual
    /// display, sent before the opening messages as Apple's viewer sends it.
    func startHighPerformance(_ info: VNCServerInfo) async throws {
        guard let wanted = configuration.highPerformance else { return }
        guard info.negotiatedVersion == .apple else {
            highPerformanceUnavailable("This connection signs in without the Mac's own account, so it cannot ask for High Performance.")
            return
        }
        guard RFBAppleMedia.holdsHighPerformance(info) else {
            highPerformanceUnavailable("This Mac does not offer High Performance screen sharing; it needs macOS 14 or later on Apple silicon.")
            return
        }
        guard RFBAppleVideoDecoder.decodesHighPerformance else {
            highPerformanceUnavailable("This device cannot decode the Mac's High Performance picture (HEVC 4:4:4).")
            return
        }
        let session = RFBAppleMediaSession(displays: 1, bitrates: wanted.bitrates)
        mediaState.begin(wanted, session: session, at: .now)
        planner.setHighPerformance()
        let mode = wanted.mode
        try await sink.write(try RFBAppleMedia.setDisplayConfiguration([mode]))
        VNCDiagnostics.note(Self.mediaLogger, .default, category: "media", "event=hp-virtual-display pixels=\(mode.pixels.width)x\(mode.pixels.height) points=\(mode.points.width)x\(mode.points.height) capped=\(wanted.bitrates.map { "\($0.max() ?? 0)" } ?? "no")")
        callbacks.highPerformance(.starting)
    }

    private func highPerformanceUnavailable(_ reason: String) {
        VNCDiagnostics.note(Self.mediaLogger, .default, category: "media", "event=hp-unavailable reason=\(reason)")
        callbacks.highPerformance(.unavailable(reason))
    }

    /// An encoding-1010 rectangle: a `u16` size, then the Mac's reply about the stream.
    func readMediaReply() async throws {
        let length = Int(try await source.u16())
        guard length <= Self.maximumMediaReplyBytes else {
            throw RFBError.protocolViolation("The Mac sent a media stream reply of \(length) bytes.")
        }
        let body = try await source.read(length)
        guard let media = mediaState.session else {
            VNCDiagnostics.note(Self.mediaLogger, .error, category: "media", "event=hp-reply-unasked bytes=\(length)")
            return
        }
        let outcome = try media.reply(body)
        VNCDiagnostics.note(Self.mediaLogger, .default, category: "media", "event=hp-reply type=\(body.count >= 2 ? Int(body[1]) : -1) bind=\(outcome.bind.map { "\($0.audio),\($0.videos.map(String.init).joined(separator: ","))" } ?? "-") down=\(outcome.streamDown)")
        if outcome.streamDown {
            mediaState.noteStreamDown()
            callbacks.highPerformance(.restarting)
        }
        if let ports = outcome.bind { try await bindMedia(ports, session: media) }
    }

    private func bindMedia(_ ports: RFBAppleMediaSession.Ports, session: RFBAppleMediaSession) async throws {
        guard let addresses = await addressesAction?() else {
            throw RFBError.unsupported("This connection's addresses are unknown, so the Mac's High Performance picture cannot be received.")
        }
        let callbacks = callbacks, state = mediaState
        let receiver = try RFBAppleMediaReceiver(
            local: addresses.local, peer: addresses.peer, session: session, ports: ports,
            pictures: { [weak self] _, picture in
                guard let frame = VNCClient.frameData(picture) else { return }
                if state.notePicture() {
                    VNCDiagnostics.note(VNCClient.mediaLogger, .default, category: "media", "event=hp-first-picture size=\(frame.width)x\(frame.height)")
                    callbacks.highPerformance(.streaming)
                }
                guard self?.state.ready == true else { return }
                callbacks.frame(frame.width, frame.height, frame.data)
            },
            sound: { unit in callbacks.mediaSound(unit) },
            failed: { [weak self] error in self?.failSession(error) })
        mediaState.setReceiver(receiver)
        receiver.start()
    }

    /// Sends what the stream wants next, once the virtual display has settled: the encodings naming
    /// the stream, or the offer for the display.
    func offerMedia(framebufferWidth width: Int, height: Int) {
        guard let media = mediaState.session, !media.awaitingAnswer, let wanted = mediaState.wanted,
              planner.currentDisplays.count == 1, width > 0, height > 0 else { return }
        let mode = wanted.mode
        let matches = abs(width - Int(mode.pixels.width)) <= 2 && abs(height - Int(mode.pixels.height)) <= 2
        guard matches || (mediaState.configuredFor(at: .now).map { $0 >= Self.virtualDisplaySettle } ?? false) else { return }
        let size: RFBAppleMediaSession.Size = (UInt16(clamping: width), UInt16(clamping: height))
        do {
            switch try media.offer(sizes: [size], at: .now) {
            case .encodings?:
                VNCDiagnostics.note(Self.mediaLogger, .default, category: "media", "event=hp-encodings display=\(width)x\(height)")
                planner.preferMediaStream()
                pumpPlanner()
            case .configuration(let message)?:
                VNCDiagnostics.note(Self.mediaLogger, .default, category: "media", "event=hp-offer display=\(width)x\(height) bytes=\(message.count)")
                sendInOrder(message)
            case nil:
                break
            }
        } catch let error as RFBError {
            failSession(error)
        } catch {
            failSession(.protocolViolation(error.localizedDescription))
        }
    }

    /// A layout arrived: a size other than the one the stream was offered for is a display change.
    func mediaLayoutArrived(width: Int, height: Int) {
        guard let media = mediaState.session, let offered = media.offeredSizes?.first else { return }
        if Int(offered.width) != width || Int(offered.height) != height {
            media.displayChanged()
            mediaState.noteStreamDown()
            callbacks.highPerformance(.restarting)
        }
    }

    /// Why the session ends now, when the stream is overdue.
    func mediaOverdue() -> RFBError? { mediaState.session?.overdue(at: .now) }

    /// A decoded picture as the BGRA bytes the framebuffer hands on, without a copy where its rows
    /// are packed.
    static func frameData(_ picture: CVPixelBuffer) -> (width: Int, height: Int, data: Data)? {
        guard CVPixelBufferGetPixelFormatType(picture) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(picture, .readOnly) == kCVReturnSuccess else { return nil }
        let width = CVPixelBufferGetWidth(picture), height = CVPixelBufferGetHeight(picture)
        let row = CVPixelBufferGetBytesPerRow(picture)
        guard let base = CVPixelBufferGetBaseAddress(picture) else {
            CVPixelBufferUnlockBaseAddress(picture, .readOnly)
            return nil
        }
        if row == width * 4 {
            let retained = Unmanaged.passRetained(picture)
            let data = Data(bytesNoCopy: base, count: row * height, deallocator: .custom { _, _ in
                CVPixelBufferUnlockBaseAddress(retained.takeUnretainedValue(), .readOnly)
                retained.release()
            })
            return (width, height, data)
        }
        defer { CVPixelBufferUnlockBaseAddress(picture, .readOnly) }
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { destination in
            for line in 0..<height {
                (destination.baseAddress! + line * width * 4).copyMemory(from: base + line * row, byteCount: width * 4)
            }
        }
        return (width, height, data)
    }
}
