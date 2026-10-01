import Foundation
import ImageIO
import CoreGraphics
import NIOCore
import NIOEmbedded
@testable import RDPKit
import Testing

/// D42a: the clipboard carries HTML, RTF and images as well as text (2026-09-30).

private func pngFixture(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> Data {
    var rgba = [UInt8](repeating: 255, count: width * height * 4)
    for i in 0..<(width * height) { rgba[i * 4] = red; rgba[i * 4 + 1] = green; rgba[i * 4 + 2] = blue }
    // A different colour in the top-left pixel, so orientation is checked too.
    rgba[0] = 0; rgba[1] = 0; rgba[2] = 0
    let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

/// (red, green, blue) at (x, y), counted from the top-left.
private func rgb(ofPNG png: Data, x: Int, y: Int) -> [UInt8] {
    let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil)!
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return Array(pixel[0..<3])
}

@Test func htmlTravelsInTheWindowsWrapperAndComesBackAsTheFragment() throws {
    let fragment = "<b>Grüße</b> &amp; <i>more</i>"
    let encoded = RDPClipboardHTML.encode(fragment)
    #expect(encoded.last == 0)
    let header = String(decoding: encoded.prefix(110), as: UTF8.self)
    #expect(header.hasPrefix("Version:0.9\r\nStartHTML:"))
    #expect(RDPClipboardHTML.decode(encoded) == fragment)
}

@Test func anImageGoesAsABottomUpDIBAndComesBackTheRightWayUp() throws {
    let png = pngFixture(width: 5, height: 3, red: 200, green: 100, blue: 50)
    let dib = try #require(RDPClipboardBitmap.dib(fromPNG: png))
    #expect(dib.count == 40 + 5 * 3 * 4)
    #expect(Array(dib[14..<16]) == [32, 0], "32 bits per pixel")
    let back = try #require(RDPClipboardBitmap.png(fromDIB: dib))
    #expect(rgb(ofPNG: back, x: 0, y: 0) == [0, 0, 0], "the top-left pixel stays top-left")
    #expect(rgb(ofPNG: back, x: 4, y: 2) == [200, 100, 50])
}

@Test func aTopDown24BitDIBIsRead() throws {
    // 2×1, top-down (negative height), 24-bit: blue pixel, then red. Rows pad to 4 bytes.
    var dib = Data()
    for value: UInt32 in [40, 2, UInt32(bitPattern: -1)] { dib.appendLittleEndianUInt32(value) }
    dib.appendLittleEndianUInt16(1); dib.appendLittleEndianUInt16(24)
    for _ in 0..<6 { dib.appendLittleEndianUInt32(0) }
    dib.append(contentsOf: [255, 0, 0, 0, 0, 255, 0, 0])
    let png = try #require(RDPClipboardBitmap.png(fromDIB: dib))
    #expect(rgb(ofPNG: png, x: 0, y: 0) == [0, 0, 255])
    #expect(rgb(ofPNG: png, x: 1, y: 0) == [255, 0, 0])
}

@Test func malformedDIBsAreRefused() {
    #expect(RDPClipboardBitmap.png(fromDIB: Data([1, 2, 3])) == nil)
    var huge = Data()
    for value: UInt32 in [40, 100_000, 1] { huge.appendLittleEndianUInt32(value) }
    huge.appendLittleEndianUInt16(1); huge.appendLittleEndianUInt16(32)
    for _ in 0..<6 { huge.appendLittleEndianUInt32(0) }
    #expect(RDPClipboardBitmap.png(fromDIB: huge) == nil, "too wide, and no pixels behind the header")
}

@Test func localRichContentAnswersEachFormatItOffers() throws {
    let content = RDPClipboardRichContent(text: "hi", html: "<b>hi</b>", rtf: Data("{\\rtf1 hi}".utf8),
                                          png: pngFixture(width: 2, height: 2, red: 1, green: 2, blue: 3))
    #expect(RDPClipboardSession.richData(content, formatID: 13) == RDPClipboardFormatDataResponsePDU.unicodeText("hi").data)
    #expect(RDPClipboardHTML.decode(try #require(RDPClipboardSession.richData(content, formatID: 0xC002))) == "<b>hi</b>")
    #expect(RDPClipboardSession.richData(content, formatID: 0xC003) == Data("{\\rtf1 hi}".utf8) + Data([0]))
    #expect(RDPClipboardSession.richData(content, formatID: 8)?.count == 40 + 16)
    #expect(RDPClipboardSession.richData(RDPClipboardRichContent(text: "only"), formatID: 8) == nil)
}

/// The server's clipboard is fetched one format at a time and handed over whole.
@Test func aRemoteCopyIsFetchedFormatByFormatAndDeliveredWhole() throws {
    let channel = EmbeddedChannel()
    try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 3389)).wait()
    let session = RDPClipboardSession(userChannelID: 1001, staticChannelID: 1005, channel: channel)
    final class Box: @unchecked Sendable { var delivered: RDPClipboardRichContent? }
    let box = Box()
    session.setRemoteContentHandler { box.delivered = $0 }

    func requestedFormat() throws -> UInt32? {
        channel.embeddedEventLoop.run()
        guard var buffer = try channel.readOutbound(as: ByteBuffer.self),
              let bytes = buffer.readBytes(length: buffer.readableBytes) else { return nil }
        var cursor = try ByteCursor(X224DataTPDU.unwrap(Data(bytes)))
        _ = try cursor.readUInt8(); _ = try cursor.readBigEndianUInt16(); _ = try cursor.readBigEndianUInt16()
        _ = try cursor.readUInt8()
        let userData = try cursor.readData(count: try cursor.readPERLength())
        let pdu = try RDPClipboardPDU.parse(from: RDPStaticVirtualChannelPDU.parse(fromUserData: userData).payload)
        return try RDPClipboardFormatDataRequestPDU.parseIfPresent(from: pdu)?.formatID
    }

    let list = RDPClipboardFormatListPDU(entries: [
        RDPClipboardFormatListEntry(formatID: 13),
        RDPClipboardFormatListEntry(formatID: 0xC0A0, formatName: "HTML Format"),
        RDPClipboardFormatListEntry(formatID: 8),
    ])
    #expect(session.beginRemoteFetch(list))
    #expect(try requestedFormat() == 13)
    session.receiveRemoteFormat(.text, response: .unicodeText("hello"))
    #expect(try requestedFormat() == 0xC0A0)
    session.receiveRemoteFormat(.html, response: RDPClipboardFormatDataResponsePDU(ok: true, data: RDPClipboardHTML.encode("<i>hello</i>")))
    #expect(try requestedFormat() == 8)
    #expect(box.delivered == nil, "nothing is handed over until every format has answered")
    let dib = try #require(RDPClipboardBitmap.dib(fromPNG: pngFixture(width: 3, height: 2, red: 9, green: 8, blue: 7)))
    session.receiveRemoteFormat(.dib, response: RDPClipboardFormatDataResponsePDU(ok: true, data: dib))
    let delivered = try #require(box.delivered)
    #expect(delivered.text == "hello" && delivered.html == "<i>hello</i>")
    #expect(rgb(ofPNG: try #require(delivered.png), x: 2, y: 1) == [9, 8, 7])

    // Without a rich handler the caller falls back to text.
    let plain = RDPClipboardSession(userChannelID: 1001, staticChannelID: 1005, channel: channel)
    #expect(!plain.beginRemoteFetch(list))
}

@Test func clipboardMessagesAreBoundedByTheClipboardNotByOneChunk() {
    let long = String(repeating: "a", count: 100_000)
    #expect(RDPClipboardLimits.canPublishUnicodeText(long))
    #expect(RDPClipboardFormatDataResponsePDU.unicodeTextIfEncodable(long) != nil)
}
