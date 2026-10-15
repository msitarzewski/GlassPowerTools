//
//  MacTerminalContextMenu.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  The terminal's contextual menu on the Mac. SwiftTerm's view has none, so a right-click in a
//  terminal did nothing (owner, 2026-10-09: "we don't have any contextual menus in terminal.
//  Copy/Paste/Paste Text/Services like [Terminal's]"). Terminal.app's shape: a right-click
//  outside the selection selects the word under the pointer first, so Look Up and Copy have
//  something to act on; then Look Up, Copy, Paste and Select All. The system adds Services
//  (Search With Google among them) because the view hands its selection to them
//  (`NSServicesMenuRequestor`), which also makes the app menu's Services work on a terminal.
//
//  Paste goes through the view's own `paste(_:)`, which the app reviews before anything reaches
//  the shell, exactly as ⌘V does.
//
//  On a link (2026-10-14, `TerminalLinkTarget`), the menu starts with what it can do there, as
//  Terminal's Open URL does: an address opens (after the same question a ⌘-click asks) or is
//  copied; a path is copied or watched — Watch Log File, a tab of its own following the file,
//  where the host can make one (`SwiftTermHostModel.onWatchFile`).
//

#if !canImport(UIKit) && canImport(AppKit)
import AppKit
import SwiftTerm

@MainActor
enum MacTerminalContextMenu {
    /// The menu for a right-click or Control-click at `event`.
    static func menu(for view: TerminalView, event: NSEvent) -> NSMenu {
        selectWordIfOutsideSelection(in: view, at: event.locationInWindow)
        let selected = selectedText(of: view)
        let menu = NSMenu(title: "Terminal")
        // Each item's state is set here; SwiftTerm's own validation knows only its selectors.
        menu.autoenablesItems = false
        if let target = link(in: view, at: event.locationInWindow) {
            addItems(for: target, model: (view as? MacTerminalModelHolding)?.hostModel, to: menu)
            menu.addItem(.separator())
        }
        if let selected, let phrase = lookUpPhrase(selected) {
            let point = view.convert(event.locationInWindow, from: nil)
            menu.addItem(item("Look Up “\(phrase)”", symbol: "info.circle") {
                view.showDefinition(for: NSAttributedString(string: selected), at: point)
            })
            menu.addItem(.separator())
        }
        // What was selected when the menu opened, not whatever is selected when Copy is chosen:
        // output arriving while the menu is open (tmux redraws its status line every second) can
        // clear or move the view's selection first, and `view.copy` then copies nothing (owner,
        // 2026-10-11: "Looks like we broke copy", right-click). Terminal.app copies what it showed.
        menu.addItem(item("Copy", enabled: selected != nil) {
            guard let selected else { return }
            copy(selected, to: copyPasteboard)
        })
        menu.addItem(item("Paste", enabled: pasteboardHasText()) { view.paste(view) })
        menu.addItem(item("Select All") { selectAll(in: view) })
        return menu
    }

    // MARK: A link under the pointer

    /// What the link under `windowPoint` points at: SwiftTerm's link there — a hyperlink, or text
    /// its rules recognise, across a soft-wrapped line too — or else an address Apple's detector
    /// finds on that row.
    static func link(in view: TerminalView, at windowPoint: NSPoint) -> TerminalLinkTarget? {
        guard let position = position(in: view, at: windowPoint) else { return nil }
        return TerminalLinkLookup.target(at: position, in: view.getTerminal())
    }

    /// Open Link and Copy Link on an address; Open in Editor, Show in Finder or Files, Watch Log
    /// File and Copy Path on a path.
    static func addItems(for target: TerminalLinkTarget, model: SwiftTermHostModel?, to menu: NSMenu) {
        // An address Open Link may not open is shown, dimmed, as it always was here.
        if case .url(let url) = target, model == nil || SwiftTermExternalLinkPolicy.validatedRequest(for: url.absoluteString) == nil {
            menu.addItem(item("Open Link", symbol: "safari", enabled: false) {})
        }
        for action in TerminalLinkLookup.actions(for: target, model: model, copy: { copy($0, to: copyPasteboard) }) {
            menu.addItem(item(action.title, symbol: action.symbol) { action.perform() })
        }
    }

    // MARK: Select All over tmux's history

    /// Select All: the terminal's text and, where the terminal shows a program that keeps more
    /// than the terminal can — tmux, which draws on the alternate screen, so its history never
    /// reaches the terminal — all of that program's history, which Copy then copies (owner,
    /// 2026-10-11: "I can't drag select past the current screen buffer so I can't copy all of the
    /// output"). The screen is highlighted as before; the history follows a moment later.
    static func selectAll(in view: TerminalView) {
        view.selectAll(nil)
        guard let holder = view as? MacTerminalHistoryHolding else { return }
        holder.dropHeldSelection()
        let terminal = view.getTerminal()
        guard terminal.isCurrentBufferAlternate, terminal.mouseMode == .off, let read = holder.fullHistory else { return }
        holder.historyRead = Task { @MainActor [weak holder] in
            let text = await read()
            guard !Task.isCancelled, let holder, let text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            holder.heldSelection = text
        }
    }

    /// ⌘A and nothing else held with it.
    static func isSelectAll(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "a"
    }

