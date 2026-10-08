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
//  rather than putting a prompt in front of someone who only opened Active.
//

import Foundation
import os
import GlassConnectionKit
import GlassShell

extension GlassTerminalCapability {
    public func runningSessions() async -> [GlassRunningSession] {
        #if os(macOS)
        let local = await localTmuxSessions()
        #else
        let local: [GlassRunningSession] = []
        #endif
        let manager = runtime.sessionManager
        let servers = manager.serverManager.servers.filter(\.keepsSessionsInTmux)
        guard !servers.isEmpty else { return local }
        // Every host asked at once; each task is on the main actor and waits on the network.
        let asks = servers.map { server in (server.id, Task { await self.tmuxSessions(on: server) }) }
        var listings: [UUID: [TerminalTmux.Session]] = [:]
        for (id, ask) in asks { listings[id] = await ask.value }
        return local + servers.flatMap { server -> [GlassRunningSession] in
            // Shown here already: a live terminal on this device attached to it.
            let shownHere = Set(manager.sessions.compactMap { session -> String? in
                guard session.server.id == server.id, session.purpose == .terminal,
                      session.state != .disconnected else { return nil }
                return session.tmuxSessionName
            })
            return (listings[server.id] ?? [])
                .filter { !shownHere.contains($0.name) }
                .sorted { (TerminalTmux.glassNumber($0.name) ?? .max, $0.name) < (TerminalTmux.glassNumber($1.name) ?? .max, $1.name) }
                .map { runningSession($0, on: server) }
        }
    }

    #if os(macOS)
    /// D47: this Mac's own tmux sessions, under This Mac — the local tabs someone closed, and
    /// sessions started anywhere else. Those a tab here shows are left out, as for a host.
    private func localTmuxSessions() async -> [GlassRunningSession] {
        let server = MacLocalTmux.server
        guard let tmux = server.executablePath() else { return [] }
        let output = await Task.detached(priority: .userInitiated) { server.listSessions(tmux) }.value
        let runtime = self.runtime
        return MacLocalTmux.listable(MacLocalTmux.sessions(from: output)).map { session in
            GlassRunningSession(
                id: "terminal-tmux:local:\(session.name)",
                title: session.isGlass ? "Terminal \(TerminalTmux.glassNumber(session.name) ?? 0)" : session.name,
                subtitle: Self.runningDetails(session),
                symbolName: "terminal",
                endpointID: Self.localShellEndpointID,
                isAttachedElsewhere: session.attachedClients > 0,
                open: { runtime.enqueue(.localTerminal(tmux: session.name)) },
                takeOver: {
                    Task { @MainActor in
                        await Task.detached { server.detachClients(session.name, tmux) }.value
                        runtime.enqueue(.localTerminal(tmux: session.name))
                    }
                },
                end: { await Task.detached { server.kill(session.name, tmux) }.value })
        }
    }
    #endif

    static func runningDetails(_ tmux: TerminalTmux.Session) -> String {
        var details: [String] = [tmux.attachedClients > 0 ? "Open elsewhere" : "Detached"]
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
            title: tmux.isGlass ? "Terminal \(TerminalTmux.glassNumber(tmux.name) ?? 0)" : tmux.name,
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
            })
    }

    /// The host's tmux sessions, or none when it cannot be asked without a prompt.
    private func tmuxSessions(on server: ServerConfiguration) async -> [TerminalTmux.Session] {
        do {
            let output = try await withTmuxSession(on: server) { try await $0.runTmuxCommand(TerminalTmux.listCommand) }
            if case .sessions(let sessions) = TerminalTmux.parse(output) { return sessions }
        } catch {
            Logger.ssh.notice("tmux sessions on a saved server not listed: \(error.localizedDescription, privacy: .public)")
        }
        return []
    }

    /// Runs `body` over a terminal already connected to `server`, or a probe opened for it.
    private func withTmuxSession<T>(on server: ServerConfiguration,
                                    _ body: (TerminalSession) async throws -> T) async throws -> T {
        let manager = runtime.sessionManager
        if let live = manager.sessions.first(where: { $0.server.id == server.id && $0.purpose == .terminal && $0.state == .connected }) {
            return try await body(live)
        }
        let probe = try await manager.createAuthorizedSession(for: server, settingsManager: runtime.settingsManager,
                                                              purpose: .probe).session
        defer { manager.closeSession(probe) }
        guard probe.state == .connected else { throw SSHError.notConnected }
        return try await body(probe)
    }
}
