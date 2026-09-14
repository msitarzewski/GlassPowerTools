import Testing
@testable import GlassEditorCore

/// Hand-picked storage cases: the boundaries, the conventions, and the hostile
/// content. The randomized half lives in `StoragePropertyTests.swift`.
@Suite("Storage buffer")
struct StorageBufferTests {

    // MARK: - Basics

    @Test("Empty buffer is one empty line")
    func emptyDocument() {
        let buffer = TextStorageBuffer()
        #expect(buffer.text == "")
        #expect(buffer.utf16Length == 0)
        #expect(buffer.lineCount == 1)
        #expect(buffer.lineStartOffsets() == [0])
        #expect(buffer.lineRange(ofLine: 0) == 0..<0)
        #expect(buffer.lineIndex(forUTF16Offset: 0) == 0)
    }

    @Test("Astral characters count as two UTF-16 units")
    func utf16Length() {
        #expect(TextStorageBuffer(text: "🙂").utf16Length == 2)
        #expect(TextStorageBuffer(text: "héllo").utf16Length == 5)
        #expect(TextStorageBuffer(text: "🇺🇸").utf16Length == 4)
    }

    // MARK: - Single edits

    @Test("Insert at start, middle, and end")
    func insertAtBoundaries() throws {
        let buffer = TextStorageBuffer(text: "bcd")
        try buffer.apply(.insert("a", at: 0))
        #expect(buffer.text == "abcd")
        try buffer.apply(.insert("X", at: 2))
        #expect(buffer.text == "abXcd")
        try buffer.apply(.insert("e", at: buffer.utf16Length))
        #expect(buffer.text == "abXcde")
    }

    @Test("Delete at start, middle, and end")
    func deleteAtBoundaries() throws {
        let buffer = TextStorageBuffer(text: "abcdef")
        try buffer.apply(.delete(0..<1))
        #expect(buffer.text == "bcdef")
        try buffer.apply(.delete(2..<3))
        #expect(buffer.text == "bcef")
        try buffer.apply(.delete(3..<4))
        #expect(buffer.text == "bce")
    }

    @Test("Replace reports the text it replaced")
    func replaceReportsReplacedText() throws {
        let buffer = TextStorageBuffer(text: "hello world")
        let applied = try buffer.apply(TextEdit(replacementRange: 6..<11, text: "there"))
        #expect(buffer.text == "hello there")
        #expect(applied.replacedText == "world")
        #expect(applied.inverse == TextEdit(replacementRange: 6..<11, text: "world"))
    }

    @Test("Whole-document replace")
    func wholeDocumentReplace() throws {
        let buffer = TextStorageBuffer(text: "one\ntwo\nthree\n")
        let applied = try buffer.apply(
            TextEdit(replacementRange: 0..<buffer.utf16Length, text: "just one line")
        )
        #expect(buffer.text == "just one line")
        #expect(buffer.lineCount == 1)
        #expect(applied.replacedText == "one\ntwo\nthree\n")

        // And back again, via the inverse.
        try buffer.apply(applied.inverse)
        #expect(buffer.text == "one\ntwo\nthree\n")
        #expect(buffer.lineCount == 4)
    }

    @Test("Empty edit is a no-op that still reports cleanly")
    func emptyEdit() throws {
        let buffer = TextStorageBuffer(text: "abc\ndef")
        let applied = try buffer.apply(TextEdit(replacementRange: 3..<3, text: ""))
        #expect(buffer.text == "abc\ndef")
        #expect(applied.replacedText == "")
        #expect(applied.inverse == TextEdit(replacementRange: 3..<3, text: ""))
        #expect(buffer.lineCount == 2)
    }

    @Test("Inverse of an applied edit restores the previous text")
    func inverseRoundTrip() throws {
        let buffer = TextStorageBuffer(text: "alpha\nbeta\ngamma")
        let before = buffer.text
        let applied = try buffer.apply(TextEdit(replacementRange: 5..<11, text: "🙂\r\n"))
        #expect(buffer.text != before)
        try buffer.apply(applied.inverse)
        #expect(buffer.text == before)
        #expect(buffer.lineCount == 3)
    }

