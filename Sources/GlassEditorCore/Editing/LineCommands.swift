import Foundation

/// The line commands (2026-11-22): comment, duplicate, move, delete, join and sort lines. Each is one undo step, named
/// for it (`EditIntent.lineCommand`).
public enum LineCommand: String, Sendable, Hashable, CaseIterable {
    case comment
    case duplicate
    case moveUp
    case moveDown
    case delete
    case join
    case sort

    /// What Undo calls it: "Undo Comment", "Undo Move Lines".
    public var undoName: String {
        switch self {
        case .comment: "Comment"
        case .duplicate: "Duplicate Lines"
        case .moveUp, .moveDown: "Move Lines"
        case .delete: "Delete Lines"
        case .join: "Join Lines"
        case .sort: "Sort Lines"
        }
    }
}

public extension LanguageID {
    /// What starts a line comment; nil where the language has none (JSON) or only block comments.
    var lineComment: String? {
        switch self {
        case .swift, .javascript, .go, .rust, .c, .php: "//"
        case .bash, .yaml, .toml, .python: "#"
        case .sql: "--"
        case .json, .markdown, .xml, .html, .plaintext: nil
        }
    }

    /// The block comment a language without line comments has.
    var blockComment: (open: String, close: String)? {
        switch self {
        case .markdown, .xml, .html: ("<!--", "-->")
        default: nil
        }
    }
}

extension LineEditing {

    // MARK: Moving offsets through a change

    /// Part of a change: at `at` in the old text, `removed` code units out and `inserted` in.
    struct Splice: Sendable, Hashable {
        var at: Int
        var removed: Int
        var inserted: Int
    }

    /// Where `offset` is once `splices` (none overlapping) are made. An offset inside removed text goes to the end of
    /// what replaced it; one exactly where text is inserted moves past it unless `keepsBefore`, which a selection's
    /// start does so it takes the new text in.
    static func moved(_ offset: Int, through splices: [Splice], keepsBefore: Bool) -> Int {
        var shift = 0
        for splice in splices.sorted(by: { $0.at < $1.at }) {
            let end = splice.at + splice.removed
            if end < offset || (end == offset && (splice.removed > 0 || !keepsBefore)) {
                shift += splice.inserted - splice.removed
            } else if splice.at < offset {
                return splice.at + shift + splice.inserted
            } else {
                break
            }
        }
        return offset + shift
    }

    /// The selection after `splices`, and the one edit over `block` that makes them.
    static func lineEdit(_ block: [Line], in text: NSString, splices: [Splice], texts: [Int: String],
                         selection: Range<Int>) -> LineEdit {
        let start = block.first?.start ?? 0
        let output = NSMutableString(string: text.substring(with: NSRange(location: start,
                                                                          length: (block.last?.end ?? 0) - start)))
        for splice in splices.sorted(by: { $0.at > $1.at }) {
            output.replaceCharacters(in: NSRange(location: splice.at - start, length: splice.removed),
                                     with: texts[splice.at] ?? "")
        }
        let lower = moved(selection.lowerBound, through: splices, keepsBefore: !selection.isEmpty)
        let upper = selection.isEmpty ? lower : moved(selection.upperBound, through: splices, keepsBefore: false)
        return LineEdit(edit: blockEdit(block, output as String), selection: lower..<max(lower, upper))
    }

    // MARK: Comment

