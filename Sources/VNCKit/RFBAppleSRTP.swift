//
//  RFBAppleSRTP.swift
//  Glass Power Tools — VNCKit
//
//  The media stream's protection and reports (RFC 3711, RFC 4585, and AVConference's own), as a
//  Mac's High Performance stream uses them: AES-256 counter mode with an HMAC-SHA1-80 tag, keyed from
//  the 46-byte masters this side put in its offer (`RFBAppleMediaNegotiation.swift`). Ported from
//  remotex (`src/vnc_apple_media.rs`, MIT, Andrew Chen) and checked against the vectors its
//  independent Python implementation made, the one that read the Mac's own packets.
//
//  Every packet in is authenticated before it is decrypted; an authentic one no newer than one
//  already received is dropped. Every report out is SRTCP under this side's keys. The Mac stops a
//  stream that hears no report from its viewer for a few seconds.
//

import CommonCrypto
import Foundation

enum RFBAppleSRTP {
    static let tagBytes = 10

    /// Why a datagram was not one this side could use.
    enum Failure: Error, Equatable {
        /// Not RTP version 2, or too short to be.
        case notRTP
        /// An RTCP packet, told apart by its second byte.
        case rtcp
        /// The authentication tag does not match.
        case forged
        /// A duplicate, or older than a packet already received.
        case stale
    }

    /// The session keys of one direction of one leg: RFC 3711 §4.3 with a key derivation rate of
    /// 0, from labels `base` (encryption), `base + 1` (authentication) and `base + 2` (salt) — 0 for
    /// SRTP, 3 for SRTCP.
    struct SessionKeys {
        private let cipher: AESBlocks
        let authentication: [UInt8]
        /// The 14-byte session salt.
        let salt: [UInt8]

        init(master: [UInt8], base: UInt8) throws {
            guard master.count == RFBAppleMedia.masterKeyBytes else { throw RFBError.invalidConfiguration("An SRTP master key is 46 bytes.") }
            let masterCipher = try AESBlocks(key: Array(master[0..<32]))
            let masterSalt = Array(master[32..<46])
            func derive(_ label: UInt8, _ count: Int) throws -> [UInt8] {
                // x = key_id ⊕ salt, the label at bits 48–55 of the 112: byte 7 of the salt.
                var iv = masterSalt + [0, 0]
                iv[7] ^= label
                var out = [UInt8](repeating: 0, count: count)
                try masterCipher.counterXOR(iv: iv, &out[...])
                return out
            }
            cipher = try AESBlocks(key: try derive(base, 32))
            authentication = try derive(base + 1, 20)
            salt = try derive(base + 2, 14)
        }

        /// RFC 3711 §4.1.1: the salt, the SSRC and the packet index, shifted 16 bits for the counter.
        func iv(ssrc: UInt32, index: UInt64) -> [UInt8] {
            var iv = salt + [0, 0]
            let ssrcBytes = ssrc.bigEndianBytes
            for offset in 0..<4 { iv[4 + offset] ^= ssrcBytes[offset] }
            let indexBytes = (index & 0xffff_ffff_ffff).bigEndianBytes
            for offset in 0..<6 { iv[8 + offset] ^= indexBytes[2 + offset] }
            return iv
        }

        func crypt(_ data: inout ArraySlice<UInt8>, ssrc: UInt32, index: UInt64) throws {
            try cipher.counterXOR(iv: iv(ssrc: ssrc, index: index), &data)
        }

        /// The HMAC-SHA1 tag over `parts`, cut to 80 bits.
        func tag(_ parts: [ArraySlice<UInt8>]) -> [UInt8] {
            var context = CCHmacContext()
            authentication.withUnsafeBytes { CCHmacInit(&context, CCHmacAlgorithm(kCCHmacAlgSHA1), $0.baseAddress, 20) }
            for part in parts { part.withUnsafeBytes { CCHmacUpdate(&context, $0.baseAddress, $0.count) } }
            var full = [UInt8](repeating: 0, count: 20)
            full.withUnsafeMutableBytes { CCHmacFinal(&context, $0.baseAddress) }
            return Array(full[0..<RFBAppleSRTP.tagBytes])
        }
    }

    /// An RTP packet's header, and where its payload sits in the datagram.
    struct Header: Equatable {
        var payloadType: UInt8
        var marker: Bool
        var sequence: UInt16
        var timestamp: UInt32
        var ssrc: UInt32
        /// The Mac's mark on a picture predicted only from one this side acknowledged: its answer
        /// to `refreshRequest`.
        var refresh: Bool
        /// The payload, without the authentication tag.
        var payload: Range<Int>
    }

