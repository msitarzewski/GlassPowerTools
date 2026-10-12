//
//  RFBAppleMediaReceiver.swift
//  Glass Power Tools — VNCKit
//
//  The receiving end of a Mac's High Performance stream, as remotex's `Receiver` runs it
//  (`src/vnc_apple_media.rs`, MIT, Andrew Chen): a UDP socket for the sound and one for each
//  display's picture, bound to the port numbers the Mac named on this side's address of the RFB
//  connection and connected to the same numbers on the Mac's, which is where it sends from and to.
//  Address and port reuse let another session on this device bind them too; being connected is what
//  hands each its own Mac's packets.
//
//  One thread reads all of them and keeps the stream alive: a receiver report on each leg every
//  second (the Mac stops a stream that hears nothing for a few seconds), the rate report every 50 ms
//  on the picture's leg, an acknowledgement of each picture handed on (which lets a loss be mended
//  with a refresh rather than a keyframe), and the refresh or keyframe a loss owes, again every
//  500 ms until it comes. Pictures are decoded on a queue of their own; falling eight behind drops
//  to the next keyframe. The picture's socket asks for a 4 MB receive buffer: the Mac sends each
//  picture as one burst at the link's speed, and remotex measured a default-sized buffer losing a
//  fifth of a stream's datagrams, keyframes among them.
//

import CoreVideo
import Foundation
import OSLog

