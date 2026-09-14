import Foundation

/// Stateless find over an immutable text snapshot
/// (projectRules.md, Naming — stateless services are enums of static funcs).
///
/// Every range this type produces is in **UTF-16 code units**, consistent with
/// `TextEdit.replacementRange` and `HighlightRun`, so a match can be handed
/// straight to storage or to a text view without a coordinate conversion.
///
/// ## Guarantees
///
/// - Results are sorted ascending by lower bound and never overlap: after a
///   match, scanning resumes at its end.
/// - A zero-width regex match (`a*`, `^`, `(?=b)`) is reported once and scanning
///   advances at least one composed character past it, so no pattern can loop.
/// - An empty pattern yields no matches. It never throws.
/// - The engine holds no state: two calls with the same query and snapshot
///   return the same ranges.
///
/// ## Known limitation: regex is synchronous and unbounded (M5)
///
/// `.regex` queries are handed to `NSRegularExpression`, which offers no step
/// budget, no timeout, and no cancellation. A pathological user-supplied pattern
/// (`(a+)+$`, `(a|aa)+$`) backtracks exponentially and blocks the calling thread
/// until it finishes — and NSRegularExpression cannot be interrupted mid-match,
/// so no in-place guard can stop it. The exposure is a self-inflicted local hang
/// (the user's own find field, on the user's own file), not attacker-reachable
/// input, so it is accepted for v1 and recorded rather than hidden
/// (`FuzzPenTests.catastrophicBacktrackingSurface`, `progress.md` M5). The
/// proper fix is an async, off-main-actor find the UI can abandon; that is an
/// architecture change deferred to M5, not a repair that belongs here. Callers
/// running untrusted patterns on the main actor should treat this as a live
/// constraint.
public enum FindEngine: Sendable {

    // MARK: - Matching

    /// All matches of `query` in `snapshot`, as UTF-16 code-unit ranges.
    ///
    /// ## Case folding
    ///
    /// The two kinds fold case through different Foundation engines, and the
    /// difference is observable:
    ///
    /// - **`.literal`** uses `NSString.range(of:options:range:)` with
    ///   `.caseInsensitive`. That is a full Unicode comparison: it applies *full*
    ///   case folding and canonical equivalence, so `STRASSE` matches `Straße`
    ///   and `café` matches `cafe` + U+0301. Because of this, a matched range's
    ///   UTF-16 length may differ from the pattern's — always use the returned
    ///   range, never `pattern.utf16.count`. Locale-specific casing is *not*
    ///   applied: `istanbul` does not match `İstanbul`.
    /// - **`.regex`** uses ICU's case-insensitive matching, which also applies
    ///   full case folding (`STRASSE` matches `Straße`) but does **not** apply
    ///   canonical equivalence — a precomposed `é` in the pattern will not match
    ///   a decomposed `é` in the text.
    ///
    /// ## Regex dialect
    ///
    /// Patterns compile with `NSRegularExpression`'s defaults plus
    /// `.caseInsensitive` when `query.caseSensitive` is `false`. Notably `^` and
    /// `$` anchor to the whole snapshot rather than to each line, and `.` does
    /// not match a line separator. A pattern may opt in inline — `(?m)`, `(?s)`.
    ///
    /// - Throws: `EditorError.invalidPattern` when `query.kind == .regex` and the
    ///   pattern does not compile. The underlying ICU reason is carried through.
    public static func matches(of query: FindQuery, in snapshot: String) throws -> [Range<Int>] {
        try rawMatches(of: query, in: snapshot).map(\.range)
    }

    /// How many times `query` occurs in `snapshot`.
    ///
    /// - Throws: `EditorError.invalidPattern`, as `matches(of:in:)` does.
    public static func matchCount(of query: FindQuery, in snapshot: String) throws -> Int {
        try matches(of: query, in: snapshot).count
    }

