import Testing
@testable import GlassEditorCore

@Suite("Opacity-aware theming")
struct ThemeTests {

    // MARK: - Sweep fixtures

    static let themes: [EditorTheme] = [.glassDark, .glassLight]
    static let opacities: [Double] = [1.0, 0.8, 0.6, 0.45, 0.3, 0.2]
    static let ambients: [AmbientEstimate] = [.unknown, .dark, .bright]
    static let backings: [SurfaceBacking] = [
        .material(.ultraThin), .blur(strength: 0.5), .opaque,
    ]

    /// What the run is actually drawn against once a scrim of the given alpha
    /// is laid down. Recomputed here from the public primitives rather than
    /// borrowed from `ContrastAdapter`, so the invariant test is checking the
    /// engine rather than agreeing with it.
    static func backdrop(
        theme: EditorTheme, surface: SurfaceCondition, scrimAlpha: Double
    ) -> ResolvedColor {
        let base = BackdropEstimate.estimatedBackdrop(
            for: surface, themeBackground: theme.background
        )
        guard scrimAlpha > 0 else { return base }
        let scrim = ResolvedColor(
            red: theme.background.red,
            green: theme.background.green,
            blue: theme.background.blue,
            alpha: scrimAlpha
        )
        return scrim.composited(over: base)
    }

    // MARK: - The core invariant

