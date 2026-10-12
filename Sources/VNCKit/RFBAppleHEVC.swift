//
//  RFBAppleHEVC.swift
//  Glass Power Tools — VNCKit
//
//  HEVC pictures out of a Mac's media stream: RFC 7798 depacketization of RTP payload type 100 —
//  single NAL units, aggregation packets and fragmentation units — for a stream offered one tile a
//  frame, each picture of the whole display on one SSRC. Ported from remotex's `Reassembler` and
//  `Depacketizer` (`src/vnc_apple_media.rs`, MIT, Andrew Chen).
//
//  A gap in the sequence numbers drops the picture it fell in and every one after it until one the
//  stream can go on from: an IRAP picture, or, when every picture before the loss was handed on, the
//  Mac's refresh picture, which predicts only from one this side acknowledged.
//

import Foundation

enum RFBAppleHEVC {
    /// The type in a two-byte HEVC NAL header's first byte.
    static func nalType(_ first: UInt8) -> UInt8 { (first >> 1) & 0x3f }

    static let aggregation: UInt8 = 48
    static let fragmentation: UInt8 = 49
    static let vps: UInt8 = 32, sps: UInt8 = 33, pps: UInt8 = 34

    /// An IRAP picture (16–23), or a parameter set ahead of one.
    static func isRandomAccess(_ type: UInt8) -> Bool { (16...23).contains(type) || (32...34).contains(type) }

    /// One picture's NAL units, in order, without start codes.
    typealias AccessUnit = [[UInt8]]

    enum Depacketized: Equatable {
        /// Nothing complete yet.
        case pending
        /// A whole access unit, decodable from what came before it.
        case unit(AccessUnit)
        /// Packets were lost: everything up to the next picture the stream can go on from is
        /// dropped, and the Mac should be asked for one (`resumesAtRefresh` says which kind).
        case lost
    }

    /// One picture's packets, put back together. A picture ends at the packet with the marker bit,
    /// or where the timestamp moves on; a gap in the sequence numbers damages the picture it fell in.
    struct Reassembler {
        private var nextSequence: UInt16?
        private var timestamp: UInt32?
        private var unit: AccessUnit = []
        private var fragment: [UInt8]?
        private var damaged = false
        private var refresh = false

        struct Pushed { var lost: Bool; var whole: (unit: AccessUnit, refresh: Bool)? }

        /// One packet; nil for a duplicate, or a late one whose picture has gone.
        mutating func push(_ header: RFBAppleSRTP.Header, _ payload: ArraySlice<UInt8>) -> Pushed? {
            var lost = false
            if let expected = nextSequence {
                let ahead = header.sequence &- expected
                if ahead >= 0x8000 { return nil }
                lost = ahead != 0
            }
            nextSequence = header.sequence &+ 1
            if let timestamp, timestamp != header.timestamp, damaged || !unit.isEmpty {
                // The previous picture's last packet never came.
                damaged = true
                _ = finish()
            }
            damaged = damaged || lost
            timestamp = header.timestamp
            refresh = refresh || header.refresh
            parse(payload)
            return Pushed(lost: lost, whole: header.marker ? finish() : nil)
        }

        private mutating func parse(_ payload: ArraySlice<UInt8>) {
            let payload = Array(payload)
            guard payload.count >= 2 else { damaged = true; return }
            let type = RFBAppleHEVC.nalType(payload[0])
            switch type {
            case RFBAppleHEVC.aggregation:
                var rest = payload[2...]
                while rest.count >= 2 {
                    let size = Int(rest[rest.startIndex]) << 8 | Int(rest[rest.startIndex + 1])
                    guard size >= 2, rest.count >= 2 + size else { damaged = true; return }
                    unit.append(Array(rest[(rest.startIndex + 2)..<(rest.startIndex + 2 + size)]))
                    rest = rest.dropFirst(2 + size)
                }
            case RFBAppleHEVC.fragmentation:
                guard payload.count >= 3 else { damaged = true; return }
                let header = payload[2]
                let (start, end, kind) = (header & 0x80 != 0, header & 0x40 != 0, header & 0x3f)
                if start {
                    fragment = [(payload[0] & 0x81) | kind << 1, payload[1]] + payload[3...]
                } else if fragment != nil {
                    fragment! += payload[3...]
                } else {
                    damaged = true
                    return
                }
                if end, let nal = fragment {
                    unit.append(nal)
                    fragment = nil
                }
            default:
                unit.append(payload)
            }
        }

        /// Closes the picture: it, if it is whole.
        private mutating func finish() -> (unit: AccessUnit, refresh: Bool)? {
            let finished = unit, wasDamaged = damaged || fragment != nil, wasRefresh = refresh
            unit = []; damaged = false; fragment = nil; refresh = false
            return !wasDamaged && !finished.isEmpty ? (finished, wasRefresh) : nil
        }
    }

    /// Access units out of a stream that sends each picture whole.
    struct Depacketizer {
        private var ssrc: UInt32?
        private var packets = Reassembler()
        /// A picture the stream can start at has arrived since the last loss.
        private var synced = false
        /// Out of step by lost packets alone, with every picture before them handed on: a refresh
        /// picture predicts from one of those, so the stream goes on from it.
        private var resumable = false

        mutating func push(_ header: RFBAppleSRTP.Header, _ payload: ArraySlice<UInt8>) -> Depacketized {
            if ssrc != header.ssrc {
                // A new stream, after an offer: it starts with an IDR of its own.
                self = Depacketizer()
                ssrc = header.ssrc
            }
            guard let pushed = packets.push(header, payload) else { return .pending }
            var out = Depacketized.pending
            if pushed.lost {
                resumable = resumable || synced
                synced = false
                out = .lost
            }
            if header.marker {
                if let whole = pushed.whole, let unit = judge(whole) { return .unit(unit) }
                if !synced { out = .lost }
            }
            return out
        }

        /// Drop everything up to the next random-access picture: a unit this side could not keep was
        /// lost to every picture that predicts from it.
        mutating func resync() {
            synced = false
            resumable = false
        }

        /// A refresh picture is enough to go on from.
        var resumesAtRefresh: Bool { !synced && resumable }

        private mutating func judge(_ whole: (unit: AccessUnit, refresh: Bool)) -> AccessUnit? {
            if !synced, whole.refresh && resumable || whole.unit.contains(where: { RFBAppleHEVC.isRandomAccess(RFBAppleHEVC.nalType($0[0])) }) {
                synced = true
                resumable = false
            }
            return synced ? whole.unit : nil
        }
    }

    /// A keyframe or refresh this side is owed, asked for again every 500 ms until a picture settles
    /// it: the Mac drops a request within a second of its last keyframe, and a still screen sends
    /// nothing else to show it did.
    struct KeyframeRequest {
        enum Ask: Equatable { case refresh, keyframe }
        private var wanted: Ask?
        private var lastAsked: ContinuousClock.Instant?
        static let interval: Duration = .milliseconds(500)

        /// A keyframe wanted wins over a refresh.
        mutating func want(_ ask: Ask) {
            if wanted != .keyframe { wanted = ask }
        }

        mutating func settle() { wanted = nil; lastAsked = nil }

        /// What to send now, if anything.
        mutating func due(at now: ContinuousClock.Instant) -> Ask? {
            guard let wanted else { return nil }
            if let lastAsked, now - lastAsked < Self.interval { return nil }
            lastAsked = now
            return wanted
        }
    }
}
