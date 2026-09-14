import Foundation

/// The line-start index behind `TextStorageBuffer`.
///
/// **Representation**: a sorted `[Int]` of UTF-16 offsets, one per line, always
/// non-empty and always beginning with `0`. Line *i* starts at `starts[i]`;
/// line *i* ends where line *i+1* begins (or at the end of the document).
///
/// **Complexity**
/// - offset → line: `O(log n)` binary search over `starts`
/// - edit: `O(k + m)` where `k` is the length of the rescanned span (the edited
///   line region, *not* the document) and `m` is the number of lines after the
///   edit, which are shifted by the edit's length delta.
///
/// The `O(m)` shift is a contiguous integer pass — a `memmove`-speed loop, not a
/// text rescan. The failure this type exists to prevent is re-scanning the whole
/// *document* per keystroke (`projectRules.md`, Testing; `PROJECT_SCAFFOLD.md`
/// M1). If profiling ever shows the shift dominating on very large documents, a
/// tree with lazily-propagated offsets can replace the array behind this same
/// internal API without touching `TextStorageBuffer`.
///
/// **Terminators recognised**: `LF` (`\n`), `CR` (`\r`), and `CRLF` (`\r\n`,
/// treated as a single terminator). Nothing else breaks a line — not `U+2028`,
/// not `U+0085`. This matches the line-ending policy the document layer
/// preserves (LF / CRLF / CR) and keeps code-editor semantics predictable.
///
/// **Convention**: a terminator always opens a new line, so a document ending in
/// a terminator has a final empty line. `"a\n"` is two lines: `"a\n"` and `""`.
struct LineIndex {
    /// Sorted, strictly increasing, `starts[0] == 0`, `starts.count == lineCount`.
    private(set) var starts: [Int]

    /// Code units re-scanned by the most recent `apply`. Exists so a test can
    /// prove incrementality structurally — a keystroke in a large document must
    /// rescan a line-sized span, not a document-sized one — instead of relying on
    /// a timing measurement that would be flaky in CI.
    private(set) var lastRescanSpan: Int = 0

    init(units: [UInt16]) {
        starts = [0]
        Self.scan(units, from: 0, upTo: units.count, emitBelow: units.count + 1, into: &starts)
    }

    var lineCount: Int { starts.count }

    func start(ofLine line: Int) -> Int {
        precondition(line >= 0 && line < starts.count, "line \(line) out of range 0..<\(starts.count)")
        return starts[line]
    }

    /// Index of the line containing `offset`. The caller is responsible for
    /// clamping `offset` into `0...utf16Length`; an offset equal to the document
    /// length belongs to the last line.
    func line(forOffset offset: Int) -> Int {
        // Last index whose start is <= offset.
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    /// Incrementally repairs the index after `units` was mutated: the old range
    /// `editStart..<oldEnd` was replaced by `insertedLength` code units.
    ///
    /// Line starts at or before the edit survive untouched, line starts safely
    /// beyond it are shifted by the length delta, and only the span between the
    /// two is rescanned. The `+ 1` guards on the surviving region exist because a
    /// `CRLF` terminator spans two code units and could otherwise straddle the
    /// edit boundary.
    mutating func apply(units: [UInt16], editStart: Int, oldEnd: Int, insertedLength: Int) {
        let delta = insertedLength - (oldEnd - editStart)
        let newLength = units.count

        // Everything up to and including this line start is still valid: a
        // terminator ending at or before `editStart` lies entirely before the
        // edit — with one exception. If that terminator is a lone CR, the code
        // unit the edit just put in its place may be an LF, merging the two into
        // a single CRLF and destroying the line start. So when a CR sits
        // immediately before the rescan point, back up one line and let the scan
        // re-decide with the CR in view.
        var lo = line(forOffset: editStart)
        var scanStart = starts[lo]
        if scanStart > 0 && units[scanStart - 1] == 0x000D {
            lo -= 1
            scanStart -= 1
        }

        // First old line start far enough past the edit that its terminator is
        // untouched. It and everything after it shift by `delta`.
        var survivor = lo + 1
        var high = starts.count
        while survivor < high {
            let mid = (survivor + high) / 2
            if starts[mid] <= oldEnd + 1 {
                survivor = mid + 1
            } else {
                high = mid
            }
        }

        let limit = survivor < starts.count ? starts[survivor] + delta : newLength + 1
        let scanEnd = min(limit, newLength)
        lastRescanSpan = max(0, scanEnd - scanStart)

        var rescanned: [Int] = []
        Self.scan(units, from: scanStart, upTo: scanEnd, emitBelow: limit, into: &rescanned)

        if delta != 0 && survivor < starts.count {
            for i in survivor..<starts.count {
                starts[i] += delta
            }
        }
        starts.replaceSubrange((lo + 1)..<survivor, with: rescanned)
    }

    /// Appends the offset *after* every line terminator found at positions
    /// `from..<end`, keeping only offsets strictly below `emitBelow` (the caller
    /// owns everything from `emitBelow` onward).
    private static func scan(
        _ units: [UInt16],
        from: Int,
        upTo end: Int,
        emitBelow: Int,
        into result: inout [Int]
    ) {
        var p = from
        while p < end {
            let unit = units[p]
            if unit == 0x000A { // LF
                if p + 1 < emitBelow { result.append(p + 1) }
            } else if unit == 0x000D { // CR, or the CR of a CRLF pair
                if p + 1 < units.count && units[p + 1] == 0x000A {
                    p += 1
                }
                if p + 1 < emitBelow { result.append(p + 1) }
            }
            p += 1
        }
    }
}
