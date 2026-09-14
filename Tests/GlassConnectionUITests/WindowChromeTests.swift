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
}
#endif
