import Foundation
import SwiftTreeSitter
import Testing

@testable import GlassEditorCore

/// End-to-end coverage of `GrammarRegistry` + `DocumentParser`: every vendored
/// language produces the roles a consumer would expect, offsets are UTF-16 even
/// when the document is not BMP-only, and the incremental path is byte-identical
/// to a full reparse.
@Suite("Grammar module")
@MainActor
struct GrammarModuleTests {

    // MARK: - Fixtures

    static let sql = """
    -- customers with recent orders
    SELECT u.id, count(*) AS n
    FROM users AS u
    JOIN orders o ON o.user_id = u.id
    WHERE u.created_at > '2026-01-01' AND u.age >= 42
    GROUP BY u.id
    ORDER BY n DESC
    LIMIT 10;
    """

    static let json = #"""
    {
      "name": "glass",
      "version": 1,
      "tags": ["a", "b"],
      "ok": true,
      "none": null
    }
    """#

    static let bash = """
    #!/usr/bin/env bash
    # tidy up
    set -euo pipefail
    for f in "$@"; do
      if [ -f "$f" ]; then
        printf '%s\\n' "$(basename "$f")"
      fi
    done
    """

    static let yaml = """
    # compose
    version: 2
    services:
      db:
        image: postgres:16
        ports:
          - "5432:5432"
        enabled: true
    """

    static let toml = """
    # config
    title = "glass"

    [owner]
    name = "Glass Family"
    ports = [8000, 8001]
    enabled = true
    """

    static let markdown = """
    # Heading

    Some text with a [link][ref].

    [ref]: https://example.com

    - item one
    - item two

    ```swift
    let x = 1
    ```
    """

    static let python = """
    # greet
    def greet(name: str) -> str:
        count = 1
        return f"hello {name}"
    """

    static let javascript = """
    // greet
    const count = 1;
    function greet(name) {
        return `hello ${name}`;
    }
    """

    static let go = """
    // greet
    package main

    import "fmt"

    func greet(name string) string {
        count := 1
        return fmt.Sprintf("hello %s %d", name, count)
    }
    """

    static let rust = """
    // greet
    fn greet(name: &str) -> String {
        let count: u32 = 1;
        format!("hello {name} {count}")
    }
    """

    static let c = """
    // greet
    #include <stdio.h>

    int greet(const char *name) {
        int count = 1;
        printf("hello %s %d", name, count);
        return 0;
    }
    """

    static let php = """
    <?php
    // greet
    function greet(string $name): string {
        $count = 1;
        return "hello $name $count";
    }
    """

    static let swiftSource = """
    // greet
    import Foundation

    struct Greeter {
        let count = 1
        func greet(_ name: String) -> String {
            "hello \\(name) \\(count)"
        }
    }
    """

    static let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!-- greet -->
    <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>Glass Power Tools</string>
        </dict>
    </plist>
    """

    /// Added 2026-09-19. A page with the four things a reader needs apart: element names,
    /// attributes with quoted values, a comment, and a script whose contents are not prose.
    static let html = """
    <!DOCTYPE html>
    <!-- a page -->
    <html lang="en">
      <head><title>Glass</title></head>
      <body class="page">
        <a href="https://example.com">A link</a>
        <script>const answer = 42;</script>
      </body>
    </html>
    """

    static func snippet(for language: LanguageID) -> String {
        switch language {
        case .sql: return sql
        case .json: return json
        case .bash: return bash
        case .yaml: return yaml
        case .toml: return toml
        case .markdown: return markdown
        case .python: return python
        case .javascript: return javascript
        case .go: return go
        case .rust: return rust
        case .c: return c
        case .php: return php
        case .swift: return swiftSource
        case .xml: return xml
        case .html: return html
        case .plaintext: return "just words\nno grammar here"
        }
    }

