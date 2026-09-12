import SwiftUI

/// The frost material a Glass surface composites behind its content.
///
/// The four cases are the values glas.sh already persists under `glassFrost`
/// (`../glas.sh/glas.sh/SettingsView.swift:736-741`), so a migrated setting maps by raw value.
public enum GlassLayerMaterial: String, Codable, CaseIterable, Sendable, Identifiable {
    case ultraThin, thin, regular, thick

    public var id: String { rawValue }

    /// Display name used by the family's Frost picker.
    public var title: String {
        switch self {
        case .ultraThin: "Light"
        case .thin: "Medium"
        case .regular: "Heavy"
        case .thick: "Max"
        }
    }

    public var material: Material {
        switch self {
        case .ultraThin: .ultraThinMaterial
        case .thin: .thinMaterial
        case .regular: .regularMaterial
        case .thick: .thickMaterial
        }
    }
}

/// The one layering state every Glass surface draws from: windows, title bars, panels,
/// detail views and, later, session canvases.
///
/// Two independent dimensions, as glas.sh defines them (`TerminalGlassAppearance`,
/// `../glas.sh/glas.sh/SettingsManager.swift:1619-1643`): `opacity` paints the theme colour
/// behind content, `frost` composites the system material. Keeping them separate preserves all
/// four corner combinations, including a fully clear surface.
public struct GlassLayerState: Codable, Equatable, Sendable {
    /// Coverage of the theme colour behind content, 0...1. **Zero means the theme is not painted**
    /// — there is no separate switch, because this is a glass product and painting the glass is the
    /// point. A user who wants no theme colour sets this to zero.
    public var opacity: Double
    /// Strength of the composited material, 0...1. Zero leaves the surface clear.
    public var frost: Double
    /// Which material `frost` composites.
    public var material: GlassLayerMaterial
    public init(opacity: Double, frost: Double, material: GlassLayerMaterial) {
        self.opacity = Self.unit(opacity)
        self.frost = Self.unit(frost)
        self.material = material
    }

    /// Decision D2: transparent-first, frost on. glas.sh's look, adopted for the family.
    public static let `default` = GlassLayerState(opacity: 0, frost: 1, material: .ultraThin)

    /// The theme coverage actually painted.
    public var effectiveOpacity: Double { opacity }
    public var isFullyTransparent: Bool { effectiveOpacity == 0 && frost == 0 }

    /// Explicit, because `paintsTheme` is no longer a stored property but still has to be *read*
    /// from settings written before it was retired. It is never written again — hence the explicit
    /// `encode`, which omits it.
    enum CodingKeys: String, CodingKey {
        case opacity, frost, material, paintsTheme
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(frost, forKey: .frost)
        try container.encode(material, forKey: .material)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? Self.default.opacity
        let frost = try container.decodeIfPresent(Double.self, forKey: .frost) ?? Self.default.frost
        let materialRaw = try container.decodeIfPresent(String.self, forKey: .material)
        let material = materialRaw.flatMap(GlassLayerMaterial.init(rawValue:)) ?? Self.default.material
        // Migration: `paintsTheme` used to gate the slider. A stored `false` meant "painted
        // nothing", whatever the slider read, so fold it into the opacity rather than silently
        // switching the theme paint on for anyone who had it off.
        let painted = try container.decodeIfPresent(Bool.self, forKey: .paintsTheme) ?? (opacity > 0)
        self.init(opacity: painted ? opacity : 0, frost: frost, material: material)
    }

    /// Clamp to the unit interval; non-finite input becomes zero, as `SettingsManager.unitValue` does.
    static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}
