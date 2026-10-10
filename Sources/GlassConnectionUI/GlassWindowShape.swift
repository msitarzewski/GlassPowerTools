//
//  GlassWindowShape.swift
//  Glass Power Tools — GlassConnectionUI
//
//  The shape a Glass window's own paint takes, so a window without a shape of its own still has
//  the system's.
//
//  A visionOS window in `.windowStyle(.plain)` has no glass and no shape: its bounds are a square
//  rectangle, and nothing rounds or clips what is painted in them. The terminal, desktop, Files,
//  editor and database windows are plain so that their transparency is theirs (D40). In Files and
//  the editor the theme paint filled those square bounds, and showed as dark square corners
//  outside the rounded glass their navigation containers draw (owner, on the Vision Pro,
//  2026-10-09: "they all have dark squared corners").
//
//  Neither shape API answers inside a plain window. `ContainerRelativeShape` and
//  `ConcentricRectangle` both resolve to the plain rectangle there — traced over the Files window
//  in the visionOS 27.2 simulator (W16) — because the window declares no container shape. So the
//  corner is a number, and the number is the system's own: a 46-point continuous rounded rectangle
//  traced over the same window lands on the edge of the glass the system draws, at all four
//  corners. Recheck it on a new visionOS by the same trace (`Tools/Screenshots/shoot.sh … files`).
//

import CoreGraphics

public enum GlassWindowShape {
    /// The corner of a visionOS window's glass, in points, drawn with continuous curvature.
    public static let spatialWindowCornerRadius: CGFloat = 46

    /// How far `GlassNativeWindowFrame` insets a canvas at its sides, to keep it clear of the
    /// title and control ornaments.
    public static let spatialCanvasInset: CGFloat = 22

    /// A canvas inside that inset, concentric with the window: 46 − 22 = 24, the corner the
    /// family's canvas card already has (`GlassCanvasBackdrop`, the desktop's session card).
    public static var spatialCanvasCornerRadius: CGFloat {
        spatialWindowCornerRadius - spatialCanvasInset
    }

    /// The corner for paint that fills a layered window's content.
    ///
    /// - Parameters:
    ///   - spatial: the headset, where a plain window gives its content no shape.
    ///   - insetForOrnaments: the frame insets the content to clear its title and control
    ///     ornaments, so the paint is the canvas card rather than the whole window.
    /// - Returns: 0 off the headset: a Mac or iPad window shapes and clips its own content, and the
    ///   paint fills it edge to edge.
    public static func paintCornerRadius(spatial: Bool, insetForOrnaments: Bool) -> CGFloat {
        guard spatial else { return 0 }
        return insetForOrnaments ? spatialCanvasCornerRadius : spatialWindowCornerRadius
    }
}
