import Foundation
import Testing
@testable import GlassEditorCore

// MARK: - Helpers

/// Applies a batch the way `TextStorageBuffer` must: ranges are against the
/// pre-batch snapshot, spliced back-to-front so earlier ranges stay valid.
/// `NSMutableString` is used deliberately — it splices in UTF-16 code units,
/// which is the coordinate system `TextEdit` publishes.
private func applying(_ batch: TextEditBatch, to snapshot: String) -> String {
    let buffer = NSMutableString(string: snapshot)
    for edit in batch.edits.sorted(by: { $0.replacementRange.lowerBound > $1.replacementRange.lowerBound }) {
        buffer.replaceCharacters(
            in: NSRange(location: edit.replacementRange.lowerBound, length: edit.replacementRange.count),
            with: edit.text
        )
    }
    return buffer as String
}

/// The snapshot text a UTF-16 range covers — used to prove the offsets the
/// engine publishes address what we think they address.
private func slice(_ snapshot: String, _ range: Range<Int>) -> String {
    let utf16 = snapshot.utf16
    let start = utf16.index(utf16.startIndex, offsetBy: range.lowerBound)
    let end = utf16.index(utf16.startIndex, offsetBy: range.upperBound)
    return String(utf16[start..<end])!
}

private func literal(_ pattern: String, caseSensitive: Bool = false, wholeWord: Bool = false) -> FindQuery {
    FindQuery(pattern: pattern, kind: .literal, caseSensitive: caseSensitive, wholeWord: wholeWord)
}

private func regex(_ pattern: String, caseSensitive: Bool = false, wholeWord: Bool = false) -> FindQuery {
    FindQuery(pattern: pattern, kind: .regex, caseSensitive: caseSensitive, wholeWord: wholeWord)
}

// MARK: - Literal search

@Suite("Find — literal matching")
struct FindLiteralTests {

    @Test("Case-insensitive literal search applies full Unicode case folding")
    func fullCaseFolding() throws {
        let snapshot = "Die Straße ist breit"
        // ß folds to ss, so a 7-unit pattern matches a 6-unit span. The returned
        // range — not the pattern's length — is what addresses the document.
        let hits = try FindEngine.matches(of: literal("STRASSE"), in: snapshot)
        #expect(hits == [4..<10])
        #expect(slice(snapshot, 4..<10) == "Straße")
        #expect(try FindEngine.matches(of: literal("STRAẞE"), in: snapshot) == [4..<10])
    }

    @Test("Case-sensitive literal search does not fold")
    func caseSensitiveDoesNotFold() throws {
        let snapshot = "Die Straße ist breit"
        #expect(try FindEngine.matches(of: literal("STRASSE", caseSensitive: true), in: snapshot).isEmpty)
        #expect(try FindEngine.matches(of: literal("Straße", caseSensitive: true), in: snapshot) == [4..<10])
    }

    @Test("Literal search is canonical-equivalence aware")
    func canonicalEquivalence() throws {
        let snapshot = "cafe\u{301} time"          // decomposed é
        let hits = try FindEngine.matches(of: literal("café"), in: snapshot)  // precomposed é
        #expect(hits == [0..<5])
        #expect(slice(snapshot, 0..<5) == "cafe\u{301}")
    }

    @Test("Case folding is not locale-tailored: dotted İ does not fold to i")
    func noLocaleTailoring() throws {
        #expect(try FindEngine.matches(of: literal("istanbul"), in: "İstanbul").isEmpty)
    }

    @Test("wholeWord rejects matches touching word characters")
    func wholeWordBoundaries() throws {
        let snapshot = "concatenate cat catalog"
        #expect(try FindEngine.matches(of: literal("cat"), in: snapshot) == [3..<6, 12..<15, 16..<19])
        #expect(try FindEngine.matches(of: literal("cat", wholeWord: true), in: snapshot) == [12..<15])
        #expect(slice(snapshot, 12..<15) == "cat")
    }

