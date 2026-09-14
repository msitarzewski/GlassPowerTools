import Foundation

/// A palette of `TokenRole` colors plus the background they were designed
/// against, resolved through `ContrastAdapter` at render time.
///
/// The theme is authored for its own background; the *surface* is whatever the
/// user has actually done to the window. Those are different things, and
/// keeping them separate is what lets one parse render correctly at two
/// opacities in two windows (D-003). Nothing here draws — `GlassEditorCore`
/// cannot import a UI framework — so the theme's whole job is to answer
/// "what color, and does it clear the floor" honestly.
public struct EditorTheme: Sendable, Hashable {

    /// Human-facing name. Not an identifier; nothing keys off it.
    public let name: String

    /// The background this palette was designed against, and the color a
    /// scrim of last resort is drawn in.
    public let background: ResolvedColor

    /// Complete role → color map. Every `TokenRole` case is present after
    /// `init`; see the fallback policy there.
    public let palette: [TokenRole: ResolvedColor]

    // MARK: - Completeness

    /// The ten roles a theme must define explicitly.
    ///
    /// These are the lossless image of glassdb's `SQLTokenKind` (D-008,
    /// `TokenRole.swift:13–23`). SQL highlighting is a shipped, visible
    /// behavior in a consumer today; a theme that quietly rendered `.keyword`
    /// in the plain-text color would be a regression against working software,
    /// so it is rejected rather than filled in.
    public static let requiredRoles: Set<TokenRole> = [
        .keyword, .function, .string, .number, .comment,
        .identifier, .operator, .punctuation, .plain, .error,
    ]

    /// Which of `requiredRoles` a candidate palette fails to define.
    public static func missingRequiredRoles(
        in palette: [TokenRole: ResolvedColor]
    ) -> Set<TokenRole> {
        requiredRoles.subtracting(palette.keys)
    }

    /// Build a theme, validating palette completeness.
    ///
    /// Fallback policy, in two tiers:
    ///
    /// - **The SQL ten** (`requiredRoles`) and `.plain` must be present
    ///   explicitly. A palette missing any of them is not a theme with a gap,
    ///   it is a theme that would silently mis-render a consumer's existing
    ///   output — so this initializer returns `nil`.
    /// - **Richer-grammar roles** — the markup, type, and binding cases that
    ///   exist for grammars beyond SQL — may be omitted, and are filled from
    ///   `.plain`. A YAML anchor rendered in the plain-text color is a theme
    ///   that has not been extended yet, not a broken one, and forcing every
    ///   third-party theme to enumerate 25 cases to be loadable at all would
    ///   buy nothing.
    ///
    /// Returning `nil` rather than asserting is deliberate. Themes are data and
    /// may arrive from a consumer at runtime; `EditorError` is the package's
    /// single error type (projectRules.md, Naming) and is a contract file this
    /// module does not extend, so an optional is the honest signal that stays
    /// inside the existing contract. A trap here would turn a bad theme file
    /// into a crash in someone else's app.
    public init?(
        name: String,
        background: ResolvedColor,
        palette: [TokenRole: ResolvedColor]
    ) {
        guard EditorTheme.missingRequiredRoles(in: palette).isEmpty,
              let plain = palette[.plain]
        else { return nil }

        var completed = palette
        for role in TokenRole.allCases where completed[role] == nil {
            completed[role] = plain
        }

        self.name = name
        self.background = background
        self.palette = completed
    }

    // MARK: - Resolution

    /// The palette entry for `role`, before any adaptation. Total, because
    /// `init` completed the palette.
    public func rawColor(for role: TokenRole) -> ResolvedColor {
        palette[role] ?? palette[.plain] ?? .white
    }

    /// The color to draw `role` in on `surface`, adapted to clear `floor`.
    ///
    /// Palette lookup, then `ContrastAdapter`. The result reports what it
    /// actually achieved and whether a scrim is required behind the run.
    public func color(
        for role: TokenRole,
        on surface: SurfaceCondition,
        floor: Double
    ) -> ContrastResult {
        ContrastAdapter.adapted(
            foreground: rawColor(for: role),
            surface: surface,
            themeBackground: background,
            floor: floor
        )
    }

