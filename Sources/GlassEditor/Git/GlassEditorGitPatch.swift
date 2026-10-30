//
//  GlassEditorGitPatch.swift
//  Glass Power Tools — GlassEditor
//
//  Part of a diff as a patch of its own, for `git apply` (2026-10-28): how one hunk, or the lines
//  chosen in it, is staged, unstaged or thrown away — `git add -p` without the terminal, as Sublime
//  Merge, Fork and VS Code do it.
//
//  **The rule for chosen lines.** A patch must match the side it is applied to exactly. Applied
//  forwards (staging, from the working tree's diff against the index), its old side is the index:
//  a removed line not chosen stays there, so it becomes context, and an added line not chosen is
//  not there yet, so it is left out. Applied in reverse (unstaging from the staged diff, or
//  throwing lines away from the working tree's), its new side is what is there now: an added line
//  not chosen stays, as context, and a removed line not chosen is left out. Its counts are worked
//  out again from what is left.
//
//  Then word-level highlights inside a changed line, the rows of a diff side by side, and the
//  conflicts in a file that a merge stopped on.
//

import Foundation

public enum GlassEditorGitPatch {
    /// A patch of `hunk` of `file`, with only the lines at `chosen` (indexes in the hunk's lines)
    /// when given; nil when nothing chosen changes anything. `reverse` is how it will be applied.
    public static func patch(of file: GlassEditorFileDiff, hunk index: Int, chosen: Set<Int>? = nil,
                             reverse: Bool) -> String? {
        guard file.hunks.indices.contains(index), let old = file.oldPath, let new = file.newPath else { return nil }
        let hunk = file.hunks[index]
        var lines: [(sign: Character, text: String, noNewline: Bool)] = []
        var oldCount = 0, newCount = 0, changes = 0
        for (offset, line) in hunk.lines.enumerated() {
            let isChosen = chosen?.contains(offset) ?? true
            switch line.kind {
            case .context:
                lines.append((" ", line.text, line.noNewlineAtEnd))
                oldCount += 1; newCount += 1
            case .removed where isChosen:
                lines.append(("-", line.text, line.noNewlineAtEnd))
                oldCount += 1; changes += 1
            case .added where isChosen:
                lines.append(("+", line.text, line.noNewlineAtEnd))
                newCount += 1; changes += 1
            case .removed:
                // Not chosen: on the side the patch is matched against only when going forwards.
                if !reverse {
                    lines.append((" ", line.text, line.noNewlineAtEnd))
                    oldCount += 1; newCount += 1
                }
            case .added:
                if reverse {
                    lines.append((" ", line.text, line.noNewlineAtEnd))
                    oldCount += 1; newCount += 1
                }
            }
        }
        guard changes > 0 else { return nil }
        // A hunk's start is the line before it when it is empty on that side, as git writes it.
        let oldStart = oldCount == 0 ? max(hunk.oldStart, 0) : max(hunk.oldStart, 1)
        let newStart = newCount == 0 ? max(hunk.newStart, 0) : max(hunk.newStart, 1)
        var text = "diff --git \(name("a/", old)) \(name("b/", new))\n"
        text += "--- \(name("a/", old, ending: true))\n"
        text += "+++ \(name("b/", new, ending: true))\n"
        text += "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@\n"
        for line in lines {
            text += String(line.sign) + line.text + "\n"
            if line.noNewline { text += "\\ No newline at end of file\n" }
        }
        return text
    }

    /// Whether lines of `file` can be staged or thrown away a hunk or a line at a time: text whose
    /// two sides are the same file. A new, deleted, renamed or binary file goes whole.
    public static func canPatch(_ file: GlassEditorFileDiff) -> Bool {
        !file.isBinary && file.oldPath != nil && file.oldPath == file.newPath && !file.hunks.isEmpty
    }

    /// A path as git writes it in a patch's headers: in C quotes when it holds a quote, a backslash
    /// or a control character, and — on the `---` and `+++` lines — ended by a tab when it holds a
    /// space, so `git apply` reads where it ends.
    static func name(_ prefix: String, _ path: String, ending: Bool = false) -> String {
        let full = prefix + path
        let needsQuotes = full.unicodeScalars.contains { $0 == "\"" || $0 == "\\" || $0.value < 0x20 || $0.value == 0x7F }
        guard needsQuotes else { return ending && full.contains(" ") ? full + "\t" : full }
        var quoted = "\""
        for scalar in full.unicodeScalars {
            switch scalar {
            case "\"": quoted += "\\\""
            case "\\": quoted += "\\\\"
            case "\n": quoted += "\\n"
            case "\t": quoted += "\\t"
            case "\r": quoted += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    quoted += "\\" + String(scalar.value, radix: 8).leftPadded(to: 3)
                } else {
                    quoted.unicodeScalars.append(scalar)
                }
            }
        }
        return quoted + "\""
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}

