import SwiftUI
import Testing
@testable import GlassConnectionUI

/// The terminal's and the results grid's own sizes, at the system's text size (2026-10-19).
@Suite("A size a person picks, at the system's text size")
struct GlassSystemTextSizeTests {
    @Test("at the standard text size, the size as picked")
    func standard() {
        #expect(GlassSystemTextSize.scaled(14, for: .large, within: 10...72) == 14)
        #expect(GlassSystemTextSize.scaled(13, for: .large, within: 10...72) == 13)
    }

    #if canImport(UIKit)
    @Test("larger and smaller with the system's size, in whole points within its range")
    func follows() {
        let largest = GlassSystemTextSize.scaled(14, for: .accessibility5, within: 10...72)
        #expect(largest >= 28 && largest == largest.rounded())
        #expect(GlassSystemTextSize.scaled(14, for: .xSmall, within: 10...72) < 14)
        #expect(GlassSystemTextSize.scaled(28, for: .accessibility5, within: 10...72) == 72)
        #expect(GlassSystemTextSize.scaled(10, for: .xSmall, within: 10...72) == 10)
    }
    #else
    @Test("a Mac has no system text size: the size as picked")
    func mac() {
        #expect(GlassSystemTextSize.scaled(14, for: .accessibility5, within: 10...72) == 14)
    }
    #endif
}
