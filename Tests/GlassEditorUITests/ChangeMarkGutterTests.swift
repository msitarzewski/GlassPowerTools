#if canImport(AppKit) && os(macOS)

import Testing
import Foundation
import AppKit
@testable import GlassEditorUI
import GlassEditorCore

/// The marks beside changed lines (2026-10-23), drawn by the real gutter in a window that is never
/// shown, and read back pixel by pixel.
@Suite("Gutter change marks")
@MainActor
struct ChangeMarkGutterTests {

    @Test("a changed line gets a bar and a removal a wedge, each beside its own line",
          arguments: [GlassTextView.TextSystem.textKit1, .textKit2])
    func marksAreDrawnBesideTheirLines(_ system: GlassTextView.TextSystem) async throws {
        let model = GlassEditorModel(snapshot: DocumentLoader.make(content: "one\ntwo\nthree\nfour\nfive\n",
                                                                  origin: .ephemeral(id: UUID())),
                                     builtInHighlighting: false)
        let engine = GlassEditorAppKitEngine(model: model, textSystem: system)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = engine.containerView
        engine.containerView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        engine.containerView.layoutSubtreeIfNeeded()
        let gutter = try #require(engine.gutter)
        gutter.displayIfNeeded()

        let labels = GlassLineNumberGutter.labels(for: engine.textView, model: model, verticalRange: nil)
        let offset = gutter.verticalOffset(textView: engine.textView)
        func middle(ofLine line: Int) throws -> CGFloat {
            try #require(labels.first { $0.number == line + 1 }).frame.midY - offset
        }
        func top(ofLine line: Int) throws -> CGFloat {
            try #require(labels.first { $0.number == line + 1 }).frame.minY - offset
        }
        let barX = gutter.bounds.width - EditorMetrics.changeMarkTrailingInset - EditorMetrics.changeMarkWidth / 2

        let before = try pixels(of: gutter)
        #expect(before.color(x: barX, y: try middle(ofLine: 1)).alphaComponent < 0.05, "nothing marked yet")

        model.lineChanges = [
            LineChange(kind: .modified, lines: 1..<2, baseLines: 1..<2),
            LineChange(kind: .deleted, lines: 3..<3, baseLines: 3..<4),
        ]
        // A layer-backed view (TextKit 2 makes the window's views so) keeps the request on its
        // layer, and its own `needsDisplay` reads false.
        var asked = false
        for _ in 0..<40 {
            await Task.yield()
            if gutter.needsDisplay || gutter.layer?.needsDisplay() == true { asked = true; break }
        }
        #expect(asked, "a change to the marks asks the gutter to draw again")

        let after = try pixels(of: gutter)
        let changed = after.color(x: barX, y: try middle(ofLine: 1))
        // The theme's amber, as near as a bitmap read back through its colour space says: the hue,
        // not the exact components, which the round trip moves by a few hundredths.
        #expect(changed.alphaComponent > 0.9)
        #expect(changed.redComponent > changed.greenComponent && changed.greenComponent > changed.blueComponent
                && changed.redComponent - changed.blueComponent > 0.2, "\(changed)")
        #expect(after.color(x: barX, y: try middle(ofLine: 0)).alphaComponent < 0.05, "an unchanged line has no bar")
        #expect(after.color(x: barX, y: try middle(ofLine: 2)).alphaComponent < 0.05)

        let wedge = after.color(x: barX, y: try top(ofLine: 3))
        #expect(wedge.alphaComponent > 0.5)
        #expect(wedge.redComponent > wedge.greenComponent + 0.25, "a removal is the theme's red")
        #expect(after.color(x: barX, y: try middle(ofLine: 3)).alphaComponent < 0.05, "the wedge is at the line's top only")
        // The numbers keep their place: the bar is beside them, not over them.
        #expect(barX > gutter.bounds.width - EditorMetrics.gutterNumberTrailingGap)
        window.close()
    }

    /// The gutter as it draws, in points from its top-left corner.
    private struct Pixels {
        let rep: NSBitmapImageRep
        let scale: CGFloat

        func color(x: CGFloat, y: CGFloat) -> NSColor {
            let color = rep.colorAt(x: Int(x * scale), y: Int(y * scale)) ?? .clear
            return color.usingColorSpace(.sRGB) ?? color
        }
    }

    private func pixels(of view: NSView) throws -> Pixels {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return Pixels(rep: rep, scale: CGFloat(rep.pixelsWide) / view.bounds.width)
    }
}

#endif
