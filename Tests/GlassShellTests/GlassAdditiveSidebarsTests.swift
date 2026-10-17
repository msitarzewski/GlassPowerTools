//
//  GlassAdditiveSidebarsTests.swift
//  Glass Power Tools — GlassShellTests
//
//  A SwiftUI split view's sidebar, on a Mac, opened and closed as its toolbar button does: additive,
//  the window grows and shrinks by it and the content beside it keeps its size and place; not, the
//  window keeps its size and the content gives way. And the window's frame for it, as rules.
//

#if os(macOS)
import AppKit
import SwiftUI
import Testing
import GlassShell

@Suite("Sidebars that add to a window", .serialized)
@MainActor
struct GlassAdditiveSidebarsTests {
    /// A window showing a sidebar and a detail, as a terminal window does, its sidebar closed.
    @MainActor
    final class Hosted {
        let window = NSWindow(contentRect: NSRect(x: 400, y: 300, width: 800, height: 500),
                              styleMask: [.titled, .resizable, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)

        /// Where SwiftUI lays the detail out, in the window: beside the sidebar, not under it.
        final class Measured { var frame: CGRect = .zero }
        let measured = Measured()

        struct Content: View {
            let measured: Measured
            @State var visibility: NavigationSplitViewVisibility = .detailOnly
            var body: some View {
                NavigationSplitView(columnVisibility: $visibility) {
                    List { Text("tab") }
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 520)
                } detail: {
                    GeometryReader { proxy in
                        Color.clear.onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                            measured.frame = frame
                        }
                    }
                }
            }
        }

