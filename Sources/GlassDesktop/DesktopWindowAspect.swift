//
//  DesktopWindowAspect.swift
//  Glass Power Tools — GlassDesktop
//
//  W38 (owner, 2026-10-11, on the Vision Pro with a Mac's two displays each in a window of its own):
//  "we need a way to lock the dimensions to the actual screen ratio". A desktop window resizes only
//  in the shape of the remote display it shows, so the picture fills it without bars.
//
//  **How each platform does it.**
//  - **Vision Pro**: SwiftUI has no aspect-ratio lock for a window. `.windowResizability(.contentSize)`
//    with content that keeps an `.aspectRatio` bounds the window by the content's minimum and maximum
//    sizes, each axis on its own, and does not hold a ratio (Apple's `WindowResizability` documentation;
//    Apple Developer Forums thread 746154, where the accepted answer names the UIKit route). UIKit's
//    `UIWindowScene.requestGeometryUpdate(.Vision(size:resizingRestrictions:))` does:
//    `UIWindowSceneResizingRestrictionsUniform` is "User resizes are restricted to the current aspect
//    ratio" (visionOS 27.2 SDK, `UIWindowSceneGeometry.h`), the call Apple's Happy Beam sample makes.
//    So the window is first given the display's shape at its current width, then held to it;
//    `.freeform` lets it go again.
//  - **Mac**: `NSWindow.contentAspectRatio`, which holds the content view to integral multiples of a
//    ratio as the person resizes it; setting `contentResizeIncrements` to 1 × 1 clears it (measured on
//    macOS 27.2: the ratio reads back 0 × 0 after). The
//    window's own chrome inside the content view (the status bar) is measured, not assumed, and the
//    ratio given is the content view's, so the picture's part keeps the display's shape.
//  - **iPad and iPhone**: no restriction exists for a scene's shape there; nothing is done.
//
//  **Which shape.** The picture the window shows (`DesktopSessionModel.pictureAspect`): its display,
//  or the whole desktop. Updated when the display shown, the host's layout, Keep Display Proportions
//  or Match Window Size changes. While Match Window Size makes the remote desktop take the window's
//  size — RDP, or a VNC server that resizes — the window is left free: the desktop follows the window,
//  so there are no bars to avoid, and holding the window to the desktop's shape would chase its own
//  tail. A Mac never resizes its displays to a window, so a Mac's windows are always held.
//

import CoreGraphics
import Foundation
import SwiftUI
import GlassConnectionUI
#if os(macOS)
import AppKit
#elseif os(visionOS)
import UIKit
import OSLog
import GlassShell
#endif

/// The window size that gives the picture a shape, kept to rules a test can read.
enum DesktopWindowAspect {
    /// What a Vision Pro desktop window has around its picture: the remote screen sits
    /// `spatialNestedCanvasInset` (34 points) inside the window's edge on every side (W28), so the
    /// window is 68 points wider and taller than its picture.
    static var spatialChrome: CGSize {
        CGSize(width: GlassWindowShape.spatialNestedCanvasInset * 2, height: GlassWindowShape.spatialNestedCanvasInset * 2)
    }

    /// The smallest a Vision Pro desktop window is (`DesktopSessionView`'s frame).
    static let spatialMinimum = CGSize(width: 800, height: 440)

    /// Two shapes a person would not tell apart.
    static func sameAspect(_ a: Double, _ b: Double) -> Bool { abs(a / b - 1) < 0.005 }