    /// The reason this package exists. Across both built-in themes, every
    /// `TokenRole`, six window opacities, three ambients, and three backings —
    /// 1,350 surfaces, 2,700 resolutions — every single result either clears
    /// the floor outright or reports a scrim that clears it. There is no
    /// combination anywhere in the sweep where the engine renders below the
    /// floor and says nothing (projectRules.md, Theming).
    @Test("No resolution anywhere in the surface sweep lands below its floor")
    func floorIsNeverSilentlyMissed() {
        var cases = 0

        for theme in Self.themes {
            for role in TokenRole.allCases {
                for opacity in Self.opacities {
                    for ambient in Self.ambients {
                        for backing in Self.backings {
                            let surface = SurfaceCondition(
                                windowOpacity: opacity, backing: backing, ambient: ambient
                            )
                            let floor = theme.minimumContrastRatio(on: surface)
                            let result = theme.color(for: role, on: surface, floor: floor)
                            let label: Comment = """
                                \(theme.name) / \(role.rawValue) / opacity \(opacity) \
                                / \(ambient.rawValue) / \(backing)
                                """

                            // Independently recompute the ratio the run will
                            // actually have, scrim included.
                            let drawnAgainst = Self.backdrop(
                                theme: theme, surface: surface, scrimAlpha: result.scrimAlpha
                            )
                            let measured = ResolvedColor.contrastRatio(
                                result.color, drawnAgainst
                            )

                            #expect(
                                measured >= floor - 0.01,
                                "below floor \(floor), measured \(measured) — \(label)"
                            )
                            // And the reported number is the real one.
                            #expect(
                                abs(measured - result.achievedRatio) < 0.01,
                                "reported \(result.achievedRatio) vs measured \(measured) — \(label)"
                            )
                            #expect(result.scrimAlpha >= 0 && result.scrimAlpha <= 1, label)

                            cases += 1
                        }
                    }
                }
            }
        }

        #expect(cases == 2 * TokenRole.allCases.count * 6 * 3 * 3)
        #expect(cases == 2700)
    }

    /// The sweep would be vacuous if the scrim path never fired. It does: a
    /// thin material over unknown passthrough is exactly the mid-gray trap.
    @Test("The sweep actually exercises both the walk and the scrim")
    func sweepExercisesBothPaths() {
        var unchanged = 0
        var walked = 0
        var scrimmed = 0

        for theme in Self.themes {
            for role in TokenRole.allCases {
                for opacity in Self.opacities {
                    for ambient in Self.ambients {
                        for backing in Self.backings {
                            let surface = SurfaceCondition(
                                windowOpacity: opacity, backing: backing, ambient: ambient
                            )
                            let result = theme.color(for: role, on: surface)
                            if result.scrimAlpha > 0 {
                                scrimmed += 1
                            } else if result.color == theme.rawColor(for: role) {
                                unchanged += 1
                            } else {
                                walked += 1
                            }
                        }
                    }
                }
            }
        }

        #expect(unchanged > 0)
        #expect(walked > 0)
        #expect(scrimmed > 0)
    }

    // MARK: - Monotonicity

    /// Thinner surface, never a weaker response.
    ///
    /// Tested under `.unknown` ambient, where the model is monotone by
    /// construction: the backdrop slides from the theme background toward
    /// mid-gray as opacity drops, so conditions only get worse. Under a *known*
    /// ambient the relationship is legitimately non-monotone — a dark theme
    /// over `.bright` passthrough passes through the trough on its way to a
    /// near-white backdrop, where flipping the text to black is easy again and
    /// the scrim correctly relaxes. Asserting monotonicity there would be
    /// asserting a bug.
    @Test("Scrim and glyph weight never weaken as opacity drops")
    func responseIsMonotoneAsOpacityDrops() {
        for theme in Self.themes {
            for role in TokenRole.allCases {
                for backing in Self.backings {
                    var previousScrim = -1.0
                    var previousWeight = -1

                    for opacity in Self.opacities {  // descending
                        let surface = SurfaceCondition(
                            windowOpacity: opacity, backing: backing, ambient: .unknown
                        )
                        let result = theme.color(for: role, on: surface)
                        let weight = ContrastAdapter.fontWeightDelta(for: surface)
                        let label: Comment = "\(theme.name) / \(role.rawValue) / \(backing)"

                        #expect(
                            result.scrimAlpha >= previousScrim - 1e-9,
                            "scrim fell from \(previousScrim) to \(result.scrimAlpha) at opacity \(opacity) — \(label)"
                        )
                        #expect(weight >= previousWeight, label)

                        previousScrim = result.scrimAlpha
                        previousWeight = weight
                    }
                }
            }
        }
    }

    // MARK: - Glyph weight

    @Test("fontWeightDelta thresholds are exact at the boundaries")
    func fontWeightDeltaThresholds() {
        func delta(_ opacity: Double) -> Int {
            ContrastAdapter.fontWeightDelta(
                for: SurfaceCondition(windowOpacity: opacity, backing: .opaque)
            )
        }

        #expect(delta(1.0) == 0)
        #expect(delta(0.81) == 0)
        #expect(delta(0.80) == 0)   // boundary is inclusive at the top
        #expect(delta(0.79) == 1)
        #expect(delta(0.60) == 1)
        #expect(delta(0.45) == 1)   // 0.45 is "below 0.8", not "below 0.45"
        #expect(delta(0.4499) == 2)
        #expect(delta(0.20) == 2)
        #expect(delta(0.0) == 2)
    }

    // MARK: - Theme completeness

    @Test("Both built-in themes define every TokenRole")
    func builtInThemesAreComplete() {
        for theme in Self.themes {
            #expect(EditorTheme.missingRequiredRoles(in: theme.palette).isEmpty)
            for role in TokenRole.allCases {
                #expect(theme.palette[role] != nil, "\(theme.name) missing \(role.rawValue)")
            }
            #expect(theme.palette.count == TokenRole.allCases.count)
        }

        // The SQL ten are explicitly distinct in the dark theme, not all
        // collapsed onto plain — the fidelity half of D-008 as a palette
        // property, not just a type property.
        let sqlTen = EditorTheme.requiredRoles.map { EditorTheme.glassDark.rawColor(for: $0) }
        #expect(Set(sqlTen).count >= 9)
    }

    @Test("A palette missing a required role is rejected, not quietly filled")
    func initRejectsIncompletePalette() {
        var palette: [TokenRole: ResolvedColor] = [:]
        for role in EditorTheme.requiredRoles {
            palette[role] = .white
        }
        #expect(EditorTheme(name: "ok", background: .black, palette: palette) != nil)

        palette[.keyword] = nil
        #expect(EditorTheme.missingRequiredRoles(in: palette) == [.keyword])
        #expect(EditorTheme(name: "no keyword", background: .black, palette: palette) == nil)

        // A palette missing only richer-grammar roles is accepted and filled
        // from .plain — the documented two-tier policy.
        var minimal: [TokenRole: ResolvedColor] = [:]
        for role in EditorTheme.requiredRoles {
            minimal[role] = ResolvedColor(red: 0.9, green: 0.9, blue: 0.9)
        }
        let filled = EditorTheme(name: "minimal", background: .black, palette: minimal)
        #expect(filled != nil)
        #expect(filled?.rawColor(for: .markupHeading) == filled?.rawColor(for: .plain))
        #expect(filled?.palette.count == TokenRole.allCases.count)
    }

    // MARK: - Backdrop model

    @Test("Unknown ambient resolves to mid-gray, and mid-gray caps contrast")
    func worstCaseBackdropIsMidGray() {
        let unknown = SurfaceCondition(
            windowOpacity: 0.5, backing: .material(.ultraThin), ambient: .unknown
        )
        #expect(BackdropEstimate.worstCaseBackdrop(for: unknown) == BackdropEstimate.midGray)
        #expect(BackdropEstimate.midGray == ResolvedColor(red: 0.5, green: 0.5, blue: 0.5))

        // The trap, stated as numbers: neither pole clears WCAG AA comfortably
        // against mid-gray, and pure white does not clear it at all.
        let whiteOnGray = ResolvedColor.contrastRatio(.white, BackdropEstimate.midGray)
        let blackOnGray = ResolvedColor.contrastRatio(.black, BackdropEstimate.midGray)
        #expect(whiteOnGray < 4.7)
        #expect(whiteOnGray < 4.5)          // below AA — hence the scrim
        #expect(blackOnGray > whiteOnGray)
        #expect(max(whiteOnGray, blackOnGray) < 5.5)  // below the raised floor

        // The true trough — where the better pole is worst — sits at relative
        // luminance 0.1791, sRGB ≈ 0.460, and caps at 4.58:1 either way.
        let trough = ResolvedColor(red: 0.4603, green: 0.4603, blue: 0.4603)
        let best = max(
            ResolvedColor.contrastRatio(.white, trough),
            ResolvedColor.contrastRatio(.black, trough)
        )
        #expect(abs(best - 4.58) < 0.05)
        #expect(best < max(whiteOnGray, blackOnGray))  // mid-gray is near, not at, the trough

        // Known ambients are not mid-gray, and they are ordered.
        let ordered: [AmbientEstimate] = [.dark, .dim, .normal, .bright]
        let luminances = ordered.map { BackdropEstimate.passthrough(for: $0).relativeLuminance }
        #expect(luminances == luminances.sorted())
        #expect(BackdropEstimate.passthrough(for: .dark).red == 0.05)
        #expect(BackdropEstimate.passthrough(for: .bright).red == 0.90)
    }

    @Test("Opaque backing means the backdrop is the theme background")
    func opaqueBackingIgnoresOpacityAndAmbient() {
        let theme = EditorTheme.glassDark
        for opacity in Self.opacities {
            for ambient in Self.ambients {
                let surface = SurfaceCondition(
                    windowOpacity: opacity, backing: .opaque, ambient: ambient
                )
                let backdrop = BackdropEstimate.estimatedBackdrop(
                    for: surface, themeBackground: theme.background
                )
                #expect(backdrop == theme.background)
            }
        }
    }

    @Test("Material weight and blur strength share one 0.55...0.90 scale")
    func materialFactorTable() {
        #expect(BackdropEstimate.materialFactor(for: .opaque) == 1.0)
        #expect(BackdropEstimate.materialFactor(for: .material(.ultraThin)) == 0.55)
        #expect(BackdropEstimate.materialFactor(for: .material(.thin)) == 0.67)
        #expect(BackdropEstimate.materialFactor(for: .material(.regular)) == 0.78)
        #expect(BackdropEstimate.materialFactor(for: .material(.thick)) == 0.90)
        #expect(BackdropEstimate.materialFactor(for: .blur(strength: 0.0)) == 0.55)
        #expect(abs(BackdropEstimate.materialFactor(for: .blur(strength: 0.5)) - 0.725) < 1e-12)
        #expect(BackdropEstimate.materialFactor(for: .blur(strength: 1.0)) == 0.90)

        // Thicker material lets less of the room through.
        let ordered = MaterialWeight.allCases.map {
            BackdropEstimate.materialFactor(for: .material($0))
        }
        #expect(ordered == ordered.sorted())
    }

    @Test("Backdrop slides from theme background toward passthrough as opacity drops")
    func backdropInterpolatesWithOpacity() {
        let theme = EditorTheme.glassDark
        var previous = -1.0
        for opacity in Self.opacities {  // descending
            let surface = SurfaceCondition(
                windowOpacity: opacity, backing: .material(.thick), ambient: .unknown
            )
            let luminance = BackdropEstimate.estimatedBackdrop(
                for: surface, themeBackground: theme.background
            ).relativeLuminance
            // Dark theme under mid-gray passthrough: the backdrop only lightens.
            #expect(luminance > previous)
            previous = luminance
        }
        #expect(previous < BackdropEstimate.midGray.relativeLuminance)
    }

    // MARK: - Adapter behavior

    @Test("A foreground already clearing the floor is returned untouched")
    func passingForegroundIsNotRepainted() {
        let theme = EditorTheme.glassDark
        let result = ContrastAdapter.adapted(
            foreground: theme.rawColor(for: .plain),
            surface: .opaque,
            themeBackground: theme.background,
            floor: 4.5
        )
        #expect(result.color == theme.rawColor(for: .plain))
        #expect(result.scrimAlpha == 0)
        #expect(result.achievedRatio > 4.5)
    }

    @Test("Adaptation moves the least it can, and keeps hue while it can")
    func adaptationIsMinimalAndHuePreserving() {
        let theme = EditorTheme.glassDark
        // A dim blue on a light-ish backdrop: must darken, but should not
        // arrive at flat black when a darker blue suffices.
        let blue = ResolvedColor(red: 0.45, green: 0.60, blue: 0.85)
        let surface = SurfaceCondition(
            windowOpacity: 0.6, backing: .material(.ultraThin), ambient: .bright
        )
        let result = ContrastAdapter.adapted(
            foreground: blue, surface: surface, themeBackground: theme.background, floor: 4.5
        )
        #expect(result.achievedRatio >= 4.5 - 0.01)
        #expect(result.color != blue)
        // Still recognizably blue: the blue channel stayed the largest.
        #expect(result.color.blue > result.color.red)
        #expect(result.color.blue > result.color.green)

        // And it stopped at the floor rather than overshooting to the pole.
        #expect(result.color != .black)
        #expect(result.achievedRatio < 6.0)
    }

    @Test("Raising the floor never lowers the response")
    func higherFloorNeverRelaxes() {
        let theme = EditorTheme.glassLight
        let surface = SurfaceCondition(
            windowOpacity: 0.3, backing: .material(.ultraThin), ambient: .unknown
        )
        var previousScrim = -1.0
        var previousRatio = 0.0
        for floor in [3.0, 4.5, 5.0, 5.5, 6.0, 7.0] {
            let result = theme.color(for: .comment, on: surface, floor: floor)
            #expect(result.scrimAlpha >= previousScrim - 1e-9, "floor \(floor)")
            #expect(result.achievedRatio >= previousRatio - 0.01, "floor \(floor)")
            #expect(result.achievedRatio >= floor - 0.01, "floor \(floor)")
            previousScrim = result.scrimAlpha
            previousRatio = result.achievedRatio
        }
    }

    @Test("The raised floor applies below 0.45 opacity and under bright ambient")
    func floorHeadroomRules() {
        let theme = EditorTheme.glassDark

        func floor(_ opacity: Double, _ ambient: AmbientEstimate) -> Double {
            theme.minimumContrastRatio(
                on: SurfaceCondition(windowOpacity: opacity, backing: .opaque, ambient: ambient)
            )
        }

        #expect(GlassEditorConfiguration().minimumContrastRatio == 4.5)   // WCAG AA, the default base
        #expect(floor(1.0, .unknown) == 4.5)
        #expect(floor(0.45, .unknown) == 4.5)      // boundary is not "below"
        #expect(floor(0.4499, .unknown) == 5.5)
        #expect(floor(0.2, .dark) == 5.5)
        #expect(floor(1.0, .bright) == 5.5)        // ambient alone raises it
        #expect(floor(1.0, .dim) == 4.5)

        // A consumer's own raised floor survives, rather than being replaced.
        let thin = SurfaceCondition(windowOpacity: 0.2, backing: .opaque)
        #expect(EditorTheme.minimumContrastRatio(on: thin, base: 7.0) == 7.0)
        #expect(EditorTheme.minimumContrastRatio(on: .opaque, base: 7.0) == 7.0)
    }

    @Test("A translucent foreground is measured as it will actually be drawn")
    func translucentForegroundIsComposited() {
        let theme = EditorTheme.glassDark
        let ghost = ResolvedColor(red: 1, green: 1, blue: 1, alpha: 0.25)
        let result = ContrastAdapter.adapted(
            foreground: ghost, surface: .opaque, themeBackground: theme.background, floor: 4.5
        )
        #expect(result.color.alpha == 1.0)
        #expect(result.achievedRatio >= 4.5 - 0.01)
    }
}
