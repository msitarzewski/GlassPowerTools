import Foundation
import SwiftTreeSitter

/// Evaluates the `#match?` / `#eq?` family of query predicates against document text.
///
/// SwiftTreeSitter already ships `QueryMatch.allowed(in:)`, and this type would be
/// redundant but for one thing: **the vendored queries are nvim-treesitter
/// derivatives, so their `#match?` arguments are Lua patterns, not ICU regular
/// expressions.** SwiftTreeSitter compiles them with `NSRegularExpression`, where
/// `%d` is a literal percent followed by `d` rather than a digit class. The failure
/// is silent and it is not hypothetical:
///
/// ```
/// ((literal) @number (#match? @number "^[-+]?%d+$"))   ; sql-highlights.scm:37
/// ```
///
/// Under an untranslated ICU evaluation that predicate never fires, so every SQL
/// numeric literal falls through to `(literal) @string` and is highlighted as a
/// string. That is precisely the silent fidelity loss the D-008 SQL-ten contract
/// exists to prevent, so `#match?` patterns are translated before evaluation.
///
/// The `.scm` files themselves stay byte-identical to upstream — the compatibility
/// shim lives here, where it is unit-tested.
struct QueryPredicateEvaluator {

    /// Document text as UTF-16 code units — capture ranges are `NSRange`s over it.
    private let utf16: [UInt16]

    /// Compiled-pattern cache, keyed by the original (untranslated) pattern.
    private var regexCache: [String: NSRegularExpression] = [:]

    init(utf16: [UInt16]) {
        self.utf16 = utf16
    }

    /// Whether every predicate attached to `match` is satisfied.
    ///
    /// A predicate whose text cannot be read fails closed — the match is rejected
    /// rather than being allowed on an unverified assumption.
    mutating func allows(_ match: QueryMatch) -> Bool {
        for predicate in match.predicates {
            switch predicate {
            case .set, .generic:
                // Directives and unrecognised predicates carry no constraint.
                continue

            case .isNot:
                // Group membership (`#is-not? local`) needs a locals query, which
                // this package does not ship. No data means no constraint.
                continue

            case .match(let expression, _), .notMatch(let expression, _):
                let negated: Bool
                if case .notMatch = predicate { negated = true } else { negated = false }
                let regex = compiled(from: expression)

                for capture in predicate.captures(in: match) {
                    guard let text = text(for: capture.range) else { return false }
                    let range = NSRange(0..<text.utf16.count)
                    let matched = regex.firstMatch(in: text, range: range) != nil
                    if matched == negated { return false }
                }

            case .eq, .notEq, .anyOf, .notAnyOf:
                for capture in predicate.captures(in: match) {
                    guard let text = text(for: capture.range) else { return false }
                    if !predicate.evalulate(with: text) { return false }
                }
            }
        }

        return true
    }

    /// Capture names in `match` that carry a genuine constraint.
    ///
    /// A predicate-guarded capture is by construction more specific than an
    /// unguarded one over the same node, and ``HighlightPriority`` ranks it higher.
    /// `#set!` directives are excluded: they attach metadata, not a constraint.
    static func constrainedCaptureNames(in match: QueryMatch) -> Set<String> {
        var names: Set<String> = []

        for predicate in match.predicates {
            switch predicate {
            case .set, .generic:
                continue
            case .eq, .notEq, .match, .notMatch, .anyOf, .notAnyOf, .isNot:
                names.formUnion(predicate.captureNames)
            }
        }

        return names
    }

    private func text(for range: NSRange) -> String? {
        guard range.location >= 0,
              range.length >= 0,
              range.location + range.length <= utf16.count
        else { return nil }

        return String(decoding: utf16[range.location..<(range.location + range.length)], as: UTF16.self)
    }

    private mutating func compiled(from expression: NSRegularExpression) -> NSRegularExpression {
        let original = expression.pattern
        if let cached = regexCache[original] { return cached }

        let translated = LuaPattern.translatedToICU(original)
        let regex: NSRegularExpression
        if translated == original {
            regex = expression
        } else if let candidate = try? NSRegularExpression(pattern: translated, options: expression.options) {
            regex = candidate
        } else {
            // Translation produced something ICU rejects — the original at least
            // compiled, so use it rather than dropping the predicate entirely.
            regex = expression
        }

        regexCache[original] = regex
        return regex
    }
}

/// Converts the Lua-pattern character classes used by nvim-treesitter `#match?`
/// arguments into ICU regular-expression syntax.
///
/// This handles the `%x` escape family, which is the whole of the difference that
/// matters for the vendored queries. Lua's positional captures (`%1`), balanced
/// match (`%b`), and frontier pattern (`%f`) are not translated — no shipped query
/// uses them, and silently mistranslating them would be worse than leaving them.
/// Uppercase complements (`%D`, `%S`, …) are translated outside character classes
/// only; inside a class ICU has no direct spelling for them.
enum LuaPattern {

    /// Class bodies, written so they are valid both inside and outside `[...]`.
    private static let classBodies: [Character: String] = [
        "d": "0-9",
        "a": "A-Za-z",
        "w": "0-9A-Za-z",
        "l": "a-z",
        "u": "A-Z",
        "s": " \\t\\n\\r\\f\\u000B",
        "x": "0-9A-Fa-f",
        "c": "\\u0000-\\u001F\\u007F",
        "g": "\\u0021-\\u007E",
        "p": "\\p{P}\\p{S}",
    ]

    /// Translates `pattern`, returning it unchanged when it contains no `%`.
    static func translatedToICU(_ pattern: String) -> String {
        guard pattern.contains("%") else { return pattern }

        var output = ""
        var insideClass = false
        var iterator = pattern.makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let value = pending { pending = nil; return value }
            return iterator.next()
        }

        while let character = next() {
            switch character {
            case "\\":
                // Preserve an existing ICU escape verbatim.
                output.append(character)
                if let escaped = next() { output.append(escaped) }

            case "[" where !insideClass:
                insideClass = true
                output.append(character)

            case "]" where insideClass:
                insideClass = false
                output.append(character)

            case "%":
                guard let escaped = next() else {
                    output.append("%")
                    continue
                }

                let lowered = escaped.lowercased()
                let key = lowered.count == 1 ? Character(lowered) : escaped

                if let body = classBodies[key] {
                    let isComplement = escaped.isUppercase
                    if insideClass {
                        // No ICU spelling for a complement inside a class; emit the
                        // positive body and leave the (unused) complement case alone.
                        output.append(body)
                    } else {
                        output.append(isComplement ? "[^\(body)]" : "[\(body)]")
                    }
                } else if escaped.isLetter || escaped.isNumber {
                    // %b, %f, %1 … — unsupported, passed through as-is.
                    output.append("%")
                    output.append(escaped)
                } else {
                    // Lua escapes a magic character with `%`; ICU uses `\`.
                    output.append("\\")
                    output.append(escaped)
                }

            default:
                output.append(character)
            }
        }

        return output
    }
}
