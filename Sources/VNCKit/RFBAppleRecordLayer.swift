//
//  RFBAppleRecordLayer.swift
//  Glass Power Tools — VNCKit
//
//  Apple's record layer: the encrypted framing every byte of an RFB 003.889 session travels in once
//  the Mac has handed over a key. Ported from remotex's `src/vnc_record.rs` (MIT, Andrew Chen) and
//  its notes (`docs/apple-vnc-889.md`, "The record layer").
//
//  **Why it exists here (2026-10-11).** A Mac encrypts a session only when the viewer asks
//  (`SetEncryption`). Speaking plain 3.8, this client never asked, so after sign-in a session — its
//  keystrokes included — crossed the network in the clear. Apple's viewer leaves it off by default;
//  remotex always asks, and so does this client once it speaks 003.889.
//
//  **The frame.**
//
//      wire       u16 ciphertext_len || ciphertext
//      plaintext  u16 body_len || body || zero filler || 20-byte SHA-1
//                 filler = (−(2 + body_len + 20)) mod 16
//      integrity  SHA1(u32_be(sequence) || the plaintext before it)
//
//  Three properties are load-bearing, and each fails silently if missed:
//  - **One CBC chain per direction for the whole session.** A record's last ciphertext block is the
//    next record's IV: one CommonCrypto cryptor per direction, never reset.
//  - **A sequence number per direction that never resets.** It is not on the wire; the two ends
//    agree only while they count the same records.
//  - **One client message per record.** Two messages in one record: the Mac reads the first and
//    drops the second (remotex: a wheel's release lost, the button left held). A message longer
//    than a record spans several, which the Mac reassembles by concatenation, as this client does
//    with the Mac's.
//
//  Records also reach the wire in the order they were framed: the chain and the counter are the
//  order. Writes are framed and queued under one lock and written by one task.
//

import CommonCrypto
import CryptoKit
import Foundation

/// The AES-128 key and IV a rekey installs, one pair for both directions; each direction's chain
/// then advances on its own.
struct RFBAppleRecordKeys: Equatable, Sendable {
    let key: [UInt8]
    let iv: [UInt8]

    static let blockSize = 16
    /// A rekey's body: a `u32` generation, then the wrapped key and IV.
    static let rekeyLength = 4 + 2 * blockSize

    /// The key and IV a rekey carries: two AES-128 blocks, each decrypted on its own (ECB) under the
    /// wrap key both ends hold from type 30's sign-in, `MD5(shared secret)`.
    static func unwrap(rekey body: [UInt8], wrapKey: [UInt8]) throws -> (generation: UInt32, keys: RFBAppleRecordKeys) {
        guard body.count == rekeyLength, wrapKey.count == blockSize else {
            throw RFBError.protocolViolation("The Mac's encryption key arrived malformed.")
        }
        var reader = ByteReader(body)
        let generation = try reader.u32()
        let key = try RFBAppleRecordCipher.ecbDecrypt(Array(body[4..<20]), key: wrapKey)
        let iv = try RFBAppleRecordCipher.ecbDecrypt(Array(body[20..<36]), key: wrapKey)
        return (generation, RFBAppleRecordKeys(key: key, iv: iv))
    }
}

/// One direction's CBC chain and record counter.
final class RFBAppleRecordCipher: @unchecked Sendable {
    private var cryptor: CCCryptorRef?
    private(set) var sequence: UInt32 = 0

    init(_ keys: RFBAppleRecordKeys, encrypting: Bool) throws {
        let status = keys.key.withUnsafeBytes { key in
            keys.iv.withUnsafeBytes { iv in
                CCCryptorCreateWithMode(CCOperation(encrypting ? kCCEncrypt : kCCDecrypt), CCMode(kCCModeCBC),
                                        CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), iv.baseAddress,
                                        key.baseAddress, key.count, nil, 0, 0, 0, &cryptor)
            }
        }
        guard status == kCCSuccess, cryptor != nil else { throw RFBError.connectionFailed("The session's encryption could not start.") }
    }

    deinit { if let cryptor { CCCryptorRelease(cryptor) } }

    /// Encrypts or decrypts whole blocks in place, the chain carrying on from the last call.
    func update(_ data: inout [UInt8]) throws {
        guard data.count % RFBAppleRecordKeys.blockSize == 0 else {
            throw RFBError.protocolViolation("A record is not a whole number of blocks.")
        }
        guard !data.isEmpty else { return }
        let input = data
        var moved = 0
        let status = input.withUnsafeBytes { source in
            data.withUnsafeMutableBytes { output in
                CCCryptorUpdate(cryptor, source.baseAddress, input.count, output.baseAddress, output.count, &moved)
            }
        }
        guard status == kCCSuccess, moved == input.count else { throw RFBError.connectionFailed("A record could not be processed.") }
    }

    /// The integrity trailer for a record's plaintext before it, counting the record.
    func trailer(_ covered: ArraySlice<UInt8>) -> [UInt8] {
        var hash = Insecure.SHA1()
        hash.update(data: sequence.bigEndianBytes)
        hash.update(data: Data(covered))
        sequence &+= 1
        return Array(hash.finalize())
    }

    static func ecbDecrypt(_ block: [UInt8], key: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: block.count + blockPad)
        var moved = 0
        let status = key.withUnsafeBytes { keyBytes in
            block.withUnsafeBytes { input in
                output.withUnsafeMutableBytes { out in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            keyBytes.baseAddress, key.count, nil, input.baseAddress, block.count,
                            out.baseAddress, out.count, &moved)
                }
            }
        }
        guard status == kCCSuccess, moved == block.count else { throw RFBError.connectionFailed("The Mac's encryption key could not be read.") }
        return Array(output[0..<moved])
    }

    private static let blockPad = 16
}

