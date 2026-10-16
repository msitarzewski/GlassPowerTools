//
//  GlassAdditiveSidebarsTests.swift
//  Glass Power Tools — GlassShellTests
//
//  A SwiftUI split view's sidebar, on a Mac, opened and closed as its toolbar button does: additive,
//  the window grows and shrinks by it and the content beside it keeps its size and place; not, the
//  window keeps its size and the content gives way.
//

#if os(macOS)
import AppKit
import SwiftUI
import Testing
import GlassShell

@Suite("Sidebars that add to a window")
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

        func settle() async {
            for _ in 0..<5 { await Task.yield() }
            try? await Task.sleep(for: .milliseconds(300))
            window.contentView?.layoutSubtreeIfNeeded()
        }

        func close() { window.close() }
    }

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
