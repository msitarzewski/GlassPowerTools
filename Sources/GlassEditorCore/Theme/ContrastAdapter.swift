import Foundation

/// The outcome of adapting one foreground color to one surface.
///
/// `achievedRatio` is reported unconditionally and without rounding in the
/// engine's favor. If adaptation could not reach the floor even at full scrim,
/// the number says so; the engine never silently renders below the configured
/// contrast floor (projectRules.md, Theming), and "silently" includes reporting
/// a ratio it did not achieve.
public struct ContrastResult: Sendable, Hashable {
    /// The color to draw the glyphs in. Always opaque.
    public var color: ResolvedColor

    /// The WCAG ratio this run will actually have **once `scrimAlpha` is
    /// applied**. When `scrimAlpha` is 0 that is just `color` against the
    /// estimated backdrop.
    public var achievedRatio: Double

    /// Opacity, 0...1, of a scrim in the theme background color drawn *behind
    /// the text run only* — never behind the window (projectRules.md,
    /// Theming). 0 means no scrim is needed.
    ///
    /// The UI layer consumes this; `ContrastAdapter` only computes it. Drawing
    /// it as a window-level wash would defeat the product: the user asked for a
    /// transparent window, and the answer to unreadable text is a few hundred
    /// square points of local backing, not the loss of the feature.
    public var scrimAlpha: Double

    public init(color: ResolvedColor, achievedRatio: Double, scrimAlpha: Double) {
        self.color = color
        self.achievedRatio = achievedRatio
        self.scrimAlpha = min(max(scrimAlpha, 0), 1)
    }
}

/// Stateless contrast adaptation against a live `SurfaceCondition`.
///
/// Follows the GlasSecretStore service convention — a `public enum` of static
/// functions, no instances, no stored state (projectRules.md, Naming).
public enum ContrastAdapter: Sendable {

    // MARK: - Entry point

