import Foundation
import GlassEditorCore

#if canImport(AppKit) && os(macOS)
import AppKit

/// The platform font class. Both backends assemble the *same* attribute
/// dictionaries, so everything from run resolution to weight compensation is
/// written once and only the two type names differ.
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
public typealias PlatformFontWeight = NSFont.Weight
#elseif canImport(UIKit)
import UIKit

public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformFontWeight = UIFont.Weight
#endif

#if canImport(AppKit) || canImport(UIKit)

// MARK: - Metrics

/// Layout constants both backends share, preserving the metrics the shipped
/// glassdb editor uses (INTEGRATION.md A3: "Gutter inset 56 / 12", "Container
/// inset 12").
///
/// The shipped implementation folded the gutter into `textContainerInset.left`
/// (56 with numbers, 12 without) because it hand-drew numbers inside the text
/// view. Both backends here draw the gutter in a *sibling* view — an
/// `NSRulerView` on macOS, a `UIView` on UIKit — so the same visual metric is
/// expressed as `gutterWidth + containerInset == 56`, with the text container's
/// own inset staying 12 in both configurations.
public enum EditorMetrics {
    /// Width of the line-number gutter view.
    public static let gutterWidth: CGFloat = 44
    /// Inset between the gutter (or the view edge) and the first glyph.
    public static let containerInset: CGFloat = 12
    /// Total leading inset when line numbers are shown — the shipped 56.
    public static let gutteredLeadingInset: CGFloat = gutterWidth + containerInset
    /// Trailing gap between a line number's right edge and the text.
    public static let gutterNumberTrailingGap: CGFloat = 10
    /// A change mark's bar: how wide, and how far its right edge is from the gutter's. It sits in
    /// the gap after the numbers, where VS Code and Zed put theirs.
    public static let changeMarkWidth: CGFloat = 3
    public static let changeMarkTrailingInset: CGFloat = 3
}

// MARK: - Color bridging

extension PlatformColor {
    /// `ResolvedColor` is the only color source in this package — no hard-coded
    /// colors anywhere in `GlassEditorUI` (projectRules.md, Theming).
    public convenience init(resolved: ResolvedColor) {
        #if canImport(AppKit) && os(macOS)
        self.init(
            srgbRed: CGFloat(resolved.red),
            green: CGFloat(resolved.green),
            blue: CGFloat(resolved.blue),
            alpha: CGFloat(resolved.alpha)
        )
        #else
        self.init(
            red: CGFloat(resolved.red),
            green: CGFloat(resolved.green),
            blue: CGFloat(resolved.blue),
            alpha: CGFloat(resolved.alpha)
        )
        #endif
    }
}

// MARK: - Attributed-string assembly

/// Turns text plus `[HighlightRun]` into platform text attributes, resolving
/// every color through `EditorTheme` against the live `SurfaceCondition`.
///
/// This is the one place either backend decides what a glyph looks like.
/// Nothing below it hard-codes a color, and nothing above it knows about
/// `NSAttributedString`.
public enum AttributedAssembly {

    // MARK: Range clamping

