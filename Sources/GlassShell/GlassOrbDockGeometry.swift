//
//  GlassOrbDockGeometry.swift
//  Glass Power Tools — GlassShell
//
//  The orb dock's geometry, apart from drawing it, so it is tested without a headset (D88; the owner,
//  2026-10-26). Orbs stand in one line, a row or a column as the person chooses (2026-11-05; until then they
//  flowed into rows as the dock's shape allowed, and the dock snapped around them when resized); a carried
//  orb lands on the one under it, in any direction; a dot's name opens toward the side with room ("When
//  a docked window's tab is too close to the right to reliably show, it should show to the left instead
//  and not get cropped"); and a window from a tall dock comes back beside it ("it should appear to the
//  left or right depending on dock position").
//

import CoreGraphics
import Foundation

/// Which way the dock lays out its orbs: a row, or a column (the owner, 2026-11-05: "We need to provide an orientation
/// selection for the dock. horizontal or vertical, then honor that when adding/removing windows/sessions"). Until then
/// the orbs wrapped into rows within whatever size the dock was left at: a dock once resized, or one whose own shrink
/// was taken for the person's, put the next window docked on a new row. Now the dock is one line of orbs, which grows
/// and shrinks along its way as orbs come and go and scrolls past its longest; a size given by hand isn't kept (his
/// choices: scroll along it; fit the orbs; the Mac's dock and Vision Pro's alike). The same on both, this device's.
public enum GlassOrbDockOrientation: String, CaseIterable, Sendable {
    case horizontal
    case vertical

    public static let key = "com.glasspowertools.orbs.dockOrientation"

    public var title: String {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }

    /// The setting in `defaults`; horizontal until chosen.
    public static func current(in defaults: UserDefaults) -> Self {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .horizontal
    }
}

/// The dock's orbs in one line, Connections first and set apart: left to right in a row, each standing on the row's
/// middle; top to bottom in a column, each on the column's middle.
public enum GlassOrbLine {
    /// Frames for items of `sizes`, in order, along `orientation`. The first is set apart by `gapAfterFirst`.
    public static func frames(of sizes: [CGSize], _ orientation: GlassOrbDockOrientation,
                              gapAfterFirst: CGFloat = 0) -> [CGRect] {
        let thickness = sizes.map { orientation == .horizontal ? $0.height : $0.width }.max() ?? 0
        var along: CGFloat = 0
        return sizes.enumerated().map { index, size in
            if index == 1 { along += gapAfterFirst }
            defer { along += orientation == .horizontal ? size.width : size.height }
            switch orientation {
            case .horizontal:
                return CGRect(x: along, y: (thickness - size.height) / 2, width: size.width, height: size.height)
            case .vertical:
                return CGRect(x: (thickness - size.width) / 2, y: along, width: size.width, height: size.height)
            }
        }
    }

    /// What the line of `sizes` takes up.
    public static func size(of sizes: [CGSize], _ orientation: GlassOrbDockOrientation,
                            gapAfterFirst: CGFloat = 0) -> CGSize {
        let frames = frames(of: sizes, orientation, gapAfterFirst: gapAfterFirst)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    /// The dock's size around the line: every orb, or the whole orbs that fit in `longest` along it (at least the first),
    /// the rest scrolled to; one orb thick; `inset` between the edge and the orbs; never under `minimum`. Whole points,
    /// rounded up, so the same orbs fit again in what it is given.
    public static func fitted(_ sizes: [CGSize], _ orientation: GlassOrbDockOrientation, inset: CGFloat,
                              gapAfterFirst: CGFloat = 0, longest: CGFloat = .greatestFiniteMagnitude,
                              minimum: CGSize = .zero) -> CGSize {
        let frames = frames(of: sizes, orientation, gapAfterFirst: gapAfterFirst)
        guard !frames.isEmpty else { return minimum }
        let ends = frames.map { orientation == .horizontal ? $0.maxX : $0.maxY }
        let room = longest - 2 * inset
        let length = ends.last { $0 <= room + 0.5 } ?? ends[0]
        let thickness = frames.map { orientation == .horizontal ? $0.maxY : $0.maxX }.max() ?? 0
        let size = orientation == .horizontal
            ? CGSize(width: length, height: thickness) : CGSize(width: thickness, height: length)
        return CGSize(width: max((size.width + 2 * inset).rounded(.up), minimum.width),
                      height: max((size.height + 2 * inset).rounded(.up), minimum.height))
    }
}

public extension GlassOrbDockOrder {
    /// Where an orb carried to `point` lands among orbs at `frames` (the carried one among them): on
    /// the one under it; before them all over `before` (Connections) or ahead of the first; after
    /// them all anywhere else.
    static func landing(at point: CGPoint, frames: [CGRect], before: CGRect? = nil) -> Landing {
        if let index = frames.firstIndex(where: { $0.contains(point) }) { return .on(index) }
        if before?.contains(point) == true { return .first }
        guard let first = frames.first else { return .last }
        if point.y < first.minY || (point.y < first.maxY && point.x < first.minX) { return .first }
        return .last
    }
}

/// The room either side of an orb's middle, within the dock.
public struct GlassOrbNameRoom: Equatable, Sendable {
    public var leading: CGFloat
    public var trailing: CGFloat

