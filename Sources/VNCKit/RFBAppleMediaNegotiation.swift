//
//  RFBAppleMediaNegotiation.swift
//  Glass Power Tools — VNCKit
//
//  High Performance's negotiation, as Apple's viewer makes it: the virtual display a Mac sends its
//  picture of, the offer of a media stream, and the Mac's answers. Ported from remotex
//  (`src/vnc_apple_media.rs`, `src/vnc_apple.rs` and the notes' "The media stream" and "The High
//  Performance virtual display", MIT, Andrew Chen), whose offers are rebuilt byte for byte from the
//  ones Apple's own negotiator produced on macOS 26.6. Nothing here is documented by Apple.
//
//  In High Performance mode the picture and the sound do not come over RFB. The viewer creates a
//  virtual display (`SetDisplayConfiguration`, 0x1d), lists encoding 1010 first in `SetEncodings`,
//  and the Mac answers with its media ports (message 1). The viewer then offers a stream (0x1c,
//  `RFBMediaStreamServerConfiguration`): SRTP master keys it chose and two AVConference offers, one
//  for the sound and one for each display's picture, each a binary property list around a deflated
//  protobuf. The Mac answers (message 2) or refuses (message 3), and `ScreensharingAgent` sends HEVC
//  and AAC-ELD over UDP, from each port it named to the same port here (`RFBAppleMediaStream.swift`).
//
//  The Mac refuses an offer without sound, and mutes its own output while the sound leg runs.
//

import Foundation
import zlib

public enum RFBAppleMedia {
    /// `kSSVideoEncoding_AVCMediaStream`: listed first, the viewer takes its picture from the media
    /// stream, and the Mac's replies arrive as rectangles of it.
    public static let encoding: Int32 = 1010

    /// 0x1c flag bit 0: 60 frames a second, which the daemon sets anyway; the virtual display's
    /// refresh bounds the rate.
    static let flag60FPS: UInt32 = 0x1
    /// Bit 1: the same for a second display.
    static let flag60FPSSecond: UInt32 = 0x2
    /// Bit 2: capture without the pointer (`send cursor with video 0`), which keeps arriving as its
    /// own shape over RFB. Without it the pointer is drawn into every picture.
    static let flagNoCursor: UInt32 = 0x4

    /// The most displays a stream carries, one video leg each.
    public static let maximumDisplays = 2

    /// The `avcMediaStreamNegotiatorMode` of an audio offer, and of a screen-video offer.
    static let modeAudio: UInt8 = 8
    static let modeVideo: UInt8 = 7

    /// `avcMediaStreamOptionRemoteEndpointInfo`: the viewer's model and builds, as Apple's client on
    /// macOS 26.6 (25G83) reported them.
    static let remoteEndpointInfo: [UInt8] = [0x08, 0x00, 0x10, 0x01, 0x1a, 0x0d] + Array("VirtualMac2,1".utf8)
        + [0x22, 0x08] + Array("2215.5.1".utf8) + [0x2a, 0x05] + Array("25G83".utf8)

    /// The blob's `f6`: the negotiation library's name and version.
    static let viceroy = "Viceroy 1.7.0"
    /// The blob's `f13`, which differs between the two modes and was not decoded further.
    static let audioF13: UInt64 = 17_169_649_764_059_066_368
    static let videoF13: UInt64 = 17_169_649_764_516_085_760

    /// The blob's repeated `f9` entries, `(f1, f2, f3)`: the audio codecs (AAC-ELD `{16, 4100}`,
    /// AMR-NB `{1, 299}`, EVS `{4, 6500}`) and, with `f1 = 0`, bitrates in bits per second. The Mac's
    /// picture rate controller moves between 20 Mbit/s and the highest of these, capped at 60; an
    /// offer whose highest is under 20 holds the encoder at it (the notes, "Rate control").
    static let codecEntries: [(UInt64, UInt64, UInt64?)] = [
        (1, 299, nil),
        (4074, 0, 16_384),
        (0, 75_000_000, 524_288),
        (0, 20_000_000, 98_304),
        (0, 40_000_000, 12_288),
        (0, 60_000_000, 262_144),
        (16, 4100, nil),
        (0, 100_000_000, 1_048_576),
        (4, 6500, nil),
        (0, 6_000_000, 131_072),
    ]

    // MARK: The offers

