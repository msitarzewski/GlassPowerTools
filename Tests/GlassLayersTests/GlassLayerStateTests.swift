import Foundation
import Testing
@testable import GlassLayers

@Suite("GlassLayerState")
struct GlassLayerStateTests {
    @Test("Default is decision D2: transparent, frost on, ultra-thin, theme off")
    func defaultMatchesDecision() {
        let state = GlassLayerState.default
        #expect(state.opacity == 0)
        #expect(state.frost == 1)
        #expect(state.material == .ultraThin)
        #expect(state.effectiveOpacity == 0)
        #expect(!state.isFullyTransparent)
    }

    @Test("Init clamps to the unit interval and treats non-finite as zero")
    func initClamps() {
        let high = GlassLayerState(opacity: 4, frost: 1.5, material: .thick)
        #expect(high.opacity == 1 && high.frost == 1)
        let low = GlassLayerState(opacity: -1, frost: -0.2, material: .thin)
        #expect(low.opacity == 0 && low.frost == 0)
        let nan = GlassLayerState(opacity: .nan, frost: .infinity, material: .regular)
        #expect(nan.opacity == 0 && nan.frost == 0)
    }

    @Test("Codable round trip preserves every field")
    func codableRoundTrip() throws {
        let original = GlassLayerState(opacity: 0.37, frost: 0.62, material: .regular)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GlassLayerState.self, from: data)
        #expect(decoded == original)
    }

    @Test("Decoding clamps out-of-range values and tolerates missing or unknown fields")
    func decodingIsDefensive() throws {
        let json = #"{"opacity": 7, "frost": -3, "material": "mirror"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GlassLayerState.self, from: json)
        #expect(decoded.opacity == 1)
        #expect(decoded.frost == 0)
        #expect(decoded.material == .ultraThin)
        #expect(decoded.effectiveOpacity == 1, "opacity alone says whether the theme is painted")

        let empty = try JSONDecoder().decode(GlassLayerState.self, from: "{}".data(using: .utf8)!)
        #expect(empty == .default)
    }

    @Test("Opacity alone says whether the theme is painted; there is no second switch")
    func effectiveOpacity() {
        var state = GlassLayerState(opacity: 0.8, frost: 0, material: .thin)
        #expect(state.effectiveOpacity == 0.8)
        #expect(!state.isFullyTransparent)
        state.opacity = 0
        #expect(state.effectiveOpacity == 0)
        #expect(state.isFullyTransparent, "zero opacity and no frost is a fully clear surface")
    }

    @Test("A stored paintsTheme of false is migrated by zeroing the opacity, not by ignoring it")
    func retiredPaintsThemeMigratesIntoOpacity() throws {
        let off = #"{"opacity": 0.92, "frost": 0.5, "material": "thin", "paintsTheme": false}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(GlassLayerState.self, from: off).effectiveOpacity == 0,
                "someone who had theme paint switched off keeps an unpainted surface")

        let on = #"{"opacity": 0.92, "frost": 0.5, "material": "thin", "paintsTheme": true}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(GlassLayerState.self, from: on).effectiveOpacity == 0.92)

        // The retired key is never written back.
        let round = try JSONEncoder().encode(GlassLayerState(opacity: 0.4, frost: 1, material: .thin))
        #expect(!String(decoding: round, as: UTF8.self).contains("paintsTheme"))
    }

    @Test("Reduce Transparency resolves to an opaque, frosted surface and keeps the material")
    func reduceTransparencyResolution() {
        let clear = GlassLayerState(opacity: 0, frost: 0, material: .thick)
        let resolved = GlassLayerResolution.resolve(clear, reduceTransparency: true)
        #expect(resolved == GlassLayerState(opacity: 1, frost: 1, material: .thick))
        #expect(GlassLayerResolution.resolve(clear, reduceTransparency: false) == clear)
    }

    @Test("A self-painting surface skips the theme layer unless Reduce Transparency is on")
    func paintsThemeOptOut() {
        // The opt-out is per surface, not per user setting: a canvas that paints its own theme
        // colour (the terminal) suppresses the layer's paint while keeping its frost.
        let themed = GlassLayerState(opacity: 0.6, frost: 0.4, material: .thin)
        let optedOut = GlassLayerResolution.resolve(themed, reduceTransparency: false, paintsTheme: false)
        #expect(optedOut.effectiveOpacity == 0)
        #expect(optedOut.frost == 0.4 && optedOut.material == .thin)
        // A surface that does not opt out gets the state unchanged.
        #expect(GlassLayerResolution.resolve(themed, reduceTransparency: false) == themed)
        // Reduce Transparency overrides the opt-out, because an opaque window is a promise.
        #expect(GlassLayerResolution.resolve(themed, reduceTransparency: true, paintsTheme: false).effectiveOpacity == 1)
    }

    @Test("Material raw values are the strings glas.sh persists")
    func materialRawValues() {
        #expect(GlassLayerMaterial.allCases.map(\.rawValue) == ["ultraThin", "thin", "regular", "thick"])
    }
}