    @Test("wholeWord: underscore is a word character, emoji and punctuation are not")
    func wholeWordCharacterClass() throws {
        #expect(try FindEngine.matches(of: literal("cat", wholeWord: true), in: "_cat").isEmpty)
        #expect(try FindEngine.matches(of: literal("cat", wholeWord: true), in: "cat9").isEmpty)
        #expect(try FindEngine.matches(of: literal("cat", wholeWord: true), in: "🙂cat🙂") == [2..<5])
        #expect(try FindEngine.matches(of: literal("cat", wholeWord: true), in: "(cat).") == [1..<4])
        #expect(FindEngine.isWordCharacter("é"))
        #expect(FindEngine.isWordCharacter("_"))
        #expect(!FindEngine.isWordCharacter("🙂"))
        #expect(!FindEngine.isWordCharacter("-"))
    }

    @Test("Matches span and address CRLF as two UTF-16 units")
    func crlf() throws {
        let snapshot = "line1\r\nline2"
        #expect(try FindEngine.matches(of: literal("1\r\nl"), in: snapshot) == [4..<8])
        #expect(try FindEngine.matches(of: literal("\r\n"), in: snapshot) == [5..<7])
        #expect(try FindEngine.matches(of: literal("\n"), in: snapshot) == [6..<7])
        #expect(slice(snapshot, 4..<8) == "1\r\nl")
    }

    @Test("Emoji in the pattern and around matches")
    func emoji() throws {
        let snapshot = "x🙂y 🙂"
        #expect(try FindEngine.matches(of: literal("🙂"), in: snapshot) == [1..<3, 5..<7])
        #expect(try FindEngine.matches(of: literal("🙂y"), in: snapshot) == [1..<4])
    }

    @Test("Offsets are UTF-16 units, not characters, after astral-plane text")
    func astralOffsets() throws {
        let snapshot = "🙂🙂 needle"
        #expect(snapshot.count == 9)               // characters
        #expect(snapshot.utf16.count == 11)        // code units
        let hits = try FindEngine.matches(of: literal("needle"), in: snapshot)
        #expect(hits == [5..<11])
        #expect(slice(snapshot, 5..<11) == "needle")
    }

    @Test("Literal search never interprets regex metacharacters")
    func literalIsNotRegex() throws {
        let snapshot = "axxb .*"
        #expect(try FindEngine.matches(of: literal(".*"), in: snapshot) == [5..<7])
        #expect(try FindEngine.matches(of: literal("a.b"), in: snapshot).isEmpty)
        #expect(try FindEngine.matches(of: literal("("), in: "f(x)") == [1..<2])
        // The same patterns as regex behave completely differently.
        #expect(try FindEngine.matches(of: regex("a.*b"), in: snapshot) == [0..<4])
        #expect(try FindEngine.matches(of: regex("\\.\\*"), in: snapshot) == [5..<7])
    }

    @Test("Repeating patterns produce non-overlapping ascending matches")
    func nonOverlapping() throws {
        let hits = try FindEngine.matches(of: literal("aa"), in: "aaaaa")
        #expect(hits == [0..<2, 2..<4])
        #expect(FindEngine.isAscendingNonOverlapping(hits))
    }

    @Test("matchCount agrees with matches")
    func matchCount() throws {
        let snapshot = "the cat sat on the cat"
        #expect(try FindEngine.matchCount(of: literal("cat"), in: snapshot) == 2)
        #expect(try FindEngine.matchCount(of: literal("zebra"), in: snapshot) == 0)
    }

    @Test("An empty pattern matches nothing and never throws")
    func emptyPattern() throws {
        let snapshot = "anything at all"
        for query in [literal(""), regex(""), literal("", wholeWord: true), regex("", wholeWord: true)] {
            #expect(try FindEngine.matches(of: query, in: snapshot).isEmpty)
            #expect(try FindEngine.matchCount(of: query, in: snapshot) == 0)
            #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 0, wrapping: true) == nil)
            #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: 5, wrapping: true) == nil)
            #expect(try FindEngine.replacePlan(for: query, replacement: "x", in: snapshot).edits.isEmpty)
        }
    }

