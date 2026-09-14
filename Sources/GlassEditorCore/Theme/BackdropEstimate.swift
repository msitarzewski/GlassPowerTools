import Foundation

/// Estimates the color a text run is actually drawn against.
///
/// Contrast adaptation is only as good as its idea of the backdrop. On an
/// opaque editor the backdrop is simply the theme background, which is why
/// stock engines never model this (D-001, "the transparency constraint is
/// decisive"). On glass it is the theme background alpha-composited over
/// *passthrough content the package cannot see* — another window, a desk, a
/// room. This type is the honest model of that unknown: it never invents a
/// passthrough color, it derives one from `AmbientEstimate`, and when ambient
/// is `.unknown` it picks the value that is worst for contrast rather than the
/// value that flatters the theme (projectRules.md, Theming).
public enum BackdropEstimate: Sendable {

    // MARK: - Passthrough

    /// The contrast-hostile neutral.
    ///
    /// Derivation. For a foreground at pure white the WCAG ratio against a
    /// backdrop of relative luminance `L` is `1.05 / (L + 0.05)`; at pure black
    /// it is `(L + 0.05) / 0.05`. The backdrop that *minimizes the better of
    /// the two* sits where they are equal:
    ///
    ///     1.05 / (L + 0.05) == (L + 0.05) / 0.05
    ///     (L + 0.05)^2 == 0.0525
    ///     L == 0.1791   →  sRGB ≈ 0.460  →  ratio 4.58:1 either way
    ///
    /// So there exists a backdrop against which **no** foreground whatsoever —
    /// not even pure black or pure white — can clear 4.59:1. Canonical mid-gray
    /// (0.5, 0.5, 0.5) sits a hair to the light side of that trough: relative
    /// luminance 0.2140, capping white text at 3.98:1 and black text at 5.28:1.
    /// Both numbers matter. The first is below WCAG AA on its own, and it is
    /// precisely why `ContrastAdapter` needs a scrim of last resort: a light
    /// theme's own foreground poles cannot be legislated into legibility over
    /// unknown passthrough, only backed by opacity behind the glyphs.
    ///
    /// Mid-gray is used rather than the exact 0.460 trough because it is the
    /// honest "we know nothing" neutral, it is within 0.7:1 of the true worst
    /// case, and it is a value a reviewer can verify by inspection.
    public static let midGray = ResolvedColor(red: 0.5, green: 0.5, blue: 0.5)

    /// The passthrough color assumed behind translucent backing, per ambient.
    ///
    /// | Ambient    | sRGB gray | Rationale                                   |
    /// |------------|-----------|---------------------------------------------|
    /// | `.unknown` | 0.50      | worst case for contrast — see `midGray`      |
    /// | `.dark`    | 0.05      | near-black room, passthrough contributes little |
    /// | `.dim`     | 0.20      | evening interior                             |
    /// | `.normal`  | 0.45      | typical lit interior                         |
    /// | `.bright`  | 0.90      | daylight / near-white passthrough            |
    ///
    /// `.unknown` is deliberately the *pessimistic* entry, not an average of
    /// the others. `SurfaceCondition` is never faked, so when the platform
    /// gives no ambient signal the adapter must assume the environment that
    /// makes text hardest to read (AGENTS.md §5).
    public static func passthrough(for ambient: AmbientEstimate) -> ResolvedColor {
        switch ambient {
        case .unknown: return midGray
        case .dark: return ResolvedColor(red: 0.05, green: 0.05, blue: 0.05)
        case .dim: return ResolvedColor(red: 0.20, green: 0.20, blue: 0.20)
        case .normal: return ResolvedColor(red: 0.45, green: 0.45, blue: 0.45)
        case .bright: return ResolvedColor(red: 0.90, green: 0.90, blue: 0.90)
        }
    }

    // MARK: - Material weighting

