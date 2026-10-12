import Foundation
import Testing
@testable import VNCKit

/// The media stream's SRTP and reports, against vectors remotex's independent Python implementation
/// made — the one that decrypted and authenticated a Mac's own packets — and a rate report a Mac
/// took (remotex `src/vnc_apple_media.rs` tests, MIT).
@Suite("Apple media stream: SRTP and reports")
struct AppleSRTPTests {
    /// The master key 0, 1, …, 45 the vectors were made with.
    private let master = (0..<46).map { UInt8($0) }
    private let packet = hexBytes("80e412340a0b0c0dcafebabe610005049285d9955b8928769900c5323d679c04bbccbf")

    @Test("a packet an independent implementation protected is authenticated and decrypted")
    func unprotect() throws {
        var data = packet
        var receiver = try RFBAppleSRTP.Receiver(master: master)
        let header = try receiver.unprotect(&data)
        #expect(header.payloadType == 100 && header.marker && header.sequence == 0x1234)
        #expect(header.timestamp == 0x0a0b_0c0d && header.ssrc == 0xcafe_babe)
        #expect(Array(data[header.payload]) == [0x02, 0x01] + Array("hello, hevc".utf8))

        var forged = packet
        forged[14] ^= 1
        var fresh = try RFBAppleSRTP.Receiver(master: master)
        #expect(throws: RFBAppleSRTP.Failure.forged) { try fresh.unprotect(&forged) }
        var otherKey = packet
        var stranger = try RFBAppleSRTP.Receiver(master: .init(repeating: 7, count: 46))
        #expect(throws: RFBAppleSRTP.Failure.forged) { try stranger.unprotect(&otherKey) }
    }

    @Test("a duplicate and a straggler are refused; a new stream starts over")
    func stale() throws {
        var receiver = try RFBAppleSRTP.Receiver(master: master)
        var first = packet
        _ = try receiver.unprotect(&first)
        var again = packet
        #expect(throws: RFBAppleSRTP.Failure.stale) { try receiver.unprotect(&again) }
        receiver.remember(ssrc: 0xcafe_babe, sequence: 0x1235, roc: 0)
        var overtaken = packet
        #expect(throws: RFBAppleSRTP.Failure.stale) { try receiver.unprotect(&overtaken) }
        receiver.remember(ssrc: 0x0102_0304, sequence: 0x1235, roc: 0)
        var other = packet
        #expect(throws: Never.self) { _ = try receiver.unprotect(&other) }
    }

    @Test("the rollover counter follows a wrap and a straggler")
    func rollover() throws {
        var receiver = try RFBAppleSRTP.Receiver(master: master)
        #expect(receiver.guessROC(ssrc: 1, sequence: 5) == 0)
        receiver.remember(ssrc: 1, sequence: 0xfff0, roc: 0)
        #expect(receiver.guessROC(ssrc: 1, sequence: 0x0002) == 1, "past the wrap")
        #expect(receiver.guessROC(ssrc: 1, sequence: 0xffff) == 0)
        receiver.remember(ssrc: 1, sequence: 0x0002, roc: 1)
        #expect(receiver.guessROC(ssrc: 1, sequence: 0xfff5) == 0, "a late packet from before the wrap")
        #expect(receiver.guessROC(ssrc: 1, sequence: 0x0010) == 1)
        #expect(receiver.guessROC(ssrc: 2, sequence: 0x0010) == 0, "a new stream starts over")
    }

    @Test("RTCP and RTP are told apart")
    func rtcpIsNotRTP() throws {
        var receiver = try RFBAppleSRTP.Receiver(master: master)
        var rtcp = hexBytes("80c90001010203040000000000000000000000")
        #expect(throws: RFBAppleSRTP.Failure.rtcp) { try receiver.unprotect(&rtcp) }
        var junk = [UInt8](repeating: 0x40, count: 30)
        #expect(throws: RFBAppleSRTP.Failure.notRTP) { try receiver.unprotect(&junk) }
        #expect(RFBAppleSRTP.receiverReport(ssrc: 0x0102_0304) == [0x80, 201, 0, 1, 1, 2, 3, 4])
    }

