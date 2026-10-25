import Testing
import Foundation
import CoreText
@testable import GlassEditorUI
import GlassEditorCore

@Suite("AttributedAssembly")
@MainActor
struct AttributedAssemblyTests {

    private let configuration = GlassEditorConfiguration()

    /// Thin glass in an unknown environment: `BackdropEstimate` assumes the
    /// contrast-hostile mid-gray passthrough, which caps white text at 3.98:1 and
    /// black at 5.28:1 — both under the 5.5:1 floor a sub-0.45-opacity surface
    /// raises. Neither pole can reach it, so `ContrastAdapter` must fall back to a
    /// scrim (`BackdropEstimate.swift:18–41`).
    ///
    /// The dark theme is the one that needs it here: pulling the light theme's
    /// near-white foreground toward black clears the floor against a mid backdrop
    /// without any scrim at all, which is the adapter working as designed rather
    /// than a gap in the test.
    private let scrimSurface = SurfaceCondition(
        windowOpacity: 0.15, backing: .material(.ultraThin), ambient: .unknown
    )
    private let scrimTheme = EditorTheme.glassDark

    // MARK: - Run → range mapping

    @Test("runs map to the right ranges, and gaps keep the plain attributes")
    func runsMapToRanges() {
        let text = "SELECT id FROM t"
        let runs = [
            HighlightRun(range: 0..<6, role: .keyword),
            HighlightRun(range: 7..<9, role: .identifier),
            HighlightRun(range: 10..<14, role: .keyword),
        ]
        let string = AttributedAssembly.attributedString(
            text: text, runs: runs, theme: .glassDark,
            surface: .opaque, configuration: configuration
        )

        #expect(string.string == text)

        let keyword = theme(.keyword)
        let identifier = theme(.identifier)
        let plain = theme(.plain)

        #expect(color(string, at: 0) == keyword)
        #expect(color(string, at: 5) == keyword)
        // The space at 6 is in no run and keeps the base attributes.
        #expect(color(string, at: 6) == plain)
        #expect(color(string, at: 7) == identifier)
        #expect(color(string, at: 10) == keyword)
        #expect(color(string, at: 14) == plain)
    }

    @Test("a later run wins where two runs overlap")
    func laterRunWins() {
        let string = AttributedAssembly.attributedString(
            text: "abcdef",
            runs: [
                HighlightRun(range: 0..<6, role: .comment),
                HighlightRun(range: 2..<4, role: .string),
            ],
            theme: .glassDark, surface: .opaque, configuration: configuration
        )
        #expect(color(string, at: 0) == theme(.comment))
        #expect(color(string, at: 2) == theme(.string))
        #expect(color(string, at: 4) == theme(.comment))
    }

    // MARK: - Scrim

    @Test("a run needing a scrim gets a background color; one that does not, does not")
    func scrimBecomesBackgroundAttribute() {
        let floor = AttributedAssembly.contrastFloor(
            configuration: configuration, surface: scrimSurface
        )
        let resolution = scrimTheme.color(for: .plain, on: scrimSurface, floor: floor)
        // Precondition for the test to mean anything.
        #expect(resolution.scrimAlpha > 0)

        let scrimmed = AttributedAssembly.attributes(
            for: .plain, theme: scrimTheme, surface: scrimSurface, configuration: configuration
        )
        let background = scrimmed[.backgroundColor] as? PlatformColor
        #expect(background != nil)
        #expect(abs((background?.alphaComponent ?? 0) - CGFloat(resolution.scrimAlpha)) < 0.001)

        // On an opaque surface a well-designed theme clears the floor untouched,
        // so there is no scrim to draw and no background attribute to set.
        let opaque = AttributedAssembly.attributes(
            for: .plain, theme: scrimTheme, surface: .opaque, configuration: configuration
        )
        #expect(opaque[.backgroundColor] == nil)
    }

    @Test("the scrim is the theme background, so it backs the run and not the window")
    func scrimUsesThemeBackground() {
        let attributes = AttributedAssembly.attributes(
            for: .plain, theme: scrimTheme, surface: scrimSurface, configuration: configuration
        )
        guard let background = attributes[.backgroundColor] as? PlatformColor else {
            Issue.record("expected a scrim background")
            return
        }
        let expected = PlatformColor(resolved: scrimTheme.background)
        #expect(abs(background.redComponent - expected.redComponent) < 0.001)
        #expect(abs(background.greenComponent - expected.greenComponent) < 0.001)
        #expect(abs(background.blueComponent - expected.blueComponent) < 0.001)
    }

    // MARK: - Weight compensation

