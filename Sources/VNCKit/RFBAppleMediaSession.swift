//
//  RFBAppleMediaSession.swift
//  Glass Power Tools — VNCKit
//
//  One High Performance session's media stream, as remotex's `MediaStream` keeps it
//  (`src/vnc_apple_media.rs`, MIT, Andrew Chen): its identity (keys, SSRCs, call id), when an offer
//  may go out, what the Mac's replies change, and what the stream owes the session by when.
//
//  - **Ports first.** The Mac names its ports for the SetEncodings that lists encoding 1010, and
//    again after every display change, never in reply to an offer; each naming is good for one
//    offer. An offer sent before them can be answered before them.
//  - **One offer at a time.** A second offer while the first's capture was starting failed it
//    (`error 32000`), and the display stream it left crashed WindowServer when the virtual display
//    went away, logging the Mac's user out. No display change goes out while an offer is unanswered.
//  - **Deadlines.** Ports within 10 s of the encodings; an answer, each display's first picture and
//    the first sound within 10 s of an offer; then something on every leg at least every 48 s, as
//    Apple's viewer counts sixteen of its 3-second RTCP timeouts. A stream that misses one ends the
//    session, as it ends Apple's viewer's: there is no way back to RFB pixels.
//

import Foundation

public final class RFBAppleMediaSession: @unchecked Sendable {
    public typealias Size = (width: UInt16, height: UInt16)

    /// The legs the Mac named: the sound's port, and each display's picture's.
    public struct Ports: Sendable, Equatable {
        public var audio: UInt16
        public var videos: [UInt16]
    }

    /// One video leg's keys, and this side's SSRC on it.
    public struct VideoLeg: Sendable {
        public let keys: RFBAppleMedia.KeyPair
        public let ssrc: UInt32
    }

    public enum Offer: Equatable {
        /// The SetEncodings listing 1010 first, which the Mac names its ports for. Held for the rest
        /// of the session: to a viewer whose preferred codec is the stream the Mac sends no pixels,
        /// which keeps its two framing threads from writing records at once.
        case encodings
        /// The 0x1c offer for the displays.
        case configuration([UInt8])
    }

    static let streamStart: Duration = .seconds(10)
    static let streamSilence: Duration = .seconds(48)

    // The session's identity: every offer carries the same, and the Mac starts a fresh stream (new
    // SSRC, same ports) on each.
    public let sessionUUID: [UInt8]
    public let callID: String
    public let audioKeys: RFBAppleMedia.KeyPair
    public let audioSSRC: UInt32
    public let videos: [VideoLeg]
    /// The offer's bitrate entries, when this client caps them; nil offers Apple's.
    public let bitrates: [UInt64]?

    private let lock = NSLock()
    private var asked = false
    private var pending = false
    private var invited = false
    private var offered: [Size]?
    private var owed = Owed.nothing
    private(set) var ports: Ports?
    private var legPictured: [ContinuousClock.Instant?]
    private var legHeard: [ContinuousClock.Instant?]
    private var sounded: ContinuousClock.Instant?
    private var soundHeard: ContinuousClock.Instant?

    private enum Owed: Equatable {
        case nothing
        case ports(since: ContinuousClock.Instant)
        case answer(offered: ContinuousClock.Instant)
        case stream(offered: ContinuousClock.Instant)
    }

    public init(displays: Int = 1, bitrates: [UInt64]? = nil) {
        let uuid = UUID()
        sessionUUID = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        callID = uuid.uuidString.uppercased()
        audioKeys = .random()
        audioSSRC = UInt32.random(in: 1 ... .max)
        videos = (0..<min(max(1, displays), RFBAppleMedia.maximumDisplays)).map { _ in
            VideoLeg(keys: .random(), ssrc: UInt32.random(in: 1 ... .max))
        }
        self.bitrates = bitrates
        legPictured = Array(repeating: nil, count: videos.count)
        legHeard = Array(repeating: nil, count: videos.count)
    }

    /// What to send toward a stream for displays of `sizes` backing pixels, which the session's
    /// displays now are with nothing about to change them: first the encodings, then, once the Mac
    /// has named its ports for them, the offer. Nothing while an offer is out, while the stream runs
    /// at those sizes, or for sizes that are not one per leg.
    public func offer(sizes: [Size], at now: ContinuousClock.Instant) throws -> Offer? {
        try lock.withLock {
            guard !pending, sizes.count == videos.count, offered.map({ !Self.same($0, sizes) }) ?? true else { return nil }
            if !asked {
                asked = true
                owed = .ports(since: now)
                return .encodings
            }
            guard invited else {
                if owed == .nothing { owed = .ports(since: now) }
                return nil
            }
            invited = false
            pending = true
            offered = sizes
            owed = .stream(offered: now)
            legPictured = Array(repeating: nil, count: videos.count)
            return .configuration(try configuration(sizes))
        }
    }

    private func configuration(_ sizes: [Size]) throws -> [UInt8] {
        let audio = try RFBAppleMedia.offer(mode: RFBAppleMedia.modeAudio, blob: RFBAppleMedia.audioOfferBlob(ssrc: audioSSRC), callID: callID)
        var legs: [(offer: [UInt8], keys: RFBAppleMedia.KeyPair)] = []
        for (leg, size) in zip(videos, sizes) {
            let blob = RFBAppleMedia.videoOfferBlob(ssrc: leg.ssrc, width: size.width, height: size.height, tiles: 1, bitrates: bitrates)
            legs.append((try RFBAppleMedia.offer(mode: RFBAppleMedia.modeVideo, blob: blob, callID: callID), leg.keys))
        }
        var flags = RFBAppleMedia.flag60FPS | RFBAppleMedia.flagNoCursor
        if legs.count > 1 { flags |= RFBAppleMedia.flag60FPSSecond }
        return try RFBAppleMedia.configurationMessage(flags: flags, sessionUUID: sessionUUID, audioOffer: audio, audioKeys: audioKeys, videos: legs)
    }

