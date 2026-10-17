//
//  MacWorkspaceToolbarHold.swift
//  Glass Power Tools — GlassTerminal
//
//  "+" and the window's title stay where they are as a terminal window's sidebar opens and closes
//  (the owner, 2026-10-17: "keep the + and title fixed"). The terminal keeps its place (D77), but
//  with the sidebar closed the window's buttons and the sidebar's button come first in the toolbar,
//  over the terminal, and with it open they move over the sidebar: "+" and the title followed them,
//  132 pt to the left (macOS 27.2). An empty item before "+" holds that room while the sidebar
//  shows, as wide as it shows: the toolbar puts "+" after the room the buttons take or after the
//  sidebar's edge, whichever is further, and the two together are the same width (measured in a
//  scene probe through each frame of a toggle, 2026-10-17).
//
//  A toolbar item is never narrower than 36 pt, so the hold appears once the sidebar shows that
//  much: as the sidebar starts to open, and as it finishes closing, "+" moves up to 36 pt and back
//  over two frames.
//

#if os(macOS)
import AppKit

enum MacWorkspaceToolbarHold {
    /// The narrowest a toolbar item is drawn (macOS 27.2): a hold any narrower would be wider than
    /// asked.
    static let smallestItem: CGFloat = 36

    /// The room before "+" with the sidebar closed, as macOS 27.2 lays the toolbar out: used until
    /// the window's own toolbar says (`room(in:)`).
    static let usualRoom: CGFloat = 132

    /// The hold before "+" while `sidebarShowing` points of sidebar show: as wide as it shows, to
    /// `room` — or none while that is narrower than a toolbar item.
    static func width(sidebarShowing: CGFloat, room: CGFloat) -> CGFloat? {
        let width = min(max(0, sidebarShowing), room)
        return width >= smallestItem ? width : nil
    }

    /// Where the sidebar's button ends, from the window's leading edge: the room before "+" while
    /// the toolbar is laid out for a closed sidebar, as it is until the sidebar shows a toolbar
    /// item's width. Nil if the toolbar has no such button on show.
    static func room(in window: NSWindow) -> CGFloat? {
        guard let item = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue.contains("toggleSidebar") }),
              let view = item.view, view.window === window, !view.isHiddenOrHasHiddenAncestor else { return nil }
        let frame = view.convert(view.bounds, to: nil)
        // Something laid out, at the leading end: not a toolbar still being built.
        guard frame.width > 0, frame.maxX > smallestItem, frame.maxX < window.frame.width / 2 else { return nil }
        return frame.maxX
    }
}
#endif
