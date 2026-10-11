import CommonCrypto
import CryptoKit
import Foundation
import Testing
@testable import VNCKit

/// Apple's record layer and its 003.889 handshake (2026-10-11): the session encrypted after sign-in,
/// which plain 3.8 never asked a Mac for. remotex's notes, "The record layer" and "Connecting".
@Suite("Apple's record layer and revision", .serialized)
struct AppleRecordLayerTests {
    static let keys = RFBAppleRecordKeys(key: Array(0..<16), iv: Array(16..<32))

    /// One record by hand, from the notes' definition, with CommonCrypto's one-shot CBC and SHA-1 —
    /// not the code under test — so a mistake made the same way in framing and opening cannot pass.
    @Test("a record is u16 length, then AES-128-CBC of u16 body length, body, zero filler and SHA-1 of the sequence and all before it")
    func knownAnswer() throws {
        let message: [UInt8] = [5, 0, 0, 10, 0, 20]
        var plaintext = UInt16(message.count).bigEndianBytes + message
        plaintext += [UInt8](repeating: 0, count: (16 - (2 + message.count + 20) % 16) % 16)
        var hash = Insecure.SHA1()
        hash.update(data: UInt32(0).bigEndianBytes)
        hash.update(data: plaintext)
        plaintext += Array(hash.finalize())
        #expect(plaintext.count % 16 == 0)
        var ciphertext = [UInt8](repeating: 0, count: plaintext.count)
        var moved = 0
        let status = Self.keys.key.withUnsafeBytes { key in
            Self.keys.iv.withUnsafeBytes { iv in
                plaintext.withUnsafeBytes { input in
                    ciphertext.withUnsafeMutableBytes { out in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), 0, key.baseAddress, 16, iv.baseAddress,
                                input.baseAddress, plaintext.count, out.baseAddress, out.count, &moved)
                    }
                }
            }
        }
        #expect(status == kCCSuccess)
        let framed = try RFBAppleRecords.frame(message, with: RFBAppleRecordCipher(Self.keys, encrypting: true))
        #expect(framed == UInt16(plaintext.count).bigEndianBytes + ciphertext)
    }

    @Test("records chain and count across the session: each opens in order, and a tampered one ends it")
    func chainAndIntegrity() throws {
        let out = try RFBAppleRecordCipher(Self.keys, encrypting: true)
        let into = try RFBAppleRecordCipher(Self.keys, encrypting: false)
        let messages: [[UInt8]] = [[1], Array(repeating: 7, count: 100), [], Array(repeating: 9, count: 70_000)]
        var wire: [UInt8] = []
        for message in messages { wire += try RFBAppleRecords.frame(message, with: out) }
        // A message past one record's body spans two.
        var bodies: [UInt8] = []
        var records = 0
        var offset = 0
        while offset < wire.count {
            let length = Int(UInt16(wire[offset]) << 8 | UInt16(wire[offset + 1]))
            bodies += try RFBAppleRecords.open(Array(wire[(offset + 2)..<(offset + 2 + length)]), with: into)
            offset += 2 + length
            records += 1
        }
        #expect(records == 5 && bodies == messages.flatMap { $0 })

        let fresh = try RFBAppleRecordCipher(Self.keys, encrypting: false)
        var tampered = try RFBAppleRecords.frame([1, 2, 3], with: RFBAppleRecordCipher(Self.keys, encrypting: true))
        tampered[5] ^= 1
        #expect(throws: RFBError.self) { try RFBAppleRecords.open(Array(tampered.dropFirst(2)), with: fresh) }
    }

    @Test("the rekey's key and IV are each one AES-128 block, decrypted alone under the wrap key")
    func rekey() throws {
        let wrap = Array(repeating: UInt8(0x5a), count: 16)
        let body = UInt32(1).bigEndianBytes
            + (try RFBSecurity.encryptECB(algorithm: CCAlgorithm(kCCAlgorithmAES128), key: wrap, plaintext: Self.keys.key))
            + (try RFBSecurity.encryptECB(algorithm: CCAlgorithm(kCCAlgorithmAES128), key: wrap, plaintext: Self.keys.iv))
        let unwrapped = try RFBAppleRecordKeys.unwrap(rekey: body, wrapKey: wrap)
        #expect(unwrapped.generation == 1 && unwrapped.keys == Self.keys)
        #expect(throws: RFBError.self) { try RFBAppleRecordKeys.unwrap(rekey: Array(body.dropLast()), wrapKey: wrap) }
    }

    @Test("written messages go one to a record, in the order written, and reads span records")
    func layer() async throws {
        let source = MemoryByteSource([], holdsOpen: true), sink = MemoryByteSink()
        let layer = RFBAppleRecordLayer(source: source, sink: sink)
        try await layer.write([9, 9])
        try layer.install(Self.keys)
        for index in 0..<50 { try await layer.write([5, UInt8(index), 0, 0, 0, 0]) }
        await layer.finish()
        let written = await sink.written
        #expect(Array(written.prefix(2)) == [9, 9], "before the key: in the clear")
        let into = try RFBAppleRecordCipher(Self.keys, encrypting: false)
        var offset = 2, seen: [[UInt8]] = []
        while offset < written.count {
            let length = Int(UInt16(written[offset]) << 8 | UInt16(written[offset + 1]))
            seen.append(Array(try RFBAppleRecords.open(Array(written[(offset + 2)..<(offset + 2 + length)]), with: into)))
            offset += 2 + length
        }
        #expect(seen == (0..<50).map { [5, UInt8($0), 0, 0, 0, 0] })

        let out = try RFBAppleRecordCipher(Self.keys, encrypting: true)
        await source.append(try RFBAppleRecords.frame([1, 2, 3], with: out) + RFBAppleRecords.frame([4, 5], with: out))
        #expect(try await layer.read(4) == [1, 2, 3, 4])
        #expect(try await layer.read(1) == [5])
    }

    @Test("on 003.889 a Mac reads the mask as left, right, middle: RFB's middle and right swap")
    func pointerMask() {
        #expect(VNCClient.applePointerMask(0x01) == 0x01)
        #expect(VNCClient.applePointerMask(0x04) == 0x02, "a right-click")
        #expect(VNCClient.applePointerMask(0x02) == 0x04, "a middle-click")
        #expect(VNCClient.applePointerMask(0x0f) == 0x0f)
        #expect(VNCClient.applePointerMask(0x09) == 0x09, "the wheel's bits stay")
    }

    /// A Mac answering 003.889 end to end: type 30 against a real key exchange, the enhanced
    /// ServerInit, the prelude, the rekey, and a picture in records.
    @Test("a Mac is answered in its own revision: sign-in, prelude, rekey, then everything in records")
    func handshake() async throws {
        let prime = hexBytes(Vectors.prime)
        let group = try ModularExponentiation(modulusBigEndian: prime)
        let serverPrivate: [UInt8] = Array(repeating: 0x11, count: 32)
        let serverPublic = RFBSecurity.fit(try group.power(baseBigEndian: [2], exponentBigEndian: serverPrivate), to: 128)
        var greeting: [UInt8] = Array("RFB 003.889\n".utf8) + [1, 30]
        greeting += UInt16(2).bigEndianBytes + UInt16(128).bigEndianBytes + prime + serverPublic
        let source = MemoryByteSource(greeting, holdsOpen: true), sink = MemoryByteSink()
        final class Frames: @unchecked Sendable { let lock = NSLock(); var count = 0 }
        let frames = Frames()
        var callbacks = VNCClientCallbacks()
        callbacks.frame = { _, _, _ in frames.lock.withLock { frames.count += 1 } }
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", username: "alice", password: "secret",
                                                               appleProtocol: true),
                               callbacks: callbacks, source: source, sink: sink)
        let run = Task { try await client.run() }

        // The viewer's answer: version, type, then 128 bytes of credentials and its public key.
        for _ in 0..<200 where await sink.written.count < 13 + 256 { try await Task.sleep(for: .milliseconds(5)) }
        let answer = await sink.written
        #expect(Array(answer.prefix(12)) == Array("RFB 003.889\n".utf8), "answered in its own revision")
        let clientPublic = Array(answer[(13 + 128)..<(13 + 256)])
        let shared = RFBSecurity.fit(try group.power(baseBigEndian: clientPublic, exponentBigEndian: serverPrivate), to: 128)
        let wrap = Array(Insecure.MD5.hash(data: shared))

        // Signed in; the enhanced ServerInit; then, after the prelude, the rekey in the clear.
        var name: [UInt8] = [0, 0] + UInt32(0x10 | 0x02).bigEndianBytes
        name += [0xbf, 0xf6, 0xe7, 0x2f, 0xec] + [UInt8](repeating: 0, count: 11) + Array("Studio".utf8)
        var after = UInt32(0).bigEndianBytes
        after += UInt16(4).bigEndianBytes + UInt16(4).bigEndianBytes + RFBPixelFormat.client.wireBytes
        after += UInt32(name.count).bigEndianBytes + name
        await source.append(after)
        for _ in 0..<200 where await sink.written.count < 13 + 256 + 1 + 66 + 4 + 12 + 8 { try await Task.sleep(for: .milliseconds(5)) }
        let prelude = Array((await sink.written)[(13 + 256)...])
        #expect(prelude.first == 0x81, "shared, and the enhanced ServerInit asked for")
        #expect(Array(prelude.dropFirst()) == RFBAppleMessages.viewerInfo + RFBAppleMessages.setModeControl
                + RFBAppleMessages.setEncryptionStart + RFBAppleMessages.enableInboundDecryption)
        var rekey: [UInt8] = [0, 0, 0, 1] + [UInt8](repeating: 0, count: 8) + RFBAppleMessages.rekeyEncoding.bigEndianBytes
        rekey += UInt32(1).bigEndianBytes
        rekey += try RFBSecurity.encryptECB(algorithm: CCAlgorithm(kCCAlgorithmAES128), key: wrap, plaintext: Self.keys.key)
        rekey += try RFBSecurity.encryptECB(algorithm: CCAlgorithm(kCCAlgorithmAES128), key: wrap, plaintext: Self.keys.iv)
        // A status message the Mac may send in the clear before it.
        await source.append([0x14, 0, 0, 4, 0, 1, 0, 2] + rekey)

        // From here, records: one picture of the 4 × 4 desktop.
        let toClient = try RFBAppleRecordCipher(Self.keys, encrypting: true)
        let update: [UInt8] = [0, 0, 0, 1] + UInt16(0).bigEndianBytes + UInt16(0).bigEndianBytes + UInt16(1).bigEndianBytes
            + UInt16(1).bigEndianBytes + Int32(0).bigEndianBytes + [1, 2, 3, 0]
        await source.append(try RFBAppleRecords.frame(update, with: toClient))
        for _ in 0..<200 where frames.lock.withLock({ frames.count }) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(frames.lock.withLock { frames.count } >= 1, "the picture arrived through the record layer")
        #expect(client.isEncrypted)

        // What the viewer sent after the prelude: records, one message each, SetPixelFormat first.
        let written = await sink.written
        var offset = 13 + 256 + 1 + 66 + 4 + 12 + 8
        let fromClient = try RFBAppleRecordCipher(Self.keys, encrypting: false)
        var messages: [[UInt8]] = []
        while offset + 2 <= written.count {
            let length = Int(UInt16(written[offset]) << 8 | UInt16(written[offset + 1]))
            guard offset + 2 + length <= written.count else { break }
            messages.append(Array(try RFBAppleRecords.open(Array(written[(offset + 2)..<(offset + 2 + length)]), with: fromClient)))
            offset += 2 + length
        }
        #expect(messages.first?.first == 0 && messages.first?.count == 20, "SetPixelFormat, alone in its record")
        #expect(messages.dropFirst().first?.first == 2, "then SetEncodings")
        #expect(messages.contains { $0.first == 3 && $0.count == 10 }, "an update request, alone in its record")
        client.cancel()
        await source.close()
        _ = try? await run.value
    }
}
