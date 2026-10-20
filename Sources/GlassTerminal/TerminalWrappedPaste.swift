//
//  TerminalWrappedPaste.swift
//  Glass Power Tools — GlassTerminal
//
//  Text a terminal program wrapped to fit its window, joined again (the owner, 2026-10-19: copying
//  from Claude "will 100% of the time break the text on new lines"). The paste review offers it.
//

import Foundation

/// A program that lays out prose in a terminal — Claude Code, Codex, a man page — breaks it into lines
/// as wide as the window and indents each continuation under the first line's text. Copied, each
/// break is a newline, and pasted, each newline is Return. Three things together say a break is one
/// of those and not the writer's:
///
/// 1. **A width.** The text was laid out `width` columns wide: its widest line, trailing spaces
///    counted, since a program pads a line to its margin (the owner's example: 134 columns, the second
///    line 130 and four spaces). Under 40 columns nothing is joined; it can't be told from a list of
///    commands.
/// 2. **The wrap rule.** A line breaks only where the next word would not fit: the line, a space and
///    the next line's first word are wider than `width`. A line that stops short of that ended there
///    on purpose.
/// 3. **The hanging indent.** A continuation starts exactly under the first line's text — past its
///    indent and its bullet ("• ", "⏺ ", "- ", "1. ") — and doesn't start an item of its own. A line
///    with neither indent nor bullet has no continuations: that is how commands look.
///
/// Never across a blank line, inside a fenced code block, at a table's border, or after a line
/// ending in "\" (the shell's own continuation).
///
/// One case it can't tell: two lines under a bullet where the first is the widest in the paste and
/// the second is short. The width can only be read from the widest line, so the break after it always
/// looks wrapped. The review shows the joined text, and its checkbox puts the lines back.
enum TerminalWrappedPaste {
    struct Repair: Equatable {
        /// The text with its wrapped lines joined, and no line's trailing spaces.
        let text: String
        /// The columns it was wrapped at.
        let width: Int
        let originalLineCount: Int
        let lineCount: Int
    }

    static let minimumWidth = 40

    /// The terminal's `pasteRewrite`: the joined text while Join Wrapped Lines is on.
    @MainActor
    static func rewrite(settings: SettingsManager) -> (String) -> String? {
        { [weak settings] text in
            guard settings?.joinsWrappedPastes == true else { return nil }
            return repair(text)?.text
        }
    }

    /// `text` with the lines a terminal wrapped joined again, or nil when no line in it looks wrapped.
    static func repair(_ text: String) -> Repair? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > 1 else { return nil }
        let width = lines.map { cellWidth($0) }.max() ?? 0
        guard width >= minimumWidth else { return nil }

