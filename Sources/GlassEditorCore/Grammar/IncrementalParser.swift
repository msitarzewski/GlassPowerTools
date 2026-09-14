import Foundation
import SwiftTreeSitter

/// One parser per open document: owns the tree, applies edits incrementally, and
/// publishes the current `[HighlightRun]`.
///
/// ## Isolation
///
/// `@MainActor`, for the reason given on `GrammarRegistry`: SwiftTreeSitter's
/// `Parser` and the C grammars underneath it are not thread-safe, and this type
/// holds one for the document's whole lifetime. `HighlightRun` is `Sendable`, so a
/// future background parse actor could own a `DocumentParser` and hand runs back
/// across isolation without changing this API — that is the M5 shape, not v1.
///
/// ## Units
///
/// Every offset in this type's API is a **UTF-16 code unit** — `TextEdit`'s
/// `replacementRange`, `HighlightRun`'s `range`, and `lastChangedRanges` alike.
/// Parsing runs in UTF-16LE (`Parser.parse(_:)` uses `TSInputEncodingUTF16LE`), so
/// tree-sitter's byte offsets are exactly twice these, and its `Point.column` is a
/// byte column. Both conversions are confined to this file and
/// `HighlightExtraction.swift`.
///
/// ## Markdown limitation
///
/// `markdown` is parsed with the **block** grammar only. tree-sitter-markdown is a
/// two-grammar language: the block grammar reduces every paragraph to an opaque
/// `(inline)` node, and inline structure (emphasis, inline code, link text) only
/// appears when `tree-sitter-markdown-inline` is run as an injection over those
/// nodes, with its own tree, its own incremental-edit bookkeeping, and its own
/// included-range maintenance across every edit. That is a second parser lifecycle,
/// not a query change, so it is deferred.
///
/// What this means in practice: ATX and setext **headings** highlight
/// (`.markupHeading`, via `(atx_heading (inline) @text.title)`), as do fenced and
/// indented **code blocks** (`.markupCode`), fence delimiters, heading markers,
/// list markers, block-quote markers and thematic breaks (`.punctuation`), and the
/// destination and label of a **link reference definition** (`.markupLink`), which
/// is itself a block construct.
///
/// What does **not** highlight is everything the block grammar folds into an
/// `(inline)` node: emphasis and strong markers, inline code spans, backslash
/// escapes, and the `[text](url)` form of a link. `.markupEmphasis` and
/// `.markupStrong` are therefore unreachable for now — no vendored query other than
/// `markdown-inline-highlights.scm` emits them. That query, and the inline grammar
/// it targets, are vendored and compiling today, and
/// `GrammarRegistry.markdownInlineLanguage` hands the grammar out, so the remaining
/// work is injection wiring rather than vendoring.
@MainActor
public final class DocumentParser {

    /// The language this parser was built for.
    public let language: LanguageID

    /// Highlight runs for the current tree. Sorted, non-overlapping, contiguous,
    /// and covering the whole document — see `HighlightExtractor`.
    public private(set) var highlights: [HighlightRun] = []

    /// Whether the most recent parse reused the previous tree.
    ///
    /// `false` after `parseFull(_:)`, after the first `apply(_:newSnapshot:)` on a
    /// parser that has no tree yet, and after any edit that failed validation and
    /// fell back to a full reparse. Always `false` for `plaintext`, which never
    /// parses at all.
    public private(set) var lastParseWasIncremental: Bool = false

    /// UTF-16 ranges tree-sitter reported as structurally changed by the most
    /// recent incremental parse.
    ///
    /// This is the observable evidence that reuse actually happened: a one-character
    /// edit in the middle of a large document reports a small local range, not the
    /// whole document. Empty after a full parse.
    public private(set) var lastChangedRanges: [Range<Int>] = []

    /// Number of parses performed, incremental or full. Test and profiling hook.
    public private(set) var parseCount: Int = 0

    /// Current document length in UTF-16 code units.
    public var documentLength: Int { utf16.count }

