import Foundation

/// What the bytes on disk actually were, decided by evidence rather than by a
/// declared default.
///
/// `hadBOM` is carried because save must reproduce the file byte-for-byte
/// (projectRules.md, Data Safety: "encoding … preserved on round trip unless
/// the user explicitly changes them"). A file that opened with a BOM saves with
/// one; a file that opened without keeps none.
///
/// `latin1Fallback` is not a guess and not a failure. ISO-8859-1 is a total
/// bijection between the 256 byte values and U+0000…U+00FF, so it decodes any
/// byte sequence and re-encodes to the identical bytes. Choosing it makes the
/// "this file is not valid UTF-8" fact *visible* to the UI, where the
/// alternative — U+FFFD replacement — destroys the original bytes silently and
/// irreversibly the first time the user saves.
public enum DetectedEncoding: Sendable, Hashable, Codable {
    case utf8(hadBOM: Bool)
    case utf16LittleEndian(hadBOM: Bool)
    case utf16BigEndian(hadBOM: Bool)
    /// Bytes that are not well-formed UTF-8, held losslessly as ISO-8859-1.
    case latin1Fallback

    /// A short, user-facing label. Not a `RawValue` — the associated `hadBOM`
    /// makes this a projection, not an identity.
    public var displayName: String {
        switch self {
        case .utf8(let bom): return bom ? "UTF-8 (BOM)" : "UTF-8"
        case .utf16LittleEndian(let bom): return bom ? "UTF-16 LE (BOM)" : "UTF-16 LE"
        case .utf16BigEndian(let bom): return bom ? "UTF-16 BE (BOM)" : "UTF-16 BE"
        case .latin1Fallback: return "ISO-8859-1 (fallback)"
        }
    }
}

/// A byte order mark actually present in the leading bytes of a file.
///
/// This exists as a separate type because `DetectedEncoding` deliberately has
/// no UTF-32 case — the package cannot edit UTF-32 in v1 — yet detection must
/// still be able to *say* it saw a UTF-32 BOM rather than truncating the
/// evidence to "UTF-16 LE", which is what a naïve two-byte sniff does to
/// `FF FE 00 00`.
public enum ByteOrderMark: Sendable, Hashable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
    case utf32LittleEndian
    case utf32BigEndian

    /// Byte length of the mark itself.
    public var byteCount: Int {
        switch self {
        case .utf8: return 3
        case .utf16LittleEndian, .utf16BigEndian: return 2
        case .utf32LittleEndian, .utf32BigEndian: return 4
        }
    }
}

/// Stateless encoding detection, decoding, and encoding
/// (projectRules.md, Naming: `public enum ServiceName { static func ... }`).
public enum EncodingDetector: Sendable {

    // MARK: - BOM sniffing

