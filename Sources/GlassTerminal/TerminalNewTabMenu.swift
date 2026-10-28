//
//  TerminalNewTabMenu.swift
//  Glass Power Tools — GlassTerminal
//
//  The + of a terminal window on iPhone, iPad and Vision Pro (the owner, 2026-10-15: "the plus in
//  the toolbar should allow a pinch and hold > servers > terminals list to open in the current
//  window"). A pinch opens the saved-host picker, as it always has; a pinch held lists the saved
//  servers, each with New Terminal and the terminals running there, as Active last listed them —
//  and the one chosen opens as a tab of this window. The Mac's "+" has its own menu (New Terminal on).
//

import SwiftUI
import GlassShell
import GlassConnectionKit

/// A saved server in the + menu: what it's called, and its terminals running on the machine.
struct TerminalNewTabMenuEntry: Identifiable {
    let server: ServerConfiguration
    let title: String
    /// Its tmux sessions no window here shows, in Active's order.
    let running: [GlassRunningSession]
    var id: UUID { server.id }

    /// Every saved server by the name a menu gives it (`machineTitle`, two on one machine told
    /// apart), in name order, each with its running terminals. Pure, so tested without a screen.
    static func entries(servers: [ServerConfiguration], title: (ServerConfiguration) -> String,
                        running: [GlassRunningSession]) -> [TerminalNewTabMenuEntry] {
        GlassTerminalRuntime.distinguished(servers.map { ($0, title($0)) })
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { server, title in
                TerminalNewTabMenuEntry(server: server, title: title, running: running.filter {
                    guard let attachment = $0.attachment, !$0.isOpenHere else { return false }
                    return attachment.kind == .ssh && attachment.endpointID.rawValue == server.id
                        && TerminalTmux.isValidSessionName(attachment.name)
                })
            }
    }

    /// This Mac's own running terminals (D47), none a tab here shows, for the Mac's "+".
    static func runningOnThisMac(_ running: [GlassRunningSession]) -> [GlassRunningSession] {
        running.filter {
            guard let attachment = $0.attachment, !$0.isOpenHere else { return false }
            return attachment.kind == .ssh && attachment.endpointID == GlassTerminalCapability.localShellEndpointID
                && TerminalTmux.isValidSessionName(attachment.name)
        }
    }
}

#if !os(macOS)
/// The + as a menu whose pinch is the picker.
struct TerminalNewTabMenu<Label: View>: View {
    /// The saved-host picker: what a pinch has always done.
    let pickServer: @MainActor () -> Void
    /// Opens a terminal on the server in this window: a new one, or attached to a running tmux session.
    let open: @MainActor (ServerConfiguration, TerminalTmuxAttachment?) -> Void
    @ViewBuilder let label: () -> Label
    @Environment(GlassTerminalRuntime.self) private var runtime: GlassTerminalRuntime?

    var body: some View {
        Menu {
            TerminalNewTabMenuItems(open: open)
        } label: {
            label()
        } primaryAction: {
            pickServer()
        }
        // The terminals listed are Active's; asked again when that list is old.
        .task { await runtime?.refreshRunningSessionsIfDue?() }
    }
}

/// What the + lists when held: each saved server with New Terminal and the terminals running there.
/// A Vision Pro tab sidebar's empty space lists them too (`VisionTerminalWorkgroupView`).
struct TerminalNewTabMenuItems: View {
    /// Opens a terminal on the server in this window: a new one, or attached to a running tmux session.
    let open: @MainActor (ServerConfiguration, TerminalTmuxAttachment?) -> Void
    @Environment(SessionManager.self) private var sessionManager
    @Environment(GlassTerminalRuntime.self) private var runtime: GlassTerminalRuntime?

    private var entries: [TerminalNewTabMenuEntry] {
        TerminalNewTabMenuEntry.entries(
            servers: sessionManager.serverManager.servers,
            title: { server in
                runtime?.machineTitle(of: server)
                    ?? GlassTerminalRuntime.machineTitle(serverName: server.name, hostName: nil)
            },
            running: runtime?.runningSessions?() ?? [])
    }

    var body: some View {
        ForEach(entries) { entry in
            Menu(entry.title) {
                Button("New Terminal", systemImage: "plus") { open(entry.server, nil) }
                if !entry.running.isEmpty {
                    Section("Running") {
                        ForEach(entry.running) { running in
                            Button {
                                if let name = running.attachment?.name {
                                    open(entry.server, TerminalTmuxAttachment(name: name))
                                }
                            } label: {
                                Text(running.title)
                                if let subtitle = running.subtitle { Text(subtitle) }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
