import Foundation

/// Semantic role of a highlighted span. The package emits roles, never colors —
/// color resolution happens in `EditorTheme.color(for:on:)` against the live
/// `SurfaceCondition` (D-003).
///
/// Fidelity contract (D-008): every case of glassdb's `SQLTokenKind` maps to a
/// distinct `TokenRole` and back, losslessly. The ten SQL cases are
/// keyword, function, string, number, comment, identifier, operator, punctuation,
/// plain, and error — each has a dedicated case below. Additional cases exist for
/// grammars richer than SQL; they never collide with the SQL ten.
public enum TokenRole: String, Sendable, Hashable, Codable, CaseIterable {
    // The SQL ten — lossless SQLTokenKind coverage.
    case keyword
    case function
    case string
    case number
    case comment
    case identifier
    case `operator`
    case punctuation
    case plain
    case error

    // Richer-grammar roles.
    case type
    case variable
    case property
    case parameter
    case constant
    case boolean
    case label
    case attribute
    case embedded
    case markupHeading
    case markupEmphasis
    case markupStrong
    case markupLink
    case markupCode
    case markupList
}

/// A contiguous span of text carrying one semantic role.
///
/// Ranges are **UTF-16 code-unit offsets** into the document — the native unit
/// of `NSRange`, TextKit 2, and SwiftTreeSitter's UTF-16 parse mode. All public
/// range-bearing API in this package uses the same unit; nothing mixes units.
public struct HighlightRun: Sendable, Hashable {
    public var range: Range<Int>
    public var role: TokenRole

    public init(range: Range<Int>, role: TokenRole) {
        self.range = range
        self.role = role
    }
}
