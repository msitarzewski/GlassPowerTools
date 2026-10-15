//
//  TerminalOpenTogether.swift
//  Glass Power Tools — GlassTerminal
//
//  W13 (owner, 2026-10-09, on the Vision Pro): "Multiselect from the 'Active' would be stellar …
//  I'd like to select multiple and open in a new window like the tab view." Running tmux sessions
//  chosen in Active — on this Mac and on saved servers, in any mix — open as one new window
//  holding them in Active's order, each terminal attached to its own session: on a Mac a window
//  with a tab apiece, as W8's Move N Tabs to New Window makes; on iPad and Vision Pro a terminal
//  workgroup window; on iPhone a workgroup whose slots connect as they are shown (W4b).
//
//  One request for all of them. Each row's own Open makes a window apiece.
//

import Foundation
import GlassConnectionKit
import GlassShell

/// One running tmux session to open with others.
struct TerminalTmuxTarget: Hashable, Sendable {
    /// The saved server it runs on; nil for this Mac's own tmux (D47).
    let serverID: UUID?
    let name: String

    init(serverID: UUID?, name: String) {
        self.serverID = serverID
        self.name = name
    }

    /// The session an Active row names, when it is a terminal's: nil for anything else, and for
    /// a name tmux would not take.
    init?(attachment: GlassRunningAttachment) {
        guard attachment.kind == .ssh, TerminalTmux.isValidSessionName(attachment.name) else { return nil }
        serverID = attachment.endpointID == GlassTerminalCapability.localShellEndpointID ? nil : attachment.endpointID.rawValue
        name = attachment.name
    }
}

extension GlassTerminalCapability {
    /// What Active's row for a tmux session attaches to when it opens with others.
    static func attachment(serverID: UUID?, name: String) -> GlassRunningAttachment {
        GlassRunningAttachment(kind: .ssh,
                               endpointID: serverID.map { EndpointID(rawValue: $0) } ?? localShellEndpointID,
                               name: name)
    }

    /// Active's "Open N in New Window": the chosen sessions, in Active's order, as one request.
    public func openRunningSessions(_ attachments: [GlassRunningAttachment]) {
        let targets = attachments.compactMap(TerminalTmuxTarget.init(attachment:))
        guard !targets.isEmpty else { return }
        runtime.enqueue(.openTmuxSessions(targets))
    }

    /// Active's Open as Tab In (the owner, 2026-10-15: "show existing tab groups. So I can open a
    /// new session into a group"): the terminal windows here with room for another tab, named
    /// as Active and Show All Windows name them.
    public func tabGroups() -> [GlassTabGroup] {
        #if os(macOS)
        Self.macTabGroups(servers: runtime.sessionManager.serverManager.servers)
        #else
        Self.workgroupTabGroups(runtime.sessionManager)
        #endif
    }

    /// iPhone, iPad and Vision Pro: each workgroup with a live terminal and room for another, in
    /// Active's order (newest first), by Active's name for it.
    static func workgroupTabGroups(_ manager: SessionManager) -> [GlassTabGroup] {
        manager.workgroups.reversed().compactMap { workgroup in
            let live = workgroup.sessionIDs.compactMap { manager.session(for: $0) }
            guard !live.isEmpty, workgroup.sessionIDs.count < LayoutPreset.maximumSessionCount else { return nil }
            return GlassTabGroup(id: workgroup.id.uuidString, title: title(of: workgroup, live: live))
        }
    }

    #if os(macOS)
    /// The Mac: each terminal window on screen with room for another tab, by the name Show All
    /// Windows gives it.
    static func macTabGroups(servers: [ServerConfiguration]) -> [GlassTabGroup] {
        MacWorkspacePreviewRegistry.shared.shownWindows.compactMap { shown in
            guard shown.controller.canAddTab,
                  let title = MacTerminalExposeModel.groups(windows: [shown.controller], servers: servers).first?.title
            else { return nil }
            return GlassTabGroup(id: shown.controller.windowID.uuidString, title: title)
        }
    }
    #endif

    /// Running sessions as more tabs of a window here, in order (Open as Tab In).
    public func openRunningSessions(_ attachments: [GlassRunningAttachment], inTabGroup group: GlassTabGroup.ID) {
        let targets = attachments.compactMap(TerminalTmuxTarget.init(attachment:))
        guard !targets.isEmpty, let windowID = UUID(uuidString: group) else { return }
        runtime.enqueue(.addTmuxSessions(targets, toWindow: windowID))
    }
}

