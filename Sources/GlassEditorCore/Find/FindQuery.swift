import Foundation

/// What the user typed into the find field, plus how it should be interpreted.
///
/// A query is a pure value — it carries no cursor, no document, and no match
/// state. `FindEngine` evaluates it against an immutable snapshot, so the same
/// query is safe to hold in a view model, pass across actors, or persist.
///
/// ## Semantics
///
/// - **`.literal`** — `pattern` is matched verbatim. It is never handed to a
///   regular-expression engine, so `.*` finds the two characters `.*` and
///   nothing else.
/// - **`.regex`** — `pattern` is an ICU regular expression compiled by
///   `NSRegularExpression`. A pattern that fails to compile throws
///   `EditorError.invalidPattern`.
/// - **`caseSensitive == false`** — case folding is applied. The exact folding
///   rules differ by kind and are documented on `FindEngine.matches(of:in:)`.
/// - **`wholeWord`** — a match is kept only when the characters immediately
///   before and after it are not word characters
///   (`FindEngine.isWordCharacter(_:)`). This is a filter applied to matches the
///   engine already found; it is not the regex engine's `\b`.
/// - **empty `pattern`** — matches nothing. It never throws and never loops.
public struct FindQuery: Sendable, Hashable, Codable {
    /// How `pattern` is interpreted.
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        /// Verbatim text. Regular-expression metacharacters carry no meaning.
        case literal
        /// An ICU regular expression, compiled by `NSRegularExpression`.
        case regex
    }

    /// The search text, interpreted according to `kind`.
    public var pattern: String
    /// Whether `pattern` is literal text or a regular expression.
    public var kind: Kind
    /// When `false`, matching folds case (see `FindEngine.matches(of:in:)`).
    public var caseSensitive: Bool
    /// When `true`, matches adjacent to a word character are discarded.
    public var wholeWord: Bool

    public init(
        pattern: String,
        kind: Kind = .literal,
        caseSensitive: Bool = false,
        wholeWord: Bool = false
    ) {
        self.pattern = pattern
        self.kind = kind
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
    }

    /// A query with an empty pattern matches nothing — the engine short-circuits
    /// on this rather than asking Foundation to search for "".
    public var isEmpty: Bool { pattern.isEmpty }
}