    /// Roles each language's fixture must produce. Deliberately a subset — the
    /// point is that the pipeline delivers the semantics a theme keys on, not that
    /// the exact role set is frozen.
    static func requiredRoles(for language: LanguageID) -> Set<TokenRole> {
        switch language {
        // The SQL ten, as far as one statement can exercise them (D-008).
        case .sql: return [.keyword, .function, .string, .number, .comment, .identifier, .operator, .punctuation]
        case .json: return [.string, .number, .property, .constant]
        case .bash: return [.keyword, .string, .comment, .function]
        case .yaml: return [.comment, .property, .string, .number, .boolean, .punctuation]
        case .toml: return [.comment, .property, .string, .number, .boolean, .operator, .punctuation]
        case .markdown: return [.markupHeading, .markupCode, .markupLink, .punctuation]
        // The five added 2026-09-16. Each fixture is written to exercise the roles a theme
        // actually keys on — a query that compiles and colours nothing is the failure being
        // guarded against, and "it parsed" would not catch it.
        case .python: return [.keyword, .function, .string, .comment, .number]
        case .javascript: return [.keyword, .function, .string, .comment, .number]
        case .go: return [.keyword, .function, .string, .comment, .number]
        // Rust's upstream query paints integer, float *and* boolean literals alike as
        // `@constant.builtin` (rust-highlights.scm:150-152), so there is no `.number` to require.
        // Overriding the capture to `.number` would colour `true` as a number, which is worse than
        // colouring `1` as a constant.
        case .rust: return [.keyword, .function, .string, .comment, .constant]
        case .c: return [.keyword, .function, .string, .comment, .number]
        case .php: return [.keyword, .function, .string, .comment, .number]
        // Added 2026-09-17. Swift is the language this project is written in; XML is every plist,
        // scheme and entitlements file on the platform.
        case .swift: return [.keyword, .function, .string, .comment, .type]
        // An element name is the closest thing markup has to a keyword, an attribute name is a
        // property, and the value is a string — the three a reader actually needs apart.
        case .xml: return [.keyword, .property, .string, .comment]
        // The same three as XML, plus the embedded run that keeps `<script>` from reading as
        // paragraph text.
        case .html: return [.keyword, .attribute, .string, .comment, .embedded]
        case .plaintext: return [.plain]
        }
    }

    static func text(_ run: HighlightRun, in utf16: [UInt16]) -> String {
        String(decoding: utf16[run.range], as: UTF16.self)
    }

    // MARK: - Per-language highlighting

    @Test("Every language highlights its fixture", arguments: LanguageID.allCases)
    func languageHighlightsFixture(_ language: LanguageID) throws {
        let parser = try DocumentParser(language: language, registry: GrammarRegistry())
        let source = Self.snippet(for: language)
        parser.parseFull(source)

        #expect(!parser.highlights.isEmpty, "\(language.rawValue): produced no highlight runs")

        let produced = Set(parser.highlights.map(\.role))
        let missing = Self.requiredRoles(for: language).subtracting(produced)
        #expect(missing.isEmpty, "\(language.rawValue): missing roles \(missing.map(\.rawValue).sorted())")

        // No run may carry .error on a well-formed fixture.
        #expect(!produced.contains(.error), "\(language.rawValue): well-formed fixture produced .error runs")
    }

    /// The output contract: sorted, non-overlapping, contiguous, total.
    @Test("Highlight runs tile the document exactly", arguments: LanguageID.allCases)
    func runsTileTheDocument(_ language: LanguageID) throws {
        let parser = try DocumentParser(language: language, registry: GrammarRegistry())
        let source = Self.snippet(for: language)
        parser.parseFull(source)

        var expectedStart = 0
        for run in parser.highlights {
            #expect(run.range.lowerBound == expectedStart, "\(language.rawValue): gap or overlap at \(run.range)")
            #expect(!run.range.isEmpty, "\(language.rawValue): empty run at \(run.range)")
            expectedStart = run.range.upperBound
        }
        #expect(expectedStart == source.utf16.count, "\(language.rawValue): runs do not reach the end of the document")

        // Adjacent runs are coalesced — no two neighbours share a role.
        for (previous, next) in zip(parser.highlights, parser.highlights.dropFirst()) {
            #expect(previous.role != next.role, "\(language.rawValue): uncoalesced runs at \(next.range)")
        }
    }