    /// The header extension's profile on the Mac's video packets, less the bits that vary, and the
    /// bit that marks a refresh picture.
    static let extensionProfile: UInt16 = 0x9301
    static let extensionVaries: UInt16 = 0x0030
    static let extensionRefresh: UInt16 = 0x0020

    /// RTCP (packet types 200–207 in the whole second byte) is told apart first.
    static func header(_ data: [UInt8]) throws(Failure) -> Header {
        guard data.count >= 12, data[0] >> 6 == 2 else { throw .notRTP }
        guard !(200...207).contains(data[1]) else { throw .rtcp }
        func u16(_ at: Int) -> UInt16 { UInt16(data[at]) << 8 | UInt16(data[at + 1]) }
        var at = 12 + 4 * Int(data[0] & 0x0f)
        var refresh = false
        if data[0] & 0x10 != 0 {
            guard data.count >= at + 4 else { throw .notRTP }
            let profile = u16(at)
            refresh = profile & ~extensionVaries == extensionProfile && profile & extensionRefresh != 0
            at += 4 + 4 * Int(u16(at + 2))
        }
        guard data.count >= at + tagBytes else { throw .notRTP }
        return Header(payloadType: data[1] & 0x7f, marker: data[1] & 0x80 != 0, sequence: u16(2),
                      timestamp: UInt32(u16(4)) << 16 | UInt32(u16(6)), ssrc: UInt32(u16(8)) << 16 | UInt32(u16(10)),
                      refresh: refresh, payload: at..<(data.count - tagBytes))
    }

    /// The receiving side of one leg's SRTP.
    struct Receiver {
        private let keys: SessionKeys
        /// For each SSRC heard from lately, the highest sequence number authenticated and its
        /// rollover counter; every offer starts a stream with a new SSRC.
        private(set) var last: [(ssrc: UInt32, sequence: UInt16, roc: UInt32)] = []
        static let remembered = 4

        init(master: [UInt8]) throws { keys = try SessionKeys(master: master, base: 0) }

        /// RFC 3711 Appendix A: the rollover counter `sequence` most likely belongs to.
        func guessROC(ssrc: UInt32, sequence: UInt16) -> UInt32 {
            guard let known = last.first(where: { $0.ssrc == ssrc }) else { return 0 }
            if known.sequence < 0x8000 {
                return sequence &- known.sequence > 0x8000 && sequence > known.sequence ? known.roc &- 1 : known.roc
            }
            return sequence < known.sequence &- 0x8000 ? known.roc &+ 1 : known.roc
        }

        /// For a test: the last packet heard from `ssrc`.
        mutating func remember(ssrc: UInt32, sequence: UInt16, roc: UInt32) { last = [(ssrc, sequence, roc)] }

        /// Authenticates and decrypts `data` in place; the payload is then in the clear at
        /// `header.payload`.
        mutating func unprotect(_ data: inout [UInt8]) throws(Failure) -> Header {
            let header = try RFBAppleSRTP.header(data)
            let roc = guessROC(ssrc: header.ssrc, sequence: header.sequence)
            let end = header.payload.upperBound
            guard keys.tag([data[0..<end], roc.bigEndianBytes[...]]) == Array(data[end...]) else { throw .forged }
            let index = UInt64(roc) << 16 | UInt64(header.sequence)
            if let at = last.firstIndex(where: { $0.ssrc == header.ssrc }) {
                guard index > UInt64(last[at].roc) << 16 | UInt64(last[at].sequence) else { throw .stale }
                last.remove(at: at)
            } else if last.count == Self.remembered {
                last.removeFirst()
            }
            var payload = data[header.payload]
            do { try keys.crypt(&payload, ssrc: header.ssrc, index: index) } catch { throw .forged }
            data.replaceSubrange(header.payload, with: payload)
            last.append((header.ssrc, header.sequence, roc))
            return header
        }
    }

    /// The sending side of one SRTCP stream: RFC 3711 §3.4, every packet encrypted under a 31-bit
    /// index of its own.
    struct ReportSender {
        private let keys: SessionKeys
        private var index: UInt32 = 0

        init(master: [UInt8]) throws { keys = try SessionKeys(master: master, base: 3) }

