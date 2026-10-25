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

    /// remotex's notes, "A Mac scrolls by a distance": 40 points right and 25 up arrive as exactly that.
    @Test("a scroll by a distance is 58 bytes: lines, lines in 16.16, points, no phase, continuous, the position")
    func scrollWheel() {
        let message = RFBAppleMessages.scrollWheel(horizontalPoints: -40, verticalPoints: 25, x: 300, y: 200)
        #expect(message.count == 58)
        #expect(Array(message[0..<8]) == [0x17, 0, 0, 54, 0, 1, 0, 11])
        #expect(Array(message[8..<14]) == UInt16(bitPattern: -4).bigEndianBytes + UInt16(2).bigEndianBytes + [0, 0], "lines: a tenth")
        #expect(Array(message[14..<26]) == UInt32(bitPattern: Int32(-262_144)).bigEndianBytes + UInt32(163_840).bigEndianBytes + [0, 0, 0, 0],
                "the same lines in 16.16: −4.0 and 2.5")
        #expect(Array(message[26..<38]) == UInt32(bitPattern: -40).bigEndianBytes + UInt32(25).bigEndianBytes + [0, 0, 0, 0], "points")
        #expect(Array(message[38..<50]) == [UInt8](repeating: 0, count: 12), "no phase, no momentum, no count")
        #expect(Array(message[50..<54]) == [0, 0, 0, 2], "continuous")
        #expect(Array(message[54..<58]) == UInt16(300).bigEndianBytes + UInt16(200).bigEndianBytes)
    }

    @Test("a pasteboard archive: one text flavor going out, an empty item clearing, the first text flavor read back")
    func pasteboardArchive() throws {
        let archive = RFBApplePasteboard.archive(Array("hé".utf8))
        #expect(try RFBApplePasteboard.text(in: archive) == "hé")
        #expect(RFBApplePasteboard.archive([]) == [0, 0, 0, 0], "an item with no flavors clears the Mac's pasteboard")
        #expect(try RFBApplePasteboard.text(in: RFBApplePasteboard.archive([])) == nil)
        let message = try RFBApplePasteboard.send("hé", session: 9)
        #expect(Array(message[0..<12]) == [0x1f, 0, 0, 0, 0, 0, 0, 9] + UInt32(archive.count).bigEndianBytes)
        #expect(Int(UInt32(message[12]) << 24 | UInt32(message[13]) << 16 | UInt32(message[14]) << 8 | UInt32(message[15])) == message.count - 16)
        #expect(try ZlibInflater().inflateAll(Array(message[16...])) == archive)
        #expect(throws: RFBError.self) { try RFBApplePasteboard.text(in: UInt32(1).bigEndianBytes + UInt32(5000).bigEndianBytes) }
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
        final class Frames: @unchecked Sendable { let lock = NSLock(); var count = 0; var texts: [String] = [] }
        let frames = Frames()
        var callbacks = VNCClientCallbacks()
        callbacks.frame = { _, _, _ in frames.lock.withLock { frames.count += 1 } }
        callbacks.cutText = { text in frames.lock.withLock { frames.texts.append(text) } }
        let client = VNCClient(configuration: VNCConfiguration(host: "mac.example", username: "alice", password: "secret",
                                                               clipboardEnabled: true, appleProtocol: true),
                               callbacks: callbacks, source: source, sink: sink)
        let run = Task { try await client.run() }

        // The viewer's answer: version, type, then 128 bytes of credentials and its public key.
        for _ in 0..<6_000 where await sink.written.count < 13 + 256 { try await Task.sleep(for: .milliseconds(5)) }
        let answer = await sink.written
        #expect(Array(answer.prefix(12)) == Array("RFB 003.889\n".utf8), "answered in its own revision")
        // Required before slicing: a short answer was an out-of-range crash, which ended the whole run.
        try #require(answer.count >= 13 + 256, "the viewer's answer: \(answer.count) bytes")
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
        for _ in 0..<6_000 where await sink.written.count < 13 + 256 + 1 + 66 + 4 + 8 + 12 + 8 { try await Task.sleep(for: .milliseconds(5)) }
        let afterAnswer = await sink.written
        let preludeLength: Int = 13 + 256 + 1 + 66 + 4 + 8 + 12 + 8
        try #require(afterAnswer.count >= preludeLength, "the prelude: \(afterAnswer.count) bytes")
        let prelude = Array(afterAnswer[(13 + 256)...])
        #expect(prelude.first == 0x81, "shared, and the enhanced ServerInit asked for")
        #expect(Array(prelude.dropFirst()) == RFBAppleMessages.viewerInfo + RFBAppleMessages.setModeControl
                + RFBApplePasteboard.autoPasteboard(true) + RFBAppleMessages.setEncryptionStart + RFBAppleMessages.enableInboundDecryption,
                "the pasteboard watched, in the clear, after ViewerInfo and SetMode")
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
        for _ in 0..<6_000 where frames.lock.withLock({ frames.count }) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(frames.lock.withLock { frames.count } >= 1, "the picture arrived through the record layer")
        #expect(client.isEncrypted)
        // Its ServerInit lists the second event message: a scroll goes as a distance, in its own record.
        #expect(client.acceptsAppleScroll)
        try await client.sendAppleScroll(horizontalPoints: 0, verticalPoints: 30, x: 1, y: 2)
        // Its pasteboard changed; fetched; answered with rich text before the plain text.
        await source.append(try RFBAppleRecords.frame([0x14, 0, 0, 4, 0, 1, 0, 2], with: toClient))
        let rich = Array("{\\rtf1 copied}".utf8), plain = Array("copied on the Mac ✓".utf8)
        var archive = UInt32(2).bigEndianBytes
        archive += UInt32(15).bigEndianBytes + Array("public.rtf-data".utf8) + UInt32(0).bigEndianBytes
        archive += UInt32(1).bigEndianBytes + UInt32(3).bigEndianBytes + Array("key".utf8) + UInt32(5).bigEndianBytes + Array("value".utf8)
        archive += UInt32(rich.count).bigEndianBytes + rich
        archive += UInt32(RFBApplePasteboard.textFlavor.count).bigEndianBytes + RFBApplePasteboard.textFlavor + UInt32(0).bigEndianBytes
        archive += UInt32(0).bigEndianBytes + UInt32(plain.count).bigEndianBytes + plain
        let compressed = try ZlibDeflater.syncFlushed(archive)
        let reply: [UInt8] = [0x1f, 0, 0, 0] + UInt32(7).bigEndianBytes + UInt32(archive.count).bigEndianBytes
            + UInt32(compressed.count).bigEndianBytes + compressed
        await source.append(try RFBAppleRecords.frame(reply, with: toClient))
        for _ in 0..<6_000 where frames.lock.withLock({ frames.texts.isEmpty }) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(frames.lock.withLock { frames.texts } == ["copied on the Mac ✓"], "the text flavor, as UTF-8")
        try await client.sendCutText("pasted on the headset é")

        // What the viewer sent after the prelude: records, one message each, SetPixelFormat first.
        // Records reach the sink after the send returns, so read until this client's pasteboard is in.
        var offset = 13 + 256 + 1 + 66 + 4 + 8 + 12 + 8
        let fromClient = try RFBAppleRecordCipher(Self.keys, encrypting: false)
        var messages: [[UInt8]] = []
        for _ in 0..<6_000 where !messages.contains(where: { $0.first == 0x1f }) {
            let written = await sink.written
            while offset + 2 <= written.count {
                let length = Int(UInt16(written[offset]) << 8 | UInt16(written[offset + 1]))
                guard offset + 2 + length <= written.count else { break }
                messages.append(Array(try RFBAppleRecords.open(Array(written[(offset + 2)..<(offset + 2 + length)]), with: fromClient)))
                offset += 2 + length
            }
            if !messages.contains(where: { $0.first == 0x1f }) { try await Task.sleep(for: .milliseconds(5)) }
        }
        #expect(messages.first?.first == 0 && messages.first?.count == 20, "SetPixelFormat, alone in its record")
        #expect(messages.dropFirst().first?.first == 2, "then SetEncodings")
        #expect(messages.contains { $0.first == 3 && $0.count == 10 }, "an update request, alone in its record")
        #expect(messages.contains { $0 == RFBAppleMessages.scrollWheel(horizontalPoints: 0, verticalPoints: 30, x: 1, y: 2) },
                "the scroll, alone in its record")
        #expect(messages.contains { $0 == RFBApplePasteboard.fetch(session: 0) }, "the fetch, in its own record")
        let sent = try #require(messages.first { $0.first == 0x1f }, "this client's pasteboard, as the Mac's message")
        #expect(Array(sent[4..<8]) == UInt32(7).bigEndianBytes, "the session the Mac's reply named")
        let outbound = try ZlibInflater().inflateAll(Array(sent[16...]))
        #expect(try RFBApplePasteboard.text(in: outbound) == "pasted on the headset é")
        #expect(!messages.contains { $0.first == 6 }, "never ClientCutText to a Mac")
        client.cancel()
        await source.close()
        _ = try? await run.value
    }
}
