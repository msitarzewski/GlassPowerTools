//
//  GlassAllWindowsLayout.swift
//  Glass Power Tools — GlassShell
//
//  How Show All Windows lays out its tiles, on every platform. Moved from the Mac's
//  `MacTerminalExpose.swift`, where it was `MacTerminalExposeLayout`, unchanged except for its
//  name, where it lives and what it makes public, so All Windows on iPhone, iPad and Vision Pro
//  lays out as the Mac does (the owner, 2026-10-14: "please mirror the Mac layout … The view
//  should adjust itself based on the number of sessions showing"). Its tests are the Mac's
//  (`MacTerminalExposeTests`), which reach it by its old name.
//

import CoreGraphics
import Foundation

/// Packs the groups onto the screen the way Mission Control does: every tile the same size, as
/// large as fits, groups flowing left to right in the order given, rows centred. Only when even
/// the smallest tiles cannot fit does it fall back to scrolling. Pure arithmetic, so it is tested
/// without a screen.
public struct GlassAllWindowsLayout: Equatable, Sendable {
    public struct Group: Equatable, Sendable {
        /// The group's box, with its title and tiles inside it.
        public let frame: CGRect
        public let titleFrame: CGRect
        public let tileFrames: [CGRect]
        /// Which row of groups it is in, counted from the top.
        public let row: Int
    }

    public private(set) var groups: [Group] = []
    /// The space the groups take: the size given, or taller when it scrolls.
    public private(set) var contentSize: CGSize = .zero
    public private(set) var scrolls = false
    public private(set) var tileSize: CGSize = .zero

    /// A tile has the in-window overview's proportions (`MacWorkspacePreview`, `GlassGalleryLayout`).
    public static let aspectRatio: CGFloat = 1.6
    public static let padding: CGFloat = 14
    public static let titleHeight: CGFloat = 30
    public static let tileSpacing: CGFloat = 14
    public static let groupSpacing: CGFloat = 26
    public static let minimumTileWidth: CGFloat = 160
    public static let maximumTileWidth: CGFloat = 600
    /// How wide a group leans: its columns are about √(tiles × bias). The widest tiles win.
    private static let biases: [Double] = [0.5, 1, 1.5, 2, 3, 4, 6, 9, 16]

    public init(tileCounts: [Int], in size: CGSize) {
        let counts = tileCounts.map { max(1, $0) }
        guard !counts.isEmpty, size.width > 0, size.height > 0,
              size.width.isFinite, size.height.isFinite else { return }
        var best: (width: CGFloat, columns: [Int])?
        for bias in Self.biases {
            let columns = counts.map { Self.columns(for: $0, bias: bias) }
            guard let width = Self.largestWidth(counts: counts, columns: columns, in: size) else { continue }
            if best.map({ width > $0.width + 0.5 }) ?? true { best = (width, columns) }
        }
        if let best {
            place(counts: counts, columns: best.columns, tileWidth: best.width, in: size, scrolls: false)
            return
        }
        // Too many for one screen: the smallest tiles, groups as wide as the screen allows, and
        // the whole arrangement scrolls.
        let usable = size.width - 2 * Self.padding
        let tileWidth = max(1, min(Self.minimumTileWidth, usable))
        let fitting = max(1, Int((usable + Self.tileSpacing) / (tileWidth + Self.tileSpacing)))
        place(counts: counts, columns: counts.map { min($0, fitting) }, tileWidth: tileWidth, in: size, scrolls: true)
    }

    public static func columns(for count: Int, bias: Double) -> Int {
        min(count, max(1, Int(ceil(sqrt(Double(count) * bias)))))
    }

    public static func groupSize(count: Int, columns: Int, tileWidth: CGFloat) -> CGSize {
        let rows = Int(ceil(Double(count) / Double(columns)))
        let tileHeight = tileWidth / aspectRatio
        return CGSize(width: 2 * padding + CGFloat(columns) * tileWidth + CGFloat(columns - 1) * tileSpacing,
                      height: 2 * padding + titleHeight + CGFloat(rows) * tileHeight + CGFloat(rows - 1) * tileSpacing)
    }

