//
//  GlassShowAllWindows.swift
//  Glass Power Tools — GlassShell
//
//  **Show All Windows**: the Mac's overview of every window the app has open, and the one control
//  that opens it, in every kind of window. It began as Show All Terminals (W9), the terminal's own;
//  the owner, 2026-10-13, after trying it from a desktop: "I'd also like our 'expose' feature to
//  include all of our connection/service types", then "Seems then that the expose tools should be
//  available in every window type now then? one component?"
//
//  So, like the ⚡ (`GlassActiveConnections.swift`): the shell owns the action and the button, the
//  terminal draws the overlay — terminal windows with a tile per tab, as before — and every other
//  open session joins it from the shell's list (`GlassCapabilityRegistry.openSessions`), a group
//  per kind. ⇧⌘\ and Window ▸ Show All Windows keep their one owner (`TerminalLibraryCommands`).
//

import SwiftUI

@MainActor
public enum GlassShowAllWindows {
    public static let title = "Show All Windows"
    public static let symbolName = "rectangle.3.group"

    /// Opens or closes the overview. Set by the capability that draws it — the terminal, on the
    /// Mac; nil elsewhere, and then the button is not drawn rather than drawn dead.
    public static var toggle: (@MainActor (OpenWindowAction) -> Void)?

    /// Every open session, for the overview's groups beside the terminal windows. Set by the
    /// composition root, the one place that holds every capability.
    public static var openSessions: (@MainActor () -> [GlassOpenSession])?

    /// The kind a session belongs to, from its id's prefix (`GlassOpenSession.id`: "desktop:…").
    public static func kind(of session: GlassOpenSession) -> String? {
        session.id.split(separator: ":", maxSplits: 1).first.map(String.init)
    }
}

/// The toolbar's Show All Windows, the same in every window: a terminal's, a desktop's, a
/// database's, an editor's, and Connections.
public struct GlassShowAllWindowsButton: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        if let toggle = GlassShowAllWindows.toggle {
            Button(GlassShowAllWindows.title, systemImage: GlassShowAllWindows.symbolName) {
                toggle(openWindow)
            }
            .help(GlassShowAllWindows.title)
            .accessibilityIdentifier("show-all-windows")
        }
    }
}

#if os(macOS)
import AppKit

/// A two-finger pinch, added up over one gesture. Only a deliberate one counts: an ordinary hand
/// resting on the trackpad, or a scroll that wobbles, moves the total far less than this. (Moved
/// from the terminal's Show All Terminals, 2026-10-13, where it was `MacTerminalExposePinch`.)
public struct GlassWindowPinch {
    /// The summed magnification a gesture must reach. A deliberate pinch passes it in a fraction
    /// of a second; a stray one does not.
    public static let threshold: CGFloat = 0.3

    public enum Outcome: Equatable {
        case pinchedIn
        case pinchedOut
    }

    public private(set) var total: CGFloat = 0
    private var answered = false

    public init() {}

    /// One magnify event. Answers at most once per gesture.
    public mutating func track(_ magnification: CGFloat, phase: NSEvent.Phase) -> Outcome? {
        if phase.contains(.began) {
            total = 0
            answered = false
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            total = 0
            answered = false
            return nil
        }
        guard !answered, magnification.isFinite else { return nil }
        total += magnification
        if total <= -Self.threshold {
            answered = true
            return .pinchedIn
        }
        if total >= Self.threshold {
            answered = true
            return .pinchedOut
        }
        return nil
    }
}

/// Watches one window's pinches and keeps every one of them from the views inside it: nothing in
/// the window is zoomed or sent anything by a pinch. Events in other windows pass untouched. So it
/// belongs only on windows whose content does not pinch to zoom — a terminal's, a desktop's — not
/// a database's diagram or an editor's text, which do.
public struct GlassWindowPinchMonitor: NSViewRepresentable {
    let onPinch: (GlassWindowPinch.Outcome) -> Void

    public init(onPinch: @escaping (GlassWindowPinch.Outcome) -> Void) { self.onPinch = onPinch }

    public func makeNSView(context: Context) -> MonitorView { MonitorView() }
    public func updateNSView(_ view: MonitorView, context: Context) { view.onPinch = onPinch }
    public static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    public final class MonitorView: NSView {
        var onPinch: ((GlassWindowPinch.Outcome) -> Void)?
        private var monitor: Any?
        private var pinch = GlassWindowPinch()

        override public func hitTest(_ point: NSPoint) -> NSView? { nil }

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                if let outcome = self.pinch.track(event.magnification, phase: event.phase) { self.onPinch?(outcome) }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private struct GlassShowAllWindowsOnPinch: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.background {
            GlassWindowPinchMonitor { outcome in
                if outcome == .pinchedIn { GlassShowAllWindows.toggle?(openWindow) }
            }
        }
    }
}

public extension View {
    /// A pinch in on this window opens Show All Windows, as it does on a terminal's (the owner,
    /// 2026-10-13: "it just doesn't activate while on a desktop with the gesture"). Only for a window
    /// whose content does not pinch to zoom (`GlassWindowPinchMonitor`).
    func glassShowAllWindowsOnPinch() -> some View {
        modifier(GlassShowAllWindowsOnPinch())
    }
}
#endif