    /// Above this many UTF-16 code units, highlighting degrades to a single
    /// plaintext run instead of running the query over the whole tree
    /// (pen finding M-7). Highlight extraction is not incremental — it allocates
    /// a role array for the whole document and re-runs the query every parse — so
    /// without a bound a large document pays a full-document sweep every debounce
    /// beat on the main actor. The document still *parses* (the tree is used for
    /// nothing else here, but the machinery stays intact); it just is not
    /// coloured. Default ~2M code units; the file still opens up to the separate,
    /// larger `GlassEditorConfiguration.largeFileByteCeiling`.
    public let highlightingCodeUnitCeiling: Int

    /// Whether the current document is above `highlightingCodeUnitCeiling` and so
    /// rendered as plaintext. Observable so a consumer can surface "syntax
    /// highlighting off (large file)".
    public private(set) var highlightingDegraded: Bool = false

    private let grammar: GrammarRegistry.LoadedGrammar
    private let parser: Parser?
    private var tree: MutableTree?
    private var utf16: [UInt16] = []
    private var lineIndex = LineStartIndex()

    /// - Parameter highlightingCodeUnitCeiling: see the property; the default is
    ///   conservative and can be raised once extraction is made incremental.
    /// - Throws: whatever `GrammarRegistry.grammar(for:)` throws, plus
    ///   `EditorError.grammarUnavailable` if the grammar loads but the parser
    ///   refuses it.
    public init(
        language: LanguageID,
        registry: GrammarRegistry,
        highlightingCodeUnitCeiling: Int = 2_000_000
    ) throws {
        let grammar = try registry.grammar(for: language)
        self.language = language
        self.grammar = grammar
        self.highlightingCodeUnitCeiling = highlightingCodeUnitCeiling

        if let tsLanguage = grammar.treeSitterLanguage {
            let parser = Parser()
            do {
                try parser.setLanguage(tsLanguage)
            } catch {
                throw EditorError.grammarUnavailable(language: language)
            }
            self.parser = parser
        } else {
            self.parser = nil
        }
    }

    /// Parse `snapshot` from scratch, discarding any previous tree.
    public func parseFull(_ snapshot: String) {
        utf16 = Array(snapshot.utf16)
        lineIndex.rebuild(from: utf16)

        tree = parser?.parse(snapshot)
        lastParseWasIncremental = false
        lastChangedRanges = []
        parseCount += 1
        recomputeHighlights()
    }

    /// Apply one edit and reparse incrementally.
    ///
    /// `newSnapshot` must be the document *after* `edit` has been applied — this
    /// type does not own the buffer, `TextStorageBuffer` does. The two are
    /// cross-checked (the edit's range must be in bounds and the resulting length
    /// must match); a mismatch falls back to a full reparse rather than feeding
    /// tree-sitter an inconsistent `InputEdit`, which would corrupt the tree
    /// silently instead of loudly.
    public func apply(_ edit: TextEdit, newSnapshot: String) {
        guard let parser, let editedTree = tree else {
            parseFull(newSnapshot)
            return
        }

        let start = edit.replacementRange.lowerBound
        let oldEnd = edit.replacementRange.upperBound
        let newEnd = start + edit.insertedLength
        let inserted = Array(edit.text.utf16)
        let newUTF16 = Array(newSnapshot.utf16)

        guard start >= 0,
              start <= oldEnd,
              oldEnd <= utf16.count,
              newUTF16.count == utf16.count + edit.lengthDelta
        else {
            parseFull(newSnapshot)
            return
        }

        let startPoint = lineIndex.point(at: start)
        let oldEndPoint = lineIndex.point(at: oldEnd)

        utf16 = newUTF16
        lineIndex.apply(replacing: start..<oldEnd, inserted: inserted)
        let newEndPoint = lineIndex.point(at: newEnd)

        editedTree.edit(InputEdit(
            startByte: start * 2,
            oldEndByte: oldEnd * 2,
            newEndByte: newEnd * 2,
            startPoint: startPoint,
            oldEndPoint: oldEndPoint,
            newEndPoint: newEndPoint
        ))

        guard let newTree = parser.parse(tree: editedTree, string: newSnapshot) else {
            parseFull(newSnapshot)
            return
        }

        // `changedRanges` is asked of the *edited old* tree, per tree-sitter's
        // documented order (SwiftTreeSitter InputEdit.swift:20).
        lastChangedRanges = editedTree.changedRanges(from: newTree).map {
            Int($0.bytes.lowerBound / 2)..<Int($0.bytes.upperBound / 2)
        }

        tree = newTree
        lastParseWasIncremental = true
        parseCount += 1
        recomputeHighlights()
    }

