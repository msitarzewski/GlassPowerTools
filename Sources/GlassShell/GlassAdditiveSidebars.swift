//
//  GlassAdditiveSidebars.swift
//  Glass Power Tools — GlassShell
//
//  A sidebar that adds to its window rather than taking from what the window shows (the owner,
//  2026-10-16: "make the left (and eventually right) sidebars additive and not resize my terminal
//  window to make room"). Opened, the window grows by the sidebar's width toward the sidebar's side;
//  closed, it shrinks back; the terminal beside it keeps its size and its place on screen, so its rows
//  and columns (or, under Scale, its text) don't change.
//
//  **AppKit's own behaviour, asked for.** A SwiftUI `NavigationSplitView` on the Mac is an
//  `NSSplitViewController`, and its sidebar an `NSSplitViewItem` whose `collapseBehavior` says what
//  happens as it opens and closes (measured: `GlassAdditiveSidebarsTests`). An item AppKit calls an
//  inspector is treated the same; whether SwiftUI's `.inspector` makes one is for the terminal's
//  first right-hand sidebar to measure.
//  `NSSplitViewItemCollapseBehaviorPreferResizingSplitViewWithFixedSiblings`: "The item prefers to
//  keep the other panes at their current size and position on screen, potentially growing or
//  shrinking the window in the direction to best preserve that. But it will break that preference in
//  order to keep the window fully on screen or when in full screen" (macOS 27.2 SDK,
//  `NSSplitViewItem.h`). The default "may change over time", so the behaviour is set, not assumed,
//  both ways: `.preferResizingSiblingsWithFixedSplitView` keeps the window's size, for a view that
//  hides its sidebar to give its content the whole window (the terminal's overview).
//
//  SwiftUI exposes neither the item nor the behaviour, so the items are found in the window's views,
//  as `MacTerminalWindowReader` finds the sidebar to open it.
//

#if os(macOS)
import AppKit

@MainActor
public enum GlassAdditiveSidebars {
    /// The window's sidebars and inspectors, in the order its views hold them.
    public static func items(in window: NSWindow) -> [NSSplitViewItem] {
        guard let root = window.contentView else { return [] }
        var found: [NSSplitViewItem] = []
        var views = [root]
        var index = 0
        // A window's views, breadth first, to a bound: the split view sits a few levels in.
        while index < views.count, index < 512 {
            let view = views[index]
            index += 1
            if let split = view as? NSSplitView, let controller = split.delegate as? NSSplitViewController {
                found += controller.splitViewItems.filter { $0.behavior == .sidebar || $0.behavior == .inspector }
            }
            views.append(contentsOf: view.subviews)
        }
        return found
    }

    /// Opening or closing a sidebar or inspector in `window` grows or shrinks the window and leaves
    /// what is beside it alone (`additive`), or keeps the window's size and resizes what is beside
    /// it. False when the window has none yet (SwiftUI builds its split view after the first
    /// update; ask again).
    @discardableResult
    public static func set(additive: Bool, in window: NSWindow) -> Bool {
        let items = items(in: window)
        set(additive: additive, items: items)
        return !items.isEmpty
    }

    /// The same, for items already found.
    public static func set(additive: Bool, items: [NSSplitViewItem]) {
        let behavior: NSSplitViewItem.CollapseBehavior = additive
            ? .preferResizingSplitViewWithFixedSiblings
            : .preferResizingSiblingsWithFixedSplitView
        for item in items where item.collapseBehavior != behavior {
            item.collapseBehavior = behavior
        }
    }
}
#endif