        init() async {
            GlassAdditiveSidebars.animationDuration = 0
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Content(measured: measured))
            // On screen, as a window the person sees, but not to be seen: AppKit keeps a window
            // on screen as it grows it, and picks the direction from where it is.
            window.alphaValue = 0
            window.orderFrontRegardless()
            window.setFrame(NSRect(x: 400, y: 300, width: 800, height: 500), display: true)
            await settle()
        }

        var sidebar: NSSplitViewItem? {
            GlassAdditiveSidebars.items(in: window).first { $0.behavior == .sidebar }
        }

        /// The detail's laid-out part, where the window shows it on screen.
        var detailOnScreen: NSRect? {
            let frame = measured.frame
            guard frame.width > 0, let content = window.contentView else { return nil }
            // SwiftUI's global space is the hosting view's, top-left first.
            let flipped = NSRect(x: frame.minX, y: content.bounds.height - frame.maxY,
                                 width: frame.width, height: frame.height)
            return window.convertToScreen(content.convert(flipped, to: nil))
        }

        /// Open or close the sidebar as AppKit's toolbar button and View ▸ Show Sidebar do.
        func toggle() async {
            guard let controller = sidebar?.viewController.parent as? NSSplitViewController else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0
                controller.toggleSidebar(nil)
            }, completionHandler: nil)
            await settle()
        }

        /// Until the window and the detail have stopped moving (200 ms still, 3 s at most).
        func settle() async {
            try? await Task.sleep(for: .milliseconds(150))
            var last = (window.frame, measured.frame), still = 0
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while ContinuousClock.now < deadline, still < 4 {
                for _ in 0..<5 { await Task.yield() }
                try? await Task.sleep(for: .milliseconds(50))
                window.contentView?.layoutSubtreeIfNeeded()
                let now = (window.frame, measured.frame)
                if now == last { still += 1 } else { still = 0; last = now }
            }
        }

        func close() { window.close() }
    }

    // MARK: The window's frame

    private let screen = NSRect(x: 0, y: 0, width: 1800, height: 1100)

    @Test("a sidebar opening grows the window to the left, closing shrinks it from the left")
    func leadingFrame() throws {
        let window = NSRect(x: 600, y: 200, width: 900, height: 500)
        let opened = try #require(GlassAdditiveSidebars.windowFrame(window, sidebarWidth: 240, opening: true,
                                                                    leading: true, visible: screen))
        #expect(opened == NSRect(x: 360, y: 200, width: 1140, height: 500), "the right edge stays: \(opened)")
        let closed = try #require(GlassAdditiveSidebars.windowFrame(opened, sidebarWidth: 240, opening: false,
                                                                    leading: true, visible: screen))
        #expect(closed == window)
    }

    @Test("an inspector grows the window to the right")
    func trailingFrame() {
        let window = NSRect(x: 100, y: 200, width: 900, height: 500)
        #expect(GlassAdditiveSidebars.windowFrame(window, sidebarWidth: 300, opening: true, leading: false,
                                                  visible: screen) == NSRect(x: 100, y: 200, width: 1200, height: 500))
    }

    @Test("opening keeps the window on screen, and gives way where it can't be that wide")
    func onScreen() {
        // Against the left edge: slid back in, the content moving with it.
        let atEdge = NSRect(x: 100, y: 200, width: 900, height: 500)
        #expect(GlassAdditiveSidebars.windowFrame(atEdge, sidebarWidth: 240, opening: true, leading: true,
                                                  visible: screen) == NSRect(x: 0, y: 200, width: 1140, height: 500))
        // Zoomed to the screen's width: nothing to grow into.
        let zoomed = NSRect(x: 0, y: 0, width: 1800, height: 1100)
        #expect(GlassAdditiveSidebars.windowFrame(zoomed, sidebarWidth: 240, opening: true, leading: true,
                                                  visible: screen) == nil)
        // Closing never moves a window someone left partly off screen.
        let off = NSRect(x: 1500, y: 200, width: 900, height: 500)
        #expect(GlassAdditiveSidebars.windowFrame(off, sidebarWidth: 240, opening: false, leading: true,
                                                  visible: screen) == NSRect(x: 1740, y: 200, width: 660, height: 500))
    }

    // MARK: A window

    @Test("additive: the window grows by the sidebar, the detail keeps its size and place")
    func additive() async throws {
        let host = await Hosted()
        defer { host.close() }
        let sidebar = try #require(host.sidebar, "SwiftUI's split view has a sidebar item")
        #expect(sidebar.isCollapsed)
        #expect(GlassAdditiveSidebars.set(additive: true, in: host.window))
        let before = try #require(host.detailOnScreen)
        let windowBefore = host.window.frame

        await host.toggle()
        #expect(!sidebar.isCollapsed, "the sidebar opened")
        let opened = try #require(host.detailOnScreen)
        #expect(abs(opened.width - before.width) < 1, "the detail kept its width: \(before) → \(opened)")
        #expect(abs(opened.minX - before.minX) < 1, "and its place: \(before) → \(opened)")
        #expect(host.window.frame.width > windowBefore.width + 100, "the window grew: \(windowBefore) → \(host.window.frame)")

        await host.toggle()
        #expect(sidebar.isCollapsed)
        let closed = try #require(host.detailOnScreen)
        #expect(abs(closed.width - before.width) < 1, "closed, the detail is as it was: \(closed)")
        #expect(abs(host.window.frame.width - windowBefore.width) < 1, "and the window: \(host.window.frame)")
    }

    @Test("not additive, after being so: the window keeps its size, the detail gives way")
    func notAdditive() async throws {
        let host = await Hosted()
        defer { host.close() }
        _ = try #require(host.sidebar)
        #expect(GlassAdditiveSidebars.set(additive: true, in: host.window))
        #expect(GlassAdditiveSidebars.set(additive: false, in: host.window))
        let before = try #require(host.detailOnScreen)
        let windowBefore = host.window.frame

        await host.toggle()
        let opened = try #require(host.detailOnScreen)
        #expect(abs(host.window.frame.width - windowBefore.width) < 1, "the window kept its size")
        #expect(opened.width < before.width - 100, "the detail gave way: \(before) → \(opened)")
    }
}
#endif
