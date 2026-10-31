//
//  GlassDebugging.swift
//  Glass Power Tools — GlassShell
//
//  Diagnostics kept in the app but out of everyone's way (the owner, 2026-10-31: "make the debug panel
//  toggleable so we can keep it but it's available when we need it", and "put the toggle in a
//  debugging section in window's settings"). Holding the version line in Settings ▸ About shows them on
//  this device, and holding it again hides them: Settings ▸ Terminal ▸ Diagnostics and a terminal
//  window's Debugging section. Never synced.
//

import Foundation

public enum GlassDebugging {
    /// Whether this device shows the diagnostics, in `GlassUITestRun.settingsDefaults`.
    public static let revealedKey = "settings.debuggingRevealed"
}
