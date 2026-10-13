import XCTest
import NIO
@testable import Citadel

/// Glass Power Tools patch C12 (`PATCHES.md`): a composite SSH string written into a buffer with no
/// room left writes its length placeholder instead of moving the writer index past the end, which
/// traps. Diffie-Hellman group 14 writes one into the exchange-hash buffer the server's KEXINIT has
/// filled, so the server decides how full that buffer is.
final class CompositeStringTests: XCTestCase {
    func testIntoABufferWithNoRoomLeft() {
        var buffer = ByteBufferAllocator().buffer(capacity: 16)
        buffer.writeRepeatingByte(0xAB, count: buffer.writableBytes)
        XCTAssertEqual(buffer.writableBytes, 0)
        let before = buffer.writerIndex

        let written = buffer.writeCompositeSSHString { $0.writeBytes([1, 2, 3]) }

        XCTAssertEqual(written, 7)
        XCTAssertEqual(buffer.writerIndex, before + 7)
        XCTAssertEqual(buffer.getInteger(at: before, as: UInt32.self), 3)
        XCTAssertEqual(buffer.getBytes(at: before + 4, length: 3), [1, 2, 3])
    }

    func testABodyThatThrowsLeavesTheBufferAsItWas() {
        struct Refused: Error {}
        var buffer = ByteBufferAllocator().buffer(capacity: 16)
        buffer.writeBytes([9, 9])
        let before = buffer.writerIndex
        XCTAssertThrowsError(try buffer.writeCompositeSSHString { _ in throw Refused() })
        XCTAssertEqual(buffer.writerIndex, before)
    }
}
