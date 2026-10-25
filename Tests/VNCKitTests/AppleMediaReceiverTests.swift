import CoreVideo
import Darwin
import Foundation
import Testing
@testable import VNCKit

/// The receiver end to end on this machine: a stand-in Mac protects remotex's HEVC 4:4:4 fixture as
/// SRTP and sends it over UDP; the receiver authenticates, reassembles, decodes and answers with
/// SRTCP reports the stand-in authenticates under the keys of the offer.
@Suite("Apple media stream: receiving", .serialized)
struct AppleMediaReceiverTests {
    /// What the Mac does to an RTP packet: the payload encrypted, then the tag over it all and the
    /// rollover counter (RFC 3711).
    private func protect(_ payload: [UInt8], keys: RFBAppleSRTP.SessionKeys, sequence: UInt16, timestamp: UInt32,
                         ssrc: UInt32, marker: Bool, payloadType: UInt8) throws -> [UInt8] {
        var body = payload[...]
        try keys.crypt(&body, ssrc: ssrc, index: UInt64(sequence))
        let header: [UInt8] = [0x80, (marker ? 0x80 : 0) | payloadType] + sequence.bigEndianBytes + timestamp.bigEndianBytes + ssrc.bigEndianBytes
        let packet = header + body
        return packet + keys.tag([packet[...], UInt32(0).bigEndianBytes[...]])
    }

    private func fixtureUnits() throws -> [[[UInt8]]] {
        let url = try #require(Bundle.module.url(forResource: "hevc-444-64x48", withExtension: "h265", subdirectory: "Fixtures"))
        let stream = [UInt8](try Data(contentsOf: url))
        var starts: [Int] = []
        var index = 0
        while index + 3 <= stream.count {
            if stream[index] == 0, stream[index + 1] == 0, stream[index + 2] == 1 { starts.append(index + 3); index += 3 } else { index += 1 }
        }
        var units: [[[UInt8]]] = [[]]
        for (number, start) in starts.enumerated() {
            var nal = Array(stream[start..<(number + 1 < starts.count ? starts[number + 1] - 3 : stream.count)])
            while nal.last == 0 { nal.removeLast() }
            units[units.count - 1].append(nal)
            if RFBAppleHEVC.nalType(nal[0]) < 32 { units.append([]) }
        }
        return units.filter { !$0.isEmpty }
    }

    /// One picture as RTP payloads: each NAL unit alone, the largest in three fragments.
    private func payloads(_ unit: [[UInt8]]) -> [[UInt8]] {
        let largest = unit.indices.max { unit[$0].count < unit[$1].count }
        return unit.indices.flatMap { index -> [[UInt8]] in
            let nal = unit[index]
            guard index == largest, nal.count > 30 else { return [nal] }
            let body = Array(nal[2...]), size = (body.count + 2) / 3
            let pieces = stride(from: 0, to: body.count, by: size).map { Array(body[$0..<min(body.count, $0 + size)]) }
            return pieces.enumerated().map { number, piece in
                [RFBAppleHEVC.fragmentation << 1 | (nal[0] & 0x81), nal[1],
                 (number == 0 ? 0x80 : 0) | (number == pieces.count - 1 ? 0x40 : 0) | RFBAppleHEVC.nalType(nal[0])] + piece
            }
        }
    }

    private final class Collected: @unchecked Sendable {
        let lock = NSLock()
        var pictures: [(Int, Int)] = []
        var sound: [[UInt8]] = []
        var failure: RFBError?
    }

