#if os(visionOS)
import SwiftUI

/// Native-window framing shared by Glass live canvases on visionOS.
/// The canvas owns its background and input; the system owns window placement and the controls'
/// ornament.
public struct GlassNativeWindowFrame<Content: View, Title: View, Controls: View>: View {
    private let showTitle: Bool
    private let showControls: Bool
    @Environment(\.glassWindowOutOfSight) private var outOfSight
    private let content: Content
    private let title: Title
    private let controls: Controls

    /// - Parameter controls: the window's controls as separate items — buttons, menus, a picker —
    ///   never wrapped in a stack: each becomes one item of Apple's toolbar ornament, which sizes
    ///   and spaces them itself.
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
        // As its orb, the window's title and controls go with it; the inset stays, so the content
        // kept out of sight is laid out as it was.
        let titleShown = showTitle && !outOfSight
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
            .padding(.top, showTitle ? GlassWindowShape.spatialTitleInset : 0)
            .padding(.bottom, showControls ? GlassWindowShape.spatialControlsInset : 0)
            // Visibility changes must not replace the live canvas host.
            .ornament(
                visibility: titleShown ? .visible : .hidden,
                attachmentAnchor: .scene(.top)
            ) {
                title.glassBackgroundEffect(in: .capsule)
            }
            // **The controls are Apple's toolbar ornament** (W31; the owner, on the Vision Pro,
            // 2026-10-10: "Why are these different sizes? Let's make them all the smaller apple
            // defaults"). A hand-built ornament — a stack of borderless buttons with its own
            // spacing and padding in a glass capsule — drew a bar of its own size beside the
            // system's. Here the system sizes the buttons, spaces them and draws the capsule, as it
            // does for the database's and the editor's.
            //
            // Only while `showControls`: a toolbar's items merge across every view in the window,
            // and several terminals share one (a workgroup's tabs are a stack of every terminal,
            // the hidden ones transparent), so only the one in front may contribute any. The
            // `.toolbar` modifier itself stays, so the canvas host is never replaced.
            .toolbar {
                if showControls && !outOfSight {
                    ToolbarItemGroup(placement: .bottomOrnament) { controls }
                }
            }
    }
}
#endif