/// Which chosen sessions open together, and as what, on each platform. Pure, so the window's
/// tabs and the workgroup's terminals are tested without a screen or a connection.
enum TerminalOpenTogether {
    /// The sessions that open, in order, and why each of the others did not, in plain words.
    struct Plan: Equatable {
        var opening: [TerminalTmuxTarget] = []
        var notOpened: [String] = []
    }

    /// Sorts the chosen sessions. A server no longer saved here has nothing to connect with. A
    /// server allowing legacy algorithms needs its own confirmation each time, which a window of
    /// several never asks — the workgroups' rule (`workgroupNeedsLegacyConsent`) — so its sessions
    /// open only alone. Where there is no local shell, this Mac's sessions can't open.
    /// - Parameter room: how many more terminals the window they join can hold (Open as Tab In);
    ///   nil for a new window.
    static func plan(_ targets: [TerminalTmuxTarget], servers: [ServerConfiguration], room: Int? = nil) -> Plan {
        var plan = Plan()
        for target in targets {
            guard let serverID = target.serverID else {
                #if os(macOS)
                plan.opening.append(target)
                #else
                plan.notOpened.append("\(target.name): local terminals are available on macOS.")
                #endif
                continue
            }
            guard let server = servers.first(where: { $0.id == serverID }) else {
                plan.notOpened.append("\(target.name) didn't open: its machine's Terminal service is no longer here.")
                continue
            }
            guard !server.legacyAlgorithmsEnabled else {
                plan.notOpened.append("\(server.name) uses legacy algorithms, so \(target.name) didn't open with the others. Open it on its own to review its security settings.")
                continue
            }
            plan.opening.append(target)
        }
        if let room {
            // A window already open: what it has room for.
            if plan.opening.count > room {
                plan.notOpened.append(room == 0
                    ? "That window is full, so \(plan.opening.count == 1 ? "it" : "they") didn't open."
                    : "That window has room for \(room) more, so the other \(plan.opening.count - room) didn't open.")
                plan.opening = Array(plan.opening.prefix(max(0, room)))
            }
            return plan
        }
        #if !os(macOS)
        // A workgroup holds as many terminals as a saved one may.
        let limit = LayoutPreset.maximumSessionCount
        if plan.opening.count > limit {
            plan.notOpened.append("A window holds \(limit) terminals, so the other \(plan.opening.count - limit) didn't open.")
            plan.opening = Array(plan.opening.prefix(limit))
        }
        #endif
        return plan
    }

    #if os(macOS)
    /// One window with a tab per session, in order: this Mac's own as Active's This Mac opens one
    /// (`localTmuxSession`), a server's as a workgroup's SSH tab does (`sshTmuxSession`, W4b) —
    /// each pane claims its session, joining it while it runs. A window holds 32 tabs; more
    /// carry on in another.
    static func macLaunchRequests(for targets: [TerminalTmuxTarget]) -> [MacWorkspaceLaunchRequest] {
        let limit = MacWorkspaceWindowRestorationState.maximumTabCount
        return stride(from: 0, to: targets.count, by: limit).map { start in
            MacWorkspaceLaunchRequest(tabs: targets[start..<min(start + limit, targets.count)].map { target in
                var intent: MacWorkspacePaneIntent
                if let serverID = target.serverID {
                    intent = .ssh(serverID: serverID)
                    intent.sshTmuxSession = target.name
                } else {
                    intent = .local
                    intent.localTmuxSession = target.name
                }
                return MacWorkspaceTabRequest(initialPaneIntent: intent)
            })
        }
    }
    #endif

    /// iPhone, iPad and Vision Pro: a workgroup made for the moment and never saved, holding a
    /// terminal per session in order, each claiming its session (W4b). Named for the machines it
    /// is on, as a terminal opened alone is named for its machine.
    static func workgroup(for targets: [TerminalTmuxTarget], servers: [ServerConfiguration]) -> LayoutPreset? {
        let intents = targets.compactMap { target in
            target.serverID.map { LayoutPreset.SessionIntent(serverID: $0, tmuxSession: target.name) }
        }
        guard !intents.isEmpty else { return nil }
        var machines: [ServerConfiguration] = []
        for serverID in intents.compactMap(\.serverID) where !machines.contains(where: { $0.id == serverID }) {
            if let server = servers.first(where: { $0.id == serverID }) { machines.append(server) }
        }
        return LayoutPreset(name: machines.map(\.name).joined(separator: ", "),
                            colorTag: machines.first?.colorTag ?? .blue,
                            sessionIntents: intents)
    }
}
