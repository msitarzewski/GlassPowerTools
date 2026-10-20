import CoreGraphics
import Testing
@testable import GlassDatabase

/// The results grid's rows, header and row numbers follow its text size (2026-10-19). At the
/// default 13 points they are what they always were; past it, a row holds a line of its text, where
/// a fixed 30 points clipped a 32-point setting and the system's largest text size.
@Suite("The results grid's sizes follow its text")
struct DatabaseGridMetricsTests {
    @Test("at the default 13 points: rows of 30, a header of 36 and row numbers 50 wide, as before")
    func defaultSize() {
        #expect(DatabaseGridMetrics.rowHeight(13) == 30)
        #expect(DatabaseGridMetrics.headerHeight(13) == 36)
        #expect(DatabaseGridMetrics.rowNumberWidth(13) == 50)
    }

    @Test("past it, a row holds a line of its text and its padding", arguments: [16, 24, 32, 41, 72] as [CGFloat])
    func larger(size: CGFloat) {
        #expect(DatabaseGridMetrics.rowHeight(size) >= size * 1.2 + 12)
        #expect(DatabaseGridMetrics.headerHeight(size) > DatabaseGridMetrics.rowHeight(size))
        // Four digits of the row numbers' font, a point smaller than the cells'.
        #expect(DatabaseGridMetrics.rowNumberWidth(size) >= 4 * (size - 1) * 0.6)
    }
}
