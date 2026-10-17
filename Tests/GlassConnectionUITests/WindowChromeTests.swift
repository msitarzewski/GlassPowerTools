#if os(macOS)
import AppKit
import Testing
@testable import GlassConnectionUI

@Suite(.serialized) @MainActor
struct WindowChromeTests {
    @Test func nativeTitlebarIsPassiveBoundedAndInstalledOnce() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = try #require(window.contentView?.superview)
        let style = window.styleMask
        let toolbarStyle = window.toolbarStyle
        GlassWindowChrome.installTitlebarMaterial(in: window)
        GlassWindowChrome.installTitlebarMaterial(in: window)
        root.layoutSubtreeIfNeeded()
        let materials = root.subviews.compactMap { $0 as? GlassTitlebarMaterialView }
        #expect(materials.count == 1)
        let material = try #require(materials.first)
        #expect(material.hitTest(NSPoint(x: 5, y: 5)) == nil)
        #expect(material.material == .sidebar)
        #expect(material.blendingMode == .behindWindow)
        #expect(material.state == .followsWindowActiveState)
        #expect(root.subviews.first === material)
        #expect(material.frame.height > 0)
        #expect(abs(material.frame.minY - window.contentLayoutRect.maxY) < 1)
        #expect(window.styleMask == style)
        #expect(window.toolbarStyle == toolbarStyle)
        #expect(!window.isVisible)
        window.setContentSize(NSSize(width: 700, height: 450))
        root.layoutSubtreeIfNeeded()
        #expect(abs(material.frame.width - root.bounds.width) < 1)
        #expect(abs(material.frame.minY - window.contentLayoutRect.maxY) < 1)
        GlassWindowChrome.installTitlebarMaterial(in: window, materialStyle: .underWindowBackground)
        #expect(material.material == .underWindowBackground)
    }

    /// Opening, AppKit lays the sidebar out at its full width before it has said the sidebar is
    /// open, and the window can be drawn then: with the sidebar still to slide in, a material that
    /// had moved left the toolbar see-through for a frame (the owner's recording, 2026-10-17). It
    /// moves once the sidebar has opened.
    @Test func materialWaitsForTheSidebarToOpen() throws {
        _ = NSApplication.shared
        let sidebar = NSSplitViewItem(sidebarWithViewController: Self.controller(width: 240))
        let split = NSSplitViewController()
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: Self.controller(width: 700)))
        sidebar.isCollapsed = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = split
        window.setContentSize(NSSize(width: 940, height: 500))
        // On screen, unseen: AppKit slides a sidebar in only in a window it shows.
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.close() }
        GlassWindowChrome.installTitlebarMaterial(in: window)
        let root = try #require(window.contentView?.superview)
        root.layoutSubtreeIfNeeded()
        let material = try #require(root.subviews.compactMap { $0 as? GlassTitlebarMaterialView }.first)
        #expect(material.leadingInset == 0, "closed: the material spans the toolbar")

        // What the material says while AppKit lays the split view out, before `isCollapsed` is
        // announced (observed after the material, so its own reading is already made).
        let opening = Opening(sidebar: sidebar, material: material)
        let observer = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: split.splitView, queue: nil
        ) { _ in
            MainActor.assumeIsolated { opening.splitViewLaidOut() }
        }
        let announcement = sidebar.observe(\.isCollapsed, options: [.new]) { _, _ in
            MainActor.assumeIsolated { opening.announced = true }
        }
        defer { announcement.invalidate(); NotificationCenter.default.removeObserver(observer) }

        // As its toolbar button does.
        split.toggleSidebar(nil)
        #expect(opening.announced)
        #expect(!opening.readings.isEmpty, "AppKit laid the split view out as the sidebar opened")
        #expect(opening.readings.allSatisfy { $0 == 0 },
                "the material held its edge until the sidebar had opened: \(opening.readings)")
        // Not held after: placed where its slide ends (which `swift test` never runs), the sidebar
        // takes the material's edge with it.
        split.splitView.setPosition(240, ofDividerAt: 0)
        root.layoutSubtreeIfNeeded()
        #expect(abs(material.leadingInset - 240) < 1, "open: the material begins at the sidebar's edge: \(material.leadingInset)")

        NSAnimationContext.runAnimationGroup({ $0.duration = 0; sidebar.isCollapsed = true }, completionHandler: nil)
        root.layoutSubtreeIfNeeded()
        #expect(material.leadingInset == 0, "closed again: \(material.leadingInset)")
    }

    /// The material's edge at each layout of the split view while the sidebar opens, until it is
    /// said to have opened.
    @MainActor
    final class Opening {
        let sidebar: NSSplitViewItem
        let material: GlassTitlebarMaterialView
        var announced = false
        var readings: [CGFloat] = []

        init(sidebar: NSSplitViewItem, material: GlassTitlebarMaterialView) {
            self.sidebar = sidebar
            self.material = material
        }

        func splitViewLaidOut() {
            if !announced, !sidebar.isCollapsed { readings.append(material.leadingInset) }
        }
    }

    private static func controller(width: CGFloat) -> NSViewController {
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 500))
        return controller
    }
}
#endif
