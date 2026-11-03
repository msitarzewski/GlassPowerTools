#if os(macOS) || os(iOS)
import Testing
@testable import GlassLayers

/// A Liquid Glass surface (the Mac's orb dock, D98) keeps what Glass, Material and Opacity mean on a window: how
/// much glass, which glass, and the theme's paint. None of them is left doing nothing (`glass-is-the-point`).
@Suite("Liquid Glass surfaces")
struct GlassLiquidLookTests {
    @Test("Material picks Apple's glass and how much it dims behind it: Clear for Light to Heavy, Regular for Max")
    func materialPicksTheGlass() {
        func look(_ material: GlassLayerMaterial) -> GlassLiquidLook {
            GlassLiquidLook(GlassLayerState(opacity: 0, frost: 1, material: material))
        }
        #expect(look(.ultraThin).kind == .clear && look(.ultraThin).dim == 0, "Light: Clear, nothing dimmed")
        #expect(look(.thin).kind == .clear && look(.thin).dim > 0)
        #expect(look(.regular).kind == .clear && look(.regular).dim > look(.thin).dim, "Heavy dims more than Medium")
        #expect(look(.regular).dim == GlassLiquidLook.heavyDim)
        #expect(look(.thick).kind == .regular, "Max: the frostier glass")
        #expect(GlassLiquidLook.Kind.clear.glass == .clear && GlassLiquidLook.Kind.regular.glass == .regular)
    }

    @Test("Glass is how much of it shows, the dimming with it; none leaves only Opacity's paint, or nothing")
    func glassIsHowMuch() {
        let half = GlassLiquidLook(GlassLayerState(opacity: 0, frost: 0.5, material: .regular))
        #expect(half.strength == 0.5)
        #expect(abs(half.dim - GlassLiquidLook.heavyDim / 2) < 0.0001, "dimmed as much as the glass shows")
        let none = GlassLiquidLook(GlassLayerState(opacity: 0, frost: 0, material: .regular))
        #expect(none.strength == 0 && none.dim == 0 && none.isEmpty, "no glass: the orbs float on the desktop")
        let painted = GlassLiquidLook(GlassLayerState(opacity: 0.4, frost: 0, material: .regular))
        #expect(painted.paint == 0.4 && !painted.isEmpty, "Opacity still paints the theme with no glass")
    }

    @Test("Reduce Transparency makes it opaque, glass and all")
    func reduceTransparency() {
        let state = GlassLayerResolution.resolve(GlassLayerState(opacity: 0, frost: 0, material: .ultraThin),
                                                 reduceTransparency: true)
        let look = GlassLiquidLook(state)
        #expect(look.paint == 1 && look.strength == 1)
    }
}
#endif