    /// ⌘/: comments the selection's lines out, or back in when every one with text already is. Line comments go at the
    /// shallowest indent among them, followed by a space; a language with only block comments (HTML, XML, Markdown)
    /// wraps the lines in one. Lines with nothing but whitespace are left alone. Nil for a language with no comments.
    public static func toggleComment(_ text: NSString, selection: Range<Int>, language: LanguageID) -> LineEdit? {
        let selection = clamped(selection, in: text)
        let block = lines(in: text, covering: selection)
        let filled = block.filter { line in content(of: line, in: text).contains { $0 != " " && $0 != "\t" } }
        guard !filled.isEmpty else { return nil }
        var splices: [Splice] = []
        var texts: [Int: String] = [:]
        func splice(at: Int, removing: Int, inserting: String) {
            splices.append(Splice(at: at, removed: removing, inserted: (inserting as NSString).length))
            texts[at] = inserting
        }

        if let token = language.lineComment {
            let tokenLength = (token as NSString).length
            let leads = filled.map { (leadingWhitespace(of: $0, in: text) as NSString).length }
            let commented = zip(filled, leads).allSatisfy { line, lead in
                content(of: line, in: text).dropFirst(lead).hasPrefix(token)
            }
            if commented {
                for (line, lead) in zip(filled, leads) {
                    let after = content(of: line, in: text).dropFirst(lead + tokenLength)
                    splice(at: line.start + lead, removing: tokenLength + (after.hasPrefix(" ") ? 1 : 0), inserting: "")
                }
            } else {
                let column = leads.min() ?? 0
                for line in filled { splice(at: line.start + column, removing: 0, inserting: token + " ") }
            }
        } else if let pair = language.blockComment, let first = filled.first, let last = filled.last {
            // UTF-16 throughout, as offsets are: a character count would drift past an emoji.
            let firstContent = content(of: first, in: text) as NSString
            let lastContent = content(of: last, in: text) as NSString
            let lead = (leadingWhitespace(of: first, in: text) as NSString).length
            var trimmedEnd = lastContent.length
            while trimmedEnd > 0, [0x20, 0x09].contains(lastContent.character(at: trimmedEnd - 1)) { trimmedEnd -= 1 }
            let open = (pair.open as NSString).length, close = (pair.close as NSString).length
            let opened = firstContent.substring(from: lead).hasPrefix(pair.open)
            let closed = lastContent.substring(to: trimmedEnd).hasSuffix(pair.close)
            let roomForBoth = first.start != last.start || trimmedEnd - lead >= open + close
            if opened && closed && roomForBoth {
                let spaceAfter = firstContent.substring(from: lead + open).hasPrefix(" ") ? 1 : 0
                let closeAt = trimmedEnd - close
                let spaceBefore = closeAt > lead + open && lastContent.substring(to: closeAt).hasSuffix(" ") ? 1 : 0
                splice(at: first.start + lead, removing: open + spaceAfter, inserting: "")
                splice(at: last.start + closeAt - spaceBefore, removing: close + spaceBefore, inserting: "")
            } else {
                splice(at: first.start + lead, removing: 0, inserting: pair.open + " ")
                splice(at: last.start + trimmedEnd, removing: 0, inserting: " " + pair.close)
            }
        } else {
            return nil
        }
        return lineEdit(block, in: text, splices: splices, texts: texts, selection: selection)
    }

    // MARK: Duplicate, move, delete

    /// The lines again, below themselves, and the selection on the copy.
    public static func duplicate(_ text: NSString, selection: Range<Int>) -> LineEdit {
        let selection = clamped(selection, in: text)
        let block = lines(in: text, covering: selection)
        let start = block.first?.start ?? 0, end = block.last?.end ?? 0
        let copied = text.substring(with: NSRange(location: start, length: end - start))
        // The last line of a file has no break of its own: the copy starts with the file's.
        let lineBreak = block.last?.terminator.isEmpty == true ? firstLineBreak(in: text) : ""
        let shift = (copied as NSString).length + (lineBreak as NSString).length
        return LineEdit(edit: TextEdit(replacementRange: end..<end, text: lineBreak + copied),
                        selection: (selection.lowerBound + shift)..<(selection.upperBound + shift))
    }

    /// The file's first line break, or "\n" in a file of one line.
    static func firstLineBreak(in text: NSString) -> String {
        let first = line(at: 0, in: text)
        return first.terminator.isEmpty ? "\n" : first.terminator
    }

