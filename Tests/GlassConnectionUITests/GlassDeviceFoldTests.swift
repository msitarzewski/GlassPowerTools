import CoreGraphics
import Testing
@testable import GlassConnectionUI

/// Where an iPhone Duo's fold crosses a view, from the system's division regions. The frames are
/// the iOS 27.1 simulator's, measured on 2026-10-21 (inner display, partly open).
@Suite("The iPhone Duo's fold")
struct GlassDeviceFoldTests {
    private let laptop = CGSize(width: 669, height: 951)
    private let book = CGSize(width: 951, height: 669)

    @Test("stood like a laptop, the fold runs across the window: a top half and a bottom half")
    func laptopPose() throws {
        let fold = try #require(GlassDeviceFold.from(regions: [CGRect(x: 0, y: 456, width: 669, height: 40)],
                                                     active: [true], in: laptop))
        #expect(fold.isAcross)
        #expect(fold.frame.minY == 456 && fold.frame.maxY == 496)
    }

    @Test("held like a book, it runs down the middle")
    func bookPose() throws {
        let fold = try #require(GlassDeviceFold.from(regions: [CGRect(x: 456, y: 0, width: 40, height: 669)],
                                                     active: [true], in: book))
        #expect(!fold.isAcross)
    }

    @Test("flat, the region is there but inactive: no fold")
    func flat() {
        #expect(GlassDeviceFold.from(regions: [CGRect(x: 0, y: 456, width: 669, height: 40)],
                                     active: [false], in: laptop) == nil)
        #expect(GlassDeviceFold.from(regions: [], active: [], in: laptop) == nil, "no Duo")
    }

    @Test("partly open by the hinge, the fold counts before its region says it is active")
    func hingeFirst() throws {
        let region = CGRect(x: 0, y: 456, width: 669, height: 40)
        #expect(GlassDeviceFold.from(regions: [region], active: [false], partlyOpen: false, in: laptop) == nil)
        let fold = try #require(GlassDeviceFold.from(regions: [region], active: [false], partlyOpen: true, in: laptop))
        #expect(fold.isAcross)
        // A flat phone's region, with no width, is never a fold.
        #expect(GlassDeviceFold.from(regions: [CGRect(x: 0, y: 476, width: 669, height: 0)], active: [false],
                                     partlyOpen: true, in: laptop) == nil)
    }

    @Test("held like a book with two pages, the fold crosses the window but neither page")
    func pages() throws {
        // Read in the window, the system's column to its right (867 × 635, 2026-10-31).
        let fold = try #require(GlassDeviceFold.from(regions: [CGRect(x: 456, y: 0, width: 40, height: 635)],
                                                     active: [true], in: CGSize(width: 867, height: 635)))
        #expect(fold.crosses(CGRect(x: 0, y: 0, width: 867, height: 635)), "the window")
        #expect(!fold.crosses(CGRect(x: 0, y: 0, width: 456, height: 635)), "the left page")
        #expect(!fold.crosses(CGRect(x: 496, y: 0, width: 371, height: 635)), "the right page")
        let laptop = try #require(GlassDeviceFold.from(regions: [CGRect(x: 0, y: 456, width: 669, height: 40)],
                                                       active: [true], in: laptop))
        #expect(laptop.crosses(CGRect(x: 0, y: 0, width: 669, height: 951)))
        #expect(!laptop.crosses(CGRect(x: 0, y: 0, width: 669, height: 456)), "above the fold")
    }

    @Test("a view the fold doesn't cross has none: one above it, or a narrow column beside it")
    func notCrossing() {
        // The terminal above the fold: in its coordinates the fold lies past its bottom edge.
        #expect(GlassDeviceFold.from(regions: [CGRect(x: 0, y: 456, width: 669, height: 40)],
                                     active: [true], in: CGSize(width: 669, height: 456)) == nil)
        // A sliver at the edge of a narrow window in Split View.
        #expect(GlassDeviceFold.from(regions: [CGRect(x: 300, y: 0, width: 20, height: 669)],
                                     active: [true], in: CGSize(width: 320, height: 669)) == nil)
    }
}
