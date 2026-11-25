//
//  MacProgramCopy.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  ⌘C after a program copied by itself (2026-11-23). A program that takes the mouse — Claude Code full screen,
//  among others — makes the selection a drag makes, and copies it when the mouse is let go. The terminal has
//  no selection of its own then, so SwiftTerm refused ⌘C and the Mac beeped, while ⌘V pasted what the program
//  had copied (the owner's check, 2026-11-23). ⌘C can't reach the program either: tmux 3.8 passes no ⌘.
//
//  So after a drag a program had, the terminal watches the clipboard for a moment. When it changes, the
//  program has copied, and while the clipboard still holds that copy, ⌘C is done already: it is allowed and
//  does nothing more. When nothing changed — a program that doesn't copy, or one on another machine whose copy
//  can't reach this Mac — ⌘C is refused as before.
//

#if os(macOS)
import AppKit
import SwiftTerm

@MainActor
final class MacProgramCopy {
    /// The pasteboard the program's copy lands on: the general one; a test's own.
    private let pasteboard: () -> NSPasteboard
    /// How long after the release to look, in turn: a local program copies within milliseconds.
    private let looks: [Duration]
    /// The clipboard's count once the program copied, while that copy is the one to stand for.
    private(set) var copied: Int?
    /// Still looking for the program's copy after a release.
    private(set) var isWatching = false
    private var watch: Task<Void, Never>?

    init(pasteboard: @escaping () -> NSPasteboard = { MacTerminalContextMenu.copyPasteboard },
         looks: [Duration] = [.milliseconds(100), .milliseconds(300), .milliseconds(700), .milliseconds(1500)]) {
        self.pasteboard = pasteboard
        self.looks = looks
    }

    /// A press, a Select All or anything else that starts a selection: whatever the program copied before
    /// is no longer what ⌘C stands for.
    func forget() {
        watch?.cancel()
        watch = nil
        isWatching = false
        copied = nil
    }

    /// The mouse let go. When a program had it, look for the program's copy.
    func released(programHadMouse: Bool) {
        forget()
        guard programHadMouse else { return }
        let before = pasteboard().changeCount
        isWatching = true
        watch = Task { [weak self, looks] in
            var waited = Duration.zero
            var found: Int?
            for look in looks {
                try? await Task.sleep(for: look - waited)
                guard !Task.isCancelled, let board = self?.pasteboard() else { return }
                waited = look
                if board.changeCount != before {
                    found = board.changeCount
                    break
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.copied = found
            self.isWatching = false
        }
    }

    /// Whether the clipboard holds what the program copied after the last drag, and nothing since.
    var holdsProgramCopy: Bool {
        copied.map { $0 == pasteboard().changeCount } ?? false
    }

    /// Whether `event` went to a program that has the mouse: SwiftTerm sends it there, unless Shift asks for the
    /// terminal's own selection and the program hasn't taken Shift too.
    static func programHasMouse(_ view: TerminalView, event: NSEvent) -> Bool {
        let terminal = view.getTerminal()
        return view.allowMouseReporting && terminal.mouseMode != .off
            && (!event.modifierFlags.contains(.shift) || terminal.mouseShiftCapture)
    }
}
#endif
