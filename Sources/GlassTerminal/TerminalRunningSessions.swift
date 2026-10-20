//
//  TerminalRunningSessions.swift
//  Glass Power Tools — GlassTerminal
//
//  D44: what Active lists under a machine as running there — the tmux sessions on servers with
//  Keep Sessions Running with tmux on, less the ones this device is already showing.
//
//  A host is asked over a terminal already connected to it when there is one, and otherwise over
//  a short `probe` connection: no shell, no window, never listed. A probe never asks for anything
//  — a server whose password is not saved, or whose host key is not trusted yet, is skipped
//  rather than putting a prompt in front of someone who only opened Active. Active says why
//  (W6): a machine skipped in silence looked like one with nothing running.
//
//  W6 (2026-10-08): a session is named as the tab showing it is (`TerminalSessionNaming`), and
//  this Mac's own sessions are listed once. The owner's Mac is also in the library as an SSH host
//  with tmux on; its fourteen running tabs were listed under that host as "Terminal 1"…"Terminal
//  14", "Open elsewhere", and This Mac listed nothing because a tab here showed each one.
//
//  W11 (2026-10-09): a session's line says the repository and branch it is in — for this Mac's
//  own sessions read from the folder, for a host's from what the tab showing it kept there.
//

import Foundation
import os
import GlassConnectionKit
import GlassShell

/// What asking one host for its tmux sessions came to.
enum TerminalHostListing: Equatable {
    case sessions([TerminalTmux.Session])
    /// Not listed, and why, in plain words.
    case skipped(String)
}

/// Why a host's sessions were not listed, in words for Active (W6). The raw error goes to the log.
enum TerminalListingSkip: LocalizedError, Equatable {
    case needsPassword
    case locked
    case keyUnavailable
    case identityUnconfirmed
    case connectionFailed
    case unreadable
    case noTmux

    /// What happened, and what to do about it.
    var explanation: String {
        switch self {
        case .needsPassword: "Signing in would need your password."
        case .locked: "Its saved password can't be read until this device is unlocked."
        case .keyUnavailable: "Its SSH key isn't on this device."
        case .identityUnconfirmed: "Connect once to confirm it's the right machine."
        case .connectionFailed: "The connection failed. Connect to it to see why."
        case .unreadable: "Its tmux sessions couldn't be read."
        case .noTmux: "tmux isn't installed there, so nothing keeps running."
        }
    }

    /// The line under the machine in Active.
    var reason: String {
        switch self {
        case .unreadable, .noTmux: explanation
        default: "Not checked: " + explanation.prefix(1).lowercased() + explanation.dropFirst()
        }
    }

    /// Ending a session over a probe that could not connect says the same.
    var errorDescription: String? { explanation }

    /// What stopped a probe, as a reason someone can act on.
    static func classify(_ error: Error) -> TerminalListingSkip {
        switch error {
        case let skip as TerminalListingSkip: skip
        case SessionOpenError.missingPassword: .needsPassword
        case SessionOpenError.credentialUnavailable: .locked
        case SessionOpenError.sshKeyNotFound, SessionOpenError.invalidSSHKey, SessionOpenError.unsupportedAgent: .keyUnavailable
        default: .connectionFailed
        }
    }
}

extension GlassTerminalCapability {
    public func runningSessions() async -> [GlassRunningSession] {
        await runningReport().sessions
    }

    public func runningReport() async -> GlassRunningReport {
        #if os(macOS)
        let local = await localTmuxListing()
        #else
        let local: [TerminalTmux.Session]? = nil
        #endif
        // This Mac's own machine (D86) isn't asked over SSH: its sessions are the local ones.
        let servers = runtime.sessionManager.serverManager.servers.filter(\.keepsSessionsInTmux)
            .filter { runtime.isThisMacServer?($0.id) != true }
        // Every host asked at once; each task is on the main actor and waits on the network.
        let asks = servers.map { server in (server, Task { await self.tmuxListing(on: server) }) }
        var hosts: [(server: ServerConfiguration, listing: TerminalHostListing)] = []
        for (server, ask) in asks { hosts.append((server, await ask.value)) }
        return runningReport(local: local, hosts: hosts)
    }