    @Test("An empty snapshot yields no matches")
    func emptySnapshot() throws {
        #expect(try FindEngine.matches(of: literal("cat"), in: "").isEmpty)
        #expect(try FindEngine.matches(of: regex("a*"), in: "") == [0..<0])
    }
}

// MARK: - Regex search

@Suite("Find — regex matching")
struct FindRegexTests {

    @Test("Zero-width matches terminate and land at sane offsets")
    func zeroWidthTermination() throws {
        // Each of these would loop forever if scanning resumed at the match end.
        #expect(try FindEngine.matches(of: regex("a*"), in: "abab") == [0..<1, 1..<1, 2..<3, 3..<3, 4..<4])
        #expect(try FindEngine.matches(of: regex("^"), in: "abab") == [0..<0])
        #expect(try FindEngine.matches(of: regex("(?=b)"), in: "abab") == [1..<1, 3..<3])
        #expect(try FindEngine.matches(of: regex("x*"), in: "ab") == [0..<0, 1..<1, 2..<2])

        for pattern in ["a*", "^", "$", "(?=b)", "\\b", "(?:)"] {
            let hits = try FindEngine.matches(of: regex(pattern), in: "abab")
            #expect(FindEngine.isAscendingNonOverlapping(hits), "\(pattern) produced overlapping matches")
            #expect(hits.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= 4 }, "\(pattern) escaped the snapshot")
        }
    }

    @Test("Zero-width matches never split a surrogate pair")
    func zeroWidthAcrossAstralText() throws {
        let snapshot = "🙂🙂"                      // four UTF-16 units, two characters
        let hits = try FindEngine.matches(of: regex("x*"), in: snapshot)
        #expect(hits == [0..<0, 2..<2, 4..<4])
        for hit in hits {
            #expect(slice(snapshot, hit).isEmpty)  // every offset is a valid boundary
        }
    }

    @Test("An uncompilable pattern throws .invalidPattern with the ICU reason")
    func invalidPattern() throws {
        for pattern in ["(", "a{2,1}", "[z-a]", "*"] {
            do {
                _ = try FindEngine.matches(of: regex(pattern), in: "abc")
                Issue.record("\(pattern) should not have compiled")
            } catch let error as EditorError {
                guard case .invalidPattern(let reason) = error else {
                    Issue.record("expected .invalidPattern, got \(error)")
                    continue
                }
                #expect(!reason.isEmpty)
            }
        }
        // Compilation failure surfaces from every entry point, not just matches.
        #expect(throws: EditorError.self) { try FindEngine.matchCount(of: regex("("), in: "abc") }
        #expect(throws: EditorError.self) { try FindEngine.nextMatch(of: regex("("), in: "abc", after: 0, wrapping: false) }
        #expect(throws: EditorError.self) { try FindEngine.previousMatch(of: regex("("), in: "abc", before: 3, wrapping: false) }
        #expect(throws: EditorError.self) { try FindEngine.replacePlan(for: regex("("), replacement: "x", in: "abc") }
        #expect(throws: EditorError.self) { try FindEngine.replaceNext(of: regex("("), replacement: "x", in: "abc", after: 0, wrapping: false) }
        // A literal pattern of the same text is not a pattern at all.
        #expect(try FindEngine.matches(of: literal("("), in: "a(bc") == [1..<2])
    }

    @Test("Regex case sensitivity and Unicode case folding")
    func regexCaseFolding() throws {
        #expect(try FindEngine.matches(of: regex("cat"), in: "CAT cat") == [0..<3, 4..<7])
        #expect(try FindEngine.matches(of: regex("cat", caseSensitive: true), in: "CAT cat") == [4..<7])
        #expect(try FindEngine.matches(of: regex("STRASSE"), in: "Die Straße") == [4..<10])
    }

