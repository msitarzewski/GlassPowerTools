//
//  GlassWindowAspectLock.swift
//  Glass Power Tools — GlassShell
//
//  A window that resizes only in the shape of what it shows. First a remote desktop's (W38, the
//  owner, 2026-10-11, on the Vision Pro with a Mac's two displays each in a window of its own: "we
//  need a way to lock the dimensions to the actual screen ratio"), so the picture fills it without
//  bars; then a terminal's under Scale (D75, 2026-10-16), whose rows and columns stay while its text
//  follows the window — the owner: "Held to the grid's shape". Moved here from the desktop's
//  `DesktopWindowAspectLock` so both hold a window the same way.
//
//  **How each platform does it.**
//  - **Vision Pro**: SwiftUI has no aspect-ratio lock for a window. `.windowResizability(.contentSize)`
//    with content that keeps an `.aspectRatio` bounds the window by the content's minimum and maximum
//    sizes, each axis on its own, and does not hold a ratio (Apple's `WindowResizability` documentation;
//    Apple Developer Forums thread 746154, where the accepted answer names the UIKit route). UIKit's
//    `UIWindowScene.requestGeometryUpdate(.Vision(size:resizingRestrictions:))` does:
//    `UIWindowSceneResizingRestrictionsUniform` is "User resizes are restricted to the current aspect
//    ratio" (visionOS 27.2 SDK, `UIWindowSceneGeometry.h`), the call Apple's Happy Beam sample makes.
//    So the window is first given the shape at its current width, then held to it; `.freeform` lets
//    it go again.
//  - **Mac**: `NSWindow.contentAspectRatio`, which holds the content view to integral multiples of a
//    ratio as the person resizes it; setting `contentResizeIncrements` to 1 × 1 clears it (measured on
//    macOS 27.2: the ratio reads back 0 × 0 after). The window's own chrome inside the content view
//    (a status bar, a toolbar's band) is measured, not assumed, and the ratio given is the content
//    view's, so the part that matters keeps its shape.
//  - **iPad and iPhone**: no restriction exists for a scene's shape there (the iOS geometry
//    preferences carry only orientations, `UIWindowSceneGeometryPreferencesIOS.h`); nothing is done.
//

import CoreGraphics
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(visionOS)
import UIKit
import OSLog
#endif

/// The window size that gives what the window shows a shape, kept to rules a test can read.
public enum GlassWindowAspect {
    /// Two shapes a person would not tell apart.
    public static func sameAspect(_ a: Double, _ b: Double) -> Bool { abs(a / b - 1) < 0.005 }

