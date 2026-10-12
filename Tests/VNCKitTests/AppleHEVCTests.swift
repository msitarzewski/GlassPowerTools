import Foundation
import Testing
@testable import VNCKit

/// HEVC out of a Mac's media stream, one picture a frame (remotex's depacketizer tests, MIT).
@Suite("Apple media stream: HEVC pictures")
struct AppleHEVCTests {
    private typealias Depacketizer = RFBAppleHEVC.Depacketizer
    private let vps: [UInt8] = [0x40, 0x01, 0xaa]
    private let sps: [UInt8] = [0x42, 0x01, 0xbb]
    private let idr: [UInt8] = [0x28, 0x01, 1, 2, 3, 4, 5, 6]
    private let trail: [UInt8] = [0x02, 0x01, 7, 8]

    private func header(_ sequence: UInt16, _ timestamp: UInt32, _ marker: Bool, ssrc: UInt32 = 9,
                        refresh: Bool = false) -> RFBAppleSRTP.Header {
        RFBAppleSRTP.Header(payloadType: 100, marker: marker, sequence: sequence, timestamp: timestamp, ssrc: ssrc,
                            refresh: refresh, payload: 0..<0)
    }

    private func aggregation(_ nals: [[UInt8]]) -> [UInt8] {
        nals.reduce([RFBAppleHEVC.aggregation << 1, 0x01]) { $0 + UInt16($1.count).bigEndianBytes + $1 }
    }

    private func fragments(_ nal: [UInt8], _ pieces: Int) -> [[UInt8]] {
        let body = Array(nal[2...])
        let size = (body.count + pieces - 1) / pieces
        let chunks = stride(from: 0, to: body.count, by: size).map { Array(body[$0..<min(body.count, $0 + size)]) }
        return chunks.enumerated().map { index, chunk in
            [RFBAppleHEVC.fragmentation << 1 | (nal[0] & 0x81), nal[1],
             (index == 0 ? 0x80 : 0) | (index == chunks.count - 1 ? 0x40 : 0) | RFBAppleHEVC.nalType(nal[0])] + chunk
        }
    }

    @Test("Apple's first picture: the parameter sets aggregated, the IDR fragmented; then a picture in one packet")
    func aggregatesFragmentsAndSingleUnits() {
        var d = Depacketizer()
        #expect(d.push(header(10, 0, false), aggregation([vps, sps])[...]) == .pending)
        let pieces = fragments(idr, 3)
        #expect(d.push(header(11, 0, false), pieces[0][...]) == .pending)
        #expect(d.push(header(12, 0, false), pieces[1][...]) == .pending)
        #expect(d.push(header(13, 0, true), pieces[2][...]) == .unit([vps, sps, idr]))
        #expect(d.push(header(14, 400, true), trail[...]) == .unit([trail]))
    }

    @Test("nothing is decodable before a random-access picture, and a gap drops pictures until the next")
    func lossDropsUntilIDR() {
        var d = Depacketizer()
        #expect(d.push(header(1, 0, true), trail[...]) == .lost, "joined mid-stream")
        #expect(d.push(header(2, 400, true), idr[...]) == .unit([idr]))
        #expect(d.push(header(3, 800, true), trail[...]) == .unit([trail]))
        #expect(d.push(header(5, 1200, true), trail[...]) == .lost, "4 never came")
        #expect(d.push(header(6, 1600, true), trail[...]) == .lost)
        #expect(d.push(header(6, 1600, true), trail[...]) == .pending, "a duplicate")
        #expect(d.push(header(7, 2000, true), idr[...]) == .unit([idr]))
        let pieces = fragments(idr, 3)
        #expect(d.push(header(8, 2400, false), pieces[0][...]) == .pending)
        #expect(d.push(header(10, 2400, true), pieces[2][...]) == .lost, "a fragment lost takes its picture")
    }

    @Test("a new stream starts its own sequence")
    func newStream() {
        var d = Depacketizer()
        #expect(d.push(header(100, 0, true), idr[...]) == .unit([idr]))
        #expect(d.push(header(5000, 0, true, ssrc: 10), idr[...]) == .unit([idr]), "not a gap")
    }

    @Test("after a loss the stream goes on at the Mac's refresh picture, but not after a resync")
    func refresh() {
        var d = Depacketizer()
        #expect(d.push(header(10, 0, false), aggregation([vps, sps])[...]) == .pending)
        if case .unit = d.push(header(11, 0, true), idr[...]) {} else { Issue.record("the IDR") }
        #expect(d.push(header(13, 800, true), trail[...]) == .lost, "12 is lost")
        #expect(d.resumesAtRefresh)
        #expect(d.push(header(14, 1200, true), trail[...]) == .lost)
        #expect(d.push(header(15, 1600, true, refresh: true), trail[...]) == .unit([trail]))
        #expect(!d.resumesAtRefresh)
        #expect(d.push(header(16, 2000, true), trail[...]) == .unit([trail]))
        #expect(d.push(header(18, 2400, false, refresh: true), trail[...]) == .lost, "a refresh that lost a packet is no start")
        #expect(d.push(header(20, 2400, true), trail[...]) == .lost)
        #expect(d.resumesAtRefresh)
        d.resync()
        #expect(!d.resumesAtRefresh)
        #expect(d.push(header(21, 2800, true, refresh: true), trail[...]) == .lost)
        #expect(d.push(header(22, 3200, false), aggregation([vps, sps])[...]) == .pending)
        if case .unit = d.push(header(23, 3200, true), idr[...]) {} else { Issue.record("the IDR after a resync") }
    }

    @Test("a malformed aggregate or an orphan fragment damages its picture")
    func malformed() {
        var d = Depacketizer()
        #expect(d.push(header(1, 0, true), [RFBAppleHEVC.aggregation << 1, 1, 0, 9, 1][...]) == .lost)
        let pieces = fragments(idr, 2)
        #expect(d.push(header(2, 400, true), pieces[1][...]) == .lost, "a last fragment with no first")
        #expect(d.push(header(3, 800, true), [0x28][...]) == .lost, "a one-byte payload")
        #expect(d.push(header(4, 1200, true), idr[...]) == .unit([idr]))
    }

    @Test("a keyframe request is repeated until a picture settles it, and an IDR wanted wins")
    func keyframeRequest() {
        let start = ContinuousClock.now
        var request = RFBAppleHEVC.KeyframeRequest()
        #expect(request.due(at: start) == nil, "nothing is owed")
        request.want(.refresh)
        #expect(request.due(at: start) == .refresh)
        #expect(request.due(at: start + .milliseconds(250)) == nil, "too soon to ask again")
        #expect(request.due(at: start + .milliseconds(500)) == .refresh, "the Mac may have dropped it")
        request.want(.keyframe)
        request.want(.refresh)
        #expect(request.due(at: start + .seconds(1)) == .keyframe)
        request.settle()
        #expect(request.due(at: start + .seconds(2)) == nil, "a picture came")
    }
}
