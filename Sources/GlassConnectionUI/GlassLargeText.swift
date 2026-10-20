//
//  GlassLargeText.swift
//  Glass Power Tools — GlassConnectionUI
//
//  The app at the five accessibility text sizes (2026-10-19). At the largest of them a service's
//  name was cut to "T…" beside buttons that kept their width, a database's Filter and More broke a
//  syllable to a line, and a tab read "Ov…ew". The owner approved three remedies, Apple's own:
//  rows stack, bars go icon-only with the Large Content Viewer, and names wrap. One place for each,
//  so every screen behaves alike. At the sizes most people use, nothing here changes anything.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A row as its caller lays it out, or, at an accessibility text size, its name on lines of its own
/// and its buttons under it, leading.
///
/// Side by side, a name takes what the buttons leave, and at the largest sizes that is nothing.
/// Apple's lists stack the same way.
public struct GlassLargeTextRow<Inline: View, Identity: View, Actions: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let inline: Inline
    private let identity: Identity
    private let actions: Actions

    /// - Parameters:
    ///   - inline: the row at ordinary sizes, unchanged.
    ///   - identity: the icon and name; stacked, it has the row's whole width.
    ///   - actions: the buttons, one line of them under the identity when stacked.
    public init(@ViewBuilder inline: () -> Inline, @ViewBuilder identity: () -> Identity,
                @ViewBuilder actions: () -> Actions) {
        self.inline = inline()
        self.identity = identity()
        self.actions = actions()
    }

    public var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                identity
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) { actions }
                    .fixedSize()
            }
        } else {
            inline
        }
    }
}

public extension View {
    /// A name that wraps at an accessibility text size and keeps to `lineLimit` lines otherwise.
    /// Names cannot shrink the way icons can; cut to "T…", a service is no longer told apart.
    func glassLargeTextWraps(lineLimit: Int = 1) -> some View {
        modifier(GlassLargeTextWraps(lineLimit: lineLimit))
    }

    /// A bar: a toolbar, a status line or a strip of tabs, one line whatever the text size.
    ///
    /// Its text grows no further than the largest ordinary size (xxxLarge). Past it, Apple's bars
    /// stop growing and say what an item is in the Large Content Viewer, the large bubble a long
    /// press shows; every item in the bar offers it (``glassBarItem()``). Labels in the bar show only
    /// their icon then.
    func glassBar() -> some View {
        modifier(GlassBar())
    }

    /// An item in a ``glassBar()``: in the Large Content Viewer at accessibility sizes, and a label
    /// shown by its icon alone there, as Apple's toolbars do. Outside a bar it reads the text size
    /// itself.
    func glassBarItem() -> some View {
        labelStyle(GlassBarLabelStyle())
            .accessibilityShowsLargeContentViewer()
    }
}

private struct GlassLargeTextWraps: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let lineLimit: Int

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        } else {
            content.lineLimit(lineLimit)
        }
    }
}

private struct GlassBar: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            // Read before the cap below: inside it, every size is at most xxxLarge.
            .environment(\.glassBarIsCondensed, dynamicTypeSize.isAccessibilitySize)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The label as its context draws it, or its icon alone at an accessibility text size.
private struct GlassBarLabelStyle: LabelStyle {
    @Environment(\.glassBarIsCondensed) private var condensedBar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        if condensedBar ?? dynamicTypeSize.isAccessibilitySize {
            Label(configuration).labelStyle(.iconOnly)
        } else {
            Label(configuration)
        }
    }
}

private extension EnvironmentValues {
    /// Whether the bar around this view stands at an accessibility text size; nil outside a bar.
    @Entry var glassBarIsCondensed: Bool? = nil
}

// MARK: - Text a person sizes themselves

/// The terminal's and the results grid's own text sizes, at the system's text size (the owner,
/// 2026-10-19: their default follows it). The size a person picks is its size at the standard text
/// size, and the system's setting scales it as it scales body text, so someone with large text gets
/// large rows from the start. Each capability's settings can turn it off.
public enum GlassSystemTextSize {
    /// `size` at `dynamicTypeSize`, whole points within `range`. At the standard size (Large), and
    /// on a Mac, which has no such setting, `size` as it is.
    public static func scaled(_ size: CGFloat, for dynamicTypeSize: DynamicTypeSize,
                              within range: ClosedRange<CGFloat>) -> CGFloat {
        #if canImport(UIKit)
        guard dynamicTypeSize != .large else { return size }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: size, compatibleWith: traits)
        return min(range.upperBound, max(range.lowerBound, scaled.rounded()))
        #else
        return size
        #endif
    }
}

// MARK: - A sidebar's width

public extension View {
    /// A sidebar column as wide as the library's (`GlassLibraryColumnLayout`), and wider at an
    /// accessibility text size. At 340 points and the largest size a file's name broke mid-word
    /// ("com-pose.yaml", the editor on an iPad, 2026-10-19); at 480 a name of a dozen letters is
    /// whole. At the sizes most people use, the column is as it was.
    func glassNavigationColumnWidth() -> some View { modifier(GlassNavigationColumnWidth()) }
}

private struct GlassNavigationColumnWidth: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        // One modifier with either set of widths, not two branches: a change of text size keeps the
        // list, its scroll position and its selection.
        let wide = dynamicTypeSize.isAccessibilitySize
        content.navigationSplitViewColumnWidth(
            min: wide ? GlassLibraryColumnLayout.accessibilityNavigationMinimum : GlassLibraryColumnLayout.navigationMinimum,
            ideal: wide ? GlassLibraryColumnLayout.accessibilityNavigationIdeal : GlassLibraryColumnLayout.navigationIdeal,
            max: wide ? GlassLibraryColumnLayout.accessibilityNavigationMaximum : GlassLibraryColumnLayout.navigationMaximum)
    }
}