    /// The audio offer's blob, before compression: one audio stream whose SSRC is `ssrc`.
    static func audioOfferBlob(ssrc: UInt32) -> [UInt8] {
        var blob = Protobuf()
        blob.uint(1, 1)
        blob.uint(2, 1)
        var stream = Protobuf()
        stream.uint(1, UInt64(ssrc))
        stream.uint(2, 0)
        stream.uint(3, 0)
        // The RTP payload types this side takes, one bit each; 0x1000 is AAC-ELD's 101. Apple's
        // viewer sends the same 0x5E7F. The Mac sets the sound's rate itself.
        stream.uint(4, 24_191)
        stream.uint(5, 0)
        stream.uint(6, 0)
        blob.message(3, stream)
        blobTail(&blob, codecs: codecEntries, f13: audioF13)
        return blob.bytes
    }

    /// The screen-video offer's blob: one stream at `width` × `height` backing pixels offering H.264
    /// (RTP payload 123) and HEVC (100), `tiles` pictures to a frame. The Mac answers with HEVC.
    /// `bitrates` replaces the offer's bitrate entries, in its order, when given.
    static func videoOfferBlob(ssrc: UInt32, width: UInt16, height: UInt16, tiles: UInt64,
                               bitrates: [UInt64]? = nil) -> [UInt8] {
        var blob = Protobuf()
        blob.uint(1, 1)
        blob.uint(2, 1)
        var stream = Protobuf()
        stream.uint(1, UInt64(ssrc))
        stream.uint(2, 0)
        stream.message(3, videoCodec(id: 123, levels: [1, 2, 1, 2],
                                     features: "FLS;MS:-1;LF:-1;LTR;CABAC;POS:0;EOD:1;HTS:2;RR:3;AR:4/3,5/8;XR:4/3,5/8;", f4: 1))
        stream.message(3, videoCodec(id: 100, levels: [1, 2],
                                     features: "FLS;LF:-1;POS:5;EOD:1;HTS:2;RR:3;POSE:4;AR:4/3,5/8;XR:4/3,5/8;", f4: 14))
        stream.uint(4, UInt64(width))
        stream.uint(5, UInt64(height))
        stream.uint(6, tiles)
        stream.uint(7, 1)
        stream.uint(8, 63)
        stream.uint(9, 1)
        stream.uint(12, 1)
        blob.message(5, stream)
        // Apple's entries, with {0, 40000000, 12288} moved to the front.
        var codecs = codecEntries
        codecs.insert(codecs.remove(at: 4), at: 0)
        if let bitrates {
            var next = bitrates.makeIterator()
            codecs = codecs.map { entry in entry.0 == 0 ? (0, next.next() ?? entry.1, entry.2) : entry }
        }
        blobTail(&blob, codecs: codecs, f13: videoF13)
        return blob.bytes
    }

    private static func videoCodec(id: UInt64, levels: [UInt64], features: String, f4: UInt64) -> Protobuf {
        var codec = Protobuf()
        codec.uint(1, id)
        for which in levels {
            var level = Protobuf()
            level.uint(1, 1)
            level.uint(2, which)
            level.uint(3, 50_115)
            level.uint(4, 0)
            codec.message(2, level)
        }
        codec.bytes(3, Array(features.utf8))
        codec.uint(4, f4)
        return codec
    }

    /// The tail every blob ends with: the library's name, `f8`, the codec list, `f13`, `f14 = 2`,
    /// `f16 = 0`.
    private static func blobTail(_ blob: inout Protobuf, codecs: [(UInt64, UInt64, UInt64?)], f13: UInt64) {
        blob.bytes(6, Array(viceroy.utf8))
        blob.uint(8, 0)
        for (f1, f2, f3) in codecs {
            var entry = Protobuf()
            entry.uint(1, f1)
            entry.uint(2, f2)
            if let f3 { entry.uint(3, f3) }
            blob.message(9, entry)
        }
        blob.uint(13, f13)
        blob.uint(14, 2)
        blob.uint(16, 0)
    }

    /// One AVConference offer: a binary property list of the negotiator mode, the compressed blob,
    /// the viewer's endpoint info and the call id.
    static func offer(mode: UInt8, blob: [UInt8], callID: String) throws -> [UInt8] {
        BinaryPropertyList.dictionary([
            ("avcMediaStreamOptionRemoteEndpointInfo", .data(remoteEndpointInfo)),
            ("avcMediaStreamNegotiatorMode", .integer(mode)),
            ("avcMediaStreamNegotiatorMediaBlob", .data(try ZlibDeflater.compressed(blob))),
            ("avcMediaStreamOptionCallID", .string(callID)),
        ])
    }