    /// The next match a find-next should select from `offset` — the find-next
    /// primitive, defined to make **forward progress**.
    ///
    /// "Progress" is what a repeated find-next walk needs to terminate. A match is
    /// eligible when it starts strictly after `offset`, or starts exactly at
    /// `offset` and is non-empty (a real match under the caret is selected). A
    /// **zero-width match sitting exactly at `offset` is skipped** — the caret is
    /// already there, and returning it would make a walk that advances by
    /// `hit.upperBound` a fixed point that spins forever on `a*`, `x?`, `$`, or
    /// any pattern that can match empty (pen-suite finding). A non-empty match is
    /// never skipped.
    ///
    /// - Parameters:
    ///   - offset: A UTF-16 offset. A negative offset is treated as the start; an
    ///     offset at or past the end has nothing after it and returns `nil`
    ///     (or wraps), rather than being clamped back onto a trailing match.
    ///   - wrapping: When `true` and nothing follows `offset`, returns the first
    ///     match in the snapshot instead of `nil`.
    /// - Returns: `nil` when there is no eligible match (and, if `wrapping`, no
    ///   match anywhere).
    /// - Throws: `EditorError.invalidPattern`, as `matches(of:in:)` does.
    public static func nextMatch(
        of query: FindQuery,
        in snapshot: String,
        after offset: Int,
        wrapping: Bool
    ) throws -> Range<Int>? {
        let all = try matches(of: query, in: snapshot)
        let start = max(offset, 0)
        if let hit = all.first(where: { m in
            m.lowerBound > start || (m.lowerBound == start && m.upperBound > start)
        }) {
            return hit
        }
        return wrapping ? all.first : nil
    }

    /// The previous match a find-previous should select from `offset` — the
    /// find-previous primitive, defined to make **backward progress**.
    ///
    /// Symmetric to ``nextMatch(of:in:after:wrapping:)``. A match is eligible when
    /// it ends strictly before `offset`, or ends exactly at `offset` and is
    /// non-empty. A zero-width match sitting exactly at `offset` is skipped so a
    /// walk terminates, and — the other half of the same pen-suite finding — a
    /// non-empty match is never skipped merely because a zero-width neighbour
    /// shares its upper bound.
    ///
    /// - Parameters:
    ///   - offset: A UTF-16 offset. An offset past the end is treated as the end;
    ///     an offset at or before `0` has nothing before it and returns `nil`
    ///     (or wraps).
    ///   - wrapping: When `true` and nothing precedes `offset`, returns the last
    ///     match in the snapshot instead of `nil`.
    /// - Returns: `nil` when there is no eligible match (and, if `wrapping`, no
    ///   match anywhere).
    /// - Throws: `EditorError.invalidPattern`, as `matches(of:in:)` does.
    public static func previousMatch(
        of query: FindQuery,
        in snapshot: String,
        before offset: Int,
        wrapping: Bool
    ) throws -> Range<Int>? {
        let all = try matches(of: query, in: snapshot)
        let end = min(offset, snapshot.utf16.count)
        if let hit = all.last(where: { m in
            m.upperBound < end || (m.upperBound == end && m.lowerBound < end)
        }) {
            return hit
        }
        return wrapping ? all.last : nil
    }

    // MARK: - Word boundaries

    /// The word-character predicate behind `FindQuery.wholeWord`.
    ///
    /// A character is a word character when it is a Unicode letter, a Unicode
    /// number, or `_`. Everything else — whitespace, punctuation, symbols, emoji
    /// — is a boundary. `cat` is therefore not a whole-word match inside
    /// `concatenate` or `cat_alog`, but is one inside `🙂cat🙂`.
    ///
    /// Adjacency is measured in composed character sequences, so a combining mark
    /// is judged as part of the base character it attaches to.
    public static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    // MARK: - Internals

    /// A match plus, for `.regex` queries, the ICU result that produced it.
    /// `ReplacePlan` needs the result to expand `$1`-style templates.
    struct RawMatch {
        var range: Range<Int>
        var regexResult: NSTextCheckingResult?
    }

