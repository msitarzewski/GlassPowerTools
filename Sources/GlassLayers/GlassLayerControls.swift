import SwiftUI
import GlassConnectionUI

/// The Appearance controls for the layering system, for the shared settings surface.
public struct GlassLayerControls: View {
    @Environment(\.glassLayers) private var layers
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        @Bindable var layers = layers
        Section {
            GlassSettingSlider(
                title: "Opacity", value: $layers.state.opacity, detents: [0, 0.5, 1],
                leadingAccessibilityLabel: "Transparent", trailingAccessibilityLabel: "Opaque",
                accessibilityIdentifier: "layers-opacity"
            )
            GlassSettingSlider(
                title: "Frost", value: $layers.state.frost, detents: [0, 0.5, 1],
                leadingAccessibilityLabel: "Clear", trailingAccessibilityLabel: "Frosted",
                accessibilityIdentifier: "layers-frost"
            )
            Picker("Material", selection: $layers.state.material) {
                ForEach(GlassLayerMaterial.allCases) { material in
                    Text(material.title).tag(material)
                }
            }
            .accessibilityIdentifier("layers-material")
            .disabled(layers.state.frost == 0)
            Button("Reset Appearance") { layers.reset() }
                .accessibilityIdentifier("layers-reset")
        } header: {
            Text("Glass")
        } footer: {
            if reduceTransparency {
                Text("Reduce Transparency is on in Accessibility. Every surface is opaque and frosted while it stays on.")
            } else {
                Text("Opacity paints the theme color behind content. Frost changes the material behind it, including the title bar. Set both to 0% for a clear window; text and controls stay visible. These are every window's; a terminal window can keep its own in its Settings, under This Window.")
            }
        }
        .disabled(reduceTransparency)
    }


}