    @Test("Regex anchors address the whole snapshot unless the pattern opts in")
    func anchorScope() throws {
        let snapshot = "ab\ncd"
        #expect(try FindEngine.matches(of: regex("^"), in: snapshot) == [0..<0])
        #expect(try FindEngine.matches(of: regex("(?m)^"), in: snapshot) == [0..<0, 3..<3])
        #expect(try FindEngine.matches(of: regex("a.c"), in: snapshot).isEmpty)
        #expect(try FindEngine.matches(of: regex("(?s)b.c"), in: snapshot) == [1..<4])
    }

    @Test("wholeWord filters regex matches too")
    func regexWholeWord() throws {
        let snapshot = "concatenate cat catalog"
        #expect(try FindEngine.matches(of: regex("cat", wholeWord: true), in: snapshot) == [12..<15])
        #expect(try FindEngine.matches(of: regex("c\\w+", wholeWord: true), in: snapshot) == [0..<11, 12..<15, 16..<23])
    }

    @Test("Regex offsets are UTF-16 units after astral-plane text")
    func regexAstralOffsets() throws {
        let snapshot = "🙂🙂 needle"
        let hits = try FindEngine.matches(of: regex("n\\w+"), in: snapshot)
        #expect(hits == [5..<11])
        #expect(slice(snapshot, 5..<11) == "needle")
    }
}

// MARK: - Replace planning

@Suite("Find — replace plans")
struct FindReplacePlanTests {

    @Test("Replace-all across multiple matches")
    func multipleMatches() throws {
        let snapshot = "the cat sat on the cat"
        let plan = try FindEngine.replacePlan(for: literal("cat"), replacement: "dog", in: snapshot)
        #expect(plan.edits.map(\.replacementRange) == [4..<7, 19..<22])
        #expect(applying(plan, to: snapshot) == "the dog sat on the dog")
    }

    @Test("Adjacent matches, and matches at the start and end")
    func adjacentAndEdgeMatches() throws {
        let adjacent = try FindEngine.replacePlan(for: literal("aa"), replacement: "b", in: "aaaa")
        #expect(adjacent.edits.map(\.replacementRange) == [0..<2, 2..<4])
        #expect(applying(adjacent, to: "aaaa") == "bb")

        let edges = "cat middle cat"
        let plan = try FindEngine.replacePlan(for: literal("cat"), replacement: "X", in: edges)
        #expect(plan.edits.map(\.replacementRange) == [0..<3, 11..<14])
        #expect(applying(plan, to: edges) == "X middle X")
    }

    @Test("Replacements longer and shorter than the match")
    func lengthChanges() throws {
        let snapshot = "cat and cat"
        let longer = try FindEngine.replacePlan(for: literal("cat"), replacement: "caterpillar", in: snapshot)
        #expect(applying(longer, to: snapshot) == "caterpillar and caterpillar")

        let shorter = try FindEngine.replacePlan(for: literal("cat"), replacement: "c", in: snapshot)
        #expect(applying(shorter, to: snapshot) == "c and c")

        let deletion = try FindEngine.replacePlan(for: literal("cat "), replacement: "", in: snapshot)
        #expect(applying(deletion, to: snapshot) == "and cat")
    }

    @Test("Regex replacement expands capture templates")
    func captureTemplates() throws {
        let snapshot = "John Smith\nJane Doe"
        let plan = try FindEngine.replacePlan(
            for: regex("(\\w+) (\\w+)"),
            replacement: "$2, $1",
            in: snapshot
        )
        #expect(plan.edits.count == 2)
        #expect(applying(plan, to: snapshot) == "Smith, John\nDoe, Jane")

        let whole = try FindEngine.replacePlan(for: regex("\\w+"), replacement: "[$0]", in: "hi there")
        #expect(applying(whole, to: "hi there") == "[hi] [there]")
    }

