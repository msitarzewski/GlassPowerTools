//
//  GlassEditorGitDiff.swift
//  Glass Power Tools — GlassEditor
//
//  `git diff`'s unified output, read into files, hunks and numbered lines.
//
//  git's own diff rather than one computed here: it already knows which files are binary, which
//  were renamed, how `.gitattributes` says to compare them and where a function starts, and the
//  Changes tab should show what `git diff` in the terminal shows, line for line.
//
//  A hunk is read by its counts, not by what its lines look like: a removed line that read
//  "-- a/x" would otherwise look like the next file's header.
//

import Foundation

/// One file's changes.
public struct GlassEditorFileDiff: Equatable, Sendable, Identifiable {
    /// From the repository's root; nil for a file that is new.
    public var oldPath: String?
    /// From the repository's root; nil for a file that was deleted.
    public var newPath: String?
    /// Not text: git says only that it differs.
    public var isBinary = false
    /// File modes, when they changed (`100644` to `100755`, executable now).
    public var oldMode: String?
    public var newMode: String?
    public var hunks: [GlassEditorDiffHunk] = []

    public init(oldPath: String?, newPath: String?) {
        self.oldPath = oldPath
        self.newPath = newPath
    }

    /// The path the file has now, or had.
    public var id: String { newPath ?? oldPath ?? "" }

    public var addedLines: Int { hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .added } } }
    public var removedLines: Int { hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .removed } } }

    /// A file not yet in git, as `git diff` would show it once added: every line new.
    public static func addition(path: String, text: String) -> GlassEditorFileDiff {
        var file = GlassEditorFileDiff(oldPath: nil, newPath: path)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let endsWithNewline = text.hasSuffix("\n")
        if endsWithNewline { lines.removeLast() }
        guard !lines.isEmpty else { return file }
        var hunk = GlassEditorDiffHunk(oldStart: 0, oldCount: 0, newStart: 1, newCount: lines.count, heading: "")
        hunk.lines = lines.enumerated().map { offset, line in
            GlassEditorDiffLine(kind: .added, text: line.hasSuffix("\r") ? String(line.dropLast()) : line,
                                oldNumber: nil, newNumber: offset + 1)
        }
        if !endsWithNewline { hunk.lines[hunk.lines.count - 1].noNewlineAtEnd = true }
        file.hunks = [hunk]
        return file
    }
}

/// One run of changes, with the lines around it.
public struct GlassEditorDiffHunk: Equatable, Sendable {
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    /// What git put after the second `@@`: the function or heading the change is in.
    public var heading: String
    public var lines: [GlassEditorDiffLine] = []

    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, heading: String) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.heading = heading
    }

    /// `@@ -12,7 +12,9 @@`, as git wrote it.
    public var range: String { "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@" }
}

public struct GlassEditorDiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case context, added, removed }

    public var kind: Kind
    public var text: String
    /// Its line in the last commit, and in the file now.
    public var oldNumber: Int?
    public var newNumber: Int?
    /// git's "\ No newline at end of file", which follows the file's last line.
    public var noNewlineAtEnd = false
}

