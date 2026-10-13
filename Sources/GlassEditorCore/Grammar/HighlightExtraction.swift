import Foundation
import SwiftTreeSitter

/// Turns a parsed tree plus a compiled highlight query into `[HighlightRun]`.
///
/// ## Output contract
///
/// The returned runs are **sorted, non-overlapping, contiguous, and cover the whole
/// document**: concatenating them reproduces `0..<utf16.count` exactly. Text no
/// capture claimed is `.plain`. A total cover was chosen over a sparse overlay
/// because the renderer has to reset attributes on uncaptured text anyway, and
/// because it makes `plaintext`'s single-`.plain`-run behaviour a consequence of
/// the general rule rather than a special case. An empty document yields no runs.
///
/// Offsets are **UTF-16 code units**, per the `HighlightRun` contract
/// (TokenRole.swift:44). Tree-sitter reports byte offsets; parsing happens in
/// UTF-16LE, so a byte offset is exactly twice a UTF-16 offset, and SwiftTreeSitter
/// already performs that halving in `Node.range` (`Encoding+Helpers.swift`).
/// Nothing in this file re-derives the conversion by hand.
enum HighlightExtractor {

    /// Resolves which of several captures covering the same character wins.
    ///
    /// Overlapping captures are the norm, not the exception — `count` in
    /// `SELECT count(*)` is captured by both `@function.call` and `@type`, and a
    /// SQL numeric literal is captured by `@string`, `@number`, and `@float`. The
    /// rule is **most specific wins**, applied in this order:
    ///
    /// 1. **Dotted specificity.** `@string.special.key` (3 components) outranks
    ///    `@string` (1), so a JSON object key is a `.property` and not a `.string`.
    ///    `@function.call` (2) outranks `@type` (1), so `count(*)` is a `.function`.
    /// 2. **Predicate-guarded outranks unguarded.** A capture carrying a `#match?`
    ///    constraint is more specific by construction, which is what lets
    ///    `((literal) @number (#match? …))` beat the blanket `(literal) @string`
    ///    in SQL.
    /// 3. **Innermost wins.** The shorter range is the more specific statement —
    ///    a fenced-code-block delimiter stays `.punctuation` inside a block that is
    ///    otherwise `.markupCode`.
    /// 4. **Later pattern wins.** nvim-treesitter's own convention: a query orders
    ///    its patterns from general to specific. This is what makes a YAML mapping
    ///    key a `.property` even though `(string_scalar)` is captured as `@string`
    ///    by an earlier pattern over the identical range.
    /// 5. **Earlier capture wins.** Within one match, captures appear in query
    ///    order, so `(comment) @comment @spell` resolves to `.comment`. (`@spell`
    ///    is dropped before this point anyway — see `CaptureMapping.isHighlighting`.)
    ///
    /// Syntax-error regions rank below every capture, so `.error` shows only where
    /// nothing else claimed the text.
    private struct Entry {
        var range: Range<Int>
        var role: TokenRole
        var specificity: Int
        var isGuarded: Bool
        var patternIndex: Int
        var emission: Int

        /// True when `self` should be painted *before* `other`, i.e. is weaker.
        static func weaker(_ lhs: Entry, _ rhs: Entry) -> Bool {
            if lhs.specificity != rhs.specificity { return lhs.specificity < rhs.specificity }
            if lhs.isGuarded != rhs.isGuarded { return !lhs.isGuarded }
            if lhs.range.count != rhs.range.count { return lhs.range.count > rhs.range.count }
            if lhs.patternIndex != rhs.patternIndex { return lhs.patternIndex < rhs.patternIndex }
            return lhs.emission > rhs.emission
        }
    }

    /// Rank given to syntax-error regions: below any real capture.
    private static let errorSpecificity = -1

    /// The most matches tree-sitter keeps in progress at once (`ts_query_cursor_set_match_limit`).
    ///
    /// Unset, tree-sitter allows any number, and 0.25 numbers their capture lists in 16 bits:
    /// past 65,535 two matches share one list, and highlighting a large file can crash
    /// (tree-sitter #5011, fixed by PR 5548 in 0.26.9, which no SwiftTreeSitter release reaches).
    /// A pattern still waiting for a later sibling keeps one match per earlier candidate, and
    /// every node revisits every match in progress, so the time grows faster than the array: one
    /// such pattern over 2,000 numbers took 32 s unlimited and 1.4 s at 256, over 4,000 numbers
    /// 262 s and 3.0 s (debug build, 2026-10-12). Helix uses 256 (helix-editor/helix#4830). On 16
    /// real files in 14 languages, up to 2M characters, every limit down to 64 found exactly the
    /// matches no limit found.
    static let matchLimit = 256