    /// D-008 in a parsed document rather than in the mapping table: the SQL ten
    /// land on the tokens a consumer would name.
    @Test("SQL roles land on the expected tokens")
    func sqlRoleFidelity() throws {
        let parser = try DocumentParser(language: .sql, registry: GrammarRegistry())
        parser.parseFull(Self.sql)
        let utf16 = Array(Self.sql.utf16)

        func role(ofFirst token: String) throws -> TokenRole {
            let offset = try #require(Self.utf16Offset(of: token, in: Self.sql), "\(token) not in the fixture")
            let run = try #require(parser.highlights.first { $0.range.contains(offset) })
            return run.role
        }

        #expect(try role(ofFirst: "SELECT") == .keyword)
        #expect(try role(ofFirst: "count") == .function)
        #expect(try role(ofFirst: "'2026-01-01'") == .string)
        #expect(try role(ofFirst: "42") == .number)
        #expect(try role(ofFirst: "-- customers") == .comment)
        #expect(try role(ofFirst: "created_at") == .identifier)
        #expect(try role(ofFirst: ">=") == .operator)
        #expect(try role(ofFirst: ";") == .punctuation)

        // The whole quoted literal is one string run, not split by the dashes.
        let literalRun = try #require(parser.highlights.first { Self.text($0, in: utf16) == "'2026-01-01'" })
        #expect(literalRun.role == .string)
    }

    /// The failure this guards against is specific: `(literal) @string` matches
    /// numeric literals too, and only the Lua-translated `#match?` predicate keeps
    /// `42` from being highlighted as a string.
    @Test("SQL numeric literals are numbers, quoted literals are strings")
    func sqlNumbersSurvivePredicates() throws {
        let source = "SELECT 42, 3.14, '42' FROM t;"
        let parser = try DocumentParser(language: .sql, registry: GrammarRegistry())
        parser.parseFull(source)
        let utf16 = Array(source.utf16)

        func role(of token: String) throws -> TokenRole {
            try #require(parser.highlights.first { Self.text($0, in: utf16) == token }).role
        }

        #expect(try role(of: "42") == .number)
        #expect(try role(of: "3.14") == .number)
        #expect(try role(of: "'42'") == .string)
    }

    // MARK: - UTF-16 correctness

    /// Tree-sitter reports byte offsets against a UTF-16LE parse. Anything that
    /// mixes units breaks the moment a document contains astral-plane characters,
    /// where one Character is two UTF-16 code units.
    @Test("Run offsets are UTF-16 code units, not characters or bytes")
    func utf16OffsetsSurviveAstralCharacters() throws {
        // Two emoji (surrogate pairs) and a combining sequence before the token.
        let prefix = "-- 🧊🪟 café\n"
        let source = prefix + "SELECT 'needle' FROM t;"

        let parser = try DocumentParser(language: .sql, registry: GrammarRegistry())
        parser.parseFull(source)
        let utf16 = Array(source.utf16)

        // Character count and UTF-16 count genuinely disagree, or this proves nothing.
        #expect(source.count != source.utf16.count, "fixture is BMP-only — the test would be vacuous")

        let run = try #require(
            parser.highlights.first { $0.role == .string },
            "no string run found"
        )
        #expect(Self.text(run, in: utf16) == "'needle'")

        // The slice is exact: the expected UTF-16 offsets, computed independently.
        let expectedLower = prefix.utf16.count + "SELECT ".utf16.count
        #expect(run.range == expectedLower..<(expectedLower + "'needle'".utf16.count))

