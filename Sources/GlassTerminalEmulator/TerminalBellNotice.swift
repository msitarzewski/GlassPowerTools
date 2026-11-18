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
        didSet {
            guard isInSight else { return }
            clear()
            clearSession()
        }
    }

    public init() {}

    // MARK: Kept on its tmux session, for every device (2026-11-15)

    /// Clears the bell kept on the terminal's tmux session (`@glass-bell`), which its `alert-bell` hook set as the
    /// bell passed through tmux, so every device's Active stops saying it. False when it can't now (not connected):
    /// it is asked again the next time the terminal is seen. Nil for a terminal outside tmux.
    @ObservationIgnored public var clearsSession: (@MainActor () -> Bool)?

    /// A bell may be kept on the session: one rang here, or the session said so.
    @ObservationIgnored public private(set) var sessionMayKeepOne = false

    /// The terminal's tmux session says a bell rang there that no device has shown (`@glass-bell`): one rung while this
    /// device wasn't connected — the iPhone put away — or watched only elsewhere. Unseen here, unless the terminal is in
    /// sight, where it is seen now and the session's is cleared.
    public func sessionKeepsOne() {
        sessionMayKeepOne = true
        if isInSight {
            clearSession()
        } else if !isUnseen {
            isUnseen = true
            Self.onUnseen?(self)
        }
    }

    private func clearSession() {
        guard sessionMayKeepOne, let clearsSession else { return }
        if clearsSession() { sessionMayKeepOne = false }
    }

    /// Told when a terminal's notice turns unseen, and when it is seen again: the Mac's notification of a bell rung out
    /// of sight is posted, then taken back (2026-11-10).
    public static var onUnseen: (@MainActor (TerminalBellNotice) -> Void)?
    public static var onSeen: (@MainActor (TerminalBellNotice) -> Void)?

    /// The terminal rang its bell.
    public func ring() {
        // On its way here it passed through tmux, whose hook kept it on the session: seen as it rings, that is cleared.
        sessionMayKeepOne = true
        if isInSight { clearSession() }
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
