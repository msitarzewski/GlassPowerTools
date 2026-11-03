import SwiftUI

/// The Glass family canvas frost, composited independently of foreground pixels.
/// A zero amount leaves the canvas clear without fading its content or controls.
public struct GlassCanvasBackdrop: View {
    private let material: Material
    private let blurAmount: Double
    private let interactive: Bool
    private let colorScheme: ColorScheme?
    private let cornerRadius: CGFloat

    /// `cornerRadius`: the frost's corners, the same as what it lies over. Over a window's paint, which
    /// the window's own corners shape, none: frost rounded more tightly than the window left the paint
    /// bare in its corners, a dark crescent under the Mac's orb dock (the owner, 2026-11-02: "what's
    /// causing this odd corner display. Did we add an artificial black border for some reason?").
    public init(
        material: Material = .ultraThinMaterial,
        blurAmount: Double,
        interactive: Bool = false,
        colorScheme: ColorScheme? = nil,
        cornerRadius: CGFloat = 24
    ) {
        self.material = material
        self.blurAmount = blurAmount.isFinite ? min(1, max(0, blurAmount)) : 0
        self.interactive = interactive
        self.colorScheme = colorScheme
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        if blurAmount > 0 {
            if let colorScheme {
                materialLayers.environment(\.colorScheme, colorScheme)
            } else {
                materialLayers
            }
        }
    }

    private var materialLayers: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(material)

            #if os(visionOS)
            if interactive {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassBackgroundEffect(in: .rect(cornerRadius: cornerRadius))
            }
            #endif
        }
        .opacity(blurAmount)
    }
}