    /// Adapt `foreground` so it clears `floor` against the backdrop implied by
    /// `surface`, reporting honestly if it could not.
    ///
    /// Algorithm, in three stages:
    ///
    /// **1. Measure.** Estimate the backdrop
    /// (`BackdropEstimate.estimatedBackdrop`). If `foreground` already clears
    /// `floor` against it, return it untouched with `scrimAlpha` 0. Most runs
    /// in an opaque or near-opaque editor exit here, which is the point — a
    /// well-designed theme should not be repainted by the engine.
    ///
    /// **2. Walk toward a pole, preserving hue as long as possible.** Pick
    /// whichever pole — black or white — has more contrast against the backdrop,
    /// then solve for the *target relative luminance* that exactly meets the
    /// floor. Toward white that is `floor · (Lb + 0.05) − 0.05`; toward black it
    /// is `(Lb + 0.05) / floor − 0.05`. Then find the smallest `t` in 0...1 such
    /// that `lerp(foreground, pole, t)` reaches that luminance, by bisection.
    ///
    /// Bisecting on *luminance* rather than on the contrast ratio is deliberate.
    /// Luminance is monotone in `t` — every channel moves monotonically toward
    /// the pole's 0 or 1, and relative luminance is a positive-weighted sum of
    /// monotone channel transforms — so bisection is sound. The contrast ratio
    /// is *not* monotone in `t`: a foreground darker than the backdrop that is
    /// walked toward white first loses contrast, crosses the backdrop, and only
    /// then gains. Bisecting that would converge on the wrong root.
    ///
    /// Interpolating in sRGB component space keeps the hue recognizable for as
    /// long as the floor allows: a blue keyword desaturates toward the pole and
    /// only arrives at flat white or flat black when nothing less will do. The
    /// smallest sufficient `t` is chosen, never a comfortable margin, because
    /// every step toward the pole is a step away from the theme the user picked.
    ///
    /// **3. Scrim of last resort.** Against a mid backdrop, *no* foreground can
    /// clear a floor above ~4.59:1 — see `BackdropEstimate.midGray` for the
    /// derivation. When even the pole falls short, opacity has to come from
    /// behind the glyphs instead. Choose the pole that works against the theme
    /// background (the fully-scrimmed limit), bisect for the **minimal**
    /// `scrimAlpha` at which the scrimmed backdrop admits the floor, then redo
    /// stage 2 against that scrimmed backdrop so the returned color is still
    /// the least-moved one that works.
    ///
    /// The pole is re-chosen in stage 3 rather than carried over from stage 2,
    /// and this is load-bearing. Near the trough the two poles are within a
    /// hair of each other, so stage 2 can legitimately pick black while the
    /// theme background is dark — and scrimming toward a dark background with
    /// black text drives contrast *down*, converging on nothing. Selecting the
    /// pole against the scrim's own destination makes the search monotone and
    /// makes `scrimAlpha = 1` a guaranteed upper bound for any theme whose
    /// background is not itself in the trough.
    ///
    /// A `foreground` with alpha below 1 is composited over the backdrop before
    /// measurement — that is what the glyphs will look like — and the returned
    /// color is opaque.
    public static func adapted(
        foreground: ResolvedColor,
        surface: SurfaceCondition,
        themeBackground: ResolvedColor,
        floor: Double
    ) -> ContrastResult {
        let backdrop = BackdropEstimate.estimatedBackdrop(
            for: surface, themeBackground: themeBackground
        )
        let drawn = foreground.alpha < 1.0
            ? foreground.composited(over: backdrop)
            : foreground

        // Stage 1 — already legible.
        let asIs = ResolvedColor.contrastRatio(drawn, backdrop)
        if asIs >= floor {
            return ContrastResult(color: drawn, achievedRatio: asIs, scrimAlpha: 0)
        }

        // Stage 2 — walk toward the better pole.
        let pole = betterPole(against: backdrop)
        let walked = walk(drawn, toward: pole, backdrop: backdrop, floor: floor)
        let walkedRatio = ResolvedColor.contrastRatio(walked, backdrop)
        // The bisection lands on the floor exactly; `solveEpsilon` keeps a
        // last-bit rounding artifact from being mistaken for a real shortfall
        // and triggering a scrim nobody can see.
        if walkedRatio >= floor - solveEpsilon {
            return ContrastResult(color: walked, achievedRatio: walkedRatio, scrimAlpha: 0)
        }

        // Stage 3 — scrim of last resort.
        let opaqueTheme = opaque(themeBackground)
        let scrimPole = betterPole(against: opaqueTheme)
        let alpha = minimalScrimAlpha(
            pole: scrimPole,
            backdrop: backdrop,
            themeBackground: themeBackground,
            floor: floor
        )
        let scrimmed = scrimmedBackdrop(
            backdrop: backdrop, themeBackground: themeBackground, alpha: alpha
        )
        let finalColor = walk(drawn, toward: scrimPole, backdrop: scrimmed, floor: floor)
        return ContrastResult(
            color: finalColor,
            achievedRatio: ResolvedColor.contrastRatio(finalColor, scrimmed),
            scrimAlpha: alpha
        )
    }

    // MARK: - Glyph weight

    /// How many weight steps to add to the configured font weight as the
    /// surface thins.
    ///
    /// Stem darkening, in effect. A glyph outline of fixed width loses apparent
    /// mass when what shows through the gaps is live passthrough rather than a
    /// solid ground: antialiasing coverage that read as "slightly lighter ink"
    /// on an opaque background reads as "the room" on glass, and thin strokes
    /// go visually dotted before they go illegible. Contrast adaptation cannot
    /// fix this — the color is already at the floor — so the compensation has
    /// to be in the outline.
    ///
    /// | Window opacity | Delta | Rationale                                  |
    /// |----------------|-------|--------------------------------------------|
    /// | `>= 0.80`      | 0     | effectively a solid ground                  |
    /// | `0.45 ..< 0.80`| +1    | one step, e.g. regular → medium             |
    /// | `< 0.45`       | +2    | e.g. regular → semibold                     |
    ///
    /// Open gate: 0.80 and 0.45 are chosen to line up with the contrast floor's
    /// own 0.45 knee, so a run never gains margin and weight at different
    /// moments. They have not been validated on a signed physical device, and
    /// per AGENTS.md §5 they stay listed as an open M0/M5 exit criterion until
    /// they have been. Device validation may move both numbers; it should not
    /// change their ordering or the step size.
    public static func fontWeightDelta(for surface: SurfaceCondition) -> Int {
        if surface.windowOpacity >= 0.80 { return 0 }
        if surface.windowOpacity >= 0.45 { return 1 }
        return 2
    }

    // MARK: - Solving

    /// Bisection depth. 60 halvings of 0...1 exhausts `Double` precision, and
    /// the whole search is a few dozen floating-point operations against no
    /// allocation — the cost is irrelevant beside the per-run layout it feeds.
    private static let bisectionSteps = 60

