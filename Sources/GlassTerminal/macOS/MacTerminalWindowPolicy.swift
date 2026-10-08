#if os(macOS)
#if os(macOS)
import AppKit
import SwiftUI
import GlassLayers
import GlassConnectionUI

enum MacTerminalToolbarItemID {
    static let tabActions = "sh.glas.toolbar.tab-actions"
}

struct MacTerminalWindowReader: NSViewRepresentable {
    @Environment(\.glassLayers) private var layers
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let tabbingIdentifier: String
    var onWindow: (NSWindow) -> Void
    var onClose: () -> Void
    /// What to ask before the window closes — or, with `quitting`, before the app quits — or nil
    /// to go without asking.
    var shouldConfirmClose: (_ quitting: Bool) -> String?
    var opensSidebarInitially: Bool
    var overviewPresented: Bool

    init(
        tabbingIdentifier: String,
        onWindow: @escaping (NSWindow) -> Void = { _ in },
        onClose: @escaping () -> Void = {},
        shouldConfirmClose: @escaping (_ quitting: Bool) -> String? = { _ in nil },
        opensSidebarInitially: Bool = false,
        overviewPresented: Bool = false
    ) {
        self.tabbingIdentifier = tabbingIdentifier
        self.onWindow = onWindow
        self.onClose = onClose
        self.shouldConfirmClose = shouldConfirmClose
        self.opensSidebarInitially = opensSidebarInitially
        self.overviewPresented = overviewPresented
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NonHitTestingWindowReaderView(frame: .zero)
        let coordinator = context.coordinator
        DispatchQueue.main.async { configure(view.window, coordinator: coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async { configure(nsView.window, coordinator: coordinator) }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.restoreWindowDelegate()
        coordinator.stopObservingWindowClose()
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        let state = GlassLayerResolution.resolve(layers.state, reduceTransparency: reduceTransparency)
        MacTerminalWindowPolicy.apply(window, tabbingIdentifier: tabbingIdentifier, overviewPresented: overviewPresented, layers: state)
        coordinator.observeWindowClose(window, action: onClose)
        coordinator.interceptWindowClose(window, shouldConfirm: shouldConfirmClose)
        coordinator.configureInitialSidebar(in: window, enabled: opensSidebarInitially, overviewPresented: overviewPresented)
        onWindow(window)
    }

    @MainActor
    private final class NonHitTestingWindowReaderView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        static let active = NSHashTable<Coordinator>.weakObjects()
        private weak var observedWindow: NSWindow?
        private var closeAction: (() -> Void)?
        private var shouldConfirmClose: ((_ quitting: Bool) -> String?)?
        // AppKit performs delegate discovery/forwarding on its main thread, but
        // NSObject's Objective-C forwarding overrides are nonisolated in Swift.
        nonisolated(unsafe) private weak var originalWindowDelegate: (any NSWindowDelegate)?
        private var isConfirmingClose = false
        private var didRunCloseAction = false
        private var wantsInitialSidebar = false
        private var didApplyInitialSidebar = false
        private var sidebarDiscoveryAttempts = 0
        private var overviewPresented = false

        func configureInitialSidebar(in window: NSWindow, enabled: Bool, overviewPresented: Bool = false) {
            wantsInitialSidebar = enabled
            self.overviewPresented = overviewPresented
            // Overview owns presentation before startup discovery completes.
            // Never replay the initial-open request later when returning to Tabs.
            if overviewPresented { didApplyInitialSidebar = true }
            applyInitialSidebarIfNeeded(in: window)
        }

        private func applyInitialSidebarIfNeeded(in window: NSWindow) {
            guard overviewPresented || (wantsInitialSidebar && !didApplyInitialSidebar && sidebarDiscoveryAttempts < 16),
                  let root = window.contentView else { return }
            if !overviewPresented { sidebarDiscoveryAttempts += 1 }
            // Use AppKit's public sidebar semantics only. SwiftUI can assemble
            // the native split after this reader attaches; didUpdate retries
            // briefly. Unsupported hosts simply keep their system default.
            var views = [root]
            var index = 0
            while index < views.count, index < 256 {
                let view = views[index]
                index += 1
                if let split = view as? NSSplitView,
                   let controller = split.delegate as? NSSplitViewController,
                   let sidebar = controller.splitViewItems.first(where: { $0.behavior == .sidebar }) {
                    if !overviewPresented { didApplyInitialSidebar = true }
                    if sidebar.isCollapsed != overviewPresented {
                        sidebar.isCollapsed = overviewPresented
                    }
                    return
                }
                views.append(contentsOf: view.subviews)
            }
        }

        func observeWindowClose(
            _ window: NSWindow,
            action: @escaping () -> Void
        ) {
            closeAction = action
            guard observedWindow !== window else { return }
            if observedWindow != nil {
                restoreWindowDelegate()
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.willCloseNotification,
                    object: observedWindow
                )
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didUpdateNotification,
                    object: observedWindow
                )
            }
            observedWindow = window
            didRunCloseAction = false
            Self.active.add(self)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(observedWindowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(observedWindowDidUpdate(_:)),
                name: NSWindow.didUpdateNotification,
                object: window
            )
        }

