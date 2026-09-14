import Foundation
import Testing
@testable import GlassEditorCore

/// Property-based storage tests: randomized edit sequences driven against a
/// deliberately naive model (`NSMutableString` mutated by UTF-16 range, line
/// starts recomputed by a full scan every time). The buffer is incremental; the
/// model is not. Any divergence is the incremental machinery being wrong —
/// which is the whole reason this package exists (`projectRules.md`, Testing).
///
/// **Seed policy**: every run uses a fixed default seed so the suite is
/// deterministic, and every assertion carries the seed plus the sequence and
/// step number that produced it. To reproduce a reported failure — or to widen
/// the search — set `GLASS_EDITOR_TEST_SEED` to any `UInt64`:
///
///     GLASS_EDITOR_TEST_SEED=12345 swift test
///
/// The seed in use is printed at the top of each test.
@Suite("Storage properties")
struct StoragePropertyTests {

    // MARK: - Seeded RNG

    /// SplitMix64 — small, well-distributed, and reproducible across platforms
    /// and Swift versions, unlike `SystemRandomNumberGenerator`.
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let defaultSeed: UInt64 = 0x5EED_1DEA_C0FF_EE01

    static var seed: UInt64 {
        ProcessInfo.processInfo.environment["GLASS_EDITOR_TEST_SEED"].flatMap(UInt64.init)
            ?? defaultSeed
    }

    /// Deliberately hostile: astral pairs, a flag, a ZWJ family, combining
    /// marks, every line-terminator flavour including a bare CR and a CRLF that
    /// random offsets will happily cut in half, plus plain ASCII so documents
    /// stay legible when a failure prints.
    static let alphabet: [String] = [
        "a", "b", "c", "xyz", " ", "\t", "0",
        "\n", "\n", "\r\n", "\r", "\n\n", "a\nb",
        "é", "e\u{0301}", "a\u{0301}\u{0308}",
        "🙂", "🇺🇸", "👨‍👩‍👧‍👦", "漢字",
        "",
    ]

    // MARK: - Naive model

