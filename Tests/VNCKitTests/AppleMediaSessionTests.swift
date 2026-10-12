import Foundation
import Testing
@testable import VNCKit

/// A High Performance stream's offers, replies and deadlines (after remotex's `MediaStream` tests).
@Suite("Apple media stream: the session")
struct AppleMediaSessionTests {
    private let ports = hexBytes("0001000100000000170c00000001170d0000000100000000000000000000000000000000")
    private let answer = hexBytes("000200020000000000000000000000000000")
    private let start = ContinuousClock.now

    @Test("the encodings first; an offer only once the Mac has named its ports, once per display, one at a time")
    func offers() throws {
        let media = RFBAppleMediaSession()
        let size: [RFBAppleMediaSession.Size] = [(3200, 2000)]
        #expect(try media.offer(sizes: size, at: start) == .encodings)
        #expect(try media.offer(sizes: size, at: start) == nil, "the ports are owed")
        #expect(try media.reply(ports) == .init(bind: .init(audio: 5900, videos: [5901]), streamDown: false))
        guard case .configuration(let message)? = try media.offer(sizes: size, at: start) else {
            Issue.record("an offer once the ports are named"); return
        }
        #expect(message[0] == 0x1c && media.awaitingAnswer)
        #expect(try media.offer(sizes: [(1600, 1000)], at: start) == nil, "one offer at a time")
        _ = try media.reply(answer)
        #expect(!media.awaitingAnswer)
        #expect(try media.offer(sizes: size, at: start) == nil, "the stream already runs at that size")
        #expect(try media.offer(sizes: [(1600, 1000)], at: start) == nil, "each naming is good for one offer")
        // A display change: the Mac names its ports again, the stream is down, and the new size is
        // offered on that naming.
        #expect(try media.reply(ports) == .init(bind: nil, streamDown: true), "the same ports stay bound")
        if case .configuration? = try media.offer(sizes: [(1600, 1000)], at: start) {} else { Issue.record("the new display's offer") }
        #expect(try media.offer(sizes: [(1600, 1000), (1600, 1000)], at: start) == nil, "not one size a leg")
    }

    @Test("the offer carries this session's keys and the capped bitrates")
    func offerContents() throws {
        let media = RFBAppleMediaSession(bitrates: [8_000_000, 8_000_000, 8_000_000, 8_000_000, 8_000_000, 6_000_000])
        _ = try media.offer(sizes: [(1600, 1000)], at: start)
        _ = try media.reply(ports)
        guard case .configuration(let message)? = try media.offer(sizes: [(1600, 1000)], at: start) else { Issue.record("offer"); return }
        #expect(Array(message[0x14..<0x24]) == media.sessionUUID)
        #expect(Array(message[0x24..<0x52]) == media.audioKeys.toMac && Array(message[0x52..<0x80]) == media.audioKeys.fromMac)
        let audioLength = Int(message[0x0a]) << 8 | Int(message[0x0b])
        let videoKeys = 0x80 + audioLength
        #expect(Array(message[videoKeys..<(videoKeys + 46)]) == media.videos[0].keys.toMac)
        #expect(Array(message[6..<10]) == [0, 0, 0, 5])
    }

    @Test("refusals and a second viewer end the session with what the Mac said")
    func refusals() throws {
        let media = RFBAppleMediaSession()
        #expect(throws: RFBError.self) { try media.reply(hexBytes("00030001000000000000000200000000")) }
        #expect(throws: RFBError.unsupported("Another viewer already has this Mac's High Performance picture; a Mac gives it to one viewer at a time.")) {
            try media.reply(hexBytes("00030001000000000000000100000001"))
        }
        var two = ports
        two.replaceSubrange(20..<22, with: UInt16(5902).bigEndianBytes)
        two[25] = 1
        #expect(throws: RFBError.self, "two picture legs for one display") { try media.reply(two) }
    }

    @Test("each deadline: the ports, the answer, the first picture and sound, and silence")
    func deadlines() throws {
        let media = RFBAppleMediaSession()
        func at(_ seconds: Double) -> ContinuousClock.Instant { start + .milliseconds(Int(seconds * 1000)) }
        #expect(media.overdue(at: at(100)) == nil, "nothing is owed before the encodings")
        _ = try media.offer(sizes: [(1600, 1000)], at: at(0))
        #expect(media.overdue(at: at(9.9)) == nil)
        #expect(media.overdue(at: at(10)) != nil, "no ports in ten seconds")
        _ = try media.reply(ports)
        #expect(media.overdue(at: at(11)) == nil)
        _ = try media.offer(sizes: [(1600, 1000)], at: at(11))
        #expect(media.overdue(at: at(21))?.errorDescription?.contains("did not answer") == true)
        _ = try media.reply(answer)
        #expect(media.overdue(at: at(21))?.errorDescription?.contains("UDP 5901") == true, "no picture: the port is named")
        media.pictured(leg: 0, size: (1600, 1000), at: at(12))
        #expect(media.overdue(at: at(21))?.errorDescription?.contains("UDP 5900") == true, "no sound")
        media.soundHeard(sound: true, at: at(12))
        #expect(media.overdue(at: at(21)) == nil)
        media.pictured(leg: 0, size: (800, 500), at: at(30))
        #expect(media.overdue(at: at(60)) != nil, "a picture of another size is not this stream's")
        media.heard(leg: 0, at: at(50))
        media.soundHeard(sound: false, at: at(50))
        #expect(media.overdue(at: at(97)) == nil, "the Mac's reports keep both legs alive")
        #expect(media.overdue(at: at(98))?.errorDescription == "The Mac's High Performance picture stopped.")
        media.displayChanged()
        #expect(media.overdue(at: at(500)) == nil, "a display change owes nothing until the next offer")
    }
}
