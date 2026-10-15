//
//  GlassWindowSizer.swift
//  Glass Power Tools — GlassShell
//
//  A window's size on Vision Pro, asked of visionOS: the Connections window becoming its orb and
//  growing back (W39), and a session window doing the same (`glassSessionOrb`, 2026-10-15). Moved
//  out of the Connections window's probe, where it began, so both ask the same way.
//

#if os(visionOS)
import SwiftUI
import UIKit
import os

@MainActor
final class GlassWindowSizer {
    weak var window: UIWindow?

    /// The window's size now, from its scene; nil until the sizer is in a window.
    var windowSize: CGSize? {
        guard let scene = window?.windowScene else { return nil }
        return scene.effectiveGeometry.coordinateSpace.bounds.size
    }

    /// Bumped by every resize asked for, so an older one still waiting gives way to the newest.
    private var generation = 0

    /// Asks visionOS to give the window `size`, once its scene's limits allow it. The limits come
    /// from the content (a scene sized by its content), and SwiftUI hands them to the scene a
    /// moment after the content changes: a size asked for before then is held to the old ones. So
    /// the limits are looked at every tenth of a second for two seconds, and the size asked for
    /// once they allow it, or then anyway; what visionOS made of it is logged. `afterward` runs once
    /// the window has had a moment to take its new size. `freeform` frees a window held to a shape
    /// (a desktop's, W38) to take this one.
    func resize(to size: CGSize, event: String, freeform: Bool = false,
                afterward: (@MainActor () -> Void)? = nil) {
        generation &+= 1
        request(size, event: event, freeform: freeform, generation: generation, attempt: 0, afterward: afterward)
    }

    private func request(_ size: CGSize, event: String, freeform: Bool, generation: Int, attempt: Int,
                         afterward: (@MainActor () -> Void)?) {
        guard generation == self.generation else { return }
        let scene = window?.windowScene
        let admitted = scene.map {
            GlassConnectionsWindowSize.admits(size, minimum: $0.effectiveGeometry.minimumSize,
                                              maximum: $0.effectiveGeometry.maximumSize)
        } ?? false
        guard let scene, admitted || attempt >= 20 else {
            guard attempt < 20 else {
                Logger.idle.error("event=\(event, privacy: .public) no-window")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.request(size, event: event, freeform: freeform, generation: generation, attempt: attempt + 1,
                              afterward: afterward)
            }
            return
        }
        Logger.idle.notice("event=\(event, privacy: .public) width=\(size.width) height=\(size.height) waited=\(attempt)")
        let preferences = freeform ? UIWindowScene.GeometryPreferences.Vision(size: size, resizingRestrictions: .freeform)
            : UIWindowScene.GeometryPreferences.Vision(size: size)
        scene.requestGeometryUpdate(preferences) { error in
            Logger.idle.error("event=\(event, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
        // What visionOS made of it, for the log.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let geometry = scene.effectiveGeometry
            let bounds = geometry.coordinateSpace.bounds.size
            Logger.idle.notice("event=\(event, privacy: .public)-geometry width=\(bounds.width) height=\(bounds.height) min=\(geometry.minimumSize.width)x\(geometry.minimumSize.height) max=\(geometry.maximumSize.width)x\(geometry.maximumSize.height)")
            afterward?()
        }
    }
}

/// Zero-size and not hit-testable: hands the sizer the window it is in.
struct GlassWindowSizerView: UIViewRepresentable {
    let sizer: GlassWindowSizer

    func makeUIView(context: Context) -> SizerView { SizerView(sizer: sizer) }
    func updateUIView(_ view: SizerView, context: Context) {}

    final class SizerView: UIView {
        let sizer: GlassWindowSizer

        init(sizer: GlassWindowSizer) {
            self.sizer = sizer
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { sizer.window = window }
        }
    }
}
#endif