    /// How much of the theme background survives the backing treatment, in
    /// 0...1, before window opacity is applied.
    ///
    /// | Backing                | Factor | Reading                              |
    /// |------------------------|--------|--------------------------------------|
    /// | `.opaque`              | 1.00   | backdrop *is* the theme background   |
    /// | `.material(.ultraThin)`| 0.55   | passthrough dominates                |
    /// | `.material(.thin)`     | 0.67   |                                      |
    /// | `.material(.regular)`  | 0.78   |                                      |
    /// | `.material(.thick)`    | 0.90   | theme background dominates           |
    /// | `.blur(strength: s)`   | 0.55 + 0.35·s | same range, linear in strength |
    ///
    /// The four material weights are evenly spaced across the same 0.55...0.90
    /// range that blur strength maps into, so glas.sh's material styles
    /// (`Constants.swift:21,48`) and glassdb's blur slider
    /// (`Constants.swift:222–247`) land on one comparable scale — the whole
    /// point of collapsing both consumers onto `SurfaceCondition`.
    ///
    /// The 0.55 floor is not zero on purpose: even the thinnest system material
    /// is a frosted layer, not a window, so some theme background always
    /// survives. The 0.90 ceiling is not one for the mirror reason — a thick
    /// material still admits a little of the room.
    ///
    /// Open gate: these six numbers are a defensible model, not a measurement.
    /// Validating them against real `NSVisualEffectView` / `.ultraThinMaterial`
    /// output on a signed device is an M0/M5 exit criterion (progress.md), and
    /// until then they stay listed as open.
    public static func materialFactor(for backing: SurfaceBacking) -> Double {
        switch backing {
        case .opaque:
            return 1.0
        case .material(let weight):
            switch weight {
            case .ultraThin: return 0.55
            case .thin: return 0.67
            case .regular: return 0.78
            case .thick: return 0.90
            }
        case .blur(let strength):
            let s = min(max(strength, 0), 1)
            return 0.55 + 0.35 * s
        }
    }

    // MARK: - Estimates

    /// The worst-case backdrop for `surface`, giving the theme background no
    /// credit at all.
    ///
    /// This is the pure-passthrough bound: what the glyphs would sit on if the
    /// window contributed nothing. It is a reasoning and diagnostics tool —
    /// `ContrastAdapter` adapts against `estimatedBackdrop(for:themeBackground:)`,
    /// which does account for the window, because sizing a scrim against a
    /// bound the surface will never actually reach would darken every run in
    /// the editor for nothing.
    ///
    /// For `.opaque` backing there is no passthrough to bound, so this returns
    /// `midGray` — the contrast-hostile neutral. That is conservative by
    /// construction: no caller treating it as a bound can be made optimistic by
    /// it.
    public static func worstCaseBackdrop(for surface: SurfaceCondition) -> ResolvedColor {
        switch surface.backing {
        case .opaque:
            return midGray
        case .material, .blur:
            return passthrough(for: surface.ambient)
        }
    }

    /// The color the text run is estimated to be drawn against.
    ///
    /// - `.opaque` backing: the backdrop **is** `themeBackground`, at full
    ///   strength. Window opacity is irrelevant — an opaque backing means the
    ///   editor draws its own solid ground, whatever the window is doing.
    /// - `.material` / `.blur` backing: the theme background is composited over
    ///   the ambient passthrough at weight `windowOpacity × materialFactor`.
    ///   Both terms matter and multiply: a thick material in a 20%-opacity
    ///   window still shows mostly room.
    ///
    /// The result is always opaque — it is a backdrop, not a layer.
    public static func estimatedBackdrop(
        for surface: SurfaceCondition,
        themeBackground: ResolvedColor
    ) -> ResolvedColor {
        let opaqueTheme = ResolvedColor(
            red: themeBackground.red,
            green: themeBackground.green,
            blue: themeBackground.blue,
            alpha: 1.0
        )

        switch surface.backing {
        case .opaque:
            return opaqueTheme

        case .material, .blur:
            let weight = surface.windowOpacity * materialFactor(for: surface.backing)
            let veil = ResolvedColor(
                red: themeBackground.red,
                green: themeBackground.green,
                blue: themeBackground.blue,
                alpha: min(max(weight, 0), 1)
            )
            return veil.composited(over: passthrough(for: surface.ambient))
        }
    }
}