    /// The clamp policy for a highlight run against the *current* document
    /// length.
    ///
    /// Highlighting is asynchronous by construction — a parse is requested for
    /// one snapshot and arrives after the debounce, by which time the user may
    /// have deleted text. A run that names a range the document no longer has is
    /// therefore an ordinary race, not a bug in the highlighter, and must not
    /// trap or throw inside a draw pass.
    ///
    /// Policy, in order:
    /// - A run starting at or after `length` is **dropped** — there is nothing
    ///   left of it to paint.
    /// - A run overhanging the end is **truncated** to `length`.
    /// - A run that is empty after clamping is **dropped**; a zero-length
    ///   attribute run has no effect and would only cost an `addAttributes` call.
    /// - A negative lower bound is raised to 0 rather than rejected: the caller
    ///   is a highlighter, and a partially-usable run is better than a hole.
    ///
    /// The stale runs are replaced wholesale by the next pass, so a truncated
    /// run is visible for at most one debounce interval.
    public static func clampedRange(_ range: Range<Int>, toUTF16Length length: Int) -> NSRange? {
        let lower = max(range.lowerBound, 0)
        let upper = min(range.upperBound, length)
        guard lower < upper else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    // MARK: Fonts

    /// Weight ladder for `ContrastAdapter.fontWeightDelta` to step along.
    ///
    /// Ordered lightest to heaviest so a delta is an index shift, clamped at
    /// both ends — a theme already at `.black` simply stays there rather than
    /// wrapping or trapping.
    static let weightLadder: [PlatformFontWeight] = [
        .ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black,
    ]

    /// The base weight shifted by `delta` steps, clamped to the ladder.
    static func weight(steppedBy delta: Int, from base: PlatformFontWeight = .regular) -> PlatformFontWeight {
        let baseIndex = weightLadder.firstIndex(of: base) ?? 3
        let index = min(max(baseIndex + delta, 0), weightLadder.count - 1)
        return weightLadder[index]
    }

    /// The font for `configuration` with `surface`'s glyph-weight compensation
    /// applied (`ContrastAdapter.fontWeightDelta`).
    ///
    /// With no `fontName` this is the monospaced system font at the compensated
    /// weight. With one, the named font is asked for the same weight through a
    /// descriptor trait; a family that has no such face returns the named font
    /// unchanged rather than silently substituting a different family.
    public static func font(
        configuration: GlassEditorConfiguration,
        surface: SurfaceCondition
    ) -> PlatformFont {
        let size = CGFloat(configuration.fontSize)
        let target = weight(steppedBy: ContrastAdapter.fontWeightDelta(for: surface))

        guard let name = configuration.fontName, let named = PlatformFont(name: name, size: size) else {
            return PlatformFont.monospacedSystemFont(ofSize: size, weight: target)
        }

        let descriptor = named.fontDescriptor.addingAttributes([
            .traits: [PlatformFontDescriptorTraitKey.weight: target.rawValue]
        ])
        #if canImport(AppKit) && os(macOS)
        return PlatformFont(descriptor: descriptor, size: size) ?? named
        #else
        return PlatformFont(descriptor: descriptor, size: size)
        #endif
    }

    // MARK: Attributes

    /// The contrast floor in force for `surface`, layering the theme's
    /// translucency headroom on top of the consumer's configured base rather
    /// than replacing it (`EditorTheme.minimumContrastRatio(on:base:)`).
    public static func contrastFloor(
        configuration: GlassEditorConfiguration,
        surface: SurfaceCondition
    ) -> Double {
        EditorTheme.minimumContrastRatio(on: surface, base: configuration.minimumContrastRatio)
    }

    /// Attributes for one `TokenRole`, including the scrim when the adapter
    /// could not reach the floor with color alone.
    ///
    /// The scrim is emitted as `.backgroundColor` on the run. That is precisely
    /// the "behind the text run only, never behind the window" requirement in
    /// projectRules.md (Theming): a background attribute paints the run's own
    /// glyph rect and nothing else, so a transparent window stays transparent
    /// everywhere the text is already legible.
    public static func attributes(
        for role: TokenRole,
        theme: EditorTheme,
        surface: SurfaceCondition,
        configuration: GlassEditorConfiguration
    ) -> [NSAttributedString.Key: Any] {
        let result = theme.color(
            for: role,
            on: surface,
            floor: contrastFloor(configuration: configuration, surface: surface)
        )
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(configuration: configuration, surface: surface),
            .foregroundColor: PlatformColor(resolved: result.color),
        ]
        if result.scrimAlpha > 0 {
            var scrim = theme.background
            scrim.alpha = result.scrimAlpha
            attributes[.backgroundColor] = PlatformColor(resolved: scrim)
        }
        return attributes
    }

    /// Attributes for unhighlighted text — the `.plain` role.
    public static func baseAttributes(
        theme: EditorTheme,
        surface: SurfaceCondition,
        configuration: GlassEditorConfiguration
    ) -> [NSAttributedString.Key: Any] {
        attributes(for: .plain, theme: theme, surface: surface, configuration: configuration)
    }

