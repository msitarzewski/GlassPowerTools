//
//  GlassEditorWindowPicture.swift
//  Glass Power Tools — GlassEditor
//
//  An editor window as Show All Windows, the orb dock and the switcher picture it: the whole
//  window — its title bar and toolbar, the file list beside the text when the list is open, the
//  tabs and the file in front (the owner, 2026-10-29: "stretch wide to fill the card, and show the
//  sidebar too if open!"). The text alone, which came first, was a narrow strip in a wide card.
//  The Mac, iPad and iPhone; the headset's window shrinks into its own orb, so there the picture is
//  the file in front (`GlassEditorModel.previewImage`).
//
//  The window's frame view on a Mac, not its content view: the content runs under the toolbar,
//  which the frame draws, so the content alone left a blank band across the top. The sidebar's
//  glass is the system's own and is not in the picture; its list is drawn in on top, where it is,
//  and its Filter field, whose glass draws as solid white, as a faint capsule with its own words.
//

import CoreGraphics
import SwiftUI
import GlassEditorUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension GlassEditorWorkspace {
    /// The window as it is, at most `maxPixelWidth` wide. Given as last drawn and drawn again just
    /// after, outside the asker's update, as a terminal's picture is (`GlassEditorModel.previewImage`).
    /// Before the window has been drawn, or with none, the file in front alone.
    public func previewImage(maxPixelWidth: Int = 1200) -> CGImage? {
        if pictureWindow != nil, !pictureAsked {
            pictureAsked = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                pictureAsked = false
                if let picture = drawWindowPicture(maxPixelWidth: maxPixelWidth) { rememberedPicture = picture }
            }
        }
        return rememberedPicture ?? selectedDocument?.model.previewImage(maxPixelWidth: maxPixelWidth)
    }

    #if os(macOS)
    private func drawWindowPicture(maxPixelWidth: Int) -> CGImage? {
        guard let window = pictureWindow as? NSWindow,
              let view = window.contentView?.superview ?? window.contentView,
              view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let scale = min(window.backingScaleFactor, CGFloat(max(1, maxPixelWidth)) / view.bounds.width)
        guard let whole = Self.drawing(of: view, in: view.bounds, scale: scale),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let picture = CGContext(data: nil, width: whole.width, height: whole.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        picture.draw(whole, in: CGRect(x: 0, y: 0, width: whole.width, height: whole.height))

        /// Where `rect` of `part` is in the picture, in its pixels.
        func place(of part: NSView, _ rect: NSRect) -> CGRect {
            var place = part.convert(rect, to: view)
            if view.isFlipped { place.origin.y = view.bounds.height - place.maxY }
            return CGRect(x: place.minX * scale, y: place.minY * scale, width: place.width * scale, height: place.height * scale)
        }
        /// `part` drawn again where it is, as it draws itself.
        func redraw(_ part: NSView) {
            let visible = part.visibleRect
            guard !part.isHiddenOrHasHiddenAncestor, visible.width > 0, visible.height > 0,
                  let drawn = Self.drawing(of: part, in: visible, scale: scale) else { return }
            picture.draw(drawn, in: place(of: part, visible))
        }

        // The sidebar's list, drawn again where it is. macOS 26 holds a sidebar inside its glass, and
        // a drawing of the window leaves out what the glass holds: the card's file list was empty
        // (the owner, 2026-10-29). The list drawn by itself draws its rows.
        for list in Self.held(NSTableView.self, in: view) { redraw(list) }
        // The sidebar's Filter field, whose glass is drawn as solid white ("The search bar is
        // bright"): a faint capsule in its place, as the glass reads, and its magnifier and words on
        // it, which draw themselves.
        for field in Self.held(NSSearchField.self, in: view) where !field.isHiddenOrHasHiddenAncestor {
            let capsule = place(of: field, field.bounds)
            let dark = field.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            picture.clear(capsule)
            picture.setFillColor(CGColor(gray: dark ? 1 : 0, alpha: dark ? 0.1 : 0.06))
            picture.addPath(CGPath(roundedRect: capsule, cornerWidth: capsule.height / 2,
                                   cornerHeight: capsule.height / 2, transform: nil))
            picture.fillPath()
            for part in Self.descendants(of: field) where part is NSButton || part is NSTextView
                || String(describing: type(of: part)).contains("Label") {
                redraw(part)
            }
        }
        return picture.makeImage()
    }

    /// `rect` of `view` as it draws itself, `scale` pixels to a point.
    private static func drawing(of view: NSView, in rect: NSRect, scale: CGFloat) -> CGImage? {
        guard let drawn = NSBitmapImageRep(bitmapDataPlanes: nil,
                                           pixelsWide: max(1, Int(rect.width * scale)),
                                           pixelsHigh: max(1, Int(rect.height * scale)),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        drawn.size = rect.size
        view.cacheDisplay(in: rect, to: drawn)
        return drawn.cgImage
    }

    /// The views of a kind inside the window's glass: the outermost of them, not those within.
    private static func held<Kind: NSView>(_ kind: Kind.Type, in view: NSView, insideGlass: Bool = false) -> [Kind] {
        let inGlass = insideGlass || view is NSGlassEffectView
        if inGlass, let found = view as? Kind { return [found] }
        return view.subviews.flatMap { held(kind, in: $0, insideGlass: inGlass) }
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
    #elseif canImport(UIKit)
    private func drawWindowPicture(maxPixelWidth: Int) -> CGImage? {
        guard let window = pictureWindow as? UIWindow, window.bounds.width > 0, window.bounds.height > 0 else { return nil }
        let scale = min(window.traitCollection.displayScale, CGFloat(max(1, maxPixelWidth)) / window.bounds.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: window.bounds.width * scale, height: window.bounds.height * scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if !window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: false) {
                context.cgContext.scaleBy(x: scale, y: scale)
                window.layer.render(in: context.cgContext)
            }
        }.cgImage
    }
    #endif
}

/// Tells a workspace which window it is in, and that it has left it. Draws nothing, takes no input.
struct GlassEditorPictureWindowReader {
    let workspace: GlassEditorWorkspace
}

#if os(macOS)
extension GlassEditorPictureWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView(frame: .zero)
        view.workspace = workspace
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) { view.workspace = workspace }

    final class ReaderView: NSView {
        weak var workspace: GlassEditorWorkspace?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Gone from its window, the picture last drawn stays: the dock and the switcher show it.
            workspace?.pictureWindow = window
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#elseif canImport(UIKit)
extension GlassEditorPictureWindowReader: UIViewRepresentable {
    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.workspace = workspace
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) { view.workspace = workspace }

    final class ReaderView: UIView {
        weak var workspace: GlassEditorWorkspace?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            workspace?.pictureWindow = window
        }
    }
}
#endif