        /// The first eight bytes in the clear, the rest encrypted, then `E || index` and the tag.
        mutating func protect(_ report: [UInt8]) -> [UInt8] {
            precondition(report.count >= 8, "an RTCP packet has an eight-byte header")
            let ssrc = UInt32(report[4]) << 24 | UInt32(report[5]) << 16 | UInt32(report[6]) << 8 | UInt32(report[7])
            var body = report[8...]
            try? keys.crypt(&body, ssrc: ssrc, index: UInt64(index))
            var out = Array(report[0..<8]) + body + (0x8000_0000 | index).bigEndianBytes
            out += keys.tag([out[...]])
            index = (index + 1) & 0x7fff_ffff
            return out
        }
    }

    /// The receiving side of one SRTCP stream: the Mac's reports, about one a second on each leg,
    /// authenticated for liveness and never decrypted.
    struct ReportReceiver {
        private let keys: SessionKeys
        /// The highest index authenticated from each sender, for as long as the keys.
        private var last: [UInt32: UInt32] = [:]

        init(master: [UInt8]) throws { keys = try SessionKeys(master: master, base: 3) }

        mutating func authenticate(_ data: [UInt8]) throws(Failure) {
            guard data.count >= 8 + 4 + tagBytes, data[0] >> 6 == 2 else { throw .notRTP }
            let end = data.count - tagBytes
            guard keys.tag([data[0..<end]]) == Array(data[end...]) else { throw .forged }
            let ssrc = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
            let index = (UInt32(data[end - 4]) << 24 | UInt32(data[end - 3]) << 16 | UInt32(data[end - 2]) << 8 | UInt32(data[end - 1])) & 0x7fff_ffff
            if let known = last[ssrc], index <= known { throw .stale }
            last[ssrc] = index
        }
    }

    // MARK: Reports

    /// A receiver report with no report blocks. The Mac stops a stream that hears nothing from its
    /// receiver for a few seconds.
    static func receiverReport(ssrc: UInt32) -> [UInt8] { [0x80, 201, 0, 1] + ssrc.bigEndianBytes }

    /// AVConference's acknowledgement of a picture this side has whole, by its RTP timestamp: an APP
    /// packet named 5. The Mac's encoder keeps the newest acknowledged picture as a long-term
    /// reference, so a loss can be mended without a keyframe. Alone in its datagram.
    static func referenceAcknowledgement(ssrc: UInt32, timestamp: UInt32) -> [UInt8] {
        [0x80, 204, 0, 3] + ssrc.bigEndianBytes + [0, 0, 0, 5] + timestamp.bigEndianBytes
    }

    /// AVConference's request for a picture to go on from after a loss: payload-specific feedback of
    /// format 2 carrying the stream's size. The Mac answers with a refresh picture, or an IDR.
    static func refreshRequest(ssrc: UInt32, mediaSSRC: UInt32, width: UInt16, height: UInt16) -> [UInt8] {
        [0x82, 206, 0, 3] + ssrc.bigEndianBytes + mediaSSRC.bigEndianBytes + width.bigEndianBytes + height.bigEndianBytes
    }

    /// A Picture Loss Indication (RFC 4585 §6.3.1): the Mac answers with an IDR, though not within a
    /// second of its last keyframe.
    static func pictureLoss(ssrc: UInt32, mediaSSRC: UInt32) -> [UInt8] {
        [0x81, 206, 0, 2] + ssrc.bigEndianBytes + mediaSSRC.bigEndianBytes
    }
}

/// AES in counter mode over ECB blocks: the keystream from `iv`, its whole 128 bits the counter,
/// XORed into the data.
final class AESBlocks: @unchecked Sendable {
    private let cryptor: CCCryptorRef
    private let lock = NSLock()

    init(key: [UInt8]) throws {
        var made: CCCryptorRef?
        let status = key.withUnsafeBytes {
            CCCryptorCreate(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            $0.baseAddress, $0.count, nil, &made)
        }
        guard status == kCCSuccess, let made else { throw RFBError.resourceLimit("The media stream's cipher could not be created.") }
        cryptor = made
    }

    deinit { CCCryptorRelease(cryptor) }

    func counterXOR(iv: [UInt8], _ data: inout ArraySlice<UInt8>) throws {
        guard !data.isEmpty else { return }
        let blocks = (data.count + 15) / 16
        var counters = [UInt8](repeating: 0, count: blocks * 16)
        var counter = iv
        for block in 0..<blocks {
            counters.replaceSubrange((block * 16)..<(block * 16 + 16), with: counter)
            var carry = 1
            for byte in (0..<16).reversed() where carry != 0 {
                let sum = Int(counter[byte]) + carry
                counter[byte] = UInt8(sum & 0xff)
                carry = sum >> 8
            }
        }
        var keystream = [UInt8](repeating: 0, count: counters.count)
        var moved = 0
        let status = lock.withLock {
            counters.withUnsafeBytes { input in
                keystream.withUnsafeMutableBytes { output in
                    CCCryptorUpdate(cryptor, input.baseAddress, input.count, output.baseAddress, output.count, &moved)
                }
            }
        }
        guard status == kCCSuccess, moved == counters.count else { throw RFBError.resourceLimit("The media stream could not be decrypted.") }
        var offset = 0
        for index in data.indices {
            data[index] ^= keystream[offset]
            offset += 1
        }
    }
}

