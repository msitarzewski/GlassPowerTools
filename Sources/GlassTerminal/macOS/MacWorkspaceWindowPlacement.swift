//
//  MacWorkspaceWindowPlacement.swift
//  Glass Power Tools — GlassTerminal
//
//  W12 (2026-10-09): after an update the terminal windows came back with the right tabs at
//  SwiftUI's default place. The owner: "Windows restored, just not position." Each window's record
//  now keeps where it was — its frame, the display it was on, and whether it was in full screen —
//  and a window the app reopens from its record goes back there, once, as it first appears.
//
//  Placed from AppKit, once, because SwiftUI can't: `defaultWindowPlacement` is told only the
//  content's size and the default display (`WindowLayoutRoot`, `WindowPlacementContext`), never
//  which window — which value — it is placing, so every terminal window would get one answer.
//  The scene declines restoration, so SwiftUI gives these windows no frame autosave name. It still
//  writes `NSWindow Frame workspace-AppWindow-1`, but a new window opens at SwiftUI's own place and
//  a frame set here is kept (a scratch app, 2026-10-09). Rule 62 holds: SwiftUI owns the window;
//  this is one deliberate act as it appears, then only reading where it is.
//

#if os(macOS)
import AppKit
import ColorSync
import Foundation

/// Where a terminal window was (W12): saved in its own record, given back once when the app
/// reopens the window.
struct MacWorkspaceWindowPlacement: Codable, Equatable, Sendable {
    /// In AppKit's screen coordinates. In full screen, the frame the window had before it went in.
    var frame: CGRect
    /// The display it was on (`MacWorkspaceDisplay.id`), when that display could be named.
    var display: String?
    /// That display's frame at the time: a display moved in the arrangement takes its windows
    /// with it.
    var displayFrame: CGRect?
    var isFullScreen = false

    /// Read from a record anything could have written: finite, a size a window can have, and a
    /// display name of a sensible length; nil otherwise.
    func validated() -> MacWorkspaceWindowPlacement? {
        func isUsable(_ rect: CGRect) -> Bool {
            let values = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
            return values.allSatisfy(\.isFinite)
                && abs(rect.origin.x) <= 1_000_000 && abs(rect.origin.y) <= 1_000_000
                && (1...100_000).contains(rect.size.width) && (1...100_000).contains(rect.size.height)
        }
        guard isUsable(frame), displayFrame.map(isUsable) ?? true, (display?.count ?? 0) <= 64 else { return nil }
        return self
    }

    /// Where the window opens again among `displays`, the main display (the one with the menu
    /// bar) first; nil with none.
    ///
    /// On its own display, exactly where it was, moved with the display if the arrangement
    /// changed — fitted onto that display if it no longer fits there, rather than sent to another.
    /// With its display gone, exactly where it was if that still fits a display; otherwise fitted
    /// onto the main display, at the same place from the top-left. Fitted: whole within the
    /// display's visible area, shrunk only where it is larger than that area.
    func restoredFrame(on displays: [MacWorkspaceDisplay]) -> CGRect? {
        guard let main = displays.first else { return nil }
        if let display, let own = displays.first(where: { $0.id == display }) {
            let moved = shifted(onto: own)
            return Self.fits(moved, on: own) ? moved : Self.fit(moved, onto: own)
        }
        if displays.contains(where: { Self.fits(frame, on: $0) }) { return frame }
        return Self.fit(shifted(onto: main), onto: main)
    }

    /// The frame at the same place from the top-left of `target` as it had on its own display.
    private func shifted(onto target: MacWorkspaceDisplay) -> CGRect {
        guard let displayFrame else { return frame }
        return frame.offsetBy(dx: target.frame.minX - displayFrame.minX, dy: target.frame.maxY - displayFrame.maxY)
    }

    /// Whole on the display, its title bar below the menu bar; a point of slack for rounding.
    static func fits(_ rect: CGRect, on display: MacWorkspaceDisplay) -> Bool {
        display.frame.insetBy(dx: -1, dy: -1).contains(rect) && rect.maxY <= display.visibleFrame.maxY + 1
    }

