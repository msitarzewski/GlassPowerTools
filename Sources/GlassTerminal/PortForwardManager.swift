//
//  PortForwardManager.swift
//  Glass Power Tools — GlassTerminal (from glas.sh)
//
//  Manages port forwarding state and tunnel lifecycle per session.
//  Supports local (-L), remote (-R), and dynamic/SOCKS5 (-D) forwarding.
//
//  The listener, direct-tcpip relay and SOCKS5 server that used to live here are the shared
//  engine's now (GlassSSHTransport: SSHTunnel via `forward` / `socks5`, SSHRemoteForward via
//  `remoteForward`). This manager keeps what is the terminal's: the per-session registry, the
//  attempt generations, the process-memory-only SOCKS5 credentials and the status the UI shows.
//

import SwiftUI
import Observation
import GlassSSHTransport
import os


@MainActor
@Observable
class PortForwardManager {
    nonisolated static let maximumConcurrentSOCKS5Connections = 64
    nonisolated static let socks5HandshakeTimeout: Duration = .seconds(15)

    var forwards: [UUID: [PortForward]] = [:] // sessionID -> forwards

    /// Running attempts keyed by forward ID (remote forwards run until closed; local and
    /// dynamic attempts finish once the tunnel is bound).
    private var runningTunnels: [UUID: Task<Void, Never>] = [:]

    /// Identifies the current tunnel attempt for each persisted forward.
    /// A stopped attempt must not update a later restart that reuses the same ID.
    private var forwardRunIDs: [UUID: UUID] = [:]

    /// Bound engine tunnels keyed by forward ID, used for shutdown.
    private var tunnels: [UUID: SSHTunnel] = [:]

    /// RFC 1929 credentials are deliberately process-memory-only and are never
    /// encoded into `PortForward`, UserDefaults, logs, or release diagnostics.
    private var socks5CredentialsByForwardID: [UUID: SOCKS5Credentials] = [:]

    nonisolated private static let logger = Logger(subsystem: "sh.glas", category: "PortForwardManager")

    nonisolated static func socks5Credentials(username: String, password: String) -> SOCKS5Credentials? {
        SOCKS5Credentials(username: username, password: password)
    }

    // MARK: - CRUD

    func addForward(_ forward: PortForward, to sessionID: UUID) {
        // Preserve source compatibility for local/remote callers. A legacy dynamic
        // caller may create the row, but it cannot start until credentials are set.
        if forwards[sessionID] == nil {
            forwards[sessionID] = []
        }
        socks5CredentialsByForwardID.removeValue(forKey: forward.id)
        var storedForward = forward
        if forward.type == .dynamic {
            storedForward.status = .error
            storedForward.errorMessage = "SOCKS5 username and password are required for this session."
        }
        forwards[sessionID]?.append(storedForward)
    }

    @discardableResult
    func addForward(
        _ forward: PortForward,
        to sessionID: UUID,
        socks5Username: String,
        socks5Password: String
    ) -> Bool {
        guard forward.type == .dynamic,
              let credentials = Self.socks5Credentials(
                username: socks5Username,
                password: socks5Password
              ) else {
            return false
        }
        if forwards[sessionID] == nil {
            forwards[sessionID] = []
        }
        socks5CredentialsByForwardID[forward.id] = credentials
        forwards[sessionID]?.append(forward)
        return true
    }

