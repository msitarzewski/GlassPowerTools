import Testing
import Foundation
import SwiftUI
@testable import GlassShell

/// The gallery's layout solver.
///
/// **These tests moved rather than being written.** They covered `MacTerminalOverviewGrid` in
/// `MacWorkspaceTests`, which is fenced to macOS — so the solver the session gallery now depends
/// on was proven on one platform and used on three. Same assertions, same numbers, run everywhere.
@Suite("How many cards fit, and how wide")
struct GlassGalleryLayoutTests {
    @Test func manualGridSizingClampsAndReflows() {
        let small = GlassGalleryLayout(count: 12, size: CGSize(width: 1200, height: 600), preferredWidth: 220)
        let large = GlassGalleryLayout(count: 12, size: CGSize(width: 1200, height: 600), preferredWidth: 600)
        #expect(small.columns > large.columns)
        #expect(small.cardWidth == 220)
        #expect(large.cardWidth == 600)
        let narrow = GlassGalleryLayout(count: 12, size: CGSize(width: 300, height: 600), preferredWidth: 600)
        #expect(narrow.columns == 1)
        #expect(narrow.cardWidth == 288)
    }

    @Test func responsiveOverviewGridFitsCardsAndAddsColumnsAsSpaceGrows() {
        let compact = GlassGalleryLayout(count: 6, size: CGSize(width: 480, height: 600))
        let wide = GlassGalleryLayout(count: 6, size: CGSize(width: 1200, height: 600))
        #expect(compact.columns >= 1)
        #expect(wide.columns > compact.columns)
        #expect(wide.cardWidth <= 520)
        #expect(CGFloat(wide.columns) * wide.cardWidth + CGFloat(wide.columns - 1) * 18 <= 1200)
        let empty = GlassGalleryLayout(count: 0, size: .zero)
        #expect(empty.columns == 1)
        #expect(empty.cardWidth > 0)
    }

}

/// The card contract the gallery and the solver share.
/// The degenerate sizes a real screen actually hands a `GeometryReader`.
@Suite("A layout for a size that is not there yet")
struct GlassGalleryLayoutDegenerateTests {
    /// Reported as a crash, not a defect in a number. A `GridItem` whose maximum is under
    /// SwiftUI's default minimum of 10 traps inside `LazyVGrid`, and a sheet's first layout pass
    /// supplies exactly the size that produced one.
    @Test func noSizeStillDescribesACardAGridWillAccept() {
        for size in [CGSize.zero,
                     CGSize(width: 1, height: 1),
                     CGSize(width: 12, height: 400),
                     CGSize(width: 0, height: 800)] {
            let layout = GlassGalleryLayout(count: 3, size: size)
            #expect(layout.columns >= 1, "\(size)")
            #expect(layout.cardWidth >= GlassGalleryLayout.minimumCardWidth, "\(size)")
        }
    }

    @Test func aPreferredWidthCannotDriveTheCardBelowTheMinimumEither() {
        let layout = GlassGalleryLayout(count: 3, size: .zero, preferredWidth: 220)
        #expect(layout.cardWidth >= GlassGalleryLayout.minimumCardWidth)
    }
}
