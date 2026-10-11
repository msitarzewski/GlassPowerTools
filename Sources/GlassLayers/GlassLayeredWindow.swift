import SwiftUI
import GlassConnectionUI

/// A window's content over the layering system: theme paint at `effectiveOpacity`, the frost
/// material at `frost`, and on macOS the window and title bar made transparent to match.
///
/// visionOS leads: there the content sits in `GlassNativeWindowFrame` with the family's title
/// and controls ornaments. Mac, iPad and iPhone adapt from that.
public struct GlassLayeredWindow<Content: View, Title: View, Controls: View>: View {
    @Environment(\.glassLayers) private var layers
    /// The window's own Appearance, over the app's (W22): set at the window's root.
    @Environment(\.glassWindowOverrides) private var windowOverrides
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let showTitle: Bool
    private let showControls: Bool
    private let paintsTheme: Bool
    private let content: Content
    private let title: Title
    private let controls: Controls

    /// - Parameter paintsTheme: false when the content paints its own theme colour (a terminal
    ///   canvas); the window then supplies only chrome and frost, never a second theme layer.
    public init(
        showTitle: Bool = true,
        showControls: Bool = true,
        paintsTheme: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder title: () -> Title,
        @ViewBuilder controls: () -> Controls
    ) {
        self.showTitle = showTitle
        self.showControls = showControls
        self.paintsTheme = paintsTheme
        self.content = content()
        self.title = title()
        self.controls = controls()
    }

    public var body: some View {
        #if os(visionOS)
        GlassNativeWindowFrame(showTitle: showTitle, showControls: showControls) {
            layered
        } title: {
            title
        } controls: {
            controls
        }
        #elseif os(macOS)
        layered.background { GlassWindowLayerReader(state: resolved) }
        #else
        layered
        #endif
    }

    private var resolved: GlassLayerState {
        GlassLayerResolution.resolve(layers.state, window: windowOverrides, reduceTransparency: reduceTransparency,
                                     paintsTheme: paintsTheme)
    }

    private var layered: some View {
        content
            .background {
                GlassLayerBackground(state: resolved, cornerRadius: paintCornerRadius)
                    .ignoresSafeArea()
            }
    }

    /// **The window's shape, on the headset.** This paint fills the window, and a plain visionOS
    /// window has no shape to keep it in: painted square, it showed as dark square corners outside
    /// the rounded glass the content draws (Files and the editor, 2026-10-09). On a Mac or iPad the
    /// window shapes itself, and the paint stays square underneath.
    private var paintCornerRadius: CGFloat {
        #if os(visionOS)
        GlassWindowShape.paintCornerRadius(spatial: true, insetForOrnaments: showTitle || showControls)
        #else
        GlassWindowShape.paintCornerRadius(spatial: false, insetForOrnaments: false)
        #endif
    }
}

public extension GlassLayeredWindow where Title == EmptyView, Controls == EmptyView {
    init(paintsTheme: Bool = true, @ViewBuilder content: () -> Content) {
        self.init(showTitle: false, showControls: false, paintsTheme: paintsTheme, content: content, title: { EmptyView() }, controls: { EmptyView() })
    }
}

/// How a `GlassLayeredPanel` relates to the surface around it.
public enum GlassLayeredPanelRole: Sendable {
    /// Its own presentation: a sheet, popover or secondary window. It paints theme and frost on
    /// every platform, because nothing else paints that surface.
    case presented
    /// A column or region inside a `GlassLayeredWindow`, which already paints edge to edge (on
    /// Vision Pro, over the window's own glass and behind its columns): it paints nothing of its
    /// own anywhere.
    case embedded
}

