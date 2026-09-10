import SwiftUI

private struct GlassLayersKey: EnvironmentKey {
    // SwiftUI reads environment defaults on the main actor; the store is main-actor isolated.
    static let defaultValue: GlassLayerStore = MainActor.assumeIsolated { GlassLayerStore() }
}

public extension EnvironmentValues {
    /// The application's layering store. Inject once at the composition root with `glassLayers(_:)`.
    var glassLayers: GlassLayerStore {
        get { self[GlassLayersKey.self] }
        set { self[GlassLayersKey.self] = newValue }
    }
}

public extension View {
    func glassLayers(_ store: GlassLayerStore) -> some View {
        environment(\.glassLayers, store)
    }
}

extension Color {
    /// The platform's theme background, painted at `effectiveOpacity` behind layered content.
    static var glassThemeBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color.black
        #endif
    }
}
