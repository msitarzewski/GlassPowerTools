//
//  GlassCloseCommand.swift
//  Glass Power Tools — GlassShell
//
//  ⌘W, owned once, and aimed by the window it fires in.
//
//  **Why AppKit and not a `Commands` item.** ⌘N is a SwiftUI item the focused window aims
//  (`GlassShellFileCommands`), and the obvious move was to do the same for ⌘W. It does not work:
//  a declared ⌘W collides with AppKit's own File ▸ Close, and read back out of the running app the
//  shell's item was simply absent from the menu bar — in one placement it was dropped and Close kept
//  the key, in another Close lost the key and a *disabled* item kept it, so ⌘W closed nothing at
//  all. Both were invisible to the compiler and to every test.
//
//  So the Close item itself is the interception point, which is what glassdb had already worked out
//  (`MacDatabaseCommandWRouter`, moved here on 2026-09-16 and widened). A window that has something
//  smaller to close — a terminal tab, a database tab — registers an action; anything else closes
//  the window, which is what ⌘W means on this platform.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// How much a registration wants ⌘W when several are attached to one window. The highest enabled
/// one answers.
public enum GlassCloseCommandPriority: Int, Sendable {
    case workspace = 100
}

public extension View {
    /// Registers what ⌘W closes in **this window**: a tab, a pane, a document — anything smaller
    /// than the window itself. A window that registers nothing is closed whole.
    ///
    /// The registration stays attached while disabled, so a workspace never falls through to
    /// closing the window with every tab in it while one of its own tabs simply cannot be closed.
    @ViewBuilder
    func glassCloseCommandTarget(priority: GlassCloseCommandPriority,
                                 isEnabled: Bool = true,
                                 perform action: @escaping @MainActor () -> Void) -> some View {
        #if os(macOS)
        background {
            GlassCloseCommandTarget(priority: priority.rawValue, isEnabled: isEnabled, action: action)
        }
        #else
        self
        #endif
    }
}

#if os(macOS)
@MainActor
public final class GlassCloseCommandRouter: NSObject, NSMenuItemValidation {
    public static let shared = GlassCloseCommandRouter()

    private static let semanticModifiers: NSEvent.ModifierFlags = [
        .command,
        .option,
        .control,
        .shift,
    ]

    private final class Registration {
        weak var window: NSWindow?
        var priority: Int
        var isEnabled: Bool
        var action: @MainActor () -> Void

        init(
            window: NSWindow?,
            priority: Int,
            isEnabled: Bool,
            action: @escaping @MainActor () -> Void
        ) {
            self.window = window
            self.priority = priority
            self.isEnabled = isEnabled
            self.action = action
        }
    }

    private var registrations: [UUID: Registration] = [:]

    /// SwiftUI's macOS lifecycle owns the application object, so the reliable
    /// interception point is the File menu command that AppKit invokes for both
    /// its Command-W key equivalent and a direct menu selection.
    public func installCloseCommandInterceptor(in mainMenu: NSMenu? = NSApp.mainMenu) {
        guard let closeItem = mainMenu.flatMap(Self.commandWItem) else { return }
        closeItem.target = self
        closeItem.action = #selector(performCloseCommand(_:))
    }

    public func update(
        id: UUID,
        window: NSWindow?,
        priority: Int,
        isEnabled: Bool,
        action: @escaping @MainActor () -> Void
    ) {
        if let registration = registrations[id] {
            registration.window = window
            registration.priority = priority
            registration.isEnabled = isEnabled
            registration.action = action
        } else {
            registrations[id] = Registration(
                window: window,
                priority: priority,
                isEnabled: isEnabled,
                action: action
            )
        }
        installCloseCommandInterceptor()
    }

    public func remove(id: UUID) {
        registrations[id] = nil
    }

    /// Returns true when the target window belongs to a database workspace.
    /// Even with no enabled editor action, consuming Close prevents the
    /// permanent Overview/SQL workspace from being closed accidentally.
    public func routeClose(targetWindow: NSWindow?) -> Bool {
        guard let targetWindow else { return false }
        registrations = registrations.filter { $0.value.window != nil }
        let windowRegistrations = registrations.values.filter {
            $0.window === targetWindow
        }
        guard !windowRegistrations.isEmpty else { return false }

        let action = windowRegistrations
            .filter(\.isEnabled)
            .max { $0.priority < $1.priority }?
            .action
        action?()
        return true
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(performCloseCommand(_:))
            || NSApp.keyWindow != nil
    }

    @objc private func performCloseCommand(_ sender: NSMenuItem) {
        guard NSApp.currentEvent?.isARepeat != true else { return }
        let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
        guard !routeClose(targetWindow: targetWindow) else { return }
        targetWindow?.performClose(sender)
    }

    /// The standard File ▸ Close, found by **what it does** rather than by the key it happens to
    /// carry.
    ///
    /// Searching for "the item with ⌘W" was the old rule, and it stopped working the moment
    /// another item declared ⌘W: the search found *that* item, and the real Close — which SwiftUI
    /// had silently stripped the key from — was left alone and keyless. `performClose:` is what the
    /// item is for, and nothing else in this menu bar does it.
    private static func commandWItem(in mainMenu: NSMenu) -> NSMenuItem? {
        let close = mainMenu.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first { $0.action == #selector(NSWindow.performClose(_:)) && !$0.isAlternate }
        // Put the key back if something took it. Read out of the running app on 2026-09-16: Close
        // had no key equivalent at all, so ⌘W matched a disabled "Close Tab" and closed nothing.
        if let close, close.keyEquivalent.lowercased() != "w" {
            close.keyEquivalent = "w"
            close.keyEquivalentModifierMask = .command
        }
        return close
    }
}

struct GlassCloseCommandTarget: NSViewRepresentable {
    let priority: Int
    let isEnabled: Bool
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView(frame: .zero)
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.update(
            priority: priority,
            isEnabled: isEnabled,
            action: action
        )
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        context.coordinator.update(
            priority: priority,
            isEnabled: isEnabled,
            action: action
        )
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: WindowReaderView, coordinator: Coordinator) {
        nsView.windowDidChange = nil
        coordinator.removeRegistration()
    }

    @MainActor
    final class Coordinator {
        private let id = UUID()
        private weak var window: NSWindow?
        private var priority = 0
        private var isEnabled = false
        private var action: @MainActor () -> Void = {}

        func attach(to window: NSWindow?) {
            self.window = window
            publish()
        }

        public func update(
            priority: Int,
            isEnabled: Bool,
            action: @escaping @MainActor () -> Void
        ) {
            self.priority = priority
            self.isEnabled = isEnabled
            self.action = action
            publish()
        }

        func removeRegistration() {
            GlassCloseCommandRouter.shared.remove(id: id)
        }

        private func publish() {
            GlassCloseCommandRouter.shared.update(
                id: id,
                window: window,
                priority: priority,
                isEnabled: isEnabled,
                action: action
            )
        }
    }

    @MainActor
    final class WindowReaderView: NSView {
        var windowDidChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange?(window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

#endif
