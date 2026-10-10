//
//  TerminalWindowLook.swift
//  Glass Power Tools — GlassTerminal
//
//  W20 (owner, 2026-10-09, in a Mac terminal window): "I was testing to see if there was a way to
//  give a color/tint to the tab group." The owner chose that **the window owns its look**: set from
//  any tab's Settings ▸ Overrides, every tab in the window shows it; new tabs and tabs moved in take
//  it; it is kept with the window, so it survives a relaunch, and a saved Workgroup carries it.
//
//  Where a look lives: a Mac terminal window's controller (`MacWorkspaceWindowController.look`,
//  saved in its record), and a workgroup on Vision Pro, iPad and iPhone (`TerminalWorkgroup.look`,
//  kept in the reopen list). A saved Workgroup's is `LayoutPreset.look`, which syncs (D51).
//
//  How a terminal is drawn: its window's look, field by field, over the terminal settings — the
//  same resolution for a Mac pane (SSH or local), a headset or iPad tab, a grid or carousel card
//  and the Mac's overview pictures, so a window's tabs always agree.
//

import SwiftUI

/// What one terminal is drawn with (W20): its window's look, field by field, over the terminal
/// settings. A field the look leaves unset follows the setting.
struct TerminalLook: Equatable {
    /// Vision Pro's frost material: `ultraThin`, `thin`, `regular` or `thick`.
    let frost: String
    /// The canvas's opacity and blur, each in 0…1.
    let glass: TerminalGlassAppearance
    let interactiveGlass: Bool
    /// "None", a name ("Blue") or a hex colour (`#FF9500`), as `TerminalGlassTint` reads it.
    let tint: String
    /// The blur the window's own look sets, or nil. On Vision Pro the window's backdrop already
    /// frosts at the settings' level, so a terminal's canvas adds frost only when its window asks.
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

    /// `look`'s fields where it sets them, the settings' elsewhere.
    init(look: TerminalSessionOverride?, frost: String, opacity: Double, blur: Double,
         interactiveGlass: Bool, tint: String) {
        self.frost = look?.glassFrost ?? frost
        self.glass = TerminalGlassAppearance.resolved(globalOpacity: opacity, globalBlur: blur, look: look)
        self.interactiveGlass = look?.interactiveGlass ?? interactiveGlass
        self.tint = look?.glassTint ?? tint
        self.windowBlur = look?.blurBackground
    }

    /// A terminal in a window with `look`, under these settings. Read in a view's body, it follows
    /// both: the settings are observable, and so is whatever holds the look.
    static func resolved(_ look: TerminalSessionOverride?, settings: SettingsManager) -> TerminalLook {
        TerminalLook(look: look, frost: settings.glassFrost, opacity: settings.windowOpacity,
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

/// Vision Pro, iPad and iPhone: the workgroup a terminal is drawn in, and its look now (W20).
/// A value, so a terminal's view is drawn again only when its window's look changes; set by the
/// workgroup's view (`VisionTerminalWorkgroupView`) for every terminal, sheet and card in it.
struct TerminalWorkgroupLook: Equatable {
    let workgroupID: UUID
    let look: TerminalSessionOverride?
}

private struct TerminalWorkgroupLookKey: EnvironmentKey {
    static let defaultValue: TerminalWorkgroupLook? = nil
}

extension EnvironmentValues {
    var terminalWorkgroupLook: TerminalWorkgroupLook? {
        get { self[TerminalWorkgroupLookKey.self] }
        set { self[TerminalWorkgroupLookKey.self] = newValue }
    }
}

/// The look of the window a terminal session is in, wherever that window is: a Mac terminal
/// window's (from those on screen), or its workgroup's. For a surface outside the window — the
/// Files browser's remote editor — that still wants to look like it.
@MainActor
enum TerminalWindowLooks {
    static func look(ofWindowHolding sessionID: UUID, sessionManager: SessionManager) -> TerminalSessionOverride? {
        #if os(macOS)
        MacWorkspacePreviewRegistry.shared.look(ofWindowHolding: sessionID)
        #else
        sessionManager.look(ofWorkgroupHolding: sessionID)
        #endif
    }
}
