//
//  GlassSessionGallery.swift
//  Glass Power Tools — GlassShell
//
//  The card and the layout solver the Mac's Terminal Overview draws sessions with.
//
//  **Almost none of this is new.** The product has had a terminal overview since glas.sh: a grid,
//  a carousel, live previews of each session, a card-width slider, arrow-key navigation, and a
//  rule about which card may steal attention. It switches between *one workgroup's terminals* on
//  macOS and visionOS. What was missing was the same thing across capabilities, on a phone.
//
//  So the layout solver moved here rather than being written again — it is the same question
//  ("how many columns fit, at what card width, so the rows fit the height") and it already had
//  tests. `MacTerminalOverview` now asks this one.
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

/// One session as a card: what it looks like right now, what it is, and a way to end it.
///
/// The shape is the terminal overview's, which is the one the product already teaches: the
/// picture on top at 1.6, the name under it in the colour of its state, a selection border. The
/// difference is that the picture is optional here — only the terminal can currently draw itself,
/// and a database or an editor says what it is instead of pretending to a screenshot.
public struct GlassSessionCard: View {
    private let session: GlassOpenSession
    private let activate: () -> Void
    private let close: () -> Void

    public init(session: GlassOpenSession, activate: @escaping () -> Void, close: @escaping () -> Void) {
        self.session = session
        self.activate = activate
        self.close = close
    }

    public var body: some View {
        Button(action: activate) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary.opacity(0.4))
                    if let snapshot = session.snapshot?() {
                        snapshot
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        // Not a missing screenshot — a session that has no picture of itself.
                        // Its own symbol, large and quiet, reads as deliberate.
                        Image(systemName: session.symbolName)
                            .font(.system(size: 34))
                            .foregroundStyle(.tertiary)
                    }
                }
                .aspectRatio(GlassGalleryLayout.aspectRatio, contentMode: .fit)
                .clipped()

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: session.symbolName)
                        .font(.caption)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let subtitle = session.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session-card-\(session.id)")
        .accessibilityLabel(session.title)
        .accessibilityValue(session.subtitle ?? "")
        // Swiping a card is the list's gesture and does not exist in a grid, so the way to end a
        // session here is a control on the card.
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive, action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityIdentifier("session-card-close-\(session.id)")
            .accessibilityLabel("Close \(session.title)")
        }
    }
}

