import Foundation
import zlib

/// One persistent zlib inflate stream, as required by the Zlib and ZRLE encodings, whose
/// compressed data continues across rectangles for the lifetime of the connection.
final class ZlibInflater {
    private var stream = z_stream()
    private var initialized = false

    init() throws {
        let status = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw RFBError.resourceLimit("The zlib decompressor could not be created.") }
        initialized = true
    }

    deinit { if initialized { inflateEnd(&stream) } }

    /// Inflates `input`, expecting the stream to produce exactly `expectedOutput` bytes for it.
    func inflate(_ input: [UInt8], expectedOutput: Int) throws -> [UInt8] {
        guard expectedOutput >= 0, expectedOutput <= RFBLimits.maximumEncodedRectangleBytes else {
            throw RFBError.resourceLimit("The compressed rectangle is too large.")
        }
        var output = [UInt8](repeating: 0, count: expectedOutput)
        var produced = 0
        var inputCopy = input
        let status: Int32 = inputCopy.withUnsafeMutableBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                stream.next_in = inputBuffer.baseAddress
                stream.avail_in = UInt32(inputBuffer.count)
                stream.next_out = outputBuffer.baseAddress
                stream.avail_out = UInt32(outputBuffer.count)
                let result = zlib.inflate(&stream, Z_SYNC_FLUSH)
                produced = outputBuffer.count - Int(stream.avail_out)
                stream.next_in = nil; stream.next_out = nil
                return result
            }
        }
        guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
            throw RFBError.protocolViolation("The server sent invalid compressed data (zlib status \(status)).")
        }
        guard produced == expectedOutput, stream.avail_in == 0 else {
            throw RFBError.protocolViolation("The compressed rectangle did not decode to the expected size.")
        }
        return output
    }

    /// Inflates without a known output size, growing in bounded steps.
    func inflateAll(_ input: [UInt8]) throws -> [UInt8] {
        var result: [UInt8] = []
        var inputCopy = input
        var chunk = [UInt8](repeating: 0, count: 65536)
        try inputCopy.withUnsafeMutableBufferPointer { inputBuffer in
            stream.next_in = inputBuffer.baseAddress
            stream.avail_in = UInt32(inputBuffer.count)
            defer { stream.next_in = nil; stream.next_out = nil }
            repeat {
                let produced: Int = try chunk.withUnsafeMutableBufferPointer { outputBuffer in
                    stream.next_out = outputBuffer.baseAddress
                    stream.avail_out = UInt32(outputBuffer.count)
                    let status = zlib.inflate(&stream, Z_SYNC_FLUSH)
                    guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
                        throw RFBError.protocolViolation("The server sent invalid compressed data (zlib status \(status)).")
                    }
                    return outputBuffer.count - Int(stream.avail_out)
                }
                result.append(contentsOf: chunk[0..<produced])
                guard result.count <= RFBLimits.maximumEncodedRectangleBytes else {
                    throw RFBError.resourceLimit("The compressed rectangle is too large.")
                }
                if produced == 0 { break }
            } while stream.avail_in > 0 || stream.avail_out == 0
        }
        return result
    }
}