/// A panel or detail surface drawing from the same state.
///
/// A `.presented` panel paints its own theme inside `cornerRadius` on every platform. An
/// `.embedded` panel is the content itself, everywhere. On the Mac, iPad and iPhone painting a
/// second rounded card inside an already layered window doubled the theme paint, clipped the
/// detail's bottom action bar into a lighter band and let the window corner show through
/// (observed on the Mac, 2026-09-10). On Vision Pro the window paints Opacity behind its columns
/// (`GlassNavigationWindowOpacity`, W32) over the glass it draws itself (`glassSpatialWindowGlass`,
/// W33). W28 had made an embedded panel a canvas there, set 34 points in from the window's
/// edges, which the owner saw as a dark panel: "remove the black background".
public struct GlassLayeredPanel<Content: View>: View {
    @Environment(\.glassLayers) private var layers
    /// The overrides of the window the panel is in (W22), so a sheet looks like its window.
    @Environment(\.glassWindowOverrides) private var windowOverrides
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let cornerRadius: CGFloat
    private let role: GlassLayeredPanelRole
    private let content: Content

    public init(cornerRadius: CGFloat = 24, role: GlassLayeredPanelRole = .presented,
                @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.role = role
        self.content = content()
    }

    public var body: some View {
        switch role {
        case .presented:
            presentedSurface(GlassLayerResolution.resolve(layers.state, window: windowOverrides,
                                                          reduceTransparency: reduceTransparency))
        case .embedded:
            content
        }
    }

    private func presentedSurface(_ state: GlassLayerState) -> some View {
        content
            .background {
                GlassLayerBackground(state: state, cornerRadius: cornerRadius)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

/// Theme paint under the shared `GlassCanvasBackdrop`. Not hit-testable; content owns input.
struct GlassLayerBackground: View {
    let state: GlassLayerState
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if state.effectiveOpacity > 0 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.glassThemeBackground)
                    .opacity(state.effectiveOpacity)
            }
            frost
        }
        .allowsHitTesting(false)
    }

    /// The frost layer.
    ///
    /// **On visionOS the system already provides the glass, and painting over it is what made the
    /// window read as a flat plate.** A `Material` fill is a *simulation* of depth designed for a
    /// 2-D display: on a Mac it samples the desktop behind the window and looks like glass, but in
    /// a headset it composites as an even translucent sheet with no specular edge and no response
    /// to the room's light — laid across the whole window it covers the real glass underneath with
    /// a convincing-looking grey rectangle.
    ///
    /// So here the frost *is* the window's own surface. The theme paint above still composites over
    /// it, which is the point of keeping opacity and frost independent: all four combinations
    /// survive, including a fully clear surface.
    @ViewBuilder private var frost: some View {
        #if os(visionOS)
        EmptyView()
        #else
        GlassCanvasBackdrop(material: state.material.material, blurAmount: state.frost)
        #endif
    }
}

/// Accessibility takes precedence: Reduce Transparency makes every surface opaque and frosted,
/// as glassDT already does for its desktop canvas.
public enum GlassLayerResolution {
    public static func resolve(_ state: GlassLayerState, reduceTransparency: Bool) -> GlassLayerState {
        resolve(state, reduceTransparency: reduceTransparency, paintsTheme: true)
    }

    /// A surface that paints its own theme opts out of the layer's theme paint; Reduce
    /// Transparency still wins, because an opaque window is an accessibility promise.
    public static func resolve(_ state: GlassLayerState, reduceTransparency: Bool, paintsTheme: Bool) -> GlassLayerState {
        if reduceTransparency {
            return GlassLayerState(opacity: 1, frost: 1, material: state.material)
        }
        guard paintsTheme else {
            // The surface paints its own theme colour, so the layer paints none.
            return GlassLayerState(opacity: 0, frost: state.frost, material: state.material)
        }
        return state
    }

    /// What a window draws (W22): the app's state with the window's own Appearance over it, field
    /// by field (`GlassLayerSettings`), then Reduce Transparency and a self-painting surface as
    /// above. A window that sets nothing draws exactly the app's.
    public static func resolve(_ state: GlassLayerState, window overrides: GlassWindowOverrides,
                               reduceTransparency: Bool, paintsTheme: Bool = true) -> GlassLayerState {
        resolve(state.overlaid(by: overrides), reduceTransparency: reduceTransparency, paintsTheme: paintsTheme)
    }
}
