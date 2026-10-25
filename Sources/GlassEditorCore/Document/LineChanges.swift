import Foundation

/// A run of lines that differ from an earlier version of the text: the marks an editor draws
/// beside the lines it has changed since the last commit.
public struct LineChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Lines that were not there.
        case added
        /// Lines that replaced others.
        case modified
        /// Lines that were removed, from just above `lines.lowerBound`.
        case deleted
    }

    public var kind: Kind
    /// Zero-based lines of the text as it is now; empty for `.deleted`.
    public var lines: Range<Int>
    /// The earlier version's lines this replaced or removed; empty for `.added`.
    public var baseLines: Range<Int>

    public init(kind: Kind, lines: Range<Int>, baseLines: Range<Int>) {
        self.kind = kind
        self.lines = lines
        self.baseLines = baseLines
    }
}

/// Which lines of a text differ from an earlier version of it, by line.
///
/// Myers' difference, as git's own default is, over lines numbered by their content so each
/// comparison is one integer. The lines both versions share at the top and the bottom are set
/// aside first: an edit is usually in one place, and that leaves almost nothing to compare.
public enum LineChanges {
    /// The most differences worked out line by line. Past it the lines between the first and the
    /// last difference are marked as one change: the work grows with the square of the
    /// differences, and a file rewritten from top to bottom is changed throughout either way.
    public static let differenceLimit = 2_000

    /// How `current` differs from `base`, in the order of its lines.
    public static func between(base: String, current: String) -> [LineChange] {
        between(base: lines(of: base), current: lines(of: current))
    }

    /// A text's lines as the editor's buffer counts them (`LineIndex`): broken at LF, CR and CRLF,
    /// with a final empty line after a final terminator. CRLF is one `Character` to Swift, so
    /// splitting at "\n" alone left a Windows file one long line.
    ///
    /// Read as bytes: LF and CR are ASCII, so where they are is where a line ends, and the bytes are
    /// many times quicker to walk than characters.
    static func lines(of text: String) -> [Substring] {
        var lines: [Substring] = []
        let bytes = text.utf8
        var start = bytes.startIndex, index = start
        while index != bytes.endIndex {
            let byte = bytes[index]
            guard byte == 0x0A || byte == 0x0D else {
                index = bytes.index(after: index)
                continue
            }
            lines.append(text[start..<index])
            index = bytes.index(after: index)
            if byte == 0x0D, index != bytes.endIndex, bytes[index] == 0x0A { index = bytes.index(after: index) }
            start = index
        }
        lines.append(text[start..<bytes.endIndex])
        return lines
    }

    static func between(base: [Substring], current: [Substring]) -> [LineChange] {
        var top = 0
        while top < base.count, top < current.count, base[top] == current[top] { top += 1 }
        var bottom = 0
        while bottom < base.count - top, bottom < current.count - top,
              base[base.count - 1 - bottom] == current[current.count - 1 - bottom] { bottom += 1 }
        let oldEnd = base.count - bottom, newEnd = current.count - bottom
        if top == oldEnd, top == newEnd { return [] }
        if top == oldEnd { return [LineChange(kind: .added, lines: top..<newEnd, baseLines: top..<top)] }
        if top == newEnd { return [LineChange(kind: .deleted, lines: top..<top, baseLines: top..<oldEnd)] }

        // Each distinct line as a number, so the comparisons below are of integers.
        var numbers: [Substring: Int32] = [:]
        func number(_ line: Substring) -> Int32 {
            if let known = numbers[line] { return known }
            let next = Int32(numbers.count)
            numbers[line] = next
            return next
        }
        let old = base[top..<oldEnd].map(number)
        let new = current[top..<newEnd].map(number)
        guard let (removed, inserted) = difference(old, new, limit: differenceLimit) else {
            return [LineChange(kind: .modified, lines: top..<newEnd, baseLines: top..<oldEnd)]
        }
        return runs(removed: removed, inserted: inserted, offset: top)
    }

    /// Myers' greedy difference: which of `old`'s lines are removed and which of `new`'s are
    /// inserted. Nil when they differ in more than `limit` lines.
    static func difference(_ old: [Int32], _ new: [Int32], limit: Int) -> (removed: [Bool], inserted: [Bool])? {
        let n = old.count, m = new.count
        let most = min(n + m, limit)
        let offset = most + 1
        // How far along `old` each diagonal k = x - y has reached. 32 bits, because the way back
        // keeps a copy per round: at the limit that is four million of them.
        var furthest = [Int32](repeating: 0, count: 2 * most + 3)
        // What `furthest` held, from -d to d, before each round d: the way back.
        var trace: [[Int32]] = []
        var cost = -1
        search: for d in 0...most {
            trace.append(Array(furthest[(offset - d)...(offset + d)]))
            for k in stride(from: -d, through: d, by: 2) {
                var x = Int((k == -d || (k != d && furthest[offset + k - 1] < furthest[offset + k + 1]))
                    ? furthest[offset + k + 1]
                    : furthest[offset + k - 1] + 1)
                var y = x - k
                while x < n, y < m, old[x] == new[y] { x += 1; y += 1 }
                furthest[offset + k] = Int32(x)
                if x >= n, y >= m {
                    cost = d
                    break search
                }
            }
        }
        guard cost >= 0 else { return nil }

        var removed = [Bool](repeating: false, count: n)
        var inserted = [Bool](repeating: false, count: m)
        var x = n, y = m
        for d in stride(from: cost, to: 0, by: -1) {
            let before = trace[d]
            func at(_ k: Int) -> Int { Int(before[k + d]) }
            let k = x - y
            let previous = (k == -d || (k != d && at(k - 1) < at(k + 1))) ? k + 1 : k - 1
            let previousX = at(previous), previousY = previousX - previous
            while x > previousX, y > previousY { x -= 1; y -= 1 }
            if x == previousX { inserted[previousY] = true } else { removed[previousX] = true }
            x = previousX
            y = previousY
        }
        return (removed, inserted)
    }

    /// Adjacent removals and insertions as one change each: insertions alone are added lines,
    /// removals alone a deletion, both together lines modified.
    static func runs(removed: [Bool], inserted: [Bool], offset: Int) -> [LineChange] {
        var changes: [LineChange] = []
        var i = 0, j = 0
        while i < removed.count || j < inserted.count {
            let oldStart = i, newStart = j
            var moved = true
            while moved {
                moved = false
                while i < removed.count, removed[i] { i += 1; moved = true }
                while j < inserted.count, inserted[j] { j += 1; moved = true }
            }
            let baseLines = (offset + oldStart)..<(offset + i), lines = (offset + newStart)..<(offset + j)
            if lines.isEmpty, baseLines.isEmpty {
                // A line both share.
                i += 1
                j += 1
            } else if baseLines.isEmpty {
                changes.append(LineChange(kind: .added, lines: lines, baseLines: baseLines))
            } else if lines.isEmpty {
                changes.append(LineChange(kind: .deleted, lines: lines, baseLines: baseLines))
            } else {
                changes.append(LineChange(kind: .modified, lines: lines, baseLines: baseLines))
            }
        }
        return changes
    }
}
