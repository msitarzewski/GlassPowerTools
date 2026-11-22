//
//  GlassEditorWindowSizeTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  The owner, 2026-11-22: "I can't resize a text editor created with shift command E". A new Mac editor window opened at
//  its minimum, 820 × 520, and could only grow; the size it was left at was never kept (B-F45). A new window opens at the
//  size the last one was left at, else 1100 × 720, and can be made much smaller.
//

import CoreGraphics
import Foundation
import Testing
@testable import GlassEditor

@MainActor
@Suite("An editor window's size")
struct GlassEditorWindowSizeTests {
    private func defaults() -> UserDefaults {
        UserDefaults.forTest(suiteName: "editor.window-size.\(UUID().uuidString)")!
    }

    private let screen = CGSize(width: 1512, height: 920)

    @Test("with nothing kept, a window opens at 1100 × 720")
    func opensAtTheDefault() {
        let preferences = GlassEditorPreferences(defaults: defaults())
        #expect(preferences.windowSize == nil)
        #expect(GlassEditorWindowSize.opening(remembered: preferences.windowSize, screen: screen)
                == CGSize(width: 1100, height: 720))
    }

    @Test("the size a window is left at is the next one's, after a relaunch too")
    func theNextWindowOpensAtTheLastSize() {
        let store = defaults()
        GlassEditorPreferences(defaults: store).keepWindowSize(CGSize(width: 900.4, height: 610.6))
        let relaunched = GlassEditorPreferences(defaults: store)
        #expect(relaunched.windowSize == CGSize(width: 900, height: 611))
        #expect(GlassEditorWindowSize.opening(remembered: relaunched.windowSize, screen: screen)
                == CGSize(width: 900, height: 611))
    }

    @Test("a small window stays small: well under the old 820 × 520 floor")
    func aSmallWindowOpensSmall() {
        let small = CGSize(width: 520, height: 340)
        #expect(GlassEditorWindowSize.opening(remembered: small, screen: screen) == small)
    }

    @Test("never smaller than the minimum, never larger than the screen")
    func boundedByTheMinimumAndTheScreen() {
        let minimum = GlassEditorWindowSize.minimum
        #expect(GlassEditorWindowSize.opening(remembered: CGSize(width: 200, height: 150), screen: screen) == minimum)
        #expect(GlassEditorWindowSize.opening(remembered: CGSize(width: 3000, height: 2000), screen: screen) == screen)
        // A screen smaller than the minimum is not believed; the minimum wins.
        #expect(GlassEditorWindowSize.opening(remembered: nil, screen: CGSize(width: 300, height: 200))
                == CGSize(width: 1100, height: 720))
    }

    /// SwiftUI resized every new window to its content's minimum as it was ordered front (measured in the macOS VM).
    @Test("a window shrunk while it opens goes back to the frame it was made at; one that grew is left alone")
    func aShrinkWhileOpeningIsUndone() {
        let made = CGRect(x: 206, y: 116, width: 1100, height: 720)
        #expect(GlassEditorWindowSize.undoing(shrinkOf: made, to: CGRect(x: 206, y: 536, width: 480, height: 300))
                == made)
        #expect(GlassEditorWindowSize.undoing(shrinkOf: made, to: CGRect(x: 206, y: 116, width: 1100, height: 700))
                == made, "shorter only")
        #expect(GlassEditorWindowSize.undoing(shrinkOf: made, to: CGRect(x: 206, y: 116, width: 900, height: 720))
                == made, "narrower only")
        #expect(GlassEditorWindowSize.undoing(shrinkOf: made, to: made) == nil)
        #expect(GlassEditorWindowSize.undoing(shrinkOf: made, to: CGRect(x: 206, y: 16, width: 1200, height: 820)) == nil)
    }

    @Test("a damaged stored size is not a window")
    func damagedSizesAreIgnored() {
        for stored: Any in [[0.0, 600.0], [900.0], [900.0, 600.0, 1.0], ["900", "600"], [Double.infinity, 600.0],
                            [90_000.0, 600.0]] {
            let store = defaults()
            store.set(stored, forKey: GlassEditorPreferences.windowSizeDefaultsKey)
            #expect(GlassEditorPreferences(defaults: store).windowSize == nil, "\(stored)")
        }
        let preferences = GlassEditorPreferences(defaults: defaults())
        preferences.keepWindowSize(CGSize(width: 0, height: 600))
        preferences.keepWindowSize(CGSize(width: CGFloat.nan, height: 600))
        #expect(preferences.windowSize == nil)
    }
}