    /// A fully assembled attributed string — the read-only rendering path
    /// (glassdb's DDL display at `TableDetailView.swift:4985` is exactly this
    /// shape: highlighting with no editor attached).
    public static func attributedString(
        text: String,
        runs: [HighlightRun],
        theme: EditorTheme,
        surface: SurfaceCondition,
        configuration: GlassEditorConfiguration
    ) -> NSAttributedString {
        let string = NSMutableAttributedString(
            string: text,
            attributes: baseAttributes(theme: theme, surface: surface, configuration: configuration)
        )
        applyRuns(runs, to: string, theme: theme, surface: surface, configuration: configuration)
        return string
    }

    /// Applies run attributes **in place**, leaving the characters untouched.
    ///
    /// The editing backends use this rather than `setAttributedString`: replacing
    /// the string would reset the selection, discard marked text, and make every
    /// highlight pass a document mutation. Only attributes move here.
    ///
    /// Callers are responsible for resetting the base attributes first when they
    /// want stale run attributes cleared — `resetBaseAttributes(on:...)` does it.
    public static func applyRuns(
        _ runs: [HighlightRun],
        to storage: NSMutableAttributedString,
        theme: EditorTheme,
        surface: SurfaceCondition,
        configuration: GlassEditorConfiguration
    ) {
        let length = storage.length
        guard length > 0 else { return }

        // One resolution per distinct role, not per run: `ContrastAdapter` runs a
        // 60-step bisection and a document has thousands of runs over a couple of
        // dozen roles.
        var cache: [TokenRole: [NSAttributedString.Key: Any]] = [:]
        for run in runs {
            guard let range = clampedRange(run.range, toUTF16Length: length) else { continue }
            let resolved: [NSAttributedString.Key: Any]
            if let cached = cache[run.role] {
                resolved = cached
            } else {
                resolved = attributes(
                    for: run.role, theme: theme, surface: surface, configuration: configuration
                )
                cache[run.role] = resolved
            }
            storage.addAttributes(resolved, range: range)
        }
    }

    /// Resets the whole storage to the `.plain` attributes, clearing any run
    /// attributes (including scrim backgrounds) left by the previous pass.
    public static func resetBaseAttributes(
        on storage: NSMutableAttributedString,
        theme: EditorTheme,
        surface: SurfaceCondition,
        configuration: GlassEditorConfiguration
    ) {
        guard storage.length > 0 else { return }
        storage.setAttributes(
            baseAttributes(theme: theme, surface: surface, configuration: configuration),
            range: NSRange(location: 0, length: storage.length)
        )
    }

    // MARK: Canvas

    /// Opacity of the theme background the backend paints behind the text canvas.
    ///
    /// The package owns the text canvas and nothing else: the window material,
    /// its blur, and its vibrancy are the consumer's business (glas.sh composes
    /// its own glass at `TerminalWindowView.swift:773`; glassdb at
    /// `TableDetailView.swift:1451`). So an `.opaque` backing paints a solid
    /// ground, and a translucent one paints the theme background at exactly the
    /// resolved window opacity — never more, which would quietly re-opaque a
    /// window the user asked to see through.
    public static func canvasBackgroundAlpha(for surface: SurfaceCondition) -> Double {
        switch surface.backing {
        case .opaque:
            return 1.0
        case .material, .blur:
            return surface.windowOpacity
        }
    }

    /// The canvas fill color for `theme` on `surface`.
    public static func canvasColor(theme: EditorTheme, surface: SurfaceCondition) -> PlatformColor {
        var background = theme.background
        background.alpha = canvasBackgroundAlpha(for: surface)
        return PlatformColor(resolved: background)
    }

