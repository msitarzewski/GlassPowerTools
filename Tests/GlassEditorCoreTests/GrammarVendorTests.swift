import Foundation
import SwiftTreeSitter
import Testing

@testable import GlassEditorCore

import TreeSitterBash
import TreeSitterJSON
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterSql
import TreeSitterTOML
import TreeSitterYAML

/// Proves every grammar links, parses, and has a highlight query that compiles against it.
///
/// Each grammar is fixed to an exact upstream commit — some as pinned dependencies, the rest
/// vendored in `Packages/` (THIRD-PARTY-NOTICES.md says which and why). This suite checks the
/// original seven directly against the C symbols; `GrammarCoverageTests` and `GrammarModuleTests`
/// run every language, so a pin that moved or a vendored copy that broke fails in tests rather
/// than in the editor.
@Suite("Vendored tree-sitter grammars")
struct GrammarVendorTests {

    /// One vendored grammar plus the snippet and query file it is checked against.
    struct Grammar {
        let name: String
        let language: Language
        let queryResource: String
        let snippet: String
    }

    static let grammars: [Grammar] = [
        Grammar(
            name: "json",
            language: Language(tree_sitter_json()),
            queryResource: "json-highlights",
            snippet: #"{"name": "glass", "version": 1, "tags": ["a", "b"], "ok": true, "none": null}"#
        ),
        Grammar(
            name: "bash",
            language: Language(tree_sitter_bash()),
            queryResource: "bash-highlights",
            snippet: """
            #!/usr/bin/env bash
            set -euo pipefail
            for f in "$@"; do
              if [ -f "$f" ]; then
                printf '%s\\n' "$(basename "$f")"
              fi
            done
            """
        ),
        Grammar(
            name: "yaml",
            language: Language(tree_sitter_yaml()),
            queryResource: "yaml-highlights",
            snippet: """
            version: 2
            services:
              db:
                image: postgres:16
                ports:
                  - "5432:5432"
                environment:
                  POSTGRES_PASSWORD: secret
            """
        ),
        Grammar(
            name: "toml",
            language: Language(tree_sitter_toml()),
            queryResource: "toml-highlights",
            snippet: """
            title = "glass"

            [owner]
            name = "Glass Family"
            ports = [8000, 8001]
            enabled = true
            """
        ),
        Grammar(
            name: "sql",
            language: Language(tree_sitter_sql()),
            queryResource: "sql-highlights",
            snippet: """
            SELECT u.id, count(*) AS n
            FROM users AS u
            JOIN orders o ON o.user_id = u.id
            WHERE u.created_at > '2026-01-01'
            GROUP BY u.id
            ORDER BY n DESC
            LIMIT 10;
            """
        ),
        Grammar(
            name: "markdown",
            language: Language(tree_sitter_markdown()),
            queryResource: "markdown-highlights",
            snippet: """
            # Heading

            Some *emphasised* text with a [link](https://example.com).

            - item one
            - item two

            ```swift
            let x = 1
            ```
            """
        ),
        Grammar(
            name: "markdown-inline",
            language: Language(tree_sitter_markdown_inline()),
            queryResource: "markdown-inline-highlights",
            snippet: "Some *emphasised* text with `code` and a [link](https://example.com)."
        ),
    ]

    /// Every grammar parses a valid snippet into an error-free tree.
    @Test("Grammar parses a valid snippet without a top-level error", arguments: grammars)
    func grammarParses(_ grammar: Grammar) throws {
        let parser = Parser()
        try parser.setLanguage(grammar.language)

        let tree = try #require(parser.parse(grammar.snippet), "\(grammar.name): parser returned no tree")
        let root = try #require(tree.rootNode, "\(grammar.name): tree had no root node")

        #expect(!root.hasError, "\(grammar.name): valid snippet produced a tree containing ERROR")
        #expect(root.childCount > 0, "\(grammar.name): root node parsed no children")
    }

    /// Negative control for `grammarParses`. If a grammar never reports an error
    /// the clean-parse assertion above proves nothing, so these grammars are shown
    /// to reject text that is definitely malformed for them. Markdown is absent by
    /// design: CommonMark has no invalid input, so every byte sequence parses.
    @Test(
        "Malformed input is reported as an error",
        arguments: [
            ("json", Language(tree_sitter_json()), "{\"a\": , }"),
            ("bash", Language(tree_sitter_bash()), "if [ -f x ]; then\n"),
            ("toml", Language(tree_sitter_toml()), "= \"no key\"\n"),
            ("sql", Language(tree_sitter_sql()), "SELECT FROM WHERE ORDER;"),
        ]
    )
    func malformedInputErrors(_ name: String, _ language: Language, _ snippet: String) throws {
        let parser = Parser()
        try parser.setLanguage(language)

        let tree = try #require(parser.parse(snippet))
        let root = try #require(tree.rootNode)

        #expect(root.hasError, "\(name): malformed input parsed clean — the error assertions are vacuous")
    }

    /// `GlassEditorCore`'s own resource bundle. The queries are declared on that
    /// target, not on the test target, so `Bundle.module` here would resolve to the
    /// wrong bundle. `GlassEditorCoreResources` is the module's own accessor.
    static var coreBundle: Bundle { GlassEditorCoreResources.bundle }

    /// Every vendored highlights.scm compiles against the grammar it ships with.
    @Test("Vendored highlights.scm compiles as a Query", arguments: grammars)
    func highlightQueryCompiles(_ grammar: Grammar) throws {
        let url = try #require(
            GlassEditorCoreResources.highlightQueryURL(named: grammar.queryResource),
            "\(grammar.name): \(grammar.queryResource).scm not found in the GlassEditorCore resource bundle"
        )

        let data = try Data(contentsOf: url)
        let query = try Query(language: grammar.language, data: data)

        #expect(query.patternCount > 0, "\(grammar.name): highlight query compiled to zero patterns")
        #expect(query.captureCount > 0, "\(grammar.name): highlight query declared no captures")
        #expect(query.captureName(for: 0) != nil, "\(grammar.name): capture 0 has no name")
    }

    /// Each target exports a genuinely different language — a copy/paste slip in
    /// the vendoring script would otherwise silently alias two grammars — and each
    /// sits inside the ABI window the pinned tree-sitter runtime accepts.
    @Test("Every vendored grammar is a distinct, ABI-compatible language")
    func grammarsAreDistinct() {
        let pointers = Set(Self.grammars.map(\.language.tsLanguage))
        #expect(pointers.count == Self.grammars.count, "two vendored targets resolve to the same TSLanguage")

        for grammar in Self.grammars {
            let abi = grammar.language.ABIVersion
            #expect(
                abi >= Language.minimumCompatibleVersion && abi <= Language.version,
                "\(grammar.name): ABI \(abi) outside runtime window \(Language.minimumCompatibleVersion)...\(Language.version)"
            )
        }
    }
}

extension GrammarVendorTests.Grammar: CustomTestStringConvertible {
    var testDescription: String { name }
}
