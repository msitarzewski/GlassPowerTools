//
//  TerminalWindowSettings.swift
//  Glass Power Tools — GlassTerminal
//
//  W22 (owner, 2026-10-10, on the Vision Pro): "the original idea was that anything in the system
//  settings could be overridden per window." A terminal window keeps a `GlassWindowOverrides`
//  (GlassLayers): its glass, which is Appearance's own (`GlassLayerSettings`), and every terminal
//  setting that can sensibly differ between windows — theme, font, cursor, bell, scrollback, tint
//  and interactive glass. Each resolves as the window's value, else the setting's, for every tab
//  in the window, and the window keeps them where it kept W20's look: the Mac window record, the
//  workgroup and its reopen record, and a saved Workgroup.
//
//  W20's look is part of it. Its five fields — opacity, blur, frost, interactive glass and tint —
//  are five of these settings, and records still carry them under `look`, in W20's format, so a
//  build from before W22 reads them; the rest go under `windowSettings`, which such a build
//  ignores (`TerminalWindowSettingsCoding`).
//
//  Not per window, and why:
//  - Initial size (columns × rows): it only sizes a terminal before it is drawn — and on the Mac the
//    window a new terminal opens in. A window that exists already has its size, a reopened one its
//    place (W12), and a server can set its own.
//  - Connection, security and machine settings (auto-reconnect, confirm before closing, host-key
//    verification, trusted keys, Tailscale, SSH keys, local shell and folder, local tmux,
//    recordings, iCloud sync, snippets): they belong to a connection, a server or this device, not
//    to how a window looks or behaves; one window can't verify a host differently from another.
//

import SwiftUI
import GlassLayers
import GlassTerminalEmulator

/// The terminal settings a window can override (W22), each under a stable key: stored with the
/// window, synced with a saved Workgroup. The window's glass is Appearance's (`GlassLayerSettings`).
nonisolated enum TerminalWindowSettings {
    // The canvas, beside Appearance's opacity, frost (the terminal's "Blur") and material.
    static let tint = GlassWindowSetting<String>("terminal.tint", title: "Glass Tint") {
        $0.count <= 64 ? $0 : nil
    }
    static let interactiveGlass = GlassWindowSetting<Bool>("terminal.interactiveGlass", title: "Interactive Glass")

    // Text.
    /// A theme from the library, by identifier. One not on this device draws with All Terminals'.
    static let theme = GlassWindowSetting<String>("terminal.theme", title: "Theme") { raw in
        guard let id = UUID(uuidString: raw) else { return nil }
        return (id == TerminalTheme.legacyDefaultID ? TerminalTheme.defaultID : id).uuidString
    }
    static let fontFamily = GlassWindowSetting<String>("terminal.fontFamily", title: "Font Family") { name in
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= TerminalTheme.maximumFontNameLength,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return trimmed
    }
    static let fontSize = GlassWindowSetting<Double>("terminal.fontSize", title: "Font Size") { size in
        guard size.isFinite else { return nil }
        return min(Double(TerminalTheme.maximumFontSize), max(Double(TerminalTheme.minimumFontSize), size.rounded()))
    }
    static let cursorStyles = ["Block", "Underline", "Bar"]
    static let cursorStyle = GlassWindowSetting<String>("terminal.cursorStyle", title: "Cursor Style") {
        cursorStyles.contains($0) ? $0 : nil
    }
    static let blinkingCursor = GlassWindowSetting<Bool>("terminal.blinkingCursor", title: "Blinking Cursor")
    /// Show previews (the Mac's, 2026-10-16): `TerminalPathPreviews`, by its raw value.
    static let pathPreviews = GlassWindowSetting<String>("terminal.pathPreviews", title: "Show Previews") {
        TerminalPathPreviews(rawValue: $0) == nil ? nil : $0
    }
    /// When the window is resized (D75, 2026-10-16): `TerminalResizeBehavior`, by its raw value.
    /// The window's bar switches it for the window.
    static let whenResized = GlassWindowSetting<String>("terminal.whenResized", title: "When Resized") {
        TerminalResizeBehavior(rawValue: $0) == nil ? nil : $0
    }

    // Behaviour.
    static let bell = GlassWindowSetting<Bool>("terminal.bell", title: "Bell")
    static let visualBell = GlassWindowSetting<Bool>("terminal.visualBell", title: "Visual Bell")
    static let keepsScrollback = GlassWindowSetting<Bool>("terminal.keepsScrollback", title: "Keep Scrollback")
    static let scrollbackLines = GlassWindowSetting<Int>("terminal.scrollbackLines", title: "Scrollback Lines") {
        min(100_000, max(1_000, $0))
    }
    /// Vision Pro (the owner, 2026-10-15: "add Auto-focus on activity to This Window"): while a
    /// terminal in the window prints, the grid and carousel bring it forward and the window's orb
    /// pulses. Unset, the window follows the saved Workgroup it was opened from, else is off.
    static let autoFocusOnActivity = GlassWindowSetting<Bool>("terminal.autoFocusOnActivity", title: "Auto-focus on Activity")

    /// The settings W20's look carried, which records keep under `look` in its format.
    static var lookKeys: Set<String> {
        GlassLayerSettings.keys.union([tint.key, interactiveGlass.key])
    }
}