    /// Full rescan of every line start, with no incremental cleverness at all.
    static func naiveLineStarts(_ text: String) -> [Int] {
        var starts = [0]
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            if units[i] == 0x000D {
                if i + 1 < units.count && units[i + 1] == 0x000A { i += 1 }
                starts.append(i + 1)
            } else if units[i] == 0x000A {
                starts.append(i + 1)
            }
            i += 1
        }
        return starts
    }

    /// Replaces a UTF-16 range in a `String` without going anywhere near the
    /// buffer's own representation.
    static func naiveReplace(_ text: String, _ range: Range<Int>, with replacement: String) -> String {
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(
            in: NSRange(location: range.lowerBound, length: range.count),
            with: replacement
        )
        return mutable as String
    }

    /// Moves an offset off the low half of a surrogate pair. Random offsets will
    /// land there constantly; the buffer rejects those by design, so the
    /// generator avoids them and `StorageBufferTests` covers the rejection.
    static func snapToScalarBoundary(_ offset: Int, in text: String) -> Int {
        let units = Array(text.utf16)
        guard offset > 0, offset < units.count else { return offset }
        if (0xD800...0xDBFF).contains(units[offset - 1]), (0xDC00...0xDFFF).contains(units[offset]) {
            return offset - 1
        }
        return offset
    }

    static func randomRange(
        in text: String,
        using rng: inout SplitMix64,
        allowDeletion: Bool
    ) -> Range<Int> {
        let length = text.utf16.count
        let lower = snapToScalarBoundary(Int.random(in: 0...length, using: &rng), in: text)
        guard allowDeletion, length > 0, Bool.random(using: &rng) else { return lower..<lower }
        // Bias toward short deletions; occasionally take a big bite.
        let span = Bool.random(using: &rng)
            ? Int.random(in: 0...min(4, length - lower), using: &rng)
            : Int.random(in: 0...(length - lower), using: &rng)
        let upper = snapToScalarBoundary(lower + span, in: text)
        return lower..<max(lower, upper)
    }

    // MARK: - Properties

    @Test("Random edit sequences match a naive model, and every inverse restores")
    func randomEditSequences() throws {
        let seed = Self.seed
        print("StoragePropertyTests.randomEditSequences seed: \(seed)")
        var rng = SplitMix64(seed: seed)

        let sequences = 500
        let editsPerSequence = 12
        var totalEdits = 0

        for sequence in 0..<sequences {
            let seedText = sequence % 3 == 0 ? "" : Self.alphabet.randomElement(using: &rng)!
            let buffer = TextStorageBuffer(text: seedText)
            var model = seedText

            for step in 0..<editsPerSequence {
                let where_ = "seed \(seed), sequence \(sequence), step \(step)"

                // Keep documents from running away; force deletions once long.
                let allowDeletion = model.utf16.count > 24 || Bool.random(using: &rng)
                let range = Self.randomRange(in: model, using: &rng, allowDeletion: allowDeletion)
                let replacement = model.utf16.count > 200
                    ? ""
                    : Self.alphabet.randomElement(using: &rng)!
                let edit = TextEdit(replacementRange: range, text: replacement)

                let before = model
                let applied = try buffer.apply(edit)
                model = Self.naiveReplace(model, range, with: replacement)
                totalEdits += 1

                #expect(
                    applied.replacedText == Self.slice(before, range),
                    "replaced text mismatch — \(where_)"
                )
                #expect(buffer.text == model, "text mismatch — \(where_)")
                #expect(buffer.utf16Length == model.utf16.count, "length mismatch — \(where_)")

                let naiveStarts = Self.naiveLineStarts(model)
                #expect(buffer.lineStartOffsets() == naiveStarts, "line starts mismatch — \(where_)")
                #expect(buffer.lineCount == naiveStarts.count, "line count mismatch — \(where_)")

                // The inverse must restore the previous document exactly, then
                // the original edit must reapply cleanly on top of it.
                try buffer.apply(applied.inverse)
                #expect(buffer.text == before, "inverse did not restore — \(where_)")
                #expect(
                    buffer.lineStartOffsets() == Self.naiveLineStarts(before),
                    "inverse left a stale line index — \(where_)"
                )
                try buffer.apply(edit)
                #expect(buffer.text == model, "reapply mismatch — \(where_)")
            }
        }

        #expect(totalEdits == sequences * editsPerSequence)
    }

    @Test("lineIndex(forUTF16Offset:) matches a naive scan at random offsets")
    func lineIndexFuzz() throws {
        let seed = Self.seed &+ 1
        print("StoragePropertyTests.lineIndexFuzz seed: \(seed)")
        var rng = SplitMix64(seed: seed)

        for sequence in 0..<120 {
            let buffer = TextStorageBuffer()
            var model = ""

            for step in 0..<10 {
                let where_ = "seed \(seed), sequence \(sequence), step \(step)"
                let range = Self.randomRange(in: model, using: &rng, allowDeletion: model.utf16.count > 30)
                let replacement = Self.alphabet.randomElement(using: &rng)!
                try buffer.apply(TextEdit(replacementRange: range, text: replacement))
                model = Self.naiveReplace(model, range, with: replacement)

                let starts = Self.naiveLineStarts(model)
                let length = model.utf16.count

                for _ in 0..<24 {
                    let offset = Int.random(in: -3...(length + 3), using: &rng)
                    let clamped = min(max(offset, 0), length)
                    let expected = starts.lastIndex(where: { $0 <= clamped })!
                    #expect(
                        buffer.lineIndex(forUTF16Offset: offset) == expected,
                        "line index mismatch at offset \(offset) — \(where_)"
                    )

                    // The line that claims the offset must actually contain it.
                    let line = buffer.lineIndex(forUTF16Offset: offset)
                    let lineRange = buffer.lineRange(ofLine: line)
                    #expect(
                        lineRange.lowerBound <= clamped
                            && (clamped < lineRange.upperBound || line == buffer.lineCount - 1),
                        "line range does not contain offset \(offset) — \(where_)"
                    )
                }

                // Line ranges tile the document with no gaps or overlaps.
                var cursor = 0
                for line in 0..<buffer.lineCount {
                    let range = buffer.lineRange(ofLine: line)
                    #expect(range.lowerBound == cursor, "line \(line) does not abut — \(where_)")
                    cursor = range.upperBound
                }
                #expect(cursor == length, "line ranges do not cover the document — \(where_)")
            }
        }
    }

    @Test("substring(in:) matches the model over random ranges")
    func substringFuzz() throws {
        let seed = Self.seed &+ 2
        print("StoragePropertyTests.substringFuzz seed: \(seed)")
        var rng = SplitMix64(seed: seed)

        for sequence in 0..<100 {
            let buffer = TextStorageBuffer()
            var model = ""

            for step in 0..<8 {
                let where_ = "seed \(seed), sequence \(sequence), step \(step)"
                let range = Self.randomRange(in: model, using: &rng, allowDeletion: model.utf16.count > 30)
                let replacement = Self.alphabet.randomElement(using: &rng)!
                try buffer.apply(TextEdit(replacementRange: range, text: replacement))
                model = Self.naiveReplace(model, range, with: replacement)
                #expect(buffer.text == model, "text mismatch — \(where_)")

                for _ in 0..<10 {
                    let probe = Self.randomRange(in: model, using: &rng, allowDeletion: true)
                    #expect(
                        try buffer.substring(in: probe) == Self.slice(model, probe),
                        "substring mismatch for \(probe) — \(where_)"
                    )
                }
            }
        }
    }

    @Test("Random batches match the same edits applied one at a time, back to front")
    func randomBatches() throws {
        let seed = Self.seed &+ 3
        print("StoragePropertyTests.randomBatches seed: \(seed)")
        var rng = SplitMix64(seed: seed)

        for sequence in 0..<200 {
            let where_ = "seed \(seed), sequence \(sequence)"
            let seedText = "alpha\nbeta\r\ngamma\rdelta\n🙂 é🇺🇸\nomega"
            let buffer = TextStorageBuffer(text: seedText)
            let reference = TextStorageBuffer(text: seedText)
            let length = seedText.utf16.count

            // Build disjoint, ordered, non-empty ranges so the batch is legal by
            // construction — overlap rejection is covered in StorageBufferTests.
            var edits: [TextEdit] = []
            var cursor = 0
            while cursor < length {
                let gap = Int.random(in: 0...5, using: &rng)
                let lower = Self.snapToScalarBoundary(min(cursor + gap, length), in: seedText)
                guard lower < length else { break }
                let span = Int.random(in: 1...min(4, length - lower), using: &rng)
                let upper = Self.snapToScalarBoundary(lower + span, in: seedText)
                guard upper > lower else { cursor = lower + 1; continue }
                if Bool.random(using: &rng) {
                    edits.append(TextEdit(
                        replacementRange: lower..<upper,
                        text: Self.alphabet.randomElement(using: &rng)!
                    ))
                }
                cursor = upper + 1
            }
            guard !edits.isEmpty else { continue }

            let applied = try buffer.apply(TextEditBatch(edits: edits))
            #expect(applied.count == edits.count, "batch dropped an edit — \(where_)")

            // Same edits, applied by hand back to front.
            for edit in edits.sorted(by: { $0.replacementRange.lowerBound > $1.replacementRange.lowerBound }) {
                try reference.apply(edit)
            }
            #expect(buffer.text == reference.text, "batch diverged from sequential — \(where_)")
            #expect(
                buffer.lineStartOffsets() == Self.naiveLineStarts(buffer.text),
                "batch left a stale line index — \(where_)"
            )

            // Undo the batch by walking the applied edits in reverse.
            for entry in applied.reversed() {
                try buffer.apply(entry.inverse)
            }
            #expect(buffer.text == seedText, "batch undo did not restore — \(where_)")
            #expect(
                buffer.lineStartOffsets() == Self.naiveLineStarts(seedText),
                "batch undo left a stale line index — \(where_)"
            )
        }
    }

    // MARK: - Helpers

    /// UTF-16 slice of a `String`, computed without the buffer.
    static func slice(_ text: String, _ range: Range<Int>) -> String {
        let mutable = NSString(string: text)
        return mutable.substring(with: NSRange(location: range.lowerBound, length: range.count))
    }
}
