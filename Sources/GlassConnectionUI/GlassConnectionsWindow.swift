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
        self(id: GlassConnectionsWindow.sceneID, value: GlassConnectionsWindow())
        #else
        self(id: GlassConnectionsWindow.sceneID)
        #endif
    }
}
