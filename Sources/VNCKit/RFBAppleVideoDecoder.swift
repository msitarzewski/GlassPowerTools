//
//  RFBAppleVideoDecoder.swift
//  Glass Power Tools — VNCKit
//
//  A Mac's High Performance picture, decoded by VideoToolbox: HEVC Range Extensions, 8-bit 4:4:4,
//  full-range BT.709 matrix, sRGB transfer, Display P3 primaries (remotex's notes, "The stream").
//  Apple's own viewer decodes it with VideoToolbox; whether a given device does is what
//  `RFBAppleVideoDecoder.decodes444` and the fixture test find out.
//
//  The parameter sets arrive in the stream, ahead of each IDR; a set that changes (a display change
//  starts a new stream at a new size) makes a new session. Pictures come out as BGRA pixel buffers
//  backed by IOSurface, ready for Metal.
//

import CoreMedia
import CoreVideo
import Foundation
import os
import VideoToolbox

public final class RFBAppleVideoDecoder: @unchecked Sendable {
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var parameterSets: [[UInt8]] = []
    private let lock = NSLock()

    public init() {}

    deinit {
        if let session { VTDecompressionSessionInvalidate(session) }
    }

    /// The size of the pictures the current parameter sets describe.
    public var size: (width: Int, height: Int)? {
        lock.withLock { format.map { CMVideoFormatDescriptionGetDimensions($0) }.map { (Int($0.width), Int($0.height)) } }
    }

    /// Decodes one access unit; the picture, or nil for a unit that holds none (parameter sets
    /// alone). Throws when VideoToolbox cannot decode it, which costs the stream a keyframe.
    public func decode(_ unit: [[UInt8]]) throws -> CVPixelBuffer? {
        try lock.withLock {
            let sets = unit.filter { (RFBAppleHEVC.vps...RFBAppleHEVC.pps).contains(RFBAppleHEVC.nalType($0[0])) }
            if !sets.isEmpty, sets != parameterSets { try configure(sets) }
            let pictures = unit.filter { !(RFBAppleHEVC.vps...RFBAppleHEVC.pps).contains(RFBAppleHEVC.nalType($0[0])) }
            guard !pictures.isEmpty else { return nil }
            guard let session, let format else {
                throw RFBError.protocolViolation("A picture came before the stream's parameter sets.")
            }
            return try Self.decode(pictures, session: session, format: format)
        }
    }

    private func configure(_ sets: [[UInt8]]) throws {
        func find(_ type: UInt8) -> [UInt8]? { sets.last { RFBAppleHEVC.nalType($0[0]) == type } }
        guard let vps = find(RFBAppleHEVC.vps), let sps = find(RFBAppleHEVC.sps), let pps = find(RFBAppleHEVC.pps) else {
            // A unit with some sets and not others keeps the ones it had.
            return
        }
        var made: CMFormatDescription?
        let status = vps.withUnsafeBufferPointer { v in
            sps.withUnsafeBufferPointer { s in
                pps.withUnsafeBufferPointer { p in
                    let pointers = [v.baseAddress!, s.baseAddress!, p.baseAddress!]
                    let sizes = [vps.count, sps.count, pps.count]
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: 3, parameterSetPointers: pointers,
                        parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &made)
                }
            }
        }
        guard status == noErr, let made else {
            throw RFBError.unsupported("The Mac's picture format could not be read (\(status)).")
        }
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var created: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: made,
                                                         decoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
                                                         outputCallback: nil, decompressionSessionOut: &created)
        guard sessionStatus == noErr, let created else {
            throw RFBError.unsupported("This device cannot decode the Mac's High Performance picture (\(sessionStatus)).")
        }
        session = created
        format = made
        parameterSets = sets
    }

    /// Whether this device decodes a Mac's High Performance picture: three pictures of the same
    /// format (`sample444`) decoded once, the answer kept and logged. A device that cannot is not
    /// asked to try a Mac's stream, which would fail only after the Mac had moved its windows.
    public static var decodesHighPerformance: Bool { sampleCheck.withLock { $0 ?? runSampleCheck(&$0) } }

    private static let sampleCheck = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    private static func runSampleCheck(_ result: inout Bool?) -> Bool {
        let started = ContinuousClock.now
        let decoder = RFBAppleVideoDecoder()
        var pictures = 0
        var failure = ""
        do {
            for unit in annexBUnits(sample444) where try decoder.decode(unit) != nil { pictures += 1 }
        } catch {
            failure = error.localizedDescription
        }
        let elapsed = ContinuousClock.now - started
        let ok = pictures == 3
        VNCDiagnostics.record(category: "media", "event=hp-decoder-check ok=\(ok) pictures=\(pictures) ms=\(elapsed.components.attoseconds / 1_000_000_000_000_000 + elapsed.components.seconds * 1000)\(failure.isEmpty ? "" : " reason=\(failure)")")
        result = ok
        return ok
    }

    /// An Annex B stream's access units, one a picture: a VCL NAL unit closes one.
    static func annexBUnits(_ stream: [UInt8]) -> [[[UInt8]]] {
        var starts: [Int] = []
        var index = 0
        while index + 3 <= stream.count {
            if stream[index] == 0, stream[index + 1] == 0, stream[index + 2] == 1 { starts.append(index + 3); index += 3 } else { index += 1 }
        }
        var units: [[[UInt8]]] = [[]]
        for (number, start) in starts.enumerated() {
            var nal = Array(stream[start..<(number + 1 < starts.count ? starts[number + 1] - 3 : stream.count)])
            while nal.last == 0 { nal.removeLast() }
            guard !nal.isEmpty else { continue }
            units[units.count - 1].append(nal)
            if RFBAppleHEVC.nalType(nal[0]) < 32 { units.append([]) }
        }
        return units.filter { !$0.isEmpty }
    }

    private static func decode(_ nals: [[UInt8]], session: VTDecompressionSession, format: CMVideoFormatDescription) throws -> CVPixelBuffer? {
        var sample = [UInt8]()
        sample.reserveCapacity(nals.reduce(0) { $0 + 4 + $1.count })
        for nal in nals { sample += UInt32(nal.count).bigEndianBytes + nal }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: sample.count,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: sample.count, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr, let block,
              sample.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                                                                     dataLength: sample.count) }) == kCMBlockBufferNoErr else {
            throw RFBError.resourceLimit("A picture could not be handed to the decoder.")
        }
        var buffer: CMSampleBuffer?
        var sizes = [sample.count]
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &sizes, sampleBufferOut: &buffer) == noErr, let buffer else {
            throw RFBError.resourceLimit("A picture could not be handed to the decoder.")
        }
        var picture: CVPixelBuffer?
        var failure: OSStatus = noErr
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: buffer, flags: [], infoFlagsOut: nil) { status, _, image, _, _ in
            failure = status
            picture = image
        }
        guard status == noErr, failure == noErr else {
            throw RFBError.protocolViolation("The decoder refused a picture (\(status == noErr ? failure : status)).")
        }
        return picture
    }
}