// MARK: - Words

/// Which parts of a changed line changed: the words that differ between a removed line and the
/// added line that replaced it, as GitHub and Sublime Merge highlight them.
public enum GlassEditorWordDiff {
    /// The changed character ranges of `old` and `new` (offsets in `Character`s), or nil when the
    /// lines have too little in common for highlighting to help, or are too long to compare.
    public static func ranges(old: String, new: String) -> (old: [Range<Int>], new: [Range<Int>])? {
        let a = tokens(old), b = tokens(new)
        guard !a.isEmpty, !b.isEmpty, a.count * b.count <= 160_000 else { return nil }
        // The longest common run of tokens, by dynamic programming over the two lists.
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i].text == b[j].text ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var keptA = Set<Int>(), keptB = Set<Int>()
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i].text == b[j].text {
                keptA.insert(i); keptB.insert(j); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        // Too little in common: the whole line changed, and highlighting every word says nothing.
        let common = keptA.reduce(0) { $0 + a[$1].text.count }
        guard common * 10 >= max(old.count, new.count) * 3 else { return nil }
        return (merged(a, kept: keptA), merged(b, kept: keptB))
    }

    struct Token {
        var text: Substring
        var range: Range<Int>
    }

    /// Words, runs of spaces, and each other character on its own.
    static func tokens(_ line: String) -> [Token] {
        var tokens: [Token] = []
        var offset = 0
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            var end = line.index(after: index)
            if character.isLetter || character.isNumber || character == "_" {
                while end < line.endIndex, line[end].isLetter || line[end].isNumber || line[end] == "_" { end = line.index(after: end) }
            } else if character.isWhitespace {
                while end < line.endIndex, line[end].isWhitespace { end = line.index(after: end) }
            }
            let length = line.distance(from: index, to: end)
            tokens.append(Token(text: line[index..<end], range: offset..<(offset + length)))
            offset += length
            index = end
        }
        return tokens
    }

    /// The tokens not kept, as ranges, adjacent ones joined.
    private static func merged(_ tokens: [Token], kept: Set<Int>) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for (index, token) in tokens.enumerated() where !kept.contains(index) {
            if let last = ranges.last, last.upperBound == token.range.lowerBound {
                ranges[ranges.count - 1] = last.lowerBound..<token.range.upperBound
            } else {
                ranges.append(token.range)
            }
        }
        return ranges
    }

    /// For each line of a hunk, its changed ranges: a run of removed lines followed by a run of
    /// added ones is paired line by line, as most of a change is a line edited in place.
    public static func highlights(of hunk: GlassEditorDiffHunk) -> [Int: [Range<Int>]] {
        var result: [Int: [Range<Int>]] = [:]
        var index = 0
        let lines = hunk.lines
        while index < lines.count {
            guard lines[index].kind == .removed else { index += 1; continue }
            var removed: [Int] = []
            while index < lines.count, lines[index].kind == .removed { removed.append(index); index += 1 }
            var added: [Int] = []
            while index < lines.count, lines[index].kind == .added { added.append(index); index += 1 }
            for (old, new) in zip(removed, added) {
                guard let ranges = ranges(old: lines[old].text, new: lines[new].text) else { continue }
                if !ranges.old.isEmpty { result[old] = ranges.old }
                if !ranges.new.isEmpty { result[new] = ranges.new }
            }
        }
        return result
    }
}

// MARK: - Side by side

/// One row of a diff shown side by side: the old line on the left, the new on the right, either
/// missing where the other side has a line it doesn't.
public struct GlassEditorSplitRow: Equatable, Sendable {
    /// Indexes into the hunk's lines.
    public var left: Int?
    public var right: Int?

    /// Context on both sides; within a change, removed lines beside the added lines that replaced
    /// them, one for one, and what is left over beside nothing.
    public static func rows(of hunk: GlassEditorDiffHunk) -> [GlassEditorSplitRow] {
        var rows: [GlassEditorSplitRow] = []
        var index = 0
        let lines = hunk.lines
        while index < lines.count {
            if lines[index].kind == .context {
                rows.append(GlassEditorSplitRow(left: index, right: index))
                index += 1
                continue
            }
            var removed: [Int] = [], added: [Int] = []
            while index < lines.count, lines[index].kind == .removed { removed.append(index); index += 1 }
            while index < lines.count, lines[index].kind == .added { added.append(index); index += 1 }
            for row in 0..<max(removed.count, added.count) {
                rows.append(GlassEditorSplitRow(left: row < removed.count ? removed[row] : nil,
                                                right: row < added.count ? added[row] : nil))
            }
        }
        return rows
    }
}

