import SwiftUI
import GlassConnectionUI

/// A window's content over the layering system: theme paint at `effectiveOpacity`, the frost
/// material at `frost`, and on macOS the window and title bar made transparent to match.
///
/// visionOS leads: there the content sits in `GlassNativeWindowFrame` with the family's title
/// and controls ornaments. Mac, iPad and iPhone adapt from that.
public struct GlassLayeredWindow<Content: View, Title: View, Controls: View>: View {
    @Environment(\.glassLayers) private var layers
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
        GlassLayerResolution.resolve(layers.state, reduceTransparency: reduceTransparency, paintsTheme: paintsTheme)
    }

    private var layered: some View {
        content
            .background {
                GlassLayerBackground(state: resolved, cornerRadius: 0)
                    .ignoresSafeArea()
            }
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
    /// A column or region inside a `GlassLayeredWindow`, which already paints edge to edge.
    case embedded
}

/// A panel or detail surface drawing from the same state.
///
/// visionOS leads: a panel is a floating surface with the family's rounded frost, so there it
/// always paints its own theme and frost inside `cornerRadius`. On the Mac, iPad and iPhone a
/// `.presented` panel paints the same way, while an `.embedded` panel is the content itself:
/// painting a second rounded card inside an already layered window doubled the theme paint,
/// clipped the detail's bottom action bar into a lighter band and let the window corner show
/// through (observed on the Mac, 2026-09-10).
public struct GlassLayeredPanel<Content: View>: View {
    @Environment(\.glassLayers) private var layers
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let cornerRadius: CGFloat
    private let role: GlassLayeredPanelRole
    private let content: Content

    public init(cornerRadius: CGFloat = 24, role: GlassLayeredPanelRole = .presented, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.role = role
        self.content = content()
    }

    private var paintsOwnSurface: Bool {
        #if os(visionOS)
        true
        #else
        role == .presented
        #endif
    }

    public var body: some View {
        if paintsOwnSurface {
            let state = GlassLayerResolution.resolve(layers.state, reduceTransparency: reduceTransparency)
            content
                .background {
                    GlassLayerBackground(state: state, cornerRadius: cornerRadius)
                }
                .clipShape(.rect(cornerRadius: cornerRadius))
        } else {
            content
        }
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
            GlassCanvasBackdrop(material: state.material.material, blurAmount: state.frost)
        }
        .allowsHitTesting(false)
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
}