    /// Active's rows from what each machine said. A host whose sessions come from this Mac's own
    /// tmux server is this Mac, in the library as an SSH host: its sessions are This Mac's, listed
    /// there once, where Open attaches without SSH and a tab here showing one is found.
    /// - Parameter local: this Mac's sessions; nil where there is no local tmux, or it did not read.
    func runningReport(local: [TerminalTmux.Session]?,
                       hosts: [(server: ServerConfiguration, listing: TerminalHostListing)]) -> GlassRunningReport {
        let manager = runtime.sessionManager
        let thisMac = Set((local ?? []).compactMap(\.server))
        var report = GlassRunningReport()
        // Sessions an SSH terminal here shows on a host that is this Mac: an open row already.
        var shownOverSSH: Set<String> = []
        for (server, listing) in hosts {
            let sessions: [TerminalTmux.Session]
            switch listing {
            case .skipped(let reason):
                report.unchecked.append(GlassUncheckedMachine(endpointID: EndpointID(rawValue: server.id), reason: reason))
                continue
            case .sessions(let listed):
                sessions = listed
            }
            // Shown here already: a live terminal on this device attached to it.
            let shownHere = Set(manager.sessions.compactMap { session -> String? in
                guard session.server.id == server.id, session.purpose == .terminal,
                      session.state != .disconnected else { return nil }
                return session.tmuxSessionName
            })
            if let theirs = sessions.first?.server, thisMac.contains(theirs) {
                shownOverSSH.formUnion(shownHere)
                continue
            }
            // Known to be this Mac (D86), whatever tmux server answered: its sessions are the local ones.
            if runtime.isThisMacServer?(server.id) == true {
                shownOverSSH.formUnion(shownHere)
                continue
            }
            report.sessions += sessions.filter { !shownHere.contains($0.name) }
                .sorted(by: Self.listingOrder)
                .map { runningSession($0, on: server) }
        }
        #if os(macOS)
        let localRows = MacLocalTmux.listable(local ?? [])
            .filter { MacLocalTmux.shownCount($0.name) > 0 || !shownOverSSH.contains($0.name) }
            .map(localRunningSession)
        report.sessions = localRows + report.sessions
        #else
        _ = shownOverSSH  // No local sessions here: nothing for it to leave out.
        #endif
        return report
    }

    /// Glass's own first, by number, then the others by name.
    nonisolated static func listingOrder(_ a: TerminalTmux.Session, _ b: TerminalTmux.Session) -> Bool {
        (TerminalTmux.glassNumber(a.name) ?? .max, a.name) < (TerminalTmux.glassNumber(b.name) ?? .max, b.name)
    }

    #if os(macOS)
    /// D47: this Mac's own tmux sessions, or nil when it has no tmux or its answer did not read.
    /// Each with the repository its folder is in, read here (W11).
    private func localTmuxListing() async -> [TerminalTmux.Session]? {
        let server = MacLocalTmux.server
        guard let tmux = server.executablePath() else { return nil }
        let output = await Task.detached(priority: .userInitiated) { server.listSessions(tmux) }.value
        guard let output, case .sessions(let sessions) = TerminalTmux.parse(output) else { return nil }
        let home = NSHomeDirectory()
        return await Task.detached(priority: .userInitiated) {
            MacLocalTmux.readingRepositories(sessions, home: home, read: server.readRepository)
        }.value
    }

    /// Goes to the tab showing a local session. Tests put a stand-in here.
    static var revealLocalTmuxSession: @MainActor (String) -> Bool = {
        MacWorkspacePreviewRegistry.shared.reveal(localTmuxSession: $0)
    }

    /// One of this Mac's sessions, under This Mac: the local tabs someone closed, sessions started
    /// anywhere else, and those a tab here shows, which Open brings forward (W6).
    private func localRunningSession(_ listed: TerminalTmux.Session) -> GlassRunningSession {
        var session = listed
        // Named as the tabs name it, from this Mac's own home.
        session.home = NSHomeDirectory()
        let server = MacLocalTmux.server
        let runtime = self.runtime
        let shown = MacLocalTmux.shownCount(session.name)
        let name = session.name
        return GlassRunningSession(
            id: "terminal-tmux:local:\(name)",
            title: session.displayName,
            subtitle: Self.runningDetails(session, shownHere: shown),
            symbolName: "terminal",
            endpointID: Self.localShellEndpointID,
            isAttachedElsewhere: session.attachedClients > shown,
            isOpenHere: shown > 0,
            open: {
                if shown > 0 {
                    // A second client would mirror the tab showing it.
                    if !Self.revealLocalTmuxSession(name) {
                        Logger.ssh.notice("No window here shows tmux session \(name, privacy: .public)")
                    }
                } else {
                    runtime.enqueue(.localTerminal(tmux: name))
                }
            },
            takeOver: {
                guard let tmux = server.executablePath() else { return }
                Task { @MainActor in
                    await Task.detached { server.detachClients(name, tmux) }.value
                    runtime.enqueue(.localTerminal(tmux: name))
                }
            },
            end: {
                guard let tmux = server.executablePath() else { return }
                await Task.detached { server.kill(name, tmux) }.value
            },
            attachment: Self.attachment(serverID: nil, name: name))
    }
    #endif