    /// Groups in rows, in order: a group starts a new row when it would not fit beside the last.
    private static func rows(_ sizes: [CGSize], width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var used: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if let last = rows.indices.last, used + groupSpacing + size.width <= width {
                rows[last].append(index)
                used += groupSpacing + size.width
            } else {
                rows.append([index])
                used = size.width
            }
        }
        return rows
    }

    private static func height(of rows: [[Int]], _ sizes: [CGSize]) -> CGFloat {
        rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }.reduce(0, +)
            + CGFloat(max(0, rows.count - 1)) * groupSpacing
    }

    private static func fits(counts: [Int], columns: [Int], tileWidth: CGFloat, in size: CGSize) -> Bool {
        let sizes = zip(counts, columns).map { groupSize(count: $0, columns: $1, tileWidth: tileWidth) }
        guard sizes.allSatisfy({ $0.width <= size.width }) else { return false }
        return height(of: rows(sizes, width: size.width), sizes) <= size.height
    }

    /// The widest tile, between the minimum and the maximum, at which these columns fit.
    private static func largestWidth(counts: [Int], columns: [Int], in size: CGSize) -> CGFloat? {
        guard fits(counts: counts, columns: columns, tileWidth: minimumTileWidth, in: size) else { return nil }
        if fits(counts: counts, columns: columns, tileWidth: maximumTileWidth, in: size) { return maximumTileWidth }
        var low = minimumTileWidth, high = maximumTileWidth
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if fits(counts: counts, columns: columns, tileWidth: middle, in: size) { low = middle } else { high = middle }
        }
        return low
    }

    private mutating func place(counts: [Int], columns: [Int], tileWidth: CGFloat, in size: CGSize, scrolls: Bool) {
        let tileHeight = tileWidth / Self.aspectRatio
        let sizes = zip(counts, columns).map { Self.groupSize(count: $0, columns: $1, tileWidth: tileWidth) }
        let rows = Self.rows(sizes, width: size.width)
        let total = Self.height(of: rows, sizes)
        var frames = [CGRect](repeating: .zero, count: counts.count)
        var rowOf = [Int](repeating: 0, count: counts.count)
        var y = scrolls ? 0 : max(0, (size.height - total) / 2)
        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = row.map { sizes[$0].width }.reduce(0, +) + CGFloat(row.count - 1) * Self.groupSpacing
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x = max(0, (size.width - rowWidth) / 2)
            for index in row {
                frames[index] = CGRect(x: x, y: y + (rowHeight - sizes[index].height) / 2,
                                       width: sizes[index].width, height: sizes[index].height)
                rowOf[index] = rowIndex
                x += sizes[index].width + Self.groupSpacing
            }
            y += rowHeight + Self.groupSpacing
        }
        groups = frames.indices.map { index in
            let frame = frames[index]
            let tiles = (0..<counts[index]).map { tile in
                CGRect(x: frame.minX + Self.padding + CGFloat(tile % columns[index]) * (tileWidth + Self.tileSpacing),
                       y: frame.minY + Self.padding + Self.titleHeight + CGFloat(tile / columns[index]) * (tileHeight + Self.tileSpacing),
                       width: tileWidth, height: tileHeight)
            }
            return Group(frame: frame,
                         titleFrame: CGRect(x: frame.minX + Self.padding, y: frame.minY + Self.padding,
                                            width: frame.width - 2 * Self.padding, height: Self.titleHeight - 8),
                         tileFrames: tiles, row: rowOf[index])
        }
        contentSize = CGSize(width: size.width, height: scrolls ? max(size.height, total) : size.height)
        self.scrolls = scrolls
        tileSize = CGSize(width: tileWidth, height: tileHeight)
    }
}
