//
//  GlassConnectionsWindow.swift
//  Glass Power Tools — GlassConnectionUI
//
//  "Open Connections", said one way everywhere (W29b).
//
//  On the headset the Connections window is a window group keyed by one fixed value
//  (`App/GlassPowerToolsApp.swift`, `mainScene`), so that opening it again brings the one window
//  forward. But `openWindow(id: "main")` names no value, and SwiftUI answers a request with no
//  value from the group's `defaultValue` — the way it answers File ▸ New Window — which on
//  visionOS 27 opened a **second** Connections window every time ⚡ or "Open Connections" was
//  pressed. Asking for the value itself is what brings the existing window forward.
//
//  Here, in the module every capability already imports, so a capability can ask for the library
//  window without knowing how the app declares it.
//

import SwiftUI
import Observation

/// The one value the headset's Connections window shows, so opening it again brings it forward.
/// Its encoded form is what visionOS keeps for the window between launches: keep the `id` key.
public struct GlassConnectionsWindow: Codable, Hashable, Sendable {
    /// The Connections scene's id, on every platform.
    public static let sceneID = "main"

    public var id = "connections"

    public init() {}
}

public extension OpenWindowAction {
    /// Opens Connections, or brings the open one forward.
    ///
    /// On visionOS it asks for the window's value, which brings the existing window forward. On
    /// the Mac, iPad and iPhone the library is a plain `WindowGroup("Connections", id: "main")`
    /// that takes no value, so it is asked for by id alone; a value it does not take would open
    /// nothing.
    func openConnections() {
        #if os(visionOS)
        GlassConnectionsRequests.shared.asked()
        self(id: GlassConnectionsWindow.sceneID, value: GlassConnectionsWindow())
        #else
        self(id: GlassConnectionsWindow.sceneID)
        #endif
    }
}

/// Every "Open Connections" on the headset, counted (W39).
///
/// Idle, the Connections window becomes its own orb (`glassConnectionsIdleShrink` in the shell):
/// the same window, small, still on screen. Asking visionOS for a window that is already on
/// screen brings it forward and changes nothing else, so ⚡ or a terminal's Connections control
/// would leave the orb an orb. The window watches this count instead, and grows back into the
/// library when it moves.
@MainActor
@Observable
public final class GlassConnectionsRequests {
    public static let shared = GlassConnectionsRequests()

    /// How many times Connections has been asked for since launch.
    public private(set) var count = 0

    /// The same count, read without observing it: for a check made while SwiftUI builds a
    /// window's views, which must not redraw the app's scenes whenever Connections is asked for.
    @ObservationIgnored public private(set) var untrackedCount = 0

    private init() {}

    func asked() {
        count &+= 1
        untrackedCount = count
    }
}

public extension EnvironmentValues {
    /// True while the headset's Connections window stands as its orb (W39). The library keeps
    /// every view and all its state, out of sight; this takes the rest away with it, inside each
    /// tab, whose content is hosted on its own: the tab bar beside the window, the toolbar below
    /// it, what VoiceOver could find and what a pinch could reach.
    @Entry var glassLibraryOutOfSight = false
    /// True while a session window stands as its orb (`glassSessionOrb`, 2026-10-15): its window
    /// frame's title and controls go with it (`GlassNativeWindowFrame`).
    @Entry var glassWindowOutOfSight = false
    /// True inside the library's compact stack — a phone, a folded iPhone Duo, an iPad window as
    /// narrow as one — where a panel's detail is a push away rather than a column beside its list.
    /// A column's own width class cannot say this: an iPad's list column is compact in landscape
    /// too, beside the detail (measured 2026-10-12).
    @Entry var glassLibraryIsStacked = false
}
