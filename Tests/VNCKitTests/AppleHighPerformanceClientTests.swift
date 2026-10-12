import CommonCrypto
import CryptoKit
import Foundation
import Testing
@testable import VNCKit

/// A High Performance session against a scripted Mac: the virtual display before the opening
/// messages, the media stream named first once a layout shows the display, the offer once the Mac
/// names its ports, and no RFB pixels shown over the stream's picture.
@Suite("Apple High Performance session", .serialized)
struct AppleHighPerformanceClientTests {
    /// A layout of one display covering the framebuffer (remotex's notes, "The display layout").
    private func layoutUpdate(width: UInt16, height: UInt16) -> [UInt8] {
        func f64(_ value: Double) -> [UInt8] { withUnsafeBytes(of: value.bitPattern.bigEndian, Array.init) }
        let edges = UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes + height.bigEndianBytes + width.bigEndianBytes
        var payload = UInt16(5).bigEndianBytes + width.bigEndianBytes + height.bigEndianBytes + width.bigEndianBytes + height.bigEndianBytes
        payload += UInt32.max.bigEndianBytes + UInt32(4).bigEndianBytes + UInt16(1).bigEndianBytes
        payload += f64(1) + f64(1) + UInt32(1).bigEndianBytes + edges + edges + UInt32(1).bigEndianBytes
        payload += RFBPixelFormat.client.wireBytes
        return [0, 0, 0, 1] + [UInt8](repeating: 0, count: 8) + RFBEncoding.appleDisplayLayout.rawValue.bigEndianBytes
            + UInt16(payload.count).bigEndianBytes + payload
    }

    /// An update of one encoding-1010 rectangle carrying `body`.
    private func mediaReply(_ body: [UInt8]) -> [UInt8] {
        [0, 0, 0, 1] + [UInt8](repeating: 0, count: 8) + RFBEncoding.appleMediaStream.rawValue.bigEndianBytes
            + UInt16(body.count).bigEndianBytes + body
    }