// MARK: - W20's look, as a window's settings

nonisolated extension TerminalSessionOverride {
    /// W20's look as a window's settings: opacity, blur and frost are the window's Appearance, tint
    /// and interactive glass the terminal's own. Every value it held keeps its meaning; a frost that
    /// was none of the four materials drew as Light and now follows Appearance's.
    var windowSettings: GlassWindowOverrides {
        var settings = GlassWindowOverrides()
        settings[GlassLayerSettings.opacity] = windowOpacity
        settings[GlassLayerSettings.frost] = blurBackground
        settings[GlassLayerSettings.material] = glassFrost.flatMap(GlassLayerMaterial.init(rawValue:))
        settings[TerminalWindowSettings.tint] = glassTint
        settings[TerminalWindowSettings.interactiveGlass] = interactiveGlass
        return settings
    }

    /// The part of a window's settings W20's look carries, in its format, so a build from before
    /// W22 still draws the window as it was; nil when the window sets none of them.
    init?(windowSettings settings: GlassWindowOverrides) {
        let look = TerminalSessionOverride(
            glassFrost: settings[GlassLayerSettings.material]?.rawValue,
            windowOpacity: settings[GlassLayerSettings.opacity],
            blurBackground: settings[GlassLayerSettings.frost],
            interactiveGlass: settings[TerminalWindowSettings.interactiveGlass],
            glassTint: settings[TerminalWindowSettings.tint])
        guard !look.isEmpty else { return nil }
        self = look
    }
}

/// How a record keeps a window's settings (W22): W20's five under `look`, in W20's format, which
/// every build since W20 reads; everything else under `windowSettings`, which earlier builds
/// ignore, as they ignore any key they don't know. Each part is read leniently: one that can't be
/// read costs the record that part, never the record. A build from before W22 that saves the record
/// again keeps the look and drops the rest, as one from before W20 dropped the look (D57).
nonisolated enum TerminalWindowSettingsCoding {
    static func decode<Key: CodingKey>(from container: KeyedDecodingContainer<Key>,
                                       look lookKey: Key, settings settingsKey: Key) -> GlassWindowOverrides {
        let rest = GlassWindowOverrides.lenientlyDecoded(from: container, forKey: settingsKey)
            .removing(TerminalWindowSettings.lookKeys)
        let look = TerminalSessionOverride.lenientlyDecoded(from: container, forKey: lookKey)?.windowSettings
        return rest.merging(look ?? GlassWindowOverrides())
    }

    static func encode<Key: CodingKey>(_ settings: GlassWindowOverrides, into container: inout KeyedEncodingContainer<Key>,
                                       look lookKey: Key, settings settingsKey: Key) throws {
        try container.encodeIfPresent(TerminalSessionOverride(windowSettings: settings), forKey: lookKey)
        try container.encodeIfNotEmpty(settings.removing(TerminalWindowSettings.lookKeys), forKey: settingsKey)
    }
}

// MARK: - What a terminal in a window uses

/// Everything a terminal is drawn and behaves with (W22): each of its window's settings over the
/// terminal setting it overrides. The same for a Mac pane (SSH or local), a headset or iPad tab, a
/// grid or carousel card and the Mac's overview pictures, so a window's tabs always agree.
struct TerminalWindowProfile: Equatable {
    let look: TerminalLook
    /// The theme, with the window's font family and size over its own.
    let theme: TerminalTheme
    let cursorStyle: String
    let blinkingCursor: Bool
    /// Lines kept; zero when scrollback is off.
    let scrollbackLines: Int
    let bellEnabled: Bool
    let visualBell: Bool
    let pathPreviews: TerminalPathPreviews
    /// Under `.scale` the terminal keeps its rows and columns and its text follows the window (D75).
    let whenResized: TerminalResizeBehavior
    /// What the window shows behind its text, its glow and its palette (D84). The palette is
    /// already in `theme`.
    let lookStyle: TerminalLookStyle

