import SwiftUI

/// The Glass family canvas frost, composited independently of foreground pixels.
/// A zero amount leaves the canvas clear without fading its content or controls.
public struct GlassCanvasBackdrop: View {
    private let material: Material
    private let blurAmount: Double
    private let interactive: Bool
    private let colorScheme: ColorScheme?

    public init(
        material: Material = .ultraThinMaterial,
        blurAmount: Double,
        interactive: Bool = false,
        colorScheme: ColorScheme? = nil
    ) {
        self.material = material
        self.blurAmount = blurAmount.isFinite ? min(1, max(0, blurAmount)) : 0
        self.interactive = interactive
        self.colorScheme = colorScheme
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(material)

            #if os(visionOS)
            if interactive {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.clear)
                    .glassBackgroundEffect(in: .rect(cornerRadius: 24))
            }
            #endif
        }
        .opacity(blurAmount)
    }
}