/// What the Mac's rate controller hears from this side: the `RCTL` report Apple's viewer sends every
/// 50 ms on the picture's leg. The controller moves on the one-way delay alone (the notes, "Rate
/// control").
struct RFBAppleRateFeedback {
    static let videoClock = 24_000.0
    /// The bandwidth estimate the report carries, in kbit/s: the controller's ceiling.
    static let reportedBandwidth: UInt16 = 60_000

    private let epoch: ContinuousClock.Instant
    /// The Mac's SSRC for the stream the rest describes; a new one starts the report again.
    private var ssrc: UInt32 = 0
    private var last: (timestamp: UInt32, at: ContinuousClock.Instant)?
    private var received: UInt32 = 0
    private var delay = OneWayDelay()

    init(epoch: ContinuousClock.Instant) { self.epoch = epoch }

    /// An authentic picture packet.
    mutating func received(ssrc: UInt32, timestamp: UInt32, at: ContinuousClock.Instant) {
        if ssrc != self.ssrc { self = RFBAppleRateFeedback(epoch: epoch); self.ssrc = ssrc }
        last = (timestamp, at)
        received &+= 1
        delay.sample(timestamp: timestamp, at: at)
    }

    /// The one-way delay the next report carries, in seconds.
    var oneWayDelay: Double { delay.delay }

    /// The report from `ssrc` at `now`, once a picture packet has arrived to echo. The Mac takes it
    /// only alone in its datagram.
    func report(ssrc: UInt32, at now: ContinuousClock.Instant) -> [UInt8]? {
        guard let last else { return nil }
        func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
        let held = UInt16(min(0xffff, max(0, (seconds(now - last.at) * 1000).rounded(.down))))
        let clock = UInt16(truncatingIfNeeded: UInt64(max(0, seconds(now - epoch)) * 1024))
        let reported = UInt16(min(Double(UInt16.max), delay.delay * 8192))
        var report: [UInt8] = [0x80, 204, 0, 7] + ssrc.bigEndianBytes + Array("RCTL".utf8) + [0x85, 0, 0, 4]
        report += UInt16(truncatingIfNeeded: last.timestamp >> 8).bigEndianBytes + [0, 0, 0, 0]
        report += held.bigEndianBytes + clock.bigEndianBytes + reported.bigEndianBytes
        report += UInt16(received & 0xfff).bigEndianBytes + Self.reportedBandwidth.bigEndianBytes
        return report
    }

    /// Apple's receiver's one-way relative delay: each picture's first packet gives a lag, its
    /// arrival less its RTP time, both from the stream's first picture; a short average follows the
    /// lag, a long one settles on its floor, and the delay is how far the short one stands above it.
    struct OneWayDelay {
        private var first: ContinuousClock.Instant?
        private var previous: UInt32 = 0
        private var ticks: UInt64 = 0
        private var short = 0.0, long = 0.0
        private(set) var delay = 0.0
        /// A lag this far from either average is a clock that jumped, not a queue.
        static let spurious = 30.0

        mutating func sample(timestamp: UInt32, at: ContinuousClock.Instant) {
            guard let first else { restart(timestamp, at); return }
            // A later packet of the same picture, or one out of order.
            let step = Int32(bitPattern: timestamp &- previous)
            guard step > 0 else { return }
            previous = timestamp
            ticks += UInt64(step)
            let elapsed = at - first
            let lag = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                - Double(ticks) / RFBAppleRateFeedback.videoClock
            if lag - short > Self.spurious || long - lag > Self.spurious { restart(timestamp, at); return }
            long = 0.9999 * long + 0.0001 * lag
            short = 0.9 * short + 0.1 * lag
            delay = short - long
            if delay < 0 { long = short; delay = 0 }
        }

        private mutating func restart(_ timestamp: UInt32, _ at: ContinuousClock.Instant) {
            self = OneWayDelay()
            first = at
            previous = timestamp
        }
    }
}
