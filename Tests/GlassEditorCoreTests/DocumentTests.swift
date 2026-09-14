import Foundation
import Testing
@testable import GlassEditorCore

// MARK: - Fixture access

/// Fixture files are checked in as bytes and read as bytes. Nothing in this
/// suite constructs hostile content from a Swift string literal, because the
/// literal would already have been through a normalizing editor by the time it
/// reached the compiler — which is exactly the corruption the fixtures exist to
/// catch. Regenerate with `Fixtures/generate-fixtures.py`.
enum Fixture {
    static func url(_ name: String) throws -> URL {
        guard let resources = Bundle.module.resourceURL else {
            throw FixtureError.bundleHasNoResources
        }
        let url = resources.appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureError.missing(name)
        }
        return url
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    enum FixtureError: Error {
        case bundleHasNoResources
        case missing(String)
    }

    /// Every fixture, with the encoding and line-ending style its bytes must
    /// produce. Changing a fixture means changing a row here.
    static let all: [Expectation] = [
        .init("utf8-plain.txt", .utf8(hadBOM: false), .lf),
        .init("utf8-bom.txt", .utf8(hadBOM: true), .lf),
        .init("utf16le-bom.txt", .utf16LittleEndian(hadBOM: true), .lf),
        .init("utf16be-bom.txt", .utf16BigEndian(hadBOM: true), .lf),
        .init("crlf.txt", .utf8(hadBOM: false), .crlf),
        .init("cr-only.txt", .utf8(hadBOM: false), .cr),
        .init("mixed-endings.txt", .utf8(hadBOM: false), .mixed(dominant: .crlf)),
        .init("combining-marks.txt", .utf8(hadBOM: false), .lf),
        .init("bidi.txt", .utf8(hadBOM: false), .lf),
        .init("invalid-utf8.bin", .latin1Fallback, .lf),
    ]

    struct Expectation: Sendable, CustomStringConvertible {
        let name: String
        let encoding: DetectedEncoding
        let lineEndings: LineEndingStyle

        init(_ name: String, _ encoding: DetectedEncoding, _ lineEndings: LineEndingStyle) {
            self.name = name
            self.encoding = encoding
            self.lineEndings = lineEndings
        }

        var description: String { name }
    }
}

// MARK: - Encoding detection

@Suite("Encoding detection")
struct EncodingDetectionTests {

    @Test("Every fixture detects the encoding its bytes actually are", arguments: Fixture.all)
    func fixtureEncoding(_ expected: Fixture.Expectation) throws {
        let data = try Fixture.data(expected.name)
        #expect(EncodingDetector.detect(in: data) == expected.encoding)
    }

    @Test("Every fixture decodes to the same encoding detection reported", arguments: Fixture.all)
    func decodeAgreesWithDetect(_ expected: Fixture.Expectation) throws {
        let data = try Fixture.data(expected.name)
        let (_, encoding) = try EncodingDetector.decode(data)
        #expect(encoding == expected.encoding)
    }

    @Test("decode -> encode is byte-identical for every fixture", arguments: Fixture.all)
    func roundTripIsByteIdentical(_ expected: Fixture.Expectation) throws {
        let original = try Fixture.data(expected.name)
        let (content, encoding) = try EncodingDetector.decode(original)
        let reencoded = try EncodingDetector.encode(content, as: encoding)
        #expect(reencoded == original, "round trip changed bytes for \(expected.name)")
    }

    @Test("BOMs are stripped from decoded content, not carried into the buffer")
    func bomStripped() throws {
        for name in ["utf8-bom.txt", "utf16le-bom.txt", "utf16be-bom.txt"] {
            let (content, _) = try EncodingDetector.decode(Fixture.data(name))
            #expect(content.unicodeScalars.first != "\u{FEFF}", "\(name) leaked its BOM into content")
        }
    }