    @Test("Literal replacement is verbatim — '$1' stays '$1'")
    func literalReplacementIsNotTemplated() throws {
        let snapshot = "price: cat"
        let plan = try FindEngine.replacePlan(for: literal("cat"), replacement: "$1 & $0 \\n", in: snapshot)
        #expect(plan.edits.map(\.text) == ["$1 & $0 \\n"])
        #expect(applying(plan, to: snapshot) == "price: $1 & $0 \\n")
    }

    @Test("A literal '$' in a regex replacement needs escapedTemplate")
    func regexTemplateEscaping() throws {
        let snapshot = "cat"
        let templated = try FindEngine.replacePlan(for: regex("cat"), replacement: "$0!", in: snapshot)
        #expect(applying(templated, to: snapshot) == "cat!")

        let escaped = NSRegularExpression.escapedTemplate(for: "$1 literal")
        let verbatim = try FindEngine.replacePlan(for: regex("cat"), replacement: escaped, in: snapshot)
        #expect(applying(verbatim, to: snapshot) == "$1 literal")
    }

    @Test("Zero-width matches plan as insertions")
    func zeroWidthReplacement() throws {
        let snapshot = "abab"
        let plan = try FindEngine.replacePlan(for: regex("(?=b)"), replacement: "-", in: snapshot)
        #expect(plan.edits.map(\.replacementRange) == [1..<1, 3..<3])
        #expect(plan.edits.allSatisfy { $0.replacementRange.isEmpty })
        #expect(applying(plan, to: snapshot) == "a-ba-b")
    }

    @Test("Planned ranges are pre-batch, ascending, and non-overlapping")
    func batchContract() throws {
        let snapshot = "aa aa aa 🙂 aa"
        let plan = try FindEngine.replacePlan(for: literal("aa"), replacement: "zzzz", in: snapshot)
        let ranges = plan.edits.map(\.replacementRange)
        #expect(FindEngine.isAscendingNonOverlapping(ranges))
        // Pre-batch: every range still addresses the searched text.
        #expect(ranges.allSatisfy { slice(snapshot, $0) == "aa" })
        #expect(applying(plan, to: snapshot) == "zzzz zzzz zzzz 🙂 zzzz")
    }

    @Test("Replacement preserves UTF-16 correctness around astral-plane text")
    func replacementAroundAstralText() throws {
        let snapshot = "🙂 cat 🙂 cat"
        let plan = try FindEngine.replacePlan(for: literal("cat"), replacement: "🐈", in: snapshot)
        #expect(plan.edits.map(\.replacementRange) == [3..<6, 10..<13])
        #expect(applying(plan, to: snapshot) == "🙂 🐈 🙂 🐈")
    }

    @Test("replaceNext plans one edit and honours caret position and wrapping")
    func replaceNextSingleEdit() throws {
        let snapshot = "cat cat cat"
        let first = try FindEngine.replaceNext(of: literal("cat"), replacement: "dog", in: snapshot, after: 0, wrapping: false)
        #expect(first == TextEdit(replacementRange: 0..<3, text: "dog"))

        // Caret inside the first match moves on to the second.
        let inside = try FindEngine.replaceNext(of: literal("cat"), replacement: "dog", in: snapshot, after: 1, wrapping: false)
        #expect(inside?.replacementRange == 4..<7)

        #expect(try FindEngine.replaceNext(of: literal("cat"), replacement: "dog", in: snapshot, after: 9, wrapping: false) == nil)
        #expect(try FindEngine.replaceNext(of: literal("cat"), replacement: "dog", in: snapshot, after: 9, wrapping: true)?.replacementRange == 0..<3)
        #expect(try FindEngine.replaceNext(of: literal("zebra"), replacement: "dog", in: snapshot, after: 0, wrapping: true) == nil)

        // Applying it leaves the other matches untouched.
        let edit = try #require(first)
        #expect(applying(TextEditBatch(edits: [edit]), to: snapshot) == "dog cat cat")
    }