    // MARK: The word under the pointer

    /// The cell under `windowPoint`, as a position in the buffer, scrollback included.
    static func position(in view: TerminalView, at windowPoint: NSPoint) -> Position? {
        let terminal = view.getTerminal()
        guard terminal.cols > 0 else { return nil }
        // SwiftTerm's text-input answer is the screen cell, row × columns + column.
        let index = view.characterIndex(for: windowPoint)
        guard index >= 0 else { return nil }
        return Position(col: index % terminal.cols, row: index / terminal.cols + terminal.buffer.yDisp)
    }

    /// Selects the word under the pointer unless the click is inside the selection, as a Mac
    /// text view does; a click on blank space leaves nothing selected.
    static func selectWordIfOutsideSelection(in view: TerminalView, at windowPoint: NSPoint) {
        guard let position = position(in: view, at: windowPoint) else { return }
        let selection = view.selection!
        if selection.active, contains(start: selection.start, end: selection.end, position) { return }
        selection.selectWordOrExpression(at: position, in: view.getTerminal().buffer)
        if selectedText(of: view) == nil { selection.selectNone() }
    }

    /// Whether `position` lies in the selection from `start` to `end`, in either order.
    nonisolated static func contains(start: Position, end: Position, _ position: Position) -> Bool {
        let (first, last) = Position.compare(start, end) == .after ? (end, start) : (start, end)
        return Position.compare(position, first) != .before && Position.compare(position, last) != .after
    }

    // MARK: The selection

    /// The selected text, or nil when nothing but blank space is selected.
    static func selectedText(of view: TerminalView) -> String? {
        if let held = (view as? MacTerminalHistoryHolding)?.heldSelection { return held }
        guard view.selection.active else { return nil }
        let text = view.selection.getSelectedText()
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// What Look Up shows in its title: the selection's first line, trimmed and shortened.
    /// Nil when there is nothing to look up.
    nonisolated static func lookUpPhrase(_ text: String, limit: Int = 30) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    // MARK: Services

    /// Whether the view hands its selection to a service: text out, nothing back, since a
    /// terminal's screen is the program's to write, not the service's.
    static func servesSelection(of view: TerminalView, sendType: NSPasteboard.PasteboardType?,
                                returnType: NSPasteboard.PasteboardType?) -> Bool {
        sendType == .string && returnType == nil && selectedText(of: view) != nil
    }

    /// Writes the selection for a service.
    static func writeSelection(of view: TerminalView, to pasteboard: NSPasteboard,
                               types: [NSPasteboard.PasteboardType]) -> Bool {
        guard types.contains(.string), let text = selectedText(of: view) else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    // MARK: Items

    /// Where Copy writes: the general pasteboard; a test's own, so a test never replaces what the
    /// person copied.
    static var copyPasteboard: NSPasteboard = .general

    static func copy(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Whether Paste has text to paste. Asks only which types are there: reading the text itself
    /// would show the system's paste-permission prompt before anyone chose Paste.
    private static func pasteboardHasText() -> Bool {
        NSPasteboard.general.types?.contains(.string) ?? false
    }

    private static func item(_ title: String, symbol: String? = nil, enabled: Bool = true,
                             _ run: @escaping @MainActor () -> Void) -> NSMenuItem {
        let action = MacTerminalMenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(MacTerminalMenuAction.choose(_:)), keyEquivalent: "")
        item.target = action
        // A menu item holds its target weakly; this keeps the action alive as long as the item.
        item.representedObject = action
        item.isEnabled = enabled
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

}

/// A Mac terminal view that knows the model it draws, for what a link's menu items ask of it.
@MainActor protocol MacTerminalModelHolding: AnyObject {
    var hostModel: SwiftTermHostModel? { get }
}

/// A Mac terminal view whose Select All can take a program's whole history
/// (`SwiftTermHostModel.onFullHistory`, `MacTerminalContextMenu.selectAll`).
@MainActor protocol MacTerminalHistoryHolding: AnyObject {
    /// What Select All took beyond the screen; Copy copies it while it is held.
    var heldSelection: String? { get set }
    var historyRead: Task<Void, Never>? { get set }
    /// Reads the history; nil where the terminal shows no such program.
    var fullHistory: (@MainActor () async -> String?)? { get }
}

extension MacTerminalHistoryHolding {
    /// A click starts a new selection: the history Select All took is let go.
    func dropHeldSelection() {
        historyRead?.cancel()
        historyRead = nil
        heldSelection = nil
    }
}

/// A menu item's action, run when the item is chosen. AppKit calls it on the main thread.
///
/// **Not `perform(_:)`.** It was, and `#selector(MenuAction.perform(_:))` named NSObject's own
/// `performSelector:`, so choosing an item asked the action to perform the menu item as if it were
/// a selector: an unrecognized one, which AppKit swallowed. Copy, Paste, Select All and Look Up
/// did nothing from the day the menu was added; ⌘C, which never goes through it, worked (owner,
/// 2026-10-11: "Looks like we broke copy" — right-click). The menu's tests checked only that the
/// items were there and enabled; they now choose them.
@MainActor final class MacTerminalMenuAction: NSObject {
    let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    @objc func choose(_ sender: Any?) { run() }
}
#endif
