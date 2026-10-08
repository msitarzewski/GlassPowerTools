//
//  GlassShellFindCommands.swift
//  Glass Power Tools — GlassShell
//
//  Edit ▸ Find: Find…, Find Next and Find Previous, owned once by the shell and aimed by whatever
//  window is focused — ⌘S's shape (D37, `GlassShellFileCommands`), for the same reason (2026-10-08).
//
//  ⌘F was the terminal's "Find in Pane…" and ⌘G its Terminal Grid. A key declared by one
//  capability is that capability's everywhere, and a second declaration does not let the focused
//  window choose: one of the two loses, silently (rule 39). The editor wants ⌘F and ⌘G as much as
//  the terminal does, so the keys belong to no capability: each window publishes what Find means
//  there, and a window with nothing to search publishes nothing.
//
//  SwiftUI's own Edit menu has no Find group unless `TextEditingCommands` is added, and nothing in
//  the app adds it — checked in a scratch app on macOS 27 — so these items do not compete with a
//  standard Find Next for ⌘G.
//

import SwiftUI

/// What Find, Find Next and Find Previous do in the focused window.
@MainActor
public struct GlassFindItemAction {
    public let isEnabled: Bool
    private let find: () -> Void
    private let findNext: () -> Void
    private let findPrevious: () -> Void

    /// - Parameters:
    ///   - find: ⌘F — open the window's find bar and put the keyboard in it.
    ///   - findNext: ⌘G — the next match, opening the bar with the last term when it is closed.
    ///   - findPrevious: ⇧⌘G — the same, the other way.
    public init(isEnabled: Bool = true, find: @escaping () -> Void,
                findNext: @escaping () -> Void, findPrevious: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.find = find
        self.findNext = findNext
        self.findPrevious = findPrevious
    }

    public func showFind() { find() }
    public func next() { findNext() }
    public func previous() { findPrevious() }
}

private struct GlassFindItemActionKey: FocusedValueKey {
    typealias Value = GlassFindItemAction
}

public extension FocusedValues {
    var glassFindItem: GlassFindItemAction? {
        get { self[GlassFindItemActionKey.self] }
        set { self[GlassFindItemActionKey.self] = newValue }
    }
}

#if os(macOS)
/// The app's one Edit ▸ Find group. Attached by the composition root beside File ▸ New and Save.
public struct GlassShellFindCommands: Commands {
    @FocusedValue(\.glassFindItem) private var findItem

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Menu("Find") {
                Button("Find…") { findItem?.showFind() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(findItem?.isEnabled != true)
                Button("Find Next") { findItem?.next() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(findItem?.isEnabled != true)
                Button("Find Previous") { findItem?.previous() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(findItem?.isEnabled != true)
            }
        }
    }
}
#endif