    @Test("replaceNext expands capture templates for regex queries only")
    func replaceNextTemplates() throws {
        let snapshot = "John Smith"
        let regexEdit = try FindEngine.replaceNext(of: regex("(\\w+) (\\w+)"), replacement: "$2, $1", in: snapshot, after: 0, wrapping: false)
        #expect(regexEdit?.text == "Smith, John")

        let literalEdit = try FindEngine.replaceNext(of: literal("John"), replacement: "$1", in: snapshot, after: 0, wrapping: false)
        #expect(literalEdit?.text == "$1")
    }
}

// MARK: - Find next / find previous

@Suite("Find — next and previous")
struct FindNavigationTests {
    private let snapshot = "cat cat cat"   // matches at 0..<3, 4..<7, 8..<11

    @Test("nextMatch walks forward from the caret")
    func nextForward() throws {
        let query = literal("cat")
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 0, wrapping: false) == 0..<3)
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 3, wrapping: false) == 4..<7)
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 4, wrapping: false) == 4..<7)
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 8, wrapping: false) == 8..<11)
    }

    @Test("A caret inside a match skips that match")
    func caretInsideMatch() throws {
        let query = literal("cat")
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 1, wrapping: false) == 4..<7)
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 5, wrapping: false) == 8..<11)
        #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: 9, wrapping: false) == 4..<7)
        #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: 5, wrapping: false) == 0..<3)
    }

    @Test("nextMatch wraps only when asked")
    func nextWrapping() throws {
        let query = literal("cat")
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 9, wrapping: false) == nil)
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 9, wrapping: true) == 0..<3)
        #expect(try FindEngine.nextMatch(of: literal("zebra"), in: snapshot, after: 0, wrapping: true) == nil)
    }

    @Test("previousMatch walks backward and wraps only when asked")
    func previousBackward() throws {
        let query = literal("cat")
        #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: 11, wrapping: false) == 8..<11)
        #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: 7, wrapping: false) == 4..<7)
        #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: 3, wrapping: false) == 0..<3)
        #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: 0, wrapping: false) == nil)
        #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: 0, wrapping: true) == 8..<11)
        #expect(try FindEngine.previousMatch(of: literal("zebra"), in: snapshot, before: 11, wrapping: true) == nil)
    }

    @Test("Out-of-bounds carets are clamped, not trapped")
    func clampedOffsets() throws {
        let query = literal("cat")
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: -100, wrapping: false) == 0..<3)
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 9_999, wrapping: false) == nil)
        #expect(try FindEngine.nextMatch(of: query, in: snapshot, after: 9_999, wrapping: true) == 0..<3)
        #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: 9_999, wrapping: false) == 8..<11)
        #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: -100, wrapping: false) == nil)
        #expect(try FindEngine.previousMatch(of: query, in: snapshot, before: -100, wrapping: true) == 8..<11)
    }

    @Test("Navigation honours regex and wholeWord queries")
    func navigationWithOtherKinds() throws {
        let text = "concatenate cat catalog cat"
        #expect(try FindEngine.nextMatch(of: literal("cat", wholeWord: true), in: text, after: 0, wrapping: false) == 12..<15)
        #expect(try FindEngine.previousMatch(of: literal("cat", wholeWord: true), in: text, before: 27, wrapping: false) == 24..<27)
        #expect(try FindEngine.nextMatch(of: regex("c\\w+g"), in: text, after: 0, wrapping: false) == 16..<23)
    }
}

// MARK: - Query value semantics

@Suite("Find — query value semantics")
struct FindQueryTests {
    @Test("FindQuery is a Hashable, Codable value with literal defaults")
    func queryValue() throws {
        let query = FindQuery(pattern: "cat")
        #expect(query.kind == .literal)
        #expect(query.caseSensitive == false)
        #expect(query.wholeWord == false)
        #expect(query.isEmpty == false)
        #expect(FindQuery(pattern: "").isEmpty)

        var other = query
        other.wholeWord = true
        #expect(query != other)

        let round = try JSONDecoder().decode(FindQuery.self, from: JSONEncoder().encode(other))
        #expect(round == other)
    }
}