    @Test("BOM presence is remembered so a BOM-less file never gains one")
    func bomNotInvented() throws {
        let (content, encoding) = try EncodingDetector.decode(Fixture.data("utf8-plain.txt"))
        #expect(encoding == .utf8(hadBOM: false))
        let bytes = try EncodingDetector.encode(content, as: encoding)
        #expect(Array(bytes.prefix(3)) != [0xEF, 0xBB, 0xBF])
    }

    @Test("Invalid UTF-8 falls back to Latin-1 and survives the round trip intact")
    func invalidUTF8IsLossless() throws {
        let original = try Fixture.data("invalid-utf8.bin")
        let (content, encoding) = try EncodingDetector.decode(original)
        #expect(encoding == .latin1Fallback)
        // The bytes that make it invalid UTF-8 are still individually present.
        #expect(content.contains("caf\u{E9}"))
        #expect(try EncodingDetector.encode(content, as: encoding) == original)
    }

    @Test("UTF-32 BOMs are recognized as UTF-32, never mistaken for UTF-16")
    func utf32IsNotMistakenForUTF16() throws {
        let littleEndian = Data([0xFF, 0xFE, 0x00, 0x00]) + Data([0x41, 0x00, 0x00, 0x00])
        let bigEndian = Data([0x00, 0x00, 0xFE, 0xFF]) + Data([0x00, 0x00, 0x00, 0x41])

        #expect(EncodingDetector.sniffBOM(in: littleEndian) == .utf32LittleEndian)
        #expect(EncodingDetector.sniffBOM(in: bigEndian) == .utf32BigEndian)
        #expect(EncodingDetector.detect(in: littleEndian) != .utf16LittleEndian(hadBOM: true))
        #expect(EncodingDetector.detect(in: bigEndian) != .utf16BigEndian(hadBOM: true))

        for data in [littleEndian, bigEndian] {
            #expect(throws: EditorError.undecodableContent(triedEncoding: "UTF-32")) {
                _ = try EncodingDetector.decode(data)
            }
        }
    }

    @Test("A UTF-16 BOM followed by an odd trailing byte is refused, not truncated")
    func utf16OddLengthThrows() {
        // Foundation's decoder discards the stray 0x42 and reports success. That
        // byte would then be gone forever at the next save.
        let data = Data([0xFF, 0xFE, 0x41, 0x00, 0x42])
        #expect(throws: EditorError.undecodableContent(triedEncoding: "UTF-16 LE")) {
            _ = try EncodingDetector.decode(data)
        }
    }

    @Test("An unpaired UTF-16 surrogate is refused rather than replaced with U+FFFD")
    func utf16UnpairedSurrogateThrows() {
        // 0x00 0xD8 is U+D800 little-endian: a lone high surrogate.
        let littleEndian = Data([0xFF, 0xFE, 0x41, 0x00, 0x00, 0xD8, 0x42, 0x00])
        #expect(throws: EditorError.undecodableContent(triedEncoding: "UTF-16 LE")) {
            _ = try EncodingDetector.decode(littleEndian)
        }

        let bigEndian = Data([0xFE, 0xFF, 0x00, 0x41, 0xDC, 0x00, 0x00, 0x42])
        #expect(throws: EditorError.undecodableContent(triedEncoding: "UTF-16 BE")) {
            _ = try EncodingDetector.decode(bigEndian)
        }
    }

    @Test("Well-formed UTF-16, surrogate pairs included, still decodes")
    func utf16WellFormedStillDecodes() throws {
        let (content, encoding) = try EncodingDetector.decode(Fixture.data("utf16le-bom.txt"))
        #expect(encoding == .utf16LittleEndian(hadBOM: true))
        #expect(content.contains("🙂"))  // an actual surrogate pair, not a lone one
    }

    @Test("A UTF-8 BOM over non-UTF-8 bytes trusts the bytes, not the mark")
    func lyingBOM() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data([0x68, 0x69, 0x80, 0x0A])
        #expect(EncodingDetector.detect(in: data) == .latin1Fallback)
        let (content, encoding) = try EncodingDetector.decode(data)
        #expect(try EncodingDetector.encode(content, as: encoding) == data)
    }

    @Test("Empty data is valid UTF-8 without a BOM")
    func emptyData() throws {
        #expect(EncodingDetector.detect(in: Data()) == .utf8(hadBOM: false))
        let (content, encoding) = try EncodingDetector.decode(Data())
        #expect(content.isEmpty)
        #expect(try EncodingDetector.encode(content, as: encoding).isEmpty)
    }

    @Test("A bare BOM with no body still round-trips")
    func bareBOM() throws {
        let data = Data([0xEF, 0xBB, 0xBF])
        let (content, encoding) = try EncodingDetector.decode(data)
        #expect(content.isEmpty)
        #expect(encoding == .utf8(hadBOM: true))
        #expect(try EncodingDetector.encode(content, as: encoding) == data)
    }

    @Test("Latin-1 refuses content it cannot represent rather than writing '?'")
    func latin1RefusesAstralCharacters() {
        #expect(throws: EditorError.self) {
            _ = try EncodingDetector.encode("caf\u{E9} 🙂", as: .latin1Fallback)
        }
        // Everything at or below U+00FF is fine.
        #expect(throws: Never.self) {
            _ = try EncodingDetector.encode("caf\u{E9} na\u{EF}ve \u{FF}", as: .latin1Fallback)
        }
    }
}

