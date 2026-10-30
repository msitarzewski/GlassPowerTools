//
//  TerminalRowFingerprint.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  A screen row's look in one number: each cell's character, width, colours and style, and whether
//  something is attached to it (an image, a link). Two rows with the same fingerprint draw the same
//  (`TerminalRowFingerprints`). The palette and the font are not in it: a theme or font change
//  repaints everything without asking (`updateFullScreen`, a new cell size).
//

import SwiftTerm

nonisolated enum TerminalRowFingerprint {
    static func of(_ line: BufferLine?, columns: Int) -> Int {
        guard let line else { return 0 }
        var hasher = Hasher()
        let count = min(columns, line.count)
        hasher.combine(count)
        for column in 0..<count {
            let cell = line[column]
            hasher.combine(cell.getCharacter())
            hasher.combine(cell.width)
            hasher.combine(cell.attribute)
            hasher.combine(cell.hasPayload)
        }
        return hasher.finalize()
    }
}