public final class RFBAppleMediaReceiver: @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.glassdt.vnc", category: "media")
    static let videoReceiveBuffer: Int32 = 4 << 20
    static let rateInterval: Duration = .milliseconds(50)
    static let reportInterval: Duration = .seconds(1)
    static let decodeQueueLimit = 8
    static let silentStart: Duration = .seconds(5)

    /// A decoded picture of display `leg`.
    public typealias Pictures = @Sendable (_ leg: Int, _ picture: CVPixelBuffer) -> Void
    /// One AAC-ELD access unit of the sound, as the Mac sent it.
    public typealias Sound = @Sendable (_ unit: [UInt8]) -> Void

    private let session: RFBAppleMediaSession
    private let pictures: Pictures
    private let sound: Sound
    private let failed: @Sendable (RFBError) -> Void
    private let audioSocket: Int32
    private var legs: [Leg]
    private var audio: AudioLeg
    private let stopLock = NSLock()
    private var stopping = false
    private var thread: Thread?

    private struct AudioLeg {
        var srtp: RFBAppleSRTP.Receiver
        var reports: RFBAppleSRTP.ReportReceiver
        var rtcp: RFBAppleSRTP.ReportSender
        let ssrc: UInt32
        var packets = 0
    }

    private final class Leg {
        let index: Int
        let socket: Int32
        let port: UInt16
        var srtp: RFBAppleSRTP.Receiver
        var reports: RFBAppleSRTP.ReportReceiver
        var rtcp: RFBAppleSRTP.ReportSender
        let ssrc: UInt32
        var mediaSSRC: UInt32 = 0
        var depacketizer = RFBAppleHEVC.Depacketizer()
        var feedback: RFBAppleRateFeedback
        var request = RFBAppleHEVC.KeyframeRequest()
        var unacknowledged: UInt32?
        let decoder = RFBAppleVideoDecoder()
        let decodeQueue: DispatchQueue
        let state = DecodeState()
        // For the log.
        var packets = 0, forged = 0, behind = 0, asks = 0, units = 0

        init(index: Int, socket: Int32, port: UInt16, keys: RFBAppleMedia.KeyPair, ssrc: UInt32, epoch: ContinuousClock.Instant) throws {
            self.index = index; self.socket = socket; self.port = port; self.ssrc = ssrc
            srtp = try RFBAppleSRTP.Receiver(master: keys.fromMac)
            reports = try RFBAppleSRTP.ReportReceiver(master: keys.fromMac)
            rtcp = try RFBAppleSRTP.ReportSender(master: keys.toMac)
            feedback = RFBAppleRateFeedback(epoch: epoch)
            decodeQueue = DispatchQueue(label: "app.glassdt.vnc.media.decode.\(index)", qos: .userInteractive)
        }
    }

    /// Shared between the receiving thread and the leg's decode queue.
    private final class DecodeState: @unchecked Sendable {
        private let lock = NSLock()
        private var queued = 0
        private var failed = false
        func enqueue() -> Bool { lock.withLock { guard queued < RFBAppleMediaReceiver.decodeQueueLimit else { return false }; queued += 1; return true } }
        func dequeue(failed didFail: Bool) { lock.withLock { queued -= 1; failed = failed || didFail } }
        /// A unit failed to decode since the last look: the stream needs a keyframe.
        func takeFailure() -> Bool { lock.withLock { defer { failed = false }; return failed } }
    }

    /// Binds the ports `session` was told and gets ready to receive; `start` begins.
    public convenience init(local: String, peer: String, session: RFBAppleMediaSession, ports: RFBAppleMediaSession.Ports,
                            pictures: @escaping Pictures, sound: @escaping Sound, failed: @escaping @Sendable (RFBError) -> Void) throws {
        try self.init(local: local, peer: peer, session: session, ports: ports, peerPorts: ports,
                      pictures: pictures, sound: sound, failed: failed)
    }

    /// `peerPorts` other than `ports` only for a test, whose stand-in Mac shares this device's address.
    init(local: String, peer: String, session: RFBAppleMediaSession, ports: RFBAppleMediaSession.Ports,
         peerPorts: RFBAppleMediaSession.Ports, pictures: @escaping Pictures, sound: @escaping Sound,
         failed: @escaping @Sendable (RFBError) -> Void) throws {
        self.session = session
        self.pictures = pictures
        self.sound = sound
        self.failed = failed
        let epoch = ContinuousClock.now
        var opened: [Int32] = []
        do {
            audioSocket = try Self.socket(local: local, peer: peer, port: ports.audio, peerPort: peerPorts.audio, buffer: nil)
            opened.append(audioSocket)
            var legs: [Leg] = []
            for (index, (port, video)) in zip(ports.videos, session.videos).enumerated() {
                let socket = try Self.socket(local: local, peer: peer, port: port, peerPort: peerPorts.videos[index],
                                             buffer: Self.videoReceiveBuffer)
                opened.append(socket)
                legs.append(try Leg(index: index, socket: socket, port: port, keys: video.keys, ssrc: video.ssrc, epoch: epoch))
            }
            self.legs = legs
            audio = AudioLeg(srtp: try RFBAppleSRTP.Receiver(master: session.audioKeys.fromMac),
                             reports: try RFBAppleSRTP.ReportReceiver(master: session.audioKeys.fromMac),
                             rtcp: try RFBAppleSRTP.ReportSender(master: session.audioKeys.toMac), ssrc: session.audioSSRC)
        } catch {
            for socket in opened { close(socket) }
            throw error
        }
        VNCDiagnostics.note(Self.logger, .default, category: "media", "event=media-bound sound=\(ports.audio) video=\(ports.videos.map(String.init).joined(separator: ","))")
    }

    deinit { stop() }

    public func start() {
        let thread = Thread { [self] in run() }
        thread.name = "app.glassdt.vnc.media"
        thread.qualityOfService = .userInteractive
        stopLock.withLock { self.thread = thread }
        thread.start()
    }

    /// Stops the thread; the sockets close as it ends.
    public func stop() { stopLock.withLock { stopping = true } }

    private var isStopping: Bool { stopLock.withLock { stopping } }

    // MARK: Sockets

    static func socket(local: String, peer: String, port: UInt16, peerPort: UInt16, buffer: Int32?) throws -> Int32 {
        func address(_ host: String, _ port: UInt16) throws -> (storage: sockaddr_storage, length: socklen_t, family: Int32) {
            var hints = addrinfo()
            hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV
            hints.ai_socktype = SOCK_DGRAM
            var found: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, String(port), &hints, &found) == 0, let found else {
                throw RFBError.connectionFailed("The High Performance picture could not be received at \(host).")
            }
            defer { freeaddrinfo(found) }
            var storage = sockaddr_storage()
            withUnsafeMutableBytes(of: &storage) { $0.copyMemory(from: UnsafeRawBufferPointer(start: found.pointee.ai_addr, count: Int(found.pointee.ai_addrlen))) }
            return (storage, found.pointee.ai_addrlen, found.pointee.ai_family)
        }
        var at = try address(local, port), to = try address(peer, peerPort)
        let fd = Darwin.socket(at.family, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw RFBError.connectionFailed("The High Performance picture's socket could not be made (\(errno)).") }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, socklen_t(MemoryLayout<Int32>.size))
        if var buffer {
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &buffer, socklen_t(MemoryLayout<Int32>.size))
            var granted: Int32 = 0, length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &granted, &length)
            if granted < buffer {
                VNCDiagnostics.note(logger, .error, category: "media", "event=media-buffer port=\(port) granted=\(granted) asked=\(buffer)")
            }
        }
        let bound = withUnsafePointer(to: &at.storage) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, at.length) } }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw RFBError.connectionFailed("UDP port \(port) could not be opened for the High Performance picture (\(code)).")
        }
        let connected = withUnsafePointer(to: &to.storage) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, to.length) } }
        guard connected == 0 else {
            let code = errno
            close(fd)
            throw RFBError.connectionFailed("UDP port \(port) could not be pointed at the Mac (\(code)).")
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    private static func send(_ socket: Int32, _ bytes: [UInt8]) {
        _ = bytes.withUnsafeBytes { Darwin.send(socket, $0.baseAddress, $0.count, 0) }
    }

    // MARK: The loop

    private func run() {
        var datagram = [UInt8](repeating: 0, count: 65_536)
        let started = ContinuousClock.now
        var nextReport = started, nextRate = started, nextLog = started + .seconds(10)
        var warnedSilent = false
        var failure: RFBError?
        defer {
            close(audioSocket)
            for leg in legs { close(leg.socket) }
            if let failure {
                VNCDiagnostics.note(Self.logger, .error, category: "media", "event=media-stopped reason=\(failure.localizedDescription)")
                failed(failure)
            }
        }
        var descriptors = [pollfd(fd: audioSocket, events: Int16(POLLIN), revents: 0)]
            + legs.map { pollfd(fd: $0.socket, events: Int16(POLLIN), revents: 0) }
        while !isStopping {
            let now = ContinuousClock.now
            let wait = min(nextReport, nextRate) - now
            let milliseconds = max(0, min(50, Int32(Double(wait.components.seconds) * 1000 + Double(wait.components.attoseconds) / 1e15)))
            let ready = poll(&descriptors, nfds_t(descriptors.count), milliseconds)
            if ready < 0, errno != EINTR {
                failure = .connectionFailed("The High Performance picture's receiver failed (\(errno)).")
                break
            }
            let arrived = ContinuousClock.now
            if descriptors[0].revents & Int16(POLLIN) != 0 {
                while case let count = recv(audioSocket, &datagram, datagram.count, 0), count > 0 {
                    takeSound(Array(datagram[0..<count]), at: arrived)
                }
            }
            for (index, leg) in legs.enumerated() where descriptors[index + 1].revents & Int16(POLLIN) != 0 {
                while case let count = recv(leg.socket, &datagram, datagram.count, 0), count > 0 {
                    take(leg, Array(datagram[0..<count]), at: arrived)
                }
            }
            let after = ContinuousClock.now
            for leg in legs {
                if leg.state.takeFailure() {
                    leg.depacketizer.resync()
                    leg.request.want(.keyframe)
                }
                acknowledge(leg)
                askForPicture(leg, at: after)
            }
            if after >= nextRate {
                nextRate = after + Self.rateInterval
                for leg in legs {
                    if let report = leg.feedback.report(ssrc: leg.ssrc, at: after) { Self.send(leg.socket, leg.rtcp.protect(report)) }
                }
            }
            if after >= nextReport {
                nextReport = after + Self.reportInterval
                Self.send(audioSocket, audio.rtcp.protect(RFBAppleSRTP.receiverReport(ssrc: audio.ssrc)))
                for leg in legs { Self.send(leg.socket, leg.rtcp.protect(RFBAppleSRTP.receiverReport(ssrc: leg.ssrc))) }
                if !warnedSilent, after - started >= Self.silentStart, legs.contains(where: { $0.packets == 0 }) {
                    warnedSilent = true
                    VNCDiagnostics.note(Self.logger, .error, category: "media", "event=media-silent ports=\(legs.map { String($0.port) }.joined(separator: ",")) sound=\(audio.packets)")
                }
            }
            if after >= nextLog {
                nextLog = after + .seconds(10)
                for leg in legs {
                    VNCDiagnostics.record(category: "media", "event=media-flow leg=\(leg.index) packets=\(leg.packets) units=\(leg.units) forged=\(leg.forged) behind=\(leg.behind) asks=\(leg.asks) delayMs=\(Int(leg.feedback.oneWayDelay * 1000)) sound=\(audio.packets)")
                    leg.units = 0
                }
            }
        }
    }

    private func takeSound(_ data: [UInt8], at now: ContinuousClock.Instant) {
        var data = data
        do {
            let header = try audio.srtp.unprotect(&data)
            audio.packets += 1
            session.soundHeard(sound: true, at: now)
            sound(Array(data[header.payload]))
        } catch .rtcp {
            if (try? audio.reports.authenticate(data)) != nil { session.soundHeard(sound: false, at: now) }
        } catch {}
    }

    private func take(_ leg: Leg, _ data: [UInt8], at now: ContinuousClock.Instant) {
        var data = data
        let header: RFBAppleSRTP.Header
        do {
            header = try leg.srtp.unprotect(&data)
        } catch .rtcp {
            if (try? leg.reports.authenticate(data)) != nil { session.heard(leg: leg.index, at: now) }
            return
        } catch .forged {
            leg.forged += 1
            if leg.forged <= 3 { VNCDiagnostics.note(Self.logger, .error, category: "media", "event=media-forged leg=\(leg.index)") }
            return
        } catch {
            return
        }
        session.heard(leg: leg.index, at: now)
        leg.feedback.received(ssrc: header.ssrc, timestamp: header.timestamp, at: now)
        leg.packets += 1
        if leg.packets == 1 {
            VNCDiagnostics.note(Self.logger, .default, category: "media", "event=media-flowing leg=\(leg.index) port=\(leg.port)")
        }
        if leg.mediaSSRC != header.ssrc {
            // A new stream, after an offer, starts with an IDR of its own.
            leg.request.settle()
            leg.unacknowledged = nil
        }
        leg.mediaSSRC = header.ssrc
        switch leg.depacketizer.push(header, data[header.payload]) {
        case .pending:
            break
        case .lost:
            leg.request.want(leg.depacketizer.resumesAtRefresh ? .refresh : .keyframe)
        case .unit(let unit):
            leg.request.settle()
            guard leg.state.enqueue() else {
                leg.behind += 1
                if leg.behind <= 3 { VNCDiagnostics.note(Self.logger, .error, category: "media", "event=media-behind leg=\(leg.index)") }
                leg.depacketizer.resync()
                leg.request.want(.keyframe)
                return
            }
            leg.units += 1
            leg.unacknowledged = header.timestamp
            let (decoder, state, index, session, pictures) = (leg.decoder, leg.state, leg.index, session, pictures)
            leg.decodeQueue.async {
                var failedToDecode = false
                do {
                    if let picture = try decoder.decode(unit) {
                        let size = (UInt16(clamping: CVPixelBufferGetWidth(picture)), UInt16(clamping: CVPixelBufferGetHeight(picture)))
                        session.pictured(leg: index, size: size, at: .now)
                        pictures(index, picture)
                    }
                } catch {
                    failedToDecode = true
                    VNCDiagnostics.note(Self.logger, .error, category: "media", "event=media-decode-failed leg=\(index) reason=\(error.localizedDescription)")
                }
                state.dequeue(failed: failedToDecode)
            }
        }
    }

    /// Tells the Mac's encoder of the picture just handed on, which it may predict a refresh from.
    private func acknowledge(_ leg: Leg) {
        guard let timestamp = leg.unacknowledged else { return }
        leg.unacknowledged = nil
        Self.send(leg.socket, leg.rtcp.protect(RFBAppleSRTP.referenceAcknowledgement(ssrc: leg.ssrc, timestamp: timestamp)))
    }

    /// Asks for the picture owed, once the leg's stream has named its SSRC.
    private func askForPicture(_ leg: Leg, at now: ContinuousClock.Instant) {
        guard leg.mediaSSRC != 0, let ask = leg.request.due(at: now) else { return }
        leg.asks += 1
        if ask == .refresh, let size = leg.decoder.size {
            Self.send(leg.socket, leg.rtcp.protect(RFBAppleSRTP.refreshRequest(ssrc: leg.ssrc, mediaSSRC: leg.mediaSSRC,
                                                                               width: UInt16(clamping: size.width), height: UInt16(clamping: size.height))))
        } else {
            Self.send(leg.socket, leg.rtcp.protect(RFBAppleSRTP.pictureLoss(ssrc: leg.ssrc, mediaSSRC: leg.mediaSSRC)))
        }
    }
}
