//
//  TerminalActivityFocus.swift
//  Glass Power Tools — GlassTerminal
//
//  Auto-focus on activity with several terminals at work in one window (2026-10-27).
//

import Foundation

/// When Auto-focus on activity brings a terminal forward: the one that printed last, unless the one in
/// front printed within `quiet`, which keeps its place while it is at work. Following every change of
/// the last to print moved a window many times a second with five coding agents at work in it (the
/// owner, 2026-10-27: "the hyper refresh is back and the gear no longer works").
struct TerminalActivityFocus {
    /// Printing, until this long without output.
    static let quiet: Duration = .milliseconds(1_200)
    private var printed: [UUID: ContinuousClock.Instant] = [:]

    mutating func note(_ id: UUID, at now: ContinuousClock.Instant = .now) {
        printed[id] = now
    }

    func isPrinting(_ id: UUID, at now: ContinuousClock.Instant = .now) -> Bool {
        printed[id].map { now - $0 < Self.quiet } ?? false
    }

    /// Whether `printing` comes forward over `front` now.
    func brings(_ printing: UUID, over front: UUID?, at now: ContinuousClock.Instant = .now) -> Bool {
        guard let front else { return true }
        return front != printing && !isPrinting(front, at: now)
    }
}
