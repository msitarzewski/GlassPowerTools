#if os(macOS)
import AppKit
import Foundation
import Testing
import SwiftTerm
@testable import GlassTerminalEmulator

/// ⌘C after a program that has the mouse copied by itself (2026-11-23): Claude Code full screen copies when the
/// mouse is let go, the terminal has no selection, and ⌘C beeped while ⌘V pasted. Each test watches a pasteboard
/// of its own, so nothing the person copied is touched.
@MainActor
@Suite("⌘C after a program copied", .serialized)
struct MacProgramCopyTests {
    private typealias HostedTerminal = TerminalFindTests.HostedTerminal

    private static let looks: [Duration] = [.milliseconds(20), .milliseconds(60), .milliseconds(150)]

    private func pasteboard(_ name: String) -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("MacProgramCopyTests.\(name).\(UUID())"))
    }

    /// Until the watch has finished looking, however late a loaded machine wakes it (a fixed wait failed once).
    private func finished(_ watch: MacProgramCopy) async throws {
        for _ in 0..<500 where watch.isWatching { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!watch.isWatching, "the watch ends")
    }

    @Test("a copy just after the release is the program's; anything copied later, or a new press, isn't")
    func watch() async throws {
        let board = pasteboard("watch")
        defer { board.releaseGlobally() }
        let watch = MacProgramCopy(pasteboard: { board }, looks: Self.looks)
        #expect(!watch.holdsProgramCopy)

        watch.released(programHadMouse: true)
        MacTerminalContextMenu.copy("what the program selected", to: board)
        try await finished(watch)
        #expect(watch.holdsProgramCopy)

        MacTerminalContextMenu.copy("copied elsewhere", to: board)
        #expect(!watch.holdsProgramCopy, "the clipboard no longer holds the program's copy")

        watch.released(programHadMouse: true)
        MacTerminalContextMenu.copy("again", to: board)
        try await finished(watch)
        #expect(watch.holdsProgramCopy)
        watch.forget()
        #expect(!watch.holdsProgramCopy, "a press starts over")
    }

    @Test("nothing copied after the release, or a release no program had, stands for nothing")
    func nothingCopied() async throws {
        let board = pasteboard("nothing")
        defer { board.releaseGlobally() }
        let watch = MacProgramCopy(pasteboard: { board }, looks: Self.looks)
        watch.released(programHadMouse: true)
        try await finished(watch)
        #expect(!watch.holdsProgramCopy, "a program that doesn't copy, or one whose copy can't reach this Mac")
        MacTerminalContextMenu.copy("late", to: board)
        #expect(!watch.holdsProgramCopy, "a copy after the watch ended isn't the program's")

        watch.released(programHadMouse: false)
        MacTerminalContextMenu.copy("the terminal's own", to: board)
        try await finished(watch)
        #expect(!watch.holdsProgramCopy, "without a program holding the mouse the terminal selects, and copies, itself")
    }

    @Test("in the real view: after a drag a program had and its copy, ⌘C is allowed and leaves the copy; a press refuses it again")
    func inTheView() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        // Full screen, and the mouse asked for, as Claude Code asks (any-event tracking, SGR).
        await host.feed("\u{1B}[?1049h\u{1B}[?1003h\u{1B}[?1006hselect me")
        let view = try #require(Self.terminalView(host))
        let board = pasteboard("view")
        defer { board.releaseGlobally() }
        let general = MacTerminalContextMenu.copyPasteboard
        MacTerminalContextMenu.copyPasteboard = board
        defer { MacTerminalContextMenu.copyPasteboard = general }
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")

        #expect(view.getTerminal().mouseMode != .off)
        #expect(!view.validateUserInterfaceItem(copyItem), "nothing selected, nothing copied: refused")

        view.mouseDown(with: try Self.mouse(.leftMouseDown, x: 2, in: view))
        view.mouseUp(with: try Self.mouse(.leftMouseUp, x: 40, in: view))
        #expect(!view.selection.active, "the drag was the program's")
        MacTerminalContextMenu.copy("select me", to: board) // the program's copy on release
        for _ in 0..<500 where !view.validateUserInterfaceItem(copyItem) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(view.validateUserInterfaceItem(copyItem), "⌘C stands for the program's copy")
        view.copy(view)
        #expect(board.string(forType: .string) == "select me", "and leaves it on the clipboard")

        view.mouseDown(with: try Self.mouse(.leftMouseDown, x: 2, in: view))
        #expect(!view.validateUserInterfaceItem(copyItem), "a new press: refused until the program copies again")
    }

    // MARK: Helpers

    private static func terminalView(_ host: HostedTerminal) -> TerminalView? {
        var views: [NSView] = host.hosting.map { [$0] } ?? []
        while !views.isEmpty {
            let view = views.removeFirst()
            if let terminal = view as? TerminalView { return terminal }
            views += view.subviews
        }
        return nil
    }

    private static func mouse(_ type: NSEvent.EventType, x: CGFloat, in view: TerminalView) throws -> NSEvent {
        let cellHeight = view.getOptimalFrameSize().height / CGFloat(view.getTerminal().rows)
        let local = NSPoint(x: x, y: view.bounds.height - 0.5 * cellHeight)
        return try #require(NSEvent.mouseEvent(
            with: type, location: view.convert(local, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
}
#endif