    /// The window size whose picture — the window less `chrome` — has `aspect` (width over height):
    /// a landscape picture keeps the window's width and takes its height from it, a portrait one
    /// keeps the height. Grown, keeping the shape, where that would fall below `minimum`.
    static func windowSize(current: CGSize, aspect: Double, chrome: CGSize, minimum: CGSize) -> CGSize {
        guard aspect.isFinite, aspect > 0, current.width.isFinite, current.height.isFinite else { return current }
        let chromeWidth = max(0, chrome.width), chromeHeight = max(0, chrome.height)
        var picture: CGSize
        if aspect >= 1 {
            let width = max(1, current.width - chromeWidth)
            picture = CGSize(width: width, height: width / aspect)
        } else {
            let height = max(1, current.height - chromeHeight)
            picture = CGSize(width: height * aspect, height: height)
        }
        // Below the minimum on either side: grow both, keeping the shape.
        let grow = max(1, (minimum.width - chromeWidth) / picture.width, (minimum.height - chromeHeight) / picture.height)
        picture = CGSize(width: picture.width * grow, height: picture.height * grow)
        return CGSize(width: (picture.width + chromeWidth).rounded(), height: (picture.height + chromeHeight).rounded())
    }
}

#if os(visionOS)
/// Holds a Vision Pro window to its picture's shape (`DesktopWindowAspect`). A plain view in the
/// window's background: it finds its scene once it is in a window and asks on the next turn of the
/// main queue, never inside SwiftUI's update (rule 64).
struct DesktopWindowAspectLock: UIViewRepresentable {
    /// Width over height of the picture; nil lets the window be any shape.
    let aspect: Double?

    func makeUIView(context: Context) -> LockView { LockView() }
    func updateUIView(_ view: LockView, context: Context) {
        view.aspect = aspect
        view.paused = context.environment.glassSessionOrb.map { !$0.isWindow } ?? false
    }

    final class LockView: UIView {
        private static let logger = Logger(subsystem: "app.glassdt", category: "window-aspect")
        var aspect: Double? {
            didSet { if aspect != oldValue { schedule() } }
        }
        /// While the window is its orb, or growing back from it: the orb frees the window to take
        /// the orb's size, and its shape is held again once the window is back at its own — it
        /// stayed free after a round trip (2026-10-15).
        var paused = false {
            didSet {
                guard paused != oldValue, !paused else { return }
                asked = nil
                schedule()
            }
        }
        /// What was last asked of the scene: a shape, or `.some(nil)` for none.
        private var asked: Double??

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            asked = nil
            schedule()
        }

        private func schedule() {
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            guard !paused, let window, let scene = window.windowScene else { return }
            switch (aspect, asked) {
            case (nil, .some(.none)):
                return
            case (let wanted?, .some(.some(let previous))) where DesktopWindowAspect.sameAspect(wanted, previous):
                return
            default:
                break
            }
            asked = .some(aspect)
            guard let aspect else {
                scene.requestGeometryUpdate(.Vision(resizingRestrictions: .freeform)) { error in
                    Self.logger.error("event=aspect-release error=\(error.localizedDescription, privacy: .public)")
                }
                return
            }
            let size = DesktopWindowAspect.windowSize(current: window.bounds.size, aspect: aspect,
                                                      chrome: DesktopWindowAspect.spatialChrome,
                                                      minimum: DesktopWindowAspect.spatialMinimum)
            Self.logger.notice("event=aspect-lock aspect=\(aspect) width=\(size.width) height=\(size.height)")
            // The shape first, free to take it; then held to it once it has it. Uniform restricts the
            // person's resizing to the ratio the window has when it is set (`UIWindowSceneGeometry.h`),
            // so it is set only after the new size is in place — never against the old shape.
            scene.requestGeometryUpdate(.Vision(size: size, resizingRestrictions: .freeform)) { error in
                Self.logger.error("event=aspect-lock error=\(error.localizedDescription, privacy: .public)")
            }
            hold(aspect, attempt: 0)
        }

