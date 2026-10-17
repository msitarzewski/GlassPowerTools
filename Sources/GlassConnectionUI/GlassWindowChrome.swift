#if os(macOS)
import AppKit

/// Native titlebar backing shared by the Glass apps. The material is passive:
/// it follows AppKit geometry without changing toolbar layout, input or canvas opacity.
@MainActor
public final class GlassTitlebarMaterialView: NSVisualEffectView {
    weak var contentBoundary: NSView?
    private var leadingConstraint: NSLayoutConstraint?
    private weak var sidebarItem: NSSplitViewItem?
    private var sidebarObservation: NSKeyValueObservation?
    private var resizeObservation: NSObjectProtocol?
    /// Changes to the sidebar under way, announced and not yet made.
    private var sidebarChanges = 0

    isolated deinit {
        if let resizeObservation { NotificationCenter.default.removeObserver(resizeObservation) }
    }

    public func followSidebarBoundary() {
        guard let contentBoundary else { return }
        var discoveredSidebar: NSSplitViewItem?
        var discoveredSplit: NSSplitView?
        var views = [contentBoundary]
        var index = 0
        while index < views.count, index < 256 {
            let view = views[index]
            index += 1
            if let split = view as? NSSplitView,
               let controller = split.delegate as? NSSplitViewController,
               let sidebar = controller.splitViewItems.first(where: { $0.behavior == .sidebar }) {
                discoveredSidebar = sidebar
                discoveredSplit = split
                break
            }
            views.append(contentsOf: view.subviews)
        }
        if sidebarItem !== discoveredSidebar {
            sidebarObservation = nil
            if let resizeObservation { NotificationCenter.default.removeObserver(resizeObservation) }
            resizeObservation = nil
            sidebarItem = discoveredSidebar
            // Opening, AppKit lays the sidebar out at its full width, and the window is drawn,
            // before it moves the sidebar out of sight to slide it in and says it has opened. Read
            // then, the edge stood at the sidebar's full width over nothing, and the window showed
            // through the toolbar for a frame (the owner's recording, 2026-10-17). The edge holds
            // from the change's first notice (`.prior`) to its last.
            sidebarObservation = discoveredSidebar?.observe(\.isCollapsed, options: [.prior]) { [weak self] _, change in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if change.isPrior {
                        self.sidebarChanges += 1
                    } else {
                        self.sidebarChanges = max(0, self.sidebarChanges - 1)
                        self.updateLeadingBoundary()
                    }
                }
            }
            if let discoveredSplit {
                resizeObservation = NotificationCenter.default.addObserver(
                    forName: NSSplitView.didResizeSubviewsNotification,
                    object: discoveredSplit, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateLeadingBoundary() }
                }
            }
        }
        updateLeadingBoundary()
    }

    private func updateLeadingBoundary() {
        guard sidebarChanges == 0, let frame = superview else { return }
        var offset: CGFloat = 0
        if let sidebarItem, !sidebarItem.isCollapsed {
            let sidebar = sidebarItem.viewController.view
            offset = sidebar.convert(sidebar.bounds, to: frame).maxX - frame.bounds.minX
        }
        offset = min(max(0, offset), frame.bounds.width)
        // Read native geometry without constraining any native content view.
        // A cross-hierarchy anchor here can pull the split view out of position.
        if let leadingConstraint {
            if abs(leadingConstraint.constant - offset) > 0.1 {
                leadingConstraint.constant = offset
            }
        } else {
            leadingConstraint = leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: offset)
            leadingConstraint?.isActive = true
        }
    }

    /// Where the material begins, from the window's leading edge.
    var leadingInset: CGFloat { leadingConstraint?.constant ?? 0 }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
public enum GlassWindowChrome {
    public static func installTitlebarMaterial(in window: NSWindow, materialStyle: NSVisualEffectView.Material = .sidebar) {
        guard let content = window.contentView,
              let frame = content.superview,
              let guide = window.contentLayoutGuide as? NSLayoutGuide else { return }
        if let existing = frame.subviews.compactMap({ $0 as? GlassTitlebarMaterialView }).first {
            if existing.contentBoundary === content {
                existing.material = materialStyle
                existing.isHidden = false
                existing.followSidebarBoundary()
                return
            }
            existing.removeFromSuperview()
        }
        // Match the native sidebar's frosted backing independently of the
        // terminal canvas. The toolbar controls keep their own Liquid Glass.
        let material = GlassTitlebarMaterialView(frame: .zero)
        material.contentBoundary = content
        material.material = materialStyle
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        material.alphaValue = 1
        material.translatesAutoresizingMaskIntoConstraints = false
        material.setAccessibilityElement(false)
        frame.addSubview(material, positioned: .below, relativeTo: nil)
        // Follow the native sidebar's edge through divider moves and
        // sidebar collapse. Never frost the already-material-backed sidebar.
        material.followSidebarBoundary()
        NSLayoutConstraint.activate([
            material.trailingAnchor.constraint(equalTo: frame.trailingAnchor),
            material.topAnchor.constraint(equalTo: frame.topAnchor),
            material.bottomAnchor.constraint(equalTo: guide.topAnchor),
        ])
        installSidebarSeparator(in: frame, alignedTo: material)
    }

    /// A hairline down the sidebar's trailing edge. The layered window has a clear backing, so
    /// AppKit's own split divider paints nothing and the desktop shows through the seam
    /// (observed on a connected session, 2026-09-11). This line is opaque and full height, and it
    /// follows the same boundary the titlebar material does.
    private static func installSidebarSeparator(in frame: NSView, alignedTo material: NSView) {
        let existing = frame.subviews.first { $0.identifier == sidebarSeparatorIdentifier }
        existing?.removeFromSuperview()
        let separator = NSView(frame: .zero)
        separator.identifier = sidebarSeparatorIdentifier
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.setAccessibilityElement(false)
        frame.addSubview(separator, positioned: .above, relativeTo: material)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.topAnchor.constraint(equalTo: frame.topAnchor),
            separator.bottomAnchor.constraint(equalTo: frame.bottomAnchor),
        ])
    }

    private static let sidebarSeparatorIdentifier = NSUserInterfaceItemIdentifier("glass.sidebar.separator")
}
#endif
