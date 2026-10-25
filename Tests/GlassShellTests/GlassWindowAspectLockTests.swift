//
//  GlassWindowAspectLockTests.swift
//  Glass Power Tools — GlassShellTests
//
//  A window held to the shape of what it shows (W38's desktops, D75's terminals under Scale), on a
//  Mac: the content takes the shape with its chrome kept, and a lock that wants no shape lets go of
//  one — including one another view set, gone with its tab or its pane split.
//

#if os(macOS)
import AppKit
import SwiftUI
import Testing
import GlassShell

@Suite("A window held to a shape")
@MainActor
struct GlassWindowAspectLockTests {
    /// A window whose content is a lock, beside a 40-point band of chrome above the part it holds.
    @MainActor
    final class Hosted {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 800, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        private var hosting: NSHostingView<GlassWindowAspectLock>?

        init(aspect: Double?) async {
            window.isReleasedWhenClosed = false
            show(aspect: aspect)
            await settle()
        }

        /// The held part: the content less the band.
        var canvas: CGSize {
            let content = window.contentView?.frame.size ?? .zero
            return CGSize(width: content.width, height: content.height - 40)
        }

        func show(aspect: Double?) {
            let lock = GlassWindowAspectLock(aspect: aspect, canvas: canvas, minimum: CGSize(width: 320, height: 200))
            if let hosting {
                hosting.rootView = lock
            } else {
                let hosting = NSHostingView(rootView: lock)
                hosting.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
                window.contentView?.addSubview(hosting)
                self.hosting = hosting
            }
        }

        func settle() async {
            for _ in 0..<5 { await Task.yield() }
            try? await Task.sleep(for: .milliseconds(50))
        }

        /// Until SwiftUI has done what is asked, for up to 10 s: a fixed 50 ms stood for it, which a
        /// run whose other tests hold the main actor outlasts (2026-10-24).
        func settle(until condition: () -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + .seconds(10)
            while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
            return condition()
        }

        func close() {
            hosting?.removeFromSuperview()
            window.close()
        }
    }

    @Test("the held part takes the shape, the chrome beside it keeps its size")
    func holdsTheShape() async {
        let host = await Hosted(aspect: 2)
        defer { host.close() }
        _ = await host.settle { abs(host.canvas.width / host.canvas.height - 2) < 0.01 && host.window.contentAspectRatio != .zero }
        let canvas = host.canvas
        #expect(abs(canvas.width / canvas.height - 2) < 0.01, "800 wide: the part 400 high, the content 440: \(canvas)")
        #expect(host.window.contentAspectRatio != .zero, "and held to it as the window is resized")
    }

    @Test("a lock that wants no shape lets go of one it didn't set")
    func letsGoOfAnothersShape() async {
        let host = await Hosted(aspect: nil)
        defer { host.close() }
        // Held by another view, since gone (a scaled terminal's tab, before its window split).
        host.window.contentAspectRatio = NSSize(width: 2, height: 1)
        host.show(aspect: nil)
        // The lock looks again as what it holds changes size.
        host.window.setContentSize(NSSize(width: 700, height: 500))
        host.show(aspect: nil)
        #expect(await host.settle { host.window.contentAspectRatio == .zero }, "free to take any shape")
    }
}
#endif