    @Test("virtual display first; the stream named once the display shows; the offer on the Mac's ports")
    func negotiation() async throws {
        let prime = hexBytes(Vectors.prime)
        let group = try ModularExponentiation(modulusBigEndian: prime)
        let serverPrivate: [UInt8] = Array(repeating: 0x11, count: 32)
        let serverPublic = RFBSecurity.fit(try group.power(baseBigEndian: [2], exponentBigEndian: serverPrivate), to: 128)
        var greeting: [UInt8] = Array("RFB 003.889\n".utf8) + [1, 30]
        greeting += UInt16(2).bigEndianBytes + UInt16(128).bigEndianBytes + prime + serverPublic
        let source = MemoryByteSource(greeting, holdsOpen: true), sink = MemoryByteSink()
        final class Seen: @unchecked Sendable { let lock = NSLock(); var frames = 0; var status: [VNCHighPerformanceStatus] = [] }
        let seen = Seen()
        var callbacks = VNCClientCallbacks()
        callbacks.frame = { _, _, _ in seen.lock.withLock { seen.frames += 1 } }
        callbacks.highPerformance = { status in seen.lock.withLock { seen.status.append(status) } }
        let wanted = VNCHighPerformance(width: 32, height: 16, density: 1, bitrates: VNCHighPerformance.capped(at: 8_000_000))
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", username: "alice", password: "secret",
                                                               appleProtocol: true, highPerformance: wanted),
                               callbacks: callbacks, source: source, sink: sink,
                               addresses: { ("127.0.0.1", "127.0.0.1") })
        let run = Task { try await client.run() }

        for _ in 0..<200 where await sink.written.count < 13 + 256 { try await Task.sleep(for: .milliseconds(5)) }
        let answer = await sink.written
        let clientPublic = Array(answer[(13 + 128)..<(13 + 256)])
        let shared = RFBSecurity.fit(try group.power(baseBigEndian: clientPublic, exponentBigEndian: serverPrivate), to: 128)
        let wrap = Array(Insecure.MD5.hash(data: shared))
        // macvm's command bitmap, which lists SetDisplayConfiguration (0x1d) and the stream's offer (0x1c).
        var name: [UInt8] = [0, 0] + UInt32(0x10 | 0x02).bigEndianBytes
        name += [0xbf, 0xf6, 0xe7, 0x2f, 0xec] + [UInt8](repeating: 0, count: 11) + Array("Studio".utf8)
        var after = UInt32(0).bigEndianBytes
        after += UInt16(64).bigEndianBytes + UInt16(32).bigEndianBytes + RFBPixelFormat.client.wireBytes
        after += UInt32(name.count).bigEndianBytes + name
        await source.append(after)
        let preludeEnd = 13 + 256 + 1 + 66 + 4 + 8 + 12
        for _ in 0..<200 where await sink.written.count < preludeEnd { try await Task.sleep(for: .milliseconds(5)) }
        var rekey: [UInt8] = [0, 0, 0, 1] + [UInt8](repeating: 0, count: 8) + RFBAppleMessages.rekeyEncoding.bigEndianBytes
        rekey += UInt32(1).bigEndianBytes
        rekey += try RFBSecurity.encryptECB(algorithm: CCAlgorithm(kCCAlgorithmAES128), key: wrap, plaintext: AppleRecordLayerTests.keys.key)
        rekey += try RFBSecurity.encryptECB(algorithm: CCAlgorithm(kCCAlgorithmAES128), key: wrap, plaintext: AppleRecordLayerTests.keys.iv)
        await source.append(rekey)

        let toClient = try RFBAppleRecordCipher(AppleRecordLayerTests.keys, encrypting: true)
        let fromClient = try RFBAppleRecordCipher(AppleRecordLayerTests.keys, encrypting: false)
        var offset = preludeEnd
        var messages: [[UInt8]] = []
        func readMessages() async throws {
            let written = await sink.written
            while offset + 2 <= written.count {
                let length = Int(UInt16(written[offset]) << 8 | UInt16(written[offset + 1]))
                guard offset + 2 + length <= written.count else { break }
                messages.append(Array(try RFBAppleRecords.open(Array(written[(offset + 2)..<(offset + 2 + length)]), with: fromClient)))
                offset += 2 + length
            }
        }
        func waitFor(_ what: String, _ found: ([[UInt8]]) -> Bool) async throws {
            for _ in 0..<300 {
                try await readMessages()
                if found(messages) { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            Issue.record("never sent: \(what)")
        }
        try await waitFor("the opening messages") { $0.contains { $0.first == 2 } }
        #expect(messages.first?.first == 0x1d, "the virtual display before anything else")
        let configuration = try #require(messages.first)
        #expect(Array(configuration[(0x0c + 0x9c)..<(0x0c + 0x9c + 8)]) == UInt32(32).bigEndianBytes + UInt32(16).bigEndianBytes)
        #expect(messages[1].first == 0 && messages[2].first == 2, "then SetPixelFormat and SetEncodings")
        #expect(!messages[2].dropFirst(4).starts(with: RFBEncoding.appleMediaStream.rawValue.bigEndianBytes), "not the stream yet")
        #expect(!messages.contains { $0.first == 8 }, "never SetServerScaling")

        // The physical desktop's pixels, then the layout of the virtual display.
        let pixels: [UInt8] = [0, 0, 0, 1] + UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes + UInt16(1).bigEndianBytes
            + UInt16(1).bigEndianBytes + Int32(0).bigEndianBytes + [1, 2, 3, 0]
        await source.append(try RFBAppleRecords.frame(pixels, with: toClient))
        await source.append(try RFBAppleRecords.frame(layoutUpdate(width: 32, height: 16), with: toClient))
        try await waitFor("the encodings naming the stream") { list in
            list.contains { $0.first == 2 && Array($0.dropFirst(4).prefix(4)) == RFBEncoding.appleMediaStream.rawValue.bigEndianBytes }
        }
        // The Mac names its ports; the offer follows.
        let base = UInt16.random(in: 40_000...60_000)
        var ports = hexBytes("0001000100000000170c00000001170d0000000100000000000000000000000000000000")
        ports.replaceSubrange(8..<10, with: base.bigEndianBytes)
        ports.replaceSubrange(14..<16, with: (base + 1).bigEndianBytes)
        await source.append(try RFBAppleRecords.frame(mediaReply(ports), with: toClient))
        try await waitFor("the offer") { $0.contains { $0.first == 0x1c } }
        let offer = try #require(messages.first { $0.first == 0x1c })
        #expect(Array(offer[4..<10]) == [0, 3, 0, 0, 0, 5], "version 3, 60 fps, no pointer in the picture")
        #expect(messages.filter { $0.first == 0x1c }.count == 1, "one offer")
        await source.append(try RFBAppleRecords.frame(mediaReply(hexBytes("000200020000000000000000000000000000")), with: toClient))
        try await Task.sleep(for: .milliseconds(100))
        try await readMessages()
        #expect(messages.filter { $0.first == 0x1c }.count == 1, "no second offer on the answer")
        #expect(messages.filter { $0.first == 3 }.allSatisfy { Array($0[6..<10]) == [0, 1, 0, 1] }, "a single pixel asked for")
        #expect(messages.filter { $0.first == 9 }.allSatisfy { Array($0[4..<8]) == UInt32(1_000_000).bigEndianBytes && Array($0[12..<16]) == [0, 1, 0, 1] },
                "a single pixel armed, once a second")
        seen.lock.withLock {
            #expect(seen.frames == 0, "the Mac's pixels are not the picture")
            #expect(seen.status == [.starting])
        }
        client.cancel()
        await source.close()
        _ = try? await run.value
    }

    @Test("a Mac whose ServerInit lists no SetDisplayConfiguration is shown in Standard mode, and says why")
    func unavailable() async throws {
        let source = MemoryByteSource(Array("RFB 003.008\n".utf8) + [1, 1] + UInt32(0).bigEndianBytes
            + UInt16(4).bigEndianBytes + UInt16(4).bigEndianBytes + RFBPixelFormat.client.wireBytes + UInt32(0).bigEndianBytes,
            holdsOpen: true)
        final class Seen: @unchecked Sendable { let lock = NSLock(); var status: [VNCHighPerformanceStatus] = [] }
        let seen = Seen()
        var callbacks = VNCClientCallbacks()
        callbacks.highPerformance = { status in seen.lock.withLock { seen.status.append(status) } }
        let client = VNCClient(configuration: VNCConfiguration(host: "linux.example", password: "",
                                                               highPerformance: VNCHighPerformance(width: 800, height: 600, density: 1)),
                               callbacks: callbacks, source: source, sink: MemoryByteSink())
        let run = Task { try await client.run() }
        for _ in 0..<200 where seen.lock.withLock({ seen.status.isEmpty }) { try await Task.sleep(for: .milliseconds(5)) }
        seen.lock.withLock {
            if case .unavailable? = seen.status.first {} else { Issue.record("said why: \(seen.status)") }
        }
        client.cancel()
        await source.close()
        _ = try? await run.value
    }
}
