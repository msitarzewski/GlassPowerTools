//
//  TerminalRepaintBand.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  The part of a Vision Pro terminal to repaint when some rows changed (2026-10-29): SwiftTerm 1.20
//  repaints the whole terminal for every update on iOS and visionOS, and the headset showed each
//  typed key as the screen refreshing. Used by `ReviewingTerminalView.setNeedsDisplay`.
//

import CoreGraphics
import Foundation

nonisolated enum TerminalRepaintBand {
    /// Settings ▸ Terminal ▸ Diagnostics ▸ Repaint Changed Lines Only; on unless turned off.
    static let key = "terminal.repaintsChangedRows"

    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// The band of the view holding screen rows `rows` (0 the top), a row wider each way for
    /// letters that reach past their own (descenders, tall Unicode), and down to the view's foot
    /// from the last row, as SwiftTerm's Mac repaint does. `bounds` is the scroll view's, its top
    /// the first screen row. Nil for rows outside the screen.
    static func rect(rows: (start: Int, end: Int), screenRows: Int, cellHeight: CGFloat, bounds: CGRect) -> CGRect? {
        guard screenRows > 0, cellHeight > 0, rows.start >= 0, rows.end >= rows.start, rows.end < screenRows else { return nil }
        let top = bounds.minY + CGFloat(max(0, rows.start - 1)) * cellHeight
        let bottom = rows.end >= screenRows - 2
            ? bounds.maxY
            : min(bounds.maxY, bounds.minY + CGFloat(rows.end + 2) * cellHeight)
        guard bottom > top else { return nil }
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top)
    }
}

/// What each screen row showed when it was last repainted, to tell which of the rows SwiftTerm names
/// really changed (2026-10-29: "Every letter affects the screen"). SwiftTerm marks every row when a
/// synchronized update ends (`endSynchronizedOutput`: `refresh(startRow: 0, endRow: rows - 1)`), and
/// Claude Code wraps each of its frames, a typed letter's included, in one; the headset counted
/// every key as a whole repaint ("every line"). Compared row by row, one letter is one row.
nonisolated struct TerminalRowFingerprints {
    private var drawn: [Int: Int] = [:]

    /// Nothing is known to be on screen: a repaint of everything, or a scroll, follows.
    mutating func forget() { drawn.removeAll() }

    /// Takes `rows` as drawn as they are now: after a whole repaint.
    mutating func record(_ rows: ClosedRange<Int>, fingerprint: (Int) -> Int) {
        for row in rows { drawn[row] = fingerprint(row) }
    }

    /// The rows of `rows` that differ from what was drawn, as the range holding them all, taken as
    /// drawn now; nil when none differ, and nothing needs repainting.
    mutating func changed(in rows: ClosedRange<Int>, fingerprint: (Int) -> Int) -> ClosedRange<Int>? {
        var low: Int?
        var high: Int?
        for row in rows {
            let print = fingerprint(row)
            guard drawn[row] != print else { continue }
            drawn[row] = print
            low = low ?? row
            high = row
        }
        guard let low, let high else { return nil }
        return low...high
    }
}