    // MARK: The 0x1c message

    /// An SRTP master key as the offer carries it: 32 bytes of AES-256 key and 14 of salt.
    public static let masterKeyBytes = 46

    /// One direction's keys of one leg, `(viewer to Mac, Mac to viewer)`.
    public struct KeyPair: Sendable, Equatable {
        public var toMac: [UInt8]
        public var fromMac: [UInt8]

        public init(toMac: [UInt8], fromMac: [UInt8]) { self.toMac = toMac; self.fromMac = fromMac }

        static func random() -> KeyPair {
            KeyPair(toMac: randomBytes(masterKeyBytes), fromMac: randomBytes(masterKeyBytes))
        }
    }

    /// `RFBMediaStreamServerConfiguration`, version 3:
    ///
    /// ```text
    /// +0x00 u8   0x1c, pad, u16 body length (everything after this field)
    /// +0x04 u16  version = 3, u32 flags
    /// +0x0a u16  audio offer length, video 1's, video 2's (0 for one display), u32 zero
    /// +0x14 16B  session UUID
    /// +0x24 46B  audio key viewer → Mac, then 46B Mac → viewer
    /// +0x80      the audio offer; then per display its two keys and its offer
    /// ```
    static func configurationMessage(flags: UInt32, sessionUUID: [UInt8], audioOffer: [UInt8], audioKeys: KeyPair,
                                     videos: [(offer: [UInt8], keys: KeyPair)]) throws -> [UInt8] {
        guard sessionUUID.count == 16, audioKeys.toMac.count == masterKeyBytes, audioKeys.fromMac.count == masterKeyBytes,
              !videos.isEmpty, videos.count <= maximumDisplays,
              videos.allSatisfy({ $0.keys.toMac.count == masterKeyBytes && $0.keys.fromMac.count == masterKeyBytes }) else {
            throw RFBError.invalidConfiguration("The media stream's offer is malformed.")
        }
        var message = [UInt8](repeating: 0, count: 0x80)
        message[0] = 0x1c
        message.replaceSubrange(4..<6, with: UInt16(3).bigEndianBytes)
        message.replaceSubrange(6..<10, with: flags.bigEndianBytes)
        message.replaceSubrange(0x0a..<0x0c, with: try length(audioOffer).bigEndianBytes)
        for (index, video) in videos.enumerated() {
            message.replaceSubrange((0x0c + 2 * index)..<(0x0e + 2 * index), with: try length(video.offer).bigEndianBytes)
        }
        message.replaceSubrange(0x14..<0x24, with: sessionUUID)
        message.replaceSubrange(0x24..<0x52, with: audioKeys.toMac)
        message.replaceSubrange(0x52..<0x80, with: audioKeys.fromMac)
        message += audioOffer
        for video in videos { message += video.keys.toMac + video.keys.fromMac + video.offer }
        message.replaceSubrange(2..<4, with: try length(Array(message[4...])).bigEndianBytes)
        return message
    }

    private static func length(_ bytes: [UInt8]) throws -> UInt16 {
        guard bytes.count <= Int(UInt16.max) else { throw RFBError.resourceLimit("The media stream's offer is too large.") }
        return UInt16(bytes.count)
    }