    /// Slack for "did the solver land on the floor". Far below any ratio a
    /// human or a test cares about; it exists only to absorb `Double` rounding.
    private static let solveEpsilon = 1e-9

    private static func opaque(_ color: ResolvedColor) -> ResolvedColor {
        ResolvedColor(red: color.red, green: color.green, blue: color.blue, alpha: 1.0)
    }

    /// Whichever of black or white has more contrast against `backdrop`.
    /// Ties (an exactly-trough backdrop) resolve to white.
    private static func betterPole(against backdrop: ResolvedColor) -> ResolvedColor {
        let towardWhite = ResolvedColor.contrastRatio(.white, backdrop)
        let towardBlack = ResolvedColor.contrastRatio(.black, backdrop)
        return towardWhite >= towardBlack ? .white : .black
    }

    private static func lerp(
        _ from: ResolvedColor, toward pole: ResolvedColor, _ t: Double
    ) -> ResolvedColor {
        ResolvedColor(
            red: from.red + (pole.red - from.red) * t,
            green: from.green + (pole.green - from.green) * t,
            blue: from.blue + (pole.blue - from.blue) * t,
            alpha: 1.0
        )
    }

    /// The least-moved point on the segment `foreground → pole` that clears
    /// `floor` against `backdrop`, or the pole itself if nothing on the segment
    /// does.
    private static func walk(
        _ foreground: ResolvedColor,
        toward pole: ResolvedColor,
        backdrop: ResolvedColor,
        floor: Double
    ) -> ResolvedColor {
        let backdropLuminance = backdrop.relativeLuminance
        let towardWhite = pole.relativeLuminance >= backdropLuminance

        // Luminance that exactly meets the floor, from the WCAG ratio solved
        // for the foreground term.
        let target: Double = towardWhite
            ? floor * (backdropLuminance + 0.05) - 0.05
            : (backdropLuminance + 0.05) / floor - 0.05

        // Unreachable even at the pole — hand back the pole and let the caller
        // decide (stage 3, or an honest sub-floor report).
        let poleLuminance = pole.relativeLuminance
        if towardWhite ? (target > poleLuminance) : (target < poleLuminance) {
            return pole
        }

        // Relative luminance is monotone in `t`, so bisect on it directly.
        var low = 0.0
        var high = 1.0
        for _ in 0..<bisectionSteps {
            let mid = (low + high) / 2
            let luminance = lerp(foreground, toward: pole, mid).relativeLuminance
            let met = towardWhite ? (luminance >= target) : (luminance <= target)
            if met { high = mid } else { low = mid }
        }
        return lerp(foreground, toward: pole, high)
    }

    /// The theme background laid over the estimated backdrop at `alpha`.
    private static func scrimmedBackdrop(
        backdrop: ResolvedColor,
        themeBackground: ResolvedColor,
        alpha: Double
    ) -> ResolvedColor {
        let scrim = ResolvedColor(
            red: themeBackground.red,
            green: themeBackground.green,
            blue: themeBackground.blue,
            alpha: min(max(alpha, 0), 1)
        )
        return scrim.composited(over: backdrop)
    }

    /// Smallest scrim opacity at which `pole` clears `floor`.
    ///
    /// The scrimmed backdrop's luminance moves monotonically from the estimated
    /// backdrop's toward the theme background's as alpha rises, and contrast
    /// against a fixed pole is monotone in that luminance, so bisection finds
    /// the minimum. Returns 1 when full scrim still falls short — the honest
    /// answer, which the caller then reports as a sub-floor `achievedRatio`
    /// rather than hiding.
    private static func minimalScrimAlpha(
        pole: ResolvedColor,
        backdrop: ResolvedColor,
        themeBackground: ResolvedColor,
        floor: Double
    ) -> Double {
        func meetsFloor(_ alpha: Double) -> Bool {
            let scrimmed = scrimmedBackdrop(
                backdrop: backdrop, themeBackground: themeBackground, alpha: alpha
            )
            return ResolvedColor.contrastRatio(pole, scrimmed) >= floor
        }

        guard meetsFloor(1.0) else { return 1.0 }
        if meetsFloor(0.0) { return 0.0 }

        var low = 0.0   // known to fail
        var high = 1.0  // known to meet
        for _ in 0..<bisectionSteps {
            let mid = (low + high) / 2
            if meetsFloor(mid) { high = mid } else { low = mid }
        }
        return high
    }
}
