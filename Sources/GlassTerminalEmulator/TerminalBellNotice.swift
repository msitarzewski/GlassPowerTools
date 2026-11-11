//
//  TerminalBellNotice.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  A bell nobody has seen yet (the owner, 2026-11-03: "We can detect when a terminal sends a bell, right? Let's add an
//  indicator when that happens"). A terminal rings its bell (BEL) for attention — a coding agent waiting for an answer,
//  a long job done — often while it is out of sight: in a tab not chosen, or a window in the dock. The notice is kept
//  with the terminal, not its view, so a terminal whose window is in the dock (and so has no view) still has one; its
//  tab, its orb and its card show it, and it clears as soon as the terminal is in sight again. It shows whatever the
//  terminal's Bell setting says: that setting (off unless turned on) is the sound and the flash, and with it off a
//  terminal's call for attention would otherwise go unnoticed altogether.
//

import Foundation
import Observation

/// Whether a terminal has rung its bell since it was last in sight.
@MainActor
@Observable
public final class TerminalBellNotice {
    /// A bell rang while the terminal was out of sight, and it has not been in sight since.
    public private(set) var isUnseen = false

    /// The terminal is in front of someone: its tab chosen in a window on screen. Set by what shows it; a bell then
    /// is seen as it rings, and becoming in sight clears one that rang before.
    @ObservationIgnored public var isInSight = false {
        didSet { if isInSight { clear() } }
    }

    public init() {}

    /// Told when a terminal's notice turns unseen, and when it is seen again: the Mac's notification of a bell rung out
    /// of sight is posted, then taken back (2026-11-10).
    public static var onUnseen: (@MainActor (TerminalBellNotice) -> Void)?
    public static var onSeen: (@MainActor (TerminalBellNotice) -> Void)?

    /// The terminal rang its bell.
    public func ring() {
        guard !isInSight, !isUnseen else { return }
        isUnseen = true
        Self.onUnseen?(self)
    }

    /// Seen: the terminal was chosen, or its notice is no longer wanted.
    public func clear() {
        guard isUnseen else { return }
        isUnseen = false
        Self.onSeen?(self)
    }
}
