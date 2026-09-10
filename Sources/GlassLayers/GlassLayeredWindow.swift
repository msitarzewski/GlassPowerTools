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
    private let content: Content
    private let title: Title
    private let controls: Controls

    public init(
        showTitle: Bool = true,
        showControls: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder title: () -> Title,
        @ViewBuilder controls: () -> Controls
    ) {
        self.showTitle = showTitle
        self.showControls = showControls
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
        GlassLayerResolution.resolve(layers.state, reduceTransparency: reduceTransparency)
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
    init(@ViewBuilder content: () -> Content) {
        self.init(showTitle: false, showControls: false, content: content, title: { EmptyView() }, controls: { EmptyView() })
    }
}

/// A panel or detail surface drawing from the same state, with the family's rounded frost.
public struct GlassLayeredPanel<Content: View>: View {
    @Environment(\.glassLayers) private var layers
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let cornerRadius: CGFloat
    private let content: Content

    public init(cornerRadius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        let state = GlassLayerResolution.resolve(layers.state, reduceTransparency: reduceTransparency)
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
            GlassCanvasBackdrop(material: state.material.material, blurAmount: state.frost)
        }
        .allowsHitTesting(false)
    }
}

/// Accessibility takes precedence: Reduce Transparency makes every surface opaque and frosted,
/// as glassDT already does for its desktop canvas.
public enum GlassLayerResolution {
    public static func resolve(_ state: GlassLayerState, reduceTransparency: Bool) -> GlassLayerState {
        guard reduceTransparency else { return state }
        return GlassLayerState(opacity: 1, frost: 1, material: state.material, paintsTheme: true)
    }
}