    public init(leading: CGFloat, trailing: CGFloat) {
        self.leading = leading
        self.trailing = trailing
    }
}

/// Which way a dot's name opens from it.
public enum GlassOrbNameSide {
    /// From the dot's middle to the end of its widest name: the dot's half, the gap, the name and the
    /// capsule's end (`GlassSessionOrbView.openingDot`).
    public static func reach(dotDiameter: CGFloat, nameWidth: CGFloat) -> CGFloat {
        dotDiameter / 2 + 4 + nameWidth + 16
    }

    /// Whether it opens toward the leading side: when the room past the dot toward the trailing
    /// edge is less than a name needs, and the leading side has more.
    public static func opensLeading(trailingRoom: CGFloat, leadingRoom: CGFloat, needs: CGFloat) -> Bool {
        trailingRoom < needs && leadingRoom > trailingRoom
    }
}

/// A ring's dots as `GlassOrbRingLayout` lays them out: evenly around the orb from its top, in the
/// ring's own space, x growing toward the trailing side (mirrored with the layout in a right-to-left
/// language).
public enum GlassOrbRing {
    /// The middle of dot `index` of `count`, `radius` from the orb's.
    public static func center(of index: Int, count: Int, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(count, 1))
        return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
    }

    /// How far dot `index` stands toward the front, from 0 (the trailing-most) to 1 (the leading-most),
    /// so a name opening toward the trailing side lies over the dots it crosses (`GlassOrbRingLayout.lift`).
    public static func standing(of index: Int, count: Int) -> CGFloat {
        (1 - center(of: index, count: count, radius: 1).x) / 2
    }

    /// The dots standing in front of dot `index`'s open name that lie across it, whose capsule is
    /// `width` long from its dot's far edge. Only a name opening toward the leading side
    /// (`GlassOrbNameSide`) has any: they make way while it is open, rather than cover it (the owner,
    /// 2026-10-27: "left seems to overlap even when looking at the right").
    public static func makingWay(for index: Int, count: Int, opensLeading: Bool, width: CGFloat,
                                 radius: CGFloat, dotDiameter: CGFloat) -> [Int] {
        let dot = center(of: index, count: count, radius: radius)
        // The capsule is its dot's circle drawn along a line to the far end.
        let end = dot.x + (opensLeading ? -1 : 1) * max(width - dotDiameter, 0)
        let (low, high) = (min(dot.x, end), max(dot.x, end))
        return (0..<count).filter { other in
            guard other != index, standing(of: other, count: count) > standing(of: index, count: count) else { return false }
            let point = center(of: other, count: count, radius: radius)
            // More than a point of the dot over the capsule.
            return hypot(point.x - min(max(point.x, low), high), point.y - dot.y) < dotDiameter - 1
        }
    }
}

/// Where a window comes back from the dock.
public enum GlassOrbDockSide: String, Equatable, Sendable {
    case above, leading, trailing

    /// Turned this far, the head is turned to the dock; less, the dock is straight ahead.
    public static let turned = 10 * Double.pi / 180

    /// A wide dock's window comes back above it. A tall one's comes back beside it: away from where
    /// the person turned to see it when the head is known (in Focus Mode, the only place visionOS
    /// tells it), with the dock off to their left (the head turned left, a positive heading) to its
    /// trailing side, off to their right to its leading side; ahead of them, or with no heading
    /// known, on the side they chose in Settings (`otherwise`).
    public static func returning(tall: Bool, headYaw: Double?, otherwise: GlassOrbDockSide = .trailing) -> GlassOrbDockSide {
        guard tall else { return .above }
        guard let headYaw, headYaw.isFinite, abs(headYaw) >= turned else { return otherwise == .above ? .trailing : otherwise }
        return headYaw > 0 ? .trailing : .leading
    }

    /// A heading for a direction the head faces: 0 down −z, positive turned left (RealityKit's).
    public static func heading(forwardX x: Double, forwardZ z: Double) -> Double { atan2(-x, -z) }
}

/// What a pinch and hold on the dock's Connections orb offers (the owner, 2026-10-26: favorites and
/// recents, and Settings): the favorite machines, then up to `recentCount` others by when they were
/// last connected, newest first; only machines with a service this device can open.
public enum GlassOrbDockMenu {
    public static let recentCount = 5

    public static func machines<ID: Hashable>(_ ids: [ID], isFavorite: (ID) -> Bool, lastConnected: (ID) -> Date?,
                                              canOpen: (ID) -> Bool) -> (favorites: [ID], recents: [ID]) {
        let openable = ids.filter(canOpen)
        let favorites = openable.filter(isFavorite)
        let recents = openable
            .filter { !isFavorite($0) && lastConnected($0) != nil }
            .sorted { (lastConnected($0) ?? .distantPast) > (lastConnected($1) ?? .distantPast) }
        return (favorites, Array(recents.prefix(recentCount)))
    }
}