        /// Sets uniform resizing once the window has the shape asked for: looked at every tenth of
        /// a second for a second, then set whatever the window's shape, logging what visionOS made of it.
        private func hold(_ aspect: Double, attempt: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, let scene = window?.windowScene, case .some(.some(let wanted)) = asked,
                      DesktopWindowAspect.sameAspect(wanted, aspect) else { return }
                let bounds = scene.effectiveGeometry.coordinateSpace.bounds.size
                let chrome = DesktopWindowAspect.spatialChrome
                let picture = (bounds.width - chrome.width) / max(1, bounds.height - chrome.height)
                guard DesktopWindowAspect.sameAspect(picture, aspect) || attempt >= 10 else {
                    hold(aspect, attempt: attempt + 1)
                    return
                }
                scene.requestGeometryUpdate(.Vision(resizingRestrictions: .uniform)) { error in
                    Self.logger.error("event=aspect-hold error=\(error.localizedDescription, privacy: .public)")
                }
                // What visionOS made of it, for the log: the scene's size and restriction a moment later.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let geometry = scene.effectiveGeometry
                    Self.logger.notice("event=aspect-geometry uniform=\(geometry.resizingRestrictions == .uniform) width=\(geometry.coordinateSpace.bounds.width) height=\(geometry.coordinateSpace.bounds.height) waited=\(attempt)")
                }
            }
        }
    }
}
#elseif os(macOS)
/// Holds a Mac window's content to its picture's shape (`DesktopWindowAspect`): `contentAspectRatio`,
/// with the chrome inside the content measured against the picture's area.
struct DesktopWindowAspectLock: NSViewRepresentable {
    /// Width over height of the picture; nil lets the window be any shape.
    let aspect: Double?
    /// The picture's area now, in points.
    let canvas: CGSize

    func makeNSView(context: Context) -> LockView { LockView() }
    func updateNSView(_ view: LockView, context: Context) { view.update(aspect: aspect, canvas: canvas) }

    final class LockView: NSView {
        private var aspect: Double?
        private var canvas = CGSize.zero
        private var held: CGSize?

        func update(aspect: Double?, canvas: CGSize) {
            let changed = aspect != self.aspect || canvas != self.canvas
            self.aspect = aspect
            self.canvas = canvas
            if changed { DispatchQueue.main.async { [weak self] in self?.apply() } }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            held = nil
            NotificationCenter.default.removeObserver(self, name: NSWindow.didEndLiveResizeNotification, object: nil)
            if let window {
                // The ratio holds the whole content while the chrome in it stays the same height, so
                // the picture's shape drifts a little over a long drag: set it right once it ends.
                NotificationCenter.default.addObserver(self, selector: #selector(resizeEnded(_:)),
                                                       name: NSWindow.didEndLiveResizeNotification, object: window)
            }
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        @objc private func resizeEnded(_ notification: Notification) {
            held = nil
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func apply() {
            // A full-screen window takes the screen's shape, whatever is asked.
            guard let window, let content = window.contentView, !window.styleMask.contains(.fullScreen) else { return }
            guard let aspect, canvas.width > 1, canvas.height > 1, !window.inLiveResize else {
                if aspect == nil, held != nil {
                    // Clears the ratio (`contentResizeIncrements` takes precedence once set to 1 × 1).
                    window.contentResizeIncrements = NSSize(width: 1, height: 1)
                    held = nil
                }
                return
            }
            let current = content.frame.size
            let chrome = CGSize(width: max(0, current.width - canvas.width), height: max(0, current.height - canvas.height))
            let target = DesktopWindowAspect.windowSize(current: current, aspect: aspect, chrome: chrome,
                                                        minimum: DesktopWindowSizing.floor)
            if held != target {
                window.contentAspectRatio = NSSize(width: target.width, height: target.height)
                held = target
            }
            guard abs(target.width - current.width) > 1 || abs(target.height - current.height) > 1 else { return }
            // Keep the top-left where it was.
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: target))
            frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
#else
/// iPad and iPhone: a scene's shape cannot be held; nothing to do.
struct DesktopWindowAspectLock: View {
    let aspect: Double?
    var body: some View { Color.clear.frame(width: 0, height: 0) }
}
#endif
