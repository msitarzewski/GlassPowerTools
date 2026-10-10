import SwiftUI
import GlassConnectionUI

/// The Appearance controls for the layering system, for the shared settings surface: every
/// window's **Opacity**, **Glass** and **Material** — the words every This Window uses too (W27).
///
/// No Material on Vision Pro: every window's glass there is Apple's own, and a layer paints no
/// frost over it (`7478a39`). The stored value stays for the Mac and iPad.
public struct GlassLayerControls: View {
    @Environment(\.glassLayers) private var layers
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        @Bindable var layers = layers
        Section {
            GlassSettingSlider(
                title: GlassLayerSettings.opacity.title, value: $layers.state.opacity, detents: [0, 0.5, 1],
                leadingAccessibilityLabel: "Transparent", trailingAccessibilityLabel: "Opaque",
                accessibilityIdentifier: "layers-opacity"
            )
            GlassSettingSlider(
                title: GlassLayerSettings.frost.title, value: $layers.state.frost, detents: [0, 0.5, 1],
                leadingAccessibilityLabel: "No glass", trailingAccessibilityLabel: "Full glass",
                accessibilityIdentifier: "layers-frost"
            )
            #if !os(visionOS)
            Picker(GlassLayerSettings.material.title, selection: $layers.state.material) {
                ForEach(GlassLayerMaterial.allCases) { material in
                    Text(material.title).tag(material)
                }
            }
            .accessibilityIdentifier("layers-material")
            .disabled(layers.state.frost == 0)
            #endif
            Button("Reset Appearance") { layers.reset() }
                .accessibilityIdentifier("layers-reset")
        } header: {
            Text("Windows")
        } footer: {
            if reduceTransparency {
                Text("Reduce Transparency is on in Accessibility. Every surface is opaque while it stays on.")
            } else {
                Text("Opacity paints the theme color behind content, and Glass is the glass behind it, including the title bar. Set both to 0% for a clear window; text and controls stay visible. These are every window's; a window can keep its own in its Settings, under This Window.")
            }
        }
        .disabled(reduceTransparency)
    }
}