// MARK: - UTF-8 well-formedness

@Suite("Strict UTF-8 validation")
struct UTF8ValidationTests {

    @Test("Accepts well-formed sequences at every length and boundary")
    func acceptsValid() {
        let valid: [[UInt8]] = [
            [],
            [0x00], [0x7F],
            [0xC2, 0x80], [0xDF, 0xBF],
            [0xE0, 0xA0, 0x80], [0xED, 0x9F, 0xBF], [0xEE, 0x80, 0x80], [0xEF, 0xBF, 0xBF],
            [0xF0, 0x90, 0x80, 0x80], [0xF4, 0x8F, 0xBF, 0xBF],  // U+10000 and U+10FFFF
        ]
        for bytes in valid {
            #expect(EncodingDetector.isWellFormedUTF8(bytes), "rejected valid sequence \(bytes)")
        }
    }

    @Test("Rejects overlongs, surrogates, out-of-range leads, and truncations")
    func rejectsInvalid() {
        let invalid: [[UInt8]] = [
            [0x80],                       // bare continuation
            [0xC0, 0xAF],                 // overlong '/'
            [0xC1, 0xBF],                 // overlong
            [0xE0, 0x80, 0xAF],           // overlong 3-byte
            [0xED, 0xA0, 0x80],           // U+D800 surrogate
            [0xED, 0xBF, 0xBF],           // U+DFFF surrogate
            [0xF0, 0x80, 0x80, 0x80],     // overlong 4-byte
            [0xF4, 0x90, 0x80, 0x80],     // beyond U+10FFFF
            [0xF5, 0x80, 0x80, 0x80],     // lead beyond range
            [0xFF],
            [0xE2, 0x82],                 // truncated 3-byte
            [0xF0, 0x9F],                 // truncated 4-byte
            [0x41, 0xC2],                 // truncated at end of buffer
        ]
        for bytes in invalid {
            #expect(!EncodingDetector.isWellFormedUTF8(bytes), "accepted invalid sequence \(bytes)")
        }
    }
}

// MARK: - Line endings

@Suite("Line ending detection")
struct LineEndingTests {

    @Test("Every fixture reports the line-ending style its bytes actually use", arguments: Fixture.all)
    func fixtureLineEndings(_ expected: Fixture.Expectation) throws {
        let snapshot = try DocumentLoader.load(
            fromData: Fixture.data(expected.name),
            origin: .ephemeral(id: UUID()),
            configuration: GlassEditorConfiguration()
        )
        #expect(snapshot.lineEndings == expected.lineEndings)
    }

    @Test("CRLF counts once, never as a CR plus an LF")
    func crlfIsAtomic() {
        let counts = LineEndingDetector.counts(in: "a\r\nb\r\nc")
        #expect(counts == LineEndingCounts(crlf: 2, lf: 0, cr: 0))
    }

