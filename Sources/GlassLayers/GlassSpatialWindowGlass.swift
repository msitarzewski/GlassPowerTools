//
//  GlassSpatialWindowGlass.swift
//  Glass Power Tools — GlassLayers
//
//  **Apple's window glass, drawn by the window itself** (D59, then W28 for every kind of window).
//  The owner, on the headset (2026-10-10): "We've lost complete transparency ... 100% transparent
//  glass (the whole point of the app)", and of the windows besides the terminal: "I'd also like to
//  rebuild all window appearances to match the new terminal."
//
//  The system's own window keeps its glass whenever it has focus, so a window in it can never be
//  clearer than that glass. A Glass window is `.windowStyle(.plain)` instead and draws the glass
//  itself, once, behind everything in it: `glassBackgroundEffect` in Apple's own 46-point
//  continuous corner, faded to the window's Glass, and not drawn at all at 0. At 0 the window is
//  completely clear; at 1 it looks as Apple's window does. Opacity is separate: it paints a
//  window's content area (its canvas), never the window.
//
//  **What a plain window cannot clear.** A `NavigationSplitView` or `NavigationStack` draws system
//  glass of its own behind every column, in a plain window too, and nothing public turns it off on
//  visionOS 27 (W28, traced in the simulator: `glassBackgroundEffect(displayMode: .never)` on the
//  container or its columns, toolbar backgrounds, toolbar visibility, every split view style and a
//  `TabView` around it all leave it; `containerBackground(_:for: .navigation)` is unavailable on
//  visionOS). So no Glass window uses one on the headset: since W33 (2026-10-10; the owner, of
//  Connections, the database, the editor and Files: "Yes, all four") they lay out their own columns
//  (`GlassSpatialSplitView`, `GlassSpatialColumn` in GlassConnectionUI) and draw this glass, and a
//  `TabView` alone draws none. Opacity paints the theme colour over it, edge to edge in the
//  window's own shape (`GlassNavigationWindowOpacity`, W32: "Opacity is essential transparency is
//  essential"), so Glass 0 and Opacity 0 leave only the text and controls.
//

import SwiftUI
import GlassConnectionUI

/// How strong a window's glass is: its Glass setting (Appearance's frost, the window's own where it
/// sets one), with Reduce Transparency keeping it at full strength.
public enum GlassWindowGlass {
    /// Whether a window whose content has a canvas also paints the theme behind the whole window
    /// (`GlassLayeredWindow(paintsTheme:)`). Everywhere but the headset: there Opacity paints the
    /// canvas alone, as a terminal's does (W28). A window of columns names its own instead
    /// (`GlassNavigationWindowOpacity`, W32).
    public static var paintsWholeWindow: Bool {
        #if os(visionOS)
        false
        #else
        true
        #endif
    }

    /// The glass for a window whose setting resolves to `frost`, 0…1. Reduce Transparency always
    /// draws the whole glass: an opaque-looking window is an accessibility promise. A value that
    /// isn't a number draws none.
    public static func strength(frost: Double, reduceTransparency: Bool) -> Double {
        if reduceTransparency { return 1 }
        guard frost.isFinite else { return 0 }
        return min(1, max(0, frost))
    }

    /// The glass for a window that follows Appearance: the app's frost, with the window's own
    /// (`GlassLayerSettings.frost`) over it.
    public static func strength(_ state: GlassLayerState, window: GlassWindowOverrides,
                                reduceTransparency: Bool) -> Double {
        strength(frost: state.overlaid(by: window).frost, reduceTransparency: reduceTransparency)
    }

    /// How strongly Opacity paints a window's canvas: Appearance's opacity, the window's own over
    /// it, and whole under Reduce Transparency — the paint `GlassLayeredWindow` draws, given to
    /// the canvas rather than to the window.
    public static func canvasOpacity(_ state: GlassLayerState, window: GlassWindowOverrides,
                                     reduceTransparency: Bool) -> Double {
        GlassLayerResolution.resolve(state, window: window, reduceTransparency: reduceTransparency).effectiveOpacity
    }
}

/// **How a window of columns shows Opacity on Vision Pro** (W32, 2026-10-10): Connections, the
/// editor, Files, the database. Each kind of window names its own value in one place, so one kind
/// can change without the others. Off the headset every window paints edge to edge as it always
/// has, whatever this says. Since W33 these windows draw their own glass at Glass
/// (`glassSpatialWindowGlass()`) and their own columns, where they had a navigation container's
/// system glass that nothing could clear.
public enum GlassNavigationWindowOpacity: Sendable, Equatable {
    /// The theme colour at Opacity, edge to edge in the window's own shape, over the window's own
    /// glass and behind its columns; and a window's text (the editor's, the SQL editor's) on a
    /// ground at the same Opacity. Nothing is painted at 0, so the window is its Glass exactly. No
    /// inset card: W28's canvas, set 34 points in from the window's edges, read as a dark panel
    /// (the owner: "remove the black background").
    case behindColumns
    /// Nothing at any Opacity: the window's glass alone.
    case none
}

public extension GlassWindowGlass {
    /// `GlassLayeredWindow(paintsTheme:)` for a window of columns.
    static func paintsTheme(_ opacity: GlassNavigationWindowOpacity) -> Bool {
        #if os(visionOS)
        opacity == .behindColumns
        #else
        true
        #endif
    }

    /// The Opacity a window of columns' own surfaces paint at (the editor's text ground, the
    /// database's surfaces), given the window's resolved Opacity (`canvasOpacity`): the same, or
    /// none in a window that paints none.
    static func surfaceOpacity(_ resolved: Double, _ opacity: GlassNavigationWindowOpacity) -> Double {
        #if os(visionOS)
        opacity == .behindColumns ? resolved : 0
        #else
        resolved
        #endif
    }
}

#if os(visionOS)
/// Apple's window glass, in Apple's corner, faded to `strength` and not drawn at all at 0. Drawn
/// once, behind the whole of a plain window (`glassSpatialWindowGlass(strength:)`).
public struct GlassSpatialWindowGlass: View {
    private let strength: Double

    public init(strength: Double) {
        self.strength = strength
    }

    public var body: some View {
        if strength > 0 {
            Color.clear
                .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: GlassWindowShape.spatialWindowCornerRadius,
                                                            style: .continuous))
                .opacity(strength)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

public extension View {
    /// This plain window's glass, at `strength`, behind everything in it and out to the window's
    /// edges. Apply once, at the window's root.
    func glassSpatialWindowGlass(strength: Double) -> some View {
        background {
            GlassSpatialWindowGlass(strength: strength)
                .ignoresSafeArea()
        }
    }

    /// This plain window's glass at its Appearance: the app's frost, the window's own over it
    /// (`\.glassWindowOverrides`, so apply it inside `glassWindowOverrides(_:)`), and Reduce
    /// Transparency.
    func glassSpatialWindowGlass() -> some View {
        modifier(GlassSpatialAppearanceGlass())
    }
}

/// The window's glass from the layer state the window draws with.
private struct GlassSpatialAppearanceGlass: ViewModifier {
    @Environment(\.glassLayers) private var layers
    @Environment(\.glassWindowOverrides) private var windowOverrides
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.glassSpatialWindowGlass(strength: GlassWindowGlass.strength(layers.state, window: windowOverrides,
                                                                             reduceTransparency: reduceTransparency))
    }
}

// The inset canvas Opacity once painted in a window of columns (`glassSpatialCanvas`, W28) went
// with the database's prototype (W33): those windows paint Opacity edge to edge (W32), and the
// terminal and the remote desktop draw their canvases themselves.
#endif