    /// The lines swapped with the one above (`up`) or below, each line's break staying where it was so the file's last
    /// line keeps having none. Nil at the top or the bottom.
    public static func move(_ text: NSString, selection: Range<Int>, up: Bool) -> LineEdit? {
        let selection = clamped(selection, in: text)
        let block = lines(in: text, covering: selection)
        guard let first = block.first, let last = block.last else { return nil }
        let region: [Line]
        let order: [Int]
        if up {
            guard first.start > 0 else { return nil }
            region = [line(at: first.start - 1, in: text)] + block
            order = Array(1..<region.count) + [0]
        } else {
            guard !last.terminator.isEmpty else { return nil }
            region = block + [line(at: last.end, in: text)]
            order = [region.count - 1] + Array(0..<(region.count - 1))
        }
        let contents = region.map { content(of: $0, in: text) }
        let breaks = region.map(\.terminator)
        let lengths = contents.map { ($0 as NSString).length }
        let breakLengths = breaks.map { ($0 as NSString).length }
        var output = ""
        var newStarts = [Int](repeating: 0, count: region.count)   // by old index
        var position = region[0].start
        for (slot, old) in order.enumerated() {
            newStarts[old] = position
            output += contents[old] + breaks[slot]
            position += lengths[old] + breakLengths[slot]
        }
        let newSlot = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })

        // An offset as (line, column); a selection's end at a line's start belongs to the line before.
        func moved(_ offset: Int, endAffinity: Bool) -> Int {
            var index = region.lastIndex { $0.start <= offset } ?? 0
            if endAffinity, index > 0, region[index].start == offset { index -= 1 }
            let column = offset - region[index].start
            let full = lengths[index] + breakLengths[newSlot[index]!]
            return newStarts[index] + min(column, full)
        }
        let lower = moved(selection.lowerBound, endAffinity: false)
        let upper = selection.isEmpty ? lower : moved(selection.upperBound, endAffinity: true)
        return LineEdit(edit: TextEdit(replacementRange: region[0].start..<(region.last!.end), text: output),
                        selection: lower..<max(lower, upper))
    }

    /// The lines gone, breaks and all; on the file's last line, the break before it goes instead. The caret where they
    /// were. Nil in an empty file.
    public static func delete(_ text: NSString, selection: Range<Int>) -> LineEdit? {
        let selection = clamped(selection, in: text)
        let block = lines(in: text, covering: selection)
        guard let first = block.first, let last = block.last else { return nil }
        var start = first.start
        if last.terminator.isEmpty, start > 0 { start = line(at: start - 1, in: text).contentEnd }
        guard last.end > start else { return nil }
        return LineEdit(edit: TextEdit(replacementRange: start..<last.end, text: ""), selection: start..<start)
    }

    // MARK: Join and sort

    /// The selection's lines as one, each joined by a space with its leading whitespace gone; a caret's line takes
    /// the next. Nil when there is nothing to join.
    public static func join(_ text: NSString, selection: Range<Int>) -> LineEdit? {
        let selection = clamped(selection, in: text)
        var block = lines(in: text, covering: selection)
        guard let first = block.first else { return nil }
        if block.count == 1 {
            guard !first.terminator.isEmpty else { return nil }
            block.append(line(at: first.end, in: text))
        }
        var joined = content(of: first, in: text)
        var joinPoint: Int?
        for line in block.dropFirst() {
            while joined.last == " " || joined.last == "\t" { joined.removeLast() }
            if joinPoint == nil { joinPoint = (joined as NSString).length }
            let piece = String(content(of: line, in: text).drop { $0 == " " || $0 == "\t" })
            guard !piece.isEmpty else { continue }
            joined += (joined.isEmpty ? "" : " ") + piece
        }
        let output = joined + (block.last?.terminator ?? "")
        let original = text.substring(with: NSRange(location: first.start, length: (block.last?.end ?? 0) - first.start))
        guard output != original else { return nil }
        let point = first.start + (joinPoint ?? 0)
        let selected = selection.isEmpty ? point..<point : first.start..<(first.start + (joined as NSString).length)
        return LineEdit(edit: blockEdit(block, output), selection: selected)
    }

    /// The selection's lines in order, as Finder orders names (numbers by value, case aside); each line's break stays
    /// where it was. Nil for one line, or lines already in order.
    public static func sort(_ text: NSString, selection: Range<Int>) -> LineEdit? {
        let selection = clamped(selection, in: text)
        let block = lines(in: text, covering: selection)
        guard block.count > 1, let first = block.first else { return nil }
        let contents = block.map { content(of: $0, in: text) }
        let sorted = contents.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard sorted != contents else { return nil }
        let breaks = block.map(\.terminator)
        let output = zip(sorted, breaks).map { $0 + $1 }.joined()
        let selected = (output as NSString).length - ((breaks.last ?? "") as NSString).length
        return LineEdit(edit: blockEdit(block, output), selection: first.start..<(first.start + selected))
    }
}
