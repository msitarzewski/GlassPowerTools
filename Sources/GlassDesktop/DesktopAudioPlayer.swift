// AVAudioEngine playback approach adapted from RDPKit/AudioPlayer.swift.
// Copyright (c) 2026 Steelbrain. MIT license retained in this package's LICENSE.
import AVFoundation
import Foundation
import GlassRDPTransport

/// PCM16LE playback with a strict scheduled-frame budget and generation-safe reset.
@MainActor
public final class DesktopAudioPlayer {
    private struct Configuration: Equatable {
        let sampleRate: Double
        let channels: Int
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let maximumQueuedSeconds: Double
    private var configuration: Configuration?
    private var format: AVAudioFormat?
    private var budget = DesktopAudioQueueBudget()

    public var isMuted = false {
        didSet { if isMuted { stop() } }
    }

    public var queuedDurationSeconds: Double {
        guard let configuration else { return 0 }
        return Double(budget.queuedFrames) / configuration.sampleRate
    }

    public init(maximumQueuedSeconds: Double = 0.5) {
        self.maximumQueuedSeconds = maximumQueuedSeconds.isFinite
            ? min(2, max(0.05, maximumQueuedSeconds)) : 0.5
        engine.attach(player)
    }

    public func play(_ sample: GlassRDPAudioSample) throws {
        guard !isMuted else { return }
        let frameCount = try DesktopPCM16.validate(sampleRate: sample.sampleRate, channels: sample.channels, data: sample.data)
        guard frameCount > 0 else { return }
        let limit = Int(sample.sampleRate * maximumQueuedSeconds)
        // Reject an oversized individual packet before opening an audio device or allocating a buffer.
        guard frameCount <= limit else { return }
        let next = Configuration(sampleRate: sample.sampleRate, channels: sample.channels)
        if configuration != next { try configure(next, frameLimit: limit) }
        guard let token = budget.reserve(frameCount), let format else { return }
        do {
            let buffer = try DesktopPCM16.buffer(sampleRate: sample.sampleRate, channels: sample.channels,
                                                data: sample.data, format: format)
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in self?.budget.complete(frameCount, generation: token) }
            }
            if !engine.isRunning { try engine.start() }
            if !player.isPlaying { player.play() }
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        // Invalidates completions before stopping the node, which can invoke old callbacks.
        budget.reset(maximumFrames: 0)
        player.stop()
        engine.stop()
        engine.reset()
        engine.disconnectNodeOutput(player)
        configuration = nil
        format = nil
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func configure(_ next: Configuration, frameLimit: Int) throws {
        stop()
        guard let nextFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: next.sampleRate,
                                            channels: AVAudioChannelCount(next.channels), interleaved: false) else {
            throw DesktopAudioError.invalidFormat
        }
        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        #endif
        engine.connect(player, to: engine.mainMixerNode, format: nextFormat)
        engine.prepare()
        do { try engine.start() }
        catch { stop(); throw error }
        configuration = next
        format = nextFormat
        budget.reset(maximumFrames: frameLimit)
    }
}

public enum DesktopAudioError: Error, Equatable, Sendable, LocalizedError {
    case invalidFormat, invalidData, allocationFailed
    public var errorDescription: String? {
        switch self {
        case .invalidFormat: "The remote audio format is unsupported."
        case .invalidData: "The remote audio packet is malformed."
        case .allocationFailed: "The remote audio buffer could not be allocated."
        }
    }
}

struct DesktopAudioQueueBudget {
    private(set) var queuedFrames = 0
    private(set) var generation: UInt64 = 0
    private var maximumFrames = 0

    mutating func reset(maximumFrames: Int) {
        generation &+= 1
        queuedFrames = 0
        self.maximumFrames = max(0, maximumFrames)
    }

    mutating func reserve(_ frames: Int) -> UInt64? {
        guard frames > 0, frames <= maximumFrames - queuedFrames else { return nil }
        queuedFrames += frames
        return generation
    }

    mutating func complete(_ frames: Int, generation: UInt64) {
        guard generation == self.generation, frames > 0 else { return }
        queuedFrames = max(0, queuedFrames - frames)
    }
}

enum DesktopPCM16 {
    static func validate(sampleRate: Double, channels: Int, data: Data) throws -> Int {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate), (1...8).contains(channels) else {
            throw DesktopAudioError.invalidFormat
        }
        guard data.count.isMultiple(of: channels * 2), data.count / (channels * 2) <= Int(UInt32.max) else {
            throw DesktopAudioError.invalidData
        }
        return data.count / (channels * 2)
    }

    static func buffer(sampleRate: Double, channels: Int, data: Data, format: AVAudioFormat? = nil) throws -> AVAudioPCMBuffer {
        let frames = try validate(sampleRate: sampleRate, channels: channels, data: data)
        guard frames > 0 else { throw DesktopAudioError.invalidData }
        guard let format = format ?? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                                   channels: AVAudioChannelCount(channels), interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let output = buffer.floatChannelData else { throw DesktopAudioError.allocationFailed }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { bytes in
            let input = bytes.bindMemory(to: UInt8.self)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    let index = (frame * channels + channel) * 2
                    let bits = UInt16(input[index]) | (UInt16(input[index + 1]) << 8)
                    output[channel][frame] = Float(Int16(bitPattern: bits)) / 32768
                }
            }
        }
        return buffer
    }
}
