//
//  GlassTitleBandTests.swift
//  Glass Power Tools — GlassLayersTests
//
//  The title band keeps its material whatever the frost (2026-09-28).
//
//  It followed `frost`: at 0.67 a third of the window behind showed through the terminal's title,
//  sharp, and at 0 the band vanished. The band names the machine; rule 50 says chrome that says
//  where you are does not become see-through. Frost and opacity are for the content below it.
//

#if os(macOS)
import AppKit
import Testing
@testable import GlassLayers

@Suite(.serialized) @MainActor
struct GlassTitleBandTests {
    private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test(arguments: [0.0, 0.67, 1.0])
    func theBandIsFullyFrostedAtAnyFrost(_ frost: Double) throws {
        let window = window()
        GlassWindowLayerPolicy.apply(window, state: GlassLayerState(opacity: 0.87, frost: frost, material: .ultraThin))
        let band = try #require(GlassWindowLayerPolicy.titlebarMaterial(in: window))
        #expect(band.alphaValue == 1)
        #expect(!band.isHidden)
    }
}
#endif
