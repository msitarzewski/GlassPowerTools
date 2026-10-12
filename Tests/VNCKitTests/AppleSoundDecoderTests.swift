import AudioToolbox
import Foundation
import Testing
@testable import VNCKit

/// High Performance's sound: AAC-ELD, 48 kHz stereo, 480-sample units, decoded with the configuration
/// the Mac never sends (remotex's notes, "The sound").
@Suite("Apple media stream: sound")
struct AppleSoundDecoderTests {
    /// This device's own AAC-ELD encoder's packets of a 1 kHz tone, and its configuration.
    private func encodedTone(packets count: Int) throws -> (packets: [[UInt8]], cookie: [UInt8]) {
        var input = RFBAppleSoundDecoder.pcm
        var output = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatMPEG4AAC_ELD, mFormatFlags: 0,
                                                 mBytesPerPacket: 0, mFramesPerPacket: 480, mBytesPerFrame: 0,
                                                 mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        var made: AudioConverterRef?
        #expect(AudioConverterNew(&input, &output, &made) == noErr)
        let encoder = try #require(made)
        defer { AudioConverterDispose(encoder) }
        var bitrate: UInt32 = 128_000
        _ = AudioConverterSetProperty(encoder, kAudioConverterEncodeBitRate, 4, &bitrate)
        let frames = 480 * (count + 4)
        var pcm = [Int16](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            let sample = Int16(12_000 * sin(2 * Double.pi * 1000 * Double(frame) / 48_000))
            pcm[2 * frame] = sample; pcm[2 * frame + 1] = sample
        }
        final class Feed { var pcm: [Int16]; var offset = 0; init(_ pcm: [Int16]) { self.pcm = pcm } }
        let feed = Feed(pcm)
        var packets: [[UInt8]] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        var description = AudioStreamPacketDescription()
        while packets.count < count {
            var produced: UInt32 = 1
            let status = buffer.withUnsafeMutableBytes { bytes -> OSStatus in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count),
                                                                                    mData: bytes.baseAddress))
                return AudioConverterFillComplexBuffer(encoder, { _, packets, data, _, context in
                    let feed = Unmanaged<Feed>.fromOpaque(context!).takeUnretainedValue()
                    let wanted = Int(packets.pointee)
                    let available = feed.pcm.count / 2 - feed.offset
                    guard available > 0 else { packets.pointee = 0; return 1 }
                    let given = min(wanted, available)
                    packets.pointee = UInt32(given)
                    feed.pcm.withUnsafeMutableBufferPointer { samples in
                        data.pointee.mNumberBuffers = 1
                        data.pointee.mBuffers.mNumberChannels = 2
                        data.pointee.mBuffers.mDataByteSize = UInt32(given * 4)
                        data.pointee.mBuffers.mData = UnsafeMutableRawPointer(samples.baseAddress! + feed.offset * 2)
                    }
                    feed.offset += given
                    return noErr
                }, Unmanaged.passUnretained(feed).toOpaque(), &produced, &list, &description)
            }
            guard produced > 0 else { #expect(status == noErr || status == 1); break }
            packets.append(Array(buffer[Int(description.mStartOffset)..<Int(description.mStartOffset) + Int(description.mDataByteSize)]))
        }
        var size: UInt32 = 0
        _ = AudioConverterGetPropertyInfo(encoder, kAudioConverterCompressionMagicCookie, &size, nil)
        var cookie = [UInt8](repeating: 0, count: Int(size))
        _ = cookie.withUnsafeMutableBytes { AudioConverterGetProperty(encoder, kAudioConverterCompressionMagicCookie, &size, $0.baseAddress!) }
        return (packets, Array(cookie[0..<Int(size)]))
    }

    @Test("units of a tone decode to 480 stereo frames each, the tone audible, under the configuration the Mac never sends")
    func decodesTone() throws {
        let (packets, cookie) = try encodedTone(packets: 30)
        #expect(packets.count == 30)
        // This device's encoder describes the same stream in its own configuration.
        #expect(cookie.windowsMatch([0xF8, 0xE6, 0x50, 0x00]), "the encoder's configuration holds F8 E6 50 00: \(cookie.map { String(format: "%02x", $0) }.joined())")
        let decoder = try RFBAppleSoundDecoder()
        var decoded: [Int16] = []
        for packet in packets {
            let pcm = try #require(decoder.decode(packet), "a unit decodes")
            #expect(pcm.count == 480 * 4)
            pcm.withUnsafeBytes { decoded += $0.bindMemory(to: Int16.self) }
        }
        // Past the codec's delay, the tone: loud, and the two channels the same.
        let tail = decoded.suffix(480 * 2 * 10)
        let peak = tail.map { abs(Int($0)) }.max() ?? 0
        #expect(peak > 6_000, "the tone survives: peak \(peak)")
        let crossings = stride(from: tail.startIndex, to: tail.endIndex - 2, by: 2).filter {
            (tail[$0] < 0) != (tail[$0 + 2] < 0)
        }.count
        #expect((180...220).contains(crossings), "1 kHz over 100 ms: \(crossings) zero crossings")
        #expect(decoder.decode([]) == nil)
    }
}

private extension Array where Element == UInt8 {
    func windowsMatch(_ needle: [UInt8]) -> Bool {
        guard count >= needle.count else { return false }
        return (0...(count - needle.count)).contains { Array(self[$0..<($0 + needle.count)]) == needle }
    }
}