    @Test("Adjacent lone CRs are counted individually")
    func repeatedCR() {
        #expect(LineEndingDetector.counts(in: "a\r\r\rb") == LineEndingCounts(crlf: 0, lf: 0, cr: 3))
        #expect(LineEndingDetector.counts(in: "a\r\r\n") == LineEndingCounts(crlf: 1, lf: 0, cr: 1))
    }

    @Test("A trailing CR at end of buffer still counts")
    func trailingCR() {
        #expect(LineEndingDetector.detect(in: "line\r") == .cr)
    }

    @Test("Mixed content reports the dominant style by count")
    func mixedDominant() {
        #expect(LineEndingDetector.detect(in: "a\r\nb\r\nc\nd") == .mixed(dominant: .crlf))
        #expect(LineEndingDetector.detect(in: "a\nb\nc\r\nd") == .mixed(dominant: .lf))
        #expect(LineEndingDetector.detect(in: "a\rb\rc\nd") == .mixed(dominant: .cr))
    }

    @Test("Ties resolve toward LF")
    func tiesFavorLF() {
        #expect(LineEndingDetector.detect(in: "a\nb\r\nc") == .mixed(dominant: .lf))
        // With no LF present, the tie cannot resolve to a style the file lacks.
        #expect(LineEndingDetector.detect(in: "a\rb\r\nc") == .mixed(dominant: .crlf))
    }

    @Test("Content with no terminator at all defaults to LF")
    func noTerminators() {
        #expect(LineEndingDetector.detect(in: "") == .lf)
        #expect(LineEndingDetector.detect(in: "one unterminated line") == .lf)
    }

    @Test("Loading never normalizes terminators in the buffer")
    func loadPreservesTerminators() throws {
        let data = try Fixture.data("mixed-endings.txt")
        let snapshot = try DocumentLoader.load(
            fromData: data,
            origin: .ephemeral(id: UUID()),
            configuration: GlassEditorConfiguration()
        )
        #expect(snapshot.content.contains("\r\n"))
        #expect(snapshot.content.contains("four\nfive"))
        #expect(snapshot.content.contains("six\rseven"))
        #expect(try EncodingDetector.encode(snapshot.content, as: snapshot.encoding) == data)
    }

    @Test("Explicit normalization converts every form and leaves content alone")
    func normalizeConverts() {
        let mixed = "one\r\ntwo\nthree\rfour"
        #expect(LineEndingDetector.normalize(mixed, to: .lf) == "one\ntwo\nthree\nfour")
        #expect(LineEndingDetector.normalize(mixed, to: .crlf) == "one\r\ntwo\r\nthree\r\nfour")
        #expect(LineEndingDetector.normalize(mixed, to: .cr) == "one\rtwo\rthree\rfour")
        // .mixed normalizes to its dominant style — converting *to* mixed is meaningless.
        #expect(LineEndingDetector.normalize(mixed, to: .mixed(dominant: .crlf)) == "one\r\ntwo\r\nthree\r\nfour")
    }

    @Test("Normalization is idempotent and preserves non-terminator scalars")
    func normalizeIdempotent() throws {
        let (content, _) = try EncodingDetector.decode(Fixture.data("combining-marks.txt"))
        let once = LineEndingDetector.normalize(content, to: .crlf)
        #expect(LineEndingDetector.normalize(once, to: .crlf) == once)
        #expect(LineEndingDetector.normalize(once, to: .lf) == content)
    }

    @Test("Normalization leaves U+2028 and U+0085 alone — they are content, not structure")
    func normalizeIgnoresExoticSeparators() {
        let exotic = "a\u{2028}b\u{0085}c\nd"
        #expect(LineEndingDetector.normalize(exotic, to: .crlf) == "a\u{2028}b\u{0085}c\r\nd")
    }
}

// MARK: - Document loading

@Suite("Document loading")
struct DocumentLoaderTests {

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassEditorKit-DocumentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Loading a local file records its URL as the origin")
    func loadLocalFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("sample.sql")
        try Fixture.data("crlf.txt").write(to: url)

