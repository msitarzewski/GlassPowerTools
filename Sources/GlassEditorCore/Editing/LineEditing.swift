import Foundation

/// One change a line command makes, and where the selection goes after it: a single edit over whole lines, so a
/// command is one undo step and the buffer, the view and the undo stack see the same thing.
public struct LineEdit: Sendable, Hashable {
    public var edit: TextEdit
    /// In the text as it is after the edit.
    public var selection: Range<Int>

    public init(edit: TextEdit, selection: Range<Int>) {
        self.edit = edit
        self.selection = selection
    }
}

/// What Return, Tab and the line commands do to text (2026-11-22). Pure: text and a selection in, an edit out, the
/// same for the Mac's text view and UIKit's, and testable without either. Offsets are UTF-16, as the buffer's are.
public enum LineEditing {

    // MARK: Lines

    /// One line: where it starts, how long its text is, and what ends it ("" for the last line of a file without one).
    public struct Line: Sendable, Hashable {
        public var start: Int
        public var contentLength: Int
        public var terminator: String
        public var contentEnd: Int { start + contentLength }
        public var end: Int { start + contentLength + (terminator as NSString).length }
    }

    /// The whole lines a selection touches. A selection that ends at the very start of a line does not take that line:
    /// selecting three lines down to the next line's start is three lines, as every editor has it.
    public static func lines(in text: NSString, covering selection: Range<Int>) -> [Line] {
        let length = text.length
        let lower = min(max(selection.lowerBound, 0), length)
        var upper = min(max(selection.upperBound, lower), length)
        if upper > lower, line(at: upper, in: text).start == upper { upper -= 1 }
        var result: [Line] = []
        var position = lower
        while true {
            let line = line(at: position, in: text)
            result.append(line)
            // The next line starts where this one ends; it is in when the selection reaches it.
            guard !line.terminator.isEmpty, line.end <= upper else { break }
            position = line.end
        }
        return result
    }

