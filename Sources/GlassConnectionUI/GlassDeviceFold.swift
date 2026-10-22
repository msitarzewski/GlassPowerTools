//
//  GlassDeviceFold.swift
//  Glass Power Tools — GlassConnectionUI
//
//  Where an iPhone Duo's fold crosses a view while the phone is partly folded (2026-10-21): stood
//  like a small laptop, the fold runs across, and Apple's guidance puts content in the top half and
//  controls in the bottom one; held like a book, it runs down the middle, and controls stay off it.
//  Flat, closed, or on any other device there is no fold.
//
//  Told by the system's reserved regions (iOS 27.1): the fold is a division region, active only
//  while the phone is folded. A fold becoming active doesn't change a view's size, so the region is
//  read again on every hinge update (`onHingeChange`), as Apple's tech talk and UTM's laptop mode
//  do.
//

import SwiftUI

/// The fold across a view, in the view's own coordinates, its margins included.
public struct GlassDeviceFold: Equatable, Sendable {
    public var frame: CGRect
    /// The size of the view it was read in.
    public var size: CGSize
    /// Where that view is on the screen.
    public var origin: CGPoint

    public init(frame: CGRect, size: CGSize, origin: CGPoint = .zero) {
        self.frame = frame
        self.size = size
        self.origin = origin
    }

    /// The fold on the screen: to lay out a view that isn't the one it was read in.
    public var globalFrame: CGRect { frame.offsetBy(dx: origin.x, dy: origin.y) }

    /// Across the view: the phone stood like a laptop, with a top half and a bottom half.
    public var isAcross: Bool { frame.width > frame.height }

    /// The fold from the system's division regions: the active one that crosses the view, if any.
    /// A region that doesn't reach across the view (a sliver of a fold at a window's edge) isn't
    /// a fold to lay out around.
    ///
    /// `partlyOpen`: the hinge says the phone is partly folded. Its region can still read inactive
    /// at that moment, and nothing else says so again when it turns active, so a region with a
    /// size counts then (on the simulator, a phone opened flat and folded with the keyboard up
    /// kept the flat layout, 2026-10-21).
    public static func from(regions: [CGRect], active: [Bool], partlyOpen: Bool = false,
                            in size: CGSize, at origin: CGPoint = .zero) -> GlassDeviceFold? {
        zip(regions, active).lazy.filter { frame, active in
            active || (partlyOpen && frame.width > 0 && frame.height > 0)
        }.map(\.0).first { frame in
            let across = frame.width > frame.height
            let span = across ? frame.width : frame.height
            let side = across ? size.width : size.height
            let within = across ? (frame.minY > 0 && frame.maxY < size.height) : (frame.minX > 0 && frame.maxX < size.width)
            return side > 0 && span >= side * 0.9 && within
        }.map { GlassDeviceFold(frame: $0, size: size, origin: origin) }
    }
}

extension View {
    /// Keeps `fold` up to date with where the device's fold crosses this view's window, in the
    /// window's (SwiftUI's global) coordinates: nil while there is none. iOS 27.1 and later;
    /// earlier, and on other platforms, always nil.
    public func glassDeviceFold(_ fold: Binding<GlassDeviceFold?>) -> some View {
        #if os(iOS)
        background {
            if #available(iOS 27.1, *) {
                GlassDeviceFoldWindowReader { fold.wrappedValue = $0 }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
import UIKit

/// Reads the fold from the window, which nothing shortens. A SwiftUI view's own regions were
/// read in a view the keyboard had shortened: with the keyboard in the bottom half, the fold
/// lay outside it, was lost, and the layout flapped between laptop and flat (2026-10-21, the
/// simulator). Read on every hinge update and again as the pose settles, since the region can
/// turn active after the update that says the hinge moved, and whenever the window lays out.
@available(iOS 27.1, *)
private struct GlassDeviceFoldWindowReader: UIViewRepresentable {
    let onChange: (GlassDeviceFold?) -> Void

    func makeUIView(context: Context) -> FoldView {
        FoldView(onChange: onChange)
    }

    func updateUIView(_ view: FoldView, context: Context) {
        view.onChange = onChange
    }

    final class FoldView: UIView {
        var onChange: (GlassDeviceFold?) -> Void
        private var partlyOpen = false
        private var reported: GlassDeviceFold??
        private var rereads: Task<Void, Never>?

        init(onChange: @escaping (GlassDeviceFold?) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            addInteraction(UIHingeInteraction { [weak self] _, update in
                self?.hingeMoved(partlyOpen: update.hinge?.status == .partiallyOpen)
            })
        }

        required init?(coder: NSCoder) { nil }

        deinit { rereads?.cancel() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            read()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            read()
        }

        private func hingeMoved(partlyOpen: Bool) {
            self.partlyOpen = partlyOpen
            read()
            rereads?.cancel()
            rereads = Task { @MainActor [weak self] in
                for delay in [250, 1_000] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.read()
                }
            }
        }

        private func read() {
            guard let window else { return report(nil) }
            let regions = window.reservedRegions(kind: .division, options: .includeInactive)
            report(GlassDeviceFold.from(regions: regions.map(\.frame), active: regions.map(\.isActive),
                                        partlyOpen: partlyOpen, in: window.bounds.size))
        }

        /// Told once per change, and never during SwiftUI's update.
        private func report(_ fold: GlassDeviceFold?) {
            if let reported, reported == fold { return }
            reported = .some(fold)
            let onChange = onChange
            DispatchQueue.main.async { onChange(fold) }
        }
    }
}
#endif