    @Test("pictures sent as SRTP over UDP arrive decoded, and the receiver's reports are authentic")
    func endToEnd() async throws {
        let session = RFBAppleMediaSession()
        let base = try freeUDPBase()
        let ports = RFBAppleMediaSession.Ports(audio: base, videos: [base + 1])
        let macPorts = RFBAppleMediaSession.Ports(audio: base + 100, videos: [base + 101])
        let collected = Collected()
        let receiver = try RFBAppleMediaReceiver(
            local: "127.0.0.1", peer: "127.0.0.1", session: session, ports: ports, peerPorts: macPorts,
            pictures: { _, picture in collected.lock.withLock { collected.pictures.append((CVPixelBufferGetWidth(picture), CVPixelBufferGetHeight(picture))) } },
            sound: { unit in collected.lock.withLock { collected.sound.append(unit) } },
            failed: { error in collected.lock.withLock { collected.failure = error } })
        receiver.start()
        defer { receiver.stop() }

        let macVideo = try RFBAppleMediaReceiver.socket(local: "127.0.0.1", peer: "127.0.0.1", port: macPorts.videos[0], peerPort: ports.videos[0], buffer: nil)
        let macAudio = try RFBAppleMediaReceiver.socket(local: "127.0.0.1", peer: "127.0.0.1", port: macPorts.audio, peerPort: ports.audio, buffer: nil)
        defer { close(macVideo); close(macAudio) }
        let videoKeys = try RFBAppleSRTP.SessionKeys(master: session.videos[0].keys.fromMac, base: 0)
        let audioKeys = try RFBAppleSRTP.SessionKeys(master: session.audioKeys.fromMac, base: 0)
        let macSSRC: UInt32 = 0x39b8_5839
        var sequence: UInt16 = 100
        for (number, unit) in try fixtureUnits().enumerated() {
            let parts = payloads(unit)
            for (index, payload) in parts.enumerated() {
                let packet = try protect(payload, keys: videoKeys, sequence: sequence, timestamp: UInt32(number * 400),
                                         ssrc: macSSRC, marker: index == parts.count - 1, payloadType: 100)
                _ = packet.withUnsafeBytes { send(macVideo, $0.baseAddress, $0.count, 0) }
                sequence &+= 1
            }
        }
        let soundUnit: [UInt8] = [0x21, 0x10, 0x05, 0x00]
        let soundPacket = try protect(soundUnit, keys: audioKeys, sequence: 7, timestamp: 480, ssrc: 0x1234, marker: true, payloadType: 101)
        _ = soundPacket.withUnsafeBytes { send(macAudio, $0.baseAddress, $0.count, 0) }

        // Wait for the three pictures and at least one report back.
        var reports = try RFBAppleSRTP.ReportReceiver(master: session.videos[0].keys.toMac)
        var authentic = 0
        var buffer = [UInt8](repeating: 0, count: 2048)
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            let count = recv(macVideo, &buffer, buffer.count, MSG_DONTWAIT)
            if count > 0, (try? reports.authenticate(Array(buffer[0..<count]))) != nil { authentic += 1 }
            let done = collected.lock.withLock { collected.pictures.count == 3 }
            if done, authentic >= 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        collected.lock.withLock {
            #expect(collected.pictures.count == 3, "three pictures decoded")
            #expect(collected.pictures.allSatisfy { $0 == (64, 48) })
            #expect(collected.sound == [soundUnit], "the sound unit as the Mac sent it")
            #expect(collected.failure == nil)
        }
        #expect(authentic >= 2, "receiver reports, rate reports and acknowledgements, all authentic SRTCP")
        #expect(session.overdue(at: .now) == nil)
    }

    @Test("a packet under another key is dropped, and nothing is decoded from it")
    func forgedIsDropped() async throws {
        let session = RFBAppleMediaSession()
        let base = try freeUDPBase()
        let ports = RFBAppleMediaSession.Ports(audio: base, videos: [base + 1])
        let macPorts = RFBAppleMediaSession.Ports(audio: base + 100, videos: [base + 101])
        let collected = Collected()
        let receiver = try RFBAppleMediaReceiver(
            local: "127.0.0.1", peer: "127.0.0.1", session: session, ports: ports, peerPorts: macPorts,
            pictures: { _, _ in collected.lock.withLock { collected.pictures.append((0, 0)) } }, sound: { _ in },
            failed: { error in collected.lock.withLock { collected.failure = error } })
        receiver.start()
        defer { receiver.stop() }
        let macVideo = try RFBAppleMediaReceiver.socket(local: "127.0.0.1", peer: "127.0.0.1", port: macPorts.videos[0], peerPort: ports.videos[0], buffer: nil)
        defer { close(macVideo) }
        let wrongKeys = try RFBAppleSRTP.SessionKeys(master: .init(repeating: 7, count: 46), base: 0)
        for (number, unit) in try fixtureUnits().enumerated() {
            for (index, payload) in unit.enumerated() {
                let packet = try protect(payload, keys: wrongKeys, sequence: UInt16(10 * number + index), timestamp: UInt32(number * 400),
                                         ssrc: 1, marker: index == unit.count - 1, payloadType: 100)
                _ = packet.withUnsafeBytes { send(macVideo, $0.baseAddress, $0.count, 0) }
            }
        }
        // Then the same pictures under the right keys, after the forged ones: once these three are in,
        // the forged packets have been read too, and any picture made from one would be a fourth. (A
        // half-second sleep stood for that, and on a busy run nothing had been read yet — 2026-10-24.)
        let videoKeys = try RFBAppleSRTP.SessionKeys(master: session.videos[0].keys.fromMac, base: 0)
        var sequence: UInt16 = 100
        for (number, unit) in try fixtureUnits().enumerated() {
            let parts = payloads(unit)
            for (index, payload) in parts.enumerated() {
                let packet = try protect(payload, keys: videoKeys, sequence: sequence, timestamp: UInt32(number * 400),
                                         ssrc: 0x39b8_5839, marker: index == parts.count - 1, payloadType: 100)
                _ = packet.withUnsafeBytes { send(macVideo, $0.baseAddress, $0.count, 0) }
                sequence &+= 1
            }
        }
        for _ in 0..<3_000 where collected.lock.withLock({ collected.pictures.count < 3 }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        collected.lock.withLock {
            #expect(collected.pictures.count == 3, "the three genuine pictures and none from the forged packets")
            #expect(collected.failure == nil)
        }
    }
}

/// A base port whose four ports the receiver binds — base, base + 1, base + 100, base + 101 — are
/// free on the loopback now, below macOS's ephemeral range (49152 on), where the system hands out
/// ports of its own. A random base from 40000 to 60000 could land on one in use (2026-10-24).
func freeUDPBase() throws -> UInt16 {
    func free(_ port: UInt16) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }
    for _ in 0..<50 {
        let base = UInt16.random(in: 30_000...39_000)
        if [base, base + 1, base + 100, base + 101].allSatisfy(free) { return base }
    }
    throw CocoaError(.featureUnsupported)
}
