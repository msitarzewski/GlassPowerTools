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
            Button("Command Palette (Alternate)…") { present() }
                .keyboardShortcut("k", modifiers: .command)
        }
    }

    private func present() {
        GlassCommandPaletteSources.present(windowEntries: windowEntries ?? [], openWindow: openWindow)
    }
}
#endif