    /// The byte order mark present at the head of `data`, if any.
    ///
    /// Order matters: the UTF-32 marks are tested before the UTF-16 marks
    /// because `FF FE 00 00` (UTF-32 LE) has `FF FE` (UTF-16 LE) as a prefix
    /// and `00 00 FE FF` (UTF-32 BE) ends with `FE FF` (UTF-16 BE).
    public static func sniffBOM(in data: Data) -> ByteOrderMark? {
        let bytes = [UInt8](data.prefix(4))

        if bytes.count >= 4 {
            if bytes[0] == 0xFF, bytes[1] == 0xFE, bytes[2] == 0x00, bytes[3] == 0x00 {
                return .utf32LittleEndian
            }
            if bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0xFE, bytes[3] == 0xFF {
                return .utf32BigEndian
            }
        }
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return .utf8
        }
        if bytes.count >= 2 {
            if bytes[0] == 0xFF, bytes[1] == 0xFE { return .utf16LittleEndian }
            if bytes[0] == 0xFE, bytes[1] == 0xFF { return .utf16BigEndian }
        }
        return nil
    }

    // MARK: - Detection

    /// Decide how `data` should be read.
    ///
    /// The ladder is: BOM evidence first, then strict UTF-8 well-formedness over
    /// the *whole* buffer, then the lossless Latin-1 fallback. There is no
    /// heuristic step — no byte-frequency scoring, no "looks like Windows-1252".
    /// A guess that is wrong here becomes corruption at save.
    ///
    /// A UTF-8 BOM whose body is *not* well-formed UTF-8 reports
    /// `.latin1Fallback`, not `.utf8(hadBOM: true)`: the mark is a claim, the
    /// bytes are the evidence, and the evidence wins. Those three BOM bytes are
    /// themselves valid Latin-1, so the round trip stays byte-identical.
    ///
    /// A UTF-32 BOM also reports `.latin1Fallback` because `DetectedEncoding`
    /// has no UTF-32 case — but `decode(_:)` *throws* for those bytes rather
    /// than handing back UTF-32 rendered as Latin-1 mojibake, which the user
    /// would then be invited to edit and save over. Call ``sniffBOM(in:)`` when
    /// you need to tell the two situations apart before decoding.
    ///
    /// UTF-16 without a BOM is out of scope for v1. Such a file detects as
    /// `.latin1Fallback` (its NUL-interleaved bytes are not valid UTF-8) and
    /// opens as visible garbage — wrong-looking, but losslessly wrong: the
    /// bytes survive a save untouched.
    public static func detect(in data: Data) -> DetectedEncoding {
        switch sniffBOM(in: data) {
        case .utf16LittleEndian:
            return .utf16LittleEndian(hadBOM: true)
        case .utf16BigEndian:
            return .utf16BigEndian(hadBOM: true)
        case .utf32LittleEndian, .utf32BigEndian:
            return .latin1Fallback
        case .utf8:
            return isWellFormedUTF8(data.dropFirst(3)) ? .utf8(hadBOM: true) : .latin1Fallback
        case nil:
            return isWellFormedUTF8(data) ? .utf8(hadBOM: false) : .latin1Fallback
        }
    }

    // MARK: - Decoding

    /// Decode `data` into text plus the encoding that was used, with any BOM
    /// stripped from the returned content.
    ///
    /// The BOM is removed from `content` and remembered in the returned
    /// `DetectedEncoding` instead. Leaving it in the buffer would put a
    /// zero-width character at offset 0 that every offset, find match, and
    /// grammar parse would then have to reason about.
    ///
    /// - Throws: `EditorError.undecodableContent` for UTF-32 (unsupported in
    ///   v1) and for a UTF-16 BOM followed by bytes that are not decodable
    ///   UTF-16 (odd length, or an unpaired surrogate).
    public static func decode(_ data: Data) throws -> (content: String, encoding: DetectedEncoding) {
        if let mark = sniffBOM(in: data),
           mark == .utf32LittleEndian || mark == .utf32BigEndian {
            throw EditorError.undecodableContent(triedEncoding: "UTF-32")
        }

        let encoding = detect(in: data)
        switch encoding {
        case .utf8(let hadBOM):
            let body = hadBOM ? data.dropFirst(3) : data.dropFirst(0)
            // `String(decoding:as:)`, not `String(data:encoding:.utf8)`: the
            // Foundation initializer silently strips a *leading* U+FEFF, so once
            // the real BOM is dropped a second BOM (a `EF BB BF EF BB BF …` file)
            // would be eaten as well, losing three bytes on the round trip
            // (pen-suite finding). The stdlib codec maps U+FEFF through. The body
            // was already proven well-formed by `detect`, and the reversibility
            // guard reasserts byte-exactness rather than trusting it.
            let content = String(decoding: body, as: UTF8.self)
            guard Data(content.utf8) == Data(body) else {
                throw EditorError.undecodableContent(triedEncoding: "UTF-8")
            }
            return (content, encoding)

        case .utf16LittleEndian(let hadBOM):
            let body = Data(hadBOM ? data.dropFirst(2) : data.dropFirst(0))
            let content = try decodeReversibly(body, as: .utf16LittleEndian, label: "UTF-16 LE")
            return (content, encoding)

        case .utf16BigEndian(let hadBOM):
            let body = Data(hadBOM ? data.dropFirst(2) : data.dropFirst(0))
            let content = try decodeReversibly(body, as: .utf16BigEndian, label: "UTF-16 BE")
            return (content, encoding)

        case .latin1Fallback:
            // Cannot fail for any byte sequence — ISO-8859-1 is total over the
            // 256 byte values — but the package prefers `throws` over `!`.
            guard let content = String(data: data, encoding: .isoLatin1) else {
                throw EditorError.undecodableContent(triedEncoding: "ISO-8859-1")
            }
            return (content, encoding)
        }
    }

    /// Decode UTF-16 only if the result provably re-encodes to the same bytes.
    ///
    /// Foundation's UTF-16 decoder is forgiving in ways this package cannot
    /// afford. Given an odd-length buffer it returns a `String` with the stray
    /// trailing byte **silently discarded**, and given an unpaired surrogate it
    /// substitutes U+FFFD. Either result decodes fine, displays fine, and then
    /// destroys a byte the moment the user saves — the exact silent-corruption
    /// class the Data Safety rule exists to prevent.
    ///
    /// So the decode is only accepted if re-encoding reproduces the input
    /// exactly. Reversibility is checked rather than assumed. UTF-16 files are
    /// rare and already bounded by `largeFileByteCeiling`, so the second pass is
    /// affordable; being wrong here is not.
    private static func decodeReversibly(
        _ body: Data,
        as encoding: String.Encoding,
        label: String
    ) throws -> String {
        guard body.count % 2 == 0 else {
            throw EditorError.undecodableContent(triedEncoding: label)
        }
        guard let content = String(data: body, encoding: encoding),
              let verification = content.data(using: encoding),
              verification == body else {
            throw EditorError.undecodableContent(triedEncoding: label)
        }
        return content
    }

    // MARK: - Encoding

    /// Re-encode `content` under `encoding`, reattaching the BOM when the file
    /// opened with one.
    ///
    /// `decode` followed by `encode` with the returned encoding is byte-identical
    /// for every input this package accepts. That identity is the whole point:
    /// opening a file and saving it without typing must not change a single byte.
    ///
    /// - Throws: `EditorError.saveFailed` when the content has grown characters
    ///   the target encoding cannot represent — the realistic case being a
    ///   Latin-1 file into which the user pasted an emoji. Refusing is correct;
    ///   the alternative is writing `?` over their text.
    public static func encode(_ content: String, as encoding: DetectedEncoding) throws -> Data {
        switch encoding {
        case .utf8(let hadBOM):
            var out = hadBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()
            out.append(contentsOf: content.utf8)
            return out

        case .utf16LittleEndian(let hadBOM):
            guard let body = content.data(using: .utf16LittleEndian) else {
                throw EditorError.saveFailed(reason: "content is not representable in UTF-16 LE")
            }
            return (hadBOM ? Data([0xFF, 0xFE]) : Data()) + body

        case .utf16BigEndian(let hadBOM):
            guard let body = content.data(using: .utf16BigEndian) else {
                throw EditorError.saveFailed(reason: "content is not representable in UTF-16 BE")
            }
            return (hadBOM ? Data([0xFE, 0xFF]) : Data()) + body

        case .latin1Fallback:
            guard let body = content.data(using: .isoLatin1) else {
                throw EditorError.saveFailed(
                    reason: "content contains characters above U+00FF, which ISO-8859-1 cannot represent"
                )
            }
            return body
        }
    }

    // MARK: - UTF-8 well-formedness

    /// Strict UTF-8 validation per the Unicode well-formed byte sequence table
    /// (Unicode 15.0, Table 3-7).
    ///
    /// Hand-rolled rather than delegated to `String(data:encoding:.utf8)` so the
    /// three rejection classes the fixtures exercise are explicit and testable:
    /// overlong encodings (`C0 AF`), surrogate code points (`ED A0 80`), and
    /// values above U+10FFFF (`F5 ..`). A validator that accepts any of those
    /// lets a file open as "UTF-8" and then get rewritten in a different,
    /// silently-corrected form.
    public static func isWellFormedUTF8(_ bytes: some Collection<UInt8>) -> Bool {
        var iterator = bytes.makeIterator()

        func next() -> UInt8? { iterator.next() }
        func continuation(_ range: ClosedRange<UInt8>) -> Bool {
            guard let byte = next() else { return false }
            return range.contains(byte)
        }

        while let byte = next() {
            switch byte {
            case 0x00...0x7F:
                continue
            case 0xC2...0xDF:
                guard continuation(0x80...0xBF) else { return false }
            case 0xE0:
                // E0 80..9F would be an overlong encoding of a 2-byte value.
                guard continuation(0xA0...0xBF), continuation(0x80...0xBF) else { return false }
            case 0xE1...0xEC, 0xEE...0xEF:
                guard continuation(0x80...0xBF), continuation(0x80...0xBF) else { return false }
            case 0xED:
                // ED A0..BF is the surrogate range D800..DFFF, never valid UTF-8.
                guard continuation(0x80...0x9F), continuation(0x80...0xBF) else { return false }
            case 0xF0:
                // F0 80..8F would be an overlong encoding of a 3-byte value.
                guard continuation(0x90...0xBF),
                      continuation(0x80...0xBF),
                      continuation(0x80...0xBF) else { return false }
            case 0xF1...0xF3:
                guard continuation(0x80...0xBF),
                      continuation(0x80...0xBF),
                      continuation(0x80...0xBF) else { return false }
            case 0xF4:
                // F4 90.. would exceed U+10FFFF.
                guard continuation(0x80...0x8F),
                      continuation(0x80...0xBF),
                      continuation(0x80...0xBF) else { return false }
            default:
                // 0x80...0xC1 (bare continuation or overlong lead) and 0xF5...0xFF.
                return false
            }
        }
        return true
    }
}