    // MARK: - Highlighting

    /// Rebuilds `highlights` from the current tree.
    ///
    /// The query is re-run over the whole tree after every parse. The incremental
    /// win claimed by this type is in the *parse*, which is the expensive half;
    /// restricting the query cursor to `lastChangedRanges` and splicing runs is a
    /// real further optimisation, but it changes the output contract from "derived
    /// from the tree" to "derived from the tree plus an edit history", and that is
    /// a correctness risk this milestone does not need to take. The
    /// incremental-equals-full test in `GrammarModuleTests` is what would have to
    /// keep passing if it is taken later.
    private func recomputeHighlights() {
        // Above the ceiling, degrade to plaintext rather than pay a
        // full-document query sweep every beat (pen finding M-7).
        guard utf16.count <= highlightingCodeUnitCeiling else {
            highlightingDegraded = true
            highlights = HighlightExtractor.plainCover(length: utf16.count)
            return
        }
        highlightingDegraded = false

        guard let tree, let query = grammar.highlightQuery else {
            highlights = HighlightExtractor.plainCover(length: utf16.count)
            return
        }

        highlights = HighlightExtractor.runs(
            in: tree,
            query: query,
            language: language,
            utf16: utf16
        )
    }
}

/// UTF-16 offsets at which each line begins, maintained across edits.
///
/// Exists so `DocumentParser` can produce tree-sitter `Point`s without rescanning
/// the document on every keystroke: a lookup is a binary search, and an edit splices
/// only the line starts the edit actually disturbed. Line starts are the offsets
/// following each `U+000A`, which is exactly how tree-sitter counts rows — a CRLF
/// pair leaves its `\r` at the end of the preceding row.
struct LineStartIndex {
    private var starts: [Int] = [0]

    /// Number of lines currently indexed. Test hook.
    var lineCount: Int { starts.count }

    mutating func rebuild(from utf16: [UInt16]) {
        starts = [0]
        for (offset, unit) in utf16.enumerated() where unit == 0x0A {
            starts.append(offset + 1)
        }
    }

    /// The tree-sitter `Point` for a UTF-16 offset.
    ///
    /// `column` is a **byte** column, as tree-sitter requires. Parsing is UTF-16LE,
    /// so that is twice the UTF-16 column.
    func point(at offset: Int) -> Point {
        let row = rowIndex(containing: offset)
        return Point(row: row, column: (offset - starts[row]) * 2)
    }

    /// Splice the index for a replacement of `range` by `inserted`.
    mutating func apply(replacing range: Range<Int>, inserted: [UInt16]) {
        let start = range.lowerBound
        let oldEnd = range.upperBound
        let delta = inserted.count - range.count

        // Line starts strictly after `start` and at or before `oldEnd` are the ones
        // whose newline lay inside the replaced text; they go away.
        let lower = firstIndex(above: start)
        let upper = firstIndex(above: oldEnd)

        var replacements: [Int] = []
        for (offset, unit) in inserted.enumerated() where unit == 0x0A {
            replacements.append(start + offset + 1)
        }

        starts.replaceSubrange(lower..<upper, with: replacements)

        let tail = lower + replacements.count
        if delta != 0 && tail < starts.count {
            for index in tail..<starts.count { starts[index] += delta }
        }
    }

    /// Index of the last line start at or before `offset`.
    private func rowIndex(containing offset: Int) -> Int {
        max(0, firstIndex(above: offset) - 1)
    }

    /// Index of the first line start strictly greater than `offset`.
    private func firstIndex(above offset: Int) -> Int {
        var low = 0
        var high = starts.count

        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= offset { low = mid + 1 } else { high = mid }
        }

        return low
    }
}
