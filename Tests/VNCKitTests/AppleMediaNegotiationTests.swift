import Foundation
import Testing
import zlib
@testable import VNCKit

/// High Performance's negotiation, against what Apple's own negotiator produced and what the Mac
/// sent, as remotex captured them (`src/vnc_apple_media.rs` and `src/vnc_apple.rs` tests, MIT).
@Suite("Apple media stream: negotiation")
struct AppleMediaNegotiationTests {
    /// `AVCMediaStreamNegotiator initWithMode:8` on macOS 26.6 for SSRC 3606155525, byte for byte.
    static let capturedAudioBlob = "080110011a120885a2c6b70d1000180020ffbc0128003000320d56696365726f7920312e372e3040004a05080110ab024a0908ea1f1000188080014a0b080010c0d1e123188080204a0b08001080dac409188080064a0a08001080b489131880604a0b080010808ece1c188080104a0508101084204a0b08001080c2d72f188080404a05080410e4324a0b080010809bee02188080086880e0f084deafb6a3ee017002800100"
    /// And `initWithMode:7` for SSRC 3023179925 at 1600 × 1000, with Apple's four tiles.
    static let capturedVideoBlob = "080110012af5010895a1c8a10b10001a7d087b120a0801100118c387032000120a0801100218c387032000120a0801100118c387032000120a0801100218c3870320001a47464c533b4d533a2d313b4c463a2d313b4c54523b43414241433b504f533a303b454f443a313b4854533a323b52523a333b41523a342f332c352f383b58523a342f332c352f383b20011a5c0864120a0801100118c387032000120a0801100218c3870320001a3e464c533b4c463a2d313b504f533a353b454f443a313b4854533a323b52523a333b504f53453a343b41523a342f332c352f383b58523a342f332c352f383b200e20c00c28e80730043801403f48016001320d56696365726f7920312e372e3040004a0a08001080b489131880604a05080110ab024a0908ea1f1000188080014a0b080010c0d1e123188080204a0b08001080dac409188080064a0b080010808ece1c188080104a0508101084204a0b08001080c2d72f188080404a05080410e4324a0b080010809bee0218808008688080e7dedfafb6a3ee017002800100"

    @Test("the blobs are what Apple's negotiator produces")
    func blobs() {
        #expect(RFBAppleMedia.audioOfferBlob(ssrc: 3_606_155_525) == hexBytes(Self.capturedAudioBlob))
        #expect(RFBAppleMedia.videoOfferBlob(ssrc: 3_023_179_925, width: 1600, height: 1000, tiles: 4) == hexBytes(Self.capturedVideoBlob))
    }

    /// A protobuf's top-level fields, read independently of the writer: a varint, or the bytes.
    private func fields(_ bytes: [UInt8]) -> [(UInt64, UInt64?, [UInt8]?)] {
        var at = 0
        func varint() -> UInt64 {
            var value: UInt64 = 0, shift: UInt64 = 0
            while true {
                let byte = bytes[at]; at += 1
                value |= UInt64(byte & 0x7f) << shift
                shift += 7
                if byte & 0x80 == 0 { return value }
            }
        }
        var out: [(UInt64, UInt64?, [UInt8]?)] = []
        while at < bytes.count {
            let tag = varint()
            if tag & 7 == 0 { out.append((tag >> 3, varint(), nil)) } else {
                let length = Int(varint())
                out.append((tag >> 3, nil, Array(bytes[at..<(at + length)])))
                at += length
            }
        }
        return out
    }

