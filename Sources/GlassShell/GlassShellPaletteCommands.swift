//
//  GlassShellPaletteCommands.swift
//  Glass Power Tools — GlassShell
//
//  Command Palette…, once, owned by the shell like File ▸ New and Edit ▸ Find. The terminal and the
//  database each declared it on ⇧⌘P and ⌘K, each with only its own connections, so the app menu
//  listed it twice and which palette a key opened was SwiftUI's choice (the owner, 2026-10-13:
//  "This menu needs attention"). Each capability's entries come from `GlassCommandPaletteSources`;
//  the focused window adds its own commands through `macCommandCenterEntries`.
//
//  **One item, on ⇧⌘P** (2026-10-18). The one palette kept both keys, and a SwiftUI menu item holds
//  one, so the app menu still listed it twice, the second as "(Alternate)" — "Why are there two
//  command palettes?" The owner chose ⇧⌘P, as Xcode and VS Code have it. ⌘K is left to no one:
//  Terminal and iTerm clear the screen with it, and a terminal's user expects that.
//

#if os(macOS)
import SwiftUI
import GlassLayers

public struct GlassShellPaletteCommands: Commands {
    @FocusedValue(\.macCommandCenterEntries) private var windowEntries
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Command Palette…") { present() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }

    private func present() {
        GlassCommandPaletteSources.present(windowEntries: windowEntries ?? [], openWindow: openWindow)
    }
}
#endif
