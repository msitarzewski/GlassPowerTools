//
//  GlassOrbDockGeometry.swift
//  Glass Power Tools — GlassShell
//
//  The orb dock's geometry, apart from drawing it, so it is tested without a headset (D88; the owner,
//  2026-10-26). Orbs flow into rows as the dock's shape allows ("a responsive flex ... where the docked
//  windows move to fit the shape of the dock"), and the dock snaps around them when resized; a carried
//  orb lands on the one under it, in any direction; a dot's name opens toward the side with room ("When
//  a docked window's tab is too close to the right to reliably show, it should show to the left instead
//  and not get cropped"); and a window from a tall dock comes back beside it ("it should appear to the
//  left or right depending on dock position").
//

import CoreGraphics
import Foundation

/// Orbs in rows, as a flexbox wraps: each row from the leading edge, an orb that would cross the
/// width starting the next.
public enum GlassOrbFlow {
    /// Frames for items of `sizes`, in order, in rows no wider than `width`. An item wider than
    /// `width` has a row of its own; items stand on their row's middle. The first item is set apart by
    /// `gapAfterFirst`, beside the next or above it. When every row holds one item, the dock is a
    /// column, and they stand on one line down the middle of `width`.
    public static func frames(of sizes: [CGSize], width: CGFloat, gapAfterFirst: CGFloat = 0) -> [CGRect] {
        layout(of: sizes, width: width, gapAfterFirst: gapAfterFirst).frames
    }

    /// The frames, and where each row ends below.
    private static func layout(of sizes: [CGSize], width: CGFloat, gapAfterFirst: CGFloat) -> (frames: [CGRect], bottoms: [CGFloat]) {
        guard !sizes.isEmpty else { return ([], []) }
        var rows: [[Int]] = []
        var row: [Int] = []
        var x: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let gap = index == 1 && row == [0] ? gapAfterFirst : 0
            if !row.isEmpty, x + gap + size.width > width {
                rows.append(row)
                row = []
                x = 0
            }
            x += (row.isEmpty ? 0 : gap) + size.width
            row.append(index)
        }
        rows.append(row)

        let column = rows.count > 1 && rows.allSatisfy { $0.count == 1 } && width.isFinite
        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var bottoms: [CGFloat] = []
        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            if rowIndex == 1, rows[0] == [0] { y += gapAfterFirst }
            let height = row.map { sizes[$0].height }.max() ?? 0
            var x: CGFloat = 0
            for index in row {
                let size = sizes[index]
                if index == 1, row.first == 0 { x += gapAfterFirst }
                let left = column ? (width - size.width) / 2 : x
                frames[index] = CGRect(x: left, y: y + (height - size.height) / 2, width: size.width, height: size.height)
                x += size.width
            }
            y += height
            bottoms.append(y)
        }
        return (frames, bottoms)
    }

    /// The dock's size around items of `sizes` within `bounds`, the size the person gave it (the
    /// owner, 2026-10-27: "When we resize the dock, let's make sure it snaps to the shape of the
    /// visible icons"; he chose the nearest whole rows): as wide as the widest row they make there;
    /// as tall as every row when they fit, else as the whole rows nearest its height, at least one,
    /// the rest scrolled to. `inset` is between the edge and the items; never under `minimum`.
    /// Rounded up to whole points, so the same rows fit again in what it snaps to.
    public static func snapped(_ sizes: [CGSize], within bounds: CGSize, inset: CGFloat, gapAfterFirst: CGFloat = 0,
                               minimum: CGSize = .zero) -> CGSize {
        let (frames, bottoms) = layout(of: sizes, width: max(bounds.width - 2 * inset, 0), gapAfterFirst: gapAfterFirst)
        guard let left = frames.map(\.minX).min(), let right = frames.map(\.maxX).max(), let all = bottoms.last else {
            return minimum
        }
        let wanted = bounds.height - 2 * inset
        let height = wanted >= all ? all : bottoms.min { abs($0 - wanted) < abs($1 - wanted) } ?? all
        return CGSize(width: max((right - left + 2 * inset).rounded(.up), minimum.width),
                      height: max((height + 2 * inset).rounded(.up), minimum.height))
    }

    /// `bounds` grown to show the item at `index` — an orb just docked, which a dock snapped to fewer
    /// rows had hidden (the owner, 2026-10-27: "I just dropped a window in there and it didn't
    /// display because the dock window shrunk") — when its row is one of the first `rows`; else
    /// `bounds`, and the dock scrolls to it.
    public static func showing(_ index: Int, of sizes: [CGSize], within bounds: CGSize, inset: CGFloat,
                               gapAfterFirst: CGFloat = 0, rows: Int) -> CGSize {
        let (frames, bottoms) = layout(of: sizes, width: max(bounds.width - 2 * inset, 0), gapAfterFirst: gapAfterFirst)
        guard frames.indices.contains(index),
              let row = bottoms.firstIndex(where: { $0 >= frames[index].maxY - 0.5 }), row < rows else { return bounds }
        let shown = snapped(sizes, within: bounds, inset: inset, gapAfterFirst: gapAfterFirst).height - 2 * inset
        guard bottoms[row] > shown + 0.5 else { return bounds }
        return CGSize(width: bounds.width, height: bottoms[row] + 2 * inset)
    }

    /// What `frames` take up, from the origin.
    public static func size(of frames: [CGRect]) -> CGSize {
        CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
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