    /// The line holding `offset`. After a file's last line break, the empty line there.
    public static func line(at offset: Int, in text: NSString) -> Line {
        var start = 0, end = 0, contentsEnd = 0
        let location = min(max(offset, 0), text.length)
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        let terminator = text.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd))
        return Line(start: start, contentLength: contentsEnd - start, terminator: terminator)
    }

    /// The text of a line, without its terminator.
    static func content(of line: Line, in text: NSString) -> String {
        text.substring(with: NSRange(location: line.start, length: line.contentLength))
    }

    /// A line's leading spaces and tabs.
    static func leadingWhitespace(of line: Line, in text: NSString) -> String {
        let content = content(of: line, in: text)
        return String(content.prefix { $0 == " " || $0 == "\t" })
    }

    // MARK: Return

    /// What Return types at the selection: a line break, then the line's own indentation, so the next line starts
    /// where this one did. In code (not plain text or Markdown) a line ending in `{`, `[` or `(` takes one level more,
    /// and when the matching closer is right after the caret it goes down to a line of its own, at the old level, with
    /// the caret on the line between. Python and YAML take a level more after a `:`.
    ///
    /// - Returns: the text to insert in place of the selection, and where in it the caret goes.
    public static func newline(in text: NSString, replacing selection: Range<Int>, indentation: Indentation,
                               language: LanguageID) -> (text: String, caret: Int) {
        let caret = min(max(selection.lowerBound, 0), text.length)
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        let beforeCaret = text.substring(with: NSRange(location: start, length: caret - start))
        let lead = String(beforeCaret.prefix { $0 == " " || $0 == "\t" })

        let afterStart = min(max(selection.upperBound, caret), contentsEnd)
        let afterCaret = afterStart < contentsEnd
            ? text.substring(with: NSRange(location: afterStart, length: contentsEnd - afterStart)) : ""
        let last = beforeCaret.last { $0 != " " && $0 != "\t" }
        let next = afterCaret.first { $0 != " " && $0 != "\t" }

        let opensBlock: Bool
        var closer: Character?
        switch last {
        case "{" where language.indentsAfterBrackets: opensBlock = true; closer = "}"
        case "[" where language.indentsAfterBrackets: opensBlock = true; closer = "]"
        case "(" where language.indentsAfterBrackets: opensBlock = true; closer = ")"
        case ":" where language == .python || language == .yaml: opensBlock = true
        default: opensBlock = false
        }
        guard opensBlock else {
            let inserted = "\n" + lead
            return (inserted, (inserted as NSString).length)
        }
        let deeper = "\n" + lead + indentation.unit
        if let closer, next == closer {
            return (deeper + "\n" + lead, (deeper as NSString).length)
        }
        return (deeper, (deeper as NSString).length)
    }

    // MARK: Tab

    /// What Tab types with a caret or a selection inside one line: a tab, or with spaces as many as reach the next
    /// tab stop, so a column lines up whatever was before it.
    public static func tab(in text: NSString, at offset: Int, indentation: Indentation) -> String {
        guard indentation.kind == .spaces else { return "\t" }
        let column = visualColumn(in: text, at: offset, tabWidth: indentation.width)
        return String(repeating: " ", count: indentation.width - column % indentation.width)
    }

    /// The column `offset` is drawn at, a tab counting to the next multiple of `tabWidth`.
    public static func visualColumn(in text: NSString, at offset: Int, tabWidth: Int) -> Int {
        let clamped = min(max(offset, 0), text.length)
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: clamped, length: 0))
        var column = 0
        for unit in text.substring(with: NSRange(location: start, length: clamped - start)).utf16 {
            column = unit == 0x09 ? (column / tabWidth + 1) * tabWidth : column + 1
        }
        return column
    }

    /// Whether Tab should indent lines rather than type over the selection: the selection takes in a line break, as a
    /// whole line selected by a triple click does. Typing over that would delete the line.
    public static func selectionSpansLines(_ selection: Range<Int>, in text: NSString) -> Bool {
        guard !selection.isEmpty else { return false }
        return selection.upperBound > line(at: selection.lowerBound, in: text).contentEnd
    }

    // MARK: Indent and outdent

    /// One level more at the start of every line the selection touches; an empty line is left empty. The selection
    /// keeps the same text, and a selection of whole lines takes their new indentation in.
    public static func indent(_ text: NSString, selection: Range<Int>, indentation: Indentation) -> LineEdit? {
        let selection = clamped(selection, in: text)
        let block = lines(in: text, covering: selection)
        let unit = indentation.unit
        let unitLength = (unit as NSString).length
        var output = ""
        var insertions: [Int] = []
        for line in block {
            let content = content(of: line, in: text)
            if content.isEmpty {
                output += line.terminator
            } else {
                output += unit + content + line.terminator
                insertions.append(line.start)
            }
        }
        guard !insertions.isEmpty else { return nil }
        func moved(_ offset: Int, keepsBefore: Bool) -> Int {
            offset + insertions.reduce(0) { sum, at in
                at < offset || (at == offset && !keepsBefore) ? sum + unitLength : sum
            }
        }
        let lower = moved(selection.lowerBound, keepsBefore: !selection.isEmpty)
        let upper = selection.isEmpty ? lower : moved(selection.upperBound, keepsBefore: false)
        return LineEdit(edit: blockEdit(block, output), selection: lower..<max(lower, upper))
    }

    /// One level less from every line the selection touches: a tab, or up to a level's worth of spaces. Nothing when
    /// no line has any to take.
    public static func outdent(_ text: NSString, selection: Range<Int>, indentation: Indentation) -> LineEdit? {
        let selection = clamped(selection, in: text)
        let block = lines(in: text, covering: selection)
        var output = ""
        var removals: [(start: Int, length: Int)] = []
        for line in block {
            let content = content(of: line, in: text)
            var removed = 0
            if content.hasPrefix("\t") {
                removed = 1
            } else {
                removed = content.prefix(indentation.width).prefix { $0 == " " }.count
                if removed < indentation.width, content.dropFirst(removed).hasPrefix("\t") { removed += 1 }
            }
            output += String(content.dropFirst(removed)) + line.terminator
            if removed > 0 { removals.append((line.start, removed)) }
        }
        guard !removals.isEmpty else { return nil }
        func moved(_ offset: Int) -> Int {
            offset - removals.reduce(0) { sum, removal in
                if removal.start + removal.length <= offset { return sum + removal.length }
                if removal.start < offset { return sum + (offset - removal.start) }
                return sum
            }
        }
        let lower = moved(selection.lowerBound)
        let upper = moved(selection.upperBound)
        return LineEdit(edit: blockEdit(block, output), selection: lower..<max(lower, upper))
    }

    /// `selection` inside `text`: a range from a view is never trusted past the end of what the command reads.
    static func clamped(_ selection: Range<Int>, in text: NSString) -> Range<Int> {
        let lower = min(max(selection.lowerBound, 0), text.length)
        return lower..<min(max(selection.upperBound, lower), text.length)
    }

    /// The edit replacing `block` with `text`.
    static func blockEdit(_ block: [Line], _ text: String) -> TextEdit {
        TextEdit(replacementRange: (block.first?.start ?? 0)..<(block.last?.end ?? 0), text: text)
    }
}

public extension LanguageID {
    /// Whether a line ending in an opening bracket starts a deeper block. Not in prose.
    var indentsAfterBrackets: Bool { self != .plaintext && self != .markdown }
}