    /// Gutter number color: the `.plain` role at reduced emphasis, resolved
    /// through the theme like everything else. Never a system label color, which
    /// would ignore the theme, and never a literal.
    public static func gutterNumberColor(
        theme: EditorTheme,
        surface: SurfaceCondition,
        configuration: GlassEditorConfiguration
    ) -> PlatformColor {
        let result = theme.color(
            for: .plain,
            on: surface,
            floor: contrastFloor(configuration: configuration, surface: surface)
        )
        // Line numbers are chrome, not content: they are deliberately quieter
        // than the text they index, so the contrast floor — which governs
        // *readable text* — is not the right gate for them. The alpha is applied
        // to the floor-clearing color, so the gutter tracks the theme and the
        // surface without ever being the reason a glyph is unreadable.
        var color = result.color
        color.alpha = gutterEmphasis
        return PlatformColor(resolved: color)
    }

    /// Relative emphasis of gutter numbers against body text.
    static let gutterEmphasis: Double = 0.55

    /// A change mark's colour, from the theme's own green, amber and red: a string's for lines
    /// added, a number's for lines modified, an error's for lines removed.
    public static func changeMarkColor(
        _ kind: LineChange.Kind,
        theme: EditorTheme,
        surface: SurfaceCondition,
        configuration: GlassEditorConfiguration
    ) -> PlatformColor {
        let role: TokenRole = switch kind {
        case .added: .string
        case .modified: .number
        case .deleted: .error
        }
        let result = theme.color(for: role, on: surface,
                                 floor: contrastFloor(configuration: configuration, surface: surface))
        return PlatformColor(resolved: result.color)
    }

    /// The gutter's own font: monospaced *digits* at a size below the body text,
    /// matching the shipped metric (`HighlightedTextEditor.swift:372`).
    public static func gutterFont(configuration: GlassEditorConfiguration) -> PlatformFont {
        PlatformFont.monospacedDigitSystemFont(
            ofSize: max(10, CGFloat(configuration.fontSize) - 2),
            weight: .regular
        )
    }
}

/// Spelling of the font-descriptor traits key differs between the two
/// frameworks; the surrounding logic does not.
#if canImport(AppKit) && os(macOS)
typealias PlatformFontDescriptorTraitKey = NSFontDescriptor.TraitKey
#elseif canImport(UIKit)
typealias PlatformFontDescriptorTraitKey = UIFontDescriptor.TraitKey
#endif

// MARK: - Debounce

/// The "one highlight pass per idle beat" primitive both coordinators use.
///
/// Reproduces the shipped AppKit behavior at `HighlightedTextEditor.swift:312–329`
/// — a cancellable `Task` per edit, so a burst of keystrokes collapses into a
/// single pass — with the interval taken from
/// `GlassEditorConfiguration.highlightDebounceMilliseconds` (75 by default)
/// rather than hard-coded.
///
/// `flush()` exists so the behavior is testable without sleeping: a test
/// schedules twice, flushes, and counts one pass. Production code does not need
/// it, but a consumer tearing down a view can call it to land pending work
/// deterministically.
@MainActor
public final class DebounceBox {
    private var pending: (@MainActor () -> Void)?
    private var task: Task<Void, Never>?

    /// Idle interval before pending work runs.
    public var delay: Duration

    public init(milliseconds: Int) {
        self.delay = .milliseconds(max(0, milliseconds))
    }

    public convenience init(configuration: GlassEditorConfiguration) {
        self.init(milliseconds: configuration.highlightDebounceMilliseconds)
    }

    /// Whether work is waiting to run.
    public var hasPendingWork: Bool { pending != nil }

    /// Replaces any pending work with `work` and restarts the idle timer.
    public func schedule(_ work: @escaping @MainActor () -> Void) {
        task?.cancel()
        pending = work
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.delay ?? .milliseconds(75))
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    /// Runs pending work immediately, if any.
    public func flush() {
        task?.cancel()
        task = nil
        fire()
    }

    /// Discards pending work without running it.
    public func cancel() {
        task?.cancel()
        task = nil
        pending = nil
    }

    private func fire() {
        guard let work = pending else { return }
        pending = nil
        work()
    }

    // No `deinit` cancellation: the sleeping task captures `self` weakly, so a
    // box that goes away simply has its pending work drop on the floor when the
    // timer lands. A `deinit` touching `task` would be a nonisolated deinit
    // reading main-actor state, which Swift 6 rejects.
}

#endif