    /// The color to draw `role` in on `surface`, using this theme's own floor
    /// for that surface. The signature named in projectRules.md, Theming.
    public func color(for role: TokenRole, on surface: SurfaceCondition) -> ContrastResult {
        color(for: role, on: surface, floor: minimumContrastRatio(on: surface))
    }

    // MARK: - Floor

    /// The contrast floor this theme will not render below on `surface`.
    ///
    /// Base is WCAG 2.x AA for normal text, 4.5:1 — matching
    /// `GlassEditorConfiguration.minimumContrastRatio`'s default
    /// (`GlassEditorConfiguration.swift:39`).
    ///
    /// Raised to 5.5:1 when window opacity drops below 0.45 **or** ambient is
    /// `.bright`. WCAG's 4.5 was derived for ink on a stable, opaque page. Two
    /// things break that premise here, and both are present in this product:
    ///
    /// 1. **The backdrop moves.** Passthrough content scrolls, animates, and
    ///    changes brightness under the glyphs. A ratio computed against an
    ///    *estimate* of a moving backdrop needs headroom the static case does
    ///    not, or a run that measured 4.5 spends part of its life below it.
    /// 2. **Bright ambient washes the display.** Screen reflectance adds a
    ///    roughly constant luminance to both terms of the ratio, which
    ///    compresses it — most severely at the dark end, where the +0.05 term
    ///    stops dominating. Nominal 4.5 measures as less in daylight.
    ///
    /// 5.5 is a judgment call — roughly a fifth of headroom — not a figure from
    /// the specification, and it is applied at the same 0.45 knee as
    /// `ContrastAdapter.fontWeightDelta` so margin and glyph weight arrive
    /// together rather than a step apart. Like those thresholds it is an open
    /// M0/M5 device-validation gate.
    public func minimumContrastRatio(on surface: SurfaceCondition) -> Double {
        EditorTheme.minimumContrastRatio(on: surface, base: 4.5)
    }

    /// Floor for `surface` given a caller-supplied base — the injection point
    /// for `GlassEditorConfiguration.minimumContrastRatio`, so a consumer that
    /// has raised its own floor keeps the translucency headroom on top of it
    /// instead of having it silently replaced.
    public static func minimumContrastRatio(
        on surface: SurfaceCondition,
        base: Double
    ) -> Double {
        let needsHeadroom = surface.windowOpacity < 0.45 || surface.ambient == .bright
        return needsHeadroom ? max(base, 5.5) : base
    }
}

// MARK: - Built-in themes

extension EditorTheme {

    /// Warm-neutral dark theme. Off-white prose, desaturated accents.
    ///
    /// Restraint is functional here, not stylistic: a saturated palette on
    /// glass is a palette that `ContrastAdapter` will drag toward a pole the
    /// moment opacity drops, so the theme the user chose survives translucency
    /// better the closer its accents already sit to a legible luminance.
    ///
    /// The force-unwrap is backed by `ThemeTests.builtInThemesAreComplete`,
    /// which fails loudly if this literal ever loses a required role.
    public static let glassDark = EditorTheme(
        name: "Glass Dark",
        background: ResolvedColor(red: 0.078, green: 0.086, blue: 0.102),
        palette: [
            // The SQL ten.
            .plain: ResolvedColor(red: 0.929, green: 0.906, blue: 0.867),
            .keyword: ResolvedColor(red: 0.561, green: 0.714, blue: 0.910),
            .function: ResolvedColor(red: 0.498, green: 0.784, blue: 0.847),
            .string: ResolvedColor(red: 0.639, green: 0.808, blue: 0.549),
            .number: ResolvedColor(red: 0.898, green: 0.714, blue: 0.463),
            .comment: ResolvedColor(red: 0.498, green: 0.529, blue: 0.573),
            .identifier: ResolvedColor(red: 0.863, green: 0.839, blue: 0.796),
            .operator: ResolvedColor(red: 0.753, green: 0.784, blue: 0.831),
            .punctuation: ResolvedColor(red: 0.596, green: 0.627, blue: 0.675),
            .error: ResolvedColor(red: 0.949, green: 0.447, blue: 0.420),

            // Richer grammars.
            .type: ResolvedColor(red: 0.561, green: 0.847, blue: 0.769),
            .variable: ResolvedColor(red: 0.863, green: 0.839, blue: 0.796),
            .property: ResolvedColor(red: 0.776, green: 0.831, blue: 0.918),
            .parameter: ResolvedColor(red: 0.847, green: 0.788, blue: 0.659),
            .constant: ResolvedColor(red: 0.898, green: 0.714, blue: 0.463),
            .boolean: ResolvedColor(red: 0.898, green: 0.714, blue: 0.463),
            .label: ResolvedColor(red: 0.784, green: 0.690, blue: 0.878),
            .attribute: ResolvedColor(red: 0.725, green: 0.827, blue: 0.627),
            .embedded: ResolvedColor(red: 0.663, green: 0.706, blue: 0.776),
            .markupHeading: ResolvedColor(red: 0.941, green: 0.863, blue: 0.659),
            .markupEmphasis: ResolvedColor(red: 0.851, green: 0.804, blue: 0.745),
            .markupStrong: ResolvedColor(red: 0.937, green: 0.890, blue: 0.824),
            .markupLink: ResolvedColor(red: 0.561, green: 0.714, blue: 0.910),
            .markupCode: ResolvedColor(red: 0.639, green: 0.808, blue: 0.549),
            .markupList: ResolvedColor(red: 0.596, green: 0.627, blue: 0.675),
        ]
    )!

