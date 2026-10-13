//
//  GlassWindowOpener.swift
//  Glass Power Tools — GlassShell
//
//  Opens the app's windows from outside any of them: an intent from Siri or Shortcuts, a widget's
//  tap, a Finder service, the Dock (D72, 2026-10-13). SwiftUI hands out `openWindow` only inside a
//  window's views, and the library's was the only one kept: with the Connections window closed and
//  terminal windows open — the owner's usual Mac — a request waited for a window that never came.
//  Every kind of window now registers its own; the latest one registered opens the next window,
//  and a request made before any window exists (the app launched for it) waits for the first.
//

import SwiftUI

@MainActor
public final class GlassWindowOpener {
    public static let shared = GlassWindowOpener()

    private var openWindow: OpenWindowAction?
    private var waiting: [(OpenWindowAction) -> Void] = []

    public init() {}

    /// Whether a window has registered yet.
    public var isReady: Bool { openWindow != nil }

    public func register(_ action: OpenWindowAction) {
        openWindow = action
        let ready = waiting
        waiting = []
        ready.forEach { $0(action) }
    }

    /// Runs `body` with an `openWindow` now, or as soon as a window registers one.
    public func perform(_ body: @escaping (OpenWindowAction) -> Void) {
        if let openWindow { body(openWindow) } else { waiting.append(body) }
    }
}

private struct GlassWindowOpenerRegistration: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { GlassWindowOpener.shared.register(openWindow) }
    }
}

public extension View {
    /// This window's `openWindow`, for opening windows from outside any of them (`GlassWindowOpener`).
    func glassRegistersWindowOpener() -> some View {
        modifier(GlassWindowOpenerRegistration())
    }
}
