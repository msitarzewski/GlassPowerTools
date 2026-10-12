//
//  GlassTerminalLibraryEntries.swift
//  Glass Power Tools — GlassTerminal
//
//  The terminal's entries into the shell's library: toolbar items (Workgroups, Tailscale, a Mac
//  local terminal) and the per-service actions glas.sh offered on a saved server (Edit, Details,
//  SFTP, Delete). The shell places these through its capability hooks; until those exist the
//  same actions are reachable from the Library menu and the terminal's own windows.
//

import SwiftUI
import GlassConnectionKit
import GlassShell
import GlassLayers

/// Toolbar entries for the shell's library toolbar.
public struct GlassTerminalLibraryToolbar: View {
    private let runtime: GlassTerminalRuntime
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    public init(runtime: GlassTerminalRuntime) { self.runtime = runtime }

    public var body: some View {
        // Workgroups is not here any more: it is a panel in the library's own sidebar, beside
        // Collections, which is where glas.sh had it and where it belongs — it spans the fleet
        // rather than acting on the selected host. A toolbar button opening a second route to the
        // same surface was the leftover from when it lived in a window of its own.
        if runtime.tailscaleIsConfigured {
            Button {
                runtime.requestShowTailscale()
            } label: {
                Label("Tailscale", systemImage: "network")
            }
            .help("Tailscale devices")
            .accessibilityIdentifier("connection-library-tailscale")
        }
        #if os(macOS)
        Button {
            runtime.requestLocalTerminal()
        } label: {
            Label("Local Terminal", systemImage: "apple.terminal")
        }
        .help("Local Terminal")
        .accessibilityIdentifier("connection-library-local-terminal-toolbar")
        // The owner's "system tool in the connections window" (W9): every terminal window and its
        // tabs at once. Its key is Window ▸ Show All Terminals', not this button's (rule 39).
        Button {
            MacTerminalExpose.shared.toggle(.init(runtime: runtime, openWindow: openWindow))
        } label: {
            Label("Show All Terminals", systemImage: "rectangle.3.group")
        }
        .help("Show All Terminals")
        .disabled(!MacTerminalExpose.shared.isAvailable)
        .accessibilityIdentifier("connection-library-show-all-terminals")
        #endif
    }
}

/// Per-service actions for an SSH service in the shell's host detail, beside the shell's own
/// Connect and Edit: SFTP and the server's details. Removal is the shell's ("Remove Service"),
/// which asks the capability to delete the saved server.
public struct GlassTerminalServiceActions: View {
    private let runtime: GlassTerminalRuntime
    private let service: HostServiceLink
    private let host: HostProfile

    public init(runtime: GlassTerminalRuntime, service: HostServiceLink, host: HostProfile) {
        self.runtime = runtime
        self.service = service
        self.host = host
    }

    public var body: some View {
        // Files (SFTP) is its own peer row in the host detail, not an action on the terminal, and
        // the server's own facts are already on the host detail — glas.sh's "Details" sheet was a
        // holdover from the separate app and showed nothing the pane does not.
        EmptyView()
    }
}

#if os(macOS)
/// glas.sh's command palette entries for the library window (moved from ConnectionManagerView).
/// "Show saved connection" is gone: selection belongs to the shell's library now.
@MainActor
enum GlassTerminalCommandCenter {
    static func entries(runtime: GlassTerminalRuntime) -> [MacCommandCenterEntry] {
        var entries = [MacCommandCenterEntry(id: "connection.new", title: "New Connection",
                                            detail: "Connections") { runtime.requestAddServer() },
                       MacCommandCenterEntry(id: "terminal.local", title: "Open Local Terminal",
                                            detail: "Terminal") { runtime.requestLocalTerminal() },
                       MacCommandCenterEntry(id: "terminal.local.plain", title: "Open Basic Local Terminal",
                                            detail: "Terminal without tmux", shortcut: "⌃⌘T") {
                           runtime.requestLocalTerminal(withoutTmux: true)
                       },
                       MacCommandCenterEntry(id: "library.workgroups", title: "Workgroups",
                                            detail: "Library") { runtime.requestShowWorkgroups() }]
        if runtime.tailscaleIsConfigured {
            entries.append(MacCommandCenterEntry(id: "library.tailscale", title: "Tailscale Devices",
                                                 detail: "Library") { runtime.requestShowTailscale() })
        }
        // By machine: "Connect to alpha", not "Connect to Terminal on alpha" (2026-10-12).
        let titled = GlassTerminalRuntime.distinguished(runtime.sessionManager.serverManager.servers.map { ($0, runtime.machineTitle(of: $0)) })
        for (server, machine) in titled {
            entries.append(MacCommandCenterEntry(id: "connection.connect.\(server.id)",
                title: "Connect to \(machine)", detail: "Open SSH terminal") {
                runtime.requestConnect(serverID: server.id)
            })
            if server.keepsSessionsInTmux {
                entries.append(MacCommandCenterEntry(id: "connection.plain.\(server.id)",
                    title: "Connect to \(machine) without tmux", detail: "Open a basic SSH terminal") {
                    runtime.requestConnect(serverID: server.id, withoutTmux: true)
                })
            }
            entries.append(MacCommandCenterEntry(id: "connection.sftp.\(server.id)",
                title: "Open SFTP · \(machine)", detail: "Files") {
                runtime.requestConnect(serverID: server.id, purpose: .sftp)
            })
        }
        entries += runtime.settingsManager.layoutPresets.map { preset in
            MacCommandCenterEntry(id: "workgroup.\(preset.id)", title: "Open \(preset.name)",
                                  detail: "Workgroups") { runtime.requestOpenWorkgroup(preset.id) }
        }
        return entries
    }
}
#endif

/// Menu entries for the two surfaces. macOS gets a Library menu; visionOS shares the same
/// commands for hardware keyboards.
///
/// Workgroups opens the Connections window on its Workgroups panel, directly rather than through
/// the request queue: the queue is drained inside a Connections window, and these items must work
/// when none is open.
struct TerminalLibraryCommands: Commands {
    let runtime: GlassTerminalRuntime
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Library") {
            // ⌥⌘W is Close Pane on the Mac (MacWorkspaceCommands); a shortcut has one owner.
            #if os(macOS)
            Button("Workgroups…") { runtime.showWorkgroups(openWindow: openWindow) }
            #else
            Button("Workgroups…") { runtime.showWorkgroups(openWindow: openWindow) }
                .keyboardShortcut("w", modifiers: [.command, .option])
            #endif
            Button("Tailscale Devices…") { runtime.requestShowTailscale() }
                .disabled(!runtime.tailscaleIsConfigured)
        }
        #if os(macOS)
        // Window ▸ Workgroups, beside Tailscale where the Workgroups window used to list itself;
        // the owner opens Workgroups from here (2026-10-08).
        CommandGroup(after: .singleWindowList) {
            Button("Workgroups") { runtime.showWorkgroups(openWindow: openWindow) }
            // ⇧⌘\ is Safari's Show All Tabs; here, every terminal window and its tabs (W9). This
            // item is its one owner, and it works from any window, Connections included.
            Button("Show All Terminals") {
                MacTerminalExpose.shared.toggle(.init(runtime: runtime, openWindow: openWindow))
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])
            // Never disabled: a Commands body was not seen to follow an observed value (W9), so a
            // disabled item could stay grey with windows open. With none open it says so, and
            // still lists the tmux sessions no tab shows.
        }
        #endif
    }
}
