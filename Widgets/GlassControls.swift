//
//  GlassControls.swift
//  Glass Power Tools — Widgets
//
//  Controls (D72, 2026-10-13): Control Center and the Mac's menu bar (macOS 26), the Lock Screen and
//  the iPhone's Action button (iOS 18) — Open Terminal on a machine you choose, Show Active, and on
//  the Mac New Terminal Window. Each runs the app's own intent, carried out in the app as Siri's
//  requests are. Vision Pro has no controls.
//

#if !os(visionOS)
import AppIntents
import SwiftUI
import WidgetKit
import GlassWidgetData

/// A terminal on the machine chosen when the control was added.
struct OpenTerminalControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.glasspowertools.control.open-terminal",
                                      intent: GlassMachineControlConfiguration.self) { configuration in
            ControlWidgetButton(action: GlassOpenTerminalControlIntent(machine: configuration.machine)) {
                Label(configuration.machine?.name ?? "Choose a Machine", systemImage: "apple.terminal")
            }
        }
        .displayName("Open Terminal")
        .description("Opens a terminal on the machine you choose.")
        .promptsForUserConfiguration()
    }
}

/// What is open and running.
struct ShowActiveControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.glasspowertools.control.active") {
            ControlWidgetButton(action: GlassShowActiveIntent()) {
                Label("Active Connections", systemImage: "bolt.fill")
            }
        }
        .displayName("Active Connections")
        .description("Shows what is open and running in Glass Power Tools.")
    }
}

#if os(macOS)
/// A terminal window on this Mac.
struct NewTerminalControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.glasspowertools.control.new-terminal") {
            ControlWidgetButton(action: GlassNewTerminalIntent()) {
                Label("New Terminal", systemImage: "terminal")
            }
        }
        .displayName("New Terminal Window")
        .description("Opens a terminal window on this Mac.")
    }
}
#endif
#endif