/// Frames client messages into records, and opens the Mac's.
enum RFBAppleRecords {
    static let trailerLength = 20
    static let bodyLengthField = 2
    /// The largest record the `u16` length can state, in whole blocks.
    static let maximumCiphertext = (Int(UInt16.max) / RFBAppleRecordKeys.blockSize) * RFBAppleRecordKeys.blockSize
    static let maximumBody = maximumCiphertext - bodyLengthField - trailerLength
    static let minimumCiphertext = bodyLengthField + filler(0) + trailerLength

    static func filler(_ bodyLength: Int) -> Int {
        let block = RFBAppleRecordKeys.blockSize
        return (block - (bodyLengthField + bodyLength + trailerLength) % block) % block
    }

    /// One message, in as many records as it needs; an empty message is still one record.
    static func frame(_ message: [UInt8], with cipher: RFBAppleRecordCipher) throws -> [UInt8] {
        var out: [UInt8] = []
        var rest = message[...]
        repeat {
            let body = rest.prefix(maximumBody)
            rest = rest.dropFirst(body.count)
            let total = bodyLengthField + body.count + filler(body.count) + trailerLength
            var plaintext = UInt16(body.count).bigEndianBytes + Array(body)
            plaintext += [UInt8](repeating: 0, count: total - trailerLength - plaintext.count)
            let trailer = cipher.trailer(plaintext[...])
            plaintext += trailer
            try cipher.update(&plaintext)
            out += UInt16(total).bigEndianBytes + plaintext
        } while !rest.isEmpty
        return out
    }

    /// A record's body, once its integrity is checked; a record that fails it ends the session.
    static func open(_ ciphertext: [UInt8], with cipher: RFBAppleRecordCipher) throws -> ArraySlice<UInt8> {
        guard ciphertext.count >= minimumCiphertext else { throw RFBError.protocolViolation("The Mac sent a record too short to hold anything.") }
        var plaintext = ciphertext
        try cipher.update(&plaintext)
        let covered = plaintext.count - trailerLength
        let record = cipher.sequence
        guard Array(plaintext[covered...]) == cipher.trailer(plaintext[..<covered]) else {
            throw RFBError.protocolViolation("A record from the Mac failed its integrity check (record \(record)).")
        }
        let length = Int(UInt16(plaintext[0]) << 8 | UInt16(plaintext[1]))
        guard bodyLengthField + length <= covered else { throw RFBError.protocolViolation("A record from the Mac states a body longer than itself.") }
        return plaintext[bodyLengthField..<(bodyLengthField + length)]
    }
}

/// The client's source and sink: the bytes as they come until `install`, then the record layer.
/// The handshake reads and writes through it in the clear; everything after the rekey is records.
final class RFBAppleRecordLayer: RFBByteSource, RFBByteSink, @unchecked Sendable {
    private let source: any RFBByteSource
    private let sink: any RFBByteSink
    private let lock = NSLock()
    private var inbound: RFBAppleRecordCipher?
    private var outbound: RFBAppleRecordCipher?
    /// Opened bodies not yet read.
    private var plaintext: [UInt8] = []
    private var offset = 0
    /// Framed records in the order framed, written by one task.
    private var records: AsyncStream<[UInt8]>.Continuation?
    private var writer: Task<Void, Never>?
    private var failure: (any Error)?

    init(source: any RFBByteSource, sink: any RFBByteSink) {
        self.source = source
        self.sink = sink
    }

    var isEncrypted: Bool { lock.withLock { outbound != nil } }

    /// From now on both directions are records. Called once, between the rekey and the next byte
    /// either way: the Mac switches both its ciphers the moment it sends the rekey.
    func install(_ keys: RFBAppleRecordKeys) throws {
        let inbound = try RFBAppleRecordCipher(keys, encrypting: false)
        let outbound = try RFBAppleRecordCipher(keys, encrypting: true)
        let (stream, continuation) = AsyncStream.makeStream(of: [UInt8].self)
        let sink = sink
        let task = Task { [weak self] in
            for await record in stream {
                do { try await sink.write(record) } catch {
                    self?.lock.withLock { self?.failure = error }
                    return
                }
            }
        }
        lock.withLock {
            self.inbound = inbound
            self.outbound = outbound
            self.records = continuation
            self.writer = task
        }
    }

    /// Lets the writer finish what is queued, then stops it.
    func finish() async {
        let (continuation, task) = lock.withLock { (records, writer) }
        continuation?.finish()
        await task?.value
    }