    /// A running session's second line: where it is — `repo · branch` in a repository (W11), else
    /// its folder — unless its name already says it, then whether it is open here, elsewhere or
    /// nowhere, its windows, and when it was last used.
    static func runningDetails(_ tmux: TerminalTmux.Session, shownHere: Int = 0) -> String {
        var details: [String] = []
        if let location = TerminalSessionNaming.location(directory: tmux.directory, home: tmux.home,
                                                         repository: tmux.repository),
           location != tmux.displayName {
            details.append(location)
        }
        if shownHere > 0 {
            details.append(tmux.attachedClients > shownHere ? "Open here and elsewhere" : "Open here")
        } else {
            details.append(tmux.attachedClients > 0 ? "Open elsewhere" : "Detached")
        }
        if tmux.windows > 1 { details.append("\(tmux.windows) windows") }
        if let activity = tmux.lastActivity {
            details.append("used " + activity.formatted(.relative(presentation: .named)))
        }
        return details.joined(separator: " · ")
    }

    private func runningSession(_ tmux: TerminalTmux.Session, on server: ServerConfiguration) -> GlassRunningSession {
        let runtime = self.runtime
        return GlassRunningSession(
            id: "terminal-tmux:\(server.id.uuidString):\(tmux.name)",
            title: tmux.displayName,
            subtitle: Self.runningDetails(tmux),
            symbolName: "terminal",
            endpointID: EndpointID(rawValue: server.id),
            isAttachedElsewhere: tmux.attachedClients > 0,
            open: { runtime.enqueue(.connect(serverID: server.id, purpose: .terminal, report: nil,
                                             tmux: TerminalTmuxAttachment(name: tmux.name))) },
            takeOver: { runtime.enqueue(.connect(serverID: server.id, purpose: .terminal, report: nil,
                                                 tmux: TerminalTmuxAttachment(name: tmux.name, takeOver: true))) },
            end: { [weak self] in
                guard let self else { return }
                try await self.withTmuxSession(on: server) { _ = try await $0.runTmuxCommand(TerminalTmux.killCommand(name: tmux.name)) }
            },
            attachment: Self.attachment(serverID: server.id, name: tmux.name))
    }

    /// The host's tmux sessions, or why they were not listed: it could not be asked without a
    /// prompt, or its answer did not read.
    private func tmuxListing(on server: ServerConfiguration) async -> TerminalHostListing {
        do {
            let output = try await withTmuxSession(on: server) { try await $0.runTmuxCommand(TerminalTmux.listCommand) }
            switch TerminalTmux.parse(output) {
            case .sessions(let sessions): return .sessions(sessions)
            case .failed:
                Logger.ssh.notice("tmux sessions on a saved server could not be read")
                return .skipped(TerminalListingSkip.unreadable.reason)
            case .unavailable:
                return .skipped(TerminalListingSkip.noTmux.reason)
            }
        } catch {
            Logger.ssh.notice("tmux sessions on a saved server not listed: \(error.localizedDescription, privacy: .public)")
            return .skipped(TerminalListingSkip.classify(error).reason)
        }
    }

    /// Runs `body` over a terminal already connected to `server`, or a probe opened for it. A probe
    /// that did not connect throws why: a host key to confirm, or the connection failing.
    private func withTmuxSession<T>(on server: ServerConfiguration,
                                    _ body: (TerminalSession) async throws -> T) async throws -> T {
        let manager = runtime.sessionManager
        if let live = manager.sessions.first(where: { $0.server.id == server.id && $0.purpose == .terminal && $0.state == .connected }) {
            return try await body(live)
        }
        let probe = try await manager.createAuthorizedSession(for: server, settingsManager: runtime.settingsManager,
                                                              purpose: .probe).session
        defer { manager.closeSession(probe) }
        guard probe.state == .connected else {
            throw probe.pendingHostKeyChallenge != nil ? TerminalListingSkip.identityUnconfirmed : TerminalListingSkip.connectionFailed
        }
        return try await body(probe)
    }
}

#if DEBUG
extension GlassTerminalCapability {
    /// Screenshots only (`--demo-open active`): tmux sessions on the machine whose Terminal service
    /// is `endpointID`, as Active lists them — named and described as a real listing is — with
    /// nothing behind them: opening, taking over or ending one does nothing.
    public static func demoRunningSessions(
        on endpointID: EndpointID,
        _ sessions: [(name: String, given: String?, folder: String, repository: String?, branch: String?,
                      attached: Int, minutesAgo: Int)]
    ) -> [GlassRunningSession] {
        sessions.map { demo in
            let home = "/home/ann"
            let tmux = TerminalTmux.Session(
                name: demo.name, attachedClients: demo.attached, windows: 1,
                lastActivity: Date().addingTimeInterval(-Double(demo.minutesAgo) * 60),
                givenName: demo.given, directory: home + "/" + demo.folder, home: home,
                repository: demo.repository.map { TerminalRepository(name: $0, branch: demo.branch, root: home + "/" + $0) })
            return GlassRunningSession(
                id: "terminal-tmux:\(endpointID.rawValue.uuidString):\(demo.name)",
                title: tmux.displayName, subtitle: runningDetails(tmux), symbolName: "terminal",
                endpointID: endpointID, isAttachedElsewhere: demo.attached > 0,
                open: {}, takeOver: {}, end: {},
                attachment: attachment(serverID: endpointID.rawValue, name: demo.name))
        }
    }
}
#endif
