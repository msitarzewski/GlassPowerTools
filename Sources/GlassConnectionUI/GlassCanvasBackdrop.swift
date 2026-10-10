import SwiftUI

/// The Glass family canvas frost, composited independently of foreground pixels.
/// A zero amount leaves the canvas clear without fading its content or controls.
public struct GlassCanvasBackdrop: View {
    private let material: Material
    private let blurAmount: Double
    private let interactive: Bool
    private let colorScheme: ColorScheme?
    private let cornerRadius: CGFloat

    /// - Parameter cornerRadius: the canvas card's 24 by default; a Vision Pro terminal's frost is
    ///   the whole window, in the window's own corner.
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
