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
    /// from the last two rows, as SwiftTerm's Mac repaint does; within `bounds`, the scroll view's.
    /// Nil for rows outside the screen, or a band wholly out of sight.
    ///
    /// **`screenTop` is where SwiftTerm draws the screen's first row**, not the view's top: it draws
    /// each line of its buffer at that line's number times the cell height, so the screen starts at
    /// its first shown line's (`yDisp`). The two agree only while the terminal's rows fill the view.
    /// With fewer — tmux's window at another device's size (`showTmuxGrid`) — the view also shows
    /// lines from before the screen, and the screen starts lower: in the visionOS simulator, 12 rows
    /// in a view of 41 started 9 rows down, and a band measured from the view's top named rows 9
    /// above the ones that changed (2026-11-03). Not seen on the headset: there the system draws the
    /// whole terminal whatever band is asked for (0.4.592's counts, 288 draws, none in part), so
    /// what the band saves is the repaints skipped, not the area drawn.
    static func rect(rows: (start: Int, end: Int), screenRows: Int, cellHeight: CGFloat, screenTop: CGFloat,
                     bounds: CGRect) -> CGRect? {
        guard screenRows > 0, cellHeight > 0, rows.start >= 0, rows.end >= rows.start, rows.end < screenRows else { return nil }
        let top = max(bounds.minY, screenTop + CGFloat(rows.start - 1) * cellHeight)
        let bottom = rows.end >= screenRows - 2
            ? bounds.maxY
            : min(bounds.maxY, screenTop + CGFloat(rows.end + 2) * cellHeight)
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
