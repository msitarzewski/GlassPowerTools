//
//  GlassSessionGallery.swift
//  Glass Power Tools — GlassShell
//
//  The layout solver the Mac's Terminal Overview drew its cards with, which Show All Windows' packing
//  (`GlassAllWindowsLayout`) asks for its tile size. The overview draws as Show All Windows does now,
//  without the carousel, the card-width slider or the card of a session open elsewhere (D96,
//  2026-11-02); the card went with it.
//

import SwiftUI

/// How many cards fit across, and how wide each one is.
///
/// Moved from `MacTerminalOverview.swift`, where it was `MacTerminalOverviewGrid`, unchanged
/// except for its name and where it lives. Pure arithmetic, so it is tested without a screen —
/// which is also why it could move without anything being re-derived.
public struct GlassGalleryLayout: Equatable, Sendable {
    public let columns: Int
    public let cardWidth: CGFloat

    /// Card proportions and the space around them, shared so a card laid out here and a card
    /// drawn in `GlassSessionCard` cannot drift apart.
    public static let spacing: CGFloat = 18
    public static let aspectRatio: CGFloat = 1.6
    /// Room under the image for a title and a subtitle.
    public static let captionHeight: CGFloat = 72
    /// The narrowest card this will ever describe.
    ///
    /// **A crash, not a nicety.** `GeometryReader` reports a degenerate size on its first pass
    /// inside a sheet, which drove `cardWidth` to 1 — and a `GridItem(.flexible(maximum: 1))` is
    /// below SwiftUI's own default minimum of 10, so `LazyVGrid` trapped in
    /// `HVGrid.minorGeometry` and took the app with it the moment the gallery opened.
    public static let minimumCardWidth: CGFloat = 40

    public init(count: Int, size: CGSize, preferredWidth: Double? = nil) {
        let width = max(1, size.width - 12)
        if let preferredWidth, preferredWidth.isFinite {
            let preferred = min(720, max(220, preferredWidth))
            columns = max(1, min(max(1, count), Int((width + Self.spacing) / (preferred + Self.spacing))))
            cardWidth = max(Self.minimumCardWidth,
                            min(preferred, max(1, (width - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns))))
            return
        }
        let maximumColumns = max(1, min(max(1, count), Int((width + Self.spacing) / 238)))
        var chosen = maximumColumns
        for columns in 1...maximumColumns {
            let cardWidth = min(520, max(1, (width - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns)))
            let rows = max(1, Int(ceil(Double(count) / Double(columns))))
            if CGFloat(rows) * (cardWidth / Self.aspectRatio + Self.captionHeight)
                + CGFloat(rows - 1) * Self.spacing <= size.height - 12 {
                chosen = columns
                break
            }
        }
        columns = chosen
        cardWidth = max(Self.minimumCardWidth,
                        min(520, max(1, (width - CGFloat(chosen - 1) * Self.spacing) / CGFloat(chosen))))
    }
}