    var runtimeSettings: SwiftTermRuntimeSettings {
        SwiftTermRuntimeSettings(cursorStyle: cursorStyle, blinkingCursor: blinkingCursor,
                                 scrollbackLines: scrollbackLines, pathPreviews: pathPreviews)
    }

    init(window: GlassWindowOverrides, look: TerminalLook, theme global: TerminalTheme, library: TerminalThemeLibrary,
         cursorStyle: String, blinkingCursor: Bool, keepsScrollback: Bool, scrollbackLines: Int,
         bellEnabled: Bool, visualBell: Bool, pathPreviews: TerminalPathPreviews = .mouseover,
         whenResized: TerminalResizeBehavior = .changeGrid) {
        self.look = look
        self.theme = Self.theme(window, over: global, library: library)
        self.cursorStyle = window.value(of: TerminalWindowSettings.cursorStyle, over: cursorStyle)
        self.blinkingCursor = window.value(of: TerminalWindowSettings.blinkingCursor, over: blinkingCursor)
        self.scrollbackLines = window.value(of: TerminalWindowSettings.keepsScrollback, over: keepsScrollback)
            ? window.value(of: TerminalWindowSettings.scrollbackLines, over: scrollbackLines) : 0
        self.bellEnabled = window.value(of: TerminalWindowSettings.bell, over: bellEnabled)
        self.visualBell = window.value(of: TerminalWindowSettings.visualBell, over: visualBell)
        self.pathPreviews = TerminalPathPreviews(rawValue: window.value(of: TerminalWindowSettings.pathPreviews,
                                                                        over: pathPreviews.rawValue)) ?? pathPreviews
        self.whenResized = TerminalResizeBehavior(rawValue: window.value(of: TerminalWindowSettings.whenResized,
                                                                         over: whenResized.rawValue)) ?? whenResized
        self.lookStyle = TerminalLookStyle.resolved(window)
    }

    /// A terminal in a window with `window`'s settings. Read in a view's body, it follows both:
    /// the settings are observable, and so is whatever holds the window's.
    static func resolved(_ window: GlassWindowOverrides, settings: SettingsManager) -> TerminalWindowProfile {
        TerminalWindowProfile(window: window, look: TerminalLook.resolved(window, settings: settings),
                              theme: settings.currentTheme, library: settings.themeLibrary,
                              cursorStyle: settings.cursorStyle, blinkingCursor: settings.blinkingCursor,
                              keepsScrollback: settings.saveScrollback, scrollbackLines: settings.maxScrollbackLines,
                              bellEnabled: settings.bellEnabled, visualBell: settings.visualBell,
                              pathPreviews: settings.pathPreviews, whenResized: settings.whenResized)
    }

    /// The window's theme — one from the library, while the library has it — else `global`, with
    /// the window's font over the theme's.
    static func theme(_ window: GlassWindowOverrides, over global: TerminalTheme,
                      library: TerminalThemeLibrary) -> TerminalTheme {
        var theme = global
        if let id = window[TerminalWindowSettings.theme].flatMap(UUID.init(uuidString:)),
           let chosen = library.records.first(where: { $0.id == id && !$0.isDeleted })?.theme {
            theme = chosen
        }
        if let family = window[TerminalWindowSettings.fontFamily] { theme.fontName = family }
        if let size = window[TerminalWindowSettings.fontSize] { theme.fontSize = CGFloat(size) }
        // The window's text palette over the theme's colours (D84).
        if let phosphor = window[TerminalWindowSettings.phosphor] { theme = phosphor.applied(to: theme) }
        return theme
    }

    /// Whether the window names a theme this device's library doesn't hold (yet: themes sync).
    static func isMissingTheme(_ window: GlassWindowOverrides, library: TerminalThemeLibrary) -> Bool {
        guard let id = window[TerminalWindowSettings.theme].flatMap(UUID.init(uuidString:)) else { return false }
        return !library.records.contains { $0.id == id && !$0.isDeleted }
    }
}
