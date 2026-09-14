import Foundation

/// The document's text and the single path through which it may change.
///
/// **Representation**: a flat `[UInt16]` of UTF-16 code units, with the `String`
/// form cached and invalidated on mutation, and a `LineIndex` of line starts kept
/// incrementally in step. UTF-16 is the coordinate system every public API in
/// this package already speaks (`TextEdit.replacementRange`, `HighlightRun`), so
/// a flat code-unit array makes offset arithmetic `O(1)` and needs no index
/// translation on the hot path.
///
/// **Complexity**
/// - `apply(_:)`: `O(n)` in document length for the code-unit move, `O(k + m)`
///   for the line index (see `LineIndex`). The `O(n)` move is a `memmove` over a
///   contiguous buffer — the thing that must *not* be `O(n)` per keystroke is the
///   line rescan, and it isn't.
/// - `text`: `O(n)` on the first read after an edit, `O(1)` while cached.
/// - `substring(in:)`, `columnIndex(forUTF16Offset:)`: `O(k)` in the span read.
/// - `lineIndex(forUTF16Offset:)`: `O(log n)` in the number of lines.
///
/// A piece table would turn the `O(n)` move into `O(log n)` at the cost of making
/// every read indirect. Correctness first: the array is trivially auditable, and
/// the whole public surface here is representation-independent, so a piece table
/// can land later without moving a single call site.
///
/// **Concurrency**: deliberately *not* `Sendable`, the one exception to the
/// "all public `GlassEditorCore` types are `Sendable`" rule in
/// `memory-bank/projectRules.md` (Concurrency). This is mutable state owned by a
/// `@MainActor` engine; the class itself carries no actor annotation so that
/// every correctness-critical behavior stays testable without a view
/// (`AGENTS.md` §5).
///
/// **Line convention**: a line terminator opens a new line, so a document ending
/// in a terminator has a final, empty line. `"a\n"` is two lines. `""` is one
/// (empty) line. `LF`, `CR`, and `CRLF` are the recognised terminators; `CRLF` is
/// one terminator, not two.
public final class TextStorageBuffer {
    private var units: [UInt16]
    /// Internal rather than private so tests can assert on the index's own
    /// incrementality counters; `TextStorageBuffer` is the only writer.
    private(set) var index: LineIndex
    private var cachedText: String?

    public init(text: String = "") {
        units = Array(text.utf16)
        index = LineIndex(units: units)
        cachedText = text
    }

    // MARK: - Content

    /// The current document text.
    public var text: String {
        if let cachedText { return cachedText }
        let materialized = String(decoding: units, as: UTF16.self)
        cachedText = materialized
        return materialized
    }

    /// Document length in UTF-16 code units — the unit every range in this
    /// package is expressed in.
    public var utf16Length: Int { units.count }

    /// Number of lines. Always at least 1. A trailing terminator means the last
    /// line is empty: `"a\n"` has 2 lines, `"a"` has 1, `""` has 1.
    public var lineCount: Int { index.lineCount }

    /// The text occupying `range`, which is in UTF-16 code units.
    ///
    /// - Throws: `EditorError.rangeOutOfBounds` if the range leaves the document,
    ///   `EditorError.splitsSurrogatePair` if an endpoint lands between the two
    ///   halves of a surrogate pair.
    public func substring(in range: Range<Int>) throws -> String {
        try validate(range)
        return String(decoding: units[range], as: UTF16.self)
    }

    // MARK: - Mutation

    /// Applies one edit. This is the single mutation path for the document
    /// (`projectRules.md`, Data Safety); views never touch storage directly.
    ///
    /// - Throws: `EditorError.rangeOutOfBounds` if `edit.replacementRange` leaves
    ///   `0...utf16Length`; `EditorError.splitsSurrogatePair` if an endpoint
    ///   splits a surrogate pair. A well-behaved text system never produces a
    ///   split-pair offset, and silently repairing one would hide the bug that
    ///   produced it — so it is rejected, not rounded.
    /// - Returns: the applied edit plus the text it replaced, which is everything
    ///   undo needs.
    @discardableResult
    public func apply(_ edit: TextEdit) throws -> AppliedEdit {
        try validate(edit.replacementRange)
        return applyValidated(edit)
    }

    /// Applies a batch as one unit. Every range is interpreted against the
    /// document state *before* the batch; edits are applied back-to-front so
    /// earlier ranges stay valid.
    ///
    /// **All-or-nothing**: every range is validated, and the batch is checked for
    /// overlap, before a single code unit moves. A throw leaves the document
    /// byte-for-byte unchanged.
    ///
    /// **Overlap** means two edits contend for the same text: two non-empty
    /// ranges sharing at least one code unit, or an insertion point (empty range)
    /// falling strictly inside a non-empty range. Ranges that merely touch
    /// (`0..<3` and `3..<5`) do not overlap, and an insertion at either endpoint
    /// of a replaced range is well defined.
    ///
    /// **Order**: back-to-front by range start. Ties are resolved longest-range
    /// first (so an insertion at the start of a replaced range lands *into* the
    /// replacement rather than being consumed by it), then by reverse position in
    /// `batch.edits` — which puts several insertions at one offset into the
    /// document in the order they were listed.
    ///
    /// - Returns: the applied edits **in application order** (back-to-front). To
    ///   undo the batch, walk the array in reverse and apply each `inverse`.
    @discardableResult
    public func apply(_ batch: TextEditBatch) throws -> [AppliedEdit] {
        for edit in batch.edits {
            try validate(edit.replacementRange)
        }
        try checkForOverlap(batch.edits)

        let order = batch.edits.indices.sorted { lhs, rhs in
            let a = batch.edits[lhs].replacementRange
            let b = batch.edits[rhs].replacementRange
            if a.lowerBound != b.lowerBound { return a.lowerBound > b.lowerBound }
            if a.count != b.count { return a.count > b.count }
            return lhs > rhs
        }

        return order.map { applyValidated(batch.edits[$0]) }
    }