    /// What an encoding-1010 rectangle changed.
    public struct ReplyOutcome: Equatable {
        /// The Mac named ports this side has not bound yet: bind them.
        public var bind: Ports?
        /// A stream offered for the displays went down: the Mac named its ports again, which it does
        /// after every display change. No picture comes until the offer that naming allows.
        public var streamDown: Bool
    }

    /// Acts on an encoding-1010 rectangle's body. Throws when the Mac refused the stream or
    /// described one this side cannot receive; Apple's viewer shows the refusal and closes.
    public func reply(_ body: [UInt8]) throws -> ReplyOutcome {
        try lock.withLock {
            switch try RFBAppleMedia.reply(body) {
            case let .ports(audio, video, video2):
                let named = Ports(audio: audio, videos: [video] + (video2.map { [$0] } ?? []))
                guard named.videos.count == videos.count else {
                    throw RFBError.protocolViolation("The Mac named \(named.videos.count) picture streams for the \(videos.count) virtual displays asked for.")
                }
                invited = true
                if case .ports = owed { owed = .nothing }
                let down = offered != nil
                if down { stopStream() }
                guard ports != named else { return ReplyOutcome(bind: nil, streamDown: down) }
                ports = named
                return ReplyOutcome(bind: named, streamDown: down)
            case let .answer(answered):
                guard answered == videos.count else {
                    throw RFBError.protocolViolation("The Mac answered \(answered) picture streams of the \(videos.count) offered.")
                }
                pending = false
                if case .answer = owed { owed = .nothing }
            case .error(type: 1, subCode: 1):
                throw RFBError.unsupported("Another viewer already has this Mac's High Performance picture; a Mac gives it to one viewer at a time.")
            case let .error(type, subCode):
                throw RFBError.unsupported("The Mac refused the High Performance picture (error \(type), \(subCode)).")
            case .other:
                break
            }
            return ReplyOutcome(bind: nil, streamDown: false)
        }
    }

    /// The display changed: the Mac stops every leg and starts them again only on an offer. Until
    /// then the stream owes nothing but an answer to an offer still out.
    public func displayChanged() { lock.withLock { stopStream() } }

    private func stopStream() {
        offered = nil
        switch owed {
        case .stream(let at) where pending, .answer(let at) where pending: owed = .answer(offered: at)
        default: owed = .nothing
        }
    }

    /// An offer is out that the Mac has not answered: no display change may go out meanwhile.
    public var awaitingAnswer: Bool { lock.withLock { pending } }

    /// The sizes the running (or starting) stream was offered for.
    public var offeredSizes: [Size]? { lock.withLock { offered } }

    // MARK: What the receiver heard

    /// An authentic packet on display `leg`'s leg, a picture's or a report.
    public func heard(leg: Int, at now: ContinuousClock.Instant) { lock.withLock { if leg < legHeard.count { legHeard[leg] = now } } }

    /// A picture of display `leg` came, decoded at `size`: one of the size offered meets the offer.
    public func pictured(leg: Int, size: Size, at now: ContinuousClock.Instant) {
        lock.withLock {
            guard leg < legPictured.count, let offered, leg < offered.count, Self.same([offered[leg]], [size]) else { return }
            legPictured[leg] = now
            legHeard[leg] = now
        }
    }

    /// An authentic sound packet (`sound`) or a report on the sound's leg.
    public func soundHeard(sound: Bool, at now: ContinuousClock.Instant) {
        lock.withLock {
            if sound { sounded = now }
            soundHeard = now
        }
    }

    // MARK: Deadlines

    /// Why the session ends at `now`, if the stream is overdue.
    public func overdue(at now: ContinuousClock.Instant) -> RFBError? {
        lock.withLock {
            switch owed {
            case .nothing: return nil
            case .ports(let since):
                return now - since >= Self.streamStart ? .unsupported("The Mac did not open its High Performance picture within ten seconds.") : nil
            case .answer(let offered):
                return now - offered >= Self.streamStart ? .unsupported("The Mac did not answer the High Performance offer within ten seconds.") : nil
            case .stream(let offered):
                for leg in videos.indices {
                    let last = legPictured[leg].flatMap { pictured in max(pictured, legHeard[leg] ?? pictured) }
                    if let last, now - last < Self.streamSilence { continue }
                    if last == nil, now - offered < Self.streamStart { continue }
                    if last == nil, pending { return .unsupported("The Mac did not answer the High Performance offer within ten seconds.") }
                    if last == nil {
                        let port = ports.map { " (UDP \($0.videos[leg]))" } ?? ""
                        return .connectionFailed("No High Performance picture arrived within ten seconds\(port). A firewall or a network that blocks UDP between this device and the Mac looks like this; Standard quality works without it.")
                    }
                    return .connectionFailed("The Mac's High Performance picture stopped.")
                }
                let sound = sounded.flatMap { sounded in max(sounded, soundHeard ?? sounded) }
                if let sound, now - sound < Self.streamSilence { return nil }
                if sound == nil, now - offered < Self.streamStart { return nil }
                if sound == nil {
                    let port = ports.map { " (UDP \($0.audio))" } ?? ""
                    return .connectionFailed("No High Performance sound arrived within ten seconds\(port). A firewall or a network that blocks UDP between this device and the Mac looks like this.")
                }
                return .connectionFailed("The Mac's High Performance sound stopped.")
            }
        }
    }

    private static func same(_ a: [Size], _ b: [Size]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.width == $1.width && $0.height == $1.height }
    }
}