// MARK: - Conflicts

/// A file a merge, a rebase, a cherry-pick or a stash stopped on: its text between the conflicts,
/// and each conflict's two sides (three, with `merge.conflictStyle diff3` or `zdiff3`).
public struct GlassEditorConflictFile: Equatable, Sendable {
    public struct Conflict: Equatable, Sendable {
        /// The branch's side (HEAD's), and what git called it.
        public var ours: [String]
        public var oursLabel: String
        /// What they had in common, when git wrote it.
        public var base: [String]?
        public var theirs: [String]
        public var theirsLabel: String
    }

    public enum Part: Equatable, Sendable {
        case text([String])
        case conflict(Conflict)
    }

    public enum Choice: Equatable, Sendable {
        case ours, theirs, oursThenTheirs, theirsThenOurs
    }

    public var parts: [Part]
    /// The file's line ending, kept when it is written back.
    public var lineEnding: String
    public var endsWithNewline: Bool

    public var conflicts: [Conflict] {
        parts.compactMap { if case .conflict(let conflict) = $0 { conflict } else { nil } }
    }

    /// Reads the markers git writes, seven characters each at the start of a line. A file with
    /// none has no conflicts left.
    public static func parse(_ text: String) -> GlassEditorConflictFile {
        let lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: lineEnding)
        let endsWithNewline = text.hasSuffix(lineEnding)
        if endsWithNewline { lines.removeLast() }
        var parts: [Part] = []
        var plain: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix("<<<<<<<"), let conflict = readConflict(lines, from: &index) else {
                plain.append(line)
                index += 1
                continue
            }
            if !plain.isEmpty { parts.append(.text(plain)); plain = [] }
            parts.append(.conflict(conflict))
        }
        if !plain.isEmpty { parts.append(.text(plain)) }
        return GlassEditorConflictFile(parts: parts, lineEnding: lineEnding, endsWithNewline: endsWithNewline)
    }

    /// One conflict from its `<<<<<<<` line; nil, and `index` unmoved, when its markers don't close.
    private static func readConflict(_ lines: [String], from index: inout Int) -> Conflict? {
        var cursor = index + 1
        var ours: [String] = [], base: [String]?, theirs: [String] = []
        var section = 0 // 0 ours, 1 base, 2 theirs
        while cursor < lines.count {
            let line = lines[cursor]
            if section < 2, line.hasPrefix("|||||||") {
                section = 1; base = []
            } else if section < 2, line == "=======" || line.hasPrefix("======= ") {
                section = 2
            } else if section == 2, line.hasPrefix(">>>>>>>") {
                let conflict = Conflict(ours: ours, oursLabel: label(lines[index]), base: base,
                                        theirs: theirs, theirsLabel: label(line))
                index = cursor + 1
                return conflict
            } else {
                switch section {
                case 0: ours.append(line)
                case 1: base?.append(line)
                default: theirs.append(line)
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func label(_ marker: String) -> String {
        marker.dropFirst(7).trimmingCharacters(in: .whitespaces)
    }

    /// The file with each conflict settled by `choices` (by its order in the file); a conflict
    /// without a choice keeps its markers.
    public func resolved(_ choices: [Int: Choice]) -> String {
        var lines: [String] = []
        var number = 0
        for part in parts {
            switch part {
            case .text(let text):
                lines += text
            case .conflict(let conflict):
                defer { number += 1 }
                switch choices[number] {
                case .ours: lines += conflict.ours
                case .theirs: lines += conflict.theirs
                case .oursThenTheirs: lines += conflict.ours + conflict.theirs
                case .theirsThenOurs: lines += conflict.theirs + conflict.ours
                case nil:
                    lines.append("<<<<<<< " + conflict.oursLabel)
                    lines += conflict.ours
                    if let base = conflict.base {
                        lines.append("|||||||")
                        lines += base
                    }
                    lines.append("=======")
                    lines += conflict.theirs
                    lines.append(">>>>>>> " + conflict.theirsLabel)
                }
            }
        }
        return lines.joined(separator: lineEnding) + (endsWithNewline ? lineEnding : "")
    }
}
