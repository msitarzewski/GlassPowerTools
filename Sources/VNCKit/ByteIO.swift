import Foundation

/// Bounds-checked big-endian reader over an in-memory buffer.
public struct ByteReader {
    public let bytes: [UInt8]
    public private(set) var offset: Int

    public init(_ bytes: [UInt8], offset: Int = 0) { self.bytes = bytes; self.offset = offset }
    public var remaining: Int { bytes.count - offset }
    public var isAtEnd: Bool { offset >= bytes.count }

    public mutating func u8() throws -> UInt8 {
        guard offset < bytes.count else { throw RFBError.protocolViolation("The server message ended early.") }
        defer { offset += 1 }
        return bytes[offset]
    }

    public mutating func u16() throws -> UInt16 {
        let high = try u8(), low = try u8()
        return UInt16(high) << 8 | UInt16(low)
    }

    public mutating func u32() throws -> UInt32 {
        let high = try u16(), low = try u16()
        return UInt32(high) << 16 | UInt32(low)
    }

    public mutating func s32() throws -> Int32 { Int32(bitPattern: try u32()) }

    public mutating func bytes(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= remaining else { throw RFBError.protocolViolation("The server message ended early.") }
        defer { offset += count }
        return bytes[offset..<(offset + count)]
    }
}

/// Exactly-sized asynchronous reads; a short read is a closed connection.
public protocol RFBByteSource: Sendable {
    func read(_ count: Int) async throws -> [UInt8]
}

public protocol RFBByteSink: Sendable {
    func write(_ bytes: [UInt8]) async throws
}

extension RFBByteSource {
    func u8() async throws -> UInt8 { try await read(1)[0] }
    func u16() async throws -> UInt16 {
        let bytes = try await read(2)
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }
    func u32() async throws -> UInt32 {
        let bytes = try await read(4)
        return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }
    func s32() async throws -> Int32 { Int32(bitPattern: try await u32()) }
}

/// In-memory source used by deterministic tests. With `holdsOpen`, a read past the end waits
/// for more data or `close()` instead of reporting a closed connection.
public actor MemoryByteSource: RFBByteSource {
    private var bytes: [UInt8]
    private var offset = 0
    private let holdsOpen: Bool
    private var closed = false
    private var waiter: CheckedContinuation<Void, Never>?
    public init(_ bytes: [UInt8], holdsOpen: Bool = false) { self.bytes = bytes; self.holdsOpen = holdsOpen }
    public var remaining: Int { bytes.count - offset }
    public func read(_ count: Int) async throws -> [UInt8] {
        guard count >= 0 else { throw RFBError.protocolViolation("Negative read length.") }
        while count > bytes.count - offset {
            guard holdsOpen, !closed else { throw RFBError.connectionClosed }
            await withCheckedContinuation { waiter = $0 }
        }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }
    public func append(_ more: [UInt8]) {
        bytes.append(contentsOf: more)
        waiter?.resume(); waiter = nil
    }
    public func close() {
        closed = true
        waiter?.resume(); waiter = nil
    }
}

public actor MemoryByteSink: RFBByteSink {
    public private(set) var written: [UInt8] = []
    public init() {}
    public func write(_ bytes: [UInt8]) async throws { written.append(contentsOf: bytes) }
    public func drain() -> [UInt8] { defer { written.removeAll() }; return written }
}