        // And the keyword before the emoji-bearing comment is still correctly placed.
        let keyword = try #require(parser.highlights.first { Self.text($0, in: utf16) == "SELECT" })
        #expect(keyword.role == .keyword)
        #expect(keyword.range.lowerBound == prefix.utf16.count)
    }

    @Test("Astral characters survive an incremental edit")
    func utf16OffsetsSurviveIncrementalEdit() throws {
        var source = "{\"k\": \"v\"}"
        let parser = try DocumentParser(language: .json, registry: GrammarRegistry())
        parser.parseFull(source)

        // Insert an emoji inside the value, then check the run still slices cleanly.
        let insertion = "🧊"
        let offset = try #require(Self.utf16Offset(of: "v", in: source))
        let edit = TextEdit.insert(insertion, at: offset)
        source = "{\"k\": \"\(insertion)v\"}"
        parser.apply(edit, newSnapshot: source)

        let utf16 = Array(source.utf16)
        let value = try #require(parser.highlights.first { Self.text($0, in: utf16) == "\"\(insertion)v\"" })
        #expect(value.role == .string)

        let reference = try DocumentParser(language: .json, registry: GrammarRegistry())
        reference.parseFull(source)
        #expect(parser.highlights == reference.highlights)
    }

    // MARK: - Incremental parsing

    /// The M2 exit criterion in miniature: after any sequence of edits, the
    /// incrementally maintained tree must highlight identically to a tree parsed
    /// from the same text with no history.
    @Test(
        "Incremental highlighting equals a full reparse over random edits",
        arguments: [LanguageID.sql, .json, .bash]
    )
    func incrementalEqualsFull(_ language: LanguageID) throws {
        let seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        var rng = SeededGenerator(seed: seed)

        let registry = GrammarRegistry()
        let incremental = try DocumentParser(language: language, registry: registry)

        var source = Self.snippet(for: language)
        incremental.parseFull(source)

        let alphabet = Array("aZ0 \n(){}[]\"',;.:=*-_$#/|&<>\t")
        var incrementalParses = 0

        for step in 0..<50 {
            let length = source.utf16.count
            let insert = length == 0 || Bool.random(using: &rng)

            let edit: TextEdit
            if insert {
                let offset = Int.random(in: 0...length, using: &rng)
                let character = String(alphabet.randomElement(using: &rng)!)
                edit = TextEdit.insert(character, at: offset)
            } else {
                let offset = Int.random(in: 0..<length, using: &rng)
                edit = TextEdit.delete(offset..<(offset + 1))
            }

            source = Self.applying(edit, to: source)
            incremental.apply(edit, newSnapshot: source)
            if incremental.lastParseWasIncremental { incrementalParses += 1 }

            let reference = try DocumentParser(language: language, registry: registry)
            reference.parseFull(source)

            #expect(
                incremental.highlights == reference.highlights,
                """
                \(language.rawValue): incremental and full highlights diverged at step \(step). \
                Seed \(String(seed, radix: 16)). Edit \(edit).
                """
            )
        }

        // The equivalence above would also hold if `apply` silently fell back to a
        // full reparse every time, so assert the incremental path was really taken.
        #expect(incrementalParses == 50, "\(language.rawValue): only \(incrementalParses)/50 edits parsed incrementally")
    }

    /// Evidence that tree reuse is real: tree-sitter reports a local changed range,
    /// not the whole document.
    @Test("An interior edit changes only a local range of the tree")
    func incrementalReuseIsLocal() throws {
        let parser = try DocumentParser(language: .sql, registry: GrammarRegistry())

        // A document long enough that "the whole thing changed" is obviously wrong.
        let body = Array(repeating: "SELECT a FROM t WHERE a = 1;", count: 60).joined(separator: "\n")
        parser.parseFull(body)
        #expect(!parser.lastParseWasIncremental)
        #expect(parser.lastChangedRanges.isEmpty)

        let offset = body.utf16.count / 2
        let edit = TextEdit.insert(" ", at: offset)
        parser.apply(edit, newSnapshot: Self.applying(edit, to: body))

        #expect(parser.lastParseWasIncremental)
        let changed = parser.lastChangedRanges.reduce(0) { $0 + $1.count }
        #expect(
            changed < body.utf16.count / 4,
            "changed \(changed) of \(body.utf16.count) UTF-16 units — the tree was not reused"
        )
    }

    @Test("Multi-line edits keep tree-sitter Points consistent")
    func multiLineEditsKeepPointsConsistent() throws {
        let registry = GrammarRegistry()
        let parser = try DocumentParser(language: .yaml, registry: registry)

        var source = Self.yaml
        parser.parseFull(source)

        let edits: [TextEdit] = [
            // Insert two whole lines near the top.
            .insert("extra: 1\nmore: 2\n", at: 0),
            // Delete across a line boundary.
            .delete(9..<20),
            // Replace a run of text with text containing newlines.
            TextEdit(replacementRange: 4..<12, text: "a\nb\nc"),
        ]

        for (index, edit) in edits.enumerated() {
            source = Self.applying(edit, to: source)
            parser.apply(edit, newSnapshot: source)

            let reference = try DocumentParser(language: .yaml, registry: registry)
            reference.parseFull(source)

            #expect(parser.highlights == reference.highlights, "diverged after edit \(index)")
            #expect(parser.lastParseWasIncremental, "edit \(index) fell back to a full reparse")
        }
    }

    @Test("An edit inconsistent with the new snapshot falls back to a full reparse")
    func inconsistentEditFallsBack() throws {
        let parser = try DocumentParser(language: .json, registry: GrammarRegistry())
        parser.parseFull(#"{"a": 1}"#)

        // The snapshot does not reflect the edit; the parser must not trust it.
        let bogus = TextEdit.insert("xxxx", at: 1)
        let snapshot = #"{"a": 1, "b": 2}"#
        parser.apply(bogus, newSnapshot: snapshot)

        #expect(!parser.lastParseWasIncremental)

        let reference = try DocumentParser(language: .json, registry: GrammarRegistry())
        reference.parseFull(snapshot)
        #expect(parser.highlights == reference.highlights)
    }

    // MARK: - plaintext

    @Test("plaintext is one plain run, and stays that way across edits")
    func plaintextIsASingleRun() throws {
        let parser = try DocumentParser(language: .plaintext, registry: GrammarRegistry())

        let source = "no grammar here\njust text 🧊"
        parser.parseFull(source)

        #expect(parser.highlights == [HighlightRun(range: 0..<source.utf16.count, role: .plain)])
        #expect(!parser.lastParseWasIncremental)

        let edit = TextEdit.insert("!", at: 3)
        let updated = Self.applying(edit, to: source)
        parser.apply(edit, newSnapshot: updated)

        #expect(parser.highlights == [HighlightRun(range: 0..<updated.utf16.count, role: .plain)])
    }

    @Test("An empty document has no runs", arguments: LanguageID.allCases)
    func emptyDocumentHasNoRuns(_ language: LanguageID) throws {
        let parser = try DocumentParser(language: language, registry: GrammarRegistry())
        parser.parseFull("")
        #expect(parser.highlights.isEmpty)
        #expect(parser.documentLength == 0)
    }

    // MARK: - Syntax errors

    @Test("Malformed input surfaces .error without swallowing valid tokens")
    func malformedInputProducesErrorRuns() throws {
        let parser = try DocumentParser(language: .sql, registry: GrammarRegistry())
        let source = "SELECT FROM WHERE ORDER;"
        parser.parseFull(source)
        let utf16 = Array(source.utf16)

        let roles = Set(parser.highlights.map(\.role))
        #expect(roles.contains(.error), "no .error run for malformed SQL")

        // The valid prefix still highlights — .error ranks below every capture.
        let selectRun = try #require(parser.highlights.first { Self.text($0, in: utf16) == "SELECT" })
        #expect(selectRun.role == .keyword)
    }

    /// Not every parse failure has a visible span. tree-sitter reports an omitted
    /// token as a zero-width `MISSING` node, and a zero-width run is not something
    /// this package invents a position for — the honest output is no `.error` run
    /// at all, with the surrounding valid tokens still highlighted.
    @Test("A zero-width MISSING node produces no error run, and loses nothing")
    func missingNodeDegradesGracefully() throws {
        let parser = try DocumentParser(language: .json, registry: GrammarRegistry())
        let source = #"{"a": , "b": 2}"#
        parser.parseFull(source)
        let utf16 = Array(source.utf16)

        #expect(!parser.highlights.contains { $0.role == .error })

        let key = try #require(parser.highlights.first { Self.text($0, in: utf16) == "\"b\"" })
        #expect(key.role == .property)

        let number = try #require(parser.highlights.first { Self.text($0, in: utf16) == "2" })
        #expect(number.role == .number)
    }

    // MARK: - Registry behaviour

    @Test("Grammars are cached per language")
    func registryCaches() throws {
        let loads = LoadCounter()
        let registry = GrammarRegistry(queryData: { language in
            loads.increment()
            return try GrammarRegistry.bundledQueryData(language)
        })

        _ = try registry.grammar(for: .sql)
        _ = try registry.grammar(for: .sql)
        _ = try registry.grammar(for: .json)
        #expect(loads.value == 2)

        registry.evict()
        _ = try registry.grammar(for: .sql)
        #expect(loads.value == 3)
    }

    @Test("plaintext loads without a grammar and without throwing")
    func plaintextGrammarIsAbsentByDesign() throws {
        let grammar = try GrammarRegistry().grammar(for: .plaintext)
        #expect(grammar.treeSitterLanguage == nil)
        #expect(grammar.highlightQuery == nil)
        #expect(!grammar.isParsable)
    }

    // MARK: - Error paths

    /// A missing query resource is a `grammarUnavailable`, not a crash and not a
    /// silently unhighlighted document. Exercised through the injection seam so no
    /// broken resource has to ship.
    @Test("A missing query resource throws grammarUnavailable")
    func missingQueryThrows() throws {
        let registry = GrammarRegistry(queryData: { language in
            throw EditorError.grammarUnavailable(language: language)
        })

        #expect(throws: EditorError.grammarUnavailable(language: .sql)) {
            _ = try registry.grammar(for: .sql)
        }

        #expect(throws: EditorError.grammarUnavailable(language: .bash)) {
            _ = try DocumentParser(language: .bash, registry: registry)
        }

        // plaintext never consults the provider, so it still loads.
        #expect(throws: Never.self) {
            _ = try registry.grammar(for: .plaintext)
        }
    }

    @Test("A non-EditorError from the provider is reported as grammarUnavailable")
    func providerFailureIsNormalised() throws {
        struct Boom: Error {}
        let registry = GrammarRegistry(queryData: { _ in throw Boom() })

        #expect(throws: EditorError.grammarUnavailable(language: .yaml)) {
            _ = try registry.grammar(for: .yaml)
        }
    }

    @Test("A query that does not compile throws queryCompilationFailed with a reason")
    func brokenQueryThrows() throws {
        let registry = GrammarRegistry(queryData: { _ in
            Data("(this_node_type_does_not_exist) @keyword".utf8)
        })

        do {
            _ = try registry.grammar(for: .sql)
            Issue.record("expected queryCompilationFailed")
        } catch let error as EditorError {
            guard case .queryCompilationFailed(let language, let reason) = error else {
                Issue.record("expected queryCompilationFailed, got \(error)")
                return
            }
            #expect(language == .sql)
            #expect(!reason.isEmpty, "queryCompilationFailed carried an empty reason")
        }
    }

    @Test("Malformed query syntax also throws queryCompilationFailed")
    func malformedQuerySyntaxThrows() throws {
        let registry = GrammarRegistry(queryData: { _ in Data("((((".utf8) })

        #expect(throws: EditorError.self) {
            _ = try registry.grammar(for: .json)
        }
    }

    // MARK: - Line index

    @Test("Line index splices match a rebuild from scratch")
    func lineIndexSplicesCorrectly() throws {
        var rng = SeededGenerator(seed: 0x5DEE_CE66_D_ABCD)
        var source = "alpha\nbeta\ngamma\n\ndelta"
        var index = LineStartIndex()
        index.rebuild(from: Array(source.utf16))

        for step in 0..<200 {
            let length = source.utf16.count
            let edit: TextEdit
            if length == 0 || Bool.random(using: &rng) {
                let offset = Int.random(in: 0...length, using: &rng)
                // ASCII only: a random single-unit delete could split a surrogate
                // pair, and the lossy re-decode would change the document length
                // out from under the splice — a confound, not a bug under test.
                let text = ["x", "\n", "ab\ncd", "\n\n", "  "].randomElement(using: &rng)!
                edit = TextEdit.insert(text, at: offset)
            } else {
                let lower = Int.random(in: 0..<length, using: &rng)
                let upper = Int.random(in: lower...min(length, lower + 6), using: &rng)
                edit = TextEdit.delete(lower..<upper)
            }

            source = Self.applying(edit, to: source)
            index.apply(replacing: edit.replacementRange, inserted: Array(edit.text.utf16))

            var rebuilt = LineStartIndex()
            rebuilt.rebuild(from: Array(source.utf16))

            #expect(index.lineCount == rebuilt.lineCount, "line count diverged at step \(step)")
            for offset in stride(from: 0, through: source.utf16.count, by: 1) {
                let spliced = index.point(at: offset)
                let fresh = rebuilt.point(at: offset)
                #expect(spliced == fresh, "point(\(offset)) diverged at step \(step): \(spliced) vs \(fresh)")
            }
        }
    }

    // MARK: - Helpers

    /// UTF-16 offset of the first occurrence of `token`.
    static func utf16Offset(of token: String, in source: String) -> Int? {
        guard let range = source.range(of: token) else { return nil }
        return source[source.startIndex..<range.lowerBound].utf16.count
    }

    /// Applies a `TextEdit` to a string in UTF-16 space, mirroring what the storage
    /// layer does, so the fixture and the parser always agree.
    static func applying(_ edit: TextEdit, to source: String) -> String {
        var units = Array(source.utf16)
        let clampedLower = min(max(0, edit.replacementRange.lowerBound), units.count)
        let clampedUpper = min(max(clampedLower, edit.replacementRange.upperBound), units.count)
        units.replaceSubrange(clampedLower..<clampedUpper, with: Array(edit.text.utf16))
        return String(decoding: units, as: UTF16.self)
    }
}

