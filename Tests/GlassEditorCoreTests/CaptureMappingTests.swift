import Foundation
import SwiftTreeSitter
import Testing

@testable import GlassEditorCore

/// Guards the capture-name → `TokenRole` table against the queries that actually
/// ship. The totality test is the important one: `CaptureMapping` falls back to
/// `.plain` silently, so without it a newly vendored grammar could introduce a
/// dozen unmapped capture names and the only symptom would be uncoloured text.
@Suite("Capture mapping")
struct CaptureMappingTests {

    /// Every capture name declared by every vendored highlight query, keyed by the
    /// language whose query declares it. Read from the compiled `Query` rather than
    /// grepped out of the `.scm`, so predicate arguments and comments cannot be
    /// mistaken for captures.
    static func captureNames(for language: LanguageID) throws -> [String] {
        let tsLanguage = try #require(
            GrammarRegistry.treeSitterLanguage(for: language),
            "\(language.rawValue): no vendored grammar"
        )
        let name = try #require(GrammarRegistry.queryResourceName(for: language))
        let url = try #require(
            GlassEditorCoreResources.highlightQueryURL(named: name),
            "\(name).scm missing from the GlassEditorCore resource bundle"
        )

        let query = try Query(language: tsLanguage, data: try Data(contentsOf: url))
        return (0..<query.captureCount).compactMap { query.captureName(for: $0) }
    }

    /// The languages with a shipped grammar — everything except `plaintext`.
    static let parsableLanguages: [LanguageID] = LanguageID.allCases.filter { $0 != .plaintext }

    // MARK: - Totality

    @Test(
        "Every capture name in every vendored query maps to a real role",
        arguments: parsableLanguages
    )
    func mappingIsTotal(_ language: LanguageID) throws {
        for name in try Self.captureNames(for: language) {
            let role = CaptureMapping.role(for: name, in: language)

            if role == .plain {
                #expect(
                    CaptureMapping.intentionallyPlainCaptures.contains(name),
                    """
                    \(language.rawValue): capture "@\(name)" fell through to .plain. \
                    Add it to CaptureMapping.universal, or — if it genuinely carries \
                    no colour — to CaptureMapping.intentionallyPlainCaptures with a \
                    comment saying why.
                    """
                )
            }
        }
    }

    /// The inline markdown query is not reachable through `LanguageID`, but it ships
    /// in the bundle and will be reachable the moment injections are wired. Its
    /// capture names are held to the same standard now so that work is not a
    /// mapping exercise.
    @Test("The markdown inline query's captures are mapped too")
    func inlineMarkdownMappingIsTotal() throws {
        let url = try #require(GlassEditorCoreResources.highlightQueryURL(named: "markdown-inline-highlights"))
        let query = try Query(language: GrammarRegistry.markdownInlineLanguage, data: try Data(contentsOf: url))

        for index in 0..<query.captureCount {
            let name = try #require(query.captureName(for: index))
            let role = CaptureMapping.role(for: name, in: .markdown)

            if role == .plain {
                #expect(
                    CaptureMapping.intentionallyPlainCaptures.contains(name),
                    "markdown-inline: capture \"@\(name)\" fell through to .plain"
                )
            }
        }
    }

    /// Documents the fallback policy as behaviour rather than prose.
    @Test("Unknown capture names reduce by dotted component, then fall back to .plain")
    func fallbackPolicy() {
        // Reduction: an unmapped leaf resolves via its prefix.
        #expect(CaptureMapping.role(for: "string.special.symbol", in: .json) == .string)
        #expect(CaptureMapping.role(for: "function.method.builtin", in: .bash) == .function)

        // No prefix matches at all.
        #expect(CaptureMapping.role(for: "definitely.not.a.capture", in: .sql) == .plain)
        #expect(CaptureMapping.role(for: "nonsense", in: .sql) == .plain)
    }

    // MARK: - SQL fidelity (D-008)

    /// The ten `SQLTokenKind` cases must survive the mapping. This is the mapping
    /// half of the contract; `GrammarModuleTests` proves the roles actually appear
    /// in a parsed SQL document.
    @Test("SQL captures preserve the SQL-ten roles")
    func sqlFidelity() {
        let expected: [String: TokenRole] = [
            "keyword": .keyword,
            "keyword.operator": .keyword,
            "conditional": .keyword,
            "storageclass": .keyword,
            "type.qualifier": .keyword,
            "attribute": .keyword,
            "function.call": .function,
            "string": .string,
            "number": .number,
            "float": .number,
            "comment": .comment,
            "field": .identifier,
            "type": .identifier,
            "variable": .identifier,
            "operator": .operator,
            "punctuation.bracket": .punctuation,
            "punctuation.delimiter": .punctuation,
            "boolean": .boolean,
            "parameter": .parameter,
        ]

        for (name, role) in expected {
            #expect(
                CaptureMapping.role(for: name, in: .sql) == role,
                "SQL @\(name) should map to .\(role.rawValue)"
            )
        }
    }

    @Test("A language override only applies to its own language")
    func overridesAreScoped() {
        // @type is an identifier in SQL and a key in TOML, but a type elsewhere.
        #expect(CaptureMapping.role(for: "type", in: .sql) == .identifier)
        #expect(CaptureMapping.role(for: "type", in: .toml) == .property)
        #expect(CaptureMapping.role(for: "type", in: .yaml) == .type)

        // @attribute is a reserved modifier in SQL, a directive in YAML.
        #expect(CaptureMapping.role(for: "attribute", in: .sql) == .keyword)
        #expect(CaptureMapping.role(for: "attribute", in: .yaml) == .attribute)
    }

    @Test("Spell-check captures never contribute a highlight")
    func spellCapturesAreDropped() {
        #expect(!CaptureMapping.isHighlighting("spell"))
        #expect(!CaptureMapping.isHighlighting("nospell"))
        #expect(CaptureMapping.isHighlighting("comment"))
        #expect(CaptureMapping.isHighlighting("none"))
    }

    // MARK: - Lua pattern translation

    /// `#match?` arguments in nvim-derived queries are Lua patterns. If this
    /// translation regresses, SQL numeric literals silently become strings —
    /// see `QueryPredicates.swift` for the full story.
    @Test("Lua character classes translate to ICU")
    func luaTranslation() throws {
        #expect(LuaPattern.translatedToICU("^[-+]?%d+$") == "^[-+]?[0-9]+$")
        #expect(LuaPattern.translatedToICU("^%a%w*$") == "^[A-Za-z][0-9A-Za-z]*$")
        #expect(LuaPattern.translatedToICU("%.") == "\\.")
        #expect(LuaPattern.translatedToICU("%%") == "\\%")

        // Complement outside a class.
        #expect(LuaPattern.translatedToICU("%D") == "[^0-9]")

        // Inside a class the body is spliced, not nested.
        #expect(LuaPattern.translatedToICU("[%d%a]") == "[0-9A-Za-z]")

        // Patterns with no `%` are returned untouched, existing escapes intact.
        #expect(LuaPattern.translatedToICU("^-") == "^-")
        #expect(LuaPattern.translatedToICU("^\\d+$") == "^\\d+$")
    }

    @Test("Translated SQL number patterns accept digits and reject quoted text")
    func luaTranslationMatchesRealSQLPatterns() throws {
        let integers = try NSRegularExpression(pattern: LuaPattern.translatedToICU("^[-+]?%d+$"))

        for accepted in ["42", "10", "-7", "+3"] {
            let range = NSRange(0..<accepted.utf16.count)
            #expect(integers.firstMatch(in: accepted, range: range) != nil, "\(accepted) should match")
        }

        for rejected in ["'2026-01-01'", "'glass'", "abc"] {
            let range = NSRange(0..<rejected.utf16.count)
            #expect(integers.firstMatch(in: rejected, range: range) == nil, "\(rejected) should not match")
        }
    }
}
