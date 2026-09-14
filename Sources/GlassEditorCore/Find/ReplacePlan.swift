import Foundation

/// Replace-all and replace-one, expressed as `TextEdit`s rather than as new text.
///
/// The engine never rewrites a document — it plans. All mutation flows through
/// `TextEdit` (projectRules.md, Data Safety), which is what lets a replace-all
/// land as a single undoable unit.
///
/// ## Range contract
///
/// Every range in the returned `TextEditBatch` is measured against the snapshot
/// that was searched — the document state *before* the batch — exactly as
/// `TextEditBatch` specifies. `TextStorageBuffer` applies the edits back-to-front,
/// so earlier ranges stay valid as later ones are spliced. Because matches never
/// overlap and arrive in ascending order, the batch is always safe to apply.
extension FindEngine {

    /// One batch replacing every match of `query` with `replacement`.
    ///
    /// ## Replacement semantics
    ///
    /// - **`.literal` queries** take `replacement` verbatim. A `$1` in the
    ///   replacement stays the two characters `$1`; nothing is expanded.
    /// - **`.regex` queries** treat `replacement` as an ICU template, so `$0` is
    ///   the whole match and `$1`… are capture groups. To insert a literal `$`,
    ///   pass `NSRegularExpression.escapedTemplate(for:)` output.
    ///
    /// An empty pattern produces an empty batch. Zero-width matches produce
    /// insertions.
    ///
    /// - Returns: A batch whose edits are ascending and non-overlapping. Empty
    ///   when there is nothing to replace.
    /// - Throws: `EditorError.invalidPattern` when a `.regex` pattern does not
    ///   compile.
    public static func replacePlan(
        for query: FindQuery,
        replacement: String,
        in snapshot: String
    ) throws -> TextEditBatch {
        let found = try rawMatches(of: query, in: snapshot)
        let edits = found.map { match in
            TextEdit(
                replacementRange: match.range,
                text: replacementText(for: match, replacement: replacement, in: snapshot)
            )
        }
        assert(
            isAscendingNonOverlapping(edits.map(\.replacementRange)),
            "replacePlan produced overlapping or unsorted ranges — the batch contract requires pre-batch, non-overlapping ranges"
        )
        return TextEditBatch(edits: edits)
    }

    /// A single edit replacing the first match at or after `offset` — the
    /// replace-then-find-next primitive.
    ///
    /// Match selection matches `nextMatch(of:in:after:wrapping:)` exactly: a caret
    /// inside a match skips that match, and `offset` is clamped to the snapshot.
    /// Replacement templating follows `replacePlan(for:replacement:in:)`.
    ///
    /// - Returns: `nil` when nothing is left to replace.
    /// - Throws: `EditorError.invalidPattern` when a `.regex` pattern does not
    ///   compile.
    public static func replaceNext(
        of query: FindQuery,
        replacement: String,
        in snapshot: String,
        after offset: Int,
        wrapping: Bool
    ) throws -> TextEdit? {
        // Reuse `nextMatch`'s progress semantics so replace-then-find-next shares
        // one contract with find-next: a zero-width match exactly at the cursor
        // is skipped and a past-the-end offset finds nothing, rather than
        // clamping back onto a trailing zero-width match (pen-suite finding — a
        // repeated replaceNext loop would otherwise never terminate).
        guard let range = try nextMatch(of: query, in: snapshot, after: offset, wrapping: wrapping) else {
            return nil
        }
        // Recover the ICU result for `$1` template expansion by locating the
        // match `nextMatch` selected within the raw match list.
        let found = try rawMatches(of: query, in: snapshot)
        guard let match = found.first(where: { $0.range == range }) else { return nil }
        return TextEdit(
            replacementRange: match.range,
            text: replacementText(for: match, replacement: replacement, in: snapshot)
        )
    }

    /// Verbatim for literal queries; ICU template expansion for regex queries.
    private static func replacementText(
        for match: RawMatch,
        replacement: String,
        in snapshot: String
    ) -> String {
        guard let result = match.regexResult, let regex = result.regularExpression else {
            return replacement
        }
        return regex.replacementString(for: result, in: snapshot, offset: 0, template: replacement)
    }
}
