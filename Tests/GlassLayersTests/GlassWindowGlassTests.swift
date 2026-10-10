//
//  GlassWindowGlassTests.swift
//  Glass Power Tools — GlassLayersTests
//
//  W28 (owner, 2026-10-10): "I'd also like to rebuild all window appearances to match the new
//  terminal." Every plain window draws Apple's glass itself, as strong as its Glass setting, and
//  resolves that strength one way: Appearance's frost, the window's own over it, Reduce
//  Transparency keeping it whole. At 0 nothing is drawn, which is what makes a window clear.
//

import Testing
@testable import GlassLayers

@Suite("A window's glass is its Glass setting (W28)")
struct GlassWindowGlassTests {
    private func state(frost: Double, opacity: Double = 0) -> GlassLayerState {
        GlassLayerState(opacity: opacity, frost: frost, material: .regular)
    }

    @Test("a window that sets nothing draws Appearance's frost, whatever its opacity")
    func followsAppearance() {
        let none = GlassWindowOverrides()
        #expect(GlassWindowGlass.strength(state(frost: 1), window: none, reduceTransparency: false) == 1,
                "the starting Frost: Apple's glass, as the system's window draws it")
        #expect(GlassWindowGlass.strength(state(frost: 0), window: none, reduceTransparency: false) == 0,
                "Frost 0: no glass at all, so the window can be completely clear")
        #expect(GlassWindowGlass.strength(state(frost: 0.4), window: none, reduceTransparency: false) == 0.4)
        #expect(GlassWindowGlass.strength(state(frost: 0.4, opacity: 0.9), window: none, reduceTransparency: false) == 0.4,
                "Opacity paints the canvas; it never thickens the window's glass")
    }

    @Test("the window's own Glass wins over Appearance's, in both directions")
    func windowOverAppearance() {
        var clear = GlassWindowOverrides()
        clear[GlassLayerSettings.frost] = 0
        #expect(GlassWindowGlass.strength(state(frost: 1), window: clear, reduceTransparency: false) == 0,
                "This Window's 0: completely clear, whatever Appearance says")

        var frosted = GlassWindowOverrides()
        frosted[GlassLayerSettings.frost] = 0.75
        #expect(GlassWindowGlass.strength(state(frost: 0), window: frosted, reduceTransparency: false) == 0.75)

        var paintedOnly = GlassWindowOverrides()
        paintedOnly[GlassLayerSettings.opacity] = 1
        #expect(GlassWindowGlass.strength(state(frost: 0.3), window: paintedOnly, reduceTransparency: false) == 0.3,
                "a window that sets only its opacity follows Appearance's glass")
    }

    @Test("Reduce Transparency always draws the whole glass")
    func reduceTransparency() {
        var clear = GlassWindowOverrides()
        clear[GlassLayerSettings.frost] = 0
        #expect(GlassWindowGlass.strength(state(frost: 0), window: clear, reduceTransparency: true) == 1)
        #expect(GlassWindowGlass.strength(frost: 0, reduceTransparency: true) == 1)
    }

    @Test("Opacity paints the canvas at the window's own opacity, Appearance's elsewhere, and whole under Reduce Transparency")
    func canvasOpacity() {
        let none = GlassWindowOverrides()
        #expect(GlassWindowGlass.canvasOpacity(state(frost: 1, opacity: 0), window: none, reduceTransparency: false) == 0,
                "the starting Opacity paints nothing")
        #expect(GlassWindowGlass.canvasOpacity(state(frost: 0, opacity: 0.7), window: none, reduceTransparency: false) == 0.7,
                "the canvas's paint does not depend on the glass")

        var painted = GlassWindowOverrides()
        painted[GlassLayerSettings.opacity] = 0.25
        #expect(GlassWindowGlass.canvasOpacity(state(frost: 1, opacity: 0.9), window: painted, reduceTransparency: false) == 0.25)
        #expect(GlassWindowGlass.canvasOpacity(state(frost: 1, opacity: 0), window: painted, reduceTransparency: true) == 1)
    }

    @Test("a strength is a fraction: out-of-range values are clamped, and one that isn't a number draws none")
    func clamped() {
        #expect(GlassWindowGlass.strength(frost: 1.5, reduceTransparency: false) == 1)
        #expect(GlassWindowGlass.strength(frost: -0.2, reduceTransparency: false) == 0)
        #expect(GlassWindowGlass.strength(frost: .nan, reduceTransparency: false) == 0)
        #expect(GlassWindowGlass.strength(frost: .infinity, reduceTransparency: false) == 0)
        #expect(GlassWindowGlass.strength(frost: 0.5, reduceTransparency: false) == 0.5)
    }
}