    static func rawMatches(of query: FindQuery, in snapshot: String) throws -> [RawMatch] {
        guard !query.isEmpty else { return [] }
        let text = snapshot as NSString

        let candidates: [RawMatch]
        switch query.kind {
        case .literal:
            candidates = literalMatches(of: query, in: text).map {
                RawMatch(range: $0.lowerBound..<$0.upperBound, regexResult: nil)
            }
        case .regex:
            let regex = try compiledRegex(for: query)
            let whole = NSRange(location: 0, length: text.length)
            candidates = regex.matches(in: snapshot, options: [], range: whole).map {
                RawMatch(range: $0.range.lowerBound..<$0.range.upperBound, regexResult: $0)
            }
        }

        let kept = query.wholeWord
            ? candidates.filter { isWholeWord($0.range, in: text) }
            : candidates

        assert(isAscendingNonOverlapping(kept.map(\.range)), "FindEngine produced overlapping or unsorted matches")
        return kept
    }

    /// Compiles `query.pattern`, translating ICU's failure into `EditorError`.
    static func compiledRegex(for query: FindQuery) throws -> NSRegularExpression {
        var options: NSRegularExpression.Options = []
        if !query.caseSensitive { options.insert(.caseInsensitive) }
        do {
            return try NSRegularExpression(pattern: query.pattern, options: options)
        } catch {
            throw EditorError.invalidPattern(reason: (error as NSError).localizedDescription)
        }
    }

    /// Verbatim scan. `NSString` search is UTF-16 based, so offsets come back in
    /// the coordinate system we publish, and CRLF is two searchable units rather
    /// than one opaque grapheme.
    private static func literalMatches(of query: FindQuery, in text: NSString) -> [NSRange] {
        var options: NSString.CompareOptions = []
        if !query.caseSensitive { options.insert(.caseInsensitive) }

        var found: [NSRange] = []
        var scan = 0
        while scan <= text.length {
            let window = NSRange(location: scan, length: text.length - scan)
            let hit = text.range(of: query.pattern, options: options, range: window)
            guard hit.location != NSNotFound else { break }
            found.append(hit)
            // A non-empty match resumes at its end; a (pathological) empty one
            // resumes past the next composed character, so the loop terminates.
            scan = hit.length > 0 ? hit.upperBound : scanLocation(past: hit.location, in: text)
        }
        return found
    }

    /// The next scan position after a zero-width match — always strictly greater,
    /// and never inside a surrogate pair or a composed character sequence.
    private static func scanLocation(past location: Int, in text: NSString) -> Int {
        guard location < text.length else { return location + 1 }
        let sequence = text.rangeOfComposedCharacterSequence(at: location)
        return max(location + 1, sequence.upperBound)
    }

    /// `wholeWord` filter: neither neighbouring character may be a word character.
    private static func isWholeWord(_ range: Range<Int>, in text: NSString) -> Bool {
        !isWordCharacter(before: range.lowerBound, in: text)
            && !isWordCharacter(at: range.upperBound, in: text)
    }

    private static func isWordCharacter(before location: Int, in text: NSString) -> Bool {
        guard location > 0 else { return false }
        let sequence = text.rangeOfComposedCharacterSequence(at: location - 1)
        return isWordCharacter(firstCharacterOf: text.substring(with: sequence))
    }

    private static func isWordCharacter(at location: Int, in text: NSString) -> Bool {
        guard location < text.length else { return false }
        let sequence = text.rangeOfComposedCharacterSequence(at: location)
        return isWordCharacter(firstCharacterOf: text.substring(with: sequence))
    }

    private static func isWordCharacter(firstCharacterOf fragment: String) -> Bool {
        guard let character = fragment.first else { return false }
        return isWordCharacter(character)
    }

    private static func clamp(_ offset: Int, toLengthOf snapshot: String) -> Int {
        min(max(offset, 0), snapshot.utf16.count)
    }

    static func isAscendingNonOverlapping(_ ranges: [Range<Int>]) -> Bool {
        var previousEnd = Int.min
        for range in ranges {
            guard range.lowerBound >= previousEnd else { return false }
            previousEnd = range.upperBound
        }
        return true
    }
}