/// Counts provider invocations from inside a `@Sendable` closure.
final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

/// Deterministic RNG so a failing property test is reproducible from the seed
/// printed in its message (projectRules.md, Testing).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        // SplitMix64.
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Over the ceiling nothing is parsed — not parsed and then discarded (2026-09-23: a 14.6 MB SVG
/// spent 13 seconds in a parse whose result the ceiling then threw away).
@Suite("A document over the highlighting ceiling is not parsed")
@MainActor
struct HighlightingCeilingTests {
    @Test("Over: plaintext, no parse, the length still known. Back under: parsed again")
    func overAndUnder() throws {
        let parser = try DocumentParser(language: .json, registry: GrammarRegistry(), highlightingCodeUnitCeiling: 10)
        parser.parseFull(#"{"a": 1, "b": 2, "c": 3}"#)
        #expect(parser.highlightingDegraded)
        #expect(parser.parseCount == 0, "a document over the ceiling was parsed anyway")
        #expect(parser.documentLength == 24)
        #expect(parser.highlights.count == 1, "one plain run over the whole document")

        parser.parseFull(#"{"a": 1}"#)
        #expect(!parser.highlightingDegraded)
        #expect(parser.parseCount == 1)
        #expect(parser.highlights.contains { $0.role != .plain }, "coloured again once under the ceiling")
    }
}