        let snapshot = try DocumentLoader.load(from: url, configuration: GlassEditorConfiguration())
        #expect(snapshot.origin == .local(url))
        #expect(snapshot.encoding == .utf8(hadBOM: false))
        #expect(snapshot.lineEndings == .crlf)
        #expect(snapshot.openedDigest == nil)
        #expect(snapshot.openedStat == nil)
        #expect(snapshot.isPackageSaveable)
    }

    @Test("A file above the configured ceiling is refused, with both numbers reported")
    func ceilingRefusesLargeFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("big.txt")
        let payload = Data(repeating: 0x41, count: 4096)
        try payload.write(to: url)

        let configuration = GlassEditorConfiguration(largeFileByteCeiling: 1024)
        #expect(throws: EditorError.fileTooLarge(bytes: 4096, ceiling: 1024)) {
            _ = try DocumentLoader.load(from: url, configuration: configuration)
        }
        // Exactly at the ceiling is allowed; the check is inclusive.
        #expect(throws: Never.self) {
            _ = try DocumentLoader.load(
                from: url,
                configuration: GlassEditorConfiguration(largeFileByteCeiling: 4096)
            )
        }
    }

    @Test("The ceiling also gates the in-memory path the remote loader uses")
    func ceilingRefusesLargeData() {
        let data = Data(repeating: 0x41, count: 4096)
        #expect(throws: EditorError.fileTooLarge(bytes: 4096, ceiling: 1024)) {
            _ = try DocumentLoader.load(
                fromData: data,
                origin: .ephemeral(id: UUID()),
                configuration: GlassEditorConfiguration(largeFileByteCeiling: 1024)
            )
        }
    }

    @Test("A missing file reports unreadable data rather than crashing")
    func missingFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: EditorError.self) {
            _ = try DocumentLoader.load(
                from: directory.appendingPathComponent("nope.txt"),
                configuration: GlassEditorConfiguration()
            )
        }
    }

    @Test("Remote loads carry the digest and stat observed at open")
    func remoteSnapshotCarriesIdentity() throws {
        let reference = RemoteDocumentRef(
            connectionID: UUID(),
            host: "umbp.tail1234.ts.net",
            path: "/etc/nginx/nginx.conf"
        )
        let digest = ContentDigest(hexString: String(repeating: "ab", count: 32))
        let stat = RemoteStat(size: 43, modificationSeconds: 1_700_000_000)

        let snapshot = try DocumentLoader.load(
            fromData: Fixture.data("crlf.txt"),
            origin: .remote(reference),
            configuration: GlassEditorConfiguration(),
            openedDigest: digest,
            openedStat: stat
        )
        #expect(snapshot.openedDigest == digest)
        #expect(snapshot.openedStat == stat)
        #expect(!snapshot.isPackageSaveable)
    }

    @Test("Ephemeral documents are real documents with no file behind them")
    func ephemeralSnapshot() {
        let snapshot = DocumentLoader.make(
            content: "SELECT 1;\r\nSELECT 2;\r\n",
            origin: .ephemeral(id: UUID())
        )
        #expect(snapshot.encoding == .utf8(hadBOM: false))
        #expect(snapshot.lineEndings == .crlf)
        #expect(!snapshot.isPackageSaveable)
    }

    @Test("Local and remote paths produce identical detection for identical bytes", arguments: Fixture.all)
    func pathsAgree(_ expected: Fixture.Expectation) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let data = try Fixture.data(expected.name)
        let url = directory.appendingPathComponent(expected.name)
        try data.write(to: url)

        let configuration = GlassEditorConfiguration()
        let fromDisk = try DocumentLoader.load(from: url, configuration: configuration)
        let fromMemory = try DocumentLoader.load(
            fromData: data,
            origin: .ephemeral(id: UUID()),
            configuration: configuration
        )
        #expect(fromDisk.content == fromMemory.content)
        #expect(fromDisk.encoding == fromMemory.encoding)
        #expect(fromDisk.lineEndings == fromMemory.lineEndings)
    }
}
