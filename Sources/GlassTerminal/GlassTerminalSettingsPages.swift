//
//  GlassTerminalSettingsPages.swift
//  Glass Power Tools — GlassTerminal
//
//  glas.sh's settings pages, offered to the shell's one settings surface. Appearance is not
//  here: opacity, frost and material are Stage 1's GlassLayerControls; the terminal keeps only
//  its canvas-specific tint and interactive-glass options under Terminal.
//

import SwiftUI
import GlassShell

/// One settings page a capability contributes to the shell's settings surface.
public struct GlassTerminalSettingsPage: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    fileprivate let makeView: @MainActor (GlassTerminalRuntime) -> AnyView

    @MainActor public func view(runtime: GlassTerminalRuntime) -> AnyView { makeView(runtime) }
}

public enum GlassTerminalSettingsPages {
    /// In glas.sh's order: General (connections, security, Tailscale, SSH keys, iCloud), Terminal
    /// (theme, canvas, font, size, cursor), Snippets.
    public static let all: [GlassTerminalSettingsPage] = [
        GlassTerminalSettingsPage(id: "terminal.general", title: "Connections", systemImage: "network") { runtime in
            AnyView(GeneralSettingsView().environment(runtime.settingsManager).environment(runtime.sessionManager))
        },
        GlassTerminalSettingsPage(id: "terminal.terminal", title: "Terminal", systemImage: "terminal") { runtime in
            AnyView(TerminalSettingsView().environment(runtime.settingsManager).environment(runtime.sessionManager))
        },
        GlassTerminalSettingsPage(id: "terminal.snippets", title: "Snippets", systemImage: "text.badge.star") { runtime in
            AnyView(SnippetsSettingsView().environment(runtime.settingsManager).environment(runtime.sessionManager))
        },
    ]
}
