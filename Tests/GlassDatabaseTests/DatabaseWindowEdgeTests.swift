#if os(macOS)
import AppKit
import Testing
import GlassConnectionUI
@testable import GlassDatabase

/// The owner, 2026-10-17: "remove the gray line in database and desktop windows too", after the
/// terminal window's went. A database window's sidebar meets the workspace with no line between:
/// AppKit's divider draws nothing and the chrome's hairline is hidden, after the sidebar reopens
/// too.
@Suite(.serialized) @MainActor
struct DatabaseWindowEdgeTests {
    @Test func sidebarEdgeDrawsNoLine() throws {
        _ = NSApplication.shared
        let sidebar = NSSplitViewItem(sidebarWithViewController: Self.controller(width: 240))
        let split = NSSplitViewController()
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: Self.controller(width: 700)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = split
        window.setContentSize(NSSize(width: 940, height: 500))
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.close() }

        MacDatabaseWorkspaceWindowPolicy.apply(window)
        let root = try #require(window.contentView?.superview)
        root.layoutSubtreeIfNeeded()
        let material = try #require(root.subviews.compactMap { $0 as? GlassTitlebarMaterialView }.first)
        let hairline = try #require(root.subviews.first { $0.identifier?.rawValue == "glass.sidebar.separator" })
        let splitView = split.splitView
        func dividers() -> [NSView] {
            splitView.subviews.filter {
                !splitView.arrangedSubviews.contains($0) && $0.frame.width <= splitView.dividerThickness + 0.5
            }
        }
        #expect(!material.showsSidebarEdge)
        #expect(hairline.isHidden)
        #expect(!dividers().isEmpty, "AppKit's divider is there to see through")
        #expect(dividers().allSatisfy { $0.alphaValue == 0 }, "\(dividers().map(\.alphaValue))")

        for collapsed in [true, false] {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0; sidebar.isCollapsed = collapsed }, completionHandler: nil)
            root.layoutSubtreeIfNeeded()
        }
        // The policy runs again as the workspace updates; it keeps the edge off.
        MacDatabaseWorkspaceWindowPolicy.apply(window)
        #expect(hairline.isHidden)
        #expect(dividers().allSatisfy { $0.alphaValue == 0 }, "still nothing after it reopens: \(dividers().map(\.alphaValue))")
    }

    /// The policy runs again on every update of the workspace. Setting a window property to the value
    /// it already has still tells everything observing it, SwiftUI's hosting view among them: in the
    /// screenshot VM (2026-10-18) that notice reached a hosting view being taken down, and the app
    /// crashed in AttributeGraph under `LazyPreventsWindowDragFeature`. Applied again, it changes
    /// nothing, so it tells no one.
    @Test func applyingAgainTellsNoOne() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = Self.controller(width: 700)
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.close() }
        MacDatabaseWorkspaceWindowPolicy.apply(window)

        let observer = ChangeRecorder()
        let keys = ["opaque", "backgroundColor", "titlebarAppearsTransparent", "styleMask", "ignoresMouseEvents",
                    "movableByWindowBackground", "autorecalculatesKeyViewLoop"]
        for key in keys { window.addObserver(observer, forKeyPath: key, options: [], context: nil) }
        defer { for key in keys { window.removeObserver(observer, forKeyPath: key) } }
        MacDatabaseWorkspaceWindowPolicy.apply(window)
        #expect(observer.changes.isEmpty, "told of \(observer.changes)")
    }

    private final class ChangeRecorder: NSObject {
        var changes: [String] = []
        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            changes.append(keyPath ?? "?")
        }
    }

    private static func controller(width: CGFloat) -> NSViewController {
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 500))
        return controller
    }
}
#endif
