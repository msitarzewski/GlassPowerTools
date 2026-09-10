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

/// Toolbar entries for the shell's library toolbar.
public struct GlassTerminalLibraryToolbar: View {
    private let runtime: GlassTerminalRuntime

    public init(runtime: GlassTerminalRuntime) { self.runtime = runtime }

    public var body: some View {
        Button {
            runtime.requestShowWorkgroups()
        } label: {
            Label("Workgroups", systemImage: "rectangle.stack")
        }
        .help("Workgroups")
        .accessibilityIdentifier("connection-library-workgroups")
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
        #endif
    }
}

/// Per-service actions for an SSH service in the shell's host detail. A service whose endpoint
/// has no saved server yet offers only "Set Up…", which opens glas.sh's server form pre-filled
/// with the host and linked by the endpoint id.
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
        let serverID = service.endpointID.rawValue
        if runtime.hasServer(id: serverID) {
            Button("SFTP", systemImage: "folder") { runtime.requestConnect(serverID: serverID, purpose: .sftp) }
                .help("Connect and browse remote files using SFTP")
                .accessibilityIdentifier("connection-library-sftp-server-\(serverID.uuidString.lowercased())")
            Button("Edit", systemImage: "pencil") { runtime.requestEditServer(id: serverID) }
                .accessibilityIdentifier("connection-library-edit-server-\(serverID.uuidString.lowercased())")
            Button("Details", systemImage: "info.circle") { runtime.requestServerInfo(id: serverID) }
                .accessibilityIdentifier("connection-library-details-server-\(serverID.uuidString.lowercased())")
            Button("Delete", systemImage: "trash", role: .destructive) { runtime.requestDeleteServer(id: serverID) }
                .accessibilityIdentifier("connection-library-delete-server-\(serverID.uuidString.lowercased())")
        } else {
            Button("Set Up…", systemImage: "terminal") {
                runtime.setupRequest = .init(host: host, service: service)
            }
            .accessibilityIdentifier("connection-library-setup-server-\(serverID.uuidString.lowercased())")
        }
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
                       MacCommandCenterEntry(id: "library.workgroups", title: "Workgroups",
                                            detail: "Library") { runtime.requestShowWorkgroups() }]
        if runtime.tailscaleIsConfigured {
            entries.append(MacCommandCenterEntry(id: "library.tailscale", title: "Tailscale Devices",
                                                 detail: "Library") { runtime.requestShowTailscale() })
        }
        for server in runtime.sessionManager.serverManager.servers {
            entries.append(MacCommandCenterEntry(id: "connection.connect.\(server.id)",
                title: "Connect to \(server.name)", detail: "Open SSH terminal") {
                runtime.requestConnect(serverID: server.id)
            })
            entries.append(MacCommandCenterEntry(id: "connection.sftp.\(server.id)",
                title: "Open SFTP · \(server.name)", detail: "Files") {
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
struct TerminalLibraryCommands: Commands {
    let runtime: GlassTerminalRuntime

    var body: some Commands {
        CommandMenu("Library") {
            Button("Workgroups…") { runtime.requestShowWorkgroups() }
                .keyboardShortcut("w", modifiers: [.command, .option])
            Button("Tailscale Devices…") { runtime.requestShowTailscale() }
                .disabled(!runtime.tailscaleIsConfigured)
        }
    }
}