    /// The same palette family inverted onto a warm paper background: the
    /// accents keep their hue and trade lightness for depth.
    public static let glassLight = EditorTheme(
        name: "Glass Light",
        background: ResolvedColor(red: 0.969, green: 0.965, blue: 0.953),
        palette: [
            // The SQL ten.
            .plain: ResolvedColor(red: 0.137, green: 0.149, blue: 0.169),
            .keyword: ResolvedColor(red: 0.106, green: 0.373, blue: 0.651),
            .function: ResolvedColor(red: 0.055, green: 0.431, blue: 0.494),
            .string: ResolvedColor(red: 0.173, green: 0.431, blue: 0.227),
            .number: ResolvedColor(red: 0.541, green: 0.325, blue: 0.063),
            .comment: ResolvedColor(red: 0.365, green: 0.400, blue: 0.451),
            .identifier: ResolvedColor(red: 0.200, green: 0.216, blue: 0.239),
            .operator: ResolvedColor(red: 0.255, green: 0.282, blue: 0.333),
            .punctuation: ResolvedColor(red: 0.353, green: 0.380, blue: 0.427),
            .error: ResolvedColor(red: 0.702, green: 0.149, blue: 0.118),

            // Richer grammars.
            .type: ResolvedColor(red: 0.059, green: 0.420, blue: 0.353),
            .variable: ResolvedColor(red: 0.200, green: 0.216, blue: 0.239),
            .property: ResolvedColor(red: 0.165, green: 0.306, blue: 0.478),
            .parameter: ResolvedColor(red: 0.416, green: 0.325, blue: 0.125),
            .constant: ResolvedColor(red: 0.541, green: 0.325, blue: 0.063),
            .boolean: ResolvedColor(red: 0.541, green: 0.325, blue: 0.063),
            .label: ResolvedColor(red: 0.388, green: 0.224, blue: 0.561),
            .attribute: ResolvedColor(red: 0.247, green: 0.420, blue: 0.165),
            .embedded: ResolvedColor(red: 0.278, green: 0.314, blue: 0.369),
            .markupHeading: ResolvedColor(red: 0.227, green: 0.173, blue: 0.082),
            .markupEmphasis: ResolvedColor(red: 0.227, green: 0.247, blue: 0.278),
            .markupStrong: ResolvedColor(red: 0.106, green: 0.118, blue: 0.137),
            .markupLink: ResolvedColor(red: 0.106, green: 0.373, blue: 0.651),
            .markupCode: ResolvedColor(red: 0.173, green: 0.431, blue: 0.227),
            .markupList: ResolvedColor(red: 0.353, green: 0.380, blue: 0.427),
        ]
    )!
}
