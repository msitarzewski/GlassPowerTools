//
//  RFBAppleSoundDecoder.swift
//  Glass Power Tools — VNCKit
//
//  A Mac's High Performance sound, decoded by AudioToolbox: AAC-ELD (MPEG-4 object type 39), 48 kHz
//  stereo, one 480-sample access unit an RTP packet, whatever the offer lists (remotex's notes, "The
//  sound"). The Mac never sends its configuration; it is AudioSpecificConfig `F8 E6 50 00`, which
//  CoreAudio reads only inside an MPEG-4 ES_Descriptor — the form Safari decoded every unit of a
//  capture with, where the bare configuration made CoreAudio build an AAC-LC decoder that refused
//  each packet. While the sound leg runs the Mac mutes its own output, so this is the session's sound.
//

import AudioToolbox
import Foundation

public final class RFBAppleSoundDecoder: @unchecked Sendable {
    public static let sampleRate = 48_000.0
    public static let channels = 2
    static let framesPerPacket: UInt32 = 480

    /// AudioSpecificConfig `F8 E6 50 00` (object type 39, 48 kHz, stereo, 480-sample frames, no SBR)
    /// in an ES_Descriptor: ES_ID 1, a DecoderConfigDescriptor for MPEG-4 audio, then the config.
    static let magicCookie: [UInt8] = [0x03, 0x18, 0x00, 0x01, 0x00, 0x04, 0x13, 0x40, 0x15, 0x00, 0x18, 0x00]
        + [UInt8](repeating: 0, count: 8) + [0x05, 0x04, 0xF8, 0xE6, 0x50, 0x00]

    private let converter: AudioConverterRef
    private let lock = NSLock()

    /// Nil where this device has no AAC-ELD decoder.
    public static func make() -> RFBAppleSoundDecoder? { try? RFBAppleSoundDecoder() }

    init(cookie: [UInt8] = magicCookie) throws {
        var input = AudioStreamBasicDescription(mSampleRate: Self.sampleRate, mFormatID: kAudioFormatMPEG4AAC_ELD, mFormatFlags: 0,
                                                mBytesPerPacket: 0, mFramesPerPacket: Self.framesPerPacket, mBytesPerFrame: 0,
                                                mChannelsPerFrame: UInt32(Self.channels), mBitsPerChannel: 0, mReserved: 0)
        var output = Self.pcm
        var made: AudioConverterRef?
        guard AudioConverterNew(&input, &output, &made) == noErr, let made else {
            throw RFBError.unsupported("This device cannot decode the Mac's High Performance sound.")
        }
        let status = cookie.withUnsafeBytes {
            AudioConverterSetProperty(made, kAudioConverterDecompressionMagicCookie, UInt32($0.count), $0.baseAddress!)
        }
        guard status == noErr else {
            AudioConverterDispose(made)
            throw RFBError.unsupported("The Mac's High Performance sound could not be configured (\(status)).")
        }
        converter = made
    }

    deinit { AudioConverterDispose(converter) }

    /// Interleaved 16-bit PCM, as `DesktopAudioPlayer` plays it.
    static var pcm: AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                                    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                    mBytesPerPacket: UInt32(2 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channels),
                                    mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
    }

    /// One access unit, decoded: 480 frames of interleaved 16-bit little-endian PCM; nil for a unit
    /// the decoder refused, which costs only its 10 ms.
    public func decode(_ unit: [UInt8]) -> Data? {
        guard !unit.isEmpty, unit.count <= 8192 else { return nil }
        return lock.withLock {
            let source = PacketSource(unit)
            var frames = Self.framesPerPacket
            var pcm = [UInt8](repeating: 0, count: Int(frames) * 2 * Self.channels)
            let status: OSStatus = pcm.withUnsafeMutableBytes { output in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: UInt32(Self.channels),
                                                                                    mDataByteSize: UInt32(output.count),
                                                                                    mData: output.baseAddress))
                return withExtendedLifetime(source) {
                    AudioConverterFillComplexBuffer(converter, Self.supply, Unmanaged.passUnretained(source).toOpaque(),
                                                    &frames, &list, nil)
                }
            }
            // A converter that ran out of input says so with the source's own code, after the frames.
            guard status == noErr || status == PacketSource.exhausted, frames > 0 else { return nil }
            return Data(pcm[0..<(Int(frames) * 2 * Self.channels)])
        }
    }

    /// Hands the converter the one packet, then says there are no more.
    private static let supply: AudioConverterComplexInputDataProc = { _, packets, data, descriptions, context in
        let source = Unmanaged<PacketSource>.fromOpaque(context!).takeUnretainedValue()
        guard !source.given else {
            packets.pointee = 0
            return PacketSource.exhausted
        }
        source.given = true
        packets.pointee = 1
        data.pointee.mNumberBuffers = 1
        data.pointee.mBuffers.mNumberChannels = UInt32(RFBAppleSoundDecoder.channels)
        data.pointee.mBuffers.mDataByteSize = UInt32(source.bytes.count)
        data.pointee.mBuffers.mData = UnsafeMutableRawPointer(source.bytes.baseAddress)
        descriptions?.pointee = source.description
        return noErr
    }

    private final class PacketSource {
        static let exhausted: OSStatus = 0x6d6f7265 // 'more'
        let bytes: UnsafeMutableBufferPointer<UInt8>
        let description: UnsafeMutablePointer<AudioStreamPacketDescription>
        var given = false

        init(_ unit: [UInt8]) {
            bytes = .allocate(capacity: unit.count)
            _ = bytes.initialize(from: unit)
            description = .allocate(capacity: 1)
            description.initialize(to: AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(unit.count)))
        }

        deinit {
            bytes.deallocate()
            description.deallocate()
        }
    }
}
