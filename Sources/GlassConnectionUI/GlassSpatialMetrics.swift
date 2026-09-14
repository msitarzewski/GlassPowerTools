import SwiftUI

/// The sizes a spatial surface is read and aimed at.
///
/// visionOS is looked at from roughly a metre and a half and aimed with the eyes, so the numbers a
/// Mac layout is built from are wrong twice over: text sized for a screen half a metre away is
/// unreadable, and a control sized for a cursor is smaller than the eye can reliably settle on.
/// Apple's guidance is a **60 pt minimum** for a comfortable gaze target.
///
/// These live in one place so the whole family moves together, and so a value can be justified
/// rather than guessed at each call site. On every other platform the accessors return the
/// platform's own metric unchanged — this is not a licence to make the Mac bigger.
public enum GlassSpatialMetrics {
    /// Whether the running platform is aimed with the eyes rather than a cursor or fingertip.
    public static var isSpatial: Bool {
        #if os(visionOS)
        true
        #else
        false
        #endif
    }

    /// Minimum comfortable gaze target. Apple's figure, not a preference.
    public static let gazeTarget: CGFloat = 60

    /// Height a library row must reach to be aimed at without effort.
    public static var rowMinimumHeight: CGFloat { isSpatial ? gazeTarget : 0 }

    /// Padding inside a row. Spatial rows need the room; a Mac row must not grow.
    public static var rowVerticalPadding: CGFloat { isSpatial ? 8 : 0 }
    public static var rowHorizontalPadding: CGFloat { isSpatial ? 8 : 0 }

    /// Gap between an ornament's controls, and the ornament's own inset.
    public static let ornamentSpacing: CGFloat = 20
    public static let ornamentPadding: CGFloat = 22

    /// The type a library row is set in.
    ///
    /// One step up on visionOS, and no further. `.headline` is right on a Mac at half a metre and
    /// small at a metre and a half; `.title3` reads. Going larger starts to change the design
    /// rather than adapt it, and the row has to stay recognisably the same row — a Mac user must
    /// know this app on sight.
    public static var rowTitleFont: Font { isSpatial ? .title3 : .headline }
    public static var rowSubtitleFont: Font { isSpatial ? .callout : .caption }

    /// A section header in a spatial sidebar. `.caption` uppercase is a desktop convention that
    /// disappears at reading distance.
    public static var sectionHeaderFont: Font { isSpatial ? .headline : .subheadline }
}

public extension View {
    /// Makes a view respond to being looked at, on the platform where that is the aiming method.
    ///
    /// A visionOS control that does not highlight under gaze reads as disabled, because looking at
    /// something *is* how a user asks "can I press this?". The modifier is a no-op elsewhere, so a
    /// call site does not need its own `#if`.
    @ViewBuilder
    func glassGazeHighlight(_ enabled: Bool = true) -> some View {
        #if os(visionOS)
        if enabled { self.hoverEffect(.highlight) } else { self }
        #else
        self
        #endif
    }

    /// Gives a row the height and padding a gaze target needs, and leaves every other platform's
    /// own metrics alone.
    @ViewBuilder
    func glassSpatialRowMetrics() -> some View {
        #if os(visionOS)
        self.frame(minHeight: GlassSpatialMetrics.rowMinimumHeight, alignment: .leading)
            .padding(.vertical, GlassSpatialMetrics.rowVerticalPadding)
            .padding(.horizontal, GlassSpatialMetrics.rowHorizontalPadding)
        #else
        self
        #endif
    }
}

public extension View {
    /// The surface behind a detail panel's action bar.
    ///
    /// `.bar` is a `Material`, and a material is a 2-D stand-in for glass: it samples what is
    /// behind the window and works on a Mac. On visionOS the window's own glass is already the
    /// surface, so painting a bar across it adds an opaque strip rather than depth — the same
    /// mistake, one control smaller, as filling the whole window with `.ultraThinMaterial`. The
    /// divider above already separates the bar from the content, which is what the material was
    /// there to do.
    @ViewBuilder
    func glassActionBarSurface() -> some View {
        // Nothing, on any platform. `.bar` is a material, and a material over a window that is
        // deliberately translucent composites whatever is behind the *window* — the desktop — so
        // the footer read as a stripe of wallpaper. Swapping it for an opaque fill only traded one
        // wrong answer for another, because the panel is meant to be glass. The divider above the
        // bar is what separates it from the content, and that is enough.
        self
    }
}
