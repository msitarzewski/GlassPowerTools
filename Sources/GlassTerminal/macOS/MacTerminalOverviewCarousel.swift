//
//  MacTerminalOverviewCarousel.swift
//  Glass Power Tools — GlassTerminal
//
//  The window's overview as a row that flows past the tab in front, as an album view did (the owner,
//  2026-11-02: "i really wanted the carousel to work like the old album view in itunes, but we never got
//  there", then, asked whether to build it: "i dare you 😂 sick live animations, agent like expose?"). The
//  first carousel (removed by D96 the same day) showed three cards turned 12°; this one shows the row: the tab
//  in front flat and large, the rest turned steeply toward it and stacked close on either side, each with its
//  reflection, flowing with a trackpad, a drag, the arrow keys or new output.
//
//  The row itself moved to the shell (`GlassCarouselRow`, D99) so iPhone, iPad and Vision Pro draw the same one;
//  the Mac gives it Show All Windows' tiles (`MacTerminalExposeTabTile`: the live picture, the coding agent's mark,
//  the wave while it prints) and its trackpad.
//

#if os(macOS)
import AppKit
import SwiftUI
import GlassShell

/// The Mac's names for the shared row's pieces, as they were before the row moved to the shell.
typealias MacTerminalOverviewStyle = TerminalOverviewStyle
typealias MacTerminalCarouselGeometry = GlassCarouselGeometry
typealias MacTerminalCarouselPlacement = GlassCarouselPlacement
typealias MacTerminalCarouselScroll = GlassCarouselScroll

/// The carousel: this window's tabs, as Show All Windows draws them, in a row that flows.
struct MacTerminalCarousel: View {
    let tiles: [MacTerminalExposeTile]
    let tabs: [UUID: MacWorkspaceController]
    @Binding var selection: MacTerminalExposeItemID?
    let blurred: Bool
    let activate: (UUID) -> Void

    /// The tiles that are tabs of this window, in order.
    private var shown: [(tile: MacTerminalExposeTile, tab: MacWorkspaceController)] {
        tiles.compactMap { tile in
            guard case .tab(let id) = tile.id, let tab = tabs[id] else { return nil }
            return (tile, tab)
        }
    }

    var body: some View {
        let shown = self.shown
        let byID = Dictionary(shown.map { ($0.tile.id, $0) }, uniquingKeysWith: { first, _ in first })
        GlassCarouselRow(
            items: shown.map { entry in
                GlassCarouselItem(id: entry.tile.id, title: entry.tile.title, detail: entry.tile.location,
                                  detailTruncation: entry.tile.repository == nil ? .head : .tail,
                                  identifier: "terminal-overview-tab-\(entry.tab.workspaceID.uuidString.lowercased())")
            },
            selection: $selection,
            activate: { id in if case .tab(let tab) = id { activate(tab) } },
            scrollMonitor: { scrolled in AnyView(MacTerminalCarouselScrollMonitor(scrolled: scrolled)) }
        ) { item, _ in
            if let entry = byID[item.id] {
                MacTerminalExposeTabTile(tab: entry.tab, tile: entry.tile, selected: false, hovering: false,
                                         alwaysVisible: true, blurred: blurred)
            }
        } reflection: { item, _ in
            if let entry = byID[item.id] {
                MacWorkspacePreview(controller: entry.tab, alwaysVisible: true)
                    .blur(radius: blurred ? GlassShowAllWindows.previewBlurRadius : 0)
            }
        }
        .accessibilityIdentifier("terminal-overview-carousel")
    }
}

/// Hears the scroll wheel and trackpad over this window while the carousel shows, and keeps them from the
/// terminals hidden under it.
private struct MacTerminalCarouselScrollMonitor: NSViewRepresentable {
    let scrolled: (MacTerminalCarouselScroll) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) { view.scrolled = scrolled }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var scrolled: ((MacTerminalCarouselScroll) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                // Along the row: a sideways swipe, or a wheel or an up-and-down swipe when that is all there is.
                let across = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
                self.scrolled?(MacTerminalCarouselScroll(delta: across, precise: event.hasPreciseScrollingDeltas))
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
