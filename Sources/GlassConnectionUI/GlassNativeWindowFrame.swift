#if os(visionOS)
import SwiftUI

/// Native-window framing shared by Glass live canvases on visionOS.
/// The canvas owns its background and input; the system owns window placement.
public struct GlassNativeWindowFrame<Content: View, Title: View, Controls: View>: View {
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
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The inset exists to keep content clear of the title and control ornaments, so it
            // follows them. A surface that shows neither — the library, which is a
            // `NavigationSplitView` — must reach the window's edges, or visionOS draws its sidebar
            // surface inside the inset and the result is a darker rectangle floating in the middle
            // of the window with a visible seam on every side. A live canvas keeps its padding.
            // The side inset is the one a canvas card's corner is concentric with
            // (`GlassWindowShape.spatialCanvasCornerRadius`).
            .padding(.horizontal, showTitle || showControls ? GlassWindowShape.spatialCanvasInset : 0)
            .padding(.top, showTitle ? 34 : 0)
            .padding(.bottom, showControls ? 26 : 0)
            // Visibility changes must not replace the live canvas host.
            .ornament(
                visibility: showTitle ? .visible : .hidden,
                attachmentAnchor: .scene(.top)
            ) {
                title.glassBackgroundEffect(in: .capsule)
            }
            .ornament(
                visibility: showControls ? .visible : .hidden,
                attachmentAnchor: .scene(.bottom)
            ) {
                controls.glassBackgroundEffect(in: .capsule)
            }
    }
}
#endif
