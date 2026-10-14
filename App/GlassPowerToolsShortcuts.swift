//
//  GlassPowerToolsShortcuts.swift
//  Glass Power Tools
//
//  What Siri, Spotlight, the Shortcuts app and the iPhone's Action button offer without anyone
//  building a shortcut (D72, 2026-10-13): open a machine's terminal, database or desktop, a
//  workgroup, Active; on the Mac, a new terminal. The phrases name machines and workgroups by the
//  names in the library, which the app tells the system again whenever they change
//  (`GlassWidgetBridge.write`). Defined in the app, as App Shortcuts must be; the intents
//  themselves are the package's (`GlassWidgetData`).
//

import AppIntents
import GlassWidgetData

struct GlassPowerToolsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GlassOpenTerminalIntent(),
            phrases: [
                "Open a terminal on \(\.$machine) in \(.applicationName)",
                "Open a \(.applicationName) terminal on \(\.$machine)",
                "Connect to \(\.$machine) in \(.applicationName)",
            ],
            shortTitle: "Open Terminal",
            systemImageName: "apple.terminal")
        AppShortcut(
            intent: GlassOpenServiceIntent(),
            phrases: [
                "Open \(\.$service) in \(.applicationName)",
            ],
            shortTitle: "Open Service",
            systemImageName: "cylinder.split.1x2")
        AppShortcut(
            intent: GlassOpenDesktopIntent(),
            phrases: [
                "Open the desktop of \(\.$machine) in \(.applicationName)",
                "Show the desktop of \(\.$machine) in \(.applicationName)",
            ],
            shortTitle: "Open Desktop",
            systemImageName: "display")
        AppShortcut(
            intent: GlassOpenWorkgroupIntent(),
            phrases: [
                "Open the \(\.$target) workgroup in \(.applicationName)",
                "Open workgroup \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Workgroup",
            systemImageName: "rectangle.3.group")
        // Opened in a new SQL tab, never run.
        AppShortcut(
            intent: GlassOpenSavedQueryIntent(),
            phrases: [
                "Open the \(\.$target) query in \(.applicationName)",
                "Open saved query \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Saved Query",
            systemImageName: "doc.text.magnifyingglass")
        AppShortcut(
            intent: GlassOpenMachineIntent(),
            phrases: [
                "Show \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Show Machine",
            systemImageName: "server.rack")
        AppShortcut(
            intent: GlassShowActiveIntent(),
            phrases: [
                "Show my active connections in \(.applicationName)",
            ],
            shortTitle: "Active Connections",
            systemImageName: "bolt.fill")
        // Answered in place, without opening the app.
        AppShortcut(
            intent: GlassWhatsOpenIntent(),
            phrases: [
                "What's open in \(.applicationName)",
                "What's running in \(.applicationName)",
            ],
            shortTitle: "What's Open",
            systemImageName: "bolt.horizontal")
        #if os(macOS)
        AppShortcut(
            intent: GlassNewTerminalIntent(),
            phrases: [
                "New \(.applicationName) terminal",
                "Open a new terminal in \(.applicationName)",
            ],
            shortTitle: "New Terminal",
            systemImageName: "terminal")
        #endif
    }
}