    /// Extract highlight runs for the whole tree.
    ///
    /// - Parameters:
    ///   - tree: the current parse tree.
    ///   - query: the compiled highlight query for `language`.
    ///   - language: selects `CaptureMapping`'s per-grammar overrides.
    ///   - utf16: the document the tree was parsed from, as UTF-16 code units.
    static func runs(in tree: MutableTree, query: Query, language: LanguageID, utf16: [UInt16]) -> [HighlightRun] {
        let length = utf16.count
        guard length > 0 else { return [] }

        var entries: [Entry] = []
        var evaluator = QueryPredicateEvaluator(utf16: utf16)
        var emission = 0

        if let root = tree.rootNode {
            for range in errorRanges(from: root, length: length) {
                entries.append(Entry(
                    range: range,
                    role: .error,
                    specificity: errorSpecificity,
                    isGuarded: false,
                    patternIndex: -1,
                    emission: emission
                ))
                emission += 1
            }
        }

        let cursor = query.execute(in: tree)
        cursor.matchLimit = matchLimit

        while let match = cursor.next() {
            guard evaluator.allows(match) else { continue }
            let guardedNames = QueryPredicateEvaluator.constrainedCaptureNames(in: match)

            for capture in match.captures {
                guard let name = capture.name, CaptureMapping.isHighlighting(name) else { continue }
                guard let range = clamp(capture.range, to: length) else { continue }

                entries.append(Entry(
                    range: range,
                    role: CaptureMapping.role(for: name, in: language),
                    specificity: capture.nameComponents.count,
                    isGuarded: guardedNames.contains(name),
                    patternIndex: match.patternIndex,
                    emission: emission
                ))
                emission += 1
            }
        }

        // Weakest first, so stronger entries overwrite what they overlap.
        entries.sort(by: Entry.weaker)

        var roles = [TokenRole](repeating: .plain, count: length)
        for entry in entries {
            for offset in entry.range { roles[offset] = entry.role }
        }

        return coalesce(roles)
    }

    /// The single full-document `.plain` run used for `plaintext` documents and for
    /// any document whose grammar produced no tree.
    static func plainCover(length: Int) -> [HighlightRun] {
        guard length > 0 else { return [] }
        return [HighlightRun(range: 0..<length, role: .plain)]
    }

    // MARK: - Helpers

    private static func clamp(_ range: NSRange, to length: Int) -> Range<Int>? {
        guard range.location != NSNotFound, range.length > 0 else { return nil }

        let lower = max(0, range.location)
        let upper = min(length, range.location + range.length)
        guard lower < upper else { return nil }

        return lower..<upper
    }

    /// UTF-16 ranges of `ERROR` nodes in the tree.
    ///
    /// Walked only when the root reports an error, so a well-formed document pays
    /// nothing. `ERROR` subtrees are not descended into — the whole region is one
    /// error span, and any valid capture inside it still outranks it.
    ///
    /// tree-sitter's other failure shape, a `MISSING` node standing in for an
    /// omitted token, is zero-width and therefore produces no run. That is
    /// deliberate: there is no text to mark, and inventing a one-character span
    /// would put a role on a character the parser never objected to.
    private static func errorRanges(from root: Node, length: Int) -> [Range<Int>] {
        guard root.hasError else { return [] }

        var ranges: [Range<Int>] = []
        var stack: [Node] = [root]

        while let node = stack.popLast() {
            if node.nodeType == "ERROR" {
                if let range = clamp(node.range, to: length) { ranges.append(range) }
                continue
            }

            guard node.hasError else { continue }

            for index in 0..<node.childCount {
                if let child = node.child(at: index) { stack.append(child) }
            }
        }

        return ranges
    }

    private static func coalesce(_ roles: [TokenRole]) -> [HighlightRun] {
        var runs: [HighlightRun] = []
        var start = 0
        var current = roles[0]

        for offset in 1..<roles.count where roles[offset] != current {
            runs.append(HighlightRun(range: start..<offset, role: current))
            start = offset
            current = roles[offset]
        }

        runs.append(HighlightRun(range: start..<roles.count, role: current))
        return runs
    }
}
