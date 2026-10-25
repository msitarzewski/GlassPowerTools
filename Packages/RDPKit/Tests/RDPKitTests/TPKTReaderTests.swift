import Foundation
import NIOCore
import NIOEmbedded
@testable import RDPKit
import Testing

/// A server ends a session by sending its reason, an ErrorInfo and a Deactivate All, and hanging up.
/// Both can be in the reader, whole, before the client asks for them; the close must not discard them.
/// (`liveDeactivateThenEOFHonorsOptionalReasonAndExplicitDenial` met this only when the run was busy.)
@Test func tpktReaderDeliversWhatArrivedBeforeTheServerHungUp() throws {
    let reader = TLSTPKTStreamHandler()
    let channel = EmbeddedChannel(handler: reader)
    let errorInfo = Data([0x03, 0x00, 0x00, 0x05, 0xAA])
    let deactivate = Data([0x03, 0x00, 0x00, 0x06, 0xBB, 0xCC])
    try channel.writeInbound(ByteBuffer(bytes: errorInfo + deactivate))
    try channel.close().wait()

    var results: [Result<Data, Error>] = []
    for _ in 0 ..< 3 {
        reader.nextPacket(on: channel).whenComplete { results.append($0) }
        channel.embeddedEventLoop.run()
    }
    #expect(results.count == 3)
    #expect((try? results[0].get()) == errorInfo)
    #expect((try? results[1].get()) == deactivate)
    #expect((try? results[2].get()) == nil, "then the disconnect")
}

/// An error or a cancellation still ends reading at once: nothing queued is handed on after it.
@Test func tpktReaderDropsWhatIsQueuedOnAFailure() throws {
    let reader = TLSTPKTStreamHandler()
    let channel = EmbeddedChannel(handler: reader)
    try channel.writeInbound(ByteBuffer(bytes: [0x03, 0x00, 0x00, 0x05, 0xAA]))
    reader.fail(RDPPreflightError.cancelled)

    var result: Result<Data, Error>?
    reader.nextPacket(on: channel).whenComplete { result = $0 }
    channel.embeddedEventLoop.run()
    #expect((try? result?.get()) == nil)
    _ = try? channel.finish()
}
