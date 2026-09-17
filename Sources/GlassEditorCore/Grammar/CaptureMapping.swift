import Foundation

/// Translates tree-sitter highlight capture names into `TokenRole`.
///
/// The table below is not aspirational: every entry corresponds to a capture name
/// that actually appears in one of the seven vendored `.scm` files under
/// `Grammar/Queries`. `CaptureMappingTests` enumerates the capture names of every
/// compiled query and fails if any of them is not covered here.
///
/// ## Fallback policy
///
/// An unrecognised capture name is reduced one dotted component at a time
/// (`string.special.key` → `string.special` → `string`) and, if nothing matches,
/// resolves to `.plain`. `.plain` is therefore both a legitimate mapping and the
/// fallback — a capture that means "render this as ordinary text". Because the
/// fallback is silent by design, the totality test above is what keeps a newly
/// vendored grammar from quietly losing colour: every capture name in every
/// shipped query must resolve to a non-`.plain` role *or* appear in
/// ``intentionallyPlainCaptures``.
///
/// ## Language overrides
///
/// A few capture names carry a different meaning in one grammar than they do in
/// general. Those live in ``overrides(for:)``, which is consulted before the
/// universal table. The SQL overrides exist to protect the D-008 fidelity
/// contract: glassdb's `SQLTokenKind` classified table names and aliases as
/// *identifiers*, and nvim's SQL query captures them as `@type` and `@variable`.
/// Without the override, replacing glassdb's highlighter would silently restyle
/// every table name in the app.
public enum CaptureMapping: Sendable {

    // MARK: - Public API

    /// The role a capture name carries in a given grammar.
    ///
    /// Total: every input returns a role. See the fallback policy above.
    public static func role(for captureName: String, in language: LanguageID) -> TokenRole {
        var name = captureName

        while true {
            if let override = overrides(for: language)[name] { return override }
            if let role = universal[name] { return role }

            guard let dot = name.lastIndex(of: ".") else { return .plain }
            name = String(name[name.startIndex..<dot])
        }
    }

    /// Whether a capture participates in highlighting at all.
    ///
    /// `@spell` / `@nospell` are spell-checker hints that nvim-treesitter attaches
    /// as *secondary* captures on nodes that already carry a highlight capture —
    /// `(comment) @comment @spell` in `sql-highlights.scm:34` is the case that
    /// ships here. They carry no colour, so they are dropped before priority
    /// resolution rather than being allowed to compete with `@comment`.
    public static func isHighlighting(_ captureName: String) -> Bool {
        !nonHighlightingCaptures.contains(captureName)
    }

    /// Capture names that map to `.plain` on purpose, not by falling off the table.
    ///
    /// - `none`: nvim's "clear any highlight here" capture. `markdown-highlights.scm:27`
    ///   uses it on `(code_fence_content)` so an injected language can paint the
    ///   body instead. We ship no injections, so in practice the enclosing
    ///   `(fenced_code_block) @text.literal` outranks it and the body renders as
    ///   `.markupCode` — see `HighlightPriority` for why.
    /// - `spell` / `nospell`: spell-check hints, also excluded by ``isHighlighting(_:)``.
    public static let intentionallyPlainCaptures: Set<String> = [
        "none",
        // XML's character data — the text between the tags. It is the document's content and it
        // reads as content; painting it would leave nothing on the page uncoloured.
        "markup",
        "spell",
        "nospell",
    ]

    // MARK: - Tables

    /// Capture names that never contribute a highlight run.
    private static let nonHighlightingCaptures: Set<String> = ["spell", "nospell"]