    /// The window size whose shown part — the window less `chrome` — has `aspect` (width over
    /// height): a landscape part keeps the window's width and takes its height from it, a portrait
    /// one keeps the height. Grown, keeping the shape, where that would fall below `minimum`.
    public static func windowSize(current: CGSize, aspect: Double, chrome: CGSize, minimum: CGSize) -> CGSize {
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
/// Holds a Vision Pro window to a shape (`GlassWindowAspect`). A plain view in the window's
/// background: it finds its scene once it is in a window and asks on the next turn of the main
/// queue, never inside SwiftUI's update (rule 64).
public struct GlassWindowAspectLock: UIViewRepresentable {
    /// Width over height of the part that keeps a shape; nil lets the window be any shape.
    let aspect: Double?
    /// What the window has around that part.
    let chrome: Chrome
    /// The smallest the window is.
    let minimum: CGSize

    public enum Chrome: Equatable {
        /// The same all the way round, whatever the window's size (a desktop's inset, W28).
        case fixed(CGSize)
        /// Whatever the window has beyond `canvas`, the part's size now, measured as it is asked.
        case around(canvas: CGSize)
    }

    public init(aspect: Double?, chrome: CGSize, minimum: CGSize) {
        self.aspect = aspect
        self.chrome = .fixed(chrome)
        self.minimum = minimum
    }

    /// The window less `canvas` — the part that keeps the shape, as it is now — is its chrome.
    public init(aspect: Double?, canvas: CGSize, minimum: CGSize) {
        self.aspect = aspect
        self.chrome = .around(canvas: canvas)
        self.minimum = minimum
    }

    public func makeUIView(context: Context) -> LockView { LockView() }
    public func updateUIView(_ view: LockView, context: Context) {
        view.chrome = chrome
        view.minimum = minimum
        view.aspect = aspect
        view.paused = context.environment.glassSessionOrb.map { !$0.isWindow } ?? false
    }

    public final class LockView: UIView {
        private static let logger = Logger(subsystem: "com.glasspowertools", category: "window-aspect")
        var chrome = Chrome.fixed(.zero)
        var minimum = CGSize.zero
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
        /// The chrome the last shape was asked with, which the hold measures the window by.
        private var askedChrome = CGSize.zero

        public override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        public required init?(coder: NSCoder) { fatalError("not used") }

        public override func didMoveToWindow() {
            super.didMoveToWindow()
            asked = nil
            schedule()
        }

        private func schedule() {
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func chrome(in window: UIWindow) -> CGSize {
            switch chrome {
            case .fixed(let size):
                return size
            case .around(let canvas):
                return CGSize(width: max(0, window.bounds.width - canvas.width),
                              height: max(0, window.bounds.height - canvas.height))
            }
        }

        private func apply() {
            guard !paused, let window, let scene = window.windowScene else { return }
            switch (aspect, asked) {
            case (nil, .some(.none)):
                return
            case (let wanted?, .some(.some(let previous))) where GlassWindowAspect.sameAspect(wanted, previous):
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
            askedChrome = chrome(in: window)
            let size = GlassWindowAspect.windowSize(current: window.bounds.size, aspect: aspect,
                                                    chrome: askedChrome, minimum: minimum)
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
                      GlassWindowAspect.sameAspect(wanted, aspect) else { return }
                let bounds = scene.effectiveGeometry.coordinateSpace.bounds.size
                let picture = (bounds.width - askedChrome.width) / max(1, bounds.height - askedChrome.height)
                guard GlassWindowAspect.sameAspect(picture, aspect) || attempt >= 10 else {
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
/// Holds a Mac window's content to a shape (`GlassWindowAspect`): `contentAspectRatio`, with the
/// chrome inside the content measured against the part that keeps the shape.
public struct GlassWindowAspectLock: NSViewRepresentable {
    /// Width over height of the part that keeps a shape; nil lets the window be any shape.
    let aspect: Double?
    /// That part's size now, in points.
    let canvas: CGSize
    /// The smallest the window's content is.
    let minimum: CGSize

    public init(aspect: Double?, canvas: CGSize, minimum: CGSize) {
        self.aspect = aspect
        self.canvas = canvas
        self.minimum = minimum
    }

    public func makeNSView(context: Context) -> LockView { LockView() }
    public func updateNSView(_ view: LockView, context: Context) {
        view.update(aspect: aspect, canvas: canvas, minimum: minimum)
    }

    public final class LockView: NSView {
        private var aspect: Double?
        private var canvas = CGSize.zero
        private var minimum = CGSize.zero
        private var held: CGSize?
        private var applyScheduled = false

        func update(aspect: Double?, canvas: CGSize, minimum: CGSize) {
            let changed = aspect != self.aspect || canvas != self.canvas
            self.aspect = aspect
            self.canvas = canvas
            self.minimum = minimum
            if changed { schedule() }
        }

        /// One look per turn of the main queue: a second, queued beside the first, would measure the
        /// chrome against the part's size from before the first resized the window.
        private func schedule() {
            guard !applyScheduled else { return }
            applyScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.applyScheduled = false
                self?.apply()
            }
        }

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            held = nil
            NotificationCenter.default.removeObserver(self, name: NSWindow.didEndLiveResizeNotification, object: nil)
            if let window {
                // The ratio holds the whole content while the chrome in it stays the same height, so
                // the part's shape drifts a little over a long drag: set it right once it ends.
                NotificationCenter.default.addObserver(self, selector: #selector(resizeEnded(_:)),
                                                       name: NSWindow.didEndLiveResizeNotification, object: window)
            }
            schedule()
        }

        @objc private func resizeEnded(_ notification: Notification) {
            held = nil
            schedule()
        }

        public override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func apply() {
            // A full-screen window takes the screen's shape, whatever is asked.
            guard let window, let content = window.contentView, !window.styleMask.contains(.fullScreen) else { return }
            guard let aspect, canvas.width > 1, canvas.height > 1, !window.inLiveResize else {
                // Clears the ratio (`contentResizeIncrements` takes precedence once set to 1 × 1) —
                // also one this lock didn't set: another view's, gone with its tab, or its pane split.
                if aspect == nil, held != nil || window.contentAspectRatio != .zero {
                    window.contentResizeIncrements = NSSize(width: 1, height: 1)
                    held = nil
                }
                return
            }
            let current = content.frame.size
            let chrome = CGSize(width: max(0, current.width - canvas.width), height: max(0, current.height - canvas.height))
            let target = GlassWindowAspect.windowSize(current: current, aspect: aspect, chrome: chrome, minimum: minimum)
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
public struct GlassWindowAspectLock: View {
    public init(aspect: Double?, canvas: CGSize, minimum: CGSize) {}
    public init(aspect: Double?, chrome: CGSize, minimum: CGSize) {}
    public var body: some View { Color.clear.frame(width: 0, height: 0) }
}
#endif