    @Test("one picture a frame, at Apple's bitrates or at ones of this client's own")
    func videoOffer() throws {
        let blob = RFBAppleMedia.videoOfferBlob(ssrc: 7, width: 1280, height: 800, tiles: 1)
        let top = fields(blob)
        let stream = fields(try #require(top.first { $0.0 == 5 }?.2))
        func value(_ field: UInt64) -> UInt64? { stream.first { $0.0 == field }?.1 }
        #expect(value(4) == 1280 && value(5) == 800 && value(6) == 1)
        func bitrates(_ top: [(UInt64, UInt64?, [UInt8]?)]) -> [UInt64] {
            top.filter { $0.0 == 9 }.map { fields($0.2 ?? []) }.filter { $0.first?.1 == 0 }.compactMap { $0[1].1 }
        }
        #expect(bitrates(top) == [40_000_000, 75_000_000, 20_000_000, 60_000_000, 100_000_000, 6_000_000])
        let capped = fields(RFBAppleMedia.videoOfferBlob(ssrc: 7, width: 1280, height: 800, tiles: 1,
                                                         bitrates: [8_000_000, 8_000_000, 8_000_000, 8_000_000, 8_000_000, 6_000_000]))
        #expect(bitrates(capped) == [8_000_000, 8_000_000, 8_000_000, 8_000_000, 8_000_000, 6_000_000])
        #expect(capped.filter { $0.0 == 9 }.count == top.filter { $0.0 == 9 }.count, "the codecs stay")
    }

    @Test("the offer is a binary plist of four entries around the deflated blob")
    func offerPlist() throws {
        let blob = RFBAppleMedia.audioOfferBlob(ssrc: 1)
        let plist = try RFBAppleMedia.offer(mode: RFBAppleMedia.modeAudio, blob: blob, callID: "910BCF8F-D1D7-4EB6-B728-E1FDB02DD3B6")
        #expect(Array(plist[0..<8]) == Array("bplist00".utf8))
        #expect(Array(plist[8..<17]) == [0xd4, 1, 2, 3, 4, 5, 6, 7, 8])
        // Foundation reads it as Apple's viewer's own.
        let read = try #require(try PropertyListSerialization.propertyList(from: Data(plist), format: nil) as? [String: Any])
        #expect(read["avcMediaStreamNegotiatorMode"] as? Int == 8)
        #expect(read["avcMediaStreamOptionCallID"] as? String == "910BCF8F-D1D7-4EB6-B728-E1FDB02DD3B6")
        #expect((read["avcMediaStreamOptionRemoteEndpointInfo"] as? Data).map { [UInt8]($0) } == RFBAppleMedia.remoteEndpointInfo)
        let compressed = try #require(read["avcMediaStreamNegotiatorMediaBlob"] as? Data)
        var inflated = [UInt8](repeating: 0, count: blob.count + 64)
        var length = uLong(inflated.count)
        let status = [UInt8](compressed).withUnsafeBufferPointer { source in
            inflated.withUnsafeMutableBufferPointer { uncompress($0.baseAddress, &length, source.baseAddress, uLong(source.count)) }
        }
        #expect(status == Z_OK && Array(inflated[0..<Int(length)]) == blob)
    }

    @Test("the configuration message lays out as measured, for one display and two")
    func configuration() throws {
        let a = RFBAppleMedia.KeyPair(toMac: .init(repeating: 0xa1, count: 46), fromMac: .init(repeating: 0xa2, count: 46))
        let v = RFBAppleMedia.KeyPair(toMac: .init(repeating: 0xb1, count: 46), fromMac: .init(repeating: 0xb2, count: 46))
        let flags = RFBAppleMedia.flag60FPS | RFBAppleMedia.flagNoCursor
        let message = try RFBAppleMedia.configurationMessage(flags: flags, sessionUUID: .init(repeating: 0x11, count: 16),
                                                             audioOffer: .init(repeating: 0xaa, count: 300), audioKeys: a,
                                                             videos: [(.init(repeating: 0xbb, count: 400), v)])
        func u16(_ bytes: [UInt8], _ at: Int) -> Int { Int(bytes[at]) << 8 | Int(bytes[at + 1]) }
        #expect(message[0] == 0x1c && u16(message, 2) == message.count - 4)
        #expect(Array(message[4..<10]) == [0, 3, 0, 0, 0, 5], "version 3; 60 fps and the pointer left out")
        #expect(u16(message, 0x0a) == 300 && u16(message, 0x0c) == 400 && u16(message, 0x0e) == 0)
        #expect(Array(message[0x14..<0x24]) == .init(repeating: 0x11, count: 16))
        #expect(Array(message[0x24..<0x52]) == a.toMac && Array(message[0x52..<0x80]) == a.fromMac)
        let videoKeys = 0x80 + 300
        #expect(Array(message[videoKeys..<(videoKeys + 46)]) == v.toMac)
        #expect(Array(message[(videoKeys + 46)..<(videoKeys + 92)]) == v.fromMac)
        #expect(message.count == videoKeys + 92 + 400)

        let w = RFBAppleMedia.KeyPair(toMac: .init(repeating: 0xc1, count: 46), fromMac: .init(repeating: 0xc2, count: 46))
        let two = try RFBAppleMedia.configurationMessage(flags: flags | RFBAppleMedia.flag60FPSSecond, sessionUUID: .init(repeating: 0x11, count: 16),
                                                         audioOffer: .init(repeating: 0xaa, count: 300), audioKeys: a,
                                                         videos: [(.init(repeating: 0xbb, count: 400), v), (.init(repeating: 0xcc, count: 500), w)])
        #expect(u16(two, 2) == two.count - 4 && Array(two[6..<10]) == [0, 0, 0, 7])
        #expect(u16(two, 0x0c) == 400 && u16(two, 0x0e) == 500)
        #expect(Array(two[0x10..<message.count]) == Array(message[0x10...]))
        #expect(Array(two[message.count..<(message.count + 46)]) == w.toMac)
        // What the Mac checks the message against: 0xd8 with the first display's keys, the offers,
        // and 0x5c of keys before a second display's offer.
        #expect(two.count - 4 == 0xd8 + 300 + 400 + 0x5c + 500)
        #expect(throws: RFBError.self) {
            try RFBAppleMedia.configurationMessage(flags: flags, sessionUUID: [1], audioOffer: [], audioKeys: a, videos: [([], v)])
        }
    }

