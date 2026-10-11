//
//  RFBApplePasteboard.swift
//  Glass Power Tools — VNCKit
//
//  A Mac's own pasteboard messages, as Apple's viewer uses them (remotex's `src/vnc_apple_clipboard.rs`
//  and notes, "The pasteboard", MIT, Andrew Chen). macOS never bridges its pasteboard through RFB's
//  Client/ServerCutText, so sharing text with a Mac never worked here (2026-10-11):
//
//  - `AutoPasteboard` (0x15) starts the Mac watching its pasteboard. It goes in the clear, after
//    ViewerInfo and SetMode(control), before the record layer; sent encrypted it is accepted and
//    does nothing.
//  - The Mac then says its pasteboard changed with `MiscStatus` command 2; the viewer fetches it
//    (0x0b, eight bytes, the last four the viewer's to choose and echoed); the Mac answers with
//    0x1f: a 16-byte header and a zlib archive of every flavor of every item. Command 3 asks for
//    the viewer's pasteboard again.
//  - The viewer puts text on the Mac's pasteboard with its own 0x1f: the same header and an archive
//    of one item with one `public.utf8-plain-text` flavor; an item with no flavors clears it.
//
//  The archive is a run of items: a `u32` flavor count, then per flavor a counted name, a reserved
//  `u32`, a `u32` count of counted key and value tags, and counted data; every count a big-endian
//  `u32`. Only the first text flavor is kept.
//

import Foundation
import zlib

enum RFBApplePasteboard {
    static let textFlavor = Array("public.utf8-plain-text".utf8)
    /// The most this client inflates of a Mac's archive, which carries every flavor of what was
    /// copied — an image's TIFF beside a word. Past it the text is not looked for.
    static let maximumArchiveBytes = 32 * 1024 * 1024

    static func autoPasteboard(_ on: Bool) -> [UInt8] { [0x15, 0, 0, on ? 1 : 2, 0, 0, 0, 0] }

    static func fetch(session: UInt32) -> [UInt8] { [0x0b, 0, 0, 0] + session.bigEndianBytes }

    /// The viewer's 0x1f: text for the Mac's pasteboard, or nothing to clear it.
    static func send(_ text: String, session: UInt32) throws -> [UInt8] {
        let utf8 = Array(text.utf8)
        guard utf8.count <= RFBLimits.maximumCutTextBytes else { throw RFBError.resourceLimit("The clipboard text is too large to send.") }
        let archive = archive(utf8)
        let compressed = try ZlibDeflater.syncFlushed(archive)
        return [0x1f, 0, 0, 0] + session.bigEndianBytes + UInt32(archive.count).bigEndianBytes
            + UInt32(compressed.count).bigEndianBytes + compressed
    }

    static func archive(_ text: [UInt8]) -> [UInt8] {
        // An item with no flavors clears the Mac's pasteboard; an empty text flavor would be a
        // promise the Mac then waits on this client to keep.
        if text.isEmpty { return UInt32(0).bigEndianBytes }
        return UInt32(1).bigEndianBytes + UInt32(textFlavor.count).bigEndianBytes + textFlavor
            + UInt32(0).bigEndianBytes + UInt32(0).bigEndianBytes + UInt32(text.count).bigEndianBytes + text
    }

    /// The first text flavor in an inflated archive; nil when there is none.
    static func text(in archive: [UInt8]) throws -> String? {
        var reader = ByteReader(archive)
        func counted(_ limit: Int) throws -> ArraySlice<UInt8> {
            let length = Int(try reader.u32())
            guard length <= limit else { throw RFBError.protocolViolation("A field of the Mac's pasteboard is \(length) bytes.") }
            return try reader.bytes(length)
        }
        while !reader.isAtEnd {
            let flavors = Int(try reader.u32())
            guard flavors <= 1024 else { throw RFBError.protocolViolation("The Mac's pasteboard names \(flavors) flavors.") }
            for _ in 0..<flavors {
                let name = try counted(1024)
                _ = try reader.u32()
                let tags = Int(try reader.u32())
                guard tags <= 64 else { throw RFBError.protocolViolation("A flavor of the Mac's pasteboard has \(tags) tags.") }
                for _ in 0..<tags { _ = try counted(4096); _ = try counted(4096) }
                let data = try counted(maximumArchiveBytes)
                if name.elementsEqual(textFlavor) {
                    guard data.count <= RFBLimits.maximumCutTextBytes else { return nil }
                    return String(decoding: data, as: UTF8.self)
                }
            }
        }
        return nil
    }
}

/// zlib compression of one message, ending in a sync flush rather than the stream's end, as remotex
/// sends a Mac its pasteboard.
enum ZlibDeflater {
    static func syncFlushed(_ input: [UInt8]) throws -> [UInt8] {
        var stream = z_stream()
        guard deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw RFBError.resourceLimit("The zlib compressor could not be created.")
        }
        defer { deflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, UInt(input.count))) + 64)
        var source = input
        let status: Int32 = source.withUnsafeMutableBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                stream.next_in = inputBuffer.baseAddress
                stream.avail_in = UInt32(inputBuffer.count)
                stream.next_out = outputBuffer.baseAddress
                stream.avail_out = UInt32(outputBuffer.count)
                let result = deflate(&stream, Z_SYNC_FLUSH)
                stream.next_in = nil; stream.next_out = nil
                return result
            }
        }
        guard status == Z_OK, stream.avail_in == 0 else { throw RFBError.resourceLimit("The clipboard could not be compressed.") }
        return Array(output[0..<(output.count - Int(stream.avail_out))])
    }
}
