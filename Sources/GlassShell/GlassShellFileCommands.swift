//
//  GlassShellFileCommands.swift
//  Glass Power Tools — GlassShell
//
//  File ▸ New, owned once by the shell and aimed by whatever window is focused.
//
//  **Why the shell owns this placement.** Three merged apps each had their own File menu, and each
//  replaced `CommandGroup(.newItem)` to get it. Two replacements are not a merge: SwiftUI keeps one
//  and the other is silently absent, which is how the terminal's whole File group — ⌘T included —
//  disappeared from the shipped build. So exactly one scope replaces the placement, and it is the
//  one that belongs to no capability. Capabilities contribute with `CommandGroup(after: .newItem)`.
//
//  **Why ⌘N is a stub.** ⌘N means *new* — of whatever you are looking at. In a database workspace
//  that is a SQL document; in a terminal workspace, a terminal window; in the library, a host. One
//  key, one item, and the focused window decides both its title and what it does, so the menu
//  always says what ⌘N will actually make. The alternative — a fixed ⌘N owned by one capability —
//  is what the merge inherited, and it left ⌘N meaning "new SQL document" while a terminal was
//  frontmost.
//

import SwiftUI

/// What ⌘N makes in the focused window.
///
/// Published with `.focusedSceneValue(\.glassNewItem, …)` by each window that has an answer. A
/// window with none publishes nothing, and the item is offered as disabled rather than doing
/// something from a different window.
@MainActor
public struct GlassNewItemAction {
    /// The menu item's whole title — "New SQL Document", "New Terminal Window", "New Host". Written
    /// out rather than assembled from a noun, so each window says it in its own words.
    public let title: String
    private let action: () -> Void

    public init(title: String, _ action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public func callAsFunction() { action() }
}

private struct GlassNewItemActionKey: FocusedValueKey {
    typealias Value = GlassNewItemAction
}

public extension FocusedValues {
    var glassNewItem: GlassNewItemAction? {
        get { self[GlassNewItemActionKey.self] }
        set { self[GlassNewItemActionKey.self] = newValue }
    }
}

#if os(macOS)
/// The app's one File ▸ New item. Attached by the composition root to the library scene.
public struct GlassShellFileCommands: Commands {
    @FocusedValue(\.glassNewItem) private var newItem

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(newItem?.title ?? "New") { newItem?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newItem == nil)
        }
    }
}
#endif
