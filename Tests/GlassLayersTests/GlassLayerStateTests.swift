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
        #expect(state.paintsTheme == false)
        #expect(state.effectiveOpacity == 0)
        #expect(!state.isFullyTransparent)
    }

    @Test("Init clamps to the unit interval and treats non-finite as zero")
    func initClamps() {
        let high = GlassLayerState(opacity: 4, frost: 1.5, material: .thick, paintsTheme: true)
        #expect(high.opacity == 1 && high.frost == 1)
        let low = GlassLayerState(opacity: -1, frost: -0.2, material: .thin, paintsTheme: true)
        #expect(low.opacity == 0 && low.frost == 0)
        let nan = GlassLayerState(opacity: .nan, frost: .infinity, material: .regular, paintsTheme: true)
        #expect(nan.opacity == 0 && nan.frost == 0)
    }

    @Test("Codable round trip preserves every field")
    func codableRoundTrip() throws {
        let original = GlassLayerState(opacity: 0.37, frost: 0.62, material: .regular, paintsTheme: true)
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
        #expect(decoded.paintsTheme == true, "absent paintsTheme derives from opacity > 0")

        let empty = try JSONDecoder().decode(GlassLayerState.self, from: "{}".data(using: .utf8)!)
        #expect(empty == .default)
    }

    @Test("Effective opacity is zero unless the theme is painted")
    func effectiveOpacity() {
        var state = GlassLayerState(opacity: 0.8, frost: 0, material: .thin, paintsTheme: false)
        #expect(state.effectiveOpacity == 0)
        #expect(state.isFullyTransparent)
        state.paintsTheme = true
        #expect(state.effectiveOpacity == 0.8)
        #expect(!state.isFullyTransparent)
    }

    @Test("Reduce Transparency resolves to an opaque, frosted surface and keeps the material")
    func reduceTransparencyResolution() {
        let clear = GlassLayerState(opacity: 0, frost: 0, material: .thick, paintsTheme: false)
        let resolved = GlassLayerResolution.resolve(clear, reduceTransparency: true)
        #expect(resolved == GlassLayerState(opacity: 1, frost: 1, material: .thick, paintsTheme: true))
        #expect(GlassLayerResolution.resolve(clear, reduceTransparency: false) == clear)
    }

    @Test("A self-painting surface skips the theme layer unless Reduce Transparency is on")
    func paintsThemeOptOut() {
        let themed = GlassLayerState(opacity: 0.6, frost: 0.4, material: .thin, paintsTheme: true)
        let optedOut = GlassLayerResolution.resolve(themed, reduceTransparency: false, paintsTheme: false)
        #expect(optedOut.effectiveOpacity == 0)
        #expect(optedOut.frost == 0.4 && optedOut.material == .thin)
        #expect(GlassLayerResolution.resolve(themed, reduceTransparency: false, paintsTheme: true) == themed)
        #expect(GlassLayerResolution.resolve(themed, reduceTransparency: true, paintsTheme: false).effectiveOpacity == 1)
    }

    @Test("Material raw values are the strings glas.sh persists")
    func materialRawValues() {
        #expect(GlassLayerMaterial.allCases.map(\.rawValue) == ["ultraThin", "thin", "regular", "thick"])
    }
}
