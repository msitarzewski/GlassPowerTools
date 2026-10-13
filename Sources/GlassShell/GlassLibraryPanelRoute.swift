//
//  GlassLibraryPanelRoute.swift
//  Glass Power Tools — GlassShell
//
//  How something outside the library opens one of its sidebar panels, and, on the Mac, finds the
//  Connections window to show it in.
//
//  Workgroups lived in a window of its own until 2026-10-08, beside the same list in the library's
//  sidebar. The window went (resizing it crashed the app, and the owner asked why it existed at
//  all); its menu items now bring Connections forward on the Workgroups panel instead.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// "Open this panel in the library" — Workgroups from its menu items. Supplied to a capability by
/// the composition root, because the library is the shell's and a capability must not hold the
/// shell (the same seam as `GlassShowActiveConnections`).
public typealias GlassShowLibraryPanel = @MainActor (_ panelID: String) -> Void

#if os(macOS)
/// The Connections windows open now, so a menu item elsewhere in the app can bring one forward.
///
/// `openWindow(id: "main")` cannot: on the Mac the library is a `WindowGroup`, and opening it
/// always makes another window. A library window registers itself as it appears; nothing here
/// changes the window but its order.
@MainActor
public enum GlassLibraryWindows {
    private static let windows = NSHashTable<NSWindow>.weakObjects()

    static func register(_ window: NSWindow) { windows.add(window) }

    /// Whether a Connections window is open, shown or in the Dock, without bringing it forward.
    public static var isOpen: Bool {
        windows.allObjects.contains { $0.isVisible || $0.isMiniaturized }
    }

    /// Brings a Connections window forward — false when none is open, so the caller opens one.
    @discardableResult
    public static func bringForward() -> Bool {
        guard let window = windows.allObjects.first(where: { $0.isVisible || $0.isMiniaturized }) else {
            return false
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

/// Zero-size and non-hit-testing: records the library's window and does nothing else to it.
struct GlassLibraryWindowRegistration: NSViewRepresentable {
    func makeNSView(context: Context) -> RegistrationView { RegistrationView() }
    func updateNSView(_ nsView: RegistrationView, context: Context) {}

    final class RegistrationView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { GlassLibraryWindows.register(window) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
