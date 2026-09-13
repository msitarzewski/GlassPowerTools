//
//  GlassCommandPaletteTests.swift
//  Glass Power Tools — GlassLayersTests
//
//  Moved here from `GlassTerminalTests` on 2026-09-12 with the palette itself: the behaviour is
//  `GlassLayers`' now, so its test is too. Both capabilities used to carry a byte-for-byte copy of
//  the palette, each with its own `MacCommandCenterEntry` type of the same name — so a database
//  workspace's commands could never appear in the terminal's palette.
//

#if os(macOS)
import AppKit
import Testing
@testable import GlassLayers

@Suite("Command palette")
struct GlassCommandPaletteTests {
    @Test @MainActor func commandCenterSearchAndMenuSnapshotPreserveAvailability() {
        #expect(MacCommandCenterEntry.matches("beam error", title: "Errors", detail: "Open table · beam"))
        #expect(MacCommandCenterEntry.matches("cafe", title: "Café", detail: "Connection"))
        #expect(!MacCommandCenterEntry.matches("drop", title: "Open table", detail: "beam"))
        let menu = NSMenu(title: "Test")
        menu.autoenablesItems = false
        let enabled = NSMenuItem(title: "Show Test", action: #selector(NSApplication.hide(_:)), keyEquivalent: "s")
        enabled.target = NSApp
        menu.addItem(enabled)
        let disabled = NSMenuItem(title: "Unavailable Test", action: nil, keyEquivalent: "")
        disabled.isEnabled = false
        menu.addItem(disabled)
        let hidden = NSMenuItem(title: "Hidden Test", action: #selector(NSApplication.hide(_:)), keyEquivalent: "")
        hidden.isHidden = true
        menu.addItem(hidden)
        menu.addItem(.separator())
        let entries = MacCommandCenter.shared.menuEntries(menu, path: ["Test"], depth: 0)
        #expect(entries.map(\.title) == ["Test: Show Test", "Test: Unavailable Test"])
        #expect(MacCommandCenterEntry.matches("splrt", title: "Terminal: Split Right", detail: ""))
        #expect(entries[0].isEnabled)
        #expect(!entries[1].isEnabled)
        #expect(entries[1].detail.contains("Unavailable in this window"))
        #expect(MacCommandCenter.shared.menuEntries(menu, path: [], depth: 6).isEmpty)
    }
}
#endif
