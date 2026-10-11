//
//  DesktopViewport.swift
//  Glass Power Tools — GlassDesktop
//
//  W30 (owner, 2026-10-10, on Vision Pro over a mobile connection, sharing a Mac with two displays):
//  "I'd like two screens, independently controllable like a real desktop setup."
//
//  **One connection, several windows.** A desktop session (`DesktopSessionModel`) is the
//  connection: its transport, its framebuffer, the host's display layout, its cursor and
//  clipboard. A window onto it is a `DesktopViewport`: which display it shows, its zoom, pan and
//  tilt, its own settings (W25) and whether it is on screen. The desktop's own window
//  (`desktop-session`, keyed by the endpoint) has the session's primary viewport; a display window
//  (`desktop-display`, keyed by endpoint and display) has its own. Every window attaches its viewport
//  while it is open, and the session ends when the last one detaches — so closing one display's
//  window leaves the others connected.
//
//  **Pointer and keys** from a window go to the display it shows: a point in the window maps into
//  that display's rectangle of the framebuffer (`DesktopCoordinates.map(origin:)`, unchanged).
//  **The remote cursor** is drawn by whichever window's display it is on.
//
//  **What is fetched** is what is on screen: the session asks its transport only for the regions
//  of the displays that have a window on screen (`requestedRegions`), so a display whose window is
//  closed or in the background stops costing the network anything.
//

import Foundation
import Observation
import GlassConnectionKit
import GlassLayers
import GlassRDPTransport

/// Where a desktop window's own settings are kept on this device: the desktop's window, or one of
/// its display windows, each by display.
public struct DesktopWindowKey: Hashable, Sendable {
    public let endpoint: EndpointID
    /// Nil for the desktop's own window.
    public let display: UInt32?

    public init(endpoint: EndpointID, display: UInt32? = nil) {
        self.endpoint = endpoint; self.display = display
    }

    /// "<uuid>" for the desktop's window — the form W25 stored — and "<uuid>/display/<id>" for a
    /// display's.
    var storageKey: String {
        let id = endpoint.rawValue.uuidString
        return display.map { "\(id)/display/\($0)" } ?? id
    }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = parts.first, let id = UUID(uuidString: String(first)) else { return nil }
        switch parts.count {
        case 1: self.init(endpoint: EndpointID(rawValue: id))
        case 3 where parts[1] == "display":
            guard let display = UInt32(parts[2]) else { return nil }
            self.init(endpoint: EndpointID(rawValue: id), display: display)
        default: return nil
        }
    }
}

/// The value a display window is opened with: the desktop and the display it starts on.
public struct DesktopDisplayWindowValue: Codable, Hashable, Sendable {
    public let endpoint: UUID
    public let display: UInt32

    public init(endpoint: UUID, display: UInt32) {
        self.endpoint = endpoint; self.display = display
    }
}

/// What a desktop does with a host's several displays.
public enum DesktopDisplayWindows: String, Codable, CaseIterable, Sendable {
    /// One window, showing every display or the one chosen in it.
    case oneWindow
    /// A window for each display, opened when the desktop connects.
    case windowPerDisplay

    public var title: String {
        switch self {
        case .oneWindow: "One Window"
        case .windowPerDisplay: "A Window for Each Display"
        }
    }

    /// Where windows float side by side, each display gets its own; elsewhere one window shows them.
    static var standard: DesktopDisplayWindows {
        #if os(visionOS)
        .windowPerDisplay
        #else
        .oneWindow
        #endif
    }
}

/// One window onto a desktop session.
@MainActor @Observable
public final class DesktopViewport: Identifiable {
    public let id = UUID()
    public let key: DesktopWindowKey
    /// Nil shows the whole framebuffer; otherwise the display shown.
    public var selectedScreenID: UInt32? {
        didSet { if selectedScreenID != oldValue { session?.viewportDidChange() } }
    }
    /// This window's drawing: its mode, opacity and key colour resolved from its settings (`apply`),
    /// and its own zoom, pan and tilt.
    public var presentation = PresentationSettings()
    /// This window's own settings over All Desktops' (W25), kept on this device for this window.
    public var windowSettings: GlassWindowOverrides {
        didSet { if windowSettings != oldValue { store?.save(windowSettings, for: key) } }
    }
    /// How a touch screen drives the pointer in this window.
    public var pointerMode = DesktopPointerMode.trackpad
    /// A window in the background asks for nothing.
    public var isOnScreen = true {
        didSet { if isOnScreen != oldValue { session?.viewportDidChange() } }
    }
    /// The window resizes only in its display's shape (W38), from its settings (`apply`).
    public var keepsProportions = true
    @ObservationIgnored private let store: DesktopWindowSettingsStore?
    @ObservationIgnored weak var session: DesktopSessionModel?

    /// The desktop's own window.
    public var isPrimary: Bool { key.display == nil }

    init(key: DesktopWindowKey, store: DesktopWindowSettingsStore?) {
        self.key = key
        self.store = store
        self.windowSettings = store?.settings(for: key) ?? GlassWindowOverrides()
        self.selectedScreenID = key.display
    }
}

/// The rules between a host's displays and the windows showing them; pure, so they are tested
/// without a window.
enum DesktopDisplayLayout {
    /// The part of the framebuffer a window shows: its display, or all of it when it shows every
    /// display, or when its display is not (or no longer) in the layout.
    static func region(screenID: UInt32?, screens: [GlassRemoteScreen], framebuffer: DesktopSize) -> DesktopRegion {
        guard let id = screenID, let screen = screens.first(where: { $0.id == id }),
              screen.x >= 0, screen.y >= 0, screen.width > 0, screen.height > 0,
              screen.x + screen.width <= framebuffer.width, screen.y + screen.height <= framebuffer.height else {
            return .whole(width: framebuffer.width, height: framebuffer.height)
        }
        return .init(origin: .init(x: screen.x, y: screen.y), size: DesktopSize(width: screen.width, height: screen.height))
    }

    /// What to ask the server for: nil for everything (a window shows every display, or no window
    /// is known), empty for nothing (no window on screen), otherwise each on-screen window's display.
    static func requestedRegions(onScreen: [DesktopRegion], windows: Int, framebuffer: DesktopSize?) -> [GlassRemoteRegion]? {
        guard windows > 0 else { return nil }
        guard !onScreen.isEmpty else { return [] }
        guard let framebuffer else { return nil }
        let whole = DesktopRegion.whole(width: framebuffer.width, height: framebuffer.height)
        if onScreen.contains(whole) { return nil }
        var regions: [GlassRemoteRegion] = []
        for region in onScreen {
            let value = GlassRemoteRegion(x: region.origin.x, y: region.origin.y,
                                          width: region.size.width, height: region.size.height)
            if !regions.contains(value) { regions.append(value) }
        }
        return regions
    }

    /// The display a desktop's own window shows when each display has a window: the main one.
    static func mainScreen(_ screens: [GlassRemoteScreen]) -> GlassRemoteScreen? {
        screens.first(where: \.isPrimary) ?? screens.min { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    /// "Main Display", "Display 2": as the host's own layout lists them.
    static func name(of id: UInt32?, in screens: [GlassRemoteScreen]) -> String {
        guard let id else { return "All Displays" }
        guard let index = screens.firstIndex(where: { $0.id == id }) else { return "Display" }
        return screens[index].isPrimary ? "Main Display" : "Display \(index + 1)"
    }
}
