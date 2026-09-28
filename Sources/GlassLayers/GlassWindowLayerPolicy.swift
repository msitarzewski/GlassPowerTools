#if os(macOS)
import AppKit
import SwiftUI
import GlassConnectionUI

/// The family's window transparency sequence, applied from the layer state.
///
/// Identical in all three source applications: glas.sh `MacTerminalWindowPolicy.apply`
/// (`Platforms/macOS/MacTerminalWindowPolicy.swift:248-256`), glassdb
/// `MacDatabaseWorkspaceWindowPolicy.apply` (`Constants.swift:633-652`), glassDT
/// `DesktopMetalSurface.viewDidMoveToWindow` (`DesktopMetalSurface.swift:244-249`). The passive
/// title bar material stays at full strength: frost and opacity are for the content, not for the
/// band that names the window.
@MainActor
public enum GlassWindowLayerPolicy {
    public static func apply(_ window: NSWindow, state: GlassLayerState) {
        // The window itself is clear; content and the title bar material decide what shows.
        // Never touch alphaValue: text and controls stay opaque.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        GlassWindowChrome.installTitlebarMaterial(in: window, materialStyle: .sidebar)
        // **The title band keeps its full material, whatever the frost.** It used to follow `frost`,
        // so at 0.67 a third of the window behind showed through the title, sharp, and at 0 it
        // vanished — the band that says which machine this is became the one part of the window
        // you could not read (2026-09-28, "our terminal title bar has reverted to full
        // transparency"). Rule 50: chrome that says where you are does not become see-through.
        // Frost and opacity still decide the content below it.
        if let material = titlebarMaterial(in: window) {
            material.alphaValue = 1
            material.isHidden = false
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