    func write(_ bytes: [UInt8]) async throws {
        let queued: Bool = try lock.withLock {
            if let failure { throw failure }
            guard let outbound, let records else { return false }
            records.yield(try RFBAppleRecords.frame(bytes, with: outbound))
            return true
        }
        if !queued { try await sink.write(bytes) }
    }

    func read(_ count: Int) async throws -> [UInt8] {
        guard let inbound = lock.withLock({ inbound }) else { return try await source.read(count) }
        while plaintext.count - offset < count {
            let header = try await source.read(2)
            let length = Int(UInt16(header[0]) << 8 | UInt16(header[1]))
            guard length % RFBAppleRecordKeys.blockSize == 0, length >= RFBAppleRecords.minimumCiphertext else {
                throw RFBError.protocolViolation("The Mac sent a record of \(length) bytes, which is not a record.")
            }
            let body = try RFBAppleRecords.open(try await source.read(length), with: inbound)
            if offset > 0 { plaintext.removeFirst(offset); offset = 0 }
            plaintext += body
        }
        let result = Array(plaintext[offset..<(offset + count)])
        offset += count
        if offset == plaintext.count { plaintext.removeAll(keepingCapacity: true); offset = 0 }
        return result
    }
}

/// The messages a Mac's revision adds before its record layer (remotex's `src/vnc_apple.rs`).
enum RFBAppleMessages {
    /// The rectangle encoding the record layer's key arrives in, before the layer exists.
    static let rekeyEncoding: Int32 = 0x44f

    /// `ViewerInfo` (0x21): a `u16` length of 62, then numbers — a generic viewer (1), Screen Sharing
    /// (2), version 6.1, macOS 26.6.2, and the 32-byte bitmap of the server messages Apple's viewer
    /// handles — as remotex measured Apple's viewer sending it. A mis-sized body makes the Mac swallow
    /// the next message and hang.
    static let viewerInfo: [UInt8] = {
        var message = [UInt8](repeating: 0, count: 66)
        message[0] = 0x21
        message.replace(2, UInt16(62).bigEndianBytes)
        message.replace(4, UInt16(1).bigEndianBytes)
        message.replace(6, UInt32(2).bigEndianBytes)
        message.replace(10, UInt32(6).bigEndianBytes)
        message.replace(14, UInt32(1).bigEndianBytes)
        // The OS version: a Mac takes keys from a viewer it believes older than 10.15 the old way.
        message.replace(22, UInt32(26).bigEndianBytes)
        message.replace(26, UInt32(6).bigEndianBytes)
        message.replace(30, UInt32(2).bigEndianBytes)
        message[34] = 0xb0; message[36] = 0x0c; message[37] = 0x03; message[38] = 0x90; message[44] = 0x40
        return message
    }()

    /// The second event message (0x17), kind 11, a scroll by a distance (remotex's `scroll_wheel`;
    /// the notes, "A Mac scrolls by a distance"): 58 bytes, `u16` size 54, version 1, then line
    /// deltas as three `i16`, the same in 16.16 fixed point as three `i32`, point deltas as three
    /// `i32`, scroll phase, momentum phase and scroll count (0: no gesture around it), flags (2,
    /// continuous: the point delta is the one that counts), and the pointer's position. Each three is
    /// horizontal, vertical and an axis no device has; up and left are positive, as macOS counts them.
    static func scrollWheel(horizontalPoints: Int, verticalPoints: Int, x: Int, y: Int) -> [UInt8] {
        let pointsPerLine = 10
        let axes = [Int32(clamping: horizontalPoints), Int32(clamping: verticalPoints), 0]
        var message: [UInt8] = [0x17, 0] + UInt16(54).bigEndianBytes + UInt16(1).bigEndianBytes + UInt16(11).bigEndianBytes
        for points in axes { message += UInt16(bitPattern: Int16(clamping: Int(points) / pointsPerLine)).bigEndianBytes }
        for points in axes { message += UInt32(bitPattern: Int32(clamping: Int64(points) * 65_536 / Int64(pointsPerLine))).bigEndianBytes }
        for points in axes { message += UInt32(bitPattern: points).bigEndianBytes }
        message += [UInt8](repeating: 0, count: 12)
        message += UInt32(2).bigEndianBytes
        message += UInt16(clamping: max(0, x)).bigEndianBytes + UInt16(clamping: max(0, y)).bigEndianBytes
        return message
    }

    /// `SetMode` (0x0a): control.
    static let setModeControl: [UInt8] = [0x0a, 0, 0, 1]
    /// `SetEncryption` (0x12) command 1, AES-128 the one method: the Mac answers with the rekey. The
    /// bytes as Apple's viewer sends them.
    static let setEncryptionStart: [UInt8] = [0x12, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1]
    /// `SetEncryption` command 2, argument 1: the Mac decrypts what it receives after the rekey.
    static let enableInboundDecryption: [UInt8] = [0x12, 0, 0, 2, 0, 1, 0, 0]
}

private extension Array where Element == UInt8 {
    mutating func replace(_ offset: Int, _ bytes: [UInt8]) {
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }
}