        func stopObservingWindowClose() {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: observedWindow
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didUpdateNotification,
                object: observedWindow
            )
            observedWindow = nil
            closeAction = nil
            Self.active.remove(self)
        }

        func interceptWindowClose(
            _ window: NSWindow,
            shouldConfirm: @escaping (_ quitting: Bool) -> String?
        ) {
            self.shouldConfirmClose = shouldConfirm
            guard observedWindow === window, window.delegate !== self else { return }
            originalWindowDelegate = window.delegate
            window.delegate = self
        }

        func restoreWindowDelegate() {
            if let window = observedWindow, window.delegate === self {
                window.delegate = originalWindowDelegate
            }
            originalWindowDelegate = nil
            shouldConfirmClose = nil
        }

        // SwiftUI keeps ownership of its window lifecycle and restoration callbacks.
        // Forward every optional delegate method except the close gate we extend.
        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || originalWindowDelegate?.responds(to: selector) == true
        }

        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            if originalWindowDelegate?.responds(to: selector) == true {
                return originalWindowDelegate
            }
            return super.forwardingTarget(for: selector)
        }

        var closeConfirmationMessage: String? { shouldConfirmClose?(false) ?? nil }
        var quitConfirmationMessage: String? { shouldConfirmClose?(true) ?? nil }

        func finishSessions() {
            guard !didRunCloseAction else { return }
            didRunCloseAction = true
            closeAction?()
        }

        func windowShouldClose(_ window: NSWindow) -> Bool {
            guard !isConfirmingClose else { return false }
            guard originalWindowDelegate?.windowShouldClose?(window) != false else { return false }
            guard let message = closeConfirmationMessage else { return true }
            isConfirmingClose = true
            let alert = NSAlert()
            alert.messageText = "Close Terminal?"
            alert.informativeText = message
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            alert.beginSheetModal(for: window) { [weak self, weak window] response in
                self?.isConfirmingClose = false
                if response == .alertFirstButtonReturn {
                    window?.close()
                }
            }
            return false
        }

        @objc private func observedWindowDidUpdate(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  window === observedWindow else { return }
            applyInitialSidebarIfNeeded(in: window)
        }

        @objc private func observedWindowWillClose(_ notification: Notification) {
            finishSessions()
        }
    }
}

typealias MacTerminalTitlebarMaterialView = GlassTitlebarMaterialView

@MainActor
enum MacTerminalWindowPolicy {
    static func apply(_ window: NSWindow, tabbingIdentifier: String, overviewPresented: Bool = false,
                      layers: GlassLayerState = .default) {
        // The family's titlebar sequence (clear backing, transparent titlebar, passive material
        // whose alpha follows frost) lives in GlassLayers, and the overview gets the same one.
        //
        // It used to swap the title band to `.underWindowBackground` while the overview was up.
        // That material is *designed* to show what is behind the window, blurred — so with the
        // database window behind this one, the database's own header floated through the
        // terminal's own title (reported 2026-09-21, "we lost the title settings again"). glas.sh
        // did the same swap, which is why it is "again". Rule 50: chrome that says where you are
        // does not become see-through because a mode changed.
        GlassWindowLayerPolicy.apply(window, state: layers)
        // Leave toolbar layout and dragging to SwiftUI/AppKit.
        // The added titlebar material is passive.
        // SwiftUI's navigation sidebar owns terminal tabs inside this
        // window. Disallow a second AppKit tab layer and its horizontal strip.
        window.tabbingMode = .disallowed
        window.tabbingIdentifier = ""
        window.isRestorable = true
        window.autorecalculatesKeyViewLoop = true
    }


}
#endif

#endif
