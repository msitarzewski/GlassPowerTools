//
//  TerminalLayoutSnapshot.swift
//  Glass Power Tools — GlassTerminal
//
//  The terminal windows this device has open, for the shared layout (`GlassLayoutSnapshot`, phase 1, 2026-11-22).
//  On iPhone, iPad and Vision Pro a window or set is a workgroup, each terminal a tab; on a Mac each window's tabs,
//  a tab split into panes giving one tab per pane in a split group. Nil until the last run's windows are back: a
//  snapshot taken before would read them as closed.
//

import Foundation
import GlassShell
import GlassConnectionKit

extension GlassTerminalCapability {
    public func layoutSnapshot() -> GlassLayoutSnapshot? {
        #if os(macOS)
        MacWorkspacePreviewRegistry.shared.layoutSnapshot(servers: runtime.sessionManager.serverManager.servers,
                                                          thisMac: runtime.thisMacServerID?())
        #else
        TerminalLayoutSnapshot.current(runtime.sessionManager)
        #endif
    }
}

enum TerminalLayoutSnapshot {
    /// One terminal as a tab: in tmux once it has its session, a shell here when it isn't kept in tmux, and nothing yet
    /// while it is still being given a session (it would read as a shell for a moment).
    @MainActor
    static func tab(_ session: TerminalSession, title: String, id: UUID, splitGroup: UUID? = nil) -> GlassLayoutSnapshot.Tab? {
        let endpoint = EndpointID(rawValue: session.server.id)
        if session.usesTmux {
            guard let name = session.tmuxSessionName else { return nil }
            return GlassLayoutSnapshot.Tab(id: id, title: title, endpointID: endpoint, tmuxSession: name,
                                           tmuxCreated: session.tmuxSessionCreated, isShellHere: false,
                                           splitGroup: splitGroup)
        }
        return GlassLayoutSnapshot.Tab(id: id, title: title, endpointID: endpoint, tmuxSession: nil, tmuxCreated: nil,
                                       isShellHere: true, splitGroup: splitGroup)
    }

    /// Off the Mac: every workgroup with a terminal in it, in the order they were made. Built on every platform so a
    /// test on a Mac can ask it; only iPhone, iPad and Vision Pro use it.
    @MainActor
    static func current(_ manager: SessionManager,
                        settled: Bool = TerminalWorkgroupsToReopen.shared.hasSettled) -> GlassLayoutSnapshot? {
        guard settled else { return nil }
        return GlassLayoutSnapshot(windows: manager.workgroups.compactMap { workgroup in
            let live = workgroup.sessionIDs.compactMap { manager.session(for: $0) }.filter { $0.purpose == .terminal }
            let tabs = live.compactMap { session in
                tab(session, title: TerminalSessionNaming.steady(TerminalWorkgroupOpening.label(session, on: .allWindows)),
                    id: session.layoutTabID)
            }
            guard !tabs.isEmpty else { return nil }
            return GlassLayoutSnapshot.Window(id: workgroup.id, name: GlassTerminalCapability.title(of: workgroup, live: live),
                                              tabs: tabs)
        })
    }
}

#if os(macOS)

extension MacWorkspacePreviewRegistry {
    /// The Mac's terminal windows on screen or in the dock, each with its tabs; nil until the last run's windows are
    /// back (`layoutReady`), and while the app quits — its windows closing then are not closed.
    func layoutSnapshot(servers: [ServerConfiguration], thisMac: UUID?) -> GlassLayoutSnapshot? {
        guard layoutReady, !MacWindowsToReopen.shared.isQuitting else { return nil }
        return GlassLayoutSnapshot(windows: shownWindows.compactMap { shown in
            let controller = shown.controller
            let tabs = controller.tabs.flatMap { $0.layoutTabs(servers: servers, thisMac: thisMac) }
            guard !tabs.isEmpty else { return nil }
            let name = MacTerminalExposeModel.groups(windows: [controller], servers: servers).first?.title ?? "Terminal"
            return GlassLayoutSnapshot.Window(id: controller.windowID, name: TerminalSessionNaming.steady(name), tabs: tabs)
        })
    }
}

extension MacWorkspaceController {
    /// This tab as the layout's tabs: one per pane, in a split group when it is split. A local pane in tmux is on the
    /// machine linked as this Mac (D86), which another device reaches over SSH; with none linked, or outside tmux, it
    /// is a shell only this Mac can show. An SSH pane is on its machine, in tmux or not.
    func layoutTabs(servers: [ServerConfiguration], thisMac: UUID?) -> [GlassLayoutSnapshot.Tab] {
        guard let root = state.root else { return [] }
        let paneIDs = root.paneIDs
        let split = paneIDs.count > 1 ? workspaceID : nil
        let tabTitle = TerminalSessionNaming.steady(windowIdentity(servers: servers).title)
        return paneIDs.compactMap { paneID -> GlassLayoutSnapshot.Tab? in
            guard let pane = root.pane(id: paneID) else { return nil }
            let title = split == nil ? tabTitle : TerminalSessionNaming.steady(
                MacWorkspaceTabNaming.automaticTitle(paneContextByPaneID[paneID], home: NSHomeDirectory()) ?? tabTitle)
            func shell(_ endpoint: EndpointID?) -> GlassLayoutSnapshot.Tab {
                GlassLayoutSnapshot.Tab(id: paneID, title: title, endpointID: endpoint, tmuxSession: nil, tmuxCreated: nil,
                                        isShellHere: true, splitGroup: split)
            }
            switch pane.intent.kind {
            case .local:
                guard let thisMac, let name = localTmuxSession(for: paneID) ?? pane.intent.localTmuxSession else {
                    return shell(nil)
                }
                return GlassLayoutSnapshot.Tab(id: paneID, title: title, endpointID: EndpointID(rawValue: thisMac),
                                               tmuxSession: name, tmuxCreated: pane.intent.localTmuxSessionCreated,
                                               isShellHere: false, splitGroup: split)
            case .ssh:
                if let session = sessionsByPaneID[paneID] {
                    return TerminalLayoutSnapshot.tab(session, title: title, id: paneID, splitGroup: split)
                }
                // Not started yet: as its intent says, or nothing until it has a session.
                guard let serverID = pane.intent.serverID else { return nil }
                if pane.intent.withoutTmux { return shell(EndpointID(rawValue: serverID)) }
                guard let name = pane.intent.sshTmuxSession else { return nil }
                return GlassLayoutSnapshot.Tab(id: paneID, title: title, endpointID: EndpointID(rawValue: serverID),
                                               tmuxSession: name, tmuxCreated: pane.intent.sshTmuxSessionCreated,
                                               isShellHere: false, splitGroup: split)
            }
        }
    }
}
#endif
