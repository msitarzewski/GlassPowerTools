import Foundation

/// What the text is being drawn on top of, right now.
///
/// Designed against both consumers' real appearance models (INTEGRATION.md
/// A7/B4): glas.sh is window opacity + a material style
/// (`Constants.swift:21,48`); glassdb is opacity + blur via
/// `DatabaseGlassAppearance` (`Constants.swift:222–247`). Both map onto
/// `windowOpacity` + `backing` without invention.
public struct SurfaceCondition: Sendable, Hashable {
    /// Effective window opacity in 0...1, after per-session overrides
    /// (glas.sh resolves `sessionOverride.windowOpacity ?? settings.windowOpacity`).
    public var windowOpacity: Double

    /// What sits behind the text run.
    public var backing: SurfaceBacking

    /// Estimated ambient brightness. `.unknown` is the honest default and
    /// adaptation under it is conservative — never faked (projectRules.md).
    public var ambient: AmbientEstimate

    public init(
        windowOpacity: Double,
        backing: SurfaceBacking,
        ambient: AmbientEstimate = .unknown
    ) {
        self.windowOpacity = min(max(windowOpacity, 0), 1)
        self.backing = backing
        self.ambient = ambient
    }

    /// A fully opaque, material-free surface — the desktop-editor baseline.
    public static let opaque = SurfaceCondition(
        windowOpacity: 1.0, backing: .opaque, ambient: .unknown
    )
}

/// The background treatment behind the editor's text run.
public enum SurfaceBacking: Sendable, Hashable {
    /// Solid background; contrast math can trust the backdrop color.
    case opaque

    /// A system material of the given weight (glas.sh `glassMaterialStyle`).
    case material(MaterialWeight)

    /// A blur over arbitrary content, `strength` in 0...1
    /// (glassdb `DatabaseGlassAppearance.blur`).
    case blur(strength: Double)
}

/// System material weights, ordered thinnest to thickest.
public enum MaterialWeight: String, Sendable, Hashable, Codable, CaseIterable {
    case ultraThin
    case thin
    case regular
    case thick
}

/// Estimated ambient brightness of the physical environment.
/// `.unknown` is first-class: no visionOS ambient signal has been identified
/// yet (activeContext.md), and adaptation must degrade conservatively.
public enum AmbientEstimate: String, Sendable, Hashable, Codable, CaseIterable {
    case unknown
    case dark
    case dim
    case normal
    case bright
}
