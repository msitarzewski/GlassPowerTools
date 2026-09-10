#if os(macOS)
import AppKit
import SwiftUI
import GlassConnectionUI

/// The family's window transparency sequence, applied from the layer state.
///
/// Identical in all three source applications: glas.sh `MacTerminalWindowPolicy.apply`
/// (`Platforms/macOS/MacTerminalWindowPolicy.swift:248-256`), glassdb
/// `MacDatabaseWorkspaceWindowPolicy.apply` (`Constants.swift:633-652`), glassDT
/// `DesktopMetalSurface.viewDidMoveToWindow` (`DesktopMetalSurface.swift:244-249`). The
/// addition here is that the passive title bar material follows `frost`, so the title bar
/// background is as transparent as the rest of the window.
@MainActor
public enum GlassWindowLayerPolicy {
    public static func apply(_ window: NSWindow, state: GlassLayerState) {
        // The window itself is clear; content and the title bar material decide what shows.
        // Never touch alphaValue: text and controls stay opaque.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        GlassWindowChrome.installTitlebarMaterial(in: window, materialStyle: .sidebar)
        if let material = titlebarMaterial(in: window) {
            material.alphaValue = state.frost
            material.isHidden = state.frost == 0
        }
    }

    /// The material `GlassWindowChrome` installed, if present.
    public static func titlebarMaterial(in window: NSWindow) -> GlassTitlebarMaterialView? {
        window.contentView?.superview?.subviews.compactMap { $0 as? GlassTitlebarMaterialView }.first
    }
}

/// Zero-size, non-hit-testing view that finds its window and applies the policy, re-applying
/// whenever the state changes. Same shape as the three apps' window readers.
struct GlassWindowLayerReader: NSViewRepresentable {
    let state: GlassLayerState

    func makeNSView(context: Context) -> ReaderView { ReaderView() }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.state = state
        view.applyIfPossible()
    }

    final class ReaderView: NSView {
        var state: GlassLayerState = .default

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyIfPossible()
        }

        func applyIfPossible() {
            guard let window else { return }
            GlassWindowLayerPolicy.apply(window, state: state)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