    static func fit(_ rect: CGRect, onto display: MacWorkspaceDisplay) -> CGRect {
        let area = display.visibleFrame
        let width = min(rect.width, area.width)
        let height = min(rect.height, area.height)
        let x = min(max(rect.minX, area.minX), area.maxX - width)
        let top = min(max(rect.maxY, area.minY + height), area.maxY)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    /// Quitting: every terminal window on screen saves where it is. One in full screen keeps the
    /// frame it had before, which it saved as it went in.
    static func saveAll(registry: MacWorkspacePreviewRegistry,
                        displayOf: @MainActor (NSWindow) -> MacWorkspaceDisplay? = MacWorkspaceDisplay.of) {
        for shown in registry.shownWindows {
            let fullScreen = shown.window.styleMask.contains(.fullScreen)
            let frame = fullScreen ? (shown.controller.placement?.frame ?? shown.window.frame) : shown.window.frame
            shown.controller.savePlacement(MacWorkspaceWindowPlacement(
                frame: frame, on: displayOf(shown.window), isFullScreen: fullScreen))
        }
    }
}

extension MacWorkspaceWindowPlacement {
    init(frame: CGRect, on display: MacWorkspaceDisplay?, isFullScreen: Bool) {
        self.init(frame: frame, display: display?.id, displayFrame: display?.frame, isFullScreen: isFullScreen)
    }
}

/// A display as placement sees it: an `NSScreen`, or a stand-in in tests.
struct MacWorkspaceDisplay: Equatable, Sendable {
    /// The display's UUID, which ColorSync derives from its vendor, model and serial number, so
    /// the same display keeps it across reconnects and restarts. nil when it has none.
    var id: String?
    var frame: CGRect
    var visibleFrame: CGRect
}

extension MacWorkspaceDisplay {
    init(_ screen: NSScreen) {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let uuid = number.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
        self.init(id: uuid.map { CFUUIDCreateString(nil, $0) as String },
                  frame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    /// The displays connected now, the main one — the one with the menu bar — first.
    static func connected() -> [MacWorkspaceDisplay] {
        NSScreen.screens.map(MacWorkspaceDisplay.init)
    }

    /// The display a window is on, or nil when it is on none.
    static func of(_ window: NSWindow) -> MacWorkspaceDisplay? {
        window.screen.map(MacWorkspaceDisplay.init)
    }
}

/// Keeps a terminal window's place in its record (W12). A window reopened from its record goes
/// back where it was, once, as it first appears; after that its place is saved when a move or a
/// resize settles — not at every step of one — and as it goes in and out of full screen.
/// Quitting saves every window's place as well (`MacWorkspaceWindowPlacement.saveAll`).
final class MacWorkspaceWindowPlacementTracker: NSObject {
    private weak var window: NSWindow?
    private weak var controller: MacWorkspaceWindowController?
    private var pendingSave: Task<Void, Never>?
    /// Going in or out of full screen: the frames on the way are AppKit's animation.
    private var changingFullScreen = false
    private let settleDelay: Duration
    private let displays: @MainActor () -> [MacWorkspaceDisplay]
    private let displayOf: @MainActor (NSWindow) -> MacWorkspaceDisplay?
    private let enterFullScreen: @MainActor (NSWindow) -> Void

    init(settleDelay: Duration = .milliseconds(500),
         displays: @escaping @MainActor () -> [MacWorkspaceDisplay] = MacWorkspaceDisplay.connected,
         displayOf: @escaping @MainActor (NSWindow) -> MacWorkspaceDisplay? = MacWorkspaceDisplay.of,
         enterFullScreen: @escaping @MainActor (NSWindow) -> Void = MacWorkspaceWindowPlacementTracker.enterFullScreen) {
        self.settleDelay = settleDelay
        self.displays = displays
        self.displayOf = displayOf
        self.enterFullScreen = enterFullScreen
        super.init()
    }

    /// Once the window is on screen: AppKit takes it into a Space of its own.
    static func enterFullScreen(_ window: NSWindow) {
        DispatchQueue.main.async {
            if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
    }

    /// Starts keeping `window`'s place in `controller`'s record. The first window shown for a
    /// controller reopened from its record goes back where it was; called again for the same
    /// window, nothing happens.
    func track(_ window: NSWindow, controller: MacWorkspaceWindowController) {
        guard self.window !== window || self.controller !== controller else { return }
        stop()
        self.window = window
        self.controller = controller
        if let saved = controller.takePlacementToRestore() {
            if let frame = saved.restoredFrame(on: displays()) { window.setFrame(frame, display: true) }
            if saved.isFullScreen { enterFullScreen(window) }
        }
        let observed: [(Notification.Name, Selector)] = [
            (NSWindow.didMoveNotification, #selector(frameDidChange(_:))),
            (NSWindow.didResizeNotification, #selector(frameDidChange(_:))),
            (NSWindow.didChangeScreenNotification, #selector(frameDidChange(_:))),
            (NSWindow.didEndLiveResizeNotification, #selector(liveResizeDidEnd(_:))),
            (NSWindow.willEnterFullScreenNotification, #selector(willEnterFullScreen(_:))),
            (NSWindow.didEnterFullScreenNotification, #selector(didEnterFullScreen(_:))),
            (NSWindow.willExitFullScreenNotification, #selector(willExitFullScreen(_:))),
            (NSWindow.didExitFullScreenNotification, #selector(didExitFullScreen(_:))),
        ]
        for (name, selector) in observed {
            NotificationCenter.default.addObserver(self, selector: selector, name: name, object: window)
        }
    }

    /// A move or resize is waiting to settle before it is saved.
    var isWaitingToSave: Bool { pendingSave != nil }

    /// The window closed: nothing more is saved for it.
    func stop() {
        pendingSave?.cancel()
        pendingSave = nil
        NotificationCenter.default.removeObserver(self)
        window = nil
        controller = nil
        changingFullScreen = false
    }

    @objc private func frameDidChange(_ notification: Notification) {
        guard !changingFullScreen else { return }
        pendingSave?.cancel()
        let delay = settleDelay
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    @objc private func liveResizeDidEnd(_ notification: Notification) { save() }

    /// Its frame is still the one it had before full screen, which is the one to come back to.
    @objc private func willEnterFullScreen(_ notification: Notification) {
        save(fullScreen: true)
        changingFullScreen = true
    }

    @objc private func didEnterFullScreen(_ notification: Notification) { changingFullScreen = false }
    @objc private func willExitFullScreen(_ notification: Notification) { changingFullScreen = true }

    @objc private func didExitFullScreen(_ notification: Notification) {
        changingFullScreen = false
        save(fullScreen: false)
    }

    /// Saves where the window is now. In full screen, outside a change into or out of it,
    /// nothing: its frame is the display's.
    private func save(fullScreen: Bool? = nil) {
        pendingSave?.cancel()
        pendingSave = nil
        guard let window, let controller else { return }
        if fullScreen == nil, changingFullScreen || window.styleMask.contains(.fullScreen) { return }
        controller.savePlacement(MacWorkspaceWindowPlacement(
            frame: window.frame, on: displayOf(window), isFullScreen: fullScreen ?? false))
    }
}
#endif
