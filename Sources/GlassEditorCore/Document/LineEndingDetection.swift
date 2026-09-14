import Foundation

/// How many of each line terminator a document actually contains.
///
/// Surfaced as a public value because "this file mixes CRLF and LF" is a fact
/// the UI should be able to show with numbers, not just a `.mixed` label.
public struct LineEndingCounts: Sendable, Hashable, Codable {
    public var crlf: Int
    public var lf: Int
    public var cr: Int

    public init(crlf: Int = 0, lf: Int = 0, cr: Int = 0) {
        self.crlf = crlf
        self.lf = lf
        self.cr = cr
    }

    public var total: Int { crlf + lf + cr }
    public var isMixed: Bool { [crlf, lf, cr].filter { $0 > 0 }.count > 1 }
}

/// Stateless line-ending detection and explicit conversion
/// (projectRules.md, Naming).
///
/// **The buffer is never normalized on load.** Content is stored exactly as
/// decoded, terminators included, so a CRLF file saves as CRLF and a file that
/// mixes styles keeps every existing ending byte-for-byte (projectRules.md,
/// Data Safety). The detected `LineEndingStyle` only decides what a *newly
/// typed* line break inserts, via `LineEndingStyle.newlineString`. Display-time
/// handling of CR and CRLF belongs to the editor engine, not to storage.
///
/// ``normalize(_:to:)`` exists for the one case where rewriting terminators is
/// correct: the user explicitly asked to convert the document.
public enum LineEndingDetector: Sendable {

    /// Count each terminator form. `\r\n` counts once as CRLF, never as a CR
    /// plus an LF.
    ///
    /// Iterates unicode scalars rather than `Character`s because Swift treats
    /// `"\r\n"` as a single grapheme cluster, which would make a
    /// `Character`-level scan unable to see the two components at all.
    public static func counts(in content: String) -> LineEndingCounts {
        var counts = LineEndingCounts()
        var pendingCR = false

        for scalar in content.unicodeScalars {
            switch scalar {
            case "\r":
                if pendingCR { counts.cr += 1 }
                pendingCR = true
            case "\n":
                if pendingCR {
                    counts.crlf += 1
                    pendingCR = false
                } else {
                    counts.lf += 1
                }
            default:
                if pendingCR {
                    counts.cr += 1
                    pendingCR = false
                }
            }
        }
        if pendingCR { counts.cr += 1 }
        return counts
    }

    /// The line-ending style of `content`.
    ///
    /// Uniform content reports that single style. Mixed content reports
    /// `.mixed(dominant:)` where the dominant style is the most frequent one;
    /// ties resolve toward LF, then CRLF, then CR.
    ///
    /// Content with **no** line terminator at all — empty documents, a new
    /// scratch buffer, a single unterminated line — reports `.lf`. There is no
    /// evidence to detect from, and LF is the platform default on every OS this
    /// package targets. This is the one place the module returns a default
    /// rather than modeling "unknown": the value is only consulted when the user
    /// types their first line break, at which point any answer is a fresh
    /// choice rather than a claim about the file.
    public static func detect(in content: String) -> LineEndingStyle {
        let counts = counts(in: content)
        guard counts.total > 0 else { return .lf }

        guard counts.isMixed else {
            if counts.crlf > 0 { return .crlf }
            if counts.cr > 0 { return .cr }
            return .lf
        }

        let maximum = max(counts.lf, counts.crlf, counts.cr)
        if counts.lf == maximum { return .mixed(dominant: .lf) }
        if counts.crlf == maximum { return .mixed(dominant: .crlf) }
        return .mixed(dominant: .cr)
    }

    /// Rewrite every line terminator in `content` to `style`.
    ///
    /// **Only for an explicit, user-initiated conversion.** Nothing in the open
    /// or save path calls this; doing so would silently rewrite bytes the user
    /// never touched, which is exactly the failure mode the Data Safety rule
    /// forbids.
    ///
    /// For `.mixed(dominant:)` the dominant style is used, which makes the
    /// document uniform — converting *to* mixed is not a meaningful operation.
    /// Only CR, LF, and CRLF are treated as terminators; U+2028, U+2029, and
    /// U+0085 are left untouched, because rewriting them would change text the
    /// user sees as content rather than as structure.
    public static func normalize(_ content: String, to style: LineEndingStyle) -> String {
        let replacement = style.newlineString
        var out = String()
        out.reserveCapacity(content.unicodeScalars.count)

        var pendingCR = false
        for scalar in content.unicodeScalars {
            switch scalar {
            case "\r":
                if pendingCR { out += replacement }
                pendingCR = true
            case "\n":
                out += replacement
                pendingCR = false
            default:
                if pendingCR {
                    out += replacement
                    pendingCR = false
                }
                out.unicodeScalars.append(scalar)
            }
        }
        if pendingCR { out += replacement }
        return out
    }
}
