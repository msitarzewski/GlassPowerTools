//
//  TmuxResizeHold.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  A terminal's new size goes to tmux once a resize is over, not at each step of it (the owner,
//  2026-11-21: "hold the size until the resize ends"). Each size tmux is given resizes the pane, and
//  the program in it redraws. Claude Code redraws by printing its whole conversation again under the
//  last copy, which stays in the history at the old width, its lines cut mid-word where they no
//  longer fit (anthropics/claude-code#107564, open). A window dragged by its edge gave tmux a size at
//  every step: measured in the macOS VM, one drag told the pane's program three sizes; held, one.
//

import Foundation
#if os(macOS)
import AppKit
#endif

/// Holds a control-mode client's sizes while they keep changing, and while a window is being resized
/// by its edge, then hands on the last one, once.
@MainActor
public final class TmuxResizeHold {
    /// How long sizes stay the same before the last is handed on: a resize that animates, such as
    /// a window going full screen, hands on one size; a new font size waits this long.
    public static let settle: Duration = .milliseconds(250)

    public typealias Sleep = @MainActor (Duration) async throws -> Void

    private let sleep: Sleep
    private let isLiveResizing: @MainActor () -> Bool
    private let handOn: @MainActor (_ columns: Int, _ rows: Int) -> Void
    private var held: (columns: Int, rows: Int)?
    private var waiting: Task<Void, Never>?

    /// - Parameters:
    ///   - isLiveResizing: whether a window is being resized by its edge: nothing is handed on until
    ///     it is let go.
    ///   - handOn: the size for tmux, given to the client.
    public init(sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
                isLiveResizing: @escaping @MainActor () -> Bool = TmuxResizeHold.aWindowIsLiveResizing,
                handOn: @escaping @MainActor (_ columns: Int, _ rows: Int) -> Void) {
        self.sleep = sleep
        self.isLiveResizing = isLiveResizing
        self.handOn = handOn
    }

    /// The terminal's grid. `hold`: the pane is drawn and followed, so the size waits for the resize
    /// to end. Otherwise it is handed on now, as the attach waits on it, and anything held is dropped.
    public func size(columns: Int, rows: Int, hold: Bool) {
        waiting?.cancel()
        waiting = nil
        guard hold else {
            held = nil
            handOn(columns, rows)
            return
        }
        held = (columns, rows)
        waiting = Task { [weak self] in await self?.handOnOnceSettled() }
    }

    private func handOnOnceSettled() async {
        repeat {
            do { try await sleep(Self.settle) } catch { return }
            // A newer size started a wait of its own.
            if Task.isCancelled { return }
        } while isLiveResizing()
        guard let held else { return }
        self.held = nil
        waiting = nil
        handOn(held.columns, held.rows)
    }

    /// Until what is held has been handed on, or dropped.
    func waitUntilHandedOn() async {
        while let task = waiting {
            await task.value
            if waiting == task { return }
        }
    }

    /// A window of this app's being resized by its edge: AppKit's live resize, from the press on the
    /// edge to its release.
    public static func aWindowIsLiveResizing() -> Bool {
        #if os(macOS)
        NSApp?.windows.contains { $0.inLiveResize } ?? false
        #else
        false
        #endif
    }
}