    @Test("the Mac's replies parse as measured")
    func replies() throws {
        // Message 1 as the Mac sent it: sound at 5900, picture at 5901.
        let ports = hexBytes("0001000100000000170c00000001170d0000000100000000000000000000000000000000")
        #expect(try RFBAppleMedia.reply(ports) == .ports(audio: 5900, video: 5901, video2: nil))
        #expect(try RFBAppleMedia.reply(hexBytes("000200020000000000020003000000000000aabbccddee")) == .answer(videos: 1))
        #expect(try RFBAppleMedia.reply(hexBytes("00030001000000000000000200000000")) == .error(type: 2, subCode: 0))
        #expect(try RFBAppleMedia.reply([0, 9, 0, 1, 0, 0, 0, 0]) == .other(9))
        #expect(throws: RFBError.self) { try RFBAppleMedia.reply([0, 1, 0, 1]) }
        #expect(throws: RFBError.self) { try RFBAppleMedia.reply([0, 1, 0, 1, 0, 0, 0, 0, 0]) }
        var noSound = ports
        noSound[13] = 0
        #expect(throws: RFBError.self) { try RFBAppleMedia.reply(noSound) }
        var second = ports
        second.replaceSubrange(20..<22, with: UInt16(5902).bigEndianBytes)
        second[25] = 1
        #expect(try RFBAppleMedia.reply(second) == .ports(audio: 5900, video: 5901, video2: 5902))
        #expect(try RFBAppleMedia.reply(hexBytes("000200020000000000020003000100000000aabbccddeeff")) == .answer(videos: 2))
        #expect(throws: RFBError.self) { try RFBAppleMedia.reply(hexBytes("000200020000000000020003000000000000aabbccdd")) }
    }

    @Test("a virtual display is one mode under the fixed ceiling, its descriptor at the measured offsets")
    func virtualDisplay() throws {
        let message = try RFBAppleMedia.setDisplayConfiguration([RFBAppleMedia.VirtualMode(points: (1600, 1000), density: 1)],
                                                                refreshRate: 30)
        func u16(_ bytes: ArraySlice<UInt8>, _ at: Int) -> Int { Int(bytes[bytes.startIndex + at]) << 8 | Int(bytes[bytes.startIndex + at + 1]) }
        func u32(_ bytes: ArraySlice<UInt8>, _ at: Int) -> Int { u16(bytes, at) << 16 | u16(bytes, at + 2) }
        let all = message[...]
        #expect(message[0] == 0x1d && u16(all, 2) == message.count - 4)
        #expect(message.count == 0x0c + 0x9c + 0x1c)
        #expect(u16(all, 4) == 1 && u16(all, 6) == 1, "version 1, one display")
        let display = message[0x0c...]
        #expect(u16(display, 0) == 0x9c + 0x1c)
        #expect(Array(display.dropFirst(2).prefix(30)) == Array("Screen Sharing Virtual Display".utf8))
        #expect(u32(display, 0x7a) == 1 && u32(display, 0x7e) == 4, "dynamic, virtual")
        #expect(u32(display, 0x8a) == 3840 && u32(display, 0x8e) == 2160, "the ceiling, not the mode")
        #expect(u16(display, 0x92) == 0 && u16(display, 0x94) == 0 && u32(display, 0x96) == 7 && u16(display, 0x9a) == 1)
        #expect(u32(display, 0x9c) == 1600 && u32(display, 0xa0) == 1000 && u32(display, 0xa4) == 1600 && u32(display, 0xa8) == 1000)
        #expect(Array(display.dropFirst(0xac).prefix(8)) == [0x40, 0x3e, 0, 0, 0, 0, 0, 0], "30 Hz")
        #expect(u32(display, 0xb4) == 0)

        let retina = RFBAppleMedia.VirtualMode(points: (1600, 1000), density: 2)
        #expect(retina.pixels == (3200, 2000) && retina.points == (1600, 1000))
        let huge = RFBAppleMedia.VirtualMode(points: (2560, 1440), density: 2)
        #expect(huge.pixels == (3840, 2160) && huge.points == (1920, 1080), "shrunk under the ceiling, still 2x")

        let two = try RFBAppleMedia.setDisplayConfiguration([retina, RFBAppleMedia.VirtualMode(points: (1280, 800), density: 2)])
        let descriptor = 0x9c + 0x1c
        #expect(two.count == 0x0c + 2 * descriptor && u16(two[...], 6) == 2)
        let second = two[(0x0c + descriptor)...]
        #expect(Array(second.dropFirst(2).prefix(32)) == Array("Screen Sharing Virtual Display #2".utf8.prefix(32)))
        #expect(u32(second, 0x9c) == 2560)
        #expect(throws: RFBError.self) { try RFBAppleMedia.setDisplayConfiguration([]) }
    }
}
