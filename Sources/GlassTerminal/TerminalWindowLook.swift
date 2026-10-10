//
//  TerminalWindowLook.swift
//  Glass Power Tools — GlassTerminal
//
//  W20 (owner, 2026-10-09, in a Mac terminal window): "I was testing to see if there was a way to
//  give a color/tint to the tab group." The owner chose that **the window owns its look**: set from
//  any tab's Settings ▸ This Window, every tab in the window shows it; new tabs and tabs moved in
//  take it; it is kept with the window, so it survives a relaunch, and a saved Workgroup carries it.
//
//  W22 widened the look to every setting a window can override (`TerminalWindowSettings`); the
//  canvas's part — opacity, blur, frost, tint, interactive glass — is resolved here.
//
//  Where a window's settings live: a Mac terminal window's controller
//  (`MacWorkspaceWindowController.windowSettings`, saved in its record), and a workgroup on Vision
//  Pro, iPad and iPhone (`TerminalWorkgroup.windowSettings`, kept in the reopen list). A saved
//  Workgroup's is `LayoutPreset.windowSettings`, which syncs (D51). Everything drawn in the window
//  reads them from the environment (`\.glassWindowOverrides`).
//

import SwiftUI
import GlassLayers

/// What one terminal's canvas is drawn with (W20): its window's settings, field by field, over the
/// terminal settings. A field the window leaves unset follows the setting.
struct TerminalLook: Equatable {
    /// Vision Pro's frost material: `ultraThin`, `thin`, `regular` or `thick`.
    let frost: String
    /// The canvas's opacity and blur, each in 0…1.
    let glass: TerminalGlassAppearance
    let interactiveGlass: Bool
    /// "None", a name ("Blue") or a hex colour (`#FF9500`), as `TerminalGlassTint` reads it.
    let tint: String
    /// The blur the window itself sets, or nil. On Vision Pro a terminal's canvas adds frost only
    /// when its window asks: the window has no glass of its own there (`.plain`), and none is added
    /// around it at the settings' level (the owner: "I like it just the way it is").
    let windowBlur: Double?

    var opacity: Double { glass.opacity }
    var blur: Double { glass.blur }
    var tintColor: Color? { TerminalGlassTint.color(for: tint) }

    var material: Material {
        switch frost {
        case "thin": .thinMaterial
        case "regular": .regularMaterial
        case "thick": .thickMaterial
        default: .ultraThinMaterial
        }
    }

    /// The window's values where it sets them, the settings' elsewhere. Opacity, blur and frost
    /// are Appearance's (`GlassLayerSettings`): the terminal's settings are views over them.
    init(window: GlassWindowOverrides, frost: String, opacity: Double, blur: Double,
         interactiveGlass: Bool, tint: String) {
        self.frost = window[GlassLayerSettings.material]?.rawValue ?? frost
        self.glass = TerminalGlassAppearance.resolved(globalOpacity: opacity, globalBlur: blur, window: window)
        self.interactiveGlass = window.value(of: TerminalWindowSettings.interactiveGlass, over: interactiveGlass)
        self.tint = window.value(of: TerminalWindowSettings.tint, over: tint)
        self.windowBlur = window[GlassLayerSettings.frost]
    }

    /// A terminal in a window with these settings. Read in a view's body, it follows both: the
    /// settings are observable, and so is whatever holds the window's.
    static func resolved(_ window: GlassWindowOverrides, settings: SettingsManager) -> TerminalLook {
        TerminalLook(window: window, frost: settings.glassFrost, opacity: settings.windowOpacity,
                     blur: settings.blurBackground, interactiveGlass: settings.interactiveGlass,
                     tint: settings.glassTint)
    }
}

/// How strongly a tint colours a terminal's canvas, wherever a canvas is drawn.
enum TerminalCanvasTint {
    /// The tint's own strength, whatever the theme's opacity (W20). It was 12% of the opacity, so
    /// at the starting opacity of 0% — the transparent, frosted terminal — a tint chosen to tell
    /// one window from another showed nothing at all. A tint is a choice to colour the glass; a
    /// completely clear terminal is opacity and blur at zero with no tint.
    static func strength(canvasOpacity: Double) -> Double {
        0.12
    }
}

// MARK: - Which window a terminal is in

private struct TerminalWorkgroupIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// Vision Pro, iPad and iPhone: the workgroup a terminal is drawn in, whose settings This
    /// Window edits. The settings themselves reach the terminal as `\.glassWindowOverrides`, set by
    /// the workgroup's view (`VisionTerminalWorkgroupView`) for every terminal, sheet and card in it.
    var terminalWorkgroupID: UUID? {
        get { self[TerminalWorkgroupIDKey.self] }
        set { self[TerminalWorkgroupIDKey.self] = newValue }
    }
}

/// The settings of the window a terminal session is in, wherever that window is: a Mac terminal
/// window's (from those on screen), or its workgroup's. For a surface outside the window — the
/// Files browser's remote editor — that still wants to look like it.
@MainActor
enum TerminalWindowLooks {
    static func settings(ofWindowHolding sessionID: UUID, sessionManager: SessionManager) -> GlassWindowOverrides {
        #if os(macOS)
        MacWorkspacePreviewRegistry.shared.windowSettings(ofWindowHolding: sessionID)
        #else
        sessionManager.windowSettings(ofWorkgroupHolding: sessionID)
        #endif
    }
}
