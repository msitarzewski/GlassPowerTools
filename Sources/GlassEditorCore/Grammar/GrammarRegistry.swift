import Foundation
import SwiftTreeSitter

import TreeSitterBash
import TreeSitterJSON
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterSql
import TreeSitterTOML
import TreeSitterYAML

/// Loads and caches the tree-sitter grammar and compiled highlight query for each
/// `LanguageID`.
///
/// ## Isolation
///
/// `@MainActor`. Neither `TSParser` nor the C grammars are thread-safe, and
/// SwiftTreeSitter's `Parser` is a plain class with no internal synchronisation.
/// `Language` and `Query` *are* `Sendable` (both are immutable once built), so the
/// registry itself could in principle be an `actor` — but it exists to feed
/// `DocumentParser`, which owns a `Parser` and must be main-isolated anyway, and a
/// second isolation domain between them would buy nothing but hops. Main-actor is
/// the pragmatic v1 home.
///
/// A background parse actor is a plausible M5 evolution: it would own the `Parser`
/// and the tree, receive `TextEdit`s, and publish `[HighlightRun]` back to the main
/// actor. Nothing in this type's API blocks that — `LoadedGrammar` is already
/// `Sendable`, so the registry could be shared across such actors unchanged.
@MainActor
public final class GrammarRegistry {

    /// A grammar and its compiled highlight query, ready to parse with.
    ///
    /// `plaintext` is a real, supported language whose grammar is *absent by
    /// design*: both properties are `nil` and `DocumentParser` emits a single
    /// `.plain` run. That is not an error state (LanguageID.swift:4).
    public struct LoadedGrammar: Sendable {
        public let language: LanguageID
        public let treeSitterLanguage: Language?
        public let highlightQuery: Query?

        /// Whether this grammar parses. `false` only for `plaintext`.
        public var isParsable: Bool { treeSitterLanguage != nil }
    }

    /// Supplies the raw `.scm` bytes for a language.
    ///
    /// The default reads the resource bundle. Tests inject a provider that throws
    /// or returns deliberately broken bytes to exercise `.grammarUnavailable` and
    /// `.queryCompilationFailed` without shipping a broken resource.
    public typealias QueryDataProvider = @Sendable (LanguageID) throws -> Data

    private let queryData: QueryDataProvider
    private var cache: [LanguageID: LoadedGrammar] = [:]

    public init(queryData: @escaping QueryDataProvider = GrammarRegistry.bundledQueryData) {
        self.queryData = queryData
    }

    /// The grammar for `language`, loading and caching it on first use.
    ///
    /// - Throws: `EditorError.grammarUnavailable` when the grammar cannot be
    ///   loaded — a missing query resource, or an ABI version outside the window
    ///   the linked tree-sitter runtime accepts.
    ///   `EditorError.queryCompilationFailed` when the query resource is present
    ///   but does not compile against the grammar.
    public func grammar(for language: LanguageID) throws -> LoadedGrammar {
        if let cached = cache[language] { return cached }

        let loaded = try load(language)
        cache[language] = loaded
        return loaded
    }

    /// Drops every cached grammar. Present for tests and for consumers that want
    /// to release query memory; correctness never depends on calling it.
    public func evict() {
        cache.removeAll()
    }

    // MARK: - Loading

    private func load(_ language: LanguageID) throws -> LoadedGrammar {
        guard let tsLanguage = Self.treeSitterLanguage(for: language) else {
            // plaintext: no grammar by design, not a failure.
            return LoadedGrammar(language: language, treeSitterLanguage: nil, highlightQuery: nil)
        }

        let abi = tsLanguage.ABIVersion
        guard abi >= Language.minimumCompatibleVersion, abi <= Language.version else {
            throw EditorError.grammarUnavailable(language: language)
        }

        let data: Data
        do {
            data = try queryData(language)
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError.grammarUnavailable(language: language)
        }

        let query: Query
        do {
            query = try Query(language: tsLanguage, data: data)
        } catch {
            throw EditorError.queryCompilationFailed(
                language: language,
                reason: Self.describe(queryError: error)
            )
        }

        return LoadedGrammar(language: language, treeSitterLanguage: tsLanguage, highlightQuery: query)
    }

    /// The vendored C grammar for a language, or `nil` for `plaintext`.
    ///
    /// `markdown` resolves to the **block** grammar. The inline grammar is
    /// vendored, linked, and exposed by ``markdownInlineLanguage`` but is not wired
    /// as an injection — see `DocumentParser` for the limitation this imposes.
    public nonisolated static func treeSitterLanguage(for language: LanguageID) -> Language? {
        switch language {
        case .sql: return Language(tree_sitter_sql())
        case .json: return Language(tree_sitter_json())
        case .bash: return Language(tree_sitter_bash())
        case .yaml: return Language(tree_sitter_yaml())
        case .toml: return Language(tree_sitter_toml())
        case .markdown: return Language(tree_sitter_markdown())
        case .plaintext: return nil
        }
    }

    /// The vendored markdown *inline* grammar.
    ///
    /// Not reachable through ``grammar(for:)`` because it is not a `LanguageID` —
    /// it is one half of a two-grammar language. Exposed so the M5 injection work
    /// has something to build on without re-vendoring.
    public nonisolated static var markdownInlineLanguage: Language { Language(tree_sitter_markdown_inline()) }

    /// Base name of the highlight query resource for a language.
    public nonisolated static func queryResourceName(for language: LanguageID) -> String? {
        switch language {
        case .sql: return "sql-highlights"
        case .json: return "json-highlights"
        case .bash: return "bash-highlights"
        case .yaml: return "yaml-highlights"
        case .toml: return "toml-highlights"
        case .markdown: return "markdown-highlights"
        case .plaintext: return nil
        }
    }

    /// Reads a language's highlight query from `GlassEditorCore`'s resource bundle.
    public nonisolated static let bundledQueryData: QueryDataProvider = { language in
        guard let name = queryResourceName(for: language),
              let url = GlassEditorCoreResources.highlightQueryURL(named: name)
        else {
            throw EditorError.grammarUnavailable(language: language)
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            throw EditorError.grammarUnavailable(language: language)
        }
    }

    private nonisolated static func describe(queryError: Error) -> String {
        guard let error = queryError as? QueryError else {
            return String(describing: queryError)
        }

        switch error {
        case .none: return "no error reported"
        case .syntax(let offset): return "syntax error at byte \(offset)"
        case .nodeType(let offset): return "unknown node type at byte \(offset)"
        case .field(let offset): return "unknown field at byte \(offset)"
        case .capture(let offset): return "unknown capture at byte \(offset)"
        case .structure(let offset): return "invalid pattern structure at byte \(offset)"
        case .unknown(let offset): return "unknown query error at byte \(offset)"
        }
    }
}