    @Test("SRTCP protects as an independent implementation does, its index counting up")
    func protect() throws {
        var sender = try RFBAppleSRTP.ReportSender(master: master)
        #expect(sender.protect(RFBAppleSRTP.pictureLoss(ssrc: 0x0102_0304, mediaSSRC: 0xcafe_babe))
                == hexBytes("81ce00020102030456a0870b8000000085553297faec4eb2d978"))
        #expect(sender.protect(RFBAppleSRTP.receiverReport(ssrc: 0x0102_0304))
                == hexBytes("80c900010102030480000001bcb6f8d4262f3495b496"))
    }

    @Test("the Mac's reports are authenticated, and a forged or replayed one refused")
    func authenticate() throws {
        var sender = try RFBAppleSRTP.ReportSender(master: master)
        let first = sender.protect(RFBAppleSRTP.receiverReport(ssrc: 0x0102_0304))
        let second = sender.protect(RFBAppleSRTP.receiverReport(ssrc: 0x0102_0304))
        var reports = try RFBAppleSRTP.ReportReceiver(master: master)
        #expect(throws: Never.self) { try reports.authenticate(first) }
        #expect(throws: RFBAppleSRTP.Failure.stale) { try reports.authenticate(first) }
        #expect(throws: Never.self) { try reports.authenticate(second) }
        #expect(throws: RFBAppleSRTP.Failure.stale) { try reports.authenticate(first) }
        var forged = second
        forged[9] ^= 1
        var fresh = try RFBAppleSRTP.ReportReceiver(master: master)
        #expect(throws: RFBAppleSRTP.Failure.forged) { try fresh.authenticate(forged) }
        var stranger = try RFBAppleSRTP.ReportReceiver(master: .init(repeating: 7, count: 46))
        #expect(throws: RFBAppleSRTP.Failure.forged) { try stranger.authenticate(second) }
        #expect(throws: RFBAppleSRTP.Failure.notRTP) { try fresh.authenticate(Array(second[0..<20])) }
        var otherSender = try RFBAppleSRTP.ReportSender(master: master)
        #expect(throws: Never.self) { try reports.authenticate(otherSender.protect(RFBAppleSRTP.receiverReport(ssrc: 0x0506_0708))) }
        #expect(throws: RFBAppleSRTP.Failure.stale) { try reports.authenticate(second) }
    }

    @Test("the refresh request and the acknowledgement are AVConference's")
    func avconference() {
        #expect(RFBAppleSRTP.refreshRequest(ssrc: 1, mediaSSRC: 2, width: 1600, height: 1000)
                == [0x82, 206, 0, 3, 0, 0, 0, 1, 0, 0, 0, 2, 0x06, 0x40, 0x03, 0xe8])
        #expect(RFBAppleSRTP.referenceAcknowledgement(ssrc: 1, timestamp: 0x0a0b_0c0d)
                == [0x80, 204, 0, 3, 0, 0, 0, 1, 0, 0, 0, 5, 0x0a, 0x0b, 0x0c, 0x0d])
        #expect(RFBAppleSRTP.pictureLoss(ssrc: 1, mediaSSRC: 2) == [0x81, 206, 0, 2, 0, 0, 0, 1, 0, 0, 0, 2])
    }

    @Test("a refresh picture is marked in the header extension")
    func refreshMark() throws {
        func packet(profile: UInt16) -> [UInt8] {
            [0x90, 100, 0, 1, 0, 0, 0, 1, 0, 0, 0, 9] + profile.bigEndianBytes + [0, 1, 0, 0, 0, 0] + [UInt8](repeating: 0, count: 12)
        }
        #expect(try RFBAppleSRTP.header(packet(profile: 0x9331)).refresh)
        #expect(try !RFBAppleSRTP.header(packet(profile: 0x9311)).refresh)
        #expect(try !RFBAppleSRTP.header(packet(profile: 0x9301)).refresh)
        #expect(try RFBAppleSRTP.header(packet(profile: 0x9331)).payload == 20..<22)
    }

    /// Byte for byte a report the Mac took, 5.9 s into its stream with 2970 picture packets in.
    @Test("a rate report is one the Mac took")
    func rateReport() {
        let epoch = ContinuousClock.now
        let at = epoch + .nanoseconds(5_908_203_200)
        var feedback = RFBAppleRateFeedback(epoch: epoch)
        #expect(feedback.report(ssrc: 0x0d96_7839, at: at) == nil, "nothing to echo yet")
        for _ in 0..<2970 { feedback.received(ssrc: 0x1234_5678, timestamp: 0x8042, at: at) }
        #expect(feedback.report(ssrc: 0x0d96_7839, at: at) == hexBytes("80cc00070d9678395243544c85000004008000000000000017a200000b9aea60"))
    }

    @Test("the reported delay is a queue building between the Mac and here")
    func oneWayDelay() throws {
        let epoch = ContinuousClock.now
        func ms(_ n: Int) -> ContinuousClock.Instant { epoch + .milliseconds(n) }
        var feedback = RFBAppleRateFeedback(epoch: epoch)
        // 30 pictures a second, 800 ticks of 24 kHz apart, each 5 ms in transit.
        func picture(_ n: Int, queued: Int) {
            feedback.received(ssrc: 9, timestamp: 0xffff_f000 &+ UInt32(n * 800), at: ms(n * 100 / 3 + 5 + queued))
        }
        for n in 0..<300 { picture(n, queued: 0) }
        #expect(feedback.oneWayDelay < 0.001)
        let before = feedback.oneWayDelay
        feedback.received(ssrc: 9, timestamp: 0xffff_f000 &+ UInt32(299 * 800), at: ms(20_000))
        #expect(feedback.oneWayDelay == before, "a later packet of a picture changes nothing")
        for n in 300..<330 { picture(n, queued: (n - 299) * 10) }
        let queued = feedback.oneWayDelay
        #expect((0.2..<0.3).contains(queued))
        let report = try #require(feedback.report(ssrc: 1, at: ms(12_000)))
        #expect(UInt16(report[26]) << 8 | UInt16(report[27]) == UInt16(queued * 8192))
        for n in 330..<400 { picture(n, queued: 0) }
        #expect(feedback.oneWayDelay < 0.001)
        feedback.received(ssrc: 10, timestamp: 5, at: ms(20_000))
        #expect(try #require(feedback.report(ssrc: 1, at: ms(20_000)))[26..<30] == [0, 0, 0, 1], "a new stream starts again")
    }
}
