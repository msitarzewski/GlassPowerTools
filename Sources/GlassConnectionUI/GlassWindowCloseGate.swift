//
//  GlassWindowCloseGate.swift
//  Glass Power Tools — GlassConnectionUI
//
//  Asks before a SwiftUI window closes, as AppKit lets a window's delegate do and SwiftUI does
//  not (2026-10-17: closing an editor window threw its unsaved changes away without a word).
//
//  SwiftUI owns the window's delegate, so the gate stands in for it and forwards everything else
//  to it — the technique the terminal window's close question has used since glas.sh
//  (`MacTerminalWindowReader.Coordinator`), here on its own so any window can ask.
//

#if os(macOS)
import AppKit
import SwiftUI

/// Placed in a window's background: before the window closes — its close button, File ▸ Close,
/// `performClose` — `shouldClose` is asked. True lets it close; false keeps it, having started
/// whatever asks. A programmatic `NSWindow.close()` is not asked, which is how a window closes
/// itself once the question has been answered.
public struct GlassWindowCloseGate: NSViewRepresentable {
    let shouldClose: @MainActor () -> Bool

    public init(shouldClose: @escaping @MainActor () -> Bool) {
        self.shouldClose = shouldClose
    }

    public func makeNSView(context: Context) -> GateView {
        let view = GateView(frame: .zero)
        view.gate.shouldClose = shouldClose
        return view
    }

    public func updateNSView(_ view: GateView, context: Context) {
        view.gate.shouldClose = shouldClose
        view.install()
    }

    public final class GateView: NSView {
        let gate = Gate()

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }

        /// Again at every update: SwiftUI may set its own delegate back.
        func install() {
            if let window { gate.attach(to: window) } else { gate.detach() }
        }

        override public func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    /// The window's delegate while the gate is on screen. A window holds its delegate weakly; the
    /// gate's view holds this.
    @MainActor
    public final class Gate: NSObject, NSWindowDelegate {
        var shouldClose: (@MainActor () -> Bool)?
        private weak var window: NSWindow?
        nonisolated(unsafe) private weak var original: (any NSWindowDelegate)?

        func attach(to window: NSWindow) {
            if self.window !== window { detach() }
            self.window = window
            guard window.delegate !== self else { return }
            original = window.delegate
            window.delegate = self
        }

        func detach() {
            if let window, window.delegate === self { window.delegate = original }
            window = nil
            original = nil
        }

        public func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard original?.windowShouldClose?(sender) != false else { return false }
            return shouldClose?() ?? true
        }

        // Every other delegate method is SwiftUI's.
        nonisolated override public func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        nonisolated override public func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true { return original }
            return super.forwardingTarget(for: selector)
        }
    }
}
#endif