    @Test("glyph weight steps up below the opacity thresholds")
    func weightDeltaAppliedBelowThresholds() {
        func weight(at opacity: Double) -> Double {
            let surface = SurfaceCondition(
                windowOpacity: opacity, backing: .material(.regular), ambient: .unknown
            )
            let font = AttributedAssembly.font(configuration: configuration, surface: surface)
            let traits = font.fontDescriptor.object(forKey: .traits) as? [NSObject: Any]
            return (traits?[kCTFontWeightTrait as NSObject] as? Double) ?? .nan
        }

        // The ladder itself, independent of what the platform reports.
        #expect(ContrastAdapter.fontWeightDelta(for: SurfaceCondition(
            windowOpacity: 0.9, backing: .material(.regular), ambient: .unknown)) == 0)
        #expect(ContrastAdapter.fontWeightDelta(for: SurfaceCondition(
            windowOpacity: 0.6, backing: .material(.regular), ambient: .unknown)) == 1)
        #expect(ContrastAdapter.fontWeightDelta(for: SurfaceCondition(
            windowOpacity: 0.2, backing: .material(.regular), ambient: .unknown)) == 2)

        // And the fonts actually built from it: heavier as the surface thins.
        #expect(weight(at: 0.6) > weight(at: 0.9))
        #expect(weight(at: 0.2) > weight(at: 0.6))
    }

    @Test("the weight ladder clamps instead of running off either end")
    func weightLadderClamps() {
        #expect(AttributedAssembly.weight(steppedBy: 2, from: .black) == .black)
        #expect(AttributedAssembly.weight(steppedBy: -9, from: .regular) == .ultraLight)
        #expect(AttributedAssembly.weight(steppedBy: 0, from: .regular) == .regular)
    }

    // MARK: - Clamping

    @Test("a run overhanging the text is truncated, not dropped")
    func runOverhangIsTruncated() {
        #expect(
            AttributedAssembly.clampedRange(2..<50, toUTF16Length: 10)
                == NSRange(location: 2, length: 8)
        )
    }

    @Test("a run entirely past the end is dropped")
    func runPastEndIsDropped() {
        #expect(AttributedAssembly.clampedRange(20..<30, toUTF16Length: 10) == nil)
        #expect(AttributedAssembly.clampedRange(10..<12, toUTF16Length: 10) == nil)
    }

    @Test("an empty or negative-start run is handled without trapping")
    func degenerateRunsAreSafe() {
        #expect(AttributedAssembly.clampedRange(5..<5, toUTF16Length: 10) == nil)
        #expect(AttributedAssembly.clampedRange(-5..<0, toUTF16Length: 10) == nil)
        #expect(AttributedAssembly.clampedRange(0..<10, toUTF16Length: 0) == nil)
        #expect(
            AttributedAssembly.clampedRange(-3..<4, toUTF16Length: 10)
                == NSRange(location: 0, length: 4)
        )
    }

    @Test("stale runs from a longer document do not crash the assembly")
    func staleRunsAgainstShrunkTextAreSafe() {
        // The real race: highlighting was computed for "SELECT * FROM users" and
        // arrives after the user deleted back to "SELECT".
        let string = AttributedAssembly.attributedString(
            text: "SELECT",
            runs: [
                HighlightRun(range: 0..<6, role: .keyword),
                HighlightRun(range: 7..<8, role: .operator),
                HighlightRun(range: 9..<13, role: .keyword),
                HighlightRun(range: 14..<19, role: .identifier),
            ],
            theme: .glassDark, surface: .opaque, configuration: configuration
        )
        #expect(string.string == "SELECT")
        #expect(string.length == 6)
        #expect(color(string, at: 0) == theme(.keyword))
    }

    @Test("empty text with runs produces an empty string rather than a trap")
    func emptyTextWithRuns() {
        let string = AttributedAssembly.attributedString(
            text: "",
            runs: [HighlightRun(range: 0..<5, role: .keyword)],
            theme: .glassDark, surface: .opaque, configuration: configuration
        )
        #expect(string.length == 0)
    }

    // MARK: - Canvas

    @Test("canvas alpha is solid for an opaque backing and the window opacity otherwise")
    func canvasAlpha() {
        #expect(AttributedAssembly.canvasBackgroundAlpha(for: .opaque) == 1.0)
        #expect(
            AttributedAssembly.canvasBackgroundAlpha(
                for: SurfaceCondition(windowOpacity: 0.3, backing: .material(.thin))
            ) == 0.3
        )
        #expect(
            AttributedAssembly.canvasBackgroundAlpha(
                for: SurfaceCondition(windowOpacity: 0.65, backing: .blur(strength: 0.5))
            ) == 0.65
        )
    }

    @Test("gutter numbers resolve through the theme, never a system color")
    func gutterColorComesFromTheme() {
        let dark = AttributedAssembly.gutterNumberColor(
            theme: .glassDark, surface: .opaque, configuration: configuration
        )
        let light = AttributedAssembly.gutterNumberColor(
            theme: .glassLight, surface: .opaque, configuration: configuration
        )
        #expect(dark != light)
        #expect(abs(dark.alphaComponent - CGFloat(AttributedAssembly.gutterEmphasis)) < 0.001)
    }

    // MARK: - Helpers

    private func color(_ string: NSAttributedString, at index: Int) -> PlatformColor? {
        string.attribute(.foregroundColor, at: index, effectiveRange: nil) as? PlatformColor
    }

    private func theme(_ role: TokenRole) -> PlatformColor {
        PlatformColor(
            resolved: EditorTheme.glassDark.color(
                for: role,
                on: .opaque,
                floor: AttributedAssembly.contrastFloor(
                    configuration: configuration, surface: .opaque
                )
            ).color
        )
    }
}