    static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        return bytes
    }

    // MARK: The replies

    /// What the Mac put in an encoding-1010 rectangle.
    public enum Reply: Sendable, Equatable {
        /// Message 1: the legs are being set up, the sound from and its reports to `audioPort`, the
        /// picture from `videoPort` (and a second display's from `video2Port`), on the Mac's address;
        /// this side receives on the same numbers. Sent for the SetEncodings naming 1010 and again
        /// after each display change, with no stream behind it until the next offer.
        case ports(audio: UInt16, video: UInt16, video2: UInt16?)
        /// Message 2: the offer was accepted, with an answer for this many video legs.
        case answer(videos: Int)
        /// Message 3: the Mac could not start the stream. Type 2: no configuration could be made of
        /// the offer; type 1, sub-code 1: another viewer has the stream.
        case error(type: UInt32, subCode: UInt32)
        case other(UInt16)
    }

    /// The body of an encoding-1010 rectangle, after its `u16` size.
    public static func reply(_ body: [UInt8]) throws -> Reply {
        guard body.count >= 8 else { throw RFBError.protocolViolation("A media stream reply of \(body.count) bytes has no header.") }
        var reader = ByteReader(body)
        let type = try reader.u16()
        switch type {
        case 1:
            guard body.count >= 36 else { throw RFBError.protocolViolation("The Mac's media ports message is \(body.count) bytes.") }
            func u16(_ at: Int) -> UInt16 { UInt16(body[at]) << 8 | UInt16(body[at + 1]) }
            func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) << 16 | UInt32(u16(at + 2)) }
            guard u32(10) & u32(16) & 1 != 0 else {
                throw RFBError.protocolViolation("The Mac's media ports message enabled no sound or no picture.")
            }
            return .ports(audio: u16(8), video: u16(14), video2: u32(22) & 1 != 0 ? u16(20) : nil)
        case 2:
            guard body.count >= 18 else { throw RFBError.protocolViolation("The Mac's media answer is \(body.count) bytes.") }
            func u16(_ at: Int) -> Int { Int(body[at]) << 8 | Int(body[at + 1]) }
            let (audio, video, video2) = (u16(8), u16(10), u16(12))
            guard body.count == 18 + audio + video + video2 else {
                throw RFBError.protocolViolation("The Mac's media answer is \(body.count) bytes, not the \(18 + audio + video + video2) it describes.")
            }
            return .answer(videos: video2 == 0 ? 1 : 2)
        case 3:
            guard body.count >= 16 else { throw RFBError.protocolViolation("The Mac's media error is \(body.count) bytes.") }
            _ = try reader.bytes(6)
            return .error(type: try reader.u32(), subCode: try reader.u32())
        default:
            return .other(type)
        }
    }

    // MARK: The virtual display

    /// One virtual display's mode: the pixels the Mac renders and the points windows occupy. A
    /// backing size twice the points makes a 2x display; the Mac does not round other ratios.
    public struct VirtualMode: Sendable, Equatable {
        public var pixels: (width: UInt16, height: UInt16)
        public var points: (width: UInt16, height: UInt16)

        public static func == (a: VirtualMode, b: VirtualMode) -> Bool {
            a.pixels == b.pixels && a.points == b.points
        }

        /// `points` at `density` (1 or 2), held under the fixed ceiling: a size past it shrinks and
        /// keeps its density, since the Mac answers one out of bounds with its old layout.
        public init(points: (width: Int, height: Int), density: Double) {
            func axis(_ value: Int, _ maximum: UInt32) -> (UInt16, UInt16) {
                let pixels = min(Double(maximum), max(1, (Double(value) * density).rounded()))
                return (UInt16(pixels), UInt16(max(1, (pixels / density).rounded())))
            }
            let (pixelWidth, pointWidth) = axis(points.width, RFBAppleMedia.maximumBackingWidth)
            let (pixelHeight, pointHeight) = axis(points.height, RFBAppleMedia.maximumBackingHeight)
            self.pixels = (pixelWidth, pixelHeight)
            self.points = (pointWidth, pointHeight)
        }
    }

    /// The virtual display's fixed backing ceiling. It is the descriptor's bound, not its mode:
    /// one set to the first mode refuses every later, larger size.
    static let maximumBackingWidth: UInt32 = 3840
    static let maximumBackingHeight: UInt32 = 2160
    /// The refresh asked for, which bounds the picture rate. 60 Hz sent about 57 pictures a second
    /// under a full-screen animation, 30 Hz sent 30.
    public static let refreshRate: Double = 60
    /// Dots per inch the descriptor's millimetres are derived with.
    static let nominalDPI: Float = 132

    /// `SetDisplayConfiguration` (0x1d): one virtual display per mode, each with that one mode.
    /// The first is always dynamic, so a reconnect turns the Mac's Dynamic resolution back on;
    /// the Mac creates a second to the right of the first. Names are Apple's viewer's.
    public static func setDisplayConfiguration(_ modes: [VirtualMode], refreshRate: Double = refreshRate) throws -> [UInt8] {
        guard !modes.isEmpty, modes.count <= maximumDisplays else {
            throw RFBError.invalidConfiguration("A Mac takes one or two virtual displays.")
        }
        var body = UInt16(1).bigEndianBytes + UInt16(modes.count).bigEndianBytes + UInt32(0).bigEndianBytes
        for (index, mode) in modes.enumerated() {
            var display = UInt16(descriptorHead + modeEntry).bigEndianBytes
            display += Array((index == 0 ? "Screen Sharing Virtual Display" : "Screen Sharing Virtual Display #\(index + 1)").utf8)
            display += [UInt8](repeating: 0, count: 0x7a - display.count)
            display += UInt32(1).bigEndianBytes                    // dynamic resolution
            display += UInt32(4).bigEndianBytes                    // virtual
            func millimetres(_ points: UInt16) -> [UInt8] { (Float(points) / nominalDPI * 25.4).bitPattern.bigEndianBytes }
            display += millimetres(mode.points.width) + millimetres(mode.points.height)
            display += maximumBackingWidth.bigEndianBytes + maximumBackingHeight.bigEndianBytes
            display += UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes   // current and preferred mode
            display += UInt32(7).bigEndianBytes                    // rotations, as Apple's viewer sends
            display += UInt16(1).bigEndianBytes                    // one mode
            for value in [mode.pixels.width, mode.pixels.height, mode.points.width, mode.points.height] {
                display += UInt32(value).bigEndianBytes
            }
            display += refreshRate.bitPattern.bigEndianBytes
            display += UInt32(0).bigEndianBytes                    // no HDR
            body += display
        }
        return [0x1d, 0] + UInt16(body.count).bigEndianBytes + body
    }

    static let descriptorHead = 0x9c
    static let modeEntry = 0x1c

    /// Whether a Mac can hold High Performance: its enhanced ServerInit lists
    /// `SetDisplayConfiguration`, as Apple's viewer checks before offering the mode.
    public static func holdsHighPerformance(_ info: VNCServerInfo) -> Bool {
        info.appleAccepts(0x1d) && info.appleAccepts(0x1c)
    }
}