    // MARK: - Range validation

    @Test("Out-of-bounds ranges throw and change nothing")
    func rangeOutOfBounds() throws {
        let buffer = TextStorageBuffer(text: "abc")
        #expect(throws: EditorError.rangeOutOfBounds(requested: 0..<4, documentLength: 3)) {
            try buffer.apply(TextEdit(replacementRange: 0..<4, text: "x"))
        }
        #expect(throws: EditorError.rangeOutOfBounds(requested: 4..<4, documentLength: 3)) {
            try buffer.apply(.insert("x", at: 4))
        }
        #expect(throws: EditorError.self) {
            try buffer.substring(in: 1..<9)
        }
        #expect(buffer.text == "abc")
    }

    @Test("Edges of the valid range are accepted")
    func rangeEdgesAccepted() throws {
        let buffer = TextStorageBuffer(text: "abc")
        #expect(try buffer.substring(in: 0..<3) == "abc")
        #expect(try buffer.substring(in: 3..<3) == "")
        #expect(try buffer.substring(in: 0..<0) == "")
    }

    @Test("An offset splitting a surrogate pair is rejected, not repaired")
    func surrogateSplitRejected() throws {
        // "a🙂b": offsets 1 and 3 are the two halves of the emoji.
        let buffer = TextStorageBuffer(text: "a🙂b")
        #expect(buffer.utf16Length == 4)

        #expect(throws: EditorError.splitsSurrogatePair(offset: 2)) {
            try buffer.apply(.insert("!", at: 2))
        }
        #expect(throws: EditorError.splitsSurrogatePair(offset: 2)) {
            try buffer.apply(.delete(2..<4))
        }
        #expect(throws: EditorError.splitsSurrogatePair(offset: 2)) {
            try buffer.substring(in: 0..<2)
        }
        #expect(buffer.text == "a🙂b")

        // The pair's own boundaries are fine.
        #expect(try buffer.substring(in: 1..<3) == "🙂")
        try buffer.apply(.delete(1..<3))
        #expect(buffer.text == "ab")
    }

    @Test("A surrogate pair in a ZWJ sequence is still protected mid-sequence")
    func surrogateSplitInsideFamilyEmoji() {
        let buffer = TextStorageBuffer(text: "👨‍👩‍👧‍👦")
        #expect(throws: EditorError.splitsSurrogatePair(offset: 1)) {
            try buffer.apply(.insert("x", at: 1))
        }
        // The ZWJ joiners are BMP, so their boundaries are legal offsets even
        // though they sit inside one grapheme cluster.
        #expect(throws: Never.self) {
            _ = try buffer.substring(in: 0..<2)
        }
    }

    // MARK: - Batches

    @Test("Batch ranges are interpreted against pre-batch state")
    func batchUsesPreBatchCoordinates() throws {
        let buffer = TextStorageBuffer(text: "0123456789")
        let applied = try buffer.apply(TextEditBatch(edits: [
            TextEdit(replacementRange: 1..<3, text: "AA"),
            TextEdit(replacementRange: 6..<8, text: "B"),
        ]))
        #expect(buffer.text == "0AA345B89")
        #expect(applied.count == 2)
        // Application order is back-to-front.
        #expect(applied[0].edit.replacementRange == 6..<8)
        #expect(applied[1].edit.replacementRange == 1..<3)
        #expect(applied[0].replacedText == "67")
        #expect(applied[1].replacedText == "12")
    }

    @Test("A batch undoes by walking the applied edits in reverse")
    func batchInverseRoundTrip() throws {
        let buffer = TextStorageBuffer(text: "one\ntwo\nthree\nfour")
        let before = buffer.text
        let applied = try buffer.apply(TextEditBatch(edits: [
            TextEdit(replacementRange: 0..<3, text: "1"),
            TextEdit(replacementRange: 4..<7, text: "2️⃣"),
            TextEdit(replacementRange: 8..<13, text: ""),
        ]))
        #expect(buffer.text == "1\n2️⃣\n\nfour")

        for entry in applied.reversed() {
            try buffer.apply(entry.inverse)
        }
        #expect(buffer.text == before)
        #expect(buffer.lineCount == 4)
    }

    @Test("Overlapping ranges are rejected")
    func batchOverlapRejected() {
        let buffer = TextStorageBuffer(text: "0123456789")
        #expect(throws: EditorError.overlappingBatchEdits) {
            try buffer.apply(TextEditBatch(edits: [
                TextEdit(replacementRange: 1..<5, text: "a"),
                TextEdit(replacementRange: 4..<7, text: "b"),
            ]))
        }
        // Containment counts as overlap.
        #expect(throws: EditorError.overlappingBatchEdits) {
            try buffer.apply(TextEditBatch(edits: [
                TextEdit(replacementRange: 1..<9, text: "a"),
                TextEdit(replacementRange: 3..<4, text: "b"),
            ]))
        }
        // An insertion point strictly inside a replaced range is ambiguous.
        #expect(throws: EditorError.overlappingBatchEdits) {
            try buffer.apply(TextEditBatch(edits: [
                TextEdit(replacementRange: 1..<5, text: "a"),
                TextEdit(replacementRange: 3..<3, text: "b"),
            ]))
        }
    }

    @Test("Touching ranges and shared endpoints are not overlaps")
    func batchTouchingRangesAllowed() throws {
        let buffer = TextStorageBuffer(text: "0123456789")
        try buffer.apply(TextEditBatch(edits: [
            TextEdit(replacementRange: 0..<3, text: "a"),
            TextEdit(replacementRange: 3..<5, text: "b"),
        ]))
        #expect(buffer.text == "ab56789")

        let other = TextStorageBuffer(text: "0123456789")
        // Insertion at the start of a replaced range: the replacement happens
        // first, so the insertion lands into it.
        try other.apply(TextEditBatch(edits: [
            TextEdit(replacementRange: 2..<2, text: "["),
            TextEdit(replacementRange: 2..<5, text: "X"),
        ]))
        #expect(other.text == "01[X56789")
    }

    @Test("Several insertions at one offset keep their listed order")
    func batchInsertionsAtSameOffset() throws {
        let buffer = TextStorageBuffer(text: "()")
        try buffer.apply(TextEditBatch(edits: [
            TextEdit(replacementRange: 1..<1, text: "a"),
            TextEdit(replacementRange: 1..<1, text: "b"),
            TextEdit(replacementRange: 1..<1, text: "c"),
        ]))
        #expect(buffer.text == "(abc)")
    }

    @Test("A batch is all-or-nothing: a bad range leaves the document untouched")
    func batchAllOrNothing() {
        let buffer = TextStorageBuffer(text: "0123456789")
        let before = buffer.text
        let beforeLines = buffer.lineStartOffsets()

        #expect(throws: EditorError.self) {
            try buffer.apply(TextEditBatch(edits: [
                TextEdit(replacementRange: 0..<2, text: "ok\n"),
                TextEdit(replacementRange: 8..<20, text: "bad"),
            ]))
        }
        #expect(buffer.text == before)
        #expect(buffer.lineStartOffsets() == beforeLines)

        #expect(throws: EditorError.overlappingBatchEdits) {
            try buffer.apply(TextEditBatch(edits: [
                TextEdit(replacementRange: 0..<2, text: "ok\n"),
                TextEdit(replacementRange: 1..<3, text: "clash"),
            ]))
        }
        #expect(buffer.text == before)
        #expect(buffer.lineStartOffsets() == beforeLines)
    }

    @Test("An empty batch is a no-op")
    func emptyBatch() throws {
        let buffer = TextStorageBuffer(text: "abc")
        let applied = try buffer.apply(TextEditBatch(edits: []))
        #expect(applied.isEmpty)
        #expect(buffer.text == "abc")
    }

    // MARK: - Line conventions

    @Test("A trailing terminator means a final empty line")
    func trailingNewlineConvention() {
        #expect(TextStorageBuffer(text: "").lineCount == 1)
        #expect(TextStorageBuffer(text: "a").lineCount == 1)
        #expect(TextStorageBuffer(text: "a\n").lineCount == 2)
        #expect(TextStorageBuffer(text: "a\n\n").lineCount == 3)
        #expect(TextStorageBuffer(text: "\n").lineCount == 2)

        let buffer = TextStorageBuffer(text: "a\n")
        #expect(buffer.lineStartOffsets() == [0, 2])
        #expect(buffer.lineRange(ofLine: 1) == 2..<2)
        #expect(buffer.lineIndex(forUTF16Offset: 2) == 1)
    }

    @Test("LF, CR, and CRLF all terminate a line; CRLF is one terminator")
    func terminatorFlavours() {
        #expect(TextStorageBuffer(text: "a\nb").lineStartOffsets() == [0, 2])
        #expect(TextStorageBuffer(text: "a\rb").lineStartOffsets() == [0, 2])
        #expect(TextStorageBuffer(text: "a\r\nb").lineStartOffsets() == [0, 3])
        #expect(TextStorageBuffer(text: "a\n\rb").lineStartOffsets() == [0, 2, 3])
        #expect(TextStorageBuffer(text: "a\r\n").lineCount == 2)
        // Not line terminators: U+2028, U+0085, form feed.
        #expect(TextStorageBuffer(text: "a\u{2028}b").lineCount == 1)
        #expect(TextStorageBuffer(text: "a\u{0085}b").lineCount == 1)
    }

    @Test("lineRange includes the terminator; lineContentRange does not")
    func lineRangeConventions() throws {
        let buffer = TextStorageBuffer(text: "one\ntwo\r\nthree\rfour")
        #expect(buffer.lineCount == 4)
        #expect(buffer.lineRange(ofLine: 0) == 0..<4)
        #expect(buffer.lineRange(ofLine: 1) == 4..<9)
        #expect(buffer.lineRange(ofLine: 2) == 9..<15)
        #expect(buffer.lineRange(ofLine: 3) == 15..<19)

        #expect(try buffer.substring(in: buffer.lineRange(ofLine: 1)) == "two\r\n")
        #expect(try buffer.substring(in: buffer.lineContentRange(ofLine: 0)) == "one")
        #expect(try buffer.substring(in: buffer.lineContentRange(ofLine: 1)) == "two")
        #expect(try buffer.substring(in: buffer.lineContentRange(ofLine: 2)) == "three")
        #expect(try buffer.substring(in: buffer.lineContentRange(ofLine: 3)) == "four")

        // Line ranges tile the document exactly.
        var cursor = 0
        for line in 0..<buffer.lineCount {
            #expect(buffer.lineRange(ofLine: line).lowerBound == cursor)
            cursor = buffer.lineRange(ofLine: line).upperBound
        }
        #expect(cursor == buffer.utf16Length)
    }

    @Test("lineIndex maps every offset to the line that contains it")
    func lineIndexMapping() {
        let buffer = TextStorageBuffer(text: "ab\ncd\n")
        #expect(buffer.lineIndex(forUTF16Offset: 0) == 0)
        #expect(buffer.lineIndex(forUTF16Offset: 2) == 0) // the LF itself
        #expect(buffer.lineIndex(forUTF16Offset: 3) == 1)
        #expect(buffer.lineIndex(forUTF16Offset: 5) == 1)
        #expect(buffer.lineIndex(forUTF16Offset: 6) == 2)
        // Clamping, not trapping.
        #expect(buffer.lineIndex(forUTF16Offset: -5) == 0)
        #expect(buffer.lineIndex(forUTF16Offset: 999) == 2)
    }

    // MARK: - Incremental line index

    @Test("Line index tracks inserts and deletes without a full rescan")
    func incrementalLineIndex() throws {
        let buffer = TextStorageBuffer(text: "one\ntwo\nthree")
        #expect(buffer.lineStartOffsets() == [0, 4, 8])

        try buffer.apply(.insert("XY", at: 0))
        #expect(buffer.lineStartOffsets() == [0, 6, 10])

        try buffer.apply(.insert("\n", at: 6))
        #expect(buffer.text == "XYone\n\ntwo\nthree")
        #expect(buffer.lineStartOffsets() == [0, 6, 7, 11])

        try buffer.apply(.delete(6..<7))
        #expect(buffer.text == "XYone\ntwo\nthree")
        #expect(buffer.lineStartOffsets() == [0, 6, 10])

        try buffer.apply(TextEdit(replacementRange: 0..<2, text: "a\nb\nc\n"))
        #expect(buffer.text == "a\nb\nc\none\ntwo\nthree")
        #expect(buffer.lineStartOffsets() == [0, 2, 4, 6, 10, 14])
    }

    @Test("A keystroke rescans a line, not the document")
    func editsAreIncremental() throws {
        // The glassdb bug this package exists to kill: re-deriving line starts
        // for the whole document on every keystroke. Asserted structurally, not
        // by timing.
        let line = String(repeating: "SELECT * FROM t WHERE id = 1;", count: 2) + "\n"
        let buffer = TextStorageBuffer(text: String(repeating: line, count: 4000))
        #expect(buffer.lineCount == 4001)
        #expect(buffer.utf16Length > 200_000)

        // The rescan is bounded by the edited line plus whatever the edit added
        // — never by the document.
        let lineBudget = line.utf16.count + 4
        let middle = buffer.lineRange(ofLine: 2000).lowerBound + 10

        try buffer.apply(.insert("x", at: middle))
        #expect(buffer.index.lastRescanSpan <= lineBudget)
        #expect(buffer.lineCount == 4001)

        try buffer.apply(.insert("\n", at: middle))
        #expect(buffer.index.lastRescanSpan <= lineBudget)
        #expect(buffer.lineCount == 4002)

        try buffer.apply(.delete(middle..<(middle + 1)))
        #expect(buffer.index.lastRescanSpan <= lineBudget)
        #expect(buffer.lineCount == 4001)

        // Stated the other way round, so the intent survives a refactor: a
        // keystroke touches well under one percent of a 200K-unit document.
        #expect(buffer.index.lastRescanSpan * 100 < buffer.utf16Length)

        // Only a whole-document edit is allowed to cost a whole-document scan.
        try buffer.apply(TextEdit(replacementRange: 0..<buffer.utf16Length, text: "done"))
        #expect(buffer.text == "done")
    }

    @Test("Edits inside and across a CRLF pair keep the index honest")
    func crlfSpanningEdits() throws {
        // Splitting a CRLF apart makes two lines out of one terminator.
        let split = TextStorageBuffer(text: "a\r\nb")
        #expect(split.lineStartOffsets() == [0, 3])
        try split.apply(.insert("X", at: 2))
        #expect(split.text == "a\rX\nb")
        #expect(split.lineStartOffsets() == [0, 2, 4])

        // Deleting the LF of a CRLF leaves a lone CR, still one terminator.
        let dropLF = TextStorageBuffer(text: "a\r\nb")
        try dropLF.apply(.delete(2..<3))
        #expect(dropLF.text == "a\rb")
        #expect(dropLF.lineStartOffsets() == [0, 2])

        // Typing an LF after a lone CR merges them into one terminator.
        let merge = TextStorageBuffer(text: "a\rb")
        #expect(merge.lineStartOffsets() == [0, 2])
        try merge.apply(.insert("\n", at: 2))
        #expect(merge.text == "a\r\nb")
        #expect(merge.lineStartOffsets() == [0, 3])

        // Deleting the CR of a CRLF leaves a lone LF.
        let dropCR = TextStorageBuffer(text: "a\r\nb")
        try dropCR.apply(.delete(1..<2))
        #expect(dropCR.text == "a\nb")
        #expect(dropCR.lineStartOffsets() == [0, 2])

        // An edit that swallows a whole pair and leaves a CR butting up against
        // the next pair's LF.
        let across = TextStorageBuffer(text: "aa\r\nbb\r\ncc")
        #expect(across.lineStartOffsets() == [0, 4, 8])
        try across.apply(TextEdit(replacementRange: 2..<6, text: "\r"))
        #expect(across.text == "aa\r\r\ncc")
        #expect(across.lineStartOffsets() == [0, 3, 5])
    }

    @Test("Deleting every terminator collapses to one line")
    func collapseToOneLine() throws {
        let buffer = TextStorageBuffer(text: "a\nb\nc\nd\n")
        #expect(buffer.lineCount == 5)
        try buffer.apply(TextEditBatch(edits: [
            TextEdit(replacementRange: 1..<2, text: ""),
            TextEdit(replacementRange: 3..<4, text: ""),
            TextEdit(replacementRange: 5..<6, text: ""),
            TextEdit(replacementRange: 7..<8, text: ""),
        ]))
        #expect(buffer.text == "abcd")
        #expect(buffer.lineCount == 1)
        #expect(buffer.lineStartOffsets() == [0])
    }

    // MARK: - Grapheme columns

    @Test("Columns count grapheme clusters, not code units")
    func graphemeColumns() {
        let buffer = TextStorageBuffer(text: "ab🙂c")
        #expect(buffer.columnIndex(forUTF16Offset: 0) == 0)
        #expect(buffer.columnIndex(forUTF16Offset: 1) == 1)
        #expect(buffer.columnIndex(forUTF16Offset: 2) == 2)
        #expect(buffer.columnIndex(forUTF16Offset: 4) == 3) // after the emoji
        #expect(buffer.columnIndex(forUTF16Offset: 5) == 4)
    }

    @Test("A regional-indicator flag is one column")
    func flagColumn() {
        let buffer = TextStorageBuffer(text: "🇺🇸x")
        #expect(buffer.utf16Length == 5)
        #expect(buffer.columnIndex(forUTF16Offset: 4) == 1)
        #expect(buffer.columnIndex(forUTF16Offset: 5) == 2)
    }

    @Test("A ZWJ emoji family is one column")
    func zwjFamilyColumn() {
        let family = "👨‍👩‍👧‍👦"
        let buffer = TextStorageBuffer(text: family + "!")
        #expect(buffer.utf16Length == family.utf16.count + 1)
        #expect(buffer.columnIndex(forUTF16Offset: family.utf16.count) == 1)
        #expect(buffer.columnIndex(forUTF16Offset: family.utf16.count + 1) == 2)
    }

    @Test("Composed and decomposed é are both one column")
    func combiningMarkColumn() {
        let composed = TextStorageBuffer(text: "\u{00E9}z")
        #expect(composed.utf16Length == 2)
        #expect(composed.columnIndex(forUTF16Offset: 1) == 1)
        #expect(composed.columnIndex(forUTF16Offset: 2) == 2)

        let decomposed = TextStorageBuffer(text: "e\u{0301}z")
        #expect(decomposed.utf16Length == 3)
        #expect(decomposed.columnIndex(forUTF16Offset: 2) == 1)
        #expect(decomposed.columnIndex(forUTF16Offset: 3) == 2)

        // A base with a stack of marks is still one column.
        let stacked = TextStorageBuffer(text: "a\u{0301}\u{0308}\u{0327}b")
        #expect(stacked.columnIndex(forUTF16Offset: 4) == 1)
        #expect(stacked.columnIndex(forUTF16Offset: 5) == 2)
    }

    @Test("Columns are measured from the start of the offset's own line")
    func columnsRestartPerLine() {
        let buffer = TextStorageBuffer(text: "🙂🙂\nab🙂")
        #expect(buffer.columnIndex(forUTF16Offset: 4) == 2)  // end of line 0
        #expect(buffer.columnIndex(forUTF16Offset: 5) == 0)  // start of line 1
        #expect(buffer.columnIndex(forUTF16Offset: 7) == 2)
        #expect(buffer.columnIndex(forUTF16Offset: 9) == 3)
    }

    @Test("Column offsets are clamped and surrogate-safe")
    func columnEdgeCases() {
        let buffer = TextStorageBuffer(text: "a🙂")
        #expect(buffer.columnIndex(forUTF16Offset: -3) == 0)
        #expect(buffer.columnIndex(forUTF16Offset: 99) == 2)
        // Offset 2 splits the pair; it is treated as the pair's start.
        #expect(buffer.columnIndex(forUTF16Offset: 2) == 1)
    }
}