        var output: [String] = []
        var hangingIndent: Int?
        var previous = ""
        /// Columns the previous line had on screen that the copy left out: its indent, when the copy
        /// began inside a paragraph.
        var previousOffset = 0
        var inFence = false
        var joins = 0
        for (index, line) in lines.enumerated() {
            let content = trimmingTrailingWhitespace(line)
            let indent = leadingSpaces(content)
            let body = content.dropFirst(indent)
            let isFence = body.hasPrefix("```") || body.hasPrefix("~~~")

            if !inFence, !isFence, let hangingIndent, !output.isEmpty,
               continues(previous, offset: previousOffset, with: body, indent: indent,
                         hangingIndent: hangingIndent, width: width) {
                // A link broken at the margin is one word: no space where it broke.
                let separator = brokenLink(previous, offset: previousOffset, width: width) ? "" : " "
                output[output.count - 1] += separator + body
                previous = content
                previousOffset = 0
                joins += 1
                continue
            }

            output.append(content)
            previous = content
            previousOffset = 0
            if isFence { inFence.toggle() }
            hangingIndent = inFence || isFence ? nil : self.hangingIndent(of: body, indent: indent)
            // The copy began inside a paragraph, past its indent: the next line's indent is the
            // paragraph's.
            if index == 0, hangingIndent == nil, indent == 0, lines.count > 1 {
                let next = leadingSpaces(trimmingTrailingWhitespace(lines[1]))
                hangingIndent = next > 0 ? next : nil
                previousOffset = next
            }
        }
        guard joins > 0 else { return nil }
        return Repair(text: output.joined(separator: "\n"), width: width,
                      originalLineCount: lines.count, lineCount: output.count)
    }

    // MARK: - The three tests

    private static func continues(_ previous: String, offset: Int, with body: Substring, indent: Int,
                                  hangingIndent: Int, width: Int) -> Bool {
        guard !previous.isEmpty, !body.isEmpty, indent == hangingIndent,
              !previous.hasSuffix("\\"),
              itemMarkerLength(body) == nil,
              !startsOrEndsFrame(body), !startsOrEndsFrame(Substring(previous)),
              let firstWord = body.split(separator: " ", maxSplits: 1).first else { return false }
        return offset + cellWidth(previous) + 1 + cellWidth(firstWord) > width
    }

    /// Where a paragraph's continuations start: past its indent and bullet. Nil for a line with
    /// neither, which has none.
    private static func hangingIndent(of body: Substring, indent: Int) -> Int? {
        guard !body.isEmpty, !startsOrEndsFrame(body) else { return nil }
        if let marker = itemMarkerLength(body) { return indent + marker }
        return indent > 0 ? indent : nil
    }

    /// The length of a list item's bullet or number and the spaces after it: "• ", "⏺ ", "⎿  ",
    /// "- ", "12. ", "3) ". Nil when the line doesn't start one.
    private static func itemMarkerLength(_ body: Substring) -> Int? {
        var marker = 0
        if let first = body.first, bullets.contains(first) {
            marker = 1
        } else {
            let digits = body.prefix { $0.isASCII && $0.isNumber }
            guard (1...3).contains(digits.count), let after = body.dropFirst(digits.count).first,
                  after == "." || after == ")" else { return nil }
            marker = digits.count + 1
        }
        let spaces = body.dropFirst(marker).prefix { $0 == " " }.count
        guard spaces > 0, body.count > marker + spaces else { return nil }
        return marker + spaces
    }

    private static let bullets: Set<Character> = ["•", "◦", "▪", "‣", "⏺", "●", "○", "■", "□", "-", "*", "+",
                                                  "–", "—", "⎿", "→", "✓", "✔", "✗", "✘"]

    /// A table's row or border — box drawing, or "|" and "+" as Markdown and plain-text tables draw
    /// them — whose lines are as wide as each other on purpose.
    private static func startsOrEndsFrame(_ text: Substring) -> Bool {
        func isFrame(_ character: Character?) -> Bool {
            guard let scalar = character?.unicodeScalars.first else { return false }
            return (0x2500...0x257F).contains(scalar.value) || character == "|"
                || (character == "+" && text.contains("-+"))
        }
        let trimmed = text.drop { $0 == " " }
        return isFrame(trimmed.first) || isFrame(trimmed.last)
    }

    /// A line that runs to the margin and ends in a link's text: the link went on to the next line.
    private static func brokenLink(_ line: String, offset: Int, width: Int) -> Bool {
        offset + cellWidth(line) == width && (line.split(separator: " ").last?.contains("://") ?? false)
    }

    // MARK: - Columns

    private static func trimmingTrailingWhitespace(_ line: String) -> String {
        var line = Substring(line)
        while let last = line.last, last == " " || last == "\t" { line = line.dropLast() }
        return String(line)
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    /// The columns a terminal gives `text`: two for a wide character — CJK, Hangul, fullwidth forms,
    /// most emoji — none for a combining mark or joiner, one for the rest.
    static func cellWidth<Text: StringProtocol>(_ text: Text) -> Int {
        text.unicodeScalars.reduce(0) { $0 + columns($1) }
    }

    private static func columns(_ scalar: Unicode.Scalar) -> Int {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format: return 0
        default: break
        }
        let value = scalar.value
        if (0xFE00...0xFE0F).contains(value) { return 0 }
        let wide: [ClosedRange<UInt32>] = [
            0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
            0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
            0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD,
        ]
        return wide.contains { $0.contains(value) } ? 2 : 1
    }
}