    @discardableResult
    func configureSOCKS5Credentials(
        for forwardID: UUID,
        username: String,
        password: String
    ) -> Bool {
        guard let sessionID = forwards.first(where: { _, sessionForwards in
            sessionForwards.contains(where: {
                $0.id == forwardID && $0.type == .dynamic && !$0.isActive
            })
        })?.key, let credentials = Self.socks5Credentials(username: username, password: password) else {
            return false
        }
        socks5CredentialsByForwardID[forwardID] = credentials
        if let index = forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }) {
            forwards[sessionID]?[index].status = .inactive
            forwards[sessionID]?[index].errorMessage = nil
        }
        return true
    }

    func removeForward(_ forward: PortForward, from sessionID: UUID) {
        stopForward(forward.id)
        socks5CredentialsByForwardID.removeValue(forKey: forward.id)
        forwards[sessionID]?.removeAll { $0.id == forward.id }
    }

    func forwards(for sessionID: UUID) -> [PortForward] {
        forwards[sessionID] ?? []
    }

    func hasSOCKS5Credentials(for forwardID: UUID) -> Bool {
        socks5CredentialsByForwardID[forwardID] != nil
    }

    // MARK: - Toggle

    func toggleForward(_ forward: PortForward, in sessionID: UUID, session: TerminalSession) {
        guard let index = forwards[sessionID]?.firstIndex(where: { $0.id == forward.id }) else {
            return
        }

        if forward.isActive {
            stopForward(forward.id)
            forwards[sessionID]?[index].status = .inactive
            forwards[sessionID]?[index].errorMessage = nil
        } else {
            guard let connection = session.getSSHConnection() else {
                forwards[sessionID]?[index].status = .error
                forwards[sessionID]?[index].errorMessage = "No active SSH connection."
                return
            }
            switch forward.type {
            case .local:
                startLocalForward(forwardID: forward.id, sessionID: sessionID, connection: connection)
            case .remote:
                startRemoteForward(forwardID: forward.id, sessionID: sessionID, connection: connection)
            case .dynamic:
                guard socks5CredentialsByForwardID[forward.id] != nil else {
                    forwards[sessionID]?[index].status = .error
                    forwards[sessionID]?[index].errorMessage = "SOCKS5 username and password are required for this session."
                    return
                }
                startDynamicForward(forwardID: forward.id, sessionID: sessionID, connection: connection)
            }
        }
    }


    // MARK: - Start Local Forward

    /// Binds 127.0.0.1:<localPort> through the engine; each accepted connection is relayed over
    /// an SSH direct-tcpip channel by the tunnel itself.
    private func startLocalForward(forwardID: UUID, sessionID: UUID, connection: SSHConnection) {
        guard let index = forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }) else { return }
        let localPort = forwards[sessionID]![index].localPort
        let remoteHost = forwards[sessionID]![index].remoteHost
        let remotePort = forwards[sessionID]![index].remotePort
        forwards[sessionID]?[index].status = .starting
        forwards[sessionID]?[index].errorMessage = nil
        let runID = UUID()
        forwardRunIDs[forwardID] = runID
        let task = Task<Void, Never> { [weak self] in
            do {
                let tunnel = try await connection.forward(localPort: localPort, toHost: remoteHost, port: remotePort)
                guard let self, self.forwardRunIDs[forwardID] == runID, !Task.isCancelled else {
                    await tunnel.close()
                    return
                }
                self.tunnels[forwardID] = tunnel
                self.runningTunnels.removeValue(forKey: forwardID)
                if let idx = self.forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }) {
                    self.forwards[sessionID]?[idx].status = .active
                    Self.logger.info("Local forward active: 127.0.0.1:\(tunnel.localPort) -> \(remoteHost):\(remotePort)")
                }
            } catch is CancellationError {
            } catch {
                guard let self, self.forwardRunIDs[forwardID] == runID else { return }
                self.forwardRunIDs.removeValue(forKey: forwardID)
                self.runningTunnels.removeValue(forKey: forwardID)
                if let idx = self.forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }) {
                    self.forwards[sessionID]?[idx].status = .error
                    self.forwards[sessionID]?[idx].errorMessage = Self.userFacingBindError(error, port: localPort)
                    Self.logger.error("Local forward failed on port \(localPort): \(error)")
                }
            }
        }
        runningTunnels[forwardID] = task
    }

    // MARK: - Start Remote Forward

    /// Ask the SSH server to listen on remoteHost:remotePort and forward back
    /// through the tunnel to localHost:localPort (-R).
    private func startRemoteForward(forwardID: UUID, sessionID: UUID, connection: SSHConnection) {
        guard let index = forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }) else { return }

        let localPort = forwards[sessionID]![index].localPort
        let remoteHost = forwards[sessionID]![index].remoteHost
        let remotePort = forwards[sessionID]![index].remotePort

        forwards[sessionID]?[index].status = .starting
        forwards[sessionID]?[index].errorMessage = nil

        let runID = UUID()
        forwardRunIDs[forwardID] = runID

        let task = Task<Void, Never> { [weak self] in
            do {
                try await connection.runRemotePortForward(
                    remoteHost: remoteHost, remotePort: remotePort,
                    localHost: "127.0.0.1", localPort: localPort
                ) { [weak self] boundPort in
                    guard let self,
                          self.forwardRunIDs[forwardID] == runID,
                          self.runningTunnels[forwardID] != nil,
                          !Task.isCancelled,
                          let idx = self.forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }),
                          self.forwards[sessionID]?[idx].status == .starting else {
                        return
                    }

                    self.forwards[sessionID]?[idx].status = .active
                    Self.logger.info(
                        "Remote forward active: \(remoteHost):\(boundPort) -> 127.0.0.1:\(localPort)"
                    )
                }
                guard !Task.isCancelled else { return }

                // runRemotePortForward blocks until cancelled; reaching here means
                // the remote side closed gracefully.
                await MainActor.run {
                    guard let self,
                          self.forwardRunIDs[forwardID] == runID else { return }
                    self.forwardRunIDs.removeValue(forKey: forwardID)
                    self.runningTunnels.removeValue(forKey: forwardID)
                    if let idx = self.forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }) {
                        self.forwards[sessionID]?[idx].status = .inactive
                        self.forwards[sessionID]?[idx].errorMessage = nil
                    }
                }
            } catch is CancellationError {
                // Normal shutdown path
            } catch {
                await MainActor.run {
                    guard let self,
                          self.forwardRunIDs[forwardID] == runID else { return }
                    self.forwardRunIDs.removeValue(forKey: forwardID)
                    self.runningTunnels.removeValue(forKey: forwardID)
                    if let idx = self.forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }) {
                        self.forwards[sessionID]?[idx].status = .error
                        self.forwards[sessionID]?[idx].errorMessage = "Remote forward failed: \(error.localizedDescription)"
                        Self.logger.error("Remote forward failed \(remoteHost):\(remotePort): \(error)")
                    }
                }
            }
        }

        Self.logger.info("Remote forward starting: \(remoteHost):\(remotePort) -> 127.0.0.1:\(localPort)")

        runningTunnels[forwardID] = task
    }


    // MARK: - Start Dynamic (SOCKS5) Forward

    /// Binds a SOCKS5 proxy on 127.0.0.1:<localPort> through the engine, which authenticates
    /// each client (RFC 1929) and tunnels the requested target over SSH direct-tcpip.
    private func startDynamicForward(forwardID: UUID, sessionID: UUID, connection: SSHConnection) {
        guard let index = forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }),
              let credentials = socks5CredentialsByForwardID[forwardID] else {
            return
        }
        let localPort = forwards[sessionID]![index].localPort
        forwards[sessionID]?[index].status = .starting
        forwards[sessionID]?[index].errorMessage = nil
        let runID = UUID()
        forwardRunIDs[forwardID] = runID
        let task = Task<Void, Never> { [weak self] in
            do {
                let tunnel = try await connection.socks5(localPort: localPort, credentials: credentials)
                guard let self, self.forwardRunIDs[forwardID] == runID, !Task.isCancelled else {
                    await tunnel.close()
                    return
                }
                self.tunnels[forwardID] = tunnel
                self.runningTunnels.removeValue(forKey: forwardID)
                if let idx = self.forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }) {
                    self.forwards[sessionID]?[idx].status = .active
                    Self.logger.info("Dynamic forward active: SOCKS5 on 127.0.0.1:\(tunnel.localPort)")
                }
            } catch is CancellationError {
            } catch {
                guard let self, self.forwardRunIDs[forwardID] == runID else { return }
                self.forwardRunIDs.removeValue(forKey: forwardID)
                self.runningTunnels.removeValue(forKey: forwardID)
                if let idx = self.forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }) {
                    self.forwards[sessionID]?[idx].status = .error
                    self.forwards[sessionID]?[idx].errorMessage = Self.userFacingBindError(error, port: localPort)
                    Self.logger.error("Dynamic forward failed on port \(localPort): \(error)")
                }
            }
        }
        runningTunnels[forwardID] = task
    }

    // MARK: - Stop

    func stopForward(_ forwardID: UUID) {
        forwardRunIDs.removeValue(forKey: forwardID)
        runningTunnels[forwardID]?.cancel()
        runningTunnels.removeValue(forKey: forwardID)
        if let tunnel = tunnels.removeValue(forKey: forwardID) {
            Task { await tunnel.close() }
        }
    }

    /// Closes every forward of a session and waits, so the SSH transport can be detached with no
    /// relay still writing to it.
    func stopAllForwardsAndWait(for sessionID: UUID) async {
        let forwardIDs = forwards[sessionID]?.map(\.id) ?? []
        var tasks: [Task<Void, Never>] = []
        var closing: [SSHTunnel] = []
        for forwardID in forwardIDs {
            forwardRunIDs.removeValue(forKey: forwardID)
            if let task = runningTunnels.removeValue(forKey: forwardID) {
                task.cancel()
                tasks.append(task)
            }
            if let tunnel = tunnels.removeValue(forKey: forwardID) {
                closing.append(tunnel)
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for tunnel in closing { group.addTask { await tunnel.close() } }
            for task in tasks { group.addTask { await task.value } }
        }
        for forwardID in forwardIDs {
            if let idx = forwards[sessionID]?.firstIndex(where: { $0.id == forwardID }) {
                forwards[sessionID]?[idx].status = .inactive
                forwards[sessionID]?[idx].errorMessage = nil
            }
        }
    }

    func purgeAllForwards(for sessionID: UUID) {
        let forwardIDs = forwards[sessionID]?.map(\.id) ?? []
        for forwardID in forwardIDs {
            stopForward(forwardID)
            socks5CredentialsByForwardID.removeValue(forKey: forwardID)
        }
        forwards.removeValue(forKey: sessionID)
    }

    // MARK: - Error Formatting

    private static func userFacingBindError(_ error: Error, port: Int) -> String {
        let description = "\(error)"
        if description.contains("address_already_in_use") || description.contains("EADDRINUSE") || description.contains("Address already in use") {
            return "Port \(port) is already in use."
        }
        if description.contains("permission_denied") || description.contains("EACCES") {
            return "Permission denied binding port \(port). Ports below 1024 require elevated privileges."
        }
        return "Failed to bind port \(port): \(error.localizedDescription)"
    }
}