/// A protocol-buffers writer: varints and length-delimited fields are all the offers use.
struct Protobuf {
    private(set) var bytes: [UInt8] = []

    mutating func varint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            bytes.append(UInt8(truncatingIfNeeded: value) | 0x80)
            value >>= 7
        }
        bytes.append(UInt8(value))
    }

    mutating func uint(_ field: UInt64, _ value: UInt64) {
        varint(field << 3)
        varint(value)
    }

    mutating func bytes(_ field: UInt64, _ value: [UInt8]) {
        varint(field << 3 | 2)
        varint(UInt64(value.count))
        bytes += value
    }

    mutating func message(_ field: UInt64, _ inner: Protobuf) { bytes(field, inner.bytes) }
}

/// A binary property list (`bplist00`) of one dictionary, its entries in order: the dictionary,
/// its keys, its values, an offset table and the trailer. Only what the offers hold.
enum BinaryPropertyList {
    enum Value { case data([UInt8]), integer(UInt8), string(String) }

    static func dictionary(_ entries: [(String, Value)]) -> [UInt8] {
        func marker(_ out: inout [UInt8], _ kind: UInt8, _ count: Int) {
            if count < 15 { out.append(kind | UInt8(count)) }
            else if count < 256 { out += [kind | 0x0f, 0x10, UInt8(count)] }
            else { out += [kind | 0x0f, 0x11] + UInt16(count).bigEndianBytes }
        }
        var out = Array("bplist00".utf8)
        var offsets: [Int] = [out.count]
        let n = entries.count
        marker(&out, 0xd0, n)
        for index in 0..<n { out.append(UInt8(1 + index)) }
        for index in 0..<n { out.append(UInt8(1 + n + index)) }
        for (key, _) in entries {
            offsets.append(out.count)
            marker(&out, 0x50, key.utf8.count)
            out += Array(key.utf8)
        }
        for (_, value) in entries {
            offsets.append(out.count)
            switch value {
            case .data(let bytes): marker(&out, 0x40, bytes.count); out += bytes
            case .integer(let value): out += [0x10, value]
            case .string(let text): marker(&out, 0x50, text.utf8.count); out += Array(text.utf8)
            }
        }
        let table = out.count
        for offset in offsets { out += UInt16(offset).bigEndianBytes }
        out += [0, 0, 0, 0, 0, 0, 2, 1]
        out += UInt64(offsets.count).bigEndianBytes + UInt64(0).bigEndianBytes + UInt64(table).bigEndianBytes
        return out
    }
}

extension ZlibDeflater {
    /// A whole zlib stream, finished, at the default level.
    static func compressed(_ input: [UInt8]) throws -> [UInt8] {
        var length = compressBound(uLong(input.count))
        var output = [UInt8](repeating: 0, count: Int(length))
        let status = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compress2(destination.baseAddress, &length, source.baseAddress, uLong(source.count), Z_DEFAULT_COMPRESSION)
            }
        }
        guard status == Z_OK else { throw RFBError.resourceLimit("The media stream's offer could not be compressed.") }
        return Array(output[0..<Int(length)])
    }
}