    // MARK: - Lines

    /// Index of the line containing `offset`. The offset is clamped into
    /// `0...utf16Length`; an offset equal to the document length is on the last
    /// line.
    public func lineIndex(forUTF16Offset offset: Int) -> Int {
        index.line(forOffset: clamp(offset))
    }

    /// UTF-16 offsets at which each line begins, in order. Always non-empty and
    /// always starting with `0`.
    public func lineStartOffsets() -> [Int] {
        index.starts
    }

    /// The UTF-16 range of a line, **including its terminator**. Consecutive line
    /// ranges therefore tile the document exactly: the union of all of them is
    /// `0..<utf16Length`, with no gaps. The last line has no terminator to
    /// include.
    ///
    /// - Precondition: `line` is in `0..<lineCount`. Line numbers come from
    ///   `lineIndex(forUTF16Offset:)` or `lineCount`; an out-of-range one is a
    ///   programmer error, not a runtime condition, and traps like a bad array
    ///   subscript.
    public func lineRange(ofLine line: Int) -> Range<Int> {
        let start = index.start(ofLine: line)
        let end = line + 1 < index.lineCount ? index.start(ofLine: line + 1) : units.count
        return start..<end
    }

    /// The UTF-16 range of a line **excluding its terminator** — the companion to
    /// `lineRange(ofLine:)` for callers that want the line's visible content.
    public func lineContentRange(ofLine line: Int) -> Range<Int> {
        let range = lineRange(ofLine: line)
        var end = range.upperBound
        if end > range.lowerBound, units[end - 1] == 0x000A {
            end -= 1
            if end > range.lowerBound, units[end - 1] == 0x000D { end -= 1 }
        } else if end > range.lowerBound, units[end - 1] == 0x000D {
            end -= 1
        }
        return range.lowerBound..<end
    }

    /// Column of `offset` within its line, counted in **grapheme clusters** —
    /// what a reader calls a character. A flag (`🇺🇸`), a ZWJ emoji family, and an
    /// `é` written either composed or decomposed each count as one column.
    ///
    /// The offset is clamped into `0...utf16Length`, and an offset that splits a
    /// surrogate pair is treated as the offset of the pair's start. An offset
    /// interior to a multi-scalar cluster counts that partial cluster as one
    /// column; carets in a well-behaved text system sit on cluster boundaries.
    public func columnIndex(forUTF16Offset offset: Int) -> Int {
        let target = snapToScalarBoundary(clamp(offset))
        let start = index.start(ofLine: index.line(forOffset: target))
        guard target > start else { return 0 }
        return String(decoding: units[start..<target], as: UTF16.self).count
    }

    // MARK: - Internals

    private func applyValidated(_ edit: TextEdit) -> AppliedEdit {
        let range = edit.replacementRange
        let replaced = String(decoding: units[range], as: UTF16.self)
        let inserted = Array(edit.text.utf16)

        units.replaceSubrange(range, with: inserted)
        index.apply(
            units: units,
            editStart: range.lowerBound,
            oldEnd: range.upperBound,
            insertedLength: inserted.count
        )
        cachedText = nil

        return AppliedEdit(edit: edit, replacedText: replaced)
    }

    private func validate(_ range: Range<Int>) throws {
        guard range.lowerBound >= 0, range.upperBound <= units.count else {
            throw EditorError.rangeOutOfBounds(requested: range, documentLength: units.count)
        }
        try checkBoundary(range.lowerBound)
        try checkBoundary(range.upperBound)
    }

    private func checkBoundary(_ offset: Int) throws {
        guard offset > 0, offset < units.count else { return }
        if Self.isHighSurrogate(units[offset - 1]) && Self.isLowSurrogate(units[offset]) {
            throw EditorError.splitsSurrogatePair(offset: offset)
        }
    }

    private func checkForOverlap(_ edits: [TextEdit]) throws {
        guard edits.count > 1 else { return }
        let ranges = edits.map(\.replacementRange).sorted { a, b in
            if a.lowerBound != b.lowerBound { return a.lowerBound < b.lowerBound }
            return a.count > b.count
        }
        var lastLower = Int.min
        var lastUpper = Int.min
        for range in ranges {
            if range.isEmpty {
                if range.lowerBound > lastLower && range.lowerBound < lastUpper {
                    throw EditorError.overlappingBatchEdits
                }
            } else {
                if range.lowerBound < lastUpper {
                    throw EditorError.overlappingBatchEdits
                }
                lastLower = range.lowerBound
                lastUpper = range.upperBound
            }
        }
    }

    private func clamp(_ offset: Int) -> Int {
        min(max(offset, 0), units.count)
    }

    private func snapToScalarBoundary(_ offset: Int) -> Int {
        guard offset > 0, offset < units.count else { return offset }
        if Self.isHighSurrogate(units[offset - 1]) && Self.isLowSurrogate(units[offset]) {
            return offset - 1
        }
        return offset
    }

    private static func isHighSurrogate(_ unit: UInt16) -> Bool { (0xD800...0xDBFF).contains(unit) }
    private static func isLowSurrogate(_ unit: UInt16) -> Bool { (0xDC00...0xDFFF).contains(unit) }
}
