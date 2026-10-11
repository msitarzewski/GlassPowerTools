//
//  GlassEqualWidthRow.swift
//  Glass Power Tools — GlassConnectionUI
//
//  Equal tiles in a row, for an overview's figures. Moved here from the library's overview
//  (`GlassLibraryOverview`, 6d132e9) when the database's server overview took the same tiles
//  (W32, 2026-10-10; the owner: "let's keep all tiles and shapes aligned").
//

import SwiftUI

/// Views side by side at one shared width and one shared height, filling the width they are
/// given. Asked for its ideal size it needs its widest view's width for each, so a `ViewThatFits`
/// chooses it only where every view fits whole: equal shares of the width otherwise squeezed the
/// longest label ("Collections") onto two lines and left its tile taller than the rest.
///
/// Shared by Your Library's overview and the database's server overview, so the two windows' tiles
/// are the same shape.
public struct GlassEqualWidthRow: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? widest * CGFloat(subviews.count) + gaps
        return CGSize(width: width, height: rowHeight(width: width, gaps: gaps, subviews: subviews))
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let column = max(0, (bounds.width - gaps) / CGFloat(subviews.count))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (column + spacing), y: bounds.minY),
                          proposal: ProposedViewSize(width: column, height: bounds.height))
        }
    }

    private func rowHeight(width: CGFloat, gaps: CGFloat, subviews: Subviews) -> CGFloat {
        let column = max(0, (width - gaps) / CGFloat(subviews.count))
        return subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
    }
}