public enum GlassEditorGitDiff {
    /// Every file in `git diff`'s output, in its order.
    public static func parse(_ data: Data) -> [GlassEditorFileDiff] {
        var files: [GlassEditorFileDiff] = []
        var file: GlassEditorFileDiff?
        var hunk: GlassEditorDiffHunk?
        var oldLeft = 0, newLeft = 0, oldNumber = 0, newNumber = 0

        func endHunk() {
            if let hunk { file?.hunks.append(hunk) }
            hunk = nil
        }
        func endFile() {
            endHunk()
            if let file { files.append(file) }
            file = nil
        }

        let text = String(decoding: data, as: UTF8.self)
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw
            if hunk != nil {
                let body = line.dropFirst()
                switch line.first {
                // An empty line is a context line whose space something trimmed.
                case " " where oldLeft > 0 && newLeft > 0, nil where oldLeft > 0 && newLeft > 0:
                    hunk?.lines.append(GlassEditorDiffLine(kind: .context, text: String(body),
                                                           oldNumber: oldNumber, newNumber: newNumber))
                    oldNumber += 1; newNumber += 1; oldLeft -= 1; newLeft -= 1
                case "-" where oldLeft > 0:
                    hunk?.lines.append(GlassEditorDiffLine(kind: .removed, text: String(body),
                                                           oldNumber: oldNumber, newNumber: nil))
                    oldNumber += 1; oldLeft -= 1
                case "+" where newLeft > 0:
                    hunk?.lines.append(GlassEditorDiffLine(kind: .added, text: String(body),
                                                           oldNumber: nil, newNumber: newNumber))
                    newNumber += 1; newLeft -= 1
                case "\\":
                    markNoNewline(&hunk)
                    continue
                default:
                    endHunk()
                }
                if hunk != nil {
                    if oldLeft == 0 && newLeft == 0 { endHunk() }
                    continue
                }
            }
            if line.hasPrefix("\\") {
                // After a hunk that has already ended: it is about that hunk's last line.
                if let count = file?.hunks.count, count > 0 {
                    var last = file?.hunks[count - 1]
                    markNoNewline(&last)
                    if let last { file?.hunks[count - 1] = last }
                }
            } else if line.hasPrefix("diff --git ") {
                endFile()
                let (old, new) = paths(inHeader: line.dropFirst("diff --git ".count))
                file = GlassEditorFileDiff(oldPath: old, newPath: new)
            } else if line.hasPrefix("@@ "), file != nil, let header = hunkHeader(line) {
                endHunk()
                hunk = header
                oldNumber = header.oldStart; newNumber = header.newStart
                oldLeft = header.oldCount; newLeft = header.newCount
                if oldLeft == 0 && newLeft == 0 { endHunk() }
            } else if file != nil {
                readExtendedHeader(line, into: &file)
            }
        }
        endFile()
        return files
    }

    private static func markNoNewline(_ hunk: inout GlassEditorDiffHunk?) {
        guard let count = hunk?.lines.count, count > 0 else { return }
        hunk?.lines[count - 1].noNewlineAtEnd = true
    }

    private static func readExtendedHeader(_ line: Substring, into file: inout GlassEditorFileDiff?) {
        if line.hasPrefix("--- ") {
            file?.oldPath = path(line.dropFirst(4), prefix: "a/")
        } else if line.hasPrefix("+++ ") {
            file?.newPath = path(line.dropFirst(4), prefix: "b/")
        } else if line.hasPrefix("new file mode ") {
            file?.oldPath = nil
            file?.newMode = String(line.dropFirst("new file mode ".count))
        } else if line.hasPrefix("deleted file mode ") {
            file?.newPath = nil
            file?.oldMode = String(line.dropFirst("deleted file mode ".count))
        } else if line.hasPrefix("old mode ") {
            file?.oldMode = String(line.dropFirst("old mode ".count))
        } else if line.hasPrefix("new mode ") {
            file?.newMode = String(line.dropFirst("new mode ".count))
        } else if line.hasPrefix("rename from ") {
            file?.oldPath = unquoted(line.dropFirst("rename from ".count))
        } else if line.hasPrefix("rename to ") {
            file?.newPath = unquoted(line.dropFirst("rename to ".count))
        } else if line.hasPrefix("copy from ") {
            file?.oldPath = unquoted(line.dropFirst("copy from ".count))
        } else if line.hasPrefix("copy to ") {
            file?.newPath = unquoted(line.dropFirst("copy to ".count))
        } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
            file?.isBinary = true
        }
    }

    /// `@@ -12,7 +12,9 @@ heading`; a count left out is 1.
    static func hunkHeader(_ line: Substring) -> GlassEditorDiffHunk? {
        let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count >= 4, parts[0] == "@@", parts[3] == "@@",
              parts[1].hasPrefix("-"), parts[2].hasPrefix("+"),
              let old = range(parts[1].dropFirst()), let new = range(parts[2].dropFirst()) else { return nil }
        return GlassEditorDiffHunk(oldStart: old.start, oldCount: old.count, newStart: new.start, newCount: new.count,
                                   heading: parts.count > 4 ? String(parts[4]) : "")
    }

    private static func range(_ text: Substring) -> (start: Int, count: Int)? {
        let numbers = text.split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(numbers[0]) else { return nil }
        guard numbers.count > 1 else { return (start, 1) }
        guard numbers.count == 2, let count = Int(numbers[1]) else { return nil }
        return (start, count)
    }

    /// A `---` or `+++` path: nil for `/dev/null`, without git's `a/` or `b/`. git ends a name
    /// that has a space in it with a tab, for `patch`'s sake.
    private static func path(_ text: Substring, prefix: String) -> String? {
        var text = text
        if text.hasSuffix("\t") { text = text.dropLast() }
        guard text != "/dev/null" else { return nil }
        let name = unquoted(text)
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }

    /// The two paths in `diff --git a/<old> b/<new>`. Unquoted, a name may itself hold " b/", so
    /// the line is read as two halves when they agree — which they do except for a rename, and
    /// a rename's `rename from` and `rename to` lines say its paths again.
    static func paths(inHeader text: Substring) -> (String?, String?) {
        if text.first == "\"" {
            var rest = text
            guard let first = quotedToken(&rest) else { return (nil, nil) }
            rest = rest.drop(while: { $0 == " " })
            let second = rest.first == "\"" ? quotedToken(&rest) : String(rest)
            return (strip(first, "a/"), second.map { strip($0, "b/") })
        }
        let characters = Array(text)
        if characters.count % 2 == 1 {
            let half = characters.count / 2
            let old = String(characters[..<half]), new = String(characters[(half + 1)...])
            if characters[half] == " ", old.hasPrefix("a/"), new.hasPrefix("b/"), old.dropFirst(2) == new.dropFirst(2) {
                return (String(old.dropFirst(2)), String(new.dropFirst(2)))
            }
        }
        if let split = text.range(of: " b/", options: .backwards) {
            return (strip(String(text[..<split.lowerBound]), "a/"), String(text[split.upperBound...]))
        }
        return (nil, nil)
    }

    private static func strip(_ path: String, _ prefix: String) -> String {
        path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// Reads one C-quoted token off the front of `text`.
    private static func quotedToken(_ text: inout Substring) -> String? {
        guard text.first == "\"" else { return nil }
        var index = text.index(after: text.startIndex)
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" {
                let token = unquoted(text[text.startIndex...index])
                text = text[text.index(after: index)...]
                return token
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// A name git quoted because it holds a quote, a backslash or a control character: C escapes,
    /// with any other byte as three octal digits. A name not in quotes is returned as it is.
    static func unquoted(_ text: Substring) -> String {
        guard text.count >= 2, text.first == "\"", text.last == "\"" else { return String(text) }
        var bytes: [UInt8] = []
        var characters = Array(text.dropFirst().dropLast().utf8)[...]
        while let byte = characters.popFirst() {
            guard byte == UInt8(ascii: "\\"), let next = characters.popFirst() else {
                bytes.append(byte)
                continue
            }
            switch next {
            case UInt8(ascii: "n"): bytes.append(0x0A)
            case UInt8(ascii: "t"): bytes.append(0x09)
            case UInt8(ascii: "r"): bytes.append(0x0D)
            case UInt8(ascii: "a"): bytes.append(0x07)
            case UInt8(ascii: "b"): bytes.append(0x08)
            case UInt8(ascii: "f"): bytes.append(0x0C)
            case UInt8(ascii: "v"): bytes.append(0x0B)
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                var value = Int(next - UInt8(ascii: "0"))
                for _ in 0..<2 {
                    guard let digit = characters.first, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(digit) else { break }
                    characters.removeFirst()
                    value = value * 8 + Int(digit - UInt8(ascii: "0"))
                }
                bytes.append(UInt8(truncatingIfNeeded: value))
            default:
                bytes.append(next)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
