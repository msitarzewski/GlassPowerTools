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
//  **The window is moved here, not by AppKit.** `NSSplitViewItem.collapseBehavior`'s
//  `.preferResizingSplitViewWithFixedSiblings` promises this ("keep the other panes at their current
//  size and position on screen, potentially growing or shrinking the window", macOS 27.2 SDK,
//  `NSSplitViewItem.h`), and does it for a SwiftUI split view in a window of one's own. In a SwiftUI
//  `WindowGroup` window — the terminal's — it doesn't (measured, macOS 27.2, a window-scene probe in
//  `~/Software/glass/tmp/sidebar-probe`): AppKit grows such a window by raising its minimum width, so
//  it grew to the right only and never shrank (SwiftUI's window controller holds the window's size),
//  and a minimum SwiftUI held on the whole content stopped even that — the owner's "pops back to the
//  original size violently". So AppKit is told to keep the window's size
//  (`.preferResizingSiblingsWithFixedSplitView`) and, the moment a sidebar starts to open or close,
//  the window's frame is animated alongside it by the sidebar's width, its far edge kept. Measured the
//  same way: the column beside it drifted 2 points at most through the animation, and not at all with
//  the view holding its width meanwhile (`willResizeWindow`).
//
//  SwiftUI exposes neither the items nor their state, so the items are found in the window's views,
//  as `MacTerminalWindowReader` finds the sidebar to open it. An item AppKit calls an inspector is
//  treated as a sidebar on the right; whether SwiftUI's `.inspector` makes one is for the terminal's
//  first right-hand sidebar to measure.
//

#if os(macOS)
import AppKit
import ObjectiveC

@MainActor
public enum GlassAdditiveSidebars {
    /// Posted as a sidebar starts to open or close and the window is about to follow it; the object is
    /// the window. A view beside the sidebar can hold its width meanwhile (`animationDuration`), so
    /// what it shows isn't laid out again for the points the two animations differ by.
    public static let willResizeWindow = Notification.Name("GlassAdditiveSidebarsWillResizeWindow")

    /// How long the window takes to follow a sidebar: AppKit's own sidebar animation's length, near
    /// enough (measured 0.27–0.29 s from the toggle to the last frame). Tests set it to 0.
    public static var animationDuration: TimeInterval = 0.25

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
        set(additive: additive, items: items, in: window)
        return !items.isEmpty
    }

    /// The same, for items already found.
    public static func set(additive: Bool, items: [NSSplitViewItem], in window: NSWindow) {
        let follower = Follower.of(window)
        follower.additive = additive
        for item in items {
            if item.collapseBehavior != .preferResizingSiblingsWithFixedSplitView {
                item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
            }
            follower.watch(item)
        }
    }

    /// Whether `window` grows and shrinks with its sidebars now.
    public static func isAdditive(_ window: NSWindow) -> Bool {
        Follower.existing(window)?.additive ?? false
    }

    /// The window's frame once a sidebar `width` wide has opened (or closed): wider (or narrower) by
    /// it, toward the sidebar's side — the left for a sidebar, the right for an inspector — so what
    /// is beside it stays where it is on screen. Opening keeps the window on `visible`, sliding it
    /// back in where it would cross an edge; nil where it can't be that wide (a zoomed window), and
    /// what is beside the sidebar gives way instead.
    public static func windowFrame(_ frame: NSRect, sidebarWidth width: CGFloat, opening: Bool, leading: Bool,
                                   visible: NSRect?) -> NSRect? {
        guard width > 0, width.isFinite else { return nil }
        var target = frame
        target.size.width += opening ? width : -width
        if leading { target.origin.x += opening ? -width : width }
        guard opening, let visible else { return target }
        guard target.width <= visible.width + 0.5 else { return nil }
        if target.minX < visible.minX { target.origin.x = visible.minX }
        if target.maxX > visible.maxX { target.origin.x = visible.maxX - target.width }
        return target
    }

    /// Watches a window's sidebars and moves the window as one starts to open or close.
    @MainActor
    private final class Follower: NSObject {
        nonisolated(unsafe) private static var key: UInt8 = 0
        weak var window: NSWindow?
        var additive = false
        private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
        private let watched = NSHashTable<NSSplitViewItem>.weakObjects()
        /// Each item's state as last followed (or let be, the window not additive then).
        private var followed: [ObjectIdentifier: Bool] = [:]
        /// Where the window is going, while it gets there.
        private var heading: NSRect?
        private var headingGeneration = 0
        private var lookScheduled = false

        static func existing(_ window: NSWindow) -> Follower? {
            objc_getAssociatedObject(window, &key) as? Follower
        }

        static func of(_ window: NSWindow) -> Follower {
            if let follower = existing(window) { return follower }
            let follower = Follower()
            follower.window = window
            objc_setAssociatedObject(window, &key, follower, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return follower
        }

        func watch(_ item: NSSplitViewItem) {
            let id = ObjectIdentifier(item)
            guard observations[id] == nil else { return }
            watched.add(item)
            followed[id] = item.isCollapsed
            observations[id] = item.observe(\.isCollapsed, options: [.old, .new]) { [weak self] _, change in
                guard change.oldValue != change.newValue else { return }
                MainActor.assumeIsolated { self?.changed(id) }
            }
        }

        private func item(_ id: ObjectIdentifier) -> NSSplitViewItem? {
            watched.allObjects.first { ObjectIdentifier($0) == id }
        }

        /// A sidebar started to open or close. One click can flip it more than once — AppKit opens
        /// it, then SwiftUI puts its own state back and forth (measured: three changes for one
        /// toggle) — so the window follows what they come to, a turn of the main queue later. What
        /// changes while the window isn't additive (the overview, the sidebar it gives back) is let
        /// be as it happens, whatever the window is by the time it is looked at.
        private func changed(_ id: ObjectIdentifier) {
            guard let item = item(id), let window else { return }
            guard additive else {
                followed[id] = item.isCollapsed
                return
            }
            // Now, before the sidebar's first frame: what is beside it holds its width meanwhile.
            if !lookScheduled {
                NotificationCenter.default.post(name: GlassAdditiveSidebars.willResizeWindow, object: window)
            }
            scheduleLook()
        }

        private func scheduleLook() {
            guard !lookScheduled else { return }
            lookScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.lookScheduled = false
                self?.follow()
            }
        }

        /// The window goes where its sidebars now say, from where it was already going — from the
        /// main queue's turn after the change, not inside it, where a window resized left the
        /// sidebar unfinished (measured: it stayed open and laid out at no width).
        private func follow() {
            guard let window else { return }
            var target = heading ?? window.frame
            var moved = false
            for item in watched.allObjects {
                let id = ObjectIdentifier(item)
                let collapsed = item.isCollapsed
                guard followed[id] != collapsed else { continue }
                followed[id] = collapsed
                guard additive, window.isVisible, !window.styleMask.contains(.fullScreen),
                      let next = GlassAdditiveSidebars.windowFrame(
                        target, sidebarWidth: item.viewController.view.frame.width, opening: !collapsed,
                        leading: item.behavior == .sidebar, visible: window.screen?.visibleFrame) else { continue }
                target = next
                moved = true
            }
            guard moved, target != window.frame else { return }
            heading = target
            headingGeneration += 1
            let generation = headingGeneration
            let duration = GlassAdditiveSidebars.animationDuration
            guard duration > 0 else {
                window.setFrame(target, display: true)
                heading = nil
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    if self?.headingGeneration == generation { self?.heading = nil }
                }
            }
        }
    }
}
#endif