    /// The universal capture-name table. Every name here appears in at least one
    /// vendored query; the grammars that use it are noted alongside.
    private static let universal: [String: TokenRole] = [
        // --- Comments, literals -------------------------------------------------
        "comment": .comment,                    // bash, json, sql, toml, yaml
        "string": .string,                      // bash, json, sql, toml, yaml
        "string.escape": .string,               // markdown, markdown-inline (backslash escapes)
        "string.special": .string,              // toml (offset/local date-times)
        "string.special.key": .property,        // json (object keys)
        "escape": .string,                      // json (escape_sequence inside a string)
        "number": .number,                      // bash, json, sql, toml, yaml
        "float": .number,                       // sql
        "boolean": .boolean,                    // sql, toml, yaml
        "constant": .constant,                  // bash (command flags)
        "constant.builtin": .constant,          // json (null/true/false), yaml (null_scalar)

        // --- Names --------------------------------------------------------------
        "function": .function,                  // bash (command names, definitions)
        "function.call": .function,             // sql
        "field": .identifier,                   // sql (column references)
        "variable": .variable,                  // sql (overridden to .identifier there)
        "property": .property,                  // bash, toml, yaml (mapping keys)
        "parameter": .parameter,                // sql (bind parameters)
        "label": .label,                        // yaml (anchors and aliases)
        "attribute": .attribute,                // sql (overridden), yaml (directives)
        "type": .type,                          // sql (overridden), toml, yaml (tags)
        "type.builtin": .type,                  // sql (INT, VARCHAR, TIMESTAMP …)
        "type.qualifier": .keyword,             // sql (NOT NULL, MAXVALUE …)

        // --- Keywords and operators --------------------------------------------
        "keyword": .keyword,                    // bash, sql
        "keyword.operator": .keyword,           // sql (IN, AND, OR, NOT, BY, ON, UNION …)
        "conditional": .keyword,                // sql (CASE/WHEN/THEN/ELSE)
        "storageclass": .keyword,               // sql (VOLATILE, STORED, SEQUENCEFILE …)
        "operator": .operator,                  // bash, sql, toml
        "punctuation.bracket": .punctuation,    // sql, toml, yaml
        "punctuation.delimiter": .punctuation,  // markdown, markdown-inline, sql, toml, yaml
        // C's query uses the bare `@delimiter` for the same thing `@punctuation.delimiter` marks
        // elsewhere — semicolons, commas, the arrow in a field expression (c-highlights.scm).
        "delimiter": .punctuation,              // c
        // A class or struct being *constructed* or defined. Painted as a type, which is what it
        // names and what every theme in this app already colours: `Foo()` in Python, `new Foo()` in
        // JavaScript, a tuple struct's name in Rust.
        "constructor": .type,                   // python, javascript, rust
        // PHP marks `<?php` and `?>` as `@tag` — the boundary between markup and code, which reads
        // as punctuation rather than as a keyword.
        "tag": .punctuation,                    // php
        // A namespace. `@module.builtin` reduces to `@module` through the dotted fallback, so one
        // entry covers both.
        "module": .type,                        // php
        "punctuation.special": .punctuation,    // markdown (heading/list markers), yaml

        // --- Embedded / markup --------------------------------------------------
        "embedded": .embedded,                  // bash (command and process substitution)
        "text.title": .markupHeading,           // markdown
        "text.literal": .markupCode,            // markdown, markdown-inline
        "text.emphasis": .markupEmphasis,       // markdown-inline
        "text.strong": .markupStrong,           // markdown-inline
        "text.uri": .markupLink,                // markdown, markdown-inline
        "text.reference": .markupLink,          // markdown, markdown-inline

        // --- Added 2026-09-17 with the Swift and XML grammars ---------------------
        // Swift uses it for the wildcard pattern — the `_` that stands in for a name
        // (`swift-highlights.scm:286`). It is a keyword-ish placeholder, not a character, and
        // nothing else in the shipped queries uses the capture.
        "character.special": .keyword,
        // XML's `(ERROR)` node, painted deliberately by the grammar's own query rather than
        // arrived at through the parser's error recovery.
        "error": .error,
        // Character data between tags: the document's actual text, which should read as text.
        "markup": .plain,
        // CDATA: the delimiters mark a section, the body inside it is raw.
        "markup.heading": .markupHeading,
        "markup.raw": .markupCode,
        "markup.link": .markupLink,

        // --- Deliberate .plain --------------------------------------------------
        "none": .plain,                         // markdown (see intentionallyPlainCaptures)
        "spell": .plain,                        // sql
        "nospell": .plain,
    ]

    /// Per-grammar meaning shifts, consulted before ``universal``.
    private static func overrides(for language: LanguageID) -> [String: TokenRole] {
        switch language {
        case .sql: return sqlOverrides
        case .toml: return tomlOverrides
        // The five added in 2026-09 use nvim's conventional capture names, which `universal`
        // already maps — no grammar-specific meaning shift to undo, unlike TOML's `@type`.
        case .xml: return xmlOverrides
        case .json, .bash, .yaml, .markdown, .python, .javascript, .go, .rust, .c, .php,
             .swift, .plaintext:
            return [:]
        }
    }

    /// TOML applies `@type` to `(bare_key)` and nothing else (`toml-highlights.scm:4`),
    /// so in this grammar the capture means "key", not "type". Upstream leans on
    /// nvim's later-pattern-wins ordering — `(pair (bare_key)) @property` repaints
    /// pair keys afterwards — which leaves table headers as `@type` and pair keys as
    /// `@property` for the same syntactic thing. Mapping the capture once, here, is
    /// both simpler and more consistent: every TOML key is a `.property`.
    private static let tomlOverrides: [String: TokenRole] = [
        "type": .property,
    ]

    /// XML paints element names with `@tag` and attribute names with `@tag.attribute`
    /// (`queries/xml/highlights.scm`). `@tag` is punctuation in the universal table — it is what
    /// HTML-ish grammars use for `<` and `>` — so left alone every element name in a document would
    /// come out as bracket-coloured punctuation. In a markup language the element name is the
    /// closest thing there is to a keyword, and the attribute name is a property.
    private static let xmlOverrides: [String: TokenRole] = [
        "tag": .keyword,
        "tag.attribute": .property,
        "tag.delimiter": .punctuation,
    ]

    /// SQL reads these captures differently from the general convention.
    ///
    /// D-008 requires that the ten `SQLTokenKind` cases survive this mapping.
    /// nvim's SQL query paints table/schema references as `@type` and correlation
    /// aliases as `@variable`; both are *identifiers* to glassdb, so they are
    /// remapped. `@attribute` in SQL covers reserved modifiers (DETERMINISTIC,
    /// STABLE, PARALLEL, …), which are keywords, not attributes — unlike YAML,
    /// where `@attribute` marks `%YAML` / `%TAG` directives.
    private static let sqlOverrides: [String: TokenRole] = [
        "type": .identifier,
        "variable": .identifier,
        "attribute": .keyword,
    ]

    /// Every capture name this type recognises, for diagnostics and tests.
    public static var knownCaptureNames: Set<String> {
        var names = Set(universal.keys)
        for language in LanguageID.allCases {
            names.formUnion(overrides(for: language).keys)
        }
        return names
    }
}
